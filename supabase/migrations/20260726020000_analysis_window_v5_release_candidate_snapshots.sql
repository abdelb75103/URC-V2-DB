-- Build-pinned V5 release candidate snapshots.
--
-- The scientific views remain dynamic. These materialised views cache the
-- exact reviewed candidate payloads once so preflight, promotion and trigger
-- equality checks do not reconstruct the same JSON repeatedly.

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
