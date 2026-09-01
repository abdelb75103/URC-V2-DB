import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { buildSql, OUTPUT } from '../scripts/build-diagnosis-family-reporting-sql.mjs';

const ROOT = process.cwd();
const MIGRATION_SHA = 'b2d6af31bad2a49d26be8fe135c304fdc5a9c55a888f56cd26a5e32249cc903d';
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const read = (relativePath) => fs.readFileSync(path.join(ROOT, relativePath), 'utf8');

test('diagnosis-family reporting successor is generated, governed and reporting-only', () => {
  const migration = read(OUTPUT);
  const registration = read(
    'tools/sql/register_urc_diagnosis_family_reporting_successor_migration.sql',
  );
  const verification = read(
    'tools/sql/verify_urc_diagnosis_family_reporting_successor.sql',
  );
  const dashboardVerification = read(
    'tools/sql/verify_urc_diagnosis_family_reporting_successor_dashboards.sql',
  );
  const teamComparisonVerification = read(
    'tools/sql/verify_urc_diagnosis_family_reporting_successor_comparisons.sql',
  );
  const leagueComparisonVerification = read(
    'tools/sql/verify_urc_diagnosis_family_reporting_successor_league_comparison.sql',
  );
  const preflight = read(
    'tools/sql/preflight_urc_diagnosis_family_reporting_successor.sql',
  );
  const ledger = JSON.parse(read(
    'docs/evidence/diagnosis-families/diagnosis_family_adjudication_v1.json',
  ));

  assert.equal(migration, buildSql());
  assert.equal(sha256(migration), MIGRATION_SHA);
  assert.equal(registration.split(`migration_sha256=${MIGRATION_SHA}`).length - 1, 2);
  assert.equal(verification.split(`migration_sha256=${MIGRATION_SHA}`).length - 1, 1);
  assert.deepEqual(ledger.mapping_hashes, {
    mapping_rows_sha256: '196f9c6765dfe83b2b205614aa61b4f5c3d53a85bc32983dabb1bdfdb5910f8e',
    complete_ledger_sha256: '7f3666de1309157843bade735bf79c4b30c39c75cc1542ef96f3254d5a840af5',
    illness_mapping_rows_sha256: '8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4',
    illness_ledger_sha256: '32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92',
  });
  assert.equal(ledger.illness_mapping['2025-26_source_label_count'], 113);
  assert.equal(
    new Set(ledger.illness_mapping['2025-26_source_label_mapping']
      .map((row) => `${row.illness_group_code}\0${row.illness_group_label}`)).size,
    50,
  );
  assert.deepEqual(ledger.illness_mapping['2025-26_inventory_reconciliation'], {
    recorded_illnesses: 439,
    known_duration_illnesses: 202,
    days_lost: 927,
  });
  assert.equal(ledger.rows.filter((row) => row.review_status === 'human_review').length, 0);
  assert.deepEqual(
    ledger.rows.reduce((counts, row) => {
      counts[row.review_status] = (counts[row.review_status] ?? 0) + 1;
      return counts;
    }, {}),
    { accepted_deterministic: 780, identity_group: 122, out_of_scope: 72 },
  );

  for (const contract of [
    'create view reporting.latest_team_dashboard_v7',
    'create view reporting.latest_league_dashboard_v7',
    'create view reporting.latest_team_season_comparison_v5',
    'create view reporting.latest_league_season_comparison_v5',
    'create materialized view analysis.urc_illness_profile_rows_v1',
    'create table audit.urc_2025_26_illness_exact_labels_v1',
    'create materialized view analysis.urc_diagnosis_family_rows_v1',
    'create function reporting.illness_summary_json_v1',
    "dashboard -> 'illness_profiles' as illness_profiles",
    "dashboard -> 'illness_summary' as illness_summary",
    'Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training.',
    'season_comparison_reporting_2026_09_01_v5',
    "family_label = 'Concussion' and recorded_injuries = 126",
    "family_label = 'Concussion' and recorded_injuries = 109",
    "family_label = 'Concussion' and recorded_injuries = 17",
    "family_label = 'Hamstring muscle injury' and recorded_injuries = 82",
    "family_label = 'Concussion' and recorded_injuries = 109",
    '2025-26 league injury sections do not reconcile to 1545',
    '2024-25 league injury sections do not reconcile',
    "where item ->> 'setting' = 'all') = 1518",
    "where item ->> 'setting' = 'all') = 787",
    "where item ->> 'setting' = 'all') = 17575",
    "where season = '2025-26' and family_code <> 'unknown') <> 1464",
    "where season = '2025-26' and family_code = 'unknown') <> 81",
    'and is_time_loss) <> 73',
    'and is_time_loss) <> 1042',
    'where family.family_code is null) <> 19',
    "where season = '2024-25' and family_code = 'unknown') <> 4",
    'Diagnosis replacement changed a non-diagnosis profile row',
    'having count(distinct family_label) <> 1',
    'Illness summary does not reconcile to illness profiles',
    "from audit.urc_2025_26_illness_exact_labels_v1) <> 113",
    "from audit.urc_2025_26_illness_exact_labels_v1) <> 50",
    "where season = '2025-26' and duration_known) <> 202",
    "where season = '2025-26' and duration_known) <> 927",
    'Null rate or known-duration severity rule failed',
  ]) assert.match(migration, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));

  for (const contract of [
    '20260831170000',
    '20260831120000',
    '20260831121000',
    'f1d9c2cc-f70c-4dcc-a18d-3f2dc92d4cfc',
    '0f0def1e-021f-471f-979f-6d73d98859c4',
    '4517f50bdf03688c087a34062071d97bd635576011e02f6f8ca5d1dc69a156ae',
    '4eafb2dc32d155c69d968e833a354c145e08e0f13356b300234cefc1e2889c05',
    "'2025-26_current_injuries', 1545",
    "'2025-26_current_time_loss_injuries', 938",
    "'2025-26_current_known_duration_time_loss_injuries', 782",
    "'2025-26_current_days_lost', 20665",
    "'2025-26_illnesses', 439",
    "'2025-26_known_duration_illnesses', 202",
    "'2025-26_illness_days_lost', 927",
    "'2024-25_illnesses', 392",
    "'2025-26_source_labels', 113",
    "'2025-26_groups', 50",
    '6708f730cfa0faac40799b3eeafb99edd0e3e2e3c9a25de245daaaca1da3ef8d',
    '8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4',
    '32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92',
    "'2025-26_non_unknown_rows', 1464",
    "'2025-26_internal_unknown_rows', 81",
    "'2025-26_source_conflict_rows', 19",
  ]) assert.match(preflight, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(preflight, /\b(insert|update|delete|create|alter|drop)\b/i);
  assert.doesNotMatch(verification, /count\(\*\) from reporting\.latest_team_dashboard_v7/);
  assert.match(dashboardVerification, /where team_key = 'benetton'/);
  assert.match(teamComparisonVerification, /where team_key = 'benetton'/);
  assert.match(leagueComparisonVerification, /training_concussion_2025-26/);

  for (const contract of [
    'cohorts=2024-25_injury_1662_illness_392,2025-26_injury_1545_illness_439',
    'illness_boundary=2025-26_labels_113_groups_50_recorded_439_known_202_days_927',
    'family_boundary=2024-25_mapped_1658_unknown_4,2025-26_non_unknown_1464_internal_unknown_81_source_conflict_19',
  ]) {
    assert.match(registration, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
    assert.match(verification, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.doesNotMatch(
    migration,
    /successor\.dashboard - array\[[^\]]*'method'/s,
  );
  assert.doesNotMatch(
    migration,
    /successor\.dashboard - array\[[^\]]*'headline'/s,
  );
  assert.doesNotMatch(migration, /base\.dashboard \|\| canonical\.rows/);
  assert.doesNotMatch(migration, /select row\.\*, setting\.setting_code/);
  assert.equal(
    migration.split("'unknown', 'Unknown', 'subtype_unknown'").length - 1,
    1,
  );
  assert.equal(
    migration.split("'unknown', 'Unknown diagnosis', 'subtype_unknown'").length - 1,
    1,
  );
  assert.doesNotMatch(
    migration,
    /cross join lateral reporting\.urc_canonical_injury_sections_json_v1/,
  );
  const familyJsonBuilder = migration.slice(
    migration.indexOf('create function reporting.diagnosis_family_rows_json_v1'),
    migration.indexOf('create function reporting.illness_profile_rows_json_v1'),
  );
  assert.equal(familyJsonBuilder.split('subtypes as materialized').length - 1, 2);
  assert.equal(
    familyJsonBuilder.split('analysis.urc_diagnosis_family_team_subtypes_v1').length - 1,
    1,
  );
  assert.equal(
    familyJsonBuilder.split('analysis.urc_diagnosis_family_league_subtypes_v1').length - 1,
    1,
  );
  assert.doesNotMatch(familyJsonBuilder, /'subtypes', \(select jsonb_agg/);
  assert.equal(
    migration.split('analysis.row_correction_subject_v3(').length - 1,
    1,
  );
  assert.doesNotMatch(
    migration,
    /create view analysis\.urc_illness_profile_rows_v1/,
  );
  assert.doesNotMatch(
    migration,
    /create view analysis\.urc_diagnosis_family_rows_v1/,
  );
  const illnessBase = migration.slice(
    migration.indexOf('create materialized view analysis.urc_illness_profile_rows_v1'),
    migration.indexOf('create view analysis.urc_illness_team_profiles_v1'),
  );
  assert.match(illnessBase, /audit\.urc_2025_26_illness_exact_labels_v1/);
  assert.doesNotMatch(illnessBase, /audit\.urc_2025_26_diagnosis_family_exact_labels_v1/);
  assert.doesNotMatch(illnessBase, /problem_type_scope/);

  assert.doesNotMatch(migration, /team_dashboard_release_candidate_snapshot/);
  assert.doesNotMatch(migration, /insert into reporting\.team_dashboard_payloads_v2/i);
  assert.doesNotMatch(migration, /insert into reporting\.league_release_payloads_v6/i);
  assert.doesNotMatch(migration, /alter table lineage\./i);
  assert.doesNotMatch(migration, /alter table curated\./i);
  assert.equal(
    fs.readdirSync(path.join(ROOT, 'supabase/migrations'))
      .filter((name) => name.startsWith('20260901010000')).length,
    1,
  );
});

test('reader execution-boundary successor keeps private intermediates ungranted', () => {
  const migration = read(
    'supabase/migrations/20260901020000_urc_diagnosis_family_reader_execution_boundary.sql',
  );
  const preflight = read(
    'tools/sql/preflight_urc_diagnosis_family_reader_execution_boundary.sql',
  );
  const registration = read(
    'tools/sql/register_urc_diagnosis_family_reader_execution_boundary_migration.sql',
  );
  const verification = read(
    'tools/sql/verify_urc_diagnosis_family_reader_execution_boundary.sql',
  );
  const migrationSha = 'f9d0cdce9b30e1bbe12dc6caacb2b37d60d1107833063281a158f0a1cc00b4b2';

  assert.equal(sha256(migration), migrationSha);
  assert.match(migration, /diagnosis_family_team_dashboards_v1\s+set \(security_invoker = false\)/);
  assert.match(migration, /diagnosis_family_league_dashboards_v1\s+set \(security_invoker = false\)/);
  assert.match(migration, /revoke all on reporting\.diagnosis_family_team_dashboards_v1/);
  assert.doesNotMatch(migration, /grant select on reporting\.diagnosis_family_(?:team|league)_dashboards_v1/);
  assert.doesNotMatch(preflight, /\b(insert|update|delete|create|alter|drop)\b/i);
  assert.equal(registration.split(`migration_sha256=${migrationSha}`).length - 1, 2);
  assert.equal(verification.split(`migration_sha256=${migrationSha}`).length - 1, 1);
  for (const sql of [migration, registration, verification]) {
    assert.match(sql, /private_intermediates_ungranted|has_table_privilege/);
  }
});

test('materialized-reader successor keeps snapshots and helpers private', () => {
  const migration = read(
    'supabase/migrations/20260901021000_urc_diagnosis_family_materialized_reader_boundary.sql',
  );
  const preflight = read(
    'tools/sql/preflight_urc_diagnosis_family_materialized_reader_boundary.sql',
  );
  const registration = read(
    'tools/sql/register_urc_diagnosis_family_materialized_reader_boundary_migration.sql',
  );
  const verification = read(
    'tools/sql/verify_urc_diagnosis_family_materialized_reader_boundary.sql',
  );
  const migrationSha = 'eb015ecaa8ca3db1d4992f4c4d3498ff5f5aa65aac60f16693b780104443e5d0';

  assert.equal(sha256(migration), migrationSha);
  assert.match(migration, /create materialized view reporting\.diagnosis_family_team_dashboard_payloads_v2/);
  assert.match(migration, /create materialized view reporting\.diagnosis_family_league_dashboard_payloads_v2/);
  assert.match(migration, /from reporting\.diagnosis_family_team_dashboard_payloads_v2/);
  assert.match(migration, /from reporting\.diagnosis_family_league_dashboard_payloads_v2/);
  assert.match(migration, /revoke all on reporting\.diagnosis_family_team_dashboard_payloads_v2/);
  assert.doesNotMatch(migration, /grant select on reporting\.diagnosis_family_(?:team|league)_dashboard_payloads_v2/);
  assert.doesNotMatch(migration, /grant execute on function reporting\./);
  assert.doesNotMatch(preflight, /\b(insert|update|delete|create|alter|drop)\b/i);
  assert.equal(registration.split(`migration_sha256=${migrationSha}`).length - 1, 2);
  assert.equal(verification.split(`migration_sha256=${migrationSha}`).length - 1, 1);
});
