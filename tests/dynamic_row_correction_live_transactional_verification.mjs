/*
 * Rollback-only live verification for the dynamic row-correction pipeline.
 *
 * This harness is deliberately self-contained: it resolves pseudonymised
 * allowlisted rows inside Postgres, builds proposals from the versioned SQL
 * preview, exercises apply, promotion, and append-only rollback, then rolls
 * back the outer transaction. It never prints row identifiers or payloads.
 *
 * If the migration is not installed, the harness rehearses the migration in
 * the same outer transaction. Concurrency is tested only after installation,
 * because another session cannot see uncommitted migration objects.
 *
 * Usage against the explicitly approved target:
 *   SUPABASE_DB_URL=... node \
 *     tests/dynamic_row_correction_live_transactional_verification.mjs \
 *     --reviewer "Abdel Babiker"
 */

import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { Client } from "pg";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MIGRATION_PATH = path.join(
  ROOT,
  "supabase/migrations/20260727010000_dynamic_row_correction_pipeline_hardening.sql",
);
const EVIDENCE = "Transactional dynamic-correction verification approval";
const EVIDENCE_SHA256 = crypto
  .createHash("sha256")
  .update(EVIDENCE)
  .digest("hex");
const MIGRATION_SHA256 = crypto
  .createHash("sha256")
  .update(fs.readFileSync(MIGRATION_PATH))
  .digest("hex");
const OPERATOR = "Codex transactional verification";
const CODE_VERSION = "0".repeat(40);
const DEPENDENCY_LOCK_HASH = "1".repeat(64);
const STATEMENT_TIMEOUT_MS = 10 * 60 * 1000;
const STARTED_AT = Date.now();

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) {
    throw new Error(`missing ${name}`);
  }
  return process.argv[index + 1];
}

function mark(stage) {
  const elapsed = ((Date.now() - STARTED_AT) / 1000).toFixed(1);
  process.stderr.write(`${stage}: ${elapsed}s\n`);
}

async function procedureExists(client) {
  const result = await client.query(`
    select to_regprocedure(
      'audit.apply_row_correction_v2(jsonb,text,text)'
    ) is not null as present
  `);
  return result.rows[0].present;
}

async function correctionCounts(client) {
  const result = await client.query(`
    select jsonb_build_object(
      'sets', (select count(*) from audit.correction_sets_v1),
      'rows', (select count(*) from audit.row_corrections_v1),
      'versions', (select count(*) from processing.correction_versions_v1),
      'drafts', (select count(*) from processing.correction_drafts_v1),
      'releases', (
        select count(*) from reporting.correction_release_context_v1
      ),
      'rollbacks', (
        select count(*) from reporting.correction_rollback_context_v1
      ),
      'recovery_labels', (
        select count(*) from audit.correction_recovery_labels_v1
      ),
      'correction_league_payloads', (
        select count(*) from reporting.correction_league_payloads_v1
      ),
      'correction_team_payloads', (
        select count(*) from reporting.correction_team_payloads_v1
      ),
      'runs', (
        select count(*)
        from audit.pipeline_runs
        where command like 'correction-%'
      ),
      'steps', (
        select count(*)
        from audit.step_runs step
        join audit.pipeline_runs run on run.id = step.pipeline_run_id
        where run.command like 'correction-%'
      )
    ) as counts
  `);
  return result.rows[0].counts;
}

async function frozenV2State(client) {
  const result = await client.query(`
    select jsonb_build_object(
      'context_count', (
        select count(*) from reporting.league_release_context_v2
      ),
      'member_count', (
        select count(*) from reporting.league_release_members_v2
      ),
      'league_payload_count', (
        select count(*) from reporting.league_release_payloads_v2
      ),
      'team_payload_count', (
        select count(*) from reporting.team_dashboard_payloads_v2
      ),
      'league_hashes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'release_id', payload.release_id,
          'payload_sha256', payload.payload_sha256
        ) order by payload.release_id)
        from reporting.league_release_payloads_v2 payload
      ), '[]'::jsonb),
      'team_hashes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'bundle_release_id', payload.bundle_release_id,
          'team_key', payload.team_key,
          'payload_sha256', payload.payload_sha256
        ) order by payload.bundle_release_id, payload.team_key)
        from reporting.team_dashboard_payloads_v2 payload
      ), '[]'::jsonb)
    ) as state
  `);
  return result.rows[0].state;
}

async function servedStateV2(client) {
  const bundleResult = await client.query(`
    select
      bundle.release_id,
      release.release_label,
      release.status,
      bundle.season,
      league.payload_sha256 as league_payload_sha256,
      league.dashboard_payload as league_payload
    from reporting.latest_approved_dashboard_bundle_v2 bundle
    join reporting.aggregate_releases release
      on release.id = bundle.release_id
    join reporting.league_release_payloads_v2 league
      on league.release_id = bundle.release_id
    order by bundle.season
  `);
  const teamResult = await client.query(`
    select
      bundle.season,
      payload.team_key,
      payload.team_release_id,
      payload.curated_build_id,
      payload.payload_sha256,
      payload.dashboard_payload
    from reporting.latest_approved_dashboard_bundle_v2 bundle
    join reporting.team_dashboard_payloads_v2 payload
      on payload.bundle_release_id = bundle.release_id
    order by bundle.season, payload.team_key
  `);
  return {
    bundles: bundleResult.rows,
    teams: teamResult.rows,
  };
}

async function servedStateV4(client) {
  const bundleResult = await client.query(`
    select
      bundle.release_id,
      release.release_label,
      release.status,
      bundle.season,
      league.payload_sha256 as league_payload_sha256,
      league.dashboard_payload as league_payload
    from reporting.latest_approved_dashboard_bundle_v4 bundle
    join reporting.aggregate_releases release
      on release.id = bundle.release_id
    join reporting.dashboard_bundle_league_payloads_v1 league
      on league.release_id = bundle.release_id
    order by bundle.season
  `);
  const teamResult = await client.query(`
    select
      bundle.season,
      payload.team_key,
      payload.team_release_id,
      payload.curated_build_id,
      payload.payload_sha256,
      payload.dashboard_payload
    from reporting.latest_approved_dashboard_bundle_v4 bundle
    join reporting.dashboard_bundle_team_payloads_v1 payload
      on payload.bundle_release_id = bundle.release_id
    order by bundle.season, payload.team_key
  `);
  return {
    bundles: bundleResult.rows,
    teams: teamResult.rows,
  };
}

