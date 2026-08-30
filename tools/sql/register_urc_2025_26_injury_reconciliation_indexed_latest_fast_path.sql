-- Register only the reviewed indexed-latest reconciliation successor.

do $$
declare
  reconciliation_definition text;
  candidate_definition text;
begin
  if to_regclass(
      'analysis.urc_2025_26_injury_cohort_reconciliation_v1'
    ) is null
    or to_regclass(
      'analysis.team_dashboard_release_candidates_analysis_window_v6'
    ) is null
  then
    raise exception 'URC 2025-26 indexed-latest reconciliation objects are incomplete';
  end if;

  reconciliation_definition := pg_get_viewdef(
    'analysis.urc_2025_26_injury_cohort_reconciliation_v1'::regclass,
    true
  );
  candidate_definition := pg_get_viewdef(
    'analysis.team_dashboard_release_candidates_analysis_window_v6'::regclass,
    true
  );

  if position('injury_source_rows' in reconciliation_definition) = 0
    or position('lateral' in reconciliation_definition) = 0
    or position('order by rv.version_number desc' in reconciliation_definition) = 0
    or position('processing_counts' in reconciliation_definition) = 0
    or position('eligible_counts' in reconciliation_definition) = 0
    or position('recorded_counts' in reconciliation_definition) = 0
  then
    raise exception 'URC 2025-26 reconciliation is not indexed-latest';
  end if;

  if position(
      'analysis.urc_2025_26_injury_cohort_reconciliation_v1'
      in candidate_definition
    ) = 0
    or position('reconciliation.release_ready' in candidate_definition) = 0
  then
    raise exception 'URC 2025-26 candidate is not fail-closed on reconciliation';
  end if;

  if (
    select count(*)
    from information_schema.columns column_row
    where column_row.table_schema = 'analysis'
      and column_row.table_name =
        'team_dashboard_release_candidates_analysis_window_v6'
      and column_row.column_name in (
        'processing_eligible_injury_count',
        'eligible_curated_injury_count',
        'recorded_cohort_count',
        'processing_record_version_set_sha256',
        'curated_record_version_set_sha256',
        'reporting_record_version_set_sha256',
        'approved_injury_source_file_count',
        'unapproved_injury_source_row_count',
        'wrong_problem_type_rule_version_count'
      )
  ) <> 9 then
    raise exception 'URC 2025-26 candidate reconciliation projection is incomplete';
  end if;

  if has_table_privilege(
      'web_reader',
      'analysis.urc_2025_26_injury_cohort_reconciliation_v1',
      'select'
    )
    or has_table_privilege(
      'web_reader',
      'analysis.team_dashboard_release_candidates_analysis_window_v6',
      'select'
    )
  then
    raise exception 'URC 2025-26 indexed-latest reconciliation is not least-privilege';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260823186000',
  'urc_2025_26_injury_reconciliation_indexed_latest_fast_path',
  array['migration_sha256=1e8e4dd1cbbda3ec1f2b088148d21c963f26bbc916619aca17e93f6028f4e1ca']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260823186000'
      and migration.name =
        'urc_2025_26_injury_reconciliation_indexed_latest_fast_path'
      and migration.statements = array[
        'migration_sha256=1e8e4dd1cbbda3ec1f2b088148d21c963f26bbc916619aca17e93f6028f4e1ca'
      ]
  ) then
    raise exception 'URC 2025-26 indexed-latest reconciliation registration is absent or checksum-mismatched';
  end if;
end;
$$;
