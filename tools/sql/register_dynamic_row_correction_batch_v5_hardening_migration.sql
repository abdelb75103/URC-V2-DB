do $$
begin
  if to_regprocedure(
      'audit.apply_row_correction_batch_v6(jsonb,jsonb,text)'
    ) is null
    or to_regprocedure(
      'reporting.promote_row_correction_batch_v6(text,text,text)'
    ) is null
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v6(jsonb,jsonb,text)'::regprocedure
    ) not like '%item_key := (item ->> ''source_row_id'')%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v6(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V6 hardening objects are invalid';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch V6 registration must be data-neutral';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260803162702',
  'dynamic_row_correction_batch_v5_hardening',
  array['migration_sha256=300bf8879b3577e2179a18f2294cd88a777b49ee68c9d6430a3f4eedf8d82e37']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations migration
    where migration.version = '20260803162702'
      and migration.name = 'dynamic_row_correction_batch_v5_hardening'
      and migration.statements = array[
        'migration_sha256=300bf8879b3577e2179a18f2294cd88a777b49ee68c9d6430a3f4eedf8d82e37'
      ]
  ) then
    raise exception 'row-correction batch V6 hardening tracking is invalid';
  end if;
end;
$$;
