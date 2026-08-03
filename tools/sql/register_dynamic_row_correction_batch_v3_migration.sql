do $$
begin
  if to_regclass('audit.correction_batches_v3') is null
    or to_regclass('audit.correction_batch_items_v3') is null
    or to_regclass('processing.correction_batch_versions_v3') is null
    or to_regclass('reporting.latest_dashboard_cache_token_v1') is null
    or to_regprocedure('analysis.row_correction_preview_v3(jsonb)') is null
    or to_regprocedure(
      'audit.apply_row_correction_batch_v3(jsonb,jsonb,text)'
    ) is null
    or to_regprocedure(
      'reporting.promote_row_correction_batch_v3(text,text,text)'
    ) is null
    or to_regprocedure(
      'analysis.assert_legacy_row_correction_v2_available()'
    ) is null
    or not has_table_privilege(
      'web_reader', 'reporting.latest_dashboard_cache_token_v1', 'SELECT'
    )
    or has_table_privilege(
      'web_reader', 'audit.correction_batch_items_v3', 'SELECT'
    )
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v3(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V3 objects or privileges are invalid';
  end if;
  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch registration must remain data-neutral';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260803153728',
  'dynamic_row_correction_batch_v3',
  array['migration_sha256=c4e4bdde1ca767b42f445279f07d0ab698c47536d5a7ef4a4e2bdd585880f953']
)
on conflict (version) do nothing;

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
    raise exception 'row-correction batch V3 migration tracking is invalid';
  end if;
end;
$$;
