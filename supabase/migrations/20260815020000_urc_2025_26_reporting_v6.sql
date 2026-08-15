-- Additive Year 2 computational reporting successor.  This path reads only
-- active curated rows and becomes visible only for a complete sixteen-team build.

create view analysis.accepted_analysis_window_cohort_rules_v6
with (security_invoker = true) as
select r.cohort_view_version, r.season,
  encode(digest(convert_to(jsonb_agg(jsonb_build_object(
    'adjudication_ref',r.adjudication_ref,'decision',r.decision,
    'evidence_sha256',r.evidence_sha256,'evidence_locator',r.evidence_locator,
    'reviewer',r.reviewer,'migration_version',r.migration_version
  ) order by r.adjudication_ref)::text,'UTF8'),'sha256'),'hex') as cohort_evidence_sha256
from audit.reporting_cohort_rule_adjudications_v3 r
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version=r.cohort_view_version and w.season=r.season
 and w.decision_ref=r.adjudication_ref
 and w.season_start=date '2025-09-01' and w.season_end=date '2026-06-30'
where r.adjudication_ref='ANALYSIS-WINDOW-2025-26-01'
  and r.cohort_view_version='analysis_window_2025-26_2026-08-15_v1'
  and r.season='2025-26' and r.reviewer='Abdel Babiker'
  and r.evidence_sha256='a9c5ebc40a063564d70a2cc2e1f45fddb7069a900d398bea5b32208b65eaf3fe'
  and r.evidence_locator='docs/evidence/urc_2025_26_reporting_contract.json'
  and r.migration_version='20260815010000'
group by r.cohort_view_version,r.season having count(*)=1;

create view analysis.analysis_window_member_builds_v6
with (security_invoker = true) as
select member.team_key,member.season,member.team_release_id,member.curated_build_id,
  member.generated_at
from analysis.league_member_releases_v2 member
join curated.builds build on build.id=member.curated_build_id
 and build.team_key=member.team_key and build.season=member.season
 and build.status='active'
where member.season='2025-26'
  and (select count(*) from analysis.league_member_releases_v2 where season='2025-26')=16
  and (select count(distinct team_key) from analysis.league_member_releases_v2 where season='2025-26')=16;

create view analysis.analysis_window_injury_cohort_v6
with (security_invoker = true) as
select injury.id as injury_id,member.curated_build_id,member.team_key,member.season,
  injury.source_row_id,injury.date_injured,
  coalesce(injury.days_injured,0)::numeric as days_lost,
  coalesce(injury.days_injured,0)>0 as is_time_loss,
  case injury.activity_context when 'match' then 'match' when 'training' then 'training' else 'unknown' end as setting_code,
  coalesce(injury.body_location,'unknown') as body_location_code,
  coalesce(body.label,'Unknown') as body_location_label,
  coalesce(injury.injury_type,'unknown') as injury_type_code,
  coalesce(injury_type.label,'Unknown') as injury_type_label,
  case when injury.days_injured is null then 'unknown_or_censored'
       when injury.days_injured=0 then 'zero_days_medical_attention_only'
       when injury.days_injured=1 then 'one_day'
       when injury.days_injured between 2 and 3 then 'two_to_three_days'
       when injury.days_injured between 4 and 7 then 'four_to_seven_days'
       when injury.days_injured between 8 and 28 then 'eight_to_twenty_eight_days'
       when injury.days_injured>28 then 'greater_than_twenty_eight_days'
       else 'unknown_or_censored' end as severity_code,
  injury.date_injured is null as is_undated,window.cohort_view_version
from analysis.analysis_window_member_builds_v6 member
join curated.injuries injury on injury.curated_build_id=member.curated_build_id
 and injury.team_key=member.team_key and injury.season=member.season
join analysis.reporting_season_windows_v3 window
  on window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and window.season=member.season
join analysis.accepted_analysis_window_cohort_rules_v6 accepted
  on accepted.cohort_view_version=window.cohort_view_version and accepted.season=window.season
