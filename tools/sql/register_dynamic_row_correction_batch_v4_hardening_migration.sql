do $$
begin
  if to_regprocedure('analysis.row_correction_preview_v5(jsonb)') is null
    or to_regprocedure(
      'audit.apply_row_correction_batch_v5(jsonb,jsonb,text)'
    ) is null
    or to_regprocedure(
      'reporting.promote_row_correction_batch_v5(text,text,text)'
    ) is null
    or pg_get_functiondef(
      'analysis.row_correction_preview_v5(jsonb)'::regprocedure
    ) not like '%duplicate_item(value)%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v5(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V5 hardening objects are invalid';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch V5 registration must be data-neutral';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260803162112',
  'dynamic_row_correction_batch_v4_hardening',
  array['migration_sha256=35e0a3654eae797dfa372f513f3f052af0407e0ccf2d32d229e5703d84642d48']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations migration
    where migration.version = '20260803162112'
      and migration.name = 'dynamic_row_correction_batch_v4_hardening'
      and migration.statements = array[
        'migration_sha256=35e0a3654eae797dfa372f513f3f052af0407e0ccf2d32d229e5703d84642d48'
      ]
  ) then
    raise exception 'row-correction batch V5 hardening tracking is invalid';
  end if;
end;
$$;
