-- Combined wall-clock contract for the two direct V5 candidate views.
-- The runbook threshold is 120,000 ms on the configured live pooler.
with started as materialized (
  select clock_timestamp() as started_at
), league as materialized (
  select
    candidate.season,
    octet_length(candidate.dashboard::text) as dashboard_bytes,
    started.started_at
  from analysis.league_dashboard_release_candidates_analysis_window_v5 candidate
  cross join started
  where candidate.season = '2024-25'
    and candidate.analysis_version = 'v5'
    and candidate.classification_view_version =
      'reporting_classification_2026-07-22_v2'
    and candidate.cohort_view_version =
      'analysis_window_2024-25_2026-07-25_v1'
), teams as materialized (
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
), payload_aggregate as materialized (
  select
    (select count(*) from league)::integer as league_candidate_count,
    (select count(*) from teams)::integer as team_candidate_count,
    (select sum(dashboard_bytes) from league)::bigint
      as league_dashboard_bytes,
    (select sum(dashboard_bytes) from teams)::bigint
      as team_dashboard_bytes
), completed as materialized (
  select
    payload_aggregate.*,
    (select started_at from started) as started_at,
    clock_timestamp() as completed_at
  from payload_aggregate
)
select
  league_candidate_count,
  team_candidate_count,
  league_dashboard_bytes,
  team_dashboard_bytes,
  round(
    extract(epoch from (completed_at - started_at)) * 1000,
    3
  ) as elapsed_ms,
  league_candidate_count = 1
    and team_candidate_count = 16
    and coalesce(league_dashboard_bytes, 0) > 0
    and coalesce(team_dashboard_bytes, 0) > 0
    as candidate_payloads_passed
from completed;
