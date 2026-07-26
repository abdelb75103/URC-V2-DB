do $$
declare
  current_release_id uuid;
  current_release_label text;
  current_league_hash text;
  current_team_count integer;
  correction_aware_release_id uuid;
  correction_aware_league_hash text;
  correction_aware_team_count integer;
  correction_aware_team_mismatches integer;
  v4_league_projection_hash text;
  v5_league_projection_hash text;
  v5_team_projection_mismatches integer;
  required_trigger_count integer;
  rls_table_count integer;
begin
  if to_regclass('audit.correction_sets_v1') is null
    or to_regclass('audit.row_corrections_v1') is null
    or to_regclass('processing.correction_versions_v1') is null
    or to_regclass('processing.correction_drafts_v1') is null
    or to_regclass('reporting.correction_release_context_v1') is null
    or to_regclass('reporting.correction_rollback_context_v1') is null
    or to_regclass('reporting.correction_league_payloads_v1') is null
    or to_regclass('reporting.correction_team_payloads_v1') is null
    or to_regclass('reporting.dashboard_bundle_context_v1') is null
    or to_regclass('reporting.dashboard_bundle_league_payloads_v1') is null
    or to_regclass('reporting.dashboard_bundle_team_payloads_v1') is null
    or to_regclass('reporting.latest_approved_dashboard_bundle_v4') is null
    or to_regclass('reporting.latest_team_dashboard_v5') is null
    or to_regclass('reporting.latest_league_dashboard_v5') is null
    or to_regclass('analysis.row_correction_pending_candidate_v1') is null
    or to_regprocedure(
      'analysis.row_correction_preview_v1(jsonb)'
    ) is null
    or to_regprocedure(
      'audit.apply_row_correction_v1(jsonb,text,text)'
    ) is null
    or to_regprocedure(
      'reporting.promote_row_correction_v1(text,text,text)'
    ) is null
    or to_regprocedure(
      'reporting.rollback_row_correction_bundle_v1(text,text,text,text,text,text,text,text)'
    ) is null then
    raise exception 'dynamic row-correction objects are missing';
  end if;

  if exists (select 1 from audit.correction_sets_v1)
    or exists (select 1 from audit.row_corrections_v1)
    or exists (select 1 from processing.correction_versions_v1)
    or exists (select 1 from processing.correction_drafts_v1)
    or exists (select 1 from reporting.correction_release_context_v1)
    or exists (select 1 from reporting.correction_rollback_context_v1)
    or exists (select 1 from reporting.correction_league_payloads_v1)
    or exists (select 1 from reporting.correction_team_payloads_v1)
    or exists (
      select 1 from analysis.row_correction_pending_candidate_v1
    ) then
    raise exception 'migration installation must remain correction-data neutral';
  end if;

  select bundle.release_id, release.release_label
    into current_release_id, current_release_label
  from reporting.latest_approved_dashboard_bundle_v2 bundle
  join reporting.aggregate_releases release
    on release.id = bundle.release_id
  where bundle.season = '2024-25';

  select payload.payload_sha256 into current_league_hash
  from reporting.league_release_payloads_v2 payload
  where payload.release_id = current_release_id;

  select count(*) into current_team_count
  from reporting.team_dashboard_payloads_v2 payload
  where payload.bundle_release_id = current_release_id;

  select bundle.release_id into correction_aware_release_id
  from reporting.latest_approved_dashboard_bundle_v4 bundle
  where bundle.season = '2024-25';

  select payload.payload_sha256 into correction_aware_league_hash
  from reporting.dashboard_bundle_league_payloads_v1 payload
  where payload.release_id = correction_aware_release_id;

  select count(*) into correction_aware_team_count
  from reporting.dashboard_bundle_team_payloads_v1 payload
  where payload.bundle_release_id = correction_aware_release_id;

  select count(*) into correction_aware_team_mismatches
  from reporting.team_dashboard_payloads_v2 frozen
  left join reporting.dashboard_bundle_team_payloads_v1 unified
    on unified.bundle_release_id = frozen.bundle_release_id
   and unified.team_key = frozen.team_key
   and unified.team_release_id = frozen.team_release_id
   and unified.curated_build_id = frozen.curated_build_id
  where frozen.bundle_release_id = current_release_id
    and (
      unified.team_key is null
      or unified.payload_sha256 is distinct from frozen.payload_sha256
      or unified.dashboard_payload is distinct from frozen.dashboard_payload
    );

  select encode(extensions.digest(
    convert_to(to_jsonb(reader)::text, 'UTF8'), 'sha256'
  ), 'hex') into v4_league_projection_hash
  from reporting.latest_league_dashboard_v4 reader
  where reader.season = '2024-25';
  select encode(extensions.digest(
    convert_to(to_jsonb(reader)::text, 'UTF8'), 'sha256'
  ), 'hex') into v5_league_projection_hash
  from reporting.latest_league_dashboard_v5 reader
  where reader.season = '2024-25';

  select count(*) into v5_team_projection_mismatches
  from reporting.latest_team_dashboard_v4 v4
  full join reporting.latest_team_dashboard_v5 v5
    using (team_key, season)
  where coalesce(v4.season, v5.season) = '2024-25'
    and to_jsonb(v4) is distinct from to_jsonb(v5);

  select count(*) into required_trigger_count
  from pg_catalog.pg_trigger trigger_row
  where not trigger_row.tgisinternal
    and trigger_row.tgname in (
      'correction_sets_v1_append_only',
      'row_corrections_v1_append_only',
      'correction_versions_v1_append_only',
      'correction_drafts_v1_append_only',
      'correction_release_context_v1_append_only',
      'correction_rollback_context_v1_append_only',
      'correction_league_payloads_v1_append_only',
      'correction_team_payloads_v1_append_only',
      'correction_release_context_v1_insert_guard',
      'correction_rollback_context_v1_insert_guard',
      'validate_dynamic_league_payload_v1',
      'validate_dynamic_team_payloads_v1',
      'validate_dynamic_bundle_context_v1',
      'guard_active_row_corrections_v1'
    );

  select count(*) into rls_table_count
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace
    on namespace.oid = relation.relnamespace
  where relation.relrowsecurity
    and (namespace.nspname, relation.relname) in (
      ('audit', 'correction_sets_v1'),
      ('audit', 'row_corrections_v1'),
      ('processing', 'correction_versions_v1'),
      ('processing', 'correction_drafts_v1'),
      ('reporting', 'correction_release_context_v1'),
      ('reporting', 'correction_rollback_context_v1'),
      ('reporting', 'correction_league_payloads_v1'),
      ('reporting', 'correction_team_payloads_v1')
    );

  if current_release_id is distinct from
      '76ac684a-dc60-4b12-ab78-0a502d284555'::uuid
    or correction_aware_release_id is distinct from current_release_id
    or current_release_label is distinct from
      'urc-2024-25-v5-4ae722941285-a1'
    or current_league_hash is distinct from
      '2f4bb3cbe77e1ea1608cf8442419c2d6e11333473ce73d10559532061382fa53'
    or correction_aware_league_hash is distinct from current_league_hash
    or current_team_count <> 16
    or correction_aware_team_count <> 16
    or correction_aware_team_mismatches <> 0
    or v5_league_projection_hash is distinct from v4_league_projection_hash
    or v5_team_projection_mismatches <> 0
    or required_trigger_count <> 14
    or rls_table_count <> 8
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_dashboard_v5', 'SELECT'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_dashboard_v5', 'SELECT'
    )
    or has_table_privilege(
      'web_reader', 'reporting.dashboard_bundle_context_v1', 'SELECT'
    )
    or has_table_privilege(
      'web_reader',
      'reporting.dashboard_bundle_league_payloads_v1',
      'SELECT'
    )
    or has_table_privilege(
      'web_reader',
      'reporting.dashboard_bundle_team_payloads_v1',
      'SELECT'
    )
    or has_table_privilege(
      'web_reader',
      'reporting.latest_approved_dashboard_bundle_v4',
      'SELECT'
    ) then
    raise exception 'approved 2024-25 V5 bundle changed during installation';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260726200000',
  'dynamic_row_correction_pipeline',
  array['migration_sha256=FINAL_SHA256_PENDING']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260726200000'
      and name = 'dynamic_row_correction_pipeline'
      and statements =
        array['migration_sha256=FINAL_SHA256_PENDING']
  ) then
    raise exception 'dynamic row-correction migration tracking is invalid';
  end if;
end;
$$;
