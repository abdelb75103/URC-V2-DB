-- Rename the local batch identifier so it cannot collide with table columns.

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
    raise exception
      'row-correction batch V8 requires the exact registered V7 hardening';
  end if;
end;
$$;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'audit.apply_row_correction_batch_v7(jsonb,jsonb,text)'::regprocedure
  );
  definition := replace(definition,
    'apply_row_correction_batch_v7', 'apply_row_correction_batch_v8');
  definition := replace(definition,
    'batch_id uuid := gen_random_uuid();',
    'target_batch_id uuid := gen_random_uuid();');
  definition := replace(definition,
    E'\n    batch_id, set_id, proposal ->> ''season'', proposal ->> ''team_key'',',
    E'\n    target_batch_id, set_id, proposal ->> ''season'', proposal ->> ''team_key'','
  );
  definition := replace(definition,
    E'\n      batch_item_id, batch_id, item_index, proposal ->> ''season'',',
    E'\n      batch_item_id, target_batch_id, item_index, proposal ->> ''season'','
  );
  definition := replace(definition,
    'where item.batch_id = apply_row_correction_batch_v8.batch_id',
    'where item.batch_id = target_batch_id');
  definition := replace(definition,
    '''batch_id'', batch_id', '''batch_id'', target_batch_id');
  definition := replace(definition,
    '''20260803163038''', '''20260803163430''');
  definition := replace(definition,
    '''dynamic_row_correction_batch_v6_hardening''',
    '''dynamic_row_correction_batch_v7_hardening''');
  definition := replace(definition,
    '20260803163038_dynamic_row_correction_batch_v6_hardening.sql',
    '20260803163430_dynamic_row_correction_batch_v7_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_2026-08-03_v7',
    'row_correction_batch_2026-08-03_v8');
  definition := replace(definition,
    'row_correction_batch_candidate_2026-08-03_v7',
    'row_correction_batch_candidate_2026-08-03_v8');
  execute definition;

  definition := pg_get_functiondef(
    'reporting.promote_row_correction_batch_v7(text,text,text)'::regprocedure
  );
  definition := replace(definition,
    'promote_row_correction_batch_v7',
    'promote_row_correction_batch_v8');
  definition := replace(definition,
    '20260803163038_dynamic_row_correction_batch_v6_hardening.sql',
    '20260803163430_dynamic_row_correction_batch_v7_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_release_2026-08-03_v7',
    'row_correction_batch_release_2026-08-03_v8');
  execute definition;
end;
$$;

revoke execute on function audit.apply_row_correction_batch_v8(jsonb, jsonb, text)
  from public, anon, authenticated, web_reader;
revoke execute on function
  reporting.promote_row_correction_batch_v8(text, text, text)
  from public, anon, authenticated, web_reader;

do $$
begin
  if pg_get_functiondef(
      'audit.apply_row_correction_batch_v8(jsonb,jsonb,text)'::regprocedure
    ) not like '%target_batch_id uuid := gen_random_uuid()%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v8(jsonb,jsonb,text)'::regprocedure
    ) like '%apply_row_correction_batch_v8.batch_id%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v8(jsonb,jsonb,text)'::regprocedure
    ) not like '%where item.batch_id = target_batch_id%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v8(jsonb,jsonb,text)'::regprocedure
    ) not like '%20260803163430%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_batch_v8(text,text,text)'::regprocedure
    ) not like '%row_correction_batch_release_2026-08-03_v8%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v8(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V8 hardening was not wired exactly';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch V8 hardening must be data-neutral';
  end if;
end;
$$;
