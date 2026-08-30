-- Register only the reviewed reconciliation performance successor. Object,
-- definition and least-privilege checks precede the exact migration row.

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
    raise exception 'URC 2025-26 injury reconciliation fast-path objects are incomplete';
  end if;

  reconciliation_definition := pg_get_viewdef(
    'analysis.urc_2025_26_injury_cohort_reconciliation_v1'::regclass,
    true
  );
  candidate_definition := pg_get_viewdef(
    'analysis.team_dashboard_release_candidates_analysis_window_v6'::regclass,
    true
  );

  if position(
      'analysis.analysis_window_team_summary_v6'
      in reconciliation_definition
    ) = 0
    or position(
      'team_dashboard_payload_analysis_window_v6'
      in reconciliation_definition
    ) <> 0
  then
    raise exception 'URC 2025-26 reconciliation still rebuilds a dashboard payload';
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
    raise exception 'URC 2025-26 reconciliation fast path is not least-privilege';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260823160000',
  'urc_2025_26_injury_reconciliation_fast_path',
  array['migration_sha256=fa29bc55ea18806be789dba3d9df384d343b5d79876f8acef780a382a1808d87']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260823160000'
      and migration.name = 'urc_2025_26_injury_reconciliation_fast_path'
      and migration.statements = array[
        'migration_sha256=fa29bc55ea18806be789dba3d9df384d343b5d79876f8acef780a382a1808d87'
      ]
  ) then
    raise exception 'URC 2025-26 injury reconciliation fast-path registration is absent or checksum-mismatched';
  end if;
end;
$$;
