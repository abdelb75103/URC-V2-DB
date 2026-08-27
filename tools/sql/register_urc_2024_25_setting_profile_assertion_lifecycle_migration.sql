do $$
begin
  perform analysis.assert_urc_2024_25_setting_profile_successor_v1();
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260827171000',
  'urc_2024_25_setting_profile_assertion_lifecycle',
  array[
    'migration_sha256=b67679fffc1973d274c20c90abdfac8aba52b3e70d166142b6c154a5b0f9074d'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260827171000'
      and name = 'urc_2024_25_setting_profile_assertion_lifecycle'
      and statements = array[
        'migration_sha256=b67679fffc1973d274c20c90abdfac8aba52b3e70d166142b6c154a5b0f9074d'
      ]
  ) then
    raise exception '2024-25 setting-profile assertion lifecycle registration is invalid';
  end if;
end;
$$;
