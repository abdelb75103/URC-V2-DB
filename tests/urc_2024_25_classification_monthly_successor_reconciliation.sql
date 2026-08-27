-- Read-only local reconciliation for the additive 2024-25 successor.
-- Run only against an explicitly approved local candidate database. This file
-- is not a deployment or promotion step and emits no row-level identifiers.

with predecessor as (
  select
    (payload.dashboard_payload -> 'headline' -> 0 ->> 'value')::bigint
      as recorded_injuries,
    (payload.dashboard_payload -> 'headline' -> 1 ->> 'value')::bigint
      as time_loss_injuries,
    (select (item ->> 'numerator')::numeric
     from jsonb_array_elements(payload.dashboard_payload -> 'headline') item
     where item ->> 'key' = 'severity_mean_days') as days_lost
  from reporting.dashboard_bundle_league_payloads_v1 payload
  where payload.release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
), successor as (
  select
    (candidate.dashboard -> 'headline' -> 0 ->> 'value')::bigint
      as recorded_injuries,
    (candidate.dashboard -> 'headline' -> 1 ->> 'value')::bigint
      as time_loss_injuries,
    (select (item ->> 'numerator')::numeric
     from jsonb_array_elements(candidate.dashboard -> 'headline') item
     where item ->> 'key' = 'severity_mean_days') as days_lost
  from analysis.urc_2024_25_league_dashboard_candidate_v1 candidate
), source_reported_null_duration as (
  select count(*)::bigint as time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 fact
  where fact.source_classification_value in
      ('time loss', 'time_loss', 'timeloss', 'true')
    and fact.days_lost is null
    and not exists (
      select 1
      from audit.urc_2024_25_classification_adjudications_v1 adjudication
      where adjudication.season = fact.season
        and adjudication.source_row = fact.source_row
    )
), monthly as (
  select
    count(*) filter (where fact.date_injured is not null)::bigint
      as dated_recorded_injuries,
    count(*) filter (
      where fact.date_injured is not null
        and fact.final_classification = 'Time Loss'
    )::bigint as dated_time_loss_injuries,
    (select coalesce(sum(monthly.recorded_injuries), 0)::bigint
     from analysis.urc_2024_25_league_monthly_v1 monthly)
      as monthly_recorded_injuries,
    (select coalesce(sum(monthly.time_loss_injuries), 0)::bigint
     from analysis.urc_2024_25_league_monthly_v1 monthly)
      as monthly_time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 fact
), season_totals as (
  select
    count(*) filter (where fact.date_injured is null)::bigint
      as undated_recorded_injuries,
    count(*) filter (
      where fact.date_injured is null
        and fact.final_classification = 'Time Loss'
    )::bigint as undated_time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 fact
), adjudicated as (
  select count(*) filter (
    where adjudication.final_classification = 'Time Loss'
      and fact.days_lost is null
  )::bigint as null_duration_time_loss
  from audit.urc_2024_25_classification_adjudications_v1 adjudication
  join analysis.urc_2024_25_final_injury_classification_v1 fact
    on fact.season = adjudication.season
   and fact.source_row = adjudication.source_row
  where adjudication.season = '2024-25'
), team_totals as (
  select
    coalesce(sum(metrics.recorded_injuries), 0)::bigint
      as recorded_injuries,
    coalesce(sum(metrics.time_loss_injuries), 0)::bigint
      as time_loss_injuries,
    coalesce(sum(metrics.days_lost), 0)::numeric as days_lost
  from analysis.urc_2024_25_team_injury_metrics_v1 metrics
), diagnosis as (
  select
    count(*) filter (where fact.canonical_problem_type = 'injury')::bigint
      as injury_rows,
    count(*) filter (
      where fact.canonical_problem_type = 'injury'
        and fact.final_classification = 'Time Loss'
    )::bigint as injury_time_loss_injuries,
    count(*) filter (
      where fact.canonical_problem_type = 'injury'
        and mapping.source_row is null
    )::bigint as unknown_fallback_rows,
    count(*) filter (where fact.canonical_problem_type <> 'injury'
      and mapping.source_row is not null)::bigint as illness_mapping_rows,
    (select coalesce(sum(profile.time_loss_injuries), 0)::bigint
     from analysis.urc_2024_25_league_profiles_v1 profile
     where profile.dimension = 'diagnosis') as profile_time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 fact
  left join audit.urc_2024_25_specific_diagnosis_mappings_v1 mapping
    on mapping.season = fact.season
   and mapping.source_row = fact.source_row
)
select
  predecessor.recorded_injuries as predecessor_recorded_injuries,
  predecessor.time_loss_injuries as predecessor_time_loss_injuries,
  predecessor.days_lost as predecessor_days_lost,
  successor.recorded_injuries as successor_recorded_injuries,
  successor.time_loss_injuries as successor_time_loss_injuries,
  successor.days_lost as successor_days_lost,
  source_reported_null_duration.time_loss_injuries
    as source_reported_null_duration_time_loss,
  predecessor.recorded_injuries = 1662
    as predecessor_recorded_exact,
  predecessor.time_loss_injuries = 787
    as predecessor_time_loss_exact,
  predecessor.days_lost = 17575
    as predecessor_days_exact,
  source_reported_null_duration.time_loss_injuries = 111
    as source_reported_null_duration_exact,
  adjudicated.null_duration_time_loss
    as adjudicated_null_duration_time_loss,
  adjudicated.null_duration_time_loss = 15
    as adjudicated_null_duration_time_loss_exact,
  successor.recorded_injuries = 1662
    as successor_recorded_exact,
  successor.time_loss_injuries = 913
    as successor_time_loss_exact,
  successor.days_lost = 17575
    as successor_days_exact,
  successor.time_loss_injuries = predecessor.time_loss_injuries
    + source_reported_null_duration.time_loss_injuries
    + adjudicated.null_duration_time_loss
    as time_loss_total_reconciles,
  successor.recorded_injuries = predecessor.recorded_injuries
    as recorded_reconciles,
  successor.days_lost = predecessor.days_lost as observed_days_reconciles,
  team_totals.recorded_injuries = successor.recorded_injuries
    as team_recorded_reconciles,
  team_totals.time_loss_injuries = successor.time_loss_injuries
    as team_time_loss_reconciles,
  team_totals.days_lost = successor.days_lost as team_days_reconciles,
  team_totals.recorded_injuries = 1662 as team_recorded_exact,
  team_totals.time_loss_injuries = 913 as team_time_loss_exact,
  team_totals.days_lost = 17575 as team_days_exact,
  monthly.dated_recorded_injuries = 1656 as dated_recorded_exact,
  monthly.dated_time_loss_injuries = 912 as dated_time_loss_exact,
  season_totals.undated_recorded_injuries = 6 as undated_recorded_exact,
  season_totals.undated_time_loss_injuries = 1 as undated_time_loss_exact,
  monthly.dated_recorded_injuries = monthly.monthly_recorded_injuries
    as monthly_recorded_reconciles,
  monthly.dated_time_loss_injuries = monthly.monthly_time_loss_injuries
    as monthly_time_loss_reconciles,
  diagnosis.unknown_fallback_rows = 4 as diagnosis_unknown_fallback_exact,
  diagnosis.illness_mapping_rows = 0 as diagnosis_excludes_illness,
  diagnosis.profile_time_loss_injuries = diagnosis.injury_time_loss_injuries
    as diagnosis_time_loss_reconciles,
  (select count(*) from analysis.urc_2024_25_team_dashboard_candidate_v1) = 16
    as atomic_team_candidate,
  (select count(*) from analysis.urc_2024_25_league_dashboard_candidate_v1) = 1
    as atomic_league_candidate
from predecessor
cross join successor
cross join source_reported_null_duration
cross join monthly
cross join adjudicated
cross join season_totals
cross join team_totals
cross join diagnosis;
