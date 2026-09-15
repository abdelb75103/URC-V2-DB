-- Restore the retained reporting readers; leave release snapshots for audit.
do $$ declare item text; begin
 if (select count(*) from reporting.urc_candidate_release_context_20260915) <> 1
 then raise exception 'URC candidate release context is missing'; end if;
 if (select md5(jsonb_agg(to_jsonb(t) order by team_key)::text)
       from reporting.latest_team_dashboard_v8 t where season='2025-26')
      is distinct from (select md5(jsonb_agg(to_jsonb(t) order by team_key)::text)
        from reporting.urc_candidate_team_release_20260915 t)
 or (select md5(jsonb_agg(to_jsonb(t))::text)
       from reporting.latest_league_dashboard_v8 t where season='2025-26')
      is distinct from (select md5(jsonb_agg(to_jsonb(t))::text)
        from reporting.urc_candidate_league_release_20260915 t)
 or (select md5(jsonb_agg(to_jsonb(t) order by team_key)::text)
       from reporting.latest_team_season_comparison_v5 t)
      is distinct from (select md5(jsonb_agg(to_jsonb(t) order by team_key)::text)
        from reporting.urc_candidate_team_comparisons_20260915 t)
 or (select md5(jsonb_agg(to_jsonb(t))::text)
       from reporting.latest_league_season_comparison_v5 t)
      is distinct from (select md5(jsonb_agg(to_jsonb(t))::text)
        from reporting.urc_candidate_league_comparison_20260915 t)
 or (select cache_token from reporting.latest_dashboard_cache_token_v2 where season='2025-26')
      is distinct from (select encode(extensions.digest(convert_to(
        release_id::text || ':' || candidate_dashboard_sha256 || ':' || rule_version,
        'UTF8'),'sha256'),'hex') from reporting.urc_candidate_release_context_20260915)
 then raise exception 'A newer reporting release is served; September rollback is not current'; end if;
 foreach item in array array[
  'latest_team_dashboard_v8', 'latest_league_dashboard_v8',
  'latest_team_season_comparison_v5', 'latest_league_season_comparison_v5',
  'latest_dashboard_cache_token_v2'
 ] loop
  execute format(
    'create or replace view reporting.%I with (security_invoker = false, security_barrier = true) as %s',
    item, pg_get_viewdef(('reporting.urc_pre_candidate_' || item || '_20260915')::regclass, true)
  );
 end loop;
 if (select count(*) from reporting.latest_team_dashboard_v8) <> 32
 or (select count(*) from reporting.latest_league_dashboard_v8) <> 2
 or (select md5(jsonb_agg(to_jsonb(t) order by season,team_key)::text)
     from reporting.latest_team_dashboard_v8 t) is distinct from '3794137499366267b074a6028a919836'
 or (select md5(jsonb_agg(to_jsonb(t) order by season)::text)
     from reporting.latest_league_dashboard_v8 t) is distinct from '09f31a6276228b3fe42719e89c64ddb6'
 or (select target_attested from reporting.approved_dashboard_reader_target_v8) is distinct from true
 then raise exception 'Retained URC predecessor readers were not restored'; end if;
end $$;
