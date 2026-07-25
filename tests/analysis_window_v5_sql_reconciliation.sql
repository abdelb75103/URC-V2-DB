-- Read-only post-migration contract. Run only against the explicitly approved
-- hosted target after applying 20260725190000, never as part of a browser or
-- deployment workflow. One row per assertion makes any mismatch visible.
with members as (
  select curated_build_id, team_key, season
  from analysis.league_member_releases_v2
  where season = '2024-25'
), member_exposure as (
  select e.*
  from analysis.analysis_window_effective_exposure_cohort_v5 e
  join members using (curated_build_id, team_key, season)
), member_injuries as (
  select i.*
  from analysis.analysis_window_injury_cohort_v5 i
  join members using (curated_build_id, team_key, season)
), expected_rejections_by_team(team_key, expected_rows, expected_hours) as (
  values
    ('cardiff', 164::numeric, 180.391667::numeric),
    ('dragons', 348::numeric, 296.138333::numeric),
    ('ospreys', 32::numeric, 23.623333::numeric),
    ('scarlets', 169::numeric, 183.943333::numeric),
    ('sharks', 46::numeric, 106.937222::numeric),
    ('zebre', 56::numeric, 74.796111::numeric)
), actual_rejections_by_team as (
  select
    team_key,
    count(*)::numeric as actual_rows,
    round(coalesce(sum(minutes_clean), 0) / 60, 6) as actual_hours
  from member_exposure
  where rejected_by_pre_urc_match_rule
  group by team_key
), expected(contract_name, expected_numeric) as (
  values
    ('included_exposure_rows', 64511::numeric),
    ('exposure_hours', 81352.919497::numeric),
    ('match_hours', 6040::numeric),
    ('training_hours', 75312.919497::numeric),
    ('recorded_injuries', 1658::numeric),
    ('time_loss_injuries', 785::numeric),
    ('days_lost', 17573::numeric),
    ('pre_urc_rejected_rows', 815::numeric),
    ('pre_urc_rejected_hours', 865.830::numeric),
    ('weekly_row_moves', 0::numeric),
    ('undated_injuries', 6::numeric),
    ('team_candidate_payloads', 16::numeric),
    ('league_candidate_payloads', 1::numeric)
), actual(contract_name, actual_numeric) as (
  select 'included_exposure_rows', count(*)::numeric
  from member_exposure
  where effective_eligibility_status = 'included_pending_protocol'
  union all
  select 'exposure_hours', round(coalesce(sum(minutes_clean), 0) / 60, 6)
  from member_exposure
  where effective_eligibility_status = 'included_pending_protocol'
  union all
  select 'match_hours', match_exposure_hours
  from analysis.analysis_window_league_summary_v5
  where season = '2024-25'
  union all
  select 'training_hours', round(training_exposure_hours, 6)
  from analysis.analysis_window_league_summary_v5
  where season = '2024-25'
  union all
  select 'recorded_injuries', recorded_injuries
  from analysis.analysis_window_league_summary_v5
  where season = '2024-25'
  union all
  select 'time_loss_injuries', time_loss_injuries
  from analysis.analysis_window_league_summary_v5
  where season = '2024-25'
  union all
  select 'days_lost', days_lost
  from analysis.analysis_window_league_summary_v5
  where season = '2024-25'
  union all
  select 'pre_urc_rejected_rows', count(*)::numeric
  from member_exposure
  where rejected_by_pre_urc_match_rule
  union all
  select 'pre_urc_rejected_hours',
    round(coalesce(sum(minutes_clean), 0) / 60, 6)
  from member_exposure
  where rejected_by_pre_urc_match_rule
  union all
  select 'weekly_row_moves', count(*)::numeric
  from member_exposure
  where reporting_grain = 'weekly'
    and historical_eligibility_status is distinct from effective_eligibility_status
  union all
  select 'undated_injuries', count(*)::numeric
  from member_injuries
  where is_undated
  union all
  select 'team_candidate_payloads', count(*)::numeric
  from analysis.team_dashboard_release_candidates_analysis_window_v5
  where season = '2024-25'
  union all
  select 'league_candidate_payloads', count(*)::numeric
  from analysis.league_dashboard_release_candidates_analysis_window_v5
  where season = '2024-25'
), monthly_contract as (
  select
    (
      select coalesce(sum(m.time_loss_injuries), 0)::numeric
      from analysis.analysis_window_league_monthly_v5 m
      where m.season = '2024-25'
    ) as monthly_time_loss,
    (
      select coalesce(count(*) filter (where i.is_time_loss), 0)::numeric
      from member_injuries i
      where i.date_injured is not null
    ) as dated_time_loss
)
select
  expected.contract_name,
  expected.expected_numeric,
  actual.actual_numeric,
  coalesce(expected.expected_numeric = actual.actual_numeric, false) as passed
from expected
left join actual using (contract_name)
union all
select
  'pre_urc_rejected_rows_' || expected.team_key,
  expected.expected_rows,
  coalesce(actual.actual_rows, 0),
  expected.expected_rows = coalesce(actual.actual_rows, 0)
from expected_rejections_by_team expected
left join actual_rejections_by_team actual using (team_key)
union all
select
  'pre_urc_rejected_hours_' || expected.team_key,
  expected.expected_hours,
  coalesce(actual.actual_hours, 0),
  expected.expected_hours = coalesce(actual.actual_hours, 0)
from expected_rejections_by_team expected
left join actual_rejections_by_team actual using (team_key)
union all
select
  'monthly_time_loss_equals_dated_time_loss',
  dated_time_loss,
  monthly_time_loss,
  dated_time_loss = monthly_time_loss
from monthly_contract
union all
select
  'non_window_historical_exclusion_never_readmitted',
  0::numeric,
  count(*)::numeric,
  count(*) = 0
from member_exposure
where historical_eligibility_status = 'excluded_from_primary'
  and cardinality(array_remove(
    historical_exclusion_reasons,
    'outside_official_analysis_window'
  )) > 0
  and effective_eligibility_status = 'included_pending_protocol'
order by contract_name;