async function releasePayloadState(client, releaseId) {
  const leagueResult = await client.query(
    `
      select payload_sha256, dashboard_payload
      from reporting.dashboard_bundle_league_payloads_v1
      where release_id = $1
    `,
    [releaseId],
  );
  assert.equal(leagueResult.rowCount, 1, "release must have one league payload");
  const teamResult = await client.query(
    `
      select
        team_key, team_release_id, curated_build_id,
        payload_sha256, dashboard_payload
      from reporting.dashboard_bundle_team_payloads_v1
      where bundle_release_id = $1
      order by team_key
    `,
    [releaseId],
  );
  assert.equal(teamResult.rowCount, 16, "release must have 16 team payloads");
  return {
    league: leagueResult.rows[0],
    teams: teamResult.rows,
  };
}

function contactCellKey(cell) {
  return `${cell.setting}:${cell.key}`;
}

function assertContactDistribution(leaguePayload, teamRows, label) {
  const leagueCells = leaguePayload.contact_distribution;
  assert(Array.isArray(leagueCells), `${label} league contact data must be an array`);
  assert.equal(leagueCells.length, 12, `${label} league must expose 12 contact cells`);
  assert.equal(teamRows.length, 16, `${label} must contain all 16 teams`);

  const pooled = new Map();
  for (const row of teamRows) {
    const cells = row.dashboard_payload.contact_distribution;
    assert(
      Array.isArray(cells),
      `${label} team contact data must be an array`,
    );
    assert.equal(cells.length, 12, `${label} each team must expose 12 contact cells`);
    for (const cell of cells) {
      const key = contactCellKey(cell);
      const current = pooled.get(key) || {
        recorded_injuries: 0,
        time_loss_injuries: 0,
      };
      current.recorded_injuries += Number(cell.recorded_injuries);
      current.time_loss_injuries += Number(cell.time_loss_injuries);
      pooled.set(key, current);
    }
  }
  assert.equal(pooled.size, 12, `${label} pooled teams must define 12 cells`);
  for (const cell of leagueCells) {
    const expected = pooled.get(contactCellKey(cell));
    assert(expected, `${label} league contact cell must exist in team pool`);
    assert.equal(
      Number(cell.recorded_injuries),
      expected.recorded_injuries,
      `${label} league recorded injuries must pool all 16 teams`,
    );
    assert.equal(
      Number(cell.time_loss_injuries),
      expected.time_loss_injuries,
      `${label} league time-loss injuries must pool all 16 teams`,
    );
  }
}

async function currentReleaseId(client) {
  const result = await client.query(`
    select release_id
    from reporting.latest_approved_dashboard_bundle_v4
    where season = '2024-25'
  `);
  assert.equal(result.rowCount, 1, "one current bundle must be served");
  return result.rows[0].release_id;
}

async function assertCurrentContactDistribution(client, label) {
  const state = await releasePayloadState(client, await currentReleaseId(client));
  assertContactDistribution(state.league.dashboard_payload, state.teams, label);
  return state;
}

async function assertWebReaderSurface(client, label) {
  const internal = await assertCurrentContactDistribution(client, label);
  let assumedRole = false;
  await client.query("savepoint web_reader_role_check");
  try {
    await client.query("set local role web_reader");
    assumedRole = true;
    await client.query("release savepoint web_reader_role_check");
  } catch (error) {
    await client.query("rollback to savepoint web_reader_role_check");
    await client.query("release savepoint web_reader_role_check");
    if (error?.code !== "42501") throw error;
    const privilegeResult = await client.query(`
      select
        has_table_privilege(
          'web_reader', 'reporting.latest_team_dashboard_v5', 'SELECT'
        ) as team_reader,
        has_table_privilege(
          'web_reader', 'reporting.latest_league_dashboard_v5', 'SELECT'
        ) as league_reader,
        has_table_privilege(
          'web_reader', 'reporting.dashboard_bundle_context_v1', 'SELECT'
        ) as private_context,
        has_table_privilege(
          'web_reader',
          'reporting.dashboard_bundle_league_payloads_v1',
          'SELECT'
        ) as private_league,
        has_table_privilege(
          'web_reader',
          'reporting.dashboard_bundle_team_payloads_v1',
          'SELECT'
        ) as private_teams,
        has_table_privilege(
          'web_reader',
          'reporting.latest_approved_dashboard_bundle_v4',
          'SELECT'
        ) as private_selector
    `);
    assert.deepEqual(
      privilegeResult.rows[0],
      {
        team_reader: true,
        league_reader: true,
        private_context: false,
        private_league: false,
        private_teams: false,
        private_selector: false,
      },
      `${label} web_reader catalogue privileges must expose only V5`,
    );
  }

  try {
    const teamResult = await client.query(`
      select team_key, contact_distribution
      from reporting.latest_team_dashboard_v5
      where season = '2024-25'
      order by team_key
    `);
    const leagueResult = await client.query(`
      select contact_distribution
      from reporting.latest_league_dashboard_v5
      where season = '2024-25'
    `);
    assert.equal(teamResult.rowCount, 16, `${label} V5 reader must expose 16 teams`);
    assert.equal(leagueResult.rowCount, 1, `${label} V5 reader must expose one league`);
    for (const row of teamResult.rows) {
      assert.equal(
        row.contact_distribution.length,
        12,
        `${label} V5 team reader must expose 12 contact cells`,
      );
    }
    assert.equal(
      leagueResult.rows[0].contact_distribution.length,
      12,
      `${label} V5 league reader must expose 12 contact cells`,
    );

    const internalByTeam = new Map(
      internal.teams.map((row) => [
        row.team_key,
        row.dashboard_payload.contact_distribution,
      ]),
    );
    for (const row of teamResult.rows) {
      assert.deepEqual(
        row.contact_distribution,
        internalByTeam.get(row.team_key),
        `${label} V5 team reader must preserve the stored contact section`,
      );
    }
    assert.deepEqual(
      leagueResult.rows[0].contact_distribution,
      internal.league.dashboard_payload.contact_distribution,
      `${label} V5 league reader must preserve the stored contact section`,
    );

    if (assumedRole) {
      for (const relation of [
        "reporting.dashboard_bundle_context_v1",
        "reporting.dashboard_bundle_league_payloads_v1",
        "reporting.dashboard_bundle_team_payloads_v1",
        "reporting.latest_approved_dashboard_bundle_v4",
      ]) {
        await expectedFailure(
          client,
          `select * from ${relation} limit 1`,
          [],
          /permission denied/i,
        );
      }
    }
  } finally {
    if (assumedRole) await client.query("reset role");
  }
}

