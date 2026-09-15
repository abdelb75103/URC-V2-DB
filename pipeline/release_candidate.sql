-- Private candidate only. No active builds, reporting readers or release selectors change.
do $$ begin
  if (select payload_sha256 from _pipeline_params_attestation) <> 'CANDIDATE_PARAMS_SHA256'
  then raise exception 'Candidate input bytes changed'; end if;
end $$;
create temp table _candidate_served_before as
select 'teams' kind,md5(jsonb_agg(to_jsonb(t) order by season,team_key)::text) digest from reporting.latest_team_dashboard_v8 t
union all select 'league',md5(jsonb_agg(to_jsonb(t) order by season)::text) from reporting.latest_league_dashboard_v8 t;
drop schema if exists urc_candidate_20260915 cascade;
create schema urc_candidate_20260915;
revoke all on schema urc_candidate_20260915 from public, anon, authenticated, web_reader;

create table urc_candidate_20260915.provenance as
select value as evidence from _pipeline_params where value->>'kind' = 'provenance';
create table urc_candidate_20260915.urc_canonical_injury_rows_v1 as
select * from analysis.urc_canonical_injury_rows_v1 where false;
insert into urc_candidate_20260915.urc_canonical_injury_rows_v1
select (jsonb_populate_record(null::analysis.urc_canonical_injury_rows_v1, value->'row')).*
from _pipeline_params where value->>'kind' = 'injury';
create unique index candidate_injury_key on urc_candidate_20260915.urc_canonical_injury_rows_v1(team_key,source_row);
create view urc_candidate_20260915.urc_2025_26_canonical_injury_rows_v1 as
select * from urc_candidate_20260915.urc_canonical_injury_rows_v1;
create table urc_candidate_20260915.urc_illness_profile_rows_v2 as
select * from analysis.urc_illness_profile_rows_v2 where false;
insert into urc_candidate_20260915.urc_illness_profile_rows_v2
select (jsonb_populate_record(null::analysis.urc_illness_profile_rows_v2,value->'row')).*
from _pipeline_params where value->>'kind' = 'illness';
create unique index candidate_illness_key on urc_candidate_20260915.urc_illness_profile_rows_v2(team_key,source_row);
create table urc_candidate_20260915.injury_source_bridge as
select value->'row' as evidence from _pipeline_params where value->>'kind'='injury_bridge';
create table urc_candidate_20260915.exposure (
 team_key text not null, file_sha256 text not null, source_row_number integer not null,
 player_uid text, grain text, included boolean not null, exclusion_reason text,
 exposure_date date, week_start date, minutes numeric, distance_m numeric, hsr_m numeric, estimated boolean,
 primary key(team_key,source_row_number)
);
insert into urc_candidate_20260915.exposure
select (jsonb_populate_record(null::urc_candidate_20260915.exposure,value->'row')).*
from _pipeline_params where value->>'kind'='exposure';
do $$ begin
 if (select count(*) from urc_candidate_20260915.exposure) <> 12706
 or (select count(*) from urc_candidate_20260915.exposure where included) <> 5294
 then raise exception 'Reviewed exposure row counts changed'; end if;
 if exists(select 1 from urc_candidate_20260915.exposure e
   left join ingestion.source_files f on f.file_sha256=e.file_sha256 and f.season='2025-26'
   left join ingestion.source_rows r on r.source_file_id=f.id and r.source_row_number=e.source_row_number
   where r.id is null) then raise exception 'Candidate exposure is not registered'; end if;
end $$;

create table urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 as
select team_key,season,to_jsonb(t)-'team_key' as dashboard from reporting.latest_team_dashboard_v8 t;
create unique index candidate_team_payload_key on urc_candidate_20260915.diagnosis_family_base_team_payloads_v1(team_key,season);
create table urc_candidate_20260915.diagnosis_family_base_league_payloads_v1 as
select season,to_jsonb(t) as dashboard from reporting.latest_league_dashboard_v8 t;
create unique index candidate_league_payload_key on urc_candidate_20260915.diagnosis_family_base_league_payloads_v1(season);

