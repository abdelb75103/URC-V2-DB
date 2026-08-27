do $$
begin
  if to_regclass('analysis.urc_2024_25_team_dashboard_candidate_v3') is null
     or to_regclass('analysis.urc_2024_25_league_dashboard_candidate_v3') is null
     or to_regprocedure(
       'analysis.assert_urc_2024_25_recorded_profile_successor_v1()'
     ) is null
  then
    raise exception '2024-25 recorded-profile successor objects are incomplete';
  end if;

  perform analysis.assert_urc_2024_25_recorded_profile_successor_v1();
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260827172000',
  'urc_2024_25_recorded_profile_successor',
  array[
    'migration_sha256=885a713f85f22bb8e68cbb1bed7f1540c6f81897e95ad3e71522aaf7aa9400b2'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260827172000'
      and name = 'urc_2024_25_recorded_profile_successor'
      and statements = array[
        'migration_sha256=885a713f85f22bb8e68cbb1bed7f1540c6f81897e95ad3e71522aaf7aa9400b2'
      ]
  ) then
    raise exception '2024-25 recorded-profile successor registration is invalid';
  end if;
end;
$$;