async function assertOrdinaryV2ApprovalRejected(client, label) {
  await client.query("savepoint synthetic_ordinary_release");
  try {
    const predecessorId = await currentReleaseId(client);
    const releaseResult = await client.query(
      `
        insert into reporting.aggregate_releases (release_label, status)
        values ($1, 'draft')
        returning id
      `,
      [label],
    );
    const releaseId = releaseResult.rows[0].id;
    await client.query(
      `
        insert into reporting.league_release_context_v2 (
          release_id, season, analysis_version, generated_at,
          expected_member_count, match_exposure_decision,
          decision_reviewer, decision_recorded_at,
          classification_view_version, classification_evidence_sha256,
          cohort_view_version, cohort_evidence_sha256
        )
        select
          $1, season, analysis_version, generated_at,
          expected_member_count, match_exposure_decision,
          decision_reviewer, decision_recorded_at,
          classification_view_version, classification_evidence_sha256,
          cohort_view_version, cohort_evidence_sha256
        from reporting.dashboard_bundle_context_v1
        where release_id = $2
      `,
      [releaseId, predecessorId],
    );
    await expectedFailure(
      client,
      `
        update reporting.aggregate_releases
        set status = 'approved', approved_at = now()
        where id = $1
      `,
      [releaseId],
      /ordinary release approval blocked while (?:served row corrections are active|a correction is applied but unpromoted)/i,
    );
  } finally {
    await client.query("rollback to savepoint synthetic_ordinary_release");
    await client.query("release savepoint synthetic_ordinary_release");
  }
}

async function assertDirectApprovedInsertRejected(client) {
  await expectedFailure(
    client,
    `
      insert into reporting.aggregate_releases (release_label, status)
      values ('transactional-direct-approved-insert', 'approved')
    `,
    [],
    /aggregate releases must be inserted as draft before approval/i,
  );
}

async function expectedFailure(client, sql, values, pattern) {
  await client.query("savepoint expected_failure");
  try {
    await client.query(sql, values);
  } catch (error) {
    await client.query("rollback to savepoint expected_failure");
    if (pattern.test(String(error?.message || error))) return;
    throw error;
  }
  await client.query("rollback to savepoint expected_failure");
  throw new Error("expected failure unexpectedly succeeded");
}

async function buildProposal(client, kind, excludedSourceRowIds = []) {
  const impact = kind === "impact";
  mark(`${kind} proposal row selection started`);
  const cohortResult = await client.query(
    `
      select source_row_id
      from analysis.row_correction_base_injury_cohort_v1
      where season = '2024-25'
        and is_time_loss = $1
        and not (source_row_id = any($2::uuid[]))
      order by source_row_id
      limit 1
    `,
    [impact, excludedSourceRowIds],
  );
  assert.equal(
    cohortResult.rowCount,
    1,
    `an allowlisted ${kind} verification row must exist`,
  );

  const subjectResult = await client.query(
    `
      select
        subject.source_row_id,
        case
          when $2::boolean then subject.eligibility_value
          else subject.diagnosis_value
        end as expected_value,
        case
          when subject.diagnosis_value = '"concussion"'::jsonb
            then '"unknown"'::jsonb
          else '"concussion"'::jsonb
        end as no_impact_new_value
      from analysis.row_correction_subject_v1('2024-25', $1) subject
    `,
    [cohortResult.rows[0].source_row_id, impact],
  );
  assert.equal(subjectResult.rowCount, 1, "selected subject must resolve exactly");
  mark(`${kind} proposal subject resolved`);

  const subject = subjectResult.rows[0];
  const provisional = {
    season: "2024-25",
    source_row_id: subject.source_row_id,
    field_name: impact ? "eligibility" : "diagnosis_code",
    expected_value: subject.expected_value,
    new_value: impact ? false : subject.no_impact_new_value,
    reason: impact
      ? "Transactional exclusion impact verification"
      : "Transactional no-dashboard-impact verification",
    evidence_sha256: EVIDENCE_SHA256,
    operator: OPERATOR,
    rule_version: "row_correction_transactional_test_v1",
    code_version: CODE_VERSION,
    dependency_lock_hash: DEPENDENCY_LOCK_HASH,
    migration_sha256: MIGRATION_SHA256,
  };
  const previewResult = await client.query(
    `
      select to_jsonb(preview) as preview
      from analysis.row_correction_preview_v2($1::jsonb) preview
    `,
    [provisional],
  );
  assert.equal(previewResult.rowCount, 1, "preview must return one candidate");
  const preview = previewResult.rows[0].preview;
  mark(`${kind} SQL preview completed`);

  const proposal = {
    ...provisional,
    source_row_sha256: preview.subject.source_row_sha256,
    row_fingerprint: preview.subject.row_fingerprint,
    correction_set_hash_before: preview.correction_set_hash_before,
    correction_set_hash_after: preview.correction_set_hash_after,
    predecessor_bundle: preview.predecessor_bundle,
    affected_team_before_sha256: preview.affected_team_before_sha256,
    affected_team_after_sha256: preview.affected_team_after_sha256,
    affected_league_before_sha256: preview.affected_league_before_sha256,
    affected_league_after_sha256: preview.affected_league_after_sha256,
    unchanged_team_hashes: preview.unchanged_team_hashes,
  };
  const hashResult = await client.query(
    "select analysis.row_correction_proposal_hash_v1($1::jsonb) as hash",
    [proposal],
  );
  proposal.proposal_hash = hashResult.rows[0].hash;
  const reboundResult = await client.query(
    `
      select to_jsonb(preview) as preview
      from analysis.row_correction_preview_v2($1::jsonb) preview
    `,
    [proposal],
  );
  assert.equal(reboundResult.rowCount, 1, "bound proposal must replay exactly");
  assert.deepEqual(
    reboundResult.rows[0].preview,
    preview,
    "bound proposal preview must equal the original SQL preview",
  );

  if (impact) {
    assert.notEqual(
      preview.affected_team_before_sha256,
      preview.affected_team_after_sha256,
      "impact proposal must change the affected team payload",
    );
    assert.notEqual(
      preview.affected_league_before_sha256,
      preview.affected_league_after_sha256,
      "impact proposal must change the pooled league payload",
    );
    assert.equal(
      preview.unchanged_team_hashes.length,
      15,
      "impact preview must bind 15 unchanged teams",
    );
  } else {
    assert.equal(
      preview.affected_team_before_sha256,
      preview.affected_team_after_sha256,
      "no-impact proposal must retain the affected team payload",
    );
    assert.equal(
      preview.affected_league_before_sha256,
      preview.affected_league_after_sha256,
      "no-impact proposal must retain the league payload",
    );
    assert.equal(
      preview.unchanged_team_hashes.length,
      16,
      "no-impact preview must bind all 16 unchanged teams",
    );
  }

  mark(`${kind} proposal bound`);
  return { proposal, preview };
}

