-- Private candidate only. No active builds, reporting readers or release selectors change.
do $$ begin
  if (select payload_sha256 from _pipeline_params_attestation) <> 'beb0bcc513b4fb59f2683395ace7c98d0628886a6cb21206b4361ef22339bac4'
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
create table urc_candidate_20260915.irfu_diagnosis_family_mapping (
 team_key text not null,
 source_row integer not null,
 source_label text not null,
 osics10_code text not null,
 body_location text not null,
 pathology text not null,
 family_code text not null,
 family_label text not null,
 subtype_code text not null,
 mapping_basis text not null,
 primary key(team_key,source_row)
);
insert into urc_candidate_20260915.irfu_diagnosis_family_mapping
select (jsonb_populate_record(null::urc_candidate_20260915.irfu_diagnosis_family_mapping,value->'row')).*
from _pipeline_params where value->>'kind'='diagnosis_mapping';
do $$ begin
 if (select count(*) from urc_candidate_20260915.irfu_diagnosis_family_mapping)<>402
 or (select count(*) from urc_candidate_20260915.irfu_diagnosis_family_mapping where mapping_basis='inherited_diagnosis')<>256
 or (select count(*) from urc_candidate_20260915.irfu_diagnosis_family_mapping where mapping_basis='existing_family_alias')<>139
 or (select count(*) from urc_candidate_20260915.irfu_diagnosis_family_mapping where mapping_basis='candidate_identity_group')<>7
 or exists(select 1 from urc_candidate_20260915.irfu_diagnosis_family_mapping
   where family_code='unknown' or family_label='Unknown diagnosis')
 or exists(select 1 from urc_candidate_20260915.urc_canonical_injury_rows_v1 i
   left join urc_candidate_20260915.irfu_diagnosis_family_mapping m using(team_key,source_row)
   where i.team_key in ('connacht','leinster','munster','ulster') and m.source_row is null)
 then raise exception 'IRFU diagnosis-family mapping is incomplete'; end if;
end $$;
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
 coalesce(m.family_code,f.family_code,'unknown') family_code,
 coalesce(m.family_label,f.family_label,'Unknown diagnosis') family_label,
 coalesce(m.subtype_code,f.subtype_code,'subtype_unknown') subtype_code,
 coalesce(m.source_label,f.source_label,i.diagnosis_label) subtype_label
from urc_candidate_20260915.urc_canonical_injury_rows_v1 i
left join urc_candidate_20260915.irfu_diagnosis_family_mapping m
 on m.team_key=i.team_key and m.source_row=i.source_row
left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 f on f.source_label=i.diagnosis_label and f.family_code is not null;

