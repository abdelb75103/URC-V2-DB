do $$
declare
  current_release_id uuid;
  current_release_label text;
  current_league_hash text;
  current_team_count integer;
begin
  if to_regclass(
      'analysis.row_correction_reporting_classification_v2'
    ) is null
    or to_regclass('analysis.row_correction_target_teams_v2') is null
    or to_regclass(
      'analysis.row_correction_pending_candidate_v2'
    ) is null
    or to_regclass('audit.correction_recovery_labels_v1') is null
    or to_regprocedure(
      'analysis.row_correction_preview_v2(jsonb)'
    ) is null
    or to_regprocedure(
      'analysis.row_correction_pending_candidate_data_v2(text)'
    ) is null
    or to_regprocedure(
      'audit.apply_row_correction_v2(jsonb,text,text)'
    ) is null
    or to_regprocedure(
      'reporting.promote_row_correction_v2(text,text,text)'
    ) is null
    or to_regprocedure(
      'reporting.rollback_row_correction_bundle_recovery_v2(text,text,text,text,text,text,text,text)'
    ) is null
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_v2(jsonb,text,text)',
      'EXECUTE'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.promote_row_correction_v2(text,text,text)',
      'EXECUTE'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.rollback_row_correction_bundle_recovery_v2(text,text,text,text,text,text,text,text)',
      'EXECUTE'
    )
    or has_table_privilege(
      'web_reader', 'audit.correction_recovery_labels_v1', 'SELECT'
    ) then
    raise exception 'dynamic row-correction hardening objects are missing';
  end if;

  if exists (select 1 from audit.correction_recovery_labels_v1) then
    raise exception
      'hardening migration registration must remain correction-data neutral';
  end if;

  select bundle.release_id, release.release_label
    into current_release_id, current_release_label
  from reporting.latest_approved_dashboard_bundle_v4 bundle
  join reporting.aggregate_releases release
    on release.id = bundle.release_id
  where bundle.season = '2024-25';

  select payload.payload_sha256 into current_league_hash
  from reporting.dashboard_bundle_league_payloads_v1 payload
  where payload.release_id = current_release_id;

  select count(*) into current_team_count
  from reporting.dashboard_bundle_team_payloads_v1 payload
  where payload.bundle_release_id = current_release_id;

  if current_release_id is distinct from
      '76ac684a-dc60-4b12-ab78-0a502d284555'::uuid
    or current_release_label is distinct from
      'urc-2024-25-v5-4ae722941285-a1'
    or current_league_hash is distinct from
      '2f4bb3cbe77e1ea1608cf8442419c2d6e11333473ce73d10559532061382fa53'
    or current_team_count <> 16 then
    raise exception
      'approved 2024-25 V5 bundle changed before hardening registration';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260727010000',
  'dynamic_row_correction_pipeline_hardening',
  array['migration_sha256=29dd76bb42ac7bdc10f3a6691bf538a1af4786a15408acc467a4c9beab4cd57b']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260727010000'
      and migration.name = 'dynamic_row_correction_pipeline_hardening'
      and migration.statements =
        array['migration_sha256=29dd76bb42ac7bdc10f3a6691bf538a1af4786a15408acc467a4c9beab4cd57b']
  ) then
    raise exception
      'dynamic row-correction hardening migration tracking is invalid';
  end if;
end;
$$;
