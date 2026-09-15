-- Promote the reviewed aggregate candidate to the existing private-review readers.
-- Source rows and the retained immutable league release remain unchanged.
do $$ begin
 if (select count(*) from urc_candidate_20260915.provenance) <> 1
 or (select count(*) from urc_candidate_20260915.team_payloads) <> 32
 or (select count(*) from urc_candidate_20260915.league_payloads) <> 2
 or (select count(*) from urc_candidate_20260915.team_comparisons) <> 16
 or (select count(*) from urc_candidate_20260915.league_comparison) <> 1
 or (select count(*) from reporting.latest_team_dashboard_v8) <> 32
 or (select count(*) from reporting.latest_league_dashboard_v8) <> 2
 or (select count(*) from reporting.latest_dashboard_cache_token_v2) <> 2
 or (select count(*) from reporting.latest_approved_league_bundle_v6 where season='2025-26') <> 1
 or (select evidence->>'root_sha256' from urc_candidate_20260915.provenance)
      is distinct from '206893c3d1286020a2d489b707913dc4f4c9ca87a84b6e8e02813a2cd856c9ec'
 or (select evidence->>'diagnosis_mapping_sha256' from urc_candidate_20260915.provenance)
      is distinct from '3dd593231d1e98cfdb8f0a23f4df7bfabb868fcdaafd2e606e6f8941a85b2d8d'
 or (select evidence->>'baseline_sha256' from urc_candidate_20260915.provenance)
      is distinct from 'd409b11ebf0805a909dc0752514e26c24ab9edf8cf94a2ed65dfbde1bd6564e2'
 or (select evidence->>'rule_version' from urc_candidate_20260915.provenance)
      is distinct from 'urc_intake_candidate_20260915_v2'
 or (select md5(jsonb_agg(to_jsonb(t) order by season,team_key)::text)
     from reporting.latest_team_dashboard_v8 t) is distinct from '3794137499366267b074a6028a919836'
 or (select md5(jsonb_agg(to_jsonb(t) order by season)::text)
     from reporting.latest_league_dashboard_v8 t) is distinct from '09f31a6276228b3fe42719e89c64ddb6'
 or (select md5(jsonb_agg(to_jsonb(t) order by season,team_key)::text)
     from urc_candidate_20260915.team_payloads t) is distinct from 'af21dfa4899908dd2767467ad5954e8b'
 or (select md5(jsonb_agg(to_jsonb(t) order by season)::text)
     from urc_candidate_20260915.league_payloads t) is distinct from 'c2339632624c869a75573fcf94aa42f2'
 or (select md5(jsonb_agg(to_jsonb(t) order by team_key)::text)
     from urc_candidate_20260915.team_comparisons t) is distinct from '8d1f7454b28f095758dece291c9ee4a7'
 or (select md5(jsonb_agg(to_jsonb(t))::text)
     from urc_candidate_20260915.league_comparison t) is distinct from '16aedf372cf0559ce9c5d1b5ffff16b6'
 or (select count(*) from urc_candidate_20260915.irfu_diagnosis_family_mapping) <> 402
 or (select count(*) from urc_candidate_20260915.urc_diagnosis_family_rows_v1
     where team_key in ('connacht','leinster','munster','ulster') and family_code='unknown') <> 0
 then raise exception 'Reviewed URC candidate or served predecessor changed'; end if;
end $$;

-- Retain the original view definitions as ungranted rollback predecessors.
do $$ declare item text; begin
 foreach item in array array[
  'latest_team_dashboard_v8', 'latest_league_dashboard_v8',
  'latest_team_season_comparison_v5', 'latest_league_season_comparison_v5',
  'latest_dashboard_cache_token_v2'
 ] loop
  execute format(
    'create view reporting.urc_pre_candidate_%I_20260915 with (security_invoker = false, security_barrier = true) as %s',
    item, pg_get_viewdef(('reporting.' || item)::regclass, true)
  );
  execute format('revoke all on reporting.urc_pre_candidate_%I_20260915 from public, anon, authenticated, web_reader', item);
 end loop;