-- Fill the complete reporting calendar without inventing missing exposure.
with rows as (
 select t.team_key,jsonb_agg(coalesce(old.item,'{}'::jsonb)||jsonb_build_object('month',to_char(d.month_start,'Mon YYYY')) order by d.month_start) monthly
 from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 t
 cross join generate_series(date '2025-09-01',date '2026-06-01',interval '1 month') d(month_start)
 left join lateral (select m item from jsonb_array_elements(t.dashboard->'monthly') m
 where case when m->>'month' ~ '^[0-9]{4}-[0-9]{2}$' then to_date(m->>'month','YYYY-MM') else to_date(m->>'month','Mon YYYY') end=d.month_start::date) old on true
 where t.season='2025-26' group by team_key
)
update urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 t
set dashboard=jsonb_set(dashboard,'{monthly}',r.monthly) from rows r where t.season='2025-26' and t.team_key=r.team_key;
update urc_candidate_20260915.diagnosis_family_base_league_payloads_v1
set dashboard=jsonb_set(dashboard,'{monthly}',(select jsonb_agg(m||jsonb_build_object('month',to_char(
 case when m->>'month' ~ '^[0-9]{4}-[0-9]{2}$' then to_date(m->>'month','YYYY-MM') else to_date(m->>'month','Mon YYYY') end,'Mon YYYY')))
 from jsonb_array_elements(dashboard->'monthly') m)) where season='2025-26';

