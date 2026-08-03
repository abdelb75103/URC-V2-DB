with expected_migrations(version, name, sha256) as (
  values
    ('20260803153728', 'dynamic_row_correction_batch_v3',
      'c4e4bdde1ca767b42f445279f07d0ab698c47536d5a7ef4a4e2bdd585880f953'),
    ('20260803161707', 'dynamic_row_correction_batch_v3_hardening',
      '32a0cbe49cc93e06edc0dc5149d16a0728266bba94da9a6c141dd3caf816b5f6'),
    ('20260803162112', 'dynamic_row_correction_batch_v4_hardening',
      '35e0a3654eae797dfa372f513f3f052af0407e0ccf2d32d229e5703d84642d48'),
    ('20260803162702', 'dynamic_row_correction_batch_v5_hardening',
      '300bf8879b3577e2179a18f2294cd88a777b49ee68c9d6430a3f4eedf8d82e37'),
    ('20260803163038', 'dynamic_row_correction_batch_v6_hardening',
      '5fdfa3f824765f8fd7ff7203212c9e4a6103f705cdec25845569cdae5dcba0a9'),
    ('20260803163430', 'dynamic_row_correction_batch_v7_hardening',
      '859e18440317494eb3936fd80c136a8b8fb2e7b2604141bcf58048aeaf604365')
), migration_checks as (
  select expected.version, expected.name, expected.sha256,
    migration.version is not null as installed,
    migration.name = expected.name as name_matches,
    migration.statements @> array['migration_sha256=' || expected.sha256]
      as sha_matches
  from expected_migrations expected
  left join supabase_migrations.schema_migrations migration
    on migration.version = expected.version
), current_bundle as (
  select bundle.release_id, bundle.season,
    release.release_label,
    analysis.row_correction_bundle_hash_v1(bundle.release_id)
      as bundle_sha256
  from reporting.latest_approved_dashboard_bundle_v4 bundle
  join reporting.aggregate_releases release on release.id = bundle.release_id
), batch_counts as (
  select
    (select count(*) from audit.correction_batches_v3) as batches,
    (select count(*) from audit.correction_batch_items_v3) as items,
    (select count(*) from processing.correction_batch_versions_v3) as versions
), pending_sets as (
  select count(*) as count
  from audit.correction_sets_v1 correction_set
  where not exists (
    select 1 from reporting.correction_release_context_v1 released
    where released.correction_set_id = correction_set.id
  )
), reader_counts as (
  select
    (select count(*) from reporting.latest_team_dashboard_v5) as teams,
    (select count(*) from reporting.latest_league_dashboard_v5) as leagues,
    (select count(*) from reporting.latest_dashboard_cache_token_v1) as tokens
)
select jsonb_build_object(
  'migrations', (
    select jsonb_agg(to_jsonb(migration_checks) order by version)
    from migration_checks
  ),
  'all_migrations_exact', (
    select bool_and(installed and name_matches and sha_matches)
    from migration_checks
  ),
  'latest_objects_exist', jsonb_build_object(
    'preview_v5', to_regprocedure('analysis.row_correction_preview_v5(jsonb)') is not null,
    'apply_v8', to_regprocedure('audit.apply_row_correction_batch_v8(jsonb,jsonb,text)') is not null,
    'promote_v8', to_regprocedure('reporting.promote_row_correction_batch_v8(text,text,text)') is not null
  ),
  'web_reader_boundary', jsonb_build_object(
    'can_select_cache_token', has_table_privilege(
      'web_reader', 'reporting.latest_dashboard_cache_token_v1', 'SELECT'),
    'can_select_batch_audit', has_table_privilege(
      'web_reader', 'audit.correction_batches_v3', 'SELECT'),
    'can_apply_batch', has_function_privilege(
      'web_reader', 'audit.apply_row_correction_batch_v8(jsonb,jsonb,text)', 'EXECUTE')
  ),
  'retained_batch_rows', to_jsonb(batch_counts),
  'pending_correction_sets', pending_sets.count,
  'reader_counts', to_jsonb(reader_counts),
  'current_bundle', to_jsonb(current_bundle)
) as verification
from batch_counts, pending_sets, reader_counts, current_bundle;