end $$;

create table reporting.urc_candidate_team_release_20260915 as
select (jsonb_populate_record(
 null::reporting.urc_pre_candidate_latest_team_dashboard_v8_20260915,
 p.dashboard || jsonb_build_object('team_key',p.team_key)
)).*
from urc_candidate_20260915.team_payloads p where p.season='2025-26';
create unique index urc_candidate_team_release_key_20260915
 on reporting.urc_candidate_team_release_20260915(season,team_key);
create table reporting.urc_candidate_league_release_20260915 as
select (jsonb_populate_record(
 null::reporting.urc_pre_candidate_latest_league_dashboard_v8_20260915,
 p.dashboard
)).*
from urc_candidate_20260915.league_payloads p where p.season='2025-26';
create unique index urc_candidate_league_release_key_20260915
 on reporting.urc_candidate_league_release_20260915(season);
create table reporting.urc_candidate_team_comparisons_20260915 as
select * from urc_candidate_20260915.team_comparisons;
create unique index urc_candidate_team_comparison_key_20260915
 on reporting.urc_candidate_team_comparisons_20260915(team_key);
create table reporting.urc_candidate_league_comparison_20260915 as
select * from urc_candidate_20260915.league_comparison;
create table reporting.urc_candidate_release_context_20260915 as
select gen_random_uuid() release_id,
 'urc-2025-26-candidate-reporting-20260915-v1'::text release_label,
 '2025-26'::text season, 'Abdel Babiker'::text reviewer,
 'urc_intake_candidate_20260915_v2'::text rule_version,
 'e038d255e21a57df7fa7ae6009e57d9803b65621'::text candidate_code_commit,
 '1ba620e6f5bd7320ebc8a92502503b1aba469804f6219ff5fb753972ee53b445'::text candidate_dashboard_sha256,
 bundle.release_id predecessor_release_id,
 payload.payload_sha256 predecessor_payload_sha256,
 evidence->>'root_sha256' source_root_sha256,
 evidence->>'diagnosis_mapping_sha256' diagnosis_mapping_sha256,
 now() promoted_at
from urc_candidate_20260915.provenance
cross join reporting.latest_approved_league_bundle_v6 bundle
join reporting.league_release_payloads_v6 payload on payload.release_id=bundle.release_id
where bundle.season='2025-26';
alter table reporting.urc_candidate_release_context_20260915
 add primary key (release_id), add unique (release_label);
create function reporting.reject_urc_candidate_release_20260915_mutation()
returns trigger language plpgsql set search_path=pg_catalog as $$
begin raise exception 'URC candidate reporting release snapshot is immutable'; end;
$$;
revoke execute on function reporting.reject_urc_candidate_release_20260915_mutation()
 from public, anon, authenticated, web_reader;
do $$ declare item text; begin
 foreach item in array array[
  'urc_candidate_team_release_20260915', 'urc_candidate_league_release_20260915',
  'urc_candidate_team_comparisons_20260915', 'urc_candidate_league_comparison_20260915',
  'urc_candidate_release_context_20260915'
 ] loop
  execute format('alter table reporting.%I enable row level security',item);
  execute format('create trigger %I before insert or update or delete on reporting.%I for each row execute function reporting.reject_urc_candidate_release_20260915_mutation()',item || '_immutable',item);
 end loop;
end $$;
revoke all on reporting.urc_candidate_team_release_20260915,
 reporting.urc_candidate_league_release_20260915,
 reporting.urc_candidate_team_comparisons_20260915,
 reporting.urc_candidate_league_comparison_20260915,
 reporting.urc_candidate_release_context_20260915
from public, anon, authenticated, web_reader;

