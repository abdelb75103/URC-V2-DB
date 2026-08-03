do $$
begin
  if to_regprocedure('analysis.row_correction_preview_v4(jsonb)') is null
    or to_regprocedure(
      'audit.apply_row_correction_batch_v4(jsonb,jsonb,text)'
    ) is null
    or to_regprocedure(
      'reporting.promote_row_correction_batch_v4(text,text,text)'
    ) is null
    or pg_get_functiondef(
      'analysis.row_correction_preview_v4(jsonb)'::regprocedure
    ) not like '%group by duplicate_item ->>%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v4(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V4 hardening objects are invalid';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch hardening registration must be data-neutral';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260803161707',
  'dynamic_row_correction_batch_v3_hardening',
  array['migration_sha256=32a0cbe49cc93e06edc0dc5149d16a0728266bba94da9a6c141dd3caf816b5f6']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260803161707'
      and migration.name = 'dynamic_row_correction_batch_v3_hardening'
      and migration.statements = array[
        'migration_sha256=32a0cbe49cc93e06edc0dc5149d16a0728266bba94da9a6c141dd3caf816b5f6'
      ]
  ) then
    raise exception 'row-correction batch V4 hardening tracking is invalid';
  end if;
end;
$$;