-- The accepted denominator remains total reported minutes, with fixture match hours
-- retained and training hours calculated as the residual, as for the other teams.
with totals as (
 select team_key,count(*) as source_rows,count(*) filter(where included) as exposure_rows,
 count(distinct player_uid) filter(where included and player_uid <> 'Unknown') as players,
 count(distinct coalesce(week_start,date_trunc('week',exposure_date)::date)) filter(where included) as weeks,
 sum(minutes) filter(where included)/60 as hours,sum(distance_m) filter(where included)/1000 as distance_km
 from urc_candidate_20260915.exposure group by team_key
)
update urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 p
set dashboard=jsonb_set(p.dashboard,'{coverage}',(p.dashboard->'coverage') || jsonb_build_object(
 'hours',t.hours,'training_hours',t.hours-(p.dashboard#>>'{coverage,match_hours}')::numeric,
 'distance_km',t.distance_km,'exposure_rows',t.exposure_rows,'source_row_count',t.source_rows,
 'exposed_players',t.players,'weeks',t.weeks,
 'included_exposure_status','source_backed_exposure_submitted_may_be_incomplete'))
from totals t where p.team_key=t.team_key and p.season='2025-26';

with monthly as (
 select team_key,date_trunc('month',exposure_date)::date as month_start,
 sum(minutes)/60 as hours,sum(distance_m)/1000 as distance_km
 from urc_candidate_20260915.exposure where included group by 1,2
), rebuilt as (
 select p.team_key,jsonb_agg(m.item || jsonb_build_object('exposure_hours',fresh.hours,
 'distance_km',fresh.distance_km) order by m.ordinality) as monthly
 from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 p
 cross join lateral jsonb_array_elements(p.dashboard->'monthly') with ordinality m(item,ordinality)
 left join monthly fresh on fresh.team_key=p.team_key and fresh.month_start=
 case when m.item->>'month' ~ '^[0-9]{4}-[0-9]{2}$' then to_date(m.item->>'month','YYYY-MM')
 else to_date(m.item->>'month','Mon YYYY') end
 where p.season='2025-26' and p.team_key in ('benetton','edinburgh') group by p.team_key
)
update urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 p
set dashboard=jsonb_set(p.dashboard,'{monthly}',r.monthly)
from rebuilt r where p.team_key=r.team_key and p.season='2025-26';

with totals as (
 select sum((dashboard#>>'{coverage,hours}')::numeric) hours,
 sum((dashboard#>>'{coverage,training_hours}')::numeric) training_hours,
 sum((dashboard#>>'{coverage,distance_km}')::numeric) distance_km,
 sum((dashboard#>>'{coverage,exposure_rows}')::integer) exposure_rows,
 sum((dashboard#>>'{coverage,source_row_count}')::integer) source_rows,
 sum((dashboard#>>'{coverage,exposed_players}')::integer) players,
 sum((dashboard#>>'{coverage,weeks}')::integer) weeks
 from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 where season='2025-26'
)
update urc_candidate_20260915.diagnosis_family_base_league_payloads_v1 p
set dashboard=jsonb_set(p.dashboard,'{coverage}',p.dashboard->'coverage' || jsonb_build_object(
 'hours',t.hours,'training_hours',t.training_hours,'distance_km',t.distance_km,
 'exposure_rows',t.exposure_rows,'source_row_count',t.source_rows,'exposed_players',t.players,'weeks',t.weeks,
 'source_backed_team_count',16,'distance_contributor_count',16,'temporary_estimate_team_count',0,
 'pending_source_teams','[]'::jsonb,'included_exposure_status','16_source_backed_teams_submissions_may_be_incomplete'))
from totals t where p.season='2025-26';

create view urc_candidate_20260915.team_month_exposure as
select p.team_key,case when m->>'month' ~ '^[0-9]{4}-[0-9]{2}$'
 then to_date(m->>'month','YYYY-MM') else to_date(m->>'month','Mon YYYY') end as month_start,
 (m->>'exposure_hours')::numeric as hours,(m->>'distance_km')::numeric as distance_km
from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 p
cross join lateral jsonb_array_elements(p.dashboard->'monthly') m where season='2025-26';
with totals as (
 select month_start,sum(hours) hours,sum(distance_km) distance_km,
 count(*) filter(where hours>0) exposure_contributor_count,
 count(*) filter(where distance_km>0) distance_contributor_count
 from urc_candidate_20260915.team_month_exposure group by month_start
), rebuilt as (
 select jsonb_agg(m.item || jsonb_build_object(
 'exposure_hours',t.hours,'distance_km',t.distance_km,
 'exposure_contributor_count',t.exposure_contributor_count,
 'distance_contributor_count',t.distance_contributor_count)
 order by m.ordinality) monthly
 from urc_candidate_20260915.diagnosis_family_base_league_payloads_v1 p
 cross join lateral jsonb_array_elements(p.dashboard->'monthly') with ordinality m(item,ordinality)
 join totals t on t.month_start=case when m.item->>'month' ~ '^[0-9]{4}-[0-9]{2}$'
 then to_date(m.item->>'month','YYYY-MM') else to_date(m.item->>'month','Mon YYYY') end
 where season='2025-26'
)
update urc_candidate_20260915.diagnosis_family_base_league_payloads_v1
set dashboard=jsonb_set(dashboard,'{monthly}',rebuilt.monthly) from rebuilt where season='2025-26';

-- Reuse the accepted HSR calculations, adding the exact user-selected source fields.
create table urc_candidate_20260915.hsr_team_season_metadata_v1 as
select * from analysis.hsr_team_season_metadata_v1;
update urc_candidate_20260915.hsr_team_season_metadata_v1
set source_available=true,units='metres',
 threshold_or_zone=case team_key when 'benetton' then '>18 km/h' else 'source-defined High Speed Running; threshold unspecified' end,
 comparability_status='team_defined_not_cross_team_comparable',
 accepted_row_count=case team_key when 'benetton' then 2074 else 10632 end
where season='2025-26' and team_key in ('benetton','edinburgh');
create table urc_candidate_20260915.hsr_dashboard_monthly_actual_v1 as
select * from analysis.hsr_dashboard_monthly_actual_v1
where season<>'2025-26' or team_key not in ('benetton','edinburgh');
insert into urc_candidate_20260915.hsr_dashboard_monthly_actual_v1
select '2025-26',team_key,date_trunc('month',exposure_date)::date,
 count(*),count(*) filter(where hsr_m is not null),count(*) filter(where hsr_m is null),
 sum(distance_m),sum(hsr_m),sum(distance_m) filter(where hsr_m is not null)
from urc_candidate_20260915.exposure where included group by team_key,date_trunc('month',exposure_date);
do $$ declare name text; definition text; begin
 foreach name in array array['hsr_dashboard_monthly_display_v1','hsr_dashboard_team_display_v1',
 'hsr_dashboard_league_monthly_display_v1','hsr_dashboard_league_display_v1'] loop
 definition:=pg_get_viewdef(('analysis.'||name)::regclass,true);
 execute 'create view urc_candidate_20260915.'||name||' as '||
 replace(definition,'analysis.hsr_','urc_candidate_20260915.hsr_');
 end loop;
end $$;
update urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 t
set dashboard=jsonb_set(dashboard,'{coverage}',dashboard->'coverage'||(to_jsonb(h)-array['season','team_key']))
from urc_candidate_20260915.hsr_dashboard_team_display_v1 h
where t.season='2025-26' and h.season=t.season and h.team_key=t.team_key;
update urc_candidate_20260915.diagnosis_family_base_league_payloads_v1 t
set dashboard=jsonb_set(dashboard,'{coverage}',dashboard->'coverage'||(to_jsonb(h)-'season'))
from urc_candidate_20260915.hsr_dashboard_league_display_v1 h where t.season='2025-26' and h.season=t.season;
with rebuilt as (
 select t.team_key,jsonb_agg(m.item || coalesce(to_jsonb(h)-array['season','team_key','month_start',
 'total_distance_m','exposure_row_count','valid_paired_row_count','unknown_hsr_row_count','display_denominator_m'],'{}'::jsonb)
 order by m.ordinality) monthly
 from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 t
 cross join lateral jsonb_array_elements(dashboard->'monthly') with ordinality m(item,ordinality)
 left join urc_candidate_20260915.hsr_dashboard_monthly_display_v1 h
 on h.team_key=t.team_key and h.season=t.season and h.month_start=to_date(m.item->>'month','Mon YYYY')
 where t.season='2025-26' group by t.team_key
)
update urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 t
set dashboard=jsonb_set(dashboard,'{monthly}',r.monthly) from rebuilt r where t.team_key=r.team_key and t.season='2025-26';
with rebuilt as (
 select jsonb_agg(m.item || coalesce(to_jsonb(h)-array['season','month_start'],'{}'::jsonb) order by m.ordinality) monthly
 from urc_candidate_20260915.diagnosis_family_base_league_payloads_v1 t
 cross join lateral jsonb_array_elements(dashboard->'monthly') with ordinality m(item,ordinality)
 left join urc_candidate_20260915.hsr_dashboard_league_monthly_display_v1 h
 on h.season=t.season and h.month_start=to_date(m.item->>'month','Mon YYYY') where t.season='2025-26'
)
update urc_candidate_20260915.diagnosis_family_base_league_payloads_v1
set dashboard=jsonb_set(dashboard,'{monthly}',r.monthly) from rebuilt r where season='2025-26';
with rows as (
 select jsonb_agg(jsonb_build_object('team_key',team_key)||
 (select jsonb_object_agg(key,value) from jsonb_each(dashboard->'coverage') where key=any(array[
 'is_imputed','display_note','hsr_percentage','hsr_distance_km','hsr_source_status','imputation_method',
 'comparability_status','hsr_contributor_count','actual_hsr_distance_km'])) order by team_key) hsr
 from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 where season='2025-26'
)
update urc_candidate_20260915.diagnosis_family_base_league_payloads_v1
set dashboard=jsonb_set(dashboard,'{hsr_team_comparison}',rows.hsr) from rows where season='2025-26';

create view urc_candidate_20260915.urc_diagnosis_family_rows_v1 as
select i.season,i.team_key,i.source_row,i.setting_code,i.is_time_loss,i.days_lost,
 coalesce(f.family_code,'unknown') family_code,coalesce(f.family_label,'Unknown diagnosis') family_label,
 coalesce(f.subtype_code,'subtype_unknown') subtype_code,coalesce(f.source_label,i.diagnosis_label) subtype_label
from urc_candidate_20260915.urc_canonical_injury_rows_v1 i
left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 f on f.source_label=i.diagnosis_label and f.family_code is not null;

-- CLONED_CALCULATORS

-- A contributor's injuries enter the preliminary numerator only when that same
-- team has positive source-backed exposure in the same calendar month.
create view urc_candidate_20260915.monthly_rates as
with exposure as (
 select month_start,count(*) filter(where hours>0) contributor_count,sum(hours) exposure_hours
 from urc_candidate_20260915.team_month_exposure group by month_start
), injury as (
 select e.month_start,count(i.*) filter(where i.is_time_loss) time_loss_injuries,
 coalesce(sum(i.days_lost) filter(where i.is_time_loss),0) days_lost
 from urc_candidate_20260915.team_month_exposure e
 left join urc_candidate_20260915.urc_canonical_injury_rows_v1 i
 on i.team_key=e.team_key and date_trunc('month',i.injury_date)::date=e.month_start
 where e.hours>0 group by e.month_start
)
select e.*,coalesce(i.time_loss_injuries,0) time_loss_injuries,coalesce(i.days_lost,0) days_lost,
 coalesce(i.time_loss_injuries,0)*1000/nullif(e.exposure_hours,0) incidence_per_1000h,
 coalesce(i.days_lost,0)*1000/nullif(e.exposure_hours,0) burden_per_1000h
from exposure e left join injury i using(month_start);

create function urc_candidate_20260915.dashboard(base jsonb, target_team text default null)
returns jsonb language sql stable as $$
 with calc as materialized (
 select urc_candidate_20260915.urc_canonical_injury_sections_json_v2('2025-26',target_team) sections,
 urc_candidate_20260915.diagnosis_family_rows_json_v1('2025-26',target_team) families
 )
 select base || (sections-'method') || jsonb_build_object(
 'headline',(select jsonb_agg(item || jsonb_build_object('formula',case item->>'key'
   when 'recorded_injuries' then 'count(final classified eligible injury rows, including undated)'
   when 'time_loss_injuries' then 'count(final classification = Time Loss)'
   when 'overall_incidence_per_1000h' then 'pooled recorded injuries / pooled exposure hours * 1000'
   when 'incidence_per_1000h' then 'pooled final Time Loss injuries / pooled exposure hours * 1000'
   when 'severity_mean_days' then 'known-duration Time Loss days lost / known-duration Time Loss injuries'
   when 'severity_median_days' then 'median known-duration Time Loss days lost'
   when 'burden_per_1000h' then 'known-duration Time Loss days lost / pooled exposure hours * 1000'
   else item->>'formula' end) order by ordinality)
   from jsonb_array_elements(sections->'headline') with ordinality headline(item,ordinality)),
 'injury_profiles',reporting.replace_diagnosis_profiles_v1(sections->'injury_profiles',families),
 'diagnosis_families',families,
 'illness_profiles',urc_candidate_20260915.illness_profile_rows_json_v1('2025-26',target_team),
 'illness_summary',urc_candidate_20260915.illness_summary_json_v1('2025-26',target_team),
 'preliminary_monthly_rates',case when target_team is null then (
 select jsonb_agg(jsonb_build_object('month',to_char(month_start,'YYYY-MM'),
 'contributor_count',contributor_count,'exposure_hours',exposure_hours,
 'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,
 'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,
 'qualification','Preliminary contributor-aligned rate. Includes only teams with positive source-backed exposure in this month; not the official 16-team rate.')
 order by month_start) from urc_candidate_20260915.monthly_rates) else null end,
 'monthly',case when target_team is not null then (
 select jsonb_agg(jsonb_build_object(
   'exposure_hours',null,'distance_km',null,
   'actual_hsr_distance_km',null,'hsr_distance_km',null,'hsr_percentage',null,
   'is_imputed',false,'imputation_method',null,'display_note',null,
   'hsr_contributor_count',0,'hsr_source_status','source_available_month_missing') || m order by ordinality)
 from jsonb_array_elements(sections->'monthly') with ordinality monthly(m,ordinality)) else (
 select jsonb_agg(jsonb_build_object(
   'exposure_hours',null,'distance_km',null,
   'actual_hsr_distance_km',null,'hsr_distance_km',null,'hsr_percentage',null,
   'is_imputed',false,'imputation_method',null,'display_note',null,
   'hsr_contributor_count',0,'hsr_source_status','unavailable') || m || case when r.contributor_count=16 then '{}'::jsonb else
 jsonb_build_object('overall_incidence_per_1000h',null,'incidence_per_1000h',null,'burden_per_1000h',null) end
 order by r.month_start)
 from jsonb_array_elements(sections->'monthly') m join urc_candidate_20260915.monthly_rates r
 on r.month_start=case when m->>'month' ~ '^[0-9]{4}-[0-9]{2}$' then to_date(m->>'month','YYYY-MM') else to_date(m->>'month','Mon YYYY') end) end,
 'method',(select jsonb_agg(case
   when value#>>'{}' like 'Recorded injuries use the % reviewed dashboard injury rows.'
   then to_jsonb(format('Recorded injuries use %s reviewed candidate injury rows.',
     (select item->>'value' from jsonb_array_elements(sections->'headline') item
      where item->>'key'='recorded_injuries')))
   when value#>>'{}' = 'League values pool the final active team releases.'
   then to_jsonb('League values pool the 16 candidate team datasets.'::text)
   else value end order by ordinality)
   from jsonb_array_elements(base->'method') with ordinality method(value,ordinality)),
 'limitations',(select coalesce(jsonb_agg(value),'[]'::jsonb) from jsonb_array_elements(base->'limitations') value
 where value#>>'{}' not ilike '%temporary mean%'
 and value#>>'{}' not ilike '%monthly exposure, rates and distance are unavailable%'
 and value#>>'{}' not ilike '%await%exposure%')
 ) from calc;
$$;

create table urc_candidate_20260915.team_payloads as
select team_key,season,case when season='2025-26' then urc_candidate_20260915.dashboard(dashboard,team_key)
 else dashboard end dashboard from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1;
create table urc_candidate_20260915.league_payloads as
select season,case when season='2025-26' then urc_candidate_20260915.dashboard(dashboard)
 else dashboard end dashboard from urc_candidate_20260915.diagnosis_family_base_league_payloads_v1;
create table urc_candidate_20260915.team_comparisons as
select current.team_key,reporting.build_season_comparison_v5(previous.dashboard,current.dashboard,'team') comparison
from urc_candidate_20260915.team_payloads current join urc_candidate_20260915.team_payloads previous using(team_key)
where current.season='2025-26' and previous.season='2024-25';
create table urc_candidate_20260915.league_comparison as
select reporting.build_season_comparison_v5(previous.dashboard,current.dashboard,'league') comparison
from urc_candidate_20260915.league_payloads current cross join urc_candidate_20260915.league_payloads previous
where current.season='2025-26' and previous.season='2024-25';
revoke all on all tables in schema urc_candidate_20260915 from public,anon,authenticated,web_reader;
revoke all on all functions in schema urc_candidate_20260915 from public,anon,authenticated,web_reader;

-- Prove this transaction has not changed either served season.
do $$ begin
 if (select digest from _candidate_served_before where kind='teams') <>
 (select md5(jsonb_agg(to_jsonb(t) order by season,team_key)::text) from reporting.latest_team_dashboard_v8 t)
 or (select digest from _candidate_served_before where kind='league') <>
 (select md5(jsonb_agg(to_jsonb(t) order by season)::text) from reporting.latest_league_dashboard_v8 t)
 then raise exception 'Candidate changed served dashboards'; end if;
 if (select count(*) from urc_candidate_20260915.team_payloads)<>32
 or (select count(*) from urc_candidate_20260915.league_payloads)<>2
 or (select count(*) from urc_candidate_20260915.team_comparisons)<>16
 then raise exception 'Incomplete candidate payload set'; end if;
end $$;
