do $$
begin
  if to_regclass(
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract'
    ) is null
    or to_regprocedure(
      'analysis.injury_type_families_from_payload_v3(jsonb)'
    ) is null
    or (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract
      where snapshot_version = '20260831101000'
        and classification_view_version =
          'reporting_classification_2025-26_2026-08-31_v3'
        and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
    ) <> 16
    or (
      select count(*)
      from analysis.team_dashboard_release_candidates_analysis_window_v6
      where season = '2025-26'
        and injury_lineage_snapshot_version = '20260831101000'
    ) <> 16
    or has_table_privilege(
      'web_reader',
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract',
      'select'
    )
    or has_function_privilege(
      'web_reader',
      'analysis.injury_type_families_from_payload_v3(jsonb)',
      'execute'
    )
  then
    raise exception 'Year 2 family mapping contract correction is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831101000',
  'urc_2025_26_family_mapping_contract_correction',
  array[
    'migration_sha256=a711d6bdd4af0618c2adafb6b30ca7be03f5251150db799bc43915b62e3fd39f',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
    'classification_evidence_sha256=d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172',
    'candidate_snapshot_version=20260831101000',
    'family_mapping_version=injury_type_family_2026-07-21_v1'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831101000'
      and name = 'urc_2025_26_family_mapping_contract_correction'
      and statements = array[
        'migration_sha256=a711d6bdd4af0618c2adafb6b30ca7be03f5251150db799bc43915b62e3fd39f',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
        'classification_evidence_sha256=d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172',
        'candidate_snapshot_version=20260831101000',
        'family_mapping_version=injury_type_family_2026-07-21_v1'
      ]
  ) then
    raise exception 'Year 2 family mapping contract correction registration is invalid';
  end if;
end;
$$;