async function assertStoredDraft(client, correctionSetId, proposal, preview, impact) {
  const result = await client.query(
    `
      select *
      from processing.correction_drafts_v1
      where correction_set_id = $1
    `,
    [correctionSetId],
  );
  assert.equal(result.rowCount, 1, "apply must store one immutable draft");
  const draft = result.rows[0];
  assert.equal(draft.proposal_hash, proposal.proposal_hash);
  assert.equal(draft.correction_set_hash, proposal.correction_set_hash_after);
  assert.equal(
    draft.predecessor_bundle_id,
    proposal.predecessor_bundle.release_id,
  );
  assert.equal(
    draft.predecessor_bundle_sha256,
    proposal.predecessor_bundle.bundle_sha256,
  );
  assert.equal(
    draft.affected_team_before_sha256,
    preview.affected_team_before_sha256,
  );
  assert.equal(
    draft.affected_team_after_sha256,
    preview.affected_team_after_sha256,
  );
  assert.equal(
    draft.affected_league_before_sha256,
    preview.affected_league_before_sha256,
  );
  assert.equal(
    draft.affected_league_after_sha256,
    preview.affected_league_after_sha256,
  );
  assert.deepEqual(
    draft.affected_team_after_payload,
    preview.affected_team_after,
    "stored affected-team payload must equal the reviewed SQL preview",
  );
  assert.deepEqual(
    draft.affected_league_after_payload,
    preview.affected_league_after,
    "stored league payload must equal the reviewed SQL preview",
  );
  assert.deepEqual(
    draft.unchanged_team_hashes,
    preview.unchanged_team_hashes,
    "stored unchanged-team proof must equal the reviewed SQL preview",
  );
  assert.equal(draft.draft_bundle_sha256, preview.draft_bundle_sha256);
  assert.equal(draft.metric_change_detected, impact);
  return draft;
}

async function assertPromotedPayloads(
  client,
  promotion,
  draft,
  expectedAffectedCount,
) {
  assert.equal(promotion.affected_team_count, expectedAffectedCount);
  assert.equal(promotion.reused_team_count, 16 - expectedAffectedCount);
  assert.equal(promotion.draft_bundle_sha256, draft.draft_bundle_sha256);

  const predecessor = await releasePayloadState(
    client,
    promotion.predecessor_bundle_id,
  );
  const promoted = await releasePayloadState(client, promotion.release_id);
  assert.deepEqual(
    promoted.league.dashboard_payload,
    draft.affected_league_after_payload,
    "promoted league payload must equal the immutable draft",
  );
  assert.equal(
    promoted.league.payload_sha256,
    draft.affected_league_after_sha256,
    "promoted league hash must equal the immutable draft",
  );

  const predecessorByTeam = new Map(
    predecessor.teams.map((row) => [row.team_key, row]),
  );
  let changedTeams = 0;
  for (const row of promoted.teams) {
    const before = predecessorByTeam.get(row.team_key);
    assert(before, "every promoted team must exist in the predecessor");
    assert.equal(row.team_release_id, before.team_release_id);
    assert.equal(row.curated_build_id, before.curated_build_id);
    if (row.team_key === draft.affected_team_key) {
      assert.deepEqual(
        row.dashboard_payload,
        draft.affected_team_after_payload,
        "promoted affected-team payload must equal the immutable draft",
      );
      assert.equal(row.payload_sha256, draft.affected_team_after_sha256);
    } else {
      assert.equal(
        row.payload_sha256,
        before.payload_sha256,
        "unaffected team hash must be reused byte-for-byte",
      );
      assert.deepEqual(
        row.dashboard_payload,
        before.dashboard_payload,
        "unaffected team payload must be reused byte-for-byte",
      );
    }
    if (row.payload_sha256 !== before.payload_sha256) changedTeams += 1;
  }
  assert.equal(
    changedTeams,
    expectedAffectedCount,
    "promotion must change only the expected number of team payloads",
  );
  assertContactDistribution(
    promoted.league.dashboard_payload,
    promoted.teams,
    "promoted bundle",
  );

  const bundleHashResult = await client.query(
    "select analysis.row_correction_bundle_hash_v1($1) as hash",
    [promotion.release_id],
  );
  assert.equal(bundleHashResult.rows[0].hash, draft.draft_bundle_sha256);
  const servedResult = await client.query(
    `
      select release_id
      from reporting.latest_approved_dashboard_bundle_v4
      where season = '2024-25'
    `,
  );
  assert.equal(servedResult.rowCount, 1);
  assert.equal(
    servedResult.rows[0].release_id,
    promotion.release_id,
    "the unified selector must serve the promoted correction bundle",
  );
  await expectedFailure(
    client,
    `
      update reporting.correction_league_payloads_v1
      set payload_sha256 = payload_sha256
      where bundle_release_id = $1
    `,
    [promotion.release_id],
    /append-only/i,
  );
  await expectedFailure(
    client,
    `
      update reporting.correction_team_payloads_v1
      set payload_sha256 = payload_sha256
      where bundle_release_id = $1
    `,
    [promotion.release_id],
    /append-only/i,
  );
  return predecessor;
}

