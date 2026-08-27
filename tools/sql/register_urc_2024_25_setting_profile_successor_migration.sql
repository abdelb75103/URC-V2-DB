-- Register only the installed, reconciled setting-profile successor.

do $$
begin
  if to_regclass('analysis.urc_2024_25_team_dashboard_candidate_v2') is null
     or to_regclass('analysis.urc_2024_25_league_dashboard_candidate_v2') is null
     or to_regprocedure(
       'analysis.assert_urc_2024_25_setting_profile_successor_v1()'
     ) is null
  then
    raise exception '2024-25 setting-profile successor objects are incomplete';
  end if;

  perform analysis.assert_urc_2024_25_setting_profile_successor_v1();
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260827170000',
  'urc_2024_25_setting_profile_successor',
  array[
    'migration_sha256=ea15f4e92f4e701c414781ba35428e425cafda3bf2159be1aa62f941682a2a03',
    'classification_view_version=reporting_classification_2024-25_2026-08-27_v1'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260827170000'
      and name = 'urc_2024_25_setting_profile_successor'
      and statements = array[
        'migration_sha256=ea15f4e92f4e701c414781ba35428e425cafda3bf2159be1aa62f941682a2a03',
        'classification_view_version=reporting_classification_2024-25_2026-08-27_v1'
      ]
  ) then
    raise exception '2024-25 setting-profile successor registration is invalid';
  end if;
end;
$$;
