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
refresh materialized view
  analysis.analysis_window_team_coverage_v5_snapshot;
refresh materialized view
  analysis.analysis_window_league_coverage_v5_snapshot;
refresh materialized view
  analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot;
refresh materialized view
  analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot;
-- The candidate views read from the contact snapshots, so these must refresh
-- after the coverage layer they inherit from. Omitting them would leave the
-- published payload silently stale.
refresh materialized view
  analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot;
refresh materialized view
  analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot;

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
  if (
    select count(*)
    from analysis.analysis_window_team_coverage_v5_snapshot
    where season = '2024-25'
  ) <> 16 or (
    select count(*)
    from analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot
    where season = '2024-25'
  ) <> 16 or (
    select count(*)
    from analysis.analysis_window_league_coverage_v5_snapshot
    where season = '2024-25'
  ) <> 1 or (
    select count(*)
    from analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot
    where season = '2024-25'
  ) <> 1 then
    raise exception 'V5 corrected coverage snapshots are incomplete';
  end if;
  if (
    select count(*)
    from analysis.analysis_window_injury_cohort_v5_snapshot
  ) <> (
    select count(*)
    from analysis.analysis_window_reporting_classification_v5_snapshot
  ) or exists (
    select 1
    from analysis.analysis_window_injury_cohort_v5_snapshot injury
    left join analysis.analysis_window_reporting_classification_v5_snapshot
      classification
      using (injury_id, curated_build_id, team_key, season)
    where classification.injury_id is null
  ) or exists (
    select 1
    from analysis.analysis_window_reporting_classification_v5_snapshot
    group by injury_id, curated_build_id, team_key, season
    having count(*) <> 1
  ) then
    raise exception 'V5 shared injury and classification snapshots do not reconcile';
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
  if exists (
    select 1
    from analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot
      corrected
    join analysis.team_dashboard_payload_analysis_window_v5_snapshot original
      using (team_key, season, team_release_id, curated_build_id)
    where corrected.dashboard - 'coverage' <>
      original.dashboard - 'coverage'
  ) or exists (
    select 1
    from analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot
      corrected
    join analysis.league_dashboard_payload_analysis_window_v5_snapshot original
      using (season)
    where corrected.dashboard - 'coverage' <>
      original.dashboard - 'coverage'
  ) then
    raise exception 'V5 coverage refresh changed a non-coverage payload section';
  end if;
  -- The refreshed contact snapshots must satisfy the SAME suite the creating
  -- migration proved, not a weaker subset: a refresh replaces their contents,
  -- so a stale or shifted cohort could otherwise pass row counts while serving
  -- different published numbers. One shared definition, so the two cannot
  -- drift apart.
  perform analysis.assert_contact_distribution_v5_integrity();
  if (
    select sum(exposure_rows)
    from analysis.analysis_window_team_coverage_v5_snapshot
    where season = '2024-25'
  ) <> (
    select count(*)
    from analysis.analysis_window_effective_exposure_cohort_v5_snapshot exposure
    join analysis.league_member_releases_v2 member
      using (curated_build_id, team_key, season)
    where exposure.season = '2024-25'
      and exposure.effective_eligibility_status =
        'included_pending_protocol'
  ) then
    raise exception 'V5 coverage refresh does not reconcile to the effective cohort';
  end if;
  if exists (
    select 1
    from analysis.analysis_window_team_coverage_v5_snapshot coverage
    join analysis.team_dashboard_payload_analysis_window_v5_snapshot original
      using (curated_build_id, team_key, season)
    cross join lateral (
      select
        max((headline ->> 'denominator')::numeric)
          filter (where headline ->> 'key' = 'incidence_per_1000h')
          as incidence_denominator,
        max((headline ->> 'denominator')::numeric)
          filter (where headline ->> 'key' = 'burden_per_1000h')
          as burden_denominator
      from jsonb_array_elements(original.dashboard -> 'headline') headline
    ) denominators
    where coverage.season = '2024-25'
      and (
        coverage.exposure_hours <>
          (original.dashboard -> 'coverage' ->> 'hours')::numeric
        or coverage.exposure_hours <> denominators.incidence_denominator
        or coverage.exposure_hours <> denominators.burden_denominator
      )
  ) or exists (
    select 1
    from analysis.analysis_window_league_coverage_v5_snapshot coverage
    join analysis.league_dashboard_payload_analysis_window_v5_snapshot original
      using (season)
    cross join lateral (
      select
        max((headline ->> 'denominator')::numeric)
          filter (where headline ->> 'key' = 'incidence_per_1000h')
          as incidence_denominator,
        max((headline ->> 'denominator')::numeric)
          filter (where headline ->> 'key' = 'burden_per_1000h')
          as burden_denominator
      from jsonb_array_elements(original.dashboard -> 'headline') headline
    ) denominators
    where coverage.season = '2024-25'
      and (
        coverage.exposure_hours <>
          (original.dashboard -> 'coverage' ->> 'hours')::numeric
        or coverage.exposure_hours <> denominators.incidence_denominator
        or coverage.exposure_hours <> denominators.burden_denominator
      )
  ) then
    raise exception 'V5 coverage hours do not match the headline denominators';
  end if;
end;
$$;