left join curated.code_lists body on body.list_name='body_location' and body.code=coalesce(injury.body_location,'unknown')
left join curated.code_lists injury_type on injury_type.list_name='injury_type' and injury_type.code=coalesce(injury.injury_type,'unknown')
where injury.problem_type='injury' and injury.eligibility_status='included_pending_protocol'
  and (injury.date_injured between window.season_start and window.season_end or injury.date_injured is null);

create view analysis.analysis_window_team_exposure_v6
with (security_invoker = true) as
select member.curated_build_id,member.team_key,member.season,exposure.grain as reporting_grain,
  coalesce(exposure.session_date,exposure.week_start_date) as period_start,
  coalesce(exposure.session_date,exposure.week_start_date)+case when exposure.grain='weekly' then 6 else 0 end as period_end,
  exposure.minutes_clean,exposure.distance_m_clean,window.cohort_view_version
from analysis.analysis_window_member_builds_v6 member
join curated.exposure exposure on exposure.curated_build_id=member.curated_build_id
 and exposure.team_key=member.team_key and exposure.season=member.season
join analysis.reporting_season_windows_v3 window on window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and window.season=member.season
join analysis.accepted_analysis_window_cohort_rules_v6 accepted on accepted.cohort_view_version=window.cohort_view_version and accepted.season=window.season
where exposure.eligibility_status='included_pending_protocol'
  and coalesce(exposure.session_date,exposure.week_start_date) is not null
  and coalesce(exposure.session_date,exposure.week_start_date)<=window.season_end
  and coalesce(exposure.session_date,exposure.week_start_date)+case when exposure.grain='weekly' then 6 else 0 end>=window.season_start;

create view analysis.analysis_window_team_hours_v6
with (security_invoker = true) as
with exposure as (
  select curated_build_id,team_key,season,sum(minutes_clean)/60 as total_hours,
    sum(distance_m_clean)/1000 as distance_km,
    case when count(distinct reporting_grain)=1 then min(reporting_grain) else 'mixed' end as exposure_grain
  from analysis.analysis_window_team_exposure_v6 group by curated_build_id,team_key,season
), fixtures as (
  select member.team_key,member.season,count(*)*20.0 as match_hours
  from analysis.analysis_window_member_builds_v6 member
  join curated.fixtures fixture on fixture.season=member.season and (fixture.home_team_key=member.team_key or fixture.away_team_key=member.team_key)
  join analysis.reporting_season_windows_v3 window on window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and window.season=fixture.season
  where fixture.match_date between window.season_start and window.season_end
  group by member.team_key,member.season
)
select exposure.curated_build_id,exposure.team_key,exposure.season,exposure.total_hours,
  coalesce(fixtures.match_hours,0) as match_hours,
  exposure.total_hours-coalesce(fixtures.match_hours,0) as training_hours,
  exposure.distance_km,exposure.exposure_grain
from exposure left join fixtures using(team_key,season)
where exposure.total_hours>=coalesce(fixtures.match_hours,0);

create view analysis.analysis_window_team_summary_v6
with (security_invoker = true) as
select member.curated_build_id,member.team_key,member.season,
  count(cohort.injury_id) as recorded_injuries,
  count(cohort.injury_id) filter(where cohort.is_time_loss) as time_loss_injuries,
  coalesce(sum(cohort.days_lost) filter(where cohort.is_time_loss),0) as days_lost,
  avg(cohort.days_lost) filter(where cohort.is_time_loss) as mean_severity_days
from analysis.analysis_window_member_builds_v6 member
left join analysis.analysis_window_injury_cohort_v6 cohort using(curated_build_id,team_key,season)
group by member.curated_build_id,member.team_key,member.season;