create view urc_candidate_20260915.urc_diagnosis_family_team_exposure_v1 as
 SELECT payload.season,
    payload.team_key,
    setting.setting_code,
        CASE setting.setting_code
            WHEN 'all'::text THEN (payload.dashboard #>> '{coverage,hours}'::text[])::numeric
            WHEN 'match'::text THEN (payload.dashboard #>> '{coverage,match_hours}'::text[])::numeric
            WHEN 'training'::text THEN (payload.dashboard #>> '{coverage,training_hours}'::text[])::numeric
            ELSE NULL::numeric
        END AS exposure_hours
   FROM urc_candidate_20260915.diagnosis_family_base_team_payloads_v1 payload
     CROSS JOIN ( VALUES ('all'::text), ('match'::text), ('training'::text), ('unknown'::text)) setting(setting_code);

create view urc_candidate_20260915.urc_diagnosis_family_team_subtypes_v1 as
 WITH expanded AS (
         SELECT "row".season,
            "row".team_key,
            "row".source_row,
            setting.setting_code,
            "row".is_time_loss,
            "row".days_lost,
            "row".family_code,
            "row".family_label,
            "row".subtype_code,
            "row".subtype_label
           FROM urc_candidate_20260915.urc_diagnosis_family_rows_v1 "row"
             CROSS JOIN LATERAL ( SELECT 'all'::text AS setting_code
                UNION ALL
                 SELECT "row".setting_code) setting
        )
 SELECT season,
    team_key,
    setting_code,
    family_code,
    family_label,
    subtype_code,
    subtype_label,
    count(*) AS recorded_injuries,
    count(*) FILTER (WHERE is_time_loss) AS time_loss_injuries,
    count(*) FILTER (WHERE is_time_loss AND days_lost IS NOT NULL) AS known_duration_time_loss_injuries,
    COALESCE(sum(days_lost) FILTER (WHERE is_time_loss), 0::numeric) AS days_lost
   FROM expanded
  GROUP BY season, team_key, setting_code, family_code, family_label, subtype_code, subtype_label;

create view urc_candidate_20260915.urc_diagnosis_family_team_families_v1 as
 WITH grouped AS (
         SELECT urc_diagnosis_family_team_subtypes_v1.season,
            urc_diagnosis_family_team_subtypes_v1.team_key,
            urc_diagnosis_family_team_subtypes_v1.setting_code,
            urc_diagnosis_family_team_subtypes_v1.family_code,
            urc_diagnosis_family_team_subtypes_v1.family_label,
            sum(urc_diagnosis_family_team_subtypes_v1.recorded_injuries)::bigint AS recorded_injuries,
            sum(urc_diagnosis_family_team_subtypes_v1.time_loss_injuries)::bigint AS time_loss_injuries,
            sum(urc_diagnosis_family_team_subtypes_v1.known_duration_time_loss_injuries)::bigint AS known_duration_time_loss_injuries,
            sum(urc_diagnosis_family_team_subtypes_v1.days_lost) AS days_lost
           FROM urc_candidate_20260915.urc_diagnosis_family_team_subtypes_v1
          GROUP BY urc_diagnosis_family_team_subtypes_v1.season, urc_diagnosis_family_team_subtypes_v1.team_key, urc_diagnosis_family_team_subtypes_v1.setting_code, urc_diagnosis_family_team_subtypes_v1.family_code, urc_diagnosis_family_team_subtypes_v1.family_label
        )
 SELECT grouped.season,
    grouped.team_key,
    grouped.setting_code,
    grouped.family_code,
    grouped.family_label,
    grouped.recorded_injuries,
    grouped.time_loss_injuries,
    grouped.known_duration_time_loss_injuries,
    grouped.days_lost,
    exposure.exposure_hours,
    (grouped.time_loss_injuries * 1000)::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS incidence_per_1000h,
    grouped.days_lost * 1000::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS burden_per_1000h,
    grouped.days_lost / NULLIF(grouped.known_duration_time_loss_injuries, 0)::numeric AS mean_severity_days
   FROM grouped
     JOIN urc_candidate_20260915.urc_diagnosis_family_team_exposure_v1 exposure USING (season, team_key, setting_code);

create view urc_candidate_20260915.urc_diagnosis_family_league_exposure_v1 as
 SELECT season,
    setting_code,
        CASE
            WHEN count(exposure_hours) = 16 THEN sum(exposure_hours)
            ELSE NULL::numeric
        END AS exposure_hours
   FROM urc_candidate_20260915.urc_diagnosis_family_team_exposure_v1
  GROUP BY season, setting_code;

create view urc_candidate_20260915.urc_diagnosis_family_league_subtypes_v1 as
 SELECT season,
    setting_code,
    family_code,
    family_label,
    subtype_code,
    subtype_label,
    sum(recorded_injuries)::bigint AS recorded_injuries,
    sum(time_loss_injuries)::bigint AS time_loss_injuries,
    sum(known_duration_time_loss_injuries)::bigint AS known_duration_time_loss_injuries,
    sum(days_lost) AS days_lost
   FROM urc_candidate_20260915.urc_diagnosis_family_team_subtypes_v1
  GROUP BY season, setting_code, family_code, family_label, subtype_code, subtype_label;

create view urc_candidate_20260915.urc_diagnosis_family_league_families_v1 as
 WITH grouped AS (
         SELECT urc_diagnosis_family_league_subtypes_v1.season,
            urc_diagnosis_family_league_subtypes_v1.setting_code,
            urc_diagnosis_family_league_subtypes_v1.family_code,
            urc_diagnosis_family_league_subtypes_v1.family_label,
            sum(urc_diagnosis_family_league_subtypes_v1.recorded_injuries)::bigint AS recorded_injuries,
            sum(urc_diagnosis_family_league_subtypes_v1.time_loss_injuries)::bigint AS time_loss_injuries,
            sum(urc_diagnosis_family_league_subtypes_v1.known_duration_time_loss_injuries)::bigint AS known_duration_time_loss_injuries,
            sum(urc_diagnosis_family_league_subtypes_v1.days_lost) AS days_lost
           FROM urc_candidate_20260915.urc_diagnosis_family_league_subtypes_v1
          GROUP BY urc_diagnosis_family_league_subtypes_v1.season, urc_diagnosis_family_league_subtypes_v1.setting_code, urc_diagnosis_family_league_subtypes_v1.family_code, urc_diagnosis_family_league_subtypes_v1.family_label
        )
 SELECT grouped.season,
    grouped.setting_code,
    grouped.family_code,
    grouped.family_label,
    grouped.recorded_injuries,
    grouped.time_loss_injuries,
    grouped.known_duration_time_loss_injuries,
    grouped.days_lost,
    exposure.exposure_hours,
    (grouped.time_loss_injuries * 1000)::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS incidence_per_1000h,
    grouped.days_lost * 1000::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS burden_per_1000h,
    grouped.days_lost / NULLIF(grouped.known_duration_time_loss_injuries, 0)::numeric AS mean_severity_days
   FROM grouped
     JOIN urc_candidate_20260915.urc_diagnosis_family_league_exposure_v1 exposure USING (season, setting_code);

create view urc_candidate_20260915.urc_illness_team_profiles_v1 as
 WITH grouped AS (
         SELECT urc_illness_profile_rows_v2.season,
            urc_illness_profile_rows_v2.team_key,
            urc_illness_profile_rows_v2.illness_code,
            urc_illness_profile_rows_v2.illness_label,
            count(*) AS recorded_illnesses,
            count(*) FILTER (WHERE urc_illness_profile_rows_v2.duration_known) AS known_duration_illnesses,
            COALESCE(sum(urc_illness_profile_rows_v2.days_lost) FILTER (WHERE urc_illness_profile_rows_v2.duration_known), 0::numeric) AS days_lost
           FROM urc_candidate_20260915.urc_illness_profile_rows_v2
          GROUP BY urc_illness_profile_rows_v2.season, urc_illness_profile_rows_v2.team_key, urc_illness_profile_rows_v2.illness_code, urc_illness_profile_rows_v2.illness_label
        )
 SELECT grouped.season,
    grouped.team_key,
    grouped.illness_code,
    grouped.illness_label,
    grouped.recorded_illnesses,
    grouped.known_duration_illnesses,
    grouped.days_lost,
    'all'::text AS setting,
    exposure.exposure_hours,
    (grouped.recorded_illnesses * 1000)::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS incidence_per_1000h,
    grouped.days_lost * 1000::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS burden_per_1000h,
    grouped.days_lost / NULLIF(grouped.known_duration_illnesses, 0)::numeric AS mean_severity_days
   FROM grouped
     JOIN urc_candidate_20260915.urc_diagnosis_family_team_exposure_v1 exposure ON exposure.season = grouped.season AND exposure.team_key = grouped.team_key AND exposure.setting_code = 'all'::text;

create view urc_candidate_20260915.urc_illness_league_profiles_v1 as
 WITH grouped AS (
         SELECT urc_illness_team_profiles_v1.season,
            urc_illness_team_profiles_v1.illness_code,
            urc_illness_team_profiles_v1.illness_label,
            sum(urc_illness_team_profiles_v1.recorded_illnesses)::bigint AS recorded_illnesses,
            sum(urc_illness_team_profiles_v1.known_duration_illnesses)::bigint AS known_duration_illnesses,
            sum(urc_illness_team_profiles_v1.days_lost) AS days_lost
           FROM urc_candidate_20260915.urc_illness_team_profiles_v1
          GROUP BY urc_illness_team_profiles_v1.season, urc_illness_team_profiles_v1.illness_code, urc_illness_team_profiles_v1.illness_label
        )
 SELECT grouped.season,
    grouped.illness_code,
    grouped.illness_label,
    grouped.recorded_illnesses,
    grouped.known_duration_illnesses,
    grouped.days_lost,
    'all'::text AS setting,
    exposure.exposure_hours,
    (grouped.recorded_illnesses * 1000)::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS incidence_per_1000h,
    grouped.days_lost * 1000::numeric / NULLIF(exposure.exposure_hours, 0::numeric) AS burden_per_1000h,
    grouped.days_lost / NULLIF(grouped.known_duration_illnesses, 0)::numeric AS mean_severity_days
   FROM grouped
     JOIN urc_candidate_20260915.urc_diagnosis_family_league_exposure_v1 exposure ON exposure.season = grouped.season AND exposure.setting_code = 'all'::text;

create view urc_candidate_20260915.urc_2025_26_setting_severity_v1 as
 WITH expanded AS (
         SELECT injury.team_key,
            setting.setting_code,
            injury.severity_code,
            injury.is_time_loss,
            injury.days_lost
           FROM urc_candidate_20260915.urc_2025_26_canonical_injury_rows_v1 injury
             CROSS JOIN LATERAL ( SELECT 'all'::text AS setting_code
                UNION ALL
                 SELECT injury.setting_code
                  WHERE injury.setting_code = ANY (ARRAY['match'::text, 'training'::text])) setting
        )
 SELECT team_key,
    setting_code,
    severity_code,
        CASE severity_code
            WHEN 'zero_days_medical_attention_only'::text THEN 'Medical attention'::text
            WHEN 'one_day'::text THEN '1 day'::text
            WHEN 'two_to_three_days'::text THEN '2-3 days'::text
            WHEN 'four_to_seven_days'::text THEN '4-7 days'::text
            WHEN 'eight_to_twenty_eight_days'::text THEN '8-28 days'::text
            WHEN 'greater_than_twenty_eight_days'::text THEN '>28 days'::text
            ELSE 'Unknown or censored'::text
        END AS severity_label,
    count(*) AS recorded_injuries,
    count(*) FILTER (WHERE is_time_loss) AS time_loss_injuries,
    COALESCE(sum(days_lost) FILTER (WHERE is_time_loss), 0::bigint)::numeric AS days_lost
   FROM expanded
  GROUP BY team_key, setting_code, severity_code;

CREATE OR REPLACE FUNCTION urc_candidate_20260915.illness_summary_json_v1(target_season text, target_team text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'analysis', 'pg_temp'
AS $function$
  with exposure as (
    select exposure_hours
    from urc_candidate_20260915.urc_diagnosis_family_league_exposure_v1
    where target_team is null and season = target_season and setting_code = 'all'
    union all
    select exposure_hours
    from urc_candidate_20260915.urc_diagnosis_family_team_exposure_v1
    where target_team is not null and season = target_season
      and team_key = target_team and setting_code = 'all'
  ), totals as (
    select coalesce(sum(recorded_illnesses), 0)::bigint as recorded_illnesses,
      coalesce(sum(known_duration_illnesses), 0)::bigint
        as known_duration_illnesses,
      coalesce(sum(days_lost), 0)::numeric as days_lost
    from (
      select recorded_illnesses, known_duration_illnesses, days_lost
      from urc_candidate_20260915.urc_illness_league_profiles_v1
      where target_team is null and season = target_season
      union all
      select recorded_illnesses, known_duration_illnesses, days_lost
      from urc_candidate_20260915.urc_illness_team_profiles_v1
      where target_team is not null and season = target_season
        and team_key = target_team
    ) rows
  )
  select jsonb_build_object(
    'setting', 'all', 'recorded_illnesses', totals.recorded_illnesses,
    'known_duration_illnesses', totals.known_duration_illnesses,
    'days_lost', totals.days_lost, 'exposure_hours', exposure.exposure_hours,
    'incidence_per_1000h', totals.recorded_illnesses * 1000 /
      nullif(exposure.exposure_hours, 0),
    'burden_per_1000h', totals.days_lost * 1000 /
      nullif(exposure.exposure_hours, 0),
    'mean_severity_days', totals.days_lost /
      nullif(totals.known_duration_illnesses, 0),
    'qualification', 'Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training.'
  )
  from totals cross join exposure;
$function$
;

CREATE OR REPLACE FUNCTION urc_candidate_20260915.illness_profile_rows_json_v1(target_season text, target_team text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'analysis', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', illness_code, 'label', illness_label, 'setting', setting,
    'recorded_illnesses', recorded_illnesses,
    'known_duration_illnesses', known_duration_illnesses,
    'days_lost', days_lost, 'exposure_hours', exposure_hours,
    'incidence_per_1000h', incidence_per_1000h,
    'burden_per_1000h', burden_per_1000h,
    'mean_severity_days', mean_severity_days
  ) order by recorded_illnesses desc, illness_label, illness_code), '[]'::jsonb)
  from (
    select illness_code, illness_label, setting, recorded_illnesses,
      known_duration_illnesses, days_lost, exposure_hours,
      incidence_per_1000h, burden_per_1000h, mean_severity_days
    from urc_candidate_20260915.urc_illness_league_profiles_v1
    where target_team is null and season = target_season
    union all
    select illness_code, illness_label, setting, recorded_illnesses,
      known_duration_illnesses, days_lost, exposure_hours,
      incidence_per_1000h, burden_per_1000h, mean_severity_days
    from urc_candidate_20260915.urc_illness_team_profiles_v1
    where target_team is not null and season = target_season
      and team_key = target_team
  ) rows;
$function$
;

CREATE OR REPLACE FUNCTION urc_candidate_20260915.diagnosis_family_rows_json_v1(target_season text, target_team text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'analysis'
AS $function$
declare result jsonb;
begin
  if target_team is null then
    with subtypes as materialized (
      select * from urc_candidate_20260915.urc_diagnosis_family_league_subtypes_v1
      where season = target_season
    ), subtype_json as (
      select season, setting_code, family_code,
        jsonb_agg(jsonb_build_object(
          'code', subtype_code, 'label', subtype_label,
          'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries,
          'known_duration_time_loss_injuries',
            known_duration_time_loss_injuries,
          'days_lost', days_lost
        ) order by recorded_injuries desc, subtype_label, subtype_code) as rows
      from subtypes
      group by season, setting_code, family_code
    ), family_counts as (
      select season, setting_code, family_code, family_label,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint
          as known_duration_time_loss_injuries,
        sum(days_lost)::numeric as days_lost
      from subtypes
      group by season, setting_code, family_code, family_label
    ), families as materialized (
      select family_counts.*, exposure.exposure_hours,
        family_counts.time_loss_injuries * 1000 /
          nullif(exposure.exposure_hours, 0) as incidence_per_1000h,
        family_counts.days_lost * 1000 /
          nullif(exposure.exposure_hours, 0) as burden_per_1000h,
        family_counts.days_lost /
          nullif(family_counts.known_duration_time_loss_injuries, 0)
          as mean_severity_days
      from family_counts
      join urc_candidate_20260915.urc_diagnosis_family_league_exposure_v1 exposure
        using (season, setting_code)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', families.family_code, 'label', families.family_label,
      'setting', families.setting_code,
      'recorded_injuries', families.recorded_injuries,
      'time_loss_injuries', families.time_loss_injuries,
      'known_duration_time_loss_injuries',
        families.known_duration_time_loss_injuries,
      'days_lost', families.days_lost,
      'exposure_hours', families.exposure_hours,
      'incidence_per_1000h', families.incidence_per_1000h,
      'burden_per_1000h', families.burden_per_1000h,
      'mean_severity_days', families.mean_severity_days,
      'subtypes', subtype_json.rows
    ) order by array_position(array['all','match','training','unknown'],
      families.setting_code), families.recorded_injuries desc,
      families.family_label, families.family_code), '[]'::jsonb)
    into result
    from families
    join subtype_json using (season, setting_code, family_code);
  else
    with subtypes as materialized (
      select * from urc_candidate_20260915.urc_diagnosis_family_team_subtypes_v1
      where season = target_season and team_key = target_team
    ), subtype_json as (
      select season, team_key, setting_code, family_code,
        jsonb_agg(jsonb_build_object(
          'code', subtype_code, 'label', subtype_label,
          'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries,
          'known_duration_time_loss_injuries',
            known_duration_time_loss_injuries,
          'days_lost', days_lost
        ) order by recorded_injuries desc, subtype_label, subtype_code) as rows
      from subtypes
      group by season, team_key, setting_code, family_code
    ), family_counts as (
      select season, team_key, setting_code, family_code, family_label,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint
          as known_duration_time_loss_injuries,
        sum(days_lost)::numeric as days_lost
      from subtypes
      group by season, team_key, setting_code, family_code, family_label
    ), families as materialized (
      select family_counts.*, exposure.exposure_hours,
        family_counts.time_loss_injuries * 1000 /
          nullif(exposure.exposure_hours, 0) as incidence_per_1000h,
        family_counts.days_lost * 1000 /
          nullif(exposure.exposure_hours, 0) as burden_per_1000h,
        family_counts.days_lost /
          nullif(family_counts.known_duration_time_loss_injuries, 0)
          as mean_severity_days
      from family_counts
      join urc_candidate_20260915.urc_diagnosis_family_team_exposure_v1 exposure
        using (season, team_key, setting_code)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', families.family_code, 'label', families.family_label,
      'setting', families.setting_code,
      'recorded_injuries', families.recorded_injuries,
      'time_loss_injuries', families.time_loss_injuries,
      'known_duration_time_loss_injuries',
        families.known_duration_time_loss_injuries,
      'days_lost', families.days_lost,
      'exposure_hours', families.exposure_hours,
      'incidence_per_1000h', families.incidence_per_1000h,
      'burden_per_1000h', families.burden_per_1000h,
      'mean_severity_days', families.mean_severity_days,
      'subtypes', subtype_json.rows
    ) order by array_position(array['all','match','training','unknown'],
      families.setting_code), families.recorded_injuries desc,
      families.family_label, families.family_code), '[]'::jsonb)
    into result
    from families
    join subtype_json using (season, team_key, setting_code, family_code);
  end if;
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION urc_candidate_20260915.urc_2025_26_setting_severity_json_v1(target_team text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'analysis', 'pg_temp'
AS $function$
  with rows as (
    select setting_code, severity_code, severity_label,
      sum(recorded_injuries)::bigint as recorded_injuries,
      sum(time_loss_injuries)::bigint as time_loss_injuries,
      sum(days_lost)::numeric as days_lost
    from urc_candidate_20260915.urc_2025_26_setting_severity_v1
    where target_team is null or team_key = target_team
    group by setting_code, severity_code, severity_label
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', severity_code, 'label', severity_label, 'setting', setting_code,
    'recorded_injuries', recorded_injuries,
    'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost
  ) order by array_position(array['all','match','training','unknown'], setting_code),
    array_position(array['zero_days_medical_attention_only','one_day',
      'two_to_three_days','four_to_seven_days','eight_to_twenty_eight_days',
      'greater_than_twenty_eight_days','unknown_or_censored'], severity_code)), '[]'::jsonb)
  from rows;
