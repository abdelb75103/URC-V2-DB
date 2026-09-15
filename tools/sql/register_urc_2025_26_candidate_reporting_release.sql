do $$ begin
 if (select count(*) from reporting.urc_candidate_release_context_20260915) <> 1
 or (select count(*) from reporting.latest_team_dashboard_v8) <> 32
 or (select count(*) from reporting.latest_league_dashboard_v8) <> 2
 or (select count(*) from reporting.latest_team_season_comparison_v5) <> 16
 or (select count(*) from reporting.latest_league_season_comparison_v5) <> 1
 or (select target_attested from reporting.approved_dashboard_reader_target_v8) is distinct from true
 or exists(select 1 from reporting.latest_team_dashboard_v8 r
   join urc_candidate_20260915.team_payloads c using(season,team_key)
   where r.season='2025-26' and to_jsonb(r)-'team_key' <> c.dashboard)
 or exists(select 1 from reporting.latest_league_dashboard_v8 r
   join urc_candidate_20260915.league_payloads c using(season)
   where r.season='2025-26' and to_jsonb(r) <> c.dashboard)
 then raise exception 'URC candidate reporting release is not ready for checksum registration'; end if;
end $$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260915120000','urc_2025_26_candidate_reporting_release',array[
 'migration_sha256=2390ea68dc6dce972de47c67cd43e9534f257175ee71fe4214b9bdf35782c606',
 'candidate_dashboard_sha256=1ba620e6f5bd7320ebc8a92502503b1aba469804f6219ff5fb753972ee53b445',
 'rule_version=urc_intake_candidate_20260915_v2',
 'scope=private_aggregate_reporting_successor_2025_26_no_v6_release_mutation'
]) on conflict(version) do nothing;

do $$ begin
 if not exists(select 1 from supabase_migrations.schema_migrations
  where version='20260915120000' and name='urc_2025_26_candidate_reporting_release'
   and statements=array[
    'migration_sha256=2390ea68dc6dce972de47c67cd43e9534f257175ee71fe4214b9bdf35782c606',
    'candidate_dashboard_sha256=1ba620e6f5bd7320ebc8a92502503b1aba469804f6219ff5fb753972ee53b445',
    'rule_version=urc_intake_candidate_20260915_v2',
    'scope=private_aggregate_reporting_successor_2025_26_no_v6_release_mutation'
   ]) then raise exception 'URC candidate reporting release checksum registration differs'; end if;
end $$;
