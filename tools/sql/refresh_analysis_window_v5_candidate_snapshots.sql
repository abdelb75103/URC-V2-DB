set transaction isolation level repeatable read;

refresh materialized view
  analysis.analysis_window_injury_cohort_v5_snapshot;
refresh materialized view
  analysis.analysis_window_reporting_classification_v5_snapshot;
refresh materialized view
  analysis.analysis_window_effective_exposure_cohort_v5_snapshot;
refresh materialized view
  analysis.team_dashboard_payload_analysis_window_v5_snapshot;
refresh materialized view
  analysis.league_dashboard_payload_analysis_window_v5_snapshot;

do $$
begin
  if (
    select count(*)
    from analysis.team_dashboard_payload_analysis_window_v5_snapshot
    where season = '2024-25'
  ) <> 16 then
    raise exception 'V5 team candidate snapshot must contain exactly 16 teams';
  end if;
  if (
    select count(*)
    from analysis.league_dashboard_payload_analysis_window_v5_snapshot
    where season = '2024-25'
  ) <> 1 then
    raise exception 'V5 league candidate snapshot must contain exactly one row';
  end if;
  if exists (
    select 1
    from analysis.team_dashboard_payload_analysis_window_v5_snapshot snapshot
    full join analysis.league_member_releases_v2 member
      using (team_key, season, team_release_id, curated_build_id)
    where coalesce(snapshot.season, member.season) = '2024-25'
      and (snapshot.team_key is null or member.team_key is null)
  ) then
    raise exception 'V5 team candidate snapshot member identities do not match the approved roster';
  end if;
  if exists (
    select 1
    from analysis.team_dashboard_payload_analysis_window_v5_snapshot
    where season = '2024-25'
      and (
        classification_view_version <>
          'reporting_classification_2026-07-22_v2'
        or cohort_view_version <>
          'analysis_window_2024-25_2026-07-25_v1'
        or dashboard is null
      )
  ) or exists (
    select 1
    from analysis.league_dashboard_payload_analysis_window_v5_snapshot
    where season = '2024-25'
      and (
        classification_view_version <>
          'reporting_classification_2026-07-22_v2'
        or cohort_view_version <>
          'analysis_window_2024-25_2026-07-25_v1'
        or dashboard is null
      )
  ) then
    raise exception 'V5 candidate snapshots do not match the approved tuple';
  end if;
end;
$$;
