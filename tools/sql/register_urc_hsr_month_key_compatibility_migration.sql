do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260902010000'
      and statements[1] = 'migration_sha256=4a2598034b3715263231468444762eb453ed56a025f36e9e45d651284f8b3fb3'
  ) or not (select target_attested from reporting.approved_dashboard_reader_target_v8)
  then raise exception 'HSR month-key correction registration precondition failed';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260902030000', 'urc_hsr_month_key_compatibility',
  array['migration_sha256=5695cb6433a89700617b74bac22341aa8cc167ad849c769f4710498e5a0a612a',
    'scope=match_both_released_month_label_formats_without_changing_preserved_fields']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260902030000'
      and name = 'urc_hsr_month_key_compatibility'
      and statements = array[
        'migration_sha256=5695cb6433a89700617b74bac22341aa8cc167ad849c769f4710498e5a0a612a',
        'scope=match_both_released_month_label_formats_without_changing_preserved_fields'
      ]
  ) then raise exception 'HSR month-key correction checksum mismatch';
  end if;
end;
$$;
