-- Correct V5 dashboard coverage fields to use the accepted effective cohort.
--
-- The original V5 payload successor replaced hours and headline metrics but
-- retained several coverage counters from the V4 payload. These additive
-- snapshots compute every cohort-derived coverage field once from the shared,
-- build-pinned V5 exposure snapshot and patch only the coverage object. All
-- other payload sections remain byte-equivalent as jsonb values.

set transaction isolation level repeatable read;

create materialized view
  analysis.analysis_window_team_coverage_v5_snapshot as
with member_exposure as (
  select
    e.curated_build_id,
    e.team_key,
    e.season,
    e.reporting_grain,
    e.effective_period_start,
    e.effective_period_end,
    e.minutes_clean,
    e.distance_m_clean,
    e.scope_status,
    source.player_uid
  from analysis.analysis_window_effective_exposure_cohort_v5_snapshot e
  join analysis.league_member_releases_v2 member
    using (curated_build_id, team_key, season)
  join curated.exposure source on source.id = e.exposure_id
  where e.effective_eligibility_status = 'included_pending_protocol'
), scope_counts as (
  select team_key, season, curated_build_id,
    jsonb_object_agg(scope_status, exposure_rows order by scope_status)
      as scope_status_counts
  from (
    select team_key, season, curated_build_id, scope_status,
      count(*) as exposure_rows
    from member_exposure
    where scope_status is not null
    group by team_key, season, curated_build_id, scope_status
  ) grouped
  group by team_key, season, curated_build_id
)
select
  exposure.curated_build_id,
  exposure.team_key,
  exposure.season,
  count(*) as exposure_rows,
  count(distinct nullif(exposure.player_uid, '')) as exposed_players,
  count(distinct case
    when exposure.reporting_grain = 'weekly'
      then exposure.effective_period_start
  end) as weeks,
  count(distinct exposure.effective_period_start) as exposure_periods,
  coalesce(sum(exposure.minutes_clean), 0) / 60 as exposure_hours,
  coalesce(sum(exposure.distance_m_clean), 0) / 1000 as distance_km,
  min(exposure.effective_period_start) as coverage_start,
  max(exposure.effective_period_end) as coverage_end,
  case when count(distinct exposure.reporting_grain) = 1
    then min(exposure.reporting_grain) else 'mixed' end as exposure_grain,
  coalesce(scope.scope_status_counts, '{}'::jsonb) as scope_status_counts,
  window.season_start as analysis_window_start,
  window.season_end as analysis_window_end
from member_exposure exposure
join analysis.reporting_season_windows_v3 window
  on window.season = exposure.season
 and window.cohort_view_version =
   'analysis_window_2024-25_2026-07-25_v1'
left join scope_counts scope
  using (curated_build_id, team_key, season)
group by exposure.curated_build_id, exposure.team_key, exposure.season,
  scope.scope_status_counts, window.season_start, window.season_end;

create unique index analysis_window_team_coverage_v5_snapshot_key
  on analysis.analysis_window_team_coverage_v5_snapshot
  (team_key, season, curated_build_id);

create materialized view
  analysis.analysis_window_league_coverage_v5_snapshot as
with coverage_windows as (
  select season,
    jsonb_agg(jsonb_build_object(
      'start', coverage_start,
      'end', coverage_end,
      'teams', teams
    ) order by coverage_start, coverage_end) as windows
  from (
    select season, coverage_start, coverage_end, count(*) as teams
    from analysis.analysis_window_team_coverage_v5_snapshot
    group by season, coverage_start, coverage_end
  ) grouped
  group by season
)
select
  team.season,
  count(*)::integer as teams_included,
  sum(team.exposure_rows) as exposure_rows,
  sum(team.exposed_players) as exposed_players,
  sum(team.weeks) as weeks,
  sum(team.exposure_periods) as exposure_periods,
  sum(team.exposure_hours) as exposure_hours,
  sum(team.distance_km) as distance_km,
  case when count(distinct team.exposure_grain) = 1
    then min(team.exposure_grain) else 'mixed' end as exposure_grain,
  windows.windows as coverage_windows,
  min(team.analysis_window_start) as analysis_window_start,
  max(team.analysis_window_end) as analysis_window_end