async function assertImmutableRollback(
  client,
  promotion,
  predecessor,
  releaseLabel,
  reviewer,
  expectedActiveSetCount,
) {
  const rollbackLabel = `${releaseLabel}-rollback`;
  const rollbackResult = await client.query(
    `
      select reporting.rollback_row_correction_bundle_v1(
        $1,$2,$3,$4,$5,$6,$7,$8
      ) as value
    `,
    [
      releaseLabel,
      rollbackLabel,
      reviewer,
      "Transactional rollback verification",
      EVIDENCE_SHA256,
      OPERATOR,
      CODE_VERSION,
      DEPENDENCY_LOCK_HASH,
    ],
  );
  const rollback = rollbackResult.rows[0].value;
  assert.notEqual(
    rollback.rollback_release_id,
    promotion.predecessor_bundle_id,
    "rollback must append a new immutable release",
  );
  assert.equal(
    rollback.restored_predecessor_release_id,
    promotion.predecessor_bundle_id,
  );
  assert.equal(
    rollback.active_correction_state_restored_from_predecessor,
    true,
  );

  const restored = await releasePayloadState(
    client,
    rollback.rollback_release_id,
  );
  assert.deepEqual(
    restored,
    predecessor,
    "rollback bundle must be byte-identical to the retained predecessor",
  );
  const stateResult = await client.query(
    `
      select
        current_bundle.release_id as served_release_id,
        correction.status as correction_status,
        restored.status as rollback_status,
        predecessor.status as predecessor_status,
        rollback_context.restored_bundle_id,
        (
          select count(*)::integer
          from analysis.row_correction_served_sets_v1
          where season = '2024-25'
        ) as active_set_count
      from reporting.latest_approved_dashboard_bundle_v4 current_bundle
      join reporting.aggregate_releases correction
        on correction.id = $1
      join reporting.aggregate_releases restored
        on restored.id = $2
      join reporting.aggregate_releases predecessor
        on predecessor.id = $3
      join reporting.correction_rollback_context_v1 rollback_context
        on rollback_context.bundle_release_id = restored.id
      where current_bundle.season = '2024-25'
    `,
    [
      promotion.release_id,
      rollback.rollback_release_id,
      promotion.predecessor_bundle_id,
    ],
  );
  assert.equal(stateResult.rowCount, 1, "rollback state must be auditable");
  const state = stateResult.rows[0];
  assert.equal(state.served_release_id, rollback.rollback_release_id);
  assert.equal(state.correction_status, "retired");
  assert.equal(state.rollback_status, "approved");
  assert.equal(state.predecessor_status, "retired");
  assert.equal(
    state.restored_bundle_id,
    promotion.predecessor_bundle_id,
  );
  assert.equal(state.active_set_count, expectedActiveSetCount);
  assertContactDistribution(
    restored.league.dashboard_payload,
    restored.teams,
    "rollback bundle",
  );

  await expectedFailure(
    client,
    `
      update reporting.correction_rollback_context_v1
      set reason = reason
      where bundle_release_id = $1
    `,
    [rollback.rollback_release_id],
    /append-only/i,
  );
  return rollback;
}

async function assertCollisionSafeRecovery(
  client,
  promotion,
  predecessor,
  releaseLabel,
  reviewer,
) {
  const occupiedLabel = `${releaseLabel}-occupied-recovery`;
  await client.query(
    `
      insert into reporting.aggregate_releases (release_label, status)
      values ($1, 'draft')
    `,
    [occupiedLabel],
  );
  const recoveryResult = await client.query(
    `
      select reporting.rollback_row_correction_bundle_recovery_v2(
        $1,$2,$3,$4,$5,$6,$7,$8
      ) as value
    `,
    [
      releaseLabel,
      occupiedLabel,
      reviewer,
      "Transactional collision-safe recovery verification",
      EVIDENCE_SHA256,
      OPERATOR,
      CODE_VERSION,
      DEPENDENCY_LOCK_HASH,
    ],
  );
  const recovery = recoveryResult.rows[0].value;
  assert.equal(recovery.rollback_label_fallback_used, true);
  assert.equal(
    recovery.requested_rollback_release_label,
    occupiedLabel,
  );
  assert.notEqual(
    recovery.effective_rollback_release_label,
    occupiedLabel,
  );
  assert.match(
    recovery.effective_rollback_release_label,
    new RegExp(`^${occupiedLabel}-recovery-`),
  );
  assert.equal(
    recovery.restored_predecessor_release_id,
    promotion.predecessor_bundle_id,
  );

  const restored = await releasePayloadState(
    client,
    recovery.rollback_release_id,
  );
  assert.deepEqual(
    restored,
    predecessor,
    "collision-safe recovery must restore the exact retained predecessor",
  );
  const auditResult = await client.query(
    `
      select requested_rollback_release_label,
        effective_rollback_release_label, fallback_used
      from audit.correction_recovery_labels_v1
      where rollback_release_id = $1
    `,
    [recovery.rollback_release_id],
  );
  assert.equal(auditResult.rowCount, 1);
  assert.equal(
    auditResult.rows[0].requested_rollback_release_label,
    occupiedLabel,
  );
  assert.equal(
    auditResult.rows[0].effective_rollback_release_label,
    recovery.effective_rollback_release_label,
  );
  assert.equal(auditResult.rows[0].fallback_used, true);

  const servedResult = await client.query(`
    select release_id
    from reporting.latest_approved_dashboard_bundle_v4
    where season = '2024-25'
  `);
  assert.equal(servedResult.rowCount, 1);
  assert.equal(servedResult.rows[0].release_id, recovery.rollback_release_id);
  await expectedFailure(
    client,
    `
      update audit.correction_recovery_labels_v1
      set fallback_used = fallback_used
      where rollback_release_id = $1
    `,
    [recovery.rollback_release_id],
    /append-only/i,
  );
  return recovery;
}

