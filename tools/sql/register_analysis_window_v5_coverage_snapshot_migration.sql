do $$
begin
  if to_regclass(
    'analysis.analysis_window_team_coverage_v5_snapshot'
  ) is null or to_regclass(
    'analysis.analysis_window_league_coverage_v5_snapshot'
  ) is null or to_regclass(
    'analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot'
  ) is null or to_regclass(
    'analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot'
  ) is null then
    raise exception 'V5 coverage snapshot objects are missing';
  end if;
  if position(
    'team_dashboard_payload_analysis_window_v5_coverage_snapshot'
    in pg_get_viewdef(
      'analysis.team_dashboard_release_candidates_analysis_window_v5'::regclass,
      true
    )
  ) = 0 or position(
    'league_dashboard_payload_analysis_window_v5_coverage_snapshot'
    in pg_get_viewdef(
      'analysis.league_dashboard_release_candidates_analysis_window_v5'::regclass,
      true
    )
  ) = 0 then
    raise exception 'V5 candidate views are not bound to corrected coverage';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260726120000',
  'analysis_window_v5_coverage_payload_snapshots',
  null
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260726120000'
      and name = 'analysis_window_v5_coverage_payload_snapshots'
  ) then
    raise exception 'V5 coverage snapshot migration tracking is invalid';
  end if;
end;
$$;
