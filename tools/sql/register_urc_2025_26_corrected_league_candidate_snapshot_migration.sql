do $$
begin
  if to_regclass(
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000'
    ) is null
    or (
      select count(*)
      from analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000
      where snapshot_version = '20260831110000'
        and member_count = 16
        and jsonb_array_length(member_manifest) = 16
        and classification_view_version =
          'reporting_classification_2025-26_2026-08-31_v3'
        and cohort_view_version =
          'injury_lineage_2025-26_2026-08-30_v2'
        and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
        and member_manifest_sha256 =
          reporting.canonical_jsonb_sha256_v1(member_manifest)
    ) <> 1
    or (
      select count(*)
      from analysis.league_dashboard_release_candidates_analysis_window_v6
      where season = '2025-26'
        and analysis_version = 'v6'
        and classification_view_version =
          'reporting_classification_2025-26_2026-08-31_v3'
        and cohort_view_version =
          'injury_lineage_2025-26_2026-08-30_v2'
    ) <> 1
    or has_table_privilege(
      'web_reader',
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000',
      'select'
    )
  then
    raise exception 'Corrected Year 2 league candidate snapshot is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831110000',
  'urc_2025_26_corrected_league_candidate_snapshot',
  array[
    'migration_sha256=9175bf77c27196193374e45a01f2ec3290a7a4ac6da3e66dfd0d97cbb6b40845',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
    'team_member_count=16',
    'candidate_snapshot_version=20260831110000'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831110000'
      and name = 'urc_2025_26_corrected_league_candidate_snapshot'
      and statements = array[
        'migration_sha256=9175bf77c27196193374e45a01f2ec3290a7a4ac6da3e66dfd0d97cbb6b40845',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
        'team_member_count=16',
        'candidate_snapshot_version=20260831110000'
      ]
  ) then
    raise exception 'Corrected Year 2 league candidate snapshot registration is invalid';
  end if;
end;
$$;
