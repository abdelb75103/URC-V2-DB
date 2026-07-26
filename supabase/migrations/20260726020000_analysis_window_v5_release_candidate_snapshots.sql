-- Build-pinned V5 release candidate snapshots.
--
-- The scientific views remain dynamic. These materialised views cache the
-- exact reviewed candidate payloads once so preflight, promotion and trigger
-- equality checks do not reconstruct the same JSON repeatedly.

set transaction isolation level repeatable read;

refresh materialized view
  analysis.analysis_window_injury_cohort_v5_snapshot;
refresh materialized view
  analysis.analysis_window_reporting_classification_v5_snapshot;
refresh materialized view
  analysis.analysis_window_effective_exposure_cohort_v5_snapshot;

create materialized view analysis.team_dashboard_payload_analysis_window_v5_snapshot as
select *
from analysis.team_dashboard_payload_analysis_window_v5;

create unique index team_dashboard_payload_analysis_window_v5_snapshot_key
  on analysis.team_dashboard_payload_analysis_window_v5_snapshot
  (team_key, season);

create materialized view analysis.league_dashboard_payload_analysis_window_v5_snapshot as
select *
from analysis.league_dashboard_payload_analysis_window_v5;

create unique index league_dashboard_payload_analysis_window_v5_snapshot_key
  on analysis.league_dashboard_payload_analysis_window_v5_snapshot
  (season);

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
end;
$$;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id,
  'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_analysis_window_v5_snapshot;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, 'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_analysis_window_v5_snapshot;

comment on materialized view analysis.team_dashboard_payload_analysis_window_v5_snapshot is
  'Exact build-pinned V5 team candidate payloads. Refresh only after the dynamic V5 views have passed reconciliation and before preflight.';
comment on materialized view analysis.league_dashboard_payload_analysis_window_v5_snapshot is
  'Exact build-pinned V5 league candidate payload. Refresh only after the dynamic V5 views have passed reconciliation and before preflight.';
comment on view analysis.team_dashboard_release_candidates_analysis_window_v5 is
  'Direct V5 candidate path over the reviewed build-pinned team payload snapshot.';
comment on view analysis.league_dashboard_release_candidates_analysis_window_v5 is
  'Direct V5 candidate path over the reviewed build-pinned league payload snapshot.';