create view analysis.analysis_window_monthly_v6
with (security_invoker = true) as
with exposure as (
 select curated_build_id,team_key,season,date_trunc('month',period_start)::date as month_start,
   sum(minutes_clean)/60 as exposure_hours,sum(distance_m_clean)/1000 as distance_km
 from analysis.analysis_window_team_exposure_v6 group by curated_build_id,team_key,season,date_trunc('month',period_start)
), injuries as (
 select curated_build_id,team_key,season,date_trunc('month',date_injured)::date as month_start,
   count(*) filter(where is_time_loss) as time_loss_injuries,coalesce(sum(days_lost) filter(where is_time_loss),0) as days_lost
 from analysis.analysis_window_injury_cohort_v6
 where cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and date_injured is not null
 group by curated_build_id,team_key,season,date_trunc('month',date_injured)
), months as (select curated_build_id,team_key,season,month_start from exposure union select curated_build_id,team_key,season,month_start from injuries)
select months.curated_build_id,months.team_key,months.season,months.month_start,to_char(months.month_start,'Mon YYYY') as month_label,
 coalesce(exposure.exposure_hours,0) as exposure_hours,coalesce(exposure.distance_km,0) as distance_km,
 coalesce(injuries.time_loss_injuries,0) as time_loss_injuries,coalesce(injuries.days_lost,0) as days_lost,
 analysis.rate_per_1000_v1(coalesce(injuries.time_loss_injuries,0),coalesce(exposure.exposure_hours,0)) as incidence_per_1000h,
 analysis.rate_per_1000_v1(coalesce(injuries.days_lost,0),coalesce(exposure.exposure_hours,0)) as burden_per_1000h
from months left join exposure using(curated_build_id,team_key,season,month_start) left join injuries using(curated_build_id,team_key,season,month_start);

create view analysis.analysis_window_league_monthly_v6
with (security_invoker = true) as
select season,month_start,month_label,sum(exposure_hours) as exposure_hours,sum(distance_km) as distance_km,
 sum(time_loss_injuries) as time_loss_injuries,sum(days_lost) as days_lost,
 analysis.rate_per_1000_v1(sum(time_loss_injuries),sum(exposure_hours)) as incidence_per_1000h,
 analysis.rate_per_1000_v1(sum(days_lost),sum(exposure_hours)) as burden_per_1000h
from analysis.analysis_window_monthly_v6 group by season,month_start,month_label;

create view analysis.analysis_window_league_summary_v6
with (security_invoker = true) as
select summary.season,sum(summary.recorded_injuries) as recorded_injuries,
 sum(summary.time_loss_injuries) as time_loss_injuries,sum(summary.days_lost) as days_lost,
 sum(summary.days_lost)/nullif(sum(summary.time_loss_injuries),0) as mean_severity_days,
 sum(hours.total_hours) as exposure_hours,sum(hours.match_hours) as match_exposure_hours,sum(hours.training_hours) as training_exposure_hours
from analysis.analysis_window_team_summary_v6 summary join analysis.analysis_window_team_hours_v6 hours using(curated_build_id,team_key,season)
group by summary.season;

