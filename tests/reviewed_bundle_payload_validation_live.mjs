#!/usr/bin/env node
// Rollback-only hosted-DB contract for the reviewed-bundle promotion path.
// It applies the validator migration only inside this transaction and never
// records migration tracking or leaves a release, payload, or audit row.

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { loadEnvConfig } = require("@next/env");
const { Client } = require("pg");

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
loadEnvConfig(root);
const dbUrl = process.env.SUPABASE_DB_URL_POOLER;
if (!dbUrl) {
  throw new Error("SUPABASE_DB_URL_POOLER is required in .env.local");
}

const season = "2024-25";
const migrationPath = path.join(
  root,
  "supabase/migrations/20260720180000_reviewed_bundle_payload_validation.sql",
);
const migrationSql = fs.readFileSync(migrationPath, "utf8");
const reviewedV3BundlePath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(root, "data/reporting/urc_dashboard_bundle_2024-25_season_bound_v3_preflight.json");
const zeroHash = "0".repeat(64);
const oneHash = "1".repeat(64);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

async function approvedSnapshot(client) {
  const result = await client.query(
    `select coalesce(jsonb_agg(jsonb_build_object(
       'release_id', context.release_id, 'release_label', release.release_label,
       'status', release.status
     ) order by release.created_at, context.release_id), '[]'::jsonb) as snapshot
     from reporting.league_release_context_v2 context
     join reporting.aggregate_releases release on release.id = context.release_id
     where context.season = $1 and release.status = 'approved'`,
    [season],
  );
  return result.rows[0].snapshot;
}

async function hashReviewedBundle(client, bundle) {
  const leagueResult = await client.query(
    `select encode(digest(convert_to($1::jsonb::text, 'UTF8'), 'sha256'), 'hex') as payload_sha256`,
    [JSON.stringify(bundle.league)],
  );
  const teamResult = await client.query(
    `select team_key, dashboard,
       encode(digest(convert_to(dashboard::text, 'UTF8'), 'sha256'), 'hex') as payload_sha256
     from jsonb_to_recordset($1::jsonb) as payload(team_key text, dashboard jsonb)
     order by team_key`,
    [JSON.stringify(bundle.teams)],
  );
  return { leagueHash: leagueResult.rows[0].payload_sha256, teamRows: teamResult.rows };
}

async function loadReviewedV3(client) {
  assert(fs.existsSync(reviewedV3BundlePath), `reviewed V3 preflight bundle not found: ${reviewedV3BundlePath}`);
  const bundle = JSON.parse(fs.readFileSync(reviewedV3BundlePath, "utf8"));
  assert(bundle.season === season && bundle.league && Array.isArray(bundle.teams) && bundle.teams.length === 16,
    "reviewed V3 preflight bundle must contain one league and 16 team dashboards");
  const hashes = await hashReviewedBundle(client, bundle);
  const members = await client.query(
    `select team_key, team_release_id::text, curated_build_id::text
     from analysis.league_member_releases_v2 where season = $1 order by team_key`,
    [season],
  );
  assert(members.rows.length === 16, "V3: expected 16 current member releases");
  const memberByTeam = new Map(members.rows.map((member) => [member.team_key, member]));
  const teams = hashes.teamRows.map((payload) => {
    const member = memberByTeam.get(payload.team_key);
    assert(member, `V3: reviewed payload has no current member identity for ${payload.team_key}`);
    return { ...payload, ...member };
  });
  const classification = await client.query(
    `select evidence_sha256 from audit.rule_adjudications
     where rule_version = $1 and adjudication_ref = 'IA-02'`,
    [variants.v3.classificationVersion],
  );
  const cohort = await client.query(
    `select evidence_sha256 from audit.reporting_cohort_rule_adjudications_v3
     where cohort_view_version = $1 and season = $2 and adjudication_ref = 'COHORT-01'`,
    [variants.v3.cohortVersion, season],
  );
  assert(classification.rows.length === 1 && cohort.rows.length === 1, "V3: accepted evidence hashes are unavailable");
  return {
    ...variants.v3,
    league: {
      dashboard: bundle.league,
      payload_sha256: hashes.leagueHash,
      classification_evidence_sha256: classification.rows[0].evidence_sha256,
      cohort_evidence_sha256: cohort.rows[0].evidence_sha256,
    },
    teams,
  };
}

async function loadApprovedV2(client) {
  const context = await client.query(
    `select context.release_id::text, league.dashboard_payload as dashboard,
       league.payload_sha256
     from reporting.league_release_context_v2 context
     join reporting.aggregate_releases release on release.id = context.release_id and release.status = 'approved'
     join reporting.league_release_payloads_v2 league on league.release_id = context.release_id
     where context.season = $1 and context.analysis_version = 'v2'
       and context.classification_view_version = 'v2' and context.cohort_view_version = 'v2'
     order by release.approved_at desc nulls last, release.created_at desc limit 1`,
    [season],
  );
  if (context.rows.length !== 1) return null;
  const teams = await client.query(
    `select payload.team_key, payload.team_release_id::text, payload.curated_build_id::text,
       payload.dashboard_payload as dashboard, payload.payload_sha256
     from reporting.team_dashboard_payloads_v2 payload
     where payload.bundle_release_id = $1::uuid order by payload.team_key`,
    [context.rows[0].release_id],
  );
  assert(teams.rows.length === 16, "V2: approved bundle lacks 16 team payloads");
  return {
    ...variants.v2,
    league: { ...context.rows[0], classification_evidence_sha256: null, cohort_evidence_sha256: null },
    teams: teams.rows,
  };
}

