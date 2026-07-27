-- Additive hardening for the dynamic row-correction pipeline.
--
-- The installed 20260726200000 migration remains immutable. This successor:
--   * isolates candidate generation by season and affected team;
--   * preserves row-correction origin metadata after activation;
--   * binds apply provenance to the registered installed migration SHA; and
--   * makes automatic closeout recovery collision-safe without weakening the
--     exact-label semantics of explicit rollback.

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260726200000'
      and migration.name = 'dynamic_row_correction_pipeline'
      and migration.statements = array[
        'migration_sha256=07bbd951aedf19705ba8ea99cff30d445c6634ddfad90f84e3b9f2f38218aac5'
      ]
  ) then
    raise exception
      'dynamic row-correction hardening requires the exact registered base migration';
  end if;
end;
$$;

create view analysis.row_correction_reporting_classification_v2
with (security_invoker = true) as
select
  classification.injury_id,
  classification.curated_build_id,
  classification.team_key,
  classification.season,
  classification.setting_code,
  classification.is_time_loss,
  classification.days_lost,
  classification.diagnosis_code,
  classification.diagnosis_label,
  classification.original_body_location_code,
  classification.original_injury_type_code,
  classification.effective_body_location_code,
  classification.effective_injury_type_code,
  case
    when exists (
      select 1
      from analysis.row_correction_effective_values_v1 effective
      where effective.season = classification.season
        and effective.source_row_id = injury.source_row_id
        and effective.field_name = 'body_location_code'
    ) then 'row_correction'
    else classification.body_location_origin
  end as body_location_origin,
  case
    when exists (
      select 1
      from analysis.row_correction_effective_values_v1 effective
      where effective.season = classification.season
        and effective.source_row_id = injury.source_row_id
        and effective.field_name = 'injury_type_code'
    ) then 'row_correction'
    else classification.injury_type_origin
  end as injury_type_origin,
  case
    when exists (
      select 1
      from analysis.row_correction_effective_values_v1 effective
      where effective.season = classification.season
        and effective.source_row_id = injury.source_row_id
        and effective.field_name = 'diagnosis_code'
    ) then 'row_correction'
    else classification.diagnosis_origin
  end as diagnosis_origin,
  classification.injury_type_candidate_count,
  classification.candidate_injury_types
from analysis.row_correction_reporting_classification_v1 classification
join curated.injuries injury
  on injury.id = classification.injury_id
 and injury.curated_build_id = classification.curated_build_id
 and injury.team_key = classification.team_key
 and injury.season = classification.season;

create view analysis.row_correction_target_teams_v2
with (security_invoker = true) as
select
  context.season,
  context.affected_team_key as team_key
from analysis.row_correction_pending_context_v1 context
where context.season = nullif(
  current_setting('urc.row_correction_target_season', true), ''
);

-- Clone only the dynamic candidate segment. The source definitions are frozen
-- by the exact registered base-migration guard above. The replacements change
-- object wiring, not any accepted analytical formula.
do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_team_dashboard_payload_data_v1()'::regprocedure
  );
  definition := replace(
    definition,
    'row_correction_team_dashboard_payload_data_v1',
    'row_correction_team_dashboard_payload_data_v2_internal'
  );
  definition := replace(
    definition,
    'analysis.row_correction_target_teams_v1',
    'analysis.row_correction_target_teams_v2'
  );
  definition := replace(
    definition,
    'analysis.row_correction_reporting_classification_v1',
    'analysis.row_correction_reporting_classification_v2'
  );
  execute definition;
end;
$$;

do $$
declare
  definition text;