create view analysis.team_dashboard_payload_analysis_window_v6
with (security_invoker = true) as
select member.team_key,member.season,member.team_release_id,member.curated_build_id,
 rules.classification_view_version,rules.classification_evidence_sha256,
 cohort.cohort_view_version,cohort.cohort_evidence_sha256,
 jsonb_build_object('generated_at',member.generated_at,'team',dashboard.team,'season',member.season,
  'analysis_window',jsonb_build_object('start',window.season_start,'end',window.season_end,'basis','Registered Year 2 reporting window.'),
  'method',jsonb_build_array('Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.','Burden = pooled days lost / pooled exposure hours × 1,000.','Season-attributed undated injuries are included in totals but excluded from monthly series.','Curated IOC categories are carried forward; unsupported mappings remain Unknown.'),
  'coverage',jsonb_build_object('hours',hours.total_hours,'match_hours',hours.match_hours,'training_hours',hours.training_hours,'distance_km',hours.distance_km,'exposure_grain',hours.exposure_grain,'analysis_window_start',window.season_start,'analysis_window_end',window.season_end),
  'headline',jsonb_build_array(jsonb_build_object('key','recorded_injuries','label','Recorded injuries','value',summary.recorded_injuries,'unit','injuries'),jsonb_build_object('key','time_loss_injuries','label','Time-loss injuries','value',summary.time_loss_injuries,'unit','injuries'),jsonb_build_object('key','incidence_per_1000h','label','Incidence','value',analysis.rate_per_1000_v1(summary.time_loss_injuries,hours.total_hours),'unit','per 1,000 player-hours','numerator',summary.time_loss_injuries,'denominator',hours.total_hours),jsonb_build_object('key','severity_mean_days','label','Mean severity','value',summary.mean_severity_days,'unit','days lost per injury','numerator',summary.days_lost,'denominator',summary.time_loss_injuries),jsonb_build_object('key','burden_per_1000h','label','Burden','value',analysis.rate_per_1000_v1(summary.days_lost,hours.total_hours),'unit','days lost per 1,000 player-hours','numerator',summary.days_lost,'denominator',hours.total_hours)),
  'monthly',coalesce((select jsonb_agg(jsonb_build_object('month',monthly.month_label,'exposure_hours',monthly.exposure_hours,'distance_km',monthly.distance_km,'time_loss_injuries',monthly.time_loss_injuries,'days_lost',monthly.days_lost,'incidence_per_1000h',monthly.incidence_per_1000h,'burden_per_1000h',monthly.burden_per_1000h) order by monthly.month_start) from analysis.analysis_window_monthly_v6 monthly where monthly.curated_build_id=member.curated_build_id and monthly.team_key=member.team_key and monthly.season=member.season),'[]'::jsonb),
  'body_locations','[]'::jsonb,'injury_types','[]'::jsonb,'injury_profiles','[]'::jsonb,'severity_distribution','[]'::jsonb,'setting_split','[]'::jsonb,'setting_metrics','[]'::jsonb,'contact_distribution','[]'::jsonb,'prior_season',dashboard.prior_season,'limitations',jsonb_build_array('Candidate is unavailable until all sixteen active member builds are present.')) as dashboard
from analysis.analysis_window_member_builds_v6 member
join analysis.analysis_window_team_summary_v6 summary using(curated_build_id,team_key,season)
join analysis.analysis_window_team_hours_v6 hours using(curated_build_id,team_key,season)
join reporting.latest_team_dashboard dashboard on dashboard.release_id=member.team_release_id and dashboard.team_key=member.team_key and dashboard.season=member.season
join analysis.reporting_season_windows_v3 window on window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and window.season=member.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort on cohort.cohort_view_version=window.cohort_view_version and cohort.season=window.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
where rules.classification_view_version='reporting_classification_2026-07-22_v2';

