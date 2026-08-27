with assertion as (
  select analysis.assert_urc_2024_25_setting_profile_successor_v1()
), expected_diagnosis as (
  select setting.setting_code,
    count(*) filter (where injury.final_classification = 'Time Loss')::bigint
      as time_loss_injuries,
    coalesce(sum(injury.days_lost) filter (
      where injury.final_classification = 'Time Loss' and injury.duration_usable
    ), 0)::numeric as days_lost
  from analysis.urc_2024_25_final_injury_classification_v1 injury
  cross join lateral (
    select injury.setting_code
      where injury.setting_code in ('match', 'training', 'unknown')
    union all select 'all'::text
  ) setting
  where injury.canonical_problem_type = 'injury'
  group by setting.setting_code
), published_diagnosis as (
  select setting_code, sum(time_loss_injuries)::bigint as time_loss_injuries,
    sum(days_lost)::numeric as days_lost
  from analysis.urc_2024_25_league_profiles_v2
  where dimension = 'diagnosis'
  group by setting_code
)
select 'installed_assertion' as check_name,
  (select count(*) from assertion) = 1 as passed
union all
select 'approved_headlines',
  (select (item ->> 'value')::bigint
   from analysis.urc_2024_25_league_dashboard_candidate_v2 candidate
   cross join lateral jsonb_array_elements(candidate.dashboard -> 'headline') item
   where item ->> 'key' = 'recorded_injuries') = 1662
  and
  (select (item ->> 'value')::bigint
   from analysis.urc_2024_25_league_dashboard_candidate_v2 candidate
   cross join lateral jsonb_array_elements(candidate.dashboard -> 'headline') item
   where item ->> 'key' = 'time_loss_injuries') = 913
  and
  (select (item ->> 'numerator')::numeric
   from analysis.urc_2024_25_league_dashboard_candidate_v2 candidate
   cross join lateral jsonb_array_elements(candidate.dashboard -> 'headline') item
   where item ->> 'key' = 'severity_mean_days') = 17575
union all
select 'profile_settings',
  count(distinct setting_code) filter (
    where setting_code in ('all', 'match', 'training')
  ) = 3
from analysis.urc_2024_25_league_profiles_v2
union all
select 'injury_only_diagnosis',
  not exists (
    select 1
    from expected_diagnosis expected
    full join published_diagnosis published using (setting_code)
    where (expected.time_loss_injuries, expected.days_lost)
      is distinct from (published.time_loss_injuries, published.days_lost)
  )
union all
select 'families_present',
  jsonb_array_length(dashboard -> 'injury_type_families') > 0
from analysis.urc_2024_25_league_dashboard_candidate_v2
order by check_name;