function teamHashObject(teams) {
  return Object.fromEntries(teams.map((team) => [team.team_key, team.payload_sha256]));
}

async function createDraft(client, candidate, { parameters, members = candidate.teams } = {}) {
  const parameterValue = parameters ?? {
    league_dashboard_payload_sha256: candidate.league.payload_sha256,
    team_dashboard_payload_sha256s: teamHashObject(candidate.teams),
  };
  const run = await client.query(
    `insert into audit.pipeline_runs
       (command, team, season, status, input_hash, output_hash, parameters,
        code_version, dependency_lock_hash, operator)
     values ('rollback-reviewed-bundle-validation', 'URC Overall', $1, 'started',
       $2, $3, $4::jsonb, 'rollback-contract', 'rollback-contract', 'Codex rollback contract')
     returning id::text`,
    [season, zeroHash, oneHash, JSON.stringify(parameterValue)],
  );
  const release = await client.query(
    `insert into reporting.aggregate_releases (release_label, status, pipeline_run_id)
     values ($1, 'draft', $2::uuid) returning id::text`,
    [`rollback-reviewed-bundle-${crypto.randomUUID()}`, run.rows[0].id],
  );
  const releaseId = release.rows[0].id;
  await client.query(
    `insert into reporting.league_release_context_v2
       (release_id, season, analysis_version, generated_at, expected_member_count,
        match_exposure_decision, decision_reviewer, decision_recorded_at,
        classification_view_version, classification_evidence_sha256,
        cohort_view_version, cohort_evidence_sha256)
     values ($1::uuid, $2, $3, ($4::jsonb ->> 'generated_at')::timestamptz, 16,
       'all_registered_season_fixtures_15_players_x_80_minutes_div_60',
       'Abdel Babiker', $5::date, $6, $7, $8, $9)`,
    [
      releaseId,
      season,
      candidate.analysisVersion,
      JSON.stringify(candidate.league.dashboard),
      candidate.decisionRecordedAt,
      candidate.classificationVersion,
      candidate.league.classification_evidence_sha256,
      candidate.cohortVersion,
      candidate.league.cohort_evidence_sha256,
    ],
  );
  await client.query(
    `insert into reporting.league_release_members_v2
       (release_id, team_key, team_release_id, curated_build_id)
     select $1::uuid, member.team_key, member.team_release_id::uuid, member.curated_build_id::uuid
     from jsonb_to_recordset($2::jsonb) as member(
       team_key text, team_release_id text, curated_build_id text
     )`,
    [releaseId, JSON.stringify(members.map(({ team_key, team_release_id, curated_build_id }) => ({
      team_key, team_release_id, curated_build_id,
    })))],
  );
  return releaseId;
}

async function insertLeaguePayload(client, releaseId, dashboard) {
  await client.query(
    `insert into reporting.league_release_payloads_v2 (release_id, dashboard_payload)
     values ($1::uuid, $2::jsonb)`,
    [releaseId, JSON.stringify(dashboard)],
  );
}

async function insertTeamPayloads(client, releaseId, teams) {
  await client.query(
    `insert into reporting.team_dashboard_payloads_v2
       (bundle_release_id, team_key, team_release_id, curated_build_id, dashboard_payload)
     select $1::uuid, payload.team_key, payload.team_release_id::uuid,
       payload.curated_build_id::uuid, payload.dashboard
     from jsonb_to_recordset($2::jsonb) as payload(
       team_key text, team_release_id text, curated_build_id text, dashboard jsonb
     )`,
    [releaseId, JSON.stringify(teams.map(({ team_key, team_release_id, curated_build_id, dashboard }) => ({
      team_key, team_release_id, curated_build_id, dashboard,
    })))],
  );
}

async function expectRejected(client, baseline, name, action, results) {
  await client.query(`savepoint ${name}`);
  let rejected = false;
  try {
    await action();
  } catch {
    rejected = true;
  }
  await client.query(`rollback to savepoint ${name}`);
  assert(rejected, `${name}: expected rejection`);
  assert(sameJson(await approvedSnapshot(client), baseline), `${name}: changed approved predecessor/current release`);
  results.push(name);
}

