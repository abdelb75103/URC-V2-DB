do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260902010000'
      and statements[1] = 'migration_sha256=4a2598034b3715263231468444762eb453ed56a025f36e9e45d651284f8b3fb3'
  ) or not (select target_attested from reporting.approved_dashboard_reader_target_v8)
  then raise exception 'HSR attestation correction registration precondition failed';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260902020000', 'urc_hsr_reader_attestation_oid_fix',
  array['migration_sha256=bee1b599918457968d0a73408e7cf7d22f91563731d4faf53f63d65b522db148',
    'scope=bind_existing_attestation_privilege_targets_without_changing_grants']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260902020000'
      and name = 'urc_hsr_reader_attestation_oid_fix'
      and statements = array[
        'migration_sha256=bee1b599918457968d0a73408e7cf7d22f91563731d4faf53f63d65b522db148',
        'scope=bind_existing_attestation_privilege_targets_without_changing_grants'
      ]
  ) then raise exception 'HSR attestation correction checksum mismatch';
  end if;
end;
$$;
