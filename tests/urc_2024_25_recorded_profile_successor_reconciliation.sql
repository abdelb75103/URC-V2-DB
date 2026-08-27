select 'installed_assertion' as check_name,
  analysis.assert_urc_2024_25_recorded_profile_successor_v1() is null as passed;

select 'approved_headlines' as check_name,
  (select (item ->> 'value')::bigint
   from analysis.urc_2024_25_league_dashboard_candidate_v3 candidate
   cross join lateral jsonb_array_elements(candidate.dashboard -> 'headline') item
   where item ->> 'key' = 'recorded_injuries') = 1662
  and
  (select (item ->> 'value')::bigint
   from analysis.urc_2024_25_league_dashboard_candidate_v3 candidate
   cross join lateral jsonb_array_elements(candidate.dashboard -> 'headline') item
   where item ->> 'key' = 'time_loss_injuries') = 913
  and
  (select (item ->> 'numerator')::numeric
   from analysis.urc_2024_25_league_dashboard_candidate_v3 candidate
   cross join lateral jsonb_array_elements(candidate.dashboard -> 'headline') item
   where item ->> 'key' = 'severity_mean_days') = 17575 as passed;

select 'recorded_diagnosis_counts' as check_name,
  bool_and(profile.recorded_injuries = expected.recorded_injuries) as passed
from (values
  ('dx_hamstring_injury_f17cabd810'::text, 120::bigint),
  ('dx_lumbar_spine_pain_2022547a07', 41),
  ('dx_acromioclavicular_joint_injury_1a8d08823b', 39),
  ('dx_groin_and_adductor_injury_476e2d09eb', 37)
) expected(code, recorded_injuries)
join analysis.urc_2024_25_league_profiles_v3 profile
  on profile.setting_code = 'all'
 and profile.dimension = 'diagnosis'
 and profile.code = expected.code;

select 'recorded_profile_payload' as check_name,
  count(*) > 0 and bool_and(recorded_injuries is not null) as passed
from analysis.urc_2024_25_league_dashboard_candidate_v3 candidate
cross join lateral jsonb_to_recordset(candidate.dashboard -> 'injury_profiles')
  as profile(dimension text, setting text, recorded_injuries bigint);
