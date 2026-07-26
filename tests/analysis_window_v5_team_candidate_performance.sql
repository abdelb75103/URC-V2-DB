-- Team candidate timing contract. This is separate from the league query so
-- the same two payload families are not forced through one duplicate gate.
set local statement_timeout = '5min';

with started as materialized (
  select clock_timestamp() as started_at
), payload as materialized (
  select
    candidate.team_key,
    octet_length(candidate.dashboard::text) as dashboard_bytes,
    started.started_at
  from analysis.team_dashboard_release_candidates_analysis_window_v5 candidate
  cross join started
  where candidate.season = '2024-25'
    and candidate.analysis_version = 'v5'
    and candidate.classification_view_version =
      'reporting_classification_2026-07-22_v2'
    and candidate.cohort_view_version =
      'analysis_window_2024-25_2026-07-25_v1'
), completed as materialized (
  select
    count(*)::integer as candidate_count,
    sum(dashboard_bytes)::bigint as dashboard_bytes,
    min(started_at) as started_at,
    clock_timestamp() as completed_at
  from payload
)
select
  candidate_count,
  dashboard_bytes,
  round(extract(epoch from (completed_at - started_at)) * 1000, 3)
    as elapsed_ms,
  candidate_count = 16
    and coalesce(dashboard_bytes, 0) > 0
    as candidate_payload_passed
from completed;