async function assertSeasonScopedRoster(client, candidate) {
  const result = await client.query(
    `with reviewed as (
       select team_key, team_release_id::uuid, curated_build_id::uuid
       from jsonb_to_recordset($1::jsonb) as member(
         team_key text, team_release_id text, curated_build_id text
       )
     ), live_with_extra_season as (
       select team_key, season, team_release_id, curated_build_id
       from analysis.league_member_releases_v2 where season = $2
       union all
       select team_key, '2098-99', team_release_id, curated_build_id
       from (
         select team_key, team_release_id, curated_build_id
         from analysis.league_member_releases_v2 where season = $2 limit 1
       ) extra
     ), requested_live as (
       select team_key, team_release_id, curated_build_id
       from live_with_extra_season where season = $2
     )
     select not exists (
       select 1 from reviewed member full join requested_live live
         on live.team_key = member.team_key
        and live.team_release_id = member.team_release_id
        and live.curated_build_id = member.curated_build_id
       where member.team_key is null or live.team_key is null
     ) as matches`,
    [JSON.stringify(candidate.teams), season],
  );
  assert(result.rows[0].matches, "extra-season live members affected requested-season identity comparison");
}

const variants = {
  v3: {
    name: "v3",
    analysisVersion: "v3",
    classificationVersion: "reporting_classification_2026-07-20_v1",
    cohortVersion: "season_bound_2026-07-20_v1",
    decisionRecordedAt: "2026-07-19",
  },
  v2: {
    name: "v2",
    analysisVersion: "v2",
    classificationVersion: "v2",
    cohortVersion: "v2",
    decisionRecordedAt: "2026-07-14",
  },
};

const client = new Client({ connectionString: dbUrl, connectionTimeoutMillis: 10_000 });
const results = [];
try {
  await client.connect();
  await client.query("begin");
  await client.query(migrationSql);
  const baseline = await approvedSnapshot(client);
  const v3 = await loadReviewedV3(client);
  await assertSeasonScopedRoster(client, v3);

  const validV3 = await createDraft(client, v3);
  await insertLeaguePayload(client, validV3, v3.league.dashboard);
  await insertTeamPayloads(client, validV3, v3.teams);
  assert(sameJson(await approvedSnapshot(client), baseline), "valid draft changed approved predecessor/current release");
  results.push("valid_v3");

  await expectRejected(client, baseline, "tampered_league_hash", async () => {
    const releaseId = await createDraft(client, v3, {
      parameters: { league_dashboard_payload_sha256: zeroHash, team_dashboard_payload_sha256s: teamHashObject(v3.teams) },
    });
    await insertLeaguePayload(client, releaseId, v3.league.dashboard);
  }, results);

  await expectRejected(client, baseline, "tampered_team_hash", async () => {
    const hashes = teamHashObject(v3.teams);
    hashes[v3.teams[0].team_key] = zeroHash;
    const releaseId = await createDraft(client, v3, {
      parameters: { league_dashboard_payload_sha256: v3.league.payload_sha256, team_dashboard_payload_sha256s: hashes },
    });
    await insertLeaguePayload(client, releaseId, v3.league.dashboard);
    await insertTeamPayloads(client, releaseId, v3.teams);
  }, results);

  await expectRejected(client, baseline, "wrong_member_identity", async () => {
    const swappedMembers = v3.teams.map((team) => ({ ...team }));
    [swappedMembers[0].team_release_id, swappedMembers[1].team_release_id] = [
      swappedMembers[1].team_release_id, swappedMembers[0].team_release_id,
    ];
    [swappedMembers[0].curated_build_id, swappedMembers[1].curated_build_id] = [
      swappedMembers[1].curated_build_id, swappedMembers[0].curated_build_id,
    ];
    const releaseId = await createDraft(client, v3, { members: swappedMembers });
    await insertLeaguePayload(client, releaseId, v3.league.dashboard);
    await insertTeamPayloads(client, releaseId, swappedMembers);
  }, results);

  await expectRejected(client, baseline, "fifteen_team_rows", async () => {
    const releaseId = await createDraft(client, v3);
    await insertLeaguePayload(client, releaseId, v3.league.dashboard);
    await insertTeamPayloads(client, releaseId, v3.teams.slice(0, 15));
  }, results);

  await expectRejected(client, baseline, "seventeen_team_rows", async () => {
    const releaseId = await createDraft(client, v3);
    await insertLeaguePayload(client, releaseId, v3.league.dashboard);
    // The table's primary key rejects the seventeenth duplicate before the
    // statement-level validator runs; this is the first integrity boundary.
    await insertTeamPayloads(client, releaseId, [...v3.teams, v3.teams[0]]);
  }, results);

  await client.query("savepoint valid_v2_probe");
  const v2 = await loadApprovedV2(client);
  if (v2) {
    const validV2 = await createDraft(client, v2);
    await insertLeaguePayload(client, validV2, v2.league.dashboard);
    await insertTeamPayloads(client, validV2, v2.teams);
    assert(sameJson(await approvedSnapshot(client), baseline), "valid V2 draft changed approved predecessor/current release");
    await client.query("rollback to savepoint valid_v2_probe");
    results.push("valid_v2");
  } else {
    // V2 can be absent once a deployment retains only the V3 candidate tuple;
    // when it exists, any insertion or trigger failure must fail this harness.
    await client.query("rollback to savepoint valid_v2_probe");
    results.push("valid_v2_unavailable");
  }

  await client.query("rollback");
  console.log(JSON.stringify({ rollback_only: true, scenarios: results }));
} catch (error) {
  try { await client.query("rollback"); } catch {}
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
} finally {
  await client.end();
}