create view analysis.league_dashboard_payload_analysis_window_v6
with (security_invoker = true) as
select summary.season,rules.classification_view_version,rules.classification_evidence_sha256,cohort.cohort_view_version,cohort.cohort_evidence_sha256,
 jsonb_build_object('generated_at',(select max(generated_at) from analysis.analysis_window_member_builds_v6),'team','URC Overall','season',summary.season,
  'analysis_window',jsonb_build_object('start',window.season_start,'end',window.season_end,'basis','Registered Year 2 reporting window.'),
  'method',jsonb_build_array('Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.','Burden = pooled days lost / pooled exposure hours × 1,000.','Season-attributed undated injuries are included in totals but excluded from monthly series.'),
  'coverage',jsonb_build_object('hours',summary.exposure_hours,'match_hours',summary.match_exposure_hours,'training_hours',summary.training_exposure_hours,'teams_included',16,'analysis_window_start',window.season_start,'analysis_window_end',window.season_end),
  'headline',jsonb_build_array(jsonb_build_object('key','recorded_injuries','label','Recorded injuries','value',summary.recorded_injuries,'unit','injuries'),jsonb_build_object('key','time_loss_injuries','label','Time-loss injuries','value',summary.time_loss_injuries,'unit','injuries'),jsonb_build_object('key','incidence_per_1000h','label','Incidence','value',analysis.rate_per_1000_v1(summary.time_loss_injuries,summary.exposure_hours),'unit','per 1,000 player-hours','numerator',summary.time_loss_injuries,'denominator',summary.exposure_hours),jsonb_build_object('key','severity_mean_days','label','Mean severity','value',summary.mean_severity_days,'unit','days lost per injury','numerator',summary.days_lost,'denominator',summary.time_loss_injuries),jsonb_build_object('key','burden_per_1000h','label','Burden','value',analysis.rate_per_1000_v1(summary.days_lost,summary.exposure_hours),'unit','days lost per 1,000 player-hours','numerator',summary.days_lost,'denominator',summary.exposure_hours)),
  'monthly',coalesce((select jsonb_agg(jsonb_build_object('month',monthly.month_label,'exposure_hours',monthly.exposure_hours,'distance_km',monthly.distance_km,'time_loss_injuries',monthly.time_loss_injuries,'days_lost',monthly.days_lost,'incidence_per_1000h',monthly.incidence_per_1000h,'burden_per_1000h',monthly.burden_per_1000h) order by monthly.month_start) from analysis.analysis_window_league_monthly_v6 monthly where monthly.season=summary.season),'[]'::jsonb),
  'body_locations','[]'::jsonb,'injury_types','[]'::jsonb,'injury_profiles','[]'::jsonb,'severity_distribution','[]'::jsonb,'setting_split','[]'::jsonb,'setting_metrics','[]'::jsonb,'contact_distribution','[]'::jsonb,'prior_season',jsonb_build_object('status','frozen'),'limitations',jsonb_build_array('Candidate is unavailable until all sixteen active member builds are present.')) as dashboard
from analysis.analysis_window_league_summary_v6 summary
join analysis.reporting_season_windows_v3 window on window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and window.season=summary.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort on cohort.cohort_view_version=window.cohort_view_version and cohort.season=window.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
where rules.classification_view_version='reporting_classification_2026-07-22_v2';

create view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select team_key,season,team_release_id,curated_build_id,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard
from analysis.team_dashboard_payload_analysis_window_v6;

create view analysis.league_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select season,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard
from analysis.league_dashboard_payload_analysis_window_v6;

-- Curated-only display successors. Unknown codes are retained and no source
-- text or historical adjudication is read here.
create view analysis.analysis_window_profiles_v6
with (security_invoker = true) as
select cohort.curated_build_id,cohort.team_key,cohort.season,
 dimension,code,label,count(*) as time_loss_injuries,sum(cohort.days_lost) as days_lost,
 hours.total_hours as exposure_hours,
 analysis.rate_per_1000_v1(count(*),hours.total_hours) as incidence_per_1000h,
 analysis.rate_per_1000_v1(sum(cohort.days_lost),hours.total_hours) as burden_per_1000h,
 sum(cohort.days_lost)/nullif(count(*),0) as mean_severity_days
from analysis.analysis_window_injury_cohort_v6 cohort
cross join lateral(values
 ('body_location'::text,cohort.body_location_code,cohort.body_location_label),
 ('injury_type'::text,cohort.injury_type_code,cohort.injury_type_label),
 ('injury_profile'::text,cohort.body_location_code||'__'||cohort.injury_type_code,cohort.body_location_label||' · '||cohort.injury_type_label)
) d(dimension,code,label)
join analysis.analysis_window_team_hours_v6 hours using(curated_build_id,team_key,season)
where cohort.is_time_loss
group by cohort.curated_build_id,cohort.team_key,cohort.season,dimension,code,label,hours.total_hours;

create view analysis.analysis_window_setting_metrics_v6 with (security_invoker=true) as
select cohort.curated_build_id,cohort.team_key,cohort.season,cohort.setting_code,
 count(*) filter(where cohort.is_time_loss) as time_loss_injuries,
 coalesce(sum(cohort.days_lost) filter(where cohort.is_time_loss),0) as days_lost,
 case cohort.setting_code when 'match' then hours.match_hours when 'training' then hours.training_hours else null end as exposure_hours