from analysis.analysis_window_team_coverage_v5_snapshot team
join coverage_windows windows using (season)
group by team.season, windows.windows;

create unique index analysis_window_league_coverage_v5_snapshot_key
  on analysis.analysis_window_league_coverage_v5_snapshot (season);

create materialized view
  analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot as
select
  candidate.team_key,
  candidate.season,
  candidate.team_release_id,
  candidate.curated_build_id,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version,
  candidate.cohort_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'coverage',
    coalesce(candidate.dashboard -> 'coverage', '{}'::jsonb)
      || jsonb_build_object(
        'exposure_rows', coverage.exposure_rows,
        'exposed_players', coverage.exposed_players,
        'weeks', coverage.weeks,
        'exposure_periods', coverage.exposure_periods,
        'exposure_grain', coverage.exposure_grain,
        'hours', coverage.exposure_hours,
        'distance_km', coverage.distance_km,
        'scope_status_counts', coverage.scope_status_counts,
        'included_exposure_status', 'included',
        'analysis_window_start', coverage.analysis_window_start,
        'analysis_window_end', coverage.analysis_window_end
      )
  ) as dashboard
from analysis.team_dashboard_payload_analysis_window_v5_snapshot candidate
join analysis.analysis_window_team_coverage_v5_snapshot coverage
  using (curated_build_id, team_key, season);

create unique index
  team_dashboard_payload_analysis_window_v5_coverage_snapshot_key
  on analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot
  (team_key, season);

create materialized view
  analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot as
select
  candidate.season,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version,
  candidate.cohort_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'coverage',
    coalesce(candidate.dashboard -> 'coverage', '{}'::jsonb)
      || jsonb_build_object(
        'exposure_rows', coverage.exposure_rows,
        'exposed_players', coverage.exposed_players,
        'weeks', coverage.weeks,
        'exposure_periods', coverage.exposure_periods,
        'exposure_grain', coverage.exposure_grain,
        'hours', coverage.exposure_hours,
        'distance_km', coverage.distance_km,
        'teams_included', coverage.teams_included,
        'coverage_windows', coverage.coverage_windows,
        'included_exposure_status', 'included',
        'analysis_window_start', coverage.analysis_window_start,
        'analysis_window_end', coverage.analysis_window_end
      )
  ) as dashboard
from analysis.league_dashboard_payload_analysis_window_v5_snapshot candidate
join analysis.analysis_window_league_coverage_v5_snapshot coverage
  using (season);

create unique index
  league_dashboard_payload_analysis_window_v5_coverage_snapshot_key
  on analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot
  (season);

do $$
begin
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
    raise exception 'V5 coverage snapshots require 16 teams and one league row';
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
    raise exception 'V5 coverage correction changed a non-coverage payload section';
  end if;

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
  ) or (
    select sum(exposure_hours)
    from analysis.analysis_window_team_coverage_v5_snapshot
    where season = '2024-25'
  ) <> (
    select exposure_hours
    from analysis.analysis_window_league_coverage_v5_snapshot
    where season = '2024-25'
  ) then
    raise exception 'V5 coverage snapshots do not reconcile to the effective cohort';
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

  if exists (
    select 1
    from analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot
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
    from analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot
    where season = '2024-25'
      and (
        classification_view_version <>
          'reporting_classification_2026-07-22_v2'
        or cohort_view_version <>
          'analysis_window_2024-25_2026-07-25_v1'
        or dashboard is null
      )
  ) then
    raise exception 'V5 coverage snapshots do not match the approved tuple';
  end if;
end;
$$;

create or replace view
  analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id,
  'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot;

create or replace view
  analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, 'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot;

comment on materialized view
  analysis.analysis_window_team_coverage_v5_snapshot is
  'Build-pinned V5 team coverage derived once from the effective exposure cohort.';
comment on materialized view
  analysis.analysis_window_league_coverage_v5_snapshot is
  'Pooled V5 league coverage derived from the 16 build-pinned team coverage rows.';
comment on materialized view
  analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot is
  'V5 team candidates with all cohort-derived coverage fields corrected; non-coverage sections are unchanged.';
comment on materialized view
  analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot is
  'V5 league candidate with all cohort-derived coverage fields corrected; non-coverage sections are unchanged.';
