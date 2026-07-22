#!/usr/bin/env node
// Rollback-only hosted-DB contract for classification-only bundle releases.
// The migration, draft release, and payloads exist only inside this transaction.

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
if (!dbUrl) throw new Error("SUPABASE_DB_URL_POOLER is required in .env.local");

const season = "2024-25";
const successor = "reporting_classification_2026-07-22_v2";
const migrationSql = fs.readFileSync(path.join(
  root,
  "supabase/migrations/20260722150000_incremental_classification_bundle_release.sql",
), "utf8");
const allowedKeys = new Set(["body_locations", "injury_types", "injury_profiles"]);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function changedKeys(before, after) {
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  return [...keys].filter((key) => JSON.stringify(before[key]) !== JSON.stringify(after[key])).sort();
}

async function approvedRelease(client) {
  const result = await client.query(
    `select release.id::text,release.release_label,league.dashboard_payload as league
     from reporting.aggregate_releases release
     join reporting.league_release_context_v2 context on context.release_id=release.id
     join reporting.league_release_payloads_v2 league on league.release_id=release.id
     where release.status='approved' and context.season=$1`,
    [season],
  );
  assert(result.rows.length === 1, "expected one approved predecessor");
  return result.rows[0];
}

const client = new Client({ connectionString: dbUrl, connectionTimeoutMillis: 15_000 });
const result = { leagueChangedKeys: [], changedTeamCount: 0, teamCount: 0, rolledBack: false };

try {
  await client.connect();
  const baseline = await approvedRelease(client);
  await client.query("begin");
  await client.query(migrationSql);

  const league = await client.query(
    `select * from analysis.league_dashboard_classification_incremental_20260722_v1
     where season=$1 and classification_view_version=$2`,
    [season, successor],
  );
  const teams = await client.query(
    `select * from analysis.team_dashboard_classification_incremental_20260722_v1
     where season=$1 and classification_view_version=$2 order by team_key`,
    [season, successor],
  );
  assert(league.rows.length === 1, "expected one incremental league candidate");
  assert(teams.rows.length === 16, "expected 16 incremental team candidates");

  result.leagueChangedKeys = changedKeys(baseline.league, league.rows[0].dashboard);
  assert(result.leagueChangedKeys.length === 3, "league must change exactly three sections");
  assert(result.leagueChangedKeys.every((key) => allowedKeys.has(key)), "league changed an unrelated key");

  const predecessorTeams = await client.query(
    `select team_key,dashboard_payload as dashboard
     from reporting.team_dashboard_payloads_v2 where bundle_release_id=$1::uuid`,
    [baseline.id],
  );
  const predecessorByTeam = new Map(predecessorTeams.rows.map((row) => [row.team_key, row.dashboard]));
  for (const team of teams.rows) {
    const keys = changedKeys(predecessorByTeam.get(team.team_key), team.dashboard);
    assert(keys.every((key) => allowedKeys.has(key)), `${team.team_key} changed an unrelated key`);
    if (keys.length) result.changedTeamCount += 1;
  }
  result.teamCount = teams.rows.length;
  assert(result.changedTeamCount > 0, "successor changed no team classification payloads");

  const run = await client.query(
    `insert into audit.pipeline_runs
       (command,team,season,status,parameters,code_version,dependency_lock_hash,input_hash,output_hash,operator)
     values ('rollback-incremental-classification-release','URC Overall',$1,'started','{}'::jsonb,
       'rollback-contract','rollback-contract',$2,$2,'Codex rollback contract') returning id::text`,
    [season, "0".repeat(64)],
  );
  const release = await client.query(
    `insert into reporting.aggregate_releases(release_label,status,pipeline_run_id)
     values ($1,'draft',$2::uuid) returning id::text`,
    [`rollback-incremental-${crypto.randomUUID()}`, run.rows[0].id],
  );
  const releaseId = release.rows[0].id;
  const candidate = league.rows[0];
  await client.query(
    `insert into reporting.league_release_context_v2
       (release_id,season,analysis_version,generated_at,expected_member_count,
        match_exposure_decision,decision_reviewer,decision_recorded_at,
        classification_view_version,classification_evidence_sha256,
        cohort_view_version,cohort_evidence_sha256)
     values ($1::uuid,$2,$3,($4::jsonb->>'generated_at')::timestamptz,16,
       'all_registered_season_fixtures_15_players_x_80_minutes_div_60',
       'Abdel Babiker',date '2026-07-19',$5,$6,$7,$8)`,
    [releaseId, season, candidate.analysis_version, JSON.stringify(candidate.dashboard), successor,
      candidate.classification_evidence_sha256, candidate.cohort_view_version, candidate.cohort_evidence_sha256],
  );
  await client.query(
    `insert into reporting.league_release_members_v2(release_id,team_key,team_release_id,curated_build_id)
     select $1::uuid,team_key,team_release_id,curated_build_id
     from analysis.league_member_releases_v2 where season=$2`,
    [releaseId, season],
  );
  await client.query(
    `insert into reporting.league_release_payloads_v2(release_id,dashboard_payload)
     select $1::uuid,dashboard
     from analysis.league_dashboard_classification_incremental_20260722_v1
     where season=$2 and classification_view_version=$3`,
    [releaseId, season, successor],
  );
  await client.query(
    `insert into reporting.team_dashboard_payloads_v2
       (bundle_release_id,team_key,team_release_id,curated_build_id,dashboard_payload)
     select $1::uuid,team_key,team_release_id,curated_build_id,dashboard
     from analysis.team_dashboard_classification_incremental_20260722_v1
     where season=$2 and classification_view_version=$3`,
    [releaseId, season, successor],
  );
  const stored = await client.query(
    `select (select count(*) from reporting.league_release_payloads_v2 where release_id=$1::uuid)::int league_count,
            (select count(*) from reporting.team_dashboard_payloads_v2 where bundle_release_id=$1::uuid)::int team_count`,
    [releaseId],
  );
  assert(stored.rows[0].league_count === 1 && stored.rows[0].team_count === 16,
    "incremental draft did not store one league and 16 team payloads");

  await client.query("rollback");
  result.rolledBack = true;
  const after = await approvedRelease(client);
  assert(after.id === baseline.id && after.release_label === baseline.release_label,
    "rollback changed the approved predecessor");
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  try { await client.query("rollback"); } catch {}
  throw error;
} finally {
  await client.end();
}
