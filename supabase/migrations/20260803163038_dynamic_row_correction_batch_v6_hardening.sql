-- Qualify the batch identifier in the processing-version insert.

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
    raise exception
      'row-correction batch V7 requires the exact registered V6 hardening';
  end if;
end;
$$;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'audit.apply_row_correction_batch_v6(jsonb,jsonb,text)'::regprocedure
  );
  definition := replace(definition,
    'apply_row_correction_batch_v6', 'apply_row_correction_batch_v7');
  definition := replace(definition,
    'where item.batch_id = batch_id',
    'where item.batch_id = apply_row_correction_batch_v7.batch_id');
  definition := replace(definition,
    '''20260803162702''', '''20260803163038''');
  definition := replace(definition,
    '''dynamic_row_correction_batch_v5_hardening''',
    '''dynamic_row_correction_batch_v6_hardening''');
  definition := replace(definition,
    '20260803162702_dynamic_row_correction_batch_v5_hardening.sql',
    '20260803163038_dynamic_row_correction_batch_v6_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_2026-08-03_v6',
    'row_correction_batch_2026-08-03_v7');
  definition := replace(definition,
    'row_correction_batch_candidate_2026-08-03_v6',
    'row_correction_batch_candidate_2026-08-03_v7');
  execute definition;

  definition := pg_get_functiondef(
    'reporting.promote_row_correction_batch_v6(text,text,text)'::regprocedure
  );
  definition := replace(definition,
    'promote_row_correction_batch_v6',
    'promote_row_correction_batch_v7');
  definition := replace(definition,
    '20260803162702_dynamic_row_correction_batch_v5_hardening.sql',
    '20260803163038_dynamic_row_correction_batch_v6_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_release_2026-08-03_v6',
    'row_correction_batch_release_2026-08-03_v7');
  execute definition;
end;
$$;

revoke execute on function audit.apply_row_correction_batch_v7(jsonb, jsonb, text)
  from public, anon, authenticated, web_reader;
revoke execute on function
  reporting.promote_row_correction_batch_v7(text, text, text)
  from public, anon, authenticated, web_reader;

do $$
begin
  if pg_get_functiondef(
      'audit.apply_row_correction_batch_v7(jsonb,jsonb,text)'::regprocedure
    ) not like
      '%where item.batch_id = apply_row_correction_batch_v7.batch_id%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v7(jsonb,jsonb,text)'::regprocedure
    ) not like '%20260803163038%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_batch_v7(text,text,text)'::regprocedure
    ) not like '%row_correction_batch_release_2026-08-03_v7%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v7(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V7 hardening was not wired exactly';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch V7 hardening must be data-neutral';
  end if;
end;
$$;