begin
  definition := pg_get_viewdef(
    'analysis.row_correction_incremental_context_v1'::regclass, true
  );
  definition := replace(
    definition,
    'analysis.row_correction_target_teams_v1',
    'analysis.row_correction_target_teams_v2'
  );
  execute
    'create view analysis.row_correction_incremental_context_v2 '
    'with (security_invoker = true) as ' || definition;

  definition := pg_get_viewdef(
    'analysis.row_correction_team_payload_candidates_incremental_v1'::regclass,
    true
  );
  definition := replace(
    definition,
    'analysis.row_correction_incremental_context_v1',
    'analysis.row_correction_incremental_context_v2'
  );
  definition := replace(
    definition,
    'analysis.row_correction_team_dashboard_payload_data_v1()',
    'analysis.row_correction_team_dashboard_payload_data_v2_internal()'
  );
  execute
    'create view analysis.row_correction_team_payload_candidates_incremental_v2 '
    'with (security_invoker = true) as ' || definition;

  definition := pg_get_viewdef(
    'analysis.row_correction_league_dashboard_payload_incremental_v1'::regclass,
    true
  );
  definition := replace(
    definition,
    'analysis.row_correction_team_payload_candidates_incremental_v1',
    'analysis.row_correction_team_payload_candidates_incremental_v2'
  );
  definition := replace(
    definition,
    'analysis.row_correction_incremental_context_v1',
    'analysis.row_correction_incremental_context_v2'
  );
  execute
    'create view analysis.row_correction_league_dashboard_payload_incremental_v2 '
    'with (security_invoker = true) as ' || definition;
end;
$$;

create view analysis.team_dashboard_release_candidates_correction_v2
with (security_invoker = true) as
select
  candidate.team_key,
  candidate.season,
  candidate.team_release_id,
  candidate.curated_build_id,
  'correction_v2'::text as analysis_version,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256,
  candidate.dashboard
from analysis.row_correction_pending_context_v1 context
join analysis.row_correction_team_payload_candidates_incremental_v2 candidate
  using (season)
where context.season = nullif(
  current_setting('urc.row_correction_target_season', true), ''
);

create view analysis.league_dashboard_release_candidates_correction_v2
with (security_invoker = true) as
select
  context.season,
  'correction_v2'::text as analysis_version,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256,
  corrected.dashboard
from analysis.row_correction_pending_context_v1 context
join analysis.row_correction_league_dashboard_payload_incremental_v2 corrected
  on corrected.season = context.season
