-- Register only the complete private Year 2 reporting-key correction.

do $$
begin
  if to_regclass(
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys'
    ) is null
    or to_regprocedure(
      'analysis.injury_type_families_from_payload_v2(jsonb)'
    ) is null
    or (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys
      where snapshot_version = '20260831100000'
        and classification_view_version =
          'reporting_classification_2025-26_2026-08-31_v3'
        and classification_evidence_sha256 =
          'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'
        and cohort_view_version =
          'injury_lineage_2025-26_2026-08-30_v2'
        and injury_lineage_version_id =
          '2f419706-8c36-58dd-b4cb-e92162e782b8'::uuid
        and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
    ) <> 16
    or (
      select count(*)
      from analysis.team_dashboard_release_candidates_analysis_window_v6
      where season = '2025-26'
        and classification_view_version =
          'reporting_classification_2025-26_2026-08-31_v3'
        and injury_lineage_snapshot_version = '20260831100000'
    ) <> 16
    or has_table_privilege(
      'web_reader',
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys',
      'select'
    )
    or has_table_privilege(
      'web_reader',
      'analysis.urc_2025_26_reporting_key_rows_v2',
      'select'
    )
    or has_function_privilege(
      'web_reader',
      'analysis.injury_type_families_from_payload_v2(jsonb)',
      'execute'
    )
  then
    raise exception 'Year 2 reporting-key and family correction is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831100000',
  'urc_2025_26_reporting_key_family_correction',
  array[
    'migration_sha256=36754c640f808db0dc6e27d58135744005a304ba14cb3be7211b11224335b43f',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
    'classification_evidence_sha256=d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172',
    'candidate_snapshot_version=20260831100000'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831100000'
      and name = 'urc_2025_26_reporting_key_family_correction'
      and statements = array[
        'migration_sha256=36754c640f808db0dc6e27d58135744005a304ba14cb3be7211b11224335b43f',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
        'classification_evidence_sha256=d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172',
        'candidate_snapshot_version=20260831100000'
      ]
  ) then
    raise exception 'Year 2 reporting-key and family correction registration is invalid';
  end if;
end;
$$;
