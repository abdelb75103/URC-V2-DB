do $$
begin
  if to_regclass(
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture'
    ) is null
    or to_regclass('analysis.accepted_release_contracts_v3') is null
    or (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture
    ) <> 16
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
    ) <> 1545
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss
    ) <> 938
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss and days_lost is not null
    ) <> 782
    or (
      select coalesce(sum(days_lost), 0)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss
    ) <> 20665
    or not analysis.release_contract_candidates_available_v1(
      '2025-26', 'v6',
      'reporting_classification_2025-26_2026-08-31_v3',
      'injury_lineage_2025-26_2026-08-31_v3'
    )
    or has_table_privilege(
      'web_reader',
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture',
      'select'
    )
    or has_table_privilege(
      'web_reader', 'analysis.accepted_release_contracts_v3', 'select'
    )
  then
    raise exception 'Year 2 Welsh fixture candidate successor is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831121000',
  'urc_2025_26_welsh_fixture_candidate_successor',
  array[
    'migration_sha256=b2627d530759579077af62ebc65be2cc6707ceb6cd946461dc3f97c96c1e0474',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
    'cohort_evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
    'candidate_snapshot_version=20260831121000',
    'changed_teams=cardiff,dragons',
    'unchanged_team_count=14'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831121000'
      and name = 'urc_2025_26_welsh_fixture_candidate_successor'
      and statements = array[
        'migration_sha256=b2627d530759579077af62ebc65be2cc6707ceb6cd946461dc3f97c96c1e0474',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
        'cohort_evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
        'candidate_snapshot_version=20260831121000',
        'changed_teams=cardiff,dragons',
        'unchanged_team_count=14'
      ]
  ) then
    raise exception 'Year 2 Welsh fixture candidate successor registration is invalid';
  end if;
end;
$$;
