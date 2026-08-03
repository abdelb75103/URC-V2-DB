-- Second runtime hardening successor for batch corrections.
-- V5 names both the duplicate-item table alias and its JSON value column.

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations migration
    where migration.version = '20260803161707'
      and migration.name = 'dynamic_row_correction_batch_v3_hardening'
      and migration.statements = array[
        'migration_sha256=32a0cbe49cc93e06edc0dc5149d16a0728266bba94da9a6c141dd3caf816b5f6'
      ]
  ) then
    raise exception
      'row-correction batch V5 requires the exact registered V4 hardening';
  end if;
end;
$$;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_preview_v4(jsonb)'::regprocedure
  );
  definition := replace(definition,
    'row_correction_preview_v4', 'row_correction_preview_v5');
  definition := replace(definition,
    E'from jsonb_array_elements(proposal -> ''items'') duplicate_item\n'
      '    group by duplicate_item ->> ''source_row_id'', '
      'duplicate_item ->> ''field_name''',
    E'from jsonb_array_elements(proposal -> ''items'') duplicate_item(value)\n'
      '    group by duplicate_item.value ->> ''source_row_id'', '
      'duplicate_item.value ->> ''field_name'''
  );
  execute definition;

  definition := pg_get_functiondef(
    'audit.apply_row_correction_batch_v4(jsonb,jsonb,text)'::regprocedure
  );
  definition := replace(definition,
    'apply_row_correction_batch_v4', 'apply_row_correction_batch_v5');
  definition := replace(definition,
    'analysis.row_correction_preview_v4',
    'analysis.row_correction_preview_v5');
  definition := replace(definition,
    '''20260803161707''', '''20260803162112''');
  definition := replace(definition,
    '''dynamic_row_correction_batch_v3_hardening''',
    '''dynamic_row_correction_batch_v4_hardening''');
  definition := replace(definition,
    '20260803161707_dynamic_row_correction_batch_v3_hardening.sql',
    '20260803162112_dynamic_row_correction_batch_v4_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_2026-08-03_v4',
    'row_correction_batch_2026-08-03_v5');
  definition := replace(definition,
    'row_correction_batch_candidate_2026-08-03_v4',
    'row_correction_batch_candidate_2026-08-03_v5');
  execute definition;

  definition := pg_get_functiondef(
    'reporting.promote_row_correction_batch_v4(text,text,text)'::regprocedure
  );
  definition := replace(definition,
    'promote_row_correction_batch_v4',
    'promote_row_correction_batch_v5');
  definition := replace(definition,
    '20260803161707_dynamic_row_correction_batch_v3_hardening.sql',
    '20260803162112_dynamic_row_correction_batch_v4_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_release_2026-08-03_v4',
    'row_correction_batch_release_2026-08-03_v5');
  execute definition;
end;
$$;

revoke execute on function analysis.row_correction_preview_v5(jsonb)
  from public, anon, authenticated, web_reader;
revoke execute on function audit.apply_row_correction_batch_v5(jsonb, jsonb, text)
  from public, anon, authenticated, web_reader;
revoke execute on function
  reporting.promote_row_correction_batch_v5(text, text, text)
  from public, anon, authenticated, web_reader;

do $$
begin
  if pg_get_functiondef(
      'analysis.row_correction_preview_v5(jsonb)'::regprocedure
    ) not like '%duplicate_item(value)%'
    or pg_get_functiondef(
      'analysis.row_correction_preview_v5(jsonb)'::regprocedure
    ) not like '%duplicate_item.value ->>%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v5(jsonb,jsonb,text)'::regprocedure
    ) not like '%analysis.row_correction_preview_v5%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v5(jsonb,jsonb,text)'::regprocedure
    ) not like '%20260803162112%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_batch_v5(text,text,text)'::regprocedure
    ) not like '%row_correction_batch_release_2026-08-03_v5%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v5(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V5 hardening was not wired exactly';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch V5 hardening must be data-neutral';
  end if;
end;
$$;