from analysis.analysis_window_injury_cohort_v6 cohort join analysis.analysis_window_team_hours_v6 hours using(curated_build_id,team_key,season)
group by cohort.curated_build_id,cohort.team_key,cohort.season,cohort.setting_code,hours.match_hours,hours.training_hours;

create view analysis.analysis_window_severity_v6 with (security_invoker=true) as
select curated_build_id,team_key,season,severity_code,count(*) as recorded_injuries,
 count(*) filter(where is_time_loss) as time_loss_injuries,
 coalesce(sum(days_lost) filter(where is_time_loss),0) as days_lost
from analysis.analysis_window_injury_cohort_v6 group by curated_build_id,team_key,season,severity_code;

create view analysis.analysis_window_contact_distribution_v6 with (security_invoker=true) as
select injury.curated_build_id,injury.team_key,injury.season,
 case injury.activity_context when 'match' then 'match' when 'training' then 'training' else 'all' end as setting_code,
 coalesce(injury.contact_context,'unknown') as contact_context,
 count(*) as recorded_injuries,count(*) filter(where coalesce(injury.days_injured,0)>0) as time_loss_injuries
from curated.injuries injury join analysis.analysis_window_member_builds_v6 member using(curated_build_id,team_key,season)
join analysis.reporting_season_windows_v3 window on window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and window.season=injury.season
where injury.problem_type='injury' and injury.eligibility_status='included_pending_protocol'
and (injury.date_injured between window.season_start and window.season_end or injury.date_injured is null)
group by injury.curated_build_id,injury.team_key,injury.season,setting_code,contact_context;