where context.season = nullif(
  current_setting('urc.row_correction_target_season', true), ''
);

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_pending_candidate_data_v1()'::regprocedure
  );
  definition := replace(
    definition,
    'row_correction_pending_candidate_data_v1()',
    'row_correction_pending_candidate_data_v2(target_season text)'
  );
  definition := replace(
    definition,
    E'begin\n  select context.* into context_row',
    E'begin\n'
      '  if nullif(target_season, '''') is null then\n'
      '    raise exception ''target correction season is required'';\n'
      '  end if;\n'
      '  perform set_config(\n'
      '    ''urc.row_correction_target_season'', target_season, true\n'
      '  );\n'
      '  select context.* into context_row'
  );
  definition := replace(
    definition,
    E'from analysis.row_correction_pending_context_v1 context;\n'
      '  if not found then',
    E'from analysis.row_correction_pending_context_v1 context\n'
      '  where context.season = target_season;\n'
      '  if not found then'
  );
  definition := replace(
    definition,
    'analysis.league_dashboard_release_candidates_correction_v1',
    'analysis.league_dashboard_release_candidates_correction_v2'
  );
  definition := replace(
    definition,
    'analysis.team_dashboard_release_candidates_correction_v1',
    'analysis.team_dashboard_release_candidates_correction_v2'
  );
  execute definition;
end;
$$;

revoke execute on function
  analysis.row_correction_team_dashboard_payload_data_v2_internal()
  from public, anon, authenticated, web_reader;
revoke execute on function
  analysis.row_correction_pending_candidate_data_v2(text)
  from public, anon, authenticated, web_reader;

create view analysis.row_correction_pending_candidate_v2
with (security_invoker = true) as
select candidate.*
from analysis.row_correction_pending_candidate_data_v2(
  coalesce(
    analysis.row_correction_current_preview_v1() ->> 'season',
    nullif(current_setting('urc.row_correction_target_season', true), '')
  )
) candidate
where coalesce(
  analysis.row_correction_current_preview_v1() ->> 'season',
  nullif(current_setting('urc.row_correction_target_season', true), '')
) is not null;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_preview_v1(jsonb)'::regprocedure
  );
  definition := replace(
    definition,
    'row_correction_preview_v1',
    'row_correction_preview_v2'
  );
  definition := replace(
    definition,
    'analysis.row_correction_pending_candidate_v1',
    'analysis.row_correction_pending_candidate_v2'
  );
  execute definition;

  definition := pg_get_functiondef(
    'audit.apply_row_correction_v1(jsonb,text,text)'::regprocedure
  );
  definition := replace(
    definition,
    'apply_row_correction_v1',
    'apply_row_correction_v2_internal'
  );
  definition := replace(
    definition,
    'analysis.row_correction_preview_v1',
    'analysis.row_correction_preview_v2'
  );
  definition := replace(
    definition,
    '20260726200000_dynamic_row_correction_pipeline.sql',
    '20260727010000_dynamic_row_correction_pipeline_hardening.sql'
  );
  definition := replace(
    definition,
    'row_correction_candidate_2026-07-26_v1',
    'row_correction_candidate_2026-07-27_v2'
  );
  execute definition;

  definition := pg_get_functiondef(
    'reporting.promote_row_correction_v1(text,text,text)'::regprocedure
  );
  definition := replace(
    definition,
    'promote_row_correction_v1',
    'promote_row_correction_v2'
  );
  definition := replace(
    definition,
    'analysis.row_correction_pending_candidate_v1 candidate',
    'analysis.row_correction_pending_candidate_data_v2('
      'correction_set.season) candidate'
  );
  definition := replace(
    definition,
    '20260726200000_dynamic_row_correction_pipeline.sql',
    '20260727010000_dynamic_row_correction_pipeline_hardening.sql'
  );
  definition := replace(
    definition,
    'row_correction_release_2026-07-26_v1',
    'row_correction_release_2026-07-27_v2'
  );
  execute definition;
end;
$$;

revoke execute on function analysis.row_correction_preview_v2(jsonb)
  from public, anon, authenticated, web_reader;
revoke execute on function audit.apply_row_correction_v2_internal(
  jsonb, text, text
) from public, anon, authenticated, web_reader;
revoke execute on function reporting.promote_row_correction_v2(
  text, text, text
) from public, anon, authenticated, web_reader;

create function audit.apply_row_correction_v2(
  proposal jsonb,
  approval_evidence text,
  approval_reviewer text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting,
  supabase_migrations
as $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260727010000'
      and migration.name = 'dynamic_row_correction_pipeline_hardening'
      and migration.statements = array[
        'migration_sha256=' || coalesce(proposal ->> 'migration_sha256', '')
      ]
  ) then
    raise exception
      'proposal migration SHA does not match the installed correction implementation';
  end if;

  return audit.apply_row_correction_v2_internal(
    proposal, approval_evidence, approval_reviewer
  );
end;
$$;

revoke execute on function audit.apply_row_correction_v2(
  jsonb, text, text
) from public, anon, authenticated, web_reader;

create table audit.correction_recovery_labels_v1 (
  id uuid primary key default gen_random_uuid(),
  target_release_label text not null,
  requested_rollback_release_label text not null,
  effective_rollback_release_label text not null,
  rollback_release_id uuid not null
    references reporting.aggregate_releases(id),
  fallback_used boolean not null,
  recorded_at timestamptz not null default now(),
  unique (rollback_release_id)
);

alter table audit.correction_recovery_labels_v1 enable row level security;
revoke all on audit.correction_recovery_labels_v1
  from public, anon, authenticated, web_reader;

create trigger correction_recovery_labels_v1_append_only
before update or delete on audit.correction_recovery_labels_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();

create function reporting.rollback_row_correction_bundle_recovery_v2(
  target_release_label text,
  requested_rollback_release_label text,
  rollback_reviewer text,
  rollback_reason text,
  rollback_evidence_sha256 text,
  rollback_operator text,
  rollback_code_version text,
  rollback_dependency_lock_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, audit, analysis, processing, reporting
as $$
declare
  result jsonb;
  effective_label text := requested_rollback_release_label;
  conflict_constraint text;
  attempt integer;
begin
  for attempt in 0..4 loop
    begin
      result := reporting.rollback_row_correction_bundle_v1(
        target_release_label,
        effective_label,
        rollback_reviewer,
        rollback_reason,
        rollback_evidence_sha256,
        rollback_operator,
        rollback_code_version,
        rollback_dependency_lock_hash
      );
      exit;
    exception
      when unique_violation then
        get stacked diagnostics
          conflict_constraint = constraint_name;
        if conflict_constraint is distinct from
            'aggregate_releases_release_label_key' then
          raise;
        end if;
        effective_label := requested_rollback_release_label
          || '-recovery-' || gen_random_uuid()::text;
    end;
  end loop;

  if result is null then
    raise exception
      'automatic correction rollback could not allocate a unique recovery label';
  end if;

  insert into audit.correction_recovery_labels_v1 (
    target_release_label,
    requested_rollback_release_label,
    effective_rollback_release_label,
    rollback_release_id,
    fallback_used
  ) values (
    target_release_label,
    requested_rollback_release_label,
    effective_label,
    (result ->> 'rollback_release_id')::uuid,
    effective_label <> requested_rollback_release_label
  );

  return result || jsonb_build_object(
    'requested_rollback_release_label', requested_rollback_release_label,
    'effective_rollback_release_label', effective_label,
    'rollback_label_fallback_used',
      effective_label <> requested_rollback_release_label
  );
end;
$$;

revoke execute on function
  reporting.rollback_row_correction_bundle_recovery_v2(
    text, text, text, text, text, text, text, text
  ) from public, anon, authenticated, web_reader;

revoke all on
  analysis.row_correction_reporting_classification_v2,
  analysis.row_correction_target_teams_v2,
  analysis.row_correction_incremental_context_v2,
  analysis.row_correction_team_payload_candidates_incremental_v2,
  analysis.row_correction_league_dashboard_payload_incremental_v2,
  analysis.team_dashboard_release_candidates_correction_v2,
  analysis.league_dashboard_release_candidates_correction_v2,
  analysis.row_correction_pending_candidate_v2
from public, anon, authenticated, web_reader;

do $$
begin
  if pg_get_functiondef(
      'analysis.row_correction_team_dashboard_payload_data_v2_internal()'::regprocedure
    ) not like '%analysis.row_correction_target_teams_v2%'
    or pg_get_functiondef(
      'analysis.row_correction_team_dashboard_payload_data_v2_internal()'::regprocedure
    ) like '%analysis.row_correction_target_teams_v1%'
    or pg_get_functiondef(
      'analysis.row_correction_team_dashboard_payload_data_v2_internal()'::regprocedure
    ) not like '%analysis.row_correction_reporting_classification_v2%'
    or pg_get_functiondef(
      'analysis.row_correction_pending_candidate_data_v2(text)'::regprocedure
    ) not like '%where context.season = target_season%'
    or pg_get_functiondef(
      'analysis.row_correction_pending_candidate_data_v2(text)'::regprocedure
    ) not like '%team_dashboard_release_candidates_correction_v2%'
    or pg_get_functiondef(
      'analysis.row_correction_preview_v2(jsonb)'::regprocedure
    ) not like '%analysis.row_correction_pending_candidate_v2%'
    or pg_get_functiondef(
      'audit.apply_row_correction_v2_internal(jsonb,text,text)'::regprocedure
    ) not like '%analysis.row_correction_preview_v2%'
    or pg_get_functiondef(
      'audit.apply_row_correction_v2_internal(jsonb,text,text)'::regprocedure
    ) not like
      '%20260727010000_dynamic_row_correction_pipeline_hardening.sql%'
    or pg_get_functiondef(
      'audit.apply_row_correction_v2_internal(jsonb,text,text)'::regprocedure
    ) not like '%row_correction_candidate_2026-07-27_v2%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_v2(text,text,text)'::regprocedure
    ) not like '%row_correction_pending_candidate_data_v2(%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_v2(text,text,text)'::regprocedure
    ) not like
      '%20260727010000_dynamic_row_correction_pipeline_hardening.sql%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_v2(text,text,text)'::regprocedure
    ) not like '%row_correction_release_2026-07-27_v2%'
    or pg_get_viewdef(
      'analysis.row_correction_incremental_context_v2'::regclass, true
    ) not like '%analysis.row_correction_target_teams_v2%'
    or pg_get_viewdef(
      'analysis.row_correction_team_payload_candidates_incremental_v2'::regclass,
      true
    ) not like
      '%analysis.row_correction_team_dashboard_payload_data_v2_internal()%'
    or pg_get_viewdef(
      'analysis.row_correction_league_dashboard_payload_incremental_v2'::regclass,
      true
    ) not like
      '%analysis.row_correction_team_payload_candidates_incremental_v2%' then
    raise exception
      'dynamic row-correction V2 candidate graph was not rewired exactly';
  end if;
end;
$$;

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
      'dynamic row-correction hardening installation must be data-neutral';
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
      'approved 2024-25 V5 bundle changed during hardening installation';
  end if;
end;
$$;
