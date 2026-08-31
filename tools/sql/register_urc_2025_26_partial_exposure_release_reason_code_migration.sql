do $$
begin
  if not exists (
    select 1
    from audit.reason_codes
    where code = 'league_dashboard_release_v6_partial_exposure_reporting'
      and description =
        'Immutable 16-team 2025-26 league dashboard release with partial source-backed exposure reporting and explicit temporary team estimates.'
  ) then
    raise exception 'Partial exposure league release reason code registration is incomplete';
  end if;
end;
$$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831132000',
  'urc_2025_26_partial_exposure_release_reason_code',
  array[
    'migration_sha256=1786bfb98620220bd1857fca6d12d1283c44228fb4cb73e33e79bd029df0bde8',
    'reason_code=league_dashboard_release_v6_partial_exposure_reporting',
    'scope=audit_vocabulary_only'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831132000'
      and name = 'urc_2025_26_partial_exposure_release_reason_code'
      and statements = array[
        'migration_sha256=1786bfb98620220bd1857fca6d12d1283c44228fb4cb73e33e79bd029df0bde8',
        'reason_code=league_dashboard_release_v6_partial_exposure_reporting',
        'scope=audit_vocabulary_only'
      ]
  ) then
    raise exception 'Partial exposure league release reason code registration is invalid';
  end if;
end;
$$;
