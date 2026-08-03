do $$
begin
  if to_regprocedure(
      'audit.apply_row_correction_batch_v7(jsonb,jsonb,text)'
    ) is null
    or to_regprocedure(
      'reporting.promote_row_correction_batch_v7(text,text,text)'
    ) is null
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v7(jsonb,jsonb,text)'::regprocedure
    ) not like
      '%where item.batch_id = apply_row_correction_batch_v7.batch_id%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v7(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V7 hardening objects are invalid';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch V7 registration must be data-neutral';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260803163038',
  'dynamic_row_correction_batch_v6_hardening',
  array['migration_sha256=5fdfa3f824765f8fd7ff7203212c9e4a6103f705cdec25845569cdae5dcba0a9']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations migration
    where migration.version = '20260803163038'
      and migration.name = 'dynamic_row_correction_batch_v6_hardening'
      and migration.statements = array[
        'migration_sha256=5fdfa3f824765f8fd7ff7203212c9e4a6103f705cdec25845569cdae5dcba0a9'
      ]
  ) then
    raise exception 'row-correction batch V7 hardening tracking is invalid';
  end if;
end;
$$;
