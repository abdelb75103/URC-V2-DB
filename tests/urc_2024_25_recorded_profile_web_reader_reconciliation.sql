with dashboard as (
  select *
  from reporting.latest_league_dashboard_v6
  where season = '2024-25'
), headline as (
  select item
  from dashboard
  cross join lateral jsonb_array_elements(headline) item
), diagnosis as (
  select profile.*
  from dashboard
  cross join lateral jsonb_to_recordset(injury_profiles) as profile(
    dimension text,
    code text,
    label text,
    setting text,
    recorded_injuries bigint,
    time_loss_injuries bigint,
    days_lost numeric
  )
  where profile.dimension = 'diagnosis'
)
select
  current_user = 'web_reader' as web_reader_role,
  (select target_attested from reporting.approved_dashboard_reader_target_v2)
    as target_attested,
  (select (item ->> 'value')::bigint from headline
   where item ->> 'key' = 'recorded_injuries') = 1662
    as recorded_injuries,
  (select (item ->> 'value')::bigint from headline
   where item ->> 'key' = 'time_loss_injuries') = 913
    as time_loss_injuries,
  (select (item ->> 'numerator')::numeric from headline
   where item ->> 'key' = 'severity_mean_days') = 17575
    as observed_days,
  (select sum(recorded_injuries) from diagnosis where setting = 'all') = 1662
    and (select sum(recorded_injuries) from diagnosis
         where setting in ('match', 'training', 'unknown')) = 1662
    as recorded_diagnoses_reconcile,
  (select recorded_injuries from diagnosis
   where setting = 'all' and code = 'dx_lumbar_spine_pain_2022547a07') = 41
    and (select recorded_injuries from diagnosis
         where setting = 'all'
           and code = 'dx_acromioclavicular_joint_injury_1a8d08823b') = 39
    and (select recorded_injuries from diagnosis
         where setting = 'all'
           and code = 'dx_groin_and_adductor_injury_476e2d09eb') = 37
    as reviewed_common_diagnoses_present,
  (select bool_and(recorded_injuries is not null) from diagnosis)
    as recorded_profile_complete
from dashboard;
