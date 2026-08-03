-- Runtime hardening successor for the installed batch V3 migration.
-- The registered V3 objects remain immutable. New V4 entry functions repair
-- the duplicate-item alias ambiguity found by rollback-only verification.

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260803153728'
      and migration.name = 'dynamic_row_correction_batch_v3'
      and migration.statements = array[
        'migration_sha256=c4e4bdde1ca767b42f445279f07d0ab698c47536d5a7ef4a4e2bdd585880f953'
      ]
  ) then
    raise exception
      'row-correction batch hardening requires the exact registered V3 migration';
  end if;
end;
$$;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_preview_v3(jsonb)'::regprocedure
  );
  definition := replace(definition,
    'row_correction_preview_v3', 'row_correction_preview_v4');
  definition := replace(definition,
    E'from jsonb_array_elements(proposal -> ''items'') item\n'
      '    group by item ->> ''source_row_id'', item ->> ''field_name''',
    E'from jsonb_array_elements(proposal -> ''items'') duplicate_item\n'
      '    group by duplicate_item ->> ''source_row_id'', '
      'duplicate_item ->> ''field_name'''
  );
  execute definition;

  definition := pg_get_functiondef(
    'audit.apply_row_correction_batch_v3(jsonb,jsonb,text)'::regprocedure
  );
  definition := replace(definition,
    'apply_row_correction_batch_v3', 'apply_row_correction_batch_v4');
  definition := replace(definition,
    'analysis.row_correction_preview_v3',
    'analysis.row_correction_preview_v4');
  definition := replace(definition,
    '''20260803153728''', '''20260803161707''');
  definition := replace(definition,
    '''dynamic_row_correction_batch_v3''',
    '''dynamic_row_correction_batch_v3_hardening''');
  definition := replace(definition,
    '20260803153728_dynamic_row_correction_batch_v3.sql',
    '20260803161707_dynamic_row_correction_batch_v3_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_2026-08-03_v3',
    'row_correction_batch_2026-08-03_v4');
  definition := replace(definition,
    'row_correction_batch_candidate_2026-08-03_v3',
    'row_correction_batch_candidate_2026-08-03_v4');
  execute definition;

  definition := pg_get_functiondef(
    'reporting.promote_row_correction_batch_v3(text,text,text)'::regprocedure
  );
  definition := replace(definition,
    'promote_row_correction_batch_v3',
    'promote_row_correction_batch_v4');
  definition := replace(definition,
    '20260803153728_dynamic_row_correction_batch_v3.sql',
    '20260803161707_dynamic_row_correction_batch_v3_hardening.sql');
  definition := replace(definition,
    'row_correction_batch_release_2026-08-03_v3',
    'row_correction_batch_release_2026-08-03_v4');
  execute definition;
end;
$$;

revoke execute on function analysis.row_correction_preview_v4(jsonb)
  from public, anon, authenticated, web_reader;
revoke execute on function audit.apply_row_correction_batch_v4(jsonb, jsonb, text)
  from public, anon, authenticated, web_reader;
revoke execute on function
  reporting.promote_row_correction_batch_v4(text, text, text)
  from public, anon, authenticated, web_reader;

do $$
begin
  if pg_get_functiondef(
      'analysis.row_correction_preview_v4(jsonb)'::regprocedure
    ) like '%group by item ->>%'
    or pg_get_functiondef(
      'analysis.row_correction_preview_v4(jsonb)'::regprocedure
    ) not like '%group by duplicate_item ->>%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v4(jsonb,jsonb,text)'::regprocedure
    ) not like '%analysis.row_correction_preview_v4%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v4(jsonb,jsonb,text)'::regprocedure
    ) not like '%20260803161707%'
    or pg_get_functiondef(
      'audit.apply_row_correction_batch_v4(jsonb,jsonb,text)'::regprocedure
    ) not like '%dynamic_row_correction_batch_v3_hardening%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_batch_v4(text,text,text)'::regprocedure
    ) not like '%row_correction_batch_release_2026-08-03_v4%'
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v4(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V4 hardening was not wired exactly';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch hardening must be data-neutral';
  end if;
end;
$$;