do $$ begin
 if (select count(*) from reporting.urc_candidate_team_release_20260915) <> 16
 or (select count(*) from reporting.urc_candidate_league_release_20260915) <> 1
 or (select count(*) from reporting.urc_candidate_team_comparisons_20260915) <> 16
 or (select count(*) from reporting.urc_candidate_league_comparison_20260915) <> 1
 or (select count(*) from reporting.urc_candidate_release_context_20260915) <> 1
 or exists (
   select 1 from reporting.urc_candidate_team_release_20260915 r
   join urc_candidate_20260915.team_payloads c using(season,team_key)
   where to_jsonb(r)-'team_key' <> c.dashboard
 )
 or exists (
   select 1 from reporting.urc_candidate_league_release_20260915 r
   join urc_candidate_20260915.league_payloads c using(season)
   where to_jsonb(r) <> c.dashboard
 )
 then raise exception 'Aggregate release snapshots differ from the reviewed candidate'; end if;
end $$;

create or replace view reporting.latest_team_dashboard_v8
with (security_invoker = false, security_barrier = true) as
select * from reporting.urc_pre_candidate_latest_team_dashboard_v8_20260915
where season='2024-25'
union all
select * from reporting.urc_candidate_team_release_20260915;
create or replace view reporting.latest_league_dashboard_v8
with (security_invoker = false, security_barrier = true) as
select * from reporting.urc_pre_candidate_latest_league_dashboard_v8_20260915
where season='2024-25'
union all
select * from reporting.urc_candidate_league_release_20260915;
create or replace view reporting.latest_team_season_comparison_v5
with (security_invoker = false, security_barrier = true) as
select team_key,comparison from reporting.urc_candidate_team_comparisons_20260915;
create or replace view reporting.latest_league_season_comparison_v5
with (security_invoker = false, security_barrier = true) as
select comparison from reporting.urc_candidate_league_comparison_20260915;
create or replace view reporting.latest_dashboard_cache_token_v2
with (security_invoker = false, security_barrier = true) as
select season,cache_token from reporting.urc_pre_candidate_latest_dashboard_cache_token_v2_20260915
where season<>'2025-26'
union all
select season,encode(extensions.digest(convert_to(
 release_id::text || ':' || candidate_dashboard_sha256 || ':' || rule_version,
 'UTF8'), 'sha256'),'hex') as cache_token
from reporting.urc_candidate_release_context_20260915;

do $$ begin
 if (select count(*) from reporting.latest_team_dashboard_v8) <> 32
 or (select count(*) from reporting.latest_league_dashboard_v8) <> 2
 or (select count(*) from reporting.latest_team_season_comparison_v5) <> 16
 or (select count(*) from reporting.latest_league_season_comparison_v5) <> 1
 or (select count(*) from reporting.latest_dashboard_cache_token_v2) <> 2
 or (select cache_token from reporting.latest_dashboard_cache_token_v2 where season='2025-26')
    is not distinct from (select cache_token from reporting.urc_pre_candidate_latest_dashboard_cache_token_v2_20260915 where season='2025-26')
 or (select target_attested from reporting.approved_dashboard_reader_target_v8) is distinct from true
 or (select count(*) from reporting.latest_team_dashboard_v8
     where season='2025-26' and (headline->0->>'value')::integer=1560) <> 0
 or (select count(*) from reporting.latest_league_dashboard_v8
     where season='2025-26' and (headline->0->>'value')::integer=1560) <> 1
 or exists (select 1 from reporting.latest_team_dashboard_v8 r
   join urc_candidate_20260915.team_payloads c using(season,team_key)
   where r.season='2025-26' and to_jsonb(r)-'team_key' <> c.dashboard)
 or exists (select 1 from reporting.latest_league_dashboard_v8 r
   join urc_candidate_20260915.league_payloads c using(season)
   where r.season='2025-26' and to_jsonb(r) <> c.dashboard)
 then raise exception 'Served aggregate candidate or restricted reader is incomplete'; end if;
end $$;
