do $$
begin
  if to_regclass(
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260831122000'
    ) is null
    or (
      select count(*)
      from analysis.league_dashboard_release_candidate_snapshot_v6_20260831122000
      where snapshot_version = '20260831122000'
        and member_count = 16
        and jsonb_array_length(member_manifest) = 16
        and classification_view_version =
          'reporting_classification_2025-26_2026-08-31_v3'
        and cohort_view_version =
          'injury_lineage_2025-26_2026-08-31_v3'
        and cohort_evidence_sha256 =
          'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450'
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
          'injury_lineage_2025-26_2026-08-31_v3'
    ) <> 1
    or has_table_privilege(
      'web_reader',
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260831122000',
      'select'
    )
    or to_regclass('analysis.accepted_release_contracts_v4') is null
  then
    raise exception 'Welsh fixture league candidate snapshot is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831122000',
  'urc_2025_26_welsh_fixture_league_candidate_snapshot',
  array[
    'migration_sha256=11b7099a980301e3038541804ce2fbc0f4cafdde5c2ff1c446ca69a1dc0f7eaf',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
    'cohort_evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
    'team_member_count=16',
    'candidate_snapshot_version=20260831122000',
    'release_contract_table=analysis.accepted_release_contracts_v4',
    'corrected_teams=cardiff,dragons',
    'retained_team_count=14'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831122000'
      and name = 'urc_2025_26_welsh_fixture_league_candidate_snapshot'
      and statements = array[
        'migration_sha256=11b7099a980301e3038541804ce2fbc0f4cafdde5c2ff1c446ca69a1dc0f7eaf',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
        'cohort_evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
        'team_member_count=16',
        'candidate_snapshot_version=20260831122000',
        'release_contract_table=analysis.accepted_release_contracts_v4',
        'corrected_teams=cardiff,dragons',
        'retained_team_count=14'
      ]
  ) then
    raise exception 'Welsh fixture league candidate snapshot registration is invalid';
  end if;
end;
$$;