$function$
;

CREATE OR REPLACE FUNCTION urc_candidate_20260915.urc_canonical_injury_sections_json_v2(target_season text, target_team text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'analysis', 'reporting', 'pg_temp'
AS $function$
  with payload as (
    select dashboard
    from urc_candidate_20260915.diagnosis_family_base_league_payloads_v1
    where target_team is null and season = target_season
    union all
    select dashboard
    from urc_candidate_20260915.diagnosis_family_base_team_payloads_v1
    where target_team is not null and season = target_season
      and team_key = target_team
  ), rows as materialized (
    select * from urc_candidate_20260915.urc_canonical_injury_rows_v1 injury
    where injury.season = target_season
      and (target_team is null or injury.team_key = target_team)
  ), coverage as (
    select (dashboard #>> '{coverage,hours}')::numeric as all_hours,
      (dashboard #>> '{coverage,match_hours}')::numeric as match_hours,
      (dashboard #>> '{coverage,training_hours}')::numeric as training_hours
    from payload
  ), summary as (
    select count(*)::bigint as recorded_injuries,
      count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
      count(*) filter (where is_time_loss and days_lost is not null)::bigint
        as known_duration_time_loss_injuries,
      coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost,
      percentile_cont(0.5) within group (order by days_lost)
        filter (where is_time_loss and days_lost is not null) as median_severity_days
    from rows
  ), monthly_source as (
    select month, case when month ->> 'month' ~ '^[0-9]{4}-[0-9]{2}$'
      then to_date(month ->> 'month', 'YYYY-MM')
      else to_date(month ->> 'month', 'Mon YYYY') end as month_start
    from payload cross join lateral jsonb_array_elements(dashboard -> 'monthly') month
  ), monthly_injuries as (
    select date_trunc('month', injury_date)::date as month_start,
      count(*)::bigint as recorded_injuries,
      count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
      coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
    from rows where injury_date is not null
    group by date_trunc('month', injury_date)
  ), settings as (
    select domain.setting_code,
      count(rows.*) filter (
        where domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      )::bigint as recorded_injuries,
      count(rows.*) filter (where rows.is_time_loss and (
        domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      ))::bigint as time_loss_injuries,
      count(rows.*) filter (where rows.is_time_loss and rows.days_lost is not null
        and (domain.setting_code = 'all' or rows.setting_code = domain.setting_code)
      )::bigint as known_duration_time_loss_injuries,
      coalesce(sum(rows.days_lost) filter (where rows.is_time_loss and (
        domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      )), 0)::numeric as days_lost
    from (values ('all'::text), ('match'::text), ('training'::text),
      ('unknown'::text)) domain(setting_code)
    left join rows on true
    group by domain.setting_code
  ), profiles as (
    select setting.setting_code, dimension.dimension, dimension.code,
      dimension.label, count(*)::bigint as recorded_injuries,
      count(*) filter (where injury.is_time_loss)::bigint as time_loss_injuries,
      count(*) filter (where injury.is_time_loss and injury.days_lost is not null)::bigint
        as known_duration_time_loss_injuries,
      coalesce(sum(injury.days_lost) filter (where injury.is_time_loss), 0)::numeric
        as days_lost
    from rows injury
    cross join lateral (
      select 'all'::text as setting_code union all select injury.setting_code
    ) setting
    cross join lateral (values
      ('body_location'::text, injury.body_location_code, injury.body_location_label),
      ('injury_type'::text, injury.injury_type_code, injury.injury_type_label)
    ) dimension(dimension, code, label)
    group by setting.setting_code, dimension.dimension, dimension.code,
      dimension.label
  ), severity as (
    select setting.setting_code, band.severity_code,
      count(rows.*) filter (where rows.severity_code = band.severity_code)::bigint
        as recorded_injuries,
      count(rows.*) filter (where rows.severity_code = band.severity_code
        and rows.is_time_loss)::bigint as time_loss_injuries,
      coalesce(sum(rows.days_lost) filter (where rows.severity_code = band.severity_code
        and rows.is_time_loss), 0)::numeric as days_lost
    from (values ('all'::text), ('match'::text), ('training'::text))
      setting(setting_code)
    cross join (values ('zero_days_medical_attention_only'::text),
      ('one_day'::text), ('two_to_three_days'::text),
      ('four_to_seven_days'::text), ('eight_to_twenty_eight_days'::text),
      ('greater_than_twenty_eight_days'::text), ('unknown_or_censored'::text))
      band(severity_code)
    left join rows on (setting.setting_code = 'all'
      or rows.setting_code = setting.setting_code)
    group by setting.setting_code, band.severity_code
  ), contact as (
    select setting.setting_code, context.contact_context, context.contact_label,
      count(rows.*) filter (where rows.contact_context = context.contact_context)::bigint
        as recorded_injuries,
      count(rows.*) filter (where rows.contact_context = context.contact_context
        and rows.is_time_loss)::bigint as time_loss_injuries
    from (values ('all'::text), ('match'::text), ('training'::text),
      ('unknown'::text)) setting(setting_code)
    cross join (values ('contact'::text, 'Contact'::text),
      ('non_contact'::text, 'Non-contact'::text),
      ('unknown'::text, 'Unknown'::text))
      context(contact_context, contact_label)
    left join rows on (setting.setting_code = 'all'
      or rows.setting_code = setting.setting_code)
    group by setting.setting_code, context.contact_context, context.contact_label
  ), profile_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'dimension', dimension, 'code', code, 'label', label,
      'setting', setting_code, 'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by dimension, setting_code, code), '[]'::jsonb) as rows
    from profiles cross join coverage
  )
  select jsonb_build_object(
    'method', jsonb_build_array(
      'Recorded injuries use approved canonically injury-coded lineage rows.',
      'Time-loss status uses final classification. Days lost use known duration only.'
    ),
    'headline', jsonb_build_array(
      jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', summary.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(canonical Problem type = Injury rows, including undated)'),
      jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', summary.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(canonical injury final classification = Time Loss)'),
      jsonb_build_object('key', 'overall_incidence_per_1000h',
        'label', 'Overall incidence',
        'value', summary.recorded_injuries * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'per 1,000 player-hours', 'numerator', summary.recorded_injuries,
        'denominator', coverage.all_hours,
        'formula', 'canonical recorded injuries / released exposure hours * 1000'),
      jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', summary.time_loss_injuries * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries,
        'denominator', coverage.all_hours,
        'formula', 'canonical Time Loss injuries / released exposure hours * 1000'),
      jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity',
        'value', summary.days_lost /
          nullif(summary.known_duration_time_loss_injuries, 0),
        'unit', 'days lost per injury', 'numerator', summary.days_lost,
        'denominator', summary.known_duration_time_loss_injuries,
        'formula', 'known-duration Time Loss days / known-duration Time Loss injuries'),
      jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity',
        'value', summary.median_severity_days, 'unit', 'days lost per injury',
        'denominator', summary.known_duration_time_loss_injuries,
        'formula', 'median known-duration Time Loss days'),
      jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden',
        'value', summary.days_lost * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost,
        'denominator', coverage.all_hours,
        'formula', 'known-duration Time Loss days / released exposure hours * 1000')
    ),
    'monthly', (select coalesce(jsonb_agg((monthly_source.month -
      array['recorded_injuries','time_loss_injuries','days_lost',
        'overall_incidence_per_1000h','incidence_per_1000h','burden_per_1000h'])
      || jsonb_build_object(
        'recorded_injuries', coalesce(monthly_injuries.recorded_injuries, 0),
        'time_loss_injuries', coalesce(monthly_injuries.time_loss_injuries, 0),
        'days_lost', coalesce(monthly_injuries.days_lost, 0),
        'overall_incidence_per_1000h',
          coalesce(monthly_injuries.recorded_injuries, 0) * 1000 /
            nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0),
        'incidence_per_1000h',
          coalesce(monthly_injuries.time_loss_injuries, 0) * 1000 /
            nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0),
        'burden_per_1000h', coalesce(monthly_injuries.days_lost, 0) * 1000 /
          nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0)
      ) order by monthly_source.month_start), '[]'::jsonb)
      from monthly_source left join monthly_injuries using (month_start)),
    'body_locations', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.all_hours,
      'incidence_per_1000h', time_loss_injuries * 1000 /
        nullif(coverage.all_hours, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(coverage.all_hours, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by code), '[]'::jsonb) from profiles
      where dimension = 'body_location' and setting_code = 'all'),
    'injury_types', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.all_hours,
      'incidence_per_1000h', time_loss_injuries * 1000 /
        nullif(coverage.all_hours, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(coverage.all_hours, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by time_loss_injuries desc, code), '[]'::jsonb) from profiles
      where dimension = 'injury_type' and setting_code = 'all'),
    'injury_profiles', profile_json.rows,
    'injury_type_families', analysis.injury_type_families_from_payload_v3(
      profile_json.rows
    ),
    'severity_distribution', (select coalesce(jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'key', severity_code,
      'label', case severity_code
        when 'zero_days_medical_attention_only' then 'Medical attention'
        when 'one_day' then '1 day' when 'two_to_three_days' then '2-3 days'
        when 'four_to_seven_days' then '4-7 days'
        when 'eight_to_twenty_eight_days' then '8-28 days'
        when 'greater_than_twenty_eight_days' then '>28 days'
        else 'Unknown or censored' end,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost
    ) order by array_position(array['all','match','training'], setting_code),
      array_position(array['zero_days_medical_attention_only','one_day',
        'two_to_three_days','four_to_seven_days','eight_to_twenty_eight_days',
        'greater_than_twenty_eight_days','unknown_or_censored'], severity_code)
    ), '[]'::jsonb) from severity),
    'setting_split', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', setting_code, 'label', initcap(setting_code),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', recorded_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all','match','training','unknown'], setting_code)),
      '[]'::jsonb) from settings),
    'setting_metrics', (select coalesce(jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'label', initcap(setting_code),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', recorded_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all','match','training','unknown'], setting_code)),
      '[]'::jsonb) from settings),
    'contact_distribution', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', contact_context, 'label', contact_label, 'setting', setting_code,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries
    ) order by array_position(array['all','match','training','unknown'], setting_code),
      array_position(array['contact','non_contact','unknown'], contact_context)),
      '[]'::jsonb) from contact)
  )
  from summary cross join coverage cross join profile_json;
$function$
;


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
