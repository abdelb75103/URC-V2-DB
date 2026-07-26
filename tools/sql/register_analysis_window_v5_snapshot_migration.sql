do $$
begin
  if to_regclass(
    'analysis.team_dashboard_payload_analysis_window_v5_snapshot'
  ) is null or to_regclass(
    'analysis.league_dashboard_payload_analysis_window_v5_snapshot'
  ) is null then
    raise exception 'V5 candidate snapshot objects are missing';
  end if;
  if (
    select count(*)
    from analysis.team_dashboard_payload_analysis_window_v5_snapshot
    where season = '2024-25'
  ) <> 16 or (
    select count(*)
    from analysis.league_dashboard_payload_analysis_window_v5_snapshot
    where season = '2024-25'
  ) <> 1 then
    raise exception 'V5 candidate snapshot row counts are incomplete';
  end if;
  if position(
    'team_dashboard_payload_analysis_window_v5_snapshot'
    in pg_get_viewdef(
      'analysis.team_dashboard_release_candidates_analysis_window_v5'::regclass,
      true
    )
  ) = 0 or position(
    'league_dashboard_payload_analysis_window_v5_snapshot'
    in pg_get_viewdef(
      'analysis.league_dashboard_release_candidates_analysis_window_v5'::regclass,
      true
    )
  ) = 0 then
    raise exception 'V5 candidate views are not bound to the snapshots';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260726020000',
  'analysis_window_v5_release_candidate_snapshots',
  null
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260726020000'
      and name = 'analysis_window_v5_release_candidate_snapshots'
  ) then
    raise exception 'V5 candidate snapshot migration tracking is invalid';
  end if;
end;
$$;