async function rollbackQuietly(client) {
  if (!client) return;
  try {
    await client.query("rollback");
  } catch {}
}

const connectionString = process.env.SUPABASE_DB_URL;
if (!connectionString) throw new Error("SUPABASE_DB_URL is required");
const reviewer = argument("--reviewer");
if (reviewer !== "Abdel Babiker") {
  throw new Error("this verification is limited to the named release reviewer");
}
const connectionOptions = {
  connectionString,
  connectionTimeoutMillis: 10_000,
  query_timeout: STATEMENT_TIMEOUT_MS,
  keepAlive: true,
};

const owner = new Client(connectionOptions);
const contender = new Client(connectionOptions);
const verifier = new Client(connectionOptions);
let ownerConnected = false;
let contenderConnected = false;
let verifierConnected = false;
let installedBefore = false;
let beforeCounts;
let beforeServed;
let beforeFrozenV2;
let failure;

try {
  await owner.connect();
  ownerConnected = true;
  installedBefore = await procedureExists(owner);
  beforeFrozenV2 = await frozenV2State(owner);
  if (installedBefore) {
    await Promise.all([contender.connect(), verifier.connect()]);
    contenderConnected = true;
    verifierConnected = true;
    beforeCounts = await correctionCounts(verifier);
    beforeServed = await servedStateV4(verifier);
  } else {
    beforeServed = await servedStateV2(owner);
  }
  mark(`connections ready, migration installed=${installedBefore}`);

  await owner.query("begin");
  await owner.query(
    `set local statement_timeout = '${STATEMENT_TIMEOUT_MS}ms'`,
  );
  if (!installedBefore) {
    await owner.query(fs.readFileSync(MIGRATION_PATH, "utf8"));
    await owner.query(
      `
        insert into supabase_migrations.schema_migrations (
          version, name, statements
        ) values (
          '20260727010000',
          'dynamic_row_correction_pipeline_hardening',
          array[$1::text]
        )
        on conflict (version) do nothing
      `,
      [`migration_sha256=${MIGRATION_SHA256}`],
    );
    mark("transactional migration rehearsal completed");
  }
  assert.deepEqual(
    await frozenV2State(owner),
    beforeFrozenV2,
    "additive migration must not change frozen V2 rows or payload hashes",
  );
  await assertWebReaderSurface(owner, "baseline");
  mark("baseline V5 reader permissions and pooled contact data verified");
  await assertDirectApprovedInsertRejected(owner);
  mark("direct approved aggregate-release insertion rejected");

  const impact = await buildProposal(owner, "impact");
  await owner.query("savepoint cross_season_isolation");
  try {
    const syntheticProposalHash = crypto.randomBytes(32).toString("hex");
    await owner.query(
      `
        insert into audit.correction_sets_v1 (
          season, proposal_hash, source_row_id, team_key,
          base_bundle_id, base_bundle_sha256,
          correction_set_hash_before, correction_set_hash_after,
          source_row_sha256, row_fingerprint,
          field_name, old_value, new_value,
          reason, evidence_sha256, operator, reviewer, rule_version,
          code_version, dependency_lock_hash, migration_sha256,
          apply_pipeline_run_id
        ) values (
          '2099-00', $1, $2, $3,
          $4, $5,
          $6, $7,
          $8, $9,
          'eligibility', 'true'::jsonb, 'false'::jsonb,
          'Transactional cross-season isolation sentinel',
          $10, $11, $12, 'row_correction_transactional_test_v2',
          $13, $14, $15,
          (
            select release.pipeline_run_id
            from reporting.aggregate_releases release
            where release.id = $4
          )
        )
      `,
      [
        syntheticProposalHash,
        impact.proposal.source_row_id,
        impact.preview.subject.team_key,
        impact.preview.predecessor_bundle.release_id,
        impact.preview.predecessor_bundle.bundle_sha256,
        "2".repeat(64),
        "3".repeat(64),
        impact.proposal.source_row_sha256,
        impact.proposal.row_fingerprint,
        EVIDENCE_SHA256,
        OPERATOR,
        reviewer,
        CODE_VERSION,
        DEPENDENCY_LOCK_HASH,
        MIGRATION_SHA256,
      ],
    );
    const globalTargets = await owner.query(`
      select count(distinct season)::integer as seasons
      from analysis.row_correction_target_teams_v1
    `);
    assert.ok(
      globalTargets.rows[0].seasons >= 2,
      "cross-season fixture must expose the V1 global-target defect",
    );
    await owner.query(
      "select set_config('urc.row_correction_target_season', '2024-25', true)",
    );
    const isolatedTargets = await owner.query(`
      select count(*)::integer as rows,
        count(distinct season)::integer as seasons,
        min(season) as season,
        min(team_key) as team_key
      from analysis.row_correction_target_teams_v2
    `);
    assert.equal(isolatedTargets.rows[0].rows, 1);
    assert.equal(isolatedTargets.rows[0].seasons, 1);
    assert.equal(isolatedTargets.rows[0].season, "2024-25");
    assert.equal(
      isolatedTargets.rows[0].team_key,
      impact.preview.subject.team_key,
      "V2 target graph must isolate the requested season and affected team",
    );
    const isolatedPreview = await owner.query(
      `
        select to_jsonb(preview) as preview
        from analysis.row_correction_preview_v2($1::jsonb) preview
      `,
      [impact.proposal],
    );
    assert.equal(
      isolatedPreview.rowCount,
      1,
      "V2 preview must remain unique with another season pending",
    );
    assert.deepEqual(
      isolatedPreview.rows[0].preview,
      impact.preview,
      "another season's pending correction must not change this candidate",
    );
  } finally {
    await owner.query("rollback to savepoint cross_season_isolation");
    await owner.query("release savepoint cross_season_isolation");
  }
  mark("cross-season pending candidate isolation verified");
  const stale = {
    ...impact.proposal,
    row_fingerprint: "f".repeat(64),
  };
  const staleHashResult = await owner.query(
    "select analysis.row_correction_proposal_hash_v1($1::jsonb) as hash",
    [stale],
  );
  stale.proposal_hash = staleHashResult.rows[0].hash;
  await expectedFailure(
    owner,
    "select audit.apply_row_correction_v2($1::jsonb, $2, $3)",
    [stale, EVIDENCE, reviewer],
    /fingerprint changed/i,
  );
  mark("stale proposal rejection verified");

  const unregisteredImplementation = {
    ...impact.proposal,
    migration_sha256: "f".repeat(64),
  };
  const unregisteredHashResult = await owner.query(
    "select analysis.row_correction_proposal_hash_v1($1::jsonb) as hash",
    [unregisteredImplementation],
  );
  unregisteredImplementation.proposal_hash =
    unregisteredHashResult.rows[0].hash;
  await expectedFailure(
    owner,
    "select audit.apply_row_correction_v2($1::jsonb, $2, $3)",
    [unregisteredImplementation, EVIDENCE, reviewer],
    /does not match the installed correction implementation/i,
  );
  mark("unregistered migration provenance rejection verified");

  const impactApplyResult = await owner.query(
    "select audit.apply_row_correction_v2($1::jsonb, $2, $3) as value",
    [impact.proposal, EVIDENCE, reviewer],
  );
  const impactApply = impactApplyResult.rows[0].value;
  const impactDraft = await assertStoredDraft(
    owner,
    impactApply.correction_set_id,
    impact.proposal,
    impact.preview,
    true,
  );
  mark("impact apply and exact immutable draft verified");

  await expectedFailure(
    owner,
    "select * from analysis.row_correction_preview_v2($1::jsonb)",
    [impact.proposal],
    /already applied but unpromoted/i,
  );
  await expectedFailure(
    owner,
    `
      update audit.correction_sets_v1
      set reason = reason
      where id = $1
    `,
    [impactApply.correction_set_id],
    /append-only/i,
  );
  await expectedFailure(
    owner,
    `
      update processing.correction_drafts_v1
      set proposal_hash = proposal_hash
      where id = $1
    `,
    [impactDraft.id],
    /append-only/i,
  );
  mark("pending proposal rejection and append-only guards verified");
  await assertOrdinaryV2ApprovalRejected(
    owner,
    `txn-ordinary-pending-${Date.now()}`,
  );
  mark("ordinary V2 approval rejected while correction is pending");

  if (installedBefore) {
    await contender.query("begin");
    await contender.query("set local lock_timeout = '500ms'");
    await expectedFailure(
      contender,
      "select audit.apply_row_correction_v2($1::jsonb, $2, $3)",
      [impact.proposal, EVIDENCE, reviewer],
      /(lock timeout|canceling statement)/i,
    );
    await contender.query("rollback");
    mark("concurrent apply rejection verified");
  }

  const impactReleaseLabel = `txn-impact-${Date.now()}`;
  const impactPromotionResult = await owner.query(
    "select reporting.promote_row_correction_v2($1, $2, $3) as value",
    [impactApply.proposal_hash, reviewer, impactReleaseLabel],
  );
  const impactPromotion = impactPromotionResult.rows[0].value;
  const impactPredecessor = await assertPromotedPayloads(
    owner,
    impactPromotion,
    impactDraft,
    1,
  );
  assert.deepEqual(
    await frozenV2State(owner),
    beforeFrozenV2,
    "correction promotion must not change frozen V2 rows or hashes",
  );
  await assertWebReaderSurface(owner, "first correction");
  await assertOrdinaryV2ApprovalRejected(
    owner,
    `txn-ordinary-served-${Date.now()}`,
  );
  const firstCorrectionState = await releasePayloadState(
    owner,
    impactPromotion.release_id,
  );
  mark("first correction, V5 readers, and served ordinary-release guard verified");

  const noImpact = await buildProposal(owner, "no-impact");
  const noImpactApplyResult = await owner.query(
    "select audit.apply_row_correction_v2($1::jsonb, $2, $3) as value",
    [noImpact.proposal, EVIDENCE, reviewer],
  );
  const noImpactApply = noImpactApplyResult.rows[0].value;
  const noImpactDraft = await assertStoredDraft(
    owner,
    noImpactApply.correction_set_id,
    noImpact.proposal,
    noImpact.preview,
    false,
  );
  const correctedOrigin = await owner.query(
    `
      select classification.diagnosis_origin
      from analysis.row_correction_reporting_classification_v2 classification
      join curated.injuries injury
        on injury.id = classification.injury_id
       and injury.curated_build_id = classification.curated_build_id
       and injury.team_key = classification.team_key
       and injury.season = classification.season
      where injury.source_row_id = $1
        and classification.season = '2024-25'
    `,
    [noImpact.proposal.source_row_id],
  );
  assert.equal(correctedOrigin.rowCount, 1);
  assert.equal(
    correctedOrigin.rows[0].diagnosis_origin,
    "row_correction",
    "active clinical correction origin must remain explicit",
  );
  mark("no-impact apply and exact immutable draft verified");

  const noImpactReleaseLabel = `txn-no-impact-${Date.now()}`;
  const noImpactPromotionResult = await owner.query(
    "select reporting.promote_row_correction_v2($1, $2, $3) as value",
    [noImpactApply.proposal_hash, reviewer, noImpactReleaseLabel],
  );
  const noImpactPromotion = noImpactPromotionResult.rows[0].value;
  const noImpactPredecessor = await assertPromotedPayloads(
    owner,
    noImpactPromotion,
    noImpactDraft,
    0,
  );
  assert.deepEqual(
    await frozenV2State(owner),
    beforeFrozenV2,
    "second correction must not change frozen V2 rows or hashes",
  );
  mark("sequential no-impact correction verified as 0 changed and 16 reused");
  const noImpactRollback = await assertImmutableRollback(
    owner,
    noImpactPromotion,
    noImpactPredecessor,
    noImpactReleaseLabel,
    reviewer,
    1,
  );
  assert.deepEqual(
    await releasePayloadState(owner, noImpactRollback.rollback_release_id),
    firstCorrectionState,
    "rolling back C2 must preserve C1 as the served effective state",
  );
  await assertWebReaderSurface(owner, "second correction rollback");
  assert.deepEqual(
    await frozenV2State(owner),
    beforeFrozenV2,
    "sequential rollback must not change frozen V2 rows or hashes",
  );
  mark("C2 rollback preserved C1 and remained readable through V5");

  const postRollbackImpact = await buildProposal(
    owner,
    "impact",
    [impact.proposal.source_row_id],
  );
  const postRollbackApplyResult = await owner.query(
    "select audit.apply_row_correction_v2($1::jsonb, $2, $3) as value",
    [postRollbackImpact.proposal, EVIDENCE, reviewer],
  );
  const postRollbackApply = postRollbackApplyResult.rows[0].value;
  const postRollbackDraft = await assertStoredDraft(
    owner,
    postRollbackApply.correction_set_id,
    postRollbackImpact.proposal,
    postRollbackImpact.preview,
    true,
  );
  const postRollbackReleaseLabel = `txn-after-rollback-${Date.now()}`;
  const postRollbackPromotionResult = await owner.query(
    "select reporting.promote_row_correction_v2($1, $2, $3) as value",
    [postRollbackApply.proposal_hash, reviewer, postRollbackReleaseLabel],
  );
  const postRollbackPromotion = postRollbackPromotionResult.rows[0].value;
  const postRollbackPredecessor = await assertPromotedPayloads(
    owner,
    postRollbackPromotion,
    postRollbackDraft,
    1,
  );
  await assertWebReaderSurface(owner, "correction after rollback");
  const collisionSafeRecovery = await assertCollisionSafeRecovery(
    owner,
    postRollbackPromotion,
    postRollbackPredecessor,
    postRollbackReleaseLabel,
    reviewer,
  );
  assert.equal(
    collisionSafeRecovery.active_correction_state_restored_from_predecessor,
    true,
  );
  await assertWebReaderSurface(owner, "final rollback");
  assert.deepEqual(
    await frozenV2State(owner),
    beforeFrozenV2,
    "post-rollback correction must not change frozen V2 rows or hashes",
  );
  mark("new correction and collision-safe compensating rollback verified");
} catch (error) {
  failure = error;
} finally {
  await Promise.allSettled([
    rollbackQuietly(contenderConnected ? contender : null),
    rollbackQuietly(ownerConnected ? owner : null),
  ]);

  try {
    if (installedBefore) {
      const afterCounts = await correctionCounts(verifier);
      const afterServed = await servedStateV4(verifier);
      assert.deepEqual(
        afterCounts,
        beforeCounts,
        "transactional verification left persistent correction state",
      );
      assert.deepEqual(
        afterServed,
        beforeServed,
        "served V5 bundle or metrics changed after transactional verification",
      );
      assert.deepEqual(
        await frozenV2State(verifier),
        beforeFrozenV2,
        "transactional verification changed frozen V2 rows or hashes",
      );
    } else {
      assert.equal(
        await procedureExists(owner),
        false,
        "transactional migration rehearsal persisted objects",
      );
      assert.deepEqual(
        await servedStateV2(owner),
        beforeServed,
        "served V5 bundle or metrics changed after migration rehearsal",
      );
      assert.deepEqual(
        await frozenV2State(owner),
        beforeFrozenV2,
        "migration rehearsal changed frozen V2 rows or hashes",
      );
    }
    mark("outer rollback, zero residual state, and served parity verified");
  } catch (error) {
    if (!failure) failure = error;
  }

  await Promise.allSettled([
    ...(contenderConnected ? [contender.end()] : []),
    ...(verifierConnected ? [verifier.end()] : []),
    ...(ownerConnected ? [owner.end()] : []),
  ]);
}

if (failure) throw failure;
process.stdout.write(
  JSON.stringify({
    installed_before: installedBefore,
    stale_rejection: true,
    registered_migration_sha_rejection: true,
    cross_season_candidate_isolation: true,
    pending_rejection: true,
    append_only_guards: true,
    concurrency_rejection: installedBefore,
    exact_draft_payloads: true,
    impact_promotion: "1_changed_15_reused",
    no_impact_promotion: "0_changed_16_reused",
    sequential_corrections: "c1_c2_rollback_c2_preserved_c1",
    correction_after_rollback: true,
    immutable_rollbacks: true,
    collision_safe_recovery: "uuid_suffix_and_audited_mapping",
    clinical_correction_origin: "row_correction",
    ordinary_v2_release_guard: "pending_and_served",
    v5_reader_role_states: "baseline_correction_rollback",
    contact_distribution: "12_cells_and_16_team_pool",
    unified_correction_selection: true,
    frozen_v2_rows_and_hashes: "unchanged",
    served_parity: true,
    residual_state: "zero",
    final_action: "rollback",
  }) + "\n",
);