create view analysis.team_dashboard_payload_analysis_window_v6_enriched with (security_invoker=true) as
select base.*,
 base.dashboard || jsonb_build_object(
  'body_locations',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by code) from analysis.analysis_window_profiles_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season and dimension='body_location'),'[]'::jsonb),
  'injury_types',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by time_loss_injuries desc,code) from analysis.analysis_window_profiles_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season and dimension='injury_type'),'[]'::jsonb),
  'injury_profiles',coalesce((select jsonb_agg(jsonb_build_object('dimension',dimension,'code',code,'label',label,'setting','all','time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by dimension,code) from analysis.analysis_window_profiles_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'severity_distribution',coalesce((select jsonb_agg(jsonb_build_object('key',severity_code,'label',initcap(replace(severity_code,'_',' ')),'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost) order by severity_code) from analysis.analysis_window_severity_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'setting_metrics',coalesce((select jsonb_agg(jsonb_build_object('setting',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',analysis.rate_per_1000_v1(time_loss_injuries,exposure_hours),'burden_per_1000h',analysis.rate_per_1000_v1(days_lost,exposure_hours),'mean_severity_days',days_lost/nullif(time_loss_injuries,0)) order by setting_code) from analysis.analysis_window_setting_metrics_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'setting_split',coalesce((select jsonb_agg(jsonb_build_object('key',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours) order by setting_code) from analysis.analysis_window_setting_metrics_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'contact_distribution',coalesce((select jsonb_agg(jsonb_build_object('setting',setting_code,'contact_context',contact_context,'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries) order by setting_code,contact_context) from analysis.analysis_window_contact_distribution_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb)) as dashboard
from analysis.team_dashboard_payload_analysis_window_v6 base;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6 with (security_invoker=true) as
select team_key,season,team_release_id,curated_build_id,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard from analysis.team_dashboard_payload_analysis_window_v6_enriched;

create view analysis.analysis_window_league_profiles_v6 with (security_invoker=true) as
select season,dimension,code,label,sum(time_loss_injuries) as time_loss_injuries,
 sum(days_lost) as days_lost,sum(exposure_hours) as exposure_hours
from analysis.analysis_window_profiles_v6 group by season,dimension,code,label;

create view analysis.analysis_window_league_setting_metrics_v6 with (security_invoker=true) as
select season,setting_code,sum(time_loss_injuries) as time_loss_injuries,
 sum(days_lost) as days_lost,sum(exposure_hours) as exposure_hours
from analysis.analysis_window_setting_metrics_v6 group by season,setting_code;

create view analysis.analysis_window_league_severity_v6 with (security_invoker=true) as
select season,severity_code,sum(recorded_injuries) as recorded_injuries,
 sum(time_loss_injuries) as time_loss_injuries,sum(days_lost) as days_lost
from analysis.analysis_window_severity_v6 group by season,severity_code;

create view analysis.analysis_window_league_contact_distribution_v6 with (security_invoker=true) as
select season,setting_code,contact_context,sum(recorded_injuries) as recorded_injuries,
 sum(time_loss_injuries) as time_loss_injuries
from analysis.analysis_window_contact_distribution_v6 group by season,setting_code,contact_context;

create view analysis.league_dashboard_payload_analysis_window_v6_enriched with (security_invoker=true) as
select base.*,
 base.dashboard || jsonb_build_object(
  'body_locations',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',analysis.rate_per_1000_v1(time_loss_injuries,exposure_hours),'burden_per_1000h',analysis.rate_per_1000_v1(days_lost,exposure_hours),'mean_severity_days',days_lost/nullif(time_loss_injuries,0)) order by code) from analysis.analysis_window_league_profiles_v6 where season=base.season and dimension='body_location'),'[]'::jsonb),
  'injury_types',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',analysis.rate_per_1000_v1(time_loss_injuries,exposure_hours),'burden_per_1000h',analysis.rate_per_1000_v1(days_lost,exposure_hours),'mean_severity_days',days_lost/nullif(time_loss_injuries,0)) order by time_loss_injuries desc,code) from analysis.analysis_window_league_profiles_v6 where season=base.season and dimension='injury_type'),'[]'::jsonb),
  'injury_profiles',coalesce((select jsonb_agg(jsonb_build_object('dimension',dimension,'code',code,'label',label,'setting','all','time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',analysis.rate_per_1000_v1(time_loss_injuries,exposure_hours),'burden_per_1000h',analysis.rate_per_1000_v1(days_lost,exposure_hours),'mean_severity_days',days_lost/nullif(time_loss_injuries,0)) order by dimension,code) from analysis.analysis_window_league_profiles_v6 where season=base.season),'[]'::jsonb),
  'severity_distribution',coalesce((select jsonb_agg(jsonb_build_object('key',severity_code,'label',initcap(replace(severity_code,'_',' ')),'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost) order by severity_code) from analysis.analysis_window_league_severity_v6 where season=base.season),'[]'::jsonb),
  'setting_metrics',coalesce((select jsonb_agg(jsonb_build_object('setting',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',analysis.rate_per_1000_v1(time_loss_injuries,exposure_hours),'burden_per_1000h',analysis.rate_per_1000_v1(days_lost,exposure_hours),'mean_severity_days',days_lost/nullif(time_loss_injuries,0)) order by setting_code) from analysis.analysis_window_league_setting_metrics_v6 where season=base.season),'[]'::jsonb),
  'setting_split',coalesce((select jsonb_agg(jsonb_build_object('key',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours) order by setting_code) from analysis.analysis_window_league_setting_metrics_v6 where season=base.season),'[]'::jsonb),
  'contact_distribution',coalesce((select jsonb_agg(jsonb_build_object('setting',setting_code,'contact_context',contact_context,'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries) order by setting_code,contact_context) from analysis.analysis_window_league_contact_distribution_v6 where season=base.season),'[]'::jsonb)) as dashboard
from analysis.league_dashboard_payload_analysis_window_v6 base;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6 with (security_invoker=true) as
select season,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard from analysis.league_dashboard_payload_analysis_window_v6_enriched;
