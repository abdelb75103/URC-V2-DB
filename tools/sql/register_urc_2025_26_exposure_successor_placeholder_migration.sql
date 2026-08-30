-- Register only the installed and reconciled Year 2 placeholder successor.

do $$
begin
  if to_regclass('analysis.exposure_placeholder_events_v1') is null
    or to_regclass('analysis.active_exposure_placeholders_v1') is null
    or (select count(*) from analysis.active_exposure_placeholders_v1
        where season = '2025-26') <> 2
    or (select count(*) from analysis.team_dashboard_release_candidates_analysis_window_v6
        where season = '2025-26') <> 16
  then
    raise exception 'Year 2 exposure placeholder successor is incomplete';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830150000',
  'urc_2025_26_exposure_successor_placeholders',
  array['migration_sha256=653a03518ebb6c57f638d4c03dbafe363ad8ee2dcebd8c10375afb8711e246f4']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260830150000'
      and name = 'urc_2025_26_exposure_successor_placeholders'
      and statements = array[
        'migration_sha256=653a03518ebb6c57f638d4c03dbafe363ad8ee2dcebd8c10375afb8711e246f4'
      ]
  ) then
    raise exception 'Year 2 exposure placeholder migration registration is invalid';
  end if;
end;
$$;
