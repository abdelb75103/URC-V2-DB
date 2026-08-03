-- Evidence-key precedence hardening for the batch apply entry function.

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
    raise exception
      'row-correction batch V6 requires the exact registered V5 hardening';
  end if;
end;
$$;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'audit.apply_row_correction_batch_v5(jsonb,jsonb,text)'::regprocedure
  );
  definition := replace(definition,
    'apply_row_correction_batch_v5', 'apply_row_correction_batch_v6');
  definition := replace(definition,
    E'item_key := item ->> ''source_row_id'' || '':'' || item ->> ''field_name'';',
    E'item_key := (item ->> ''source_row_id'') || '':'' || '
      '(item ->> ''field_name'');'
  );
  definition := replace(definition,
    '''20260803162112''', '''20260803162702''');
  definition := replace(definition,
    '''dynamic_row_correction_batch_v4_hardening''',
    '''dynamic_row_correction_batch_v5_hardening''');
  definition := replace(definition,
    '20260803162112_dynamic_row_correction_batch_v4_hardening.sql',
    '20260803162702_dynamic_row_correction_batch_v5_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_2026-08-03_v5',
    'row_correction_batch_2026-08-03_v6');
  definition := replace(definition,
    'row_correction_batch_candidate_2026-08-03_v5',
    'row_correction_batch_candidate_2026-08-03_v6');
  execute definition;

  definition := pg_get_functiondef(
    'reporting.promote_row_correction_batch_v5(text,text,text)'::regprocedure
  );
  definition := replace(definition,
    'promote_row_correction_batch_v5',
    'promote_row_correction_batch_v6');
  definition := replace(definition,
    '20260803162112_dynamic_row_correction_batch_v4_hardening.sql',
    '20260803162702_dynamic_row_correction_batch_v5_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_release_2026-08-03_v5',
    'row_correction_batch_release_2026-08-03_v6');
  execute definition;
end;
$$;

revoke execute on function audit.apply_row_correction_batch_v6(jsonb, jsonb, text)
  from public, anon, authenticated, web_reader;
revoke execute on function
  reporting.promote_row_correction_batch_v6(text, text, text)
  from public, anon, authenticated, web_reader;

do $$
begin
  if pg_get_functiondef(
      'audit.apply_row_correction_batch_v6(jsonb,jsonb,text)'::regprocedure
    ) not like '%item_key := (item ->> ''source_row_id'')%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v6(jsonb,jsonb,text)'::regprocedure
    ) not like '%20260803162702%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_batch_v6(text,text,text)'::regprocedure
    ) not like '%row_correction_batch_release_2026-08-03_v6%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v6(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V6 hardening was not wired exactly';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch V6 hardening must be data-neutral';
  end if;
end;
$$;
