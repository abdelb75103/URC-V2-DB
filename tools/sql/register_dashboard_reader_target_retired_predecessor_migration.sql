do $$
begin
  if to_regclass('reporting.approved_dashboard_reader_target_v1') is null
    or not (select target_attested from reporting.approved_dashboard_reader_target_v1)
    or not has_table_privilege(
      'web_reader',
      'reporting.approved_dashboard_reader_target_v1',
      'select'
    )
  then
    raise exception 'dashboard reader target attestation successor is absent or invalid';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260826010000',
  'dashboard_reader_target_retired_predecessor',
  array['migration_sha256=5a05871d8bf959040ab41d4138549db993a970f1366a46dd9ced03dfa1a3cbdd']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260826010000'
      and migration.name = 'dashboard_reader_target_retired_predecessor'
      and migration.statements = array[
        'migration_sha256=5a05871d8bf959040ab41d4138549db993a970f1366a46dd9ced03dfa1a3cbdd'
      ]
  )
  then
    raise exception 'dashboard reader target attestation migration registration is absent or checksum-mismatched';
  end if;
end;
$$;
