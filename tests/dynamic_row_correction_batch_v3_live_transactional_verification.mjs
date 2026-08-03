import crypto from "node:crypto";
import fs from "node:fs";
import { execFileSync } from "node:child_process";
import pg from "pg";

const ROOT = new URL("../", import.meta.url);
const MIGRATION_SHA256 = "859e18440317494eb3936fd80c136a8b8fb2e7b2604141bcf58048aeaf604365";
const SEASON = "2024-25";

function readEnvironment(path) {
  const values = {};
  for (const rawLine of fs.readFileSync(path, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const index = line.indexOf("=");
    if (index < 1) continue;
    let value = line.slice(index + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    values[line.slice(0, index).trim()] = value;
  }
  return values;
}

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const env = readEnvironment(new URL("../.env.local", import.meta.url));
if (!env.SUPABASE_DB_URL_POOLER) throw new Error("SUPABASE_DB_URL_POOLER is unavailable");
const dependencyLockHash = sha256(fs.readFileSync(new URL("../package-lock.json", import.meta.url)));
const codeVersion = execFileSync("git", ["rev-parse", "HEAD"], {
  cwd: ROOT,
  encoding: "utf8",
}).trim();

const client = new pg.Client({
  connectionString: env.SUPABASE_DB_URL_POOLER,
  connectionTimeoutMillis: 10000,
  query_timeout: 900000,
  keepAlive: true,
});

async function scalar(sql, values = []) {
  const result = await client.query(sql, values);
  if (result.rows.length !== 1) throw new Error(`expected one row, got ${result.rows.length}`);
  return result.rows[0];
}

async function counts() {
  return scalar(`
    select
      (select count(*)::int from audit.correction_batches_v3) as batches,
      (select count(*)::int from audit.correction_batch_items_v3) as items,
      (select count(*)::int from processing.correction_batch_versions_v3) as versions
  `);
}

const beforeCounts = {};
try {
  await client.connect();
  Object.assign(beforeCounts, await counts());
  await client.query("begin");
  await client.query("set local statement_timeout = 900000");

  const baseline = await scalar(`
    select bundle.release_id::text as release_id,
      analysis.row_correction_bundle_hash_v1(bundle.release_id) as bundle_sha256
    from reporting.latest_approved_dashboard_bundle_v4 bundle
    where bundle.season = $1
  `, [SEASON]);

  const targets = await client.query(`
    with candidates as (
      select subject.source_row_id, subject.team_key,
        row_number() over (partition by subject.team_key order by subject.source_row_id) as item_number,
        count(*) over (partition by subject.team_key) as team_rows
      from analysis.row_correction_subjects_v1 subject
      where subject.season = $1
        and not exists (
          select 1
          from analysis.row_correction_active_values_v3 active
          where active.season = subject.season
            and active.source_row_id = subject.source_row_id
            and active.field_name = 'eligibility'
        )
    ), chosen_team as (
      select team_key from candidates where team_rows >= 2 order by team_key limit 1
    )
    select candidate.source_row_id::text, candidate.team_key
    from candidates candidate
    join chosen_team using (team_key)
    where candidate.item_number <= 2
    order by candidate.item_number
  `, [SEASON]);
  if (targets.rows.length !== 2) throw new Error("could not select two safe same-team verification rows");

  const evidenceByItem = {};
  const items = [];
  for (const [index, chosen] of targets.rows.entries()) {
    const subject = await scalar(
      "select to_jsonb(subject) as subject from analysis.row_correction_subject_v3($1, $2::uuid) subject",
      [SEASON, chosen.source_row_id],
    );
    const current = subject.subject.eligibility_value;
    if (typeof current !== "boolean") throw new Error("verification target eligibility is not boolean");
    const evidence = `rollback-only V3 verification evidence ${index + 1}`;
    const key = `${chosen.source_row_id}:eligibility`;
    evidenceByItem[key] = evidence;
    items.push({
      source_row_id: chosen.source_row_id,
      field_name: "eligibility",
      expected_value: current,
      new_value: !current,
      reason: "Rollback-only verification of same-team correction batching",
      rule_version: "row_correction_batch_2026-08-03_v3_verification",
      evidence_sha256: sha256(evidence),
    });
  }

  const proposal = {
    season: SEASON,
    items,
    operator: "Codex rollback-only verification",
    code_version: codeVersion,
    dependency_lock_hash: dependencyLockHash,
    migration_sha256: MIGRATION_SHA256,
  };
  const firstPreview = (await scalar(
    "select to_jsonb(preview) as preview from analysis.row_correction_preview_v5($1::jsonb) preview",
    [proposal],
  )).preview;
  if (!Array.isArray(firstPreview.subjects) || firstPreview.subjects.length !== 2) {
    throw new Error("batch preview did not bind both verification subjects");
  }
  const subjectByKey = new Map(firstPreview.subjects.map((subject) => [
    `${subject.source_row_id}:${subject.field_name}`,
    subject,
  ]));
  for (const item of proposal.items) {
    const subject = subjectByKey.get(`${item.source_row_id}:${item.field_name}`);
    if (!subject) throw new Error("preview subject binding is incomplete");
    item.source_row_sha256 = subject.source_row_sha256;
    item.row_fingerprint = subject.row_fingerprint;
  }
  Object.assign(proposal, {
    team_key: targets.rows[0].team_key,
    predecessor_bundle: firstPreview.predecessor_bundle,
    correction_set_hash_before: firstPreview.correction_set_hash_before,
    correction_set_hash_after: firstPreview.correction_set_hash_after,
    affected_team_before_sha256: firstPreview.affected_team_before_sha256,
    affected_team_after_sha256: firstPreview.affected_team_after_sha256,
    affected_league_before_sha256: firstPreview.affected_league_before_sha256,
    affected_league_after_sha256: firstPreview.affected_league_after_sha256,
    unchanged_team_hashes: firstPreview.unchanged_team_hashes,
  });
  proposal.proposal_hash = (await scalar(
    "select analysis.row_correction_proposal_hash_v1($1::jsonb) as proposal_hash",
    [proposal],
  )).proposal_hash;

  const applied = (await scalar(
    "select audit.apply_row_correction_batch_v8($1::jsonb, $2::jsonb, 'Abdel Babiker') as applied",
    [proposal, evidenceByItem],
  )).applied;
  if (applied.item_count !== 2) throw new Error("batch apply did not retain two items");

  const pending = await counts();
  if (pending.batches !== beforeCounts.batches + 1 || pending.items !== beforeCounts.items + 2) {
    throw new Error("batch apply audit counts are incomplete");
  }
  const beforePromotion = await scalar(`
    select bundle.release_id::text as release_id
    from reporting.latest_approved_dashboard_bundle_v4 bundle
    where bundle.season = $1
  `, [SEASON]);
  if (beforePromotion.release_id !== baseline.release_id) {
    throw new Error("unpromoted batch changed the served release");
  }

  const unique = crypto.randomUUID();
  const releaseLabel = `rollback-only-batch-v3-${unique}`;
  const promoted = (await scalar(
    "select reporting.promote_row_correction_batch_v8($1, 'Abdel Babiker', $2) as promoted",
    [proposal.proposal_hash, releaseLabel],
  )).promoted;
  if (promoted.affected_team_count !== 1 || promoted.reused_team_count !== 15) {
    throw new Error("batch promotion did not preserve the 1 + 15 team invariant");
  }

  const rollbackEvidence = "rollback-only V3 verification restore";
  await scalar(`
    select reporting.rollback_row_correction_bundle_v1(
      $1, $2, 'Abdel Babiker',
      'Restore predecessor inside rollback-only V3 verification',
      $3, 'Codex rollback-only verification', $4, $5
    ) as rolled_back
  `, [
    releaseLabel,
    `rollback-only-batch-v3-restore-${unique}`,
    sha256(rollbackEvidence),
    codeVersion,
    dependencyLockHash,
  ]);
  const restored = await scalar(`
    select analysis.row_correction_bundle_hash_v1(bundle.release_id) as bundle_sha256
    from reporting.latest_approved_dashboard_bundle_v4 bundle
    where bundle.season = $1
  `, [SEASON]);
  if (restored.bundle_sha256 !== baseline.bundle_sha256) {
    throw new Error("append-only rollback did not restore the exact predecessor payload");
  }

  await client.query("rollback");
  const afterCounts = await counts();
  if (JSON.stringify(afterCounts) !== JSON.stringify(beforeCounts)) {
    throw new Error("outer rollback retained V3 verification audit rows");
  }
  process.stdout.write(JSON.stringify({
    status: "verified_and_rolled_back",
    item_count: 2,
    affected_team_count: 1,
    reused_team_count: 15,
    predecessor_restored_exactly: true,
    retained_test_rows: 0,
  }, null, 2) + "\n");
} catch (error) {
  try { await client.query("rollback"); } catch {}
  console.error(JSON.stringify({
    message: error.message,
    position: error.position,
    internalPosition: error.internalPosition,
    internalQuery: error.internalQuery,
    where: error.where,
  }, null, 2));
  process.exitCode = 1;
} finally {
  await client.end();
}
