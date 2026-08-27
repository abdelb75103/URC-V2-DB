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
    setting text,
    time_loss_injuries bigint,
    days_lost numeric
  )
  where profile.dimension = 'diagnosis'
), monthly_rows as (
  select month.*
  from dashboard
  cross join lateral jsonb_to_recordset(monthly) as month(
    recorded_injuries bigint,
    time_loss_injuries bigint
  )
)
select
  current_user = 'web_reader' as web_reader_role,
  (select target_attested from reporting.approved_dashboard_reader_target_v2)
    as target_attested,
  (select (item ->> 'value')::bigint from headline
   where item ->> 'key' = 'recorded_injuries') = 1662 as recorded_injuries,
  (select (item ->> 'value')::bigint from headline
   where item ->> 'key' = 'time_loss_injuries') = 913 as time_loss_injuries,
  (select (item ->> 'numerator')::numeric from headline
   where item ->> 'key' = 'severity_mean_days') = 17575 as observed_days,
  (select count(*) from monthly_rows) = 10
    and (select bool_and(recorded_injuries is not null
                         and time_loss_injuries is not null)
         from monthly_rows) as four_series_monthly_source,
  (select count(distinct setting) from diagnosis
   where setting in ('all', 'match', 'training', 'unknown')) = 4
    as diagnosis_settings,
  (select sum(time_loss_injuries) from diagnosis where setting = 'all') = 913
    and (select sum(days_lost) from diagnosis where setting = 'all') = 17575
    and (select sum(time_loss_injuries) from diagnosis
         where setting in ('match', 'training', 'unknown')) = 913
    and (select sum(days_lost) from diagnosis
         where setting in ('match', 'training', 'unknown')) = 17575
    as injury_only_diagnosis_reconciles,
  jsonb_array_length(injury_type_families) > 0 as families_present,
  (select count(distinct severity.setting)
   from jsonb_to_recordset(severity_distribution) as severity(setting text)
   where severity.setting in ('all', 'match', 'training')) = 3
    as severity_settings
from dashboard;
