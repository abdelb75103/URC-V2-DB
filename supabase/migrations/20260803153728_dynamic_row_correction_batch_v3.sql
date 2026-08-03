-- Additive, same-team batch successor for the audited row-correction path.
--
-- A batch applies one or more independently evidenced row decisions for one
-- team, then recomputes that team and the pooled league payload once. Existing
-- V1/V2 corrections, immutable source/curated rows, frozen analysis views and
-- the correction-aware V5 readers remain unchanged.

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260727010000'
      and migration.name = 'dynamic_row_correction_pipeline_hardening'
      and migration.statements = array[
        'migration_sha256=29dd76bb42ac7bdc10f3a6691bf538a1af4786a15408acc467a4c9beab4cd57b'
      ]
  ) then
    raise exception
      'row-correction batch V3 requires the exact registered V2 hardening migration';
  end if;
end;
$$;

insert into audit.reason_codes (code, description) values
  (
    'row_correction_batch_applied',
    'A reviewed same-team batch of independently evidenced row corrections was appended in one transaction.'
  ),
  (
    'row_correction_batch_draft',
    'One affected team and the pooled league were recomputed once for an audited correction batch.'
  ),
  (
    'row_correction_batch_release',
    'A reviewed correction-batch draft was promoted through the immutable correction bundle lineage.'
  )
on conflict (code) do nothing;

create table audit.correction_batches_v3 (
  id uuid primary key default gen_random_uuid(),
  correction_set_id uuid not null unique
    references audit.correction_sets_v1(id),
  season text not null,
  team_key text not null references reporting.teams(team_key),
  proposal_hash text not null unique check (proposal_hash ~ '^[0-9a-f]{64}$'),
  item_count integer not null check (item_count > 0),
  reviewer text not null check (btrim(reviewer) <> ''),
  created_at timestamptz not null default now()
);

create table audit.correction_batch_items_v3 (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references audit.correction_batches_v3(id),
  item_index integer not null check (item_index >= 0),
  season text not null,
  source_row_id uuid not null references ingestion.source_rows(id),
  field_name text not null check (field_name in (
    'eligibility', 'days_injured', 'body_location_code',
    'injury_type_code', 'diagnosis_code'
  )),
  old_value jsonb,
  new_value jsonb,
  reason text not null check (btrim(reason) <> ''),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  operator text not null check (btrim(operator) <> ''),
  reviewer text not null check (btrim(reviewer) <> ''),
  rule_version text not null check (btrim(rule_version) <> ''),
  proposal_hash text not null check (proposal_hash ~ '^[0-9a-f]{64}$'),
  supersedes_correction_id uuid,
  created_at timestamptz not null default now(),
  unique (batch_id, item_index),
  unique (batch_id, source_row_id, field_name)
);

create table processing.correction_batch_versions_v3 (
  id uuid primary key default gen_random_uuid(),
  batch_item_id uuid not null unique
    references audit.correction_batch_items_v3(id),
  source_row_id uuid not null references ingestion.source_rows(id),
  field_name text not null,
  effective_value_before jsonb,
  effective_value_after jsonb,
  input_row_fingerprint text not null check (input_row_fingerprint ~ '^[0-9a-f]{64}$'),
  output_row_fingerprint text not null check (output_row_fingerprint ~ '^[0-9a-f]{64}$'),
  input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
  output_hash text not null check (output_hash ~ '^[0-9a-f]{64}$'),
  step_run_id uuid not null references audit.step_runs(id),
  created_at timestamptz not null default now()
);

alter table audit.correction_batches_v3 enable row level security;
alter table audit.correction_batch_items_v3 enable row level security;
alter table processing.correction_batch_versions_v3 enable row level security;
revoke all on audit.correction_batches_v3,
  audit.correction_batch_items_v3,
  processing.correction_batch_versions_v3
from public, anon, authenticated, web_reader;

create trigger correction_batches_v3_append_only
before update or delete on audit.correction_batches_v3
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_batch_items_v3_append_only
before update or delete on audit.correction_batch_items_v3
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_batch_versions_v3_append_only
before update or delete on processing.correction_batch_versions_v3
for each row execute function audit.reject_row_correction_history_mutation_v1();

create function analysis.row_correction_current_batch_v3()
returns jsonb
language sql
volatile
set search_path = pg_catalog
as $$
  select nullif(current_setting('urc.row_correction_batch_v3', true), '')::jsonb;
$$;

revoke execute on function analysis.row_correction_current_batch_v3()
  from public, anon, authenticated, web_reader;

create view analysis.row_correction_active_values_v3
with (security_invoker = true) as
with eligible_sets as (
  select served.correction_set_id
  from analysis.row_correction_served_sets_v1 served
  union
  select correction_set.id
  from audit.correction_sets_v1 correction_set
  where not exists (
    select 1 from reporting.correction_release_context_v1 released
    where released.correction_set_id = correction_set.id
  ) or exists (
    select 1
    from reporting.correction_release_context_v1 released
    join reporting.aggregate_releases release
      on release.id = released.bundle_release_id
    where released.correction_set_id = correction_set.id
      and release.status = 'draft'
  )
), legacy as (
  select correction.id as correction_id, correction.correction_set_id,
    correction.season, correction.source_row_id, correction.field_name,
    correction.new_value, correction.evidence_sha256,
    correction.rule_version, correction.proposal_hash, correction.created_at
  from audit.row_corrections_v1 correction
  join eligible_sets eligible on eligible.correction_set_id = correction.correction_set_id
  where not exists (
    select 1 from audit.correction_batches_v3 batch
    where batch.correction_set_id = correction.correction_set_id
  )
), batch as (
  select item.id as correction_id, batch.correction_set_id,
    item.season, item.source_row_id, item.field_name, item.new_value,
    item.evidence_sha256, item.rule_version, item.proposal_hash, item.created_at
  from audit.correction_batch_items_v3 item
  join audit.correction_batches_v3 batch on batch.id = item.batch_id
  join eligible_sets eligible on eligible.correction_set_id = batch.correction_set_id
)
select distinct on (season, source_row_id, field_name)
  correction_id, correction_set_id, season, source_row_id, field_name,
  new_value, evidence_sha256, rule_version, proposal_hash, created_at
from (
  select * from legacy
  union all
  select * from batch
) values_union
order by season, source_row_id, field_name, created_at desc, correction_id desc;

create view analysis.row_correction_effective_values_v3
with (security_invoker = true) as
with proposed as (
  select null::uuid as correction_id, null::uuid as correction_set_id,
    proposal ->> 'season' as season,
    (item ->> 'source_row_id')::uuid as source_row_id,
    item ->> 'field_name' as field_name,
    item -> 'new_value' as new_value,
    item ->> 'evidence_sha256' as evidence_sha256,
    item ->> 'rule_version' as rule_version,
    coalesce(proposal ->> 'proposal_hash', '') as proposal_hash,
    clock_timestamp() as created_at,
    1 as priority
  from analysis.row_correction_current_batch_v3() proposal
  cross join lateral jsonb_array_elements(proposal -> 'items') item
  where proposal is not null
), active as (
  select active.*, 0 as priority
  from analysis.row_correction_active_values_v3 active
)
select distinct on (season, source_row_id, field_name)
  correction_id, correction_set_id, season, source_row_id, field_name,
  new_value, evidence_sha256, rule_version, proposal_hash, created_at
from (
  select * from active
  union all
  select * from proposed
) overlay
order by season, source_row_id, field_name, priority desc, created_at desc,
  correction_id desc nulls first;

create function audit.row_correction_set_hash_v3(
  target_season text,
  proposed jsonb default null
)
returns text
language sql
stable
set search_path = pg_catalog, analysis, audit, public
as $$
with proposed_keys as (
  select (item ->> 'source_row_id')::uuid as source_row_id,
    item ->> 'field_name' as field_name
  from jsonb_array_elements(coalesce(proposed -> 'items', '[]'::jsonb)) item
), active as (
  select active.source_row_id, active.field_name, active.new_value,
    active.evidence_sha256, active.rule_version
  from analysis.row_correction_active_values_v3 active
  where active.season = target_season
    and not exists (
      select 1 from proposed_keys key
      where key.source_row_id = active.source_row_id
        and key.field_name = active.field_name
    )
), proposed_rows as (
  select (item ->> 'source_row_id')::uuid as source_row_id,
    item ->> 'field_name' as field_name, item -> 'new_value' as new_value,
    item ->> 'evidence_sha256' as evidence_sha256,
    item ->> 'rule_version' as rule_version
  from jsonb_array_elements(coalesce(proposed -> 'items', '[]'::jsonb)) item
  where proposed ->> 'season' = target_season
), state as (
  select * from active
  union all
  select * from proposed_rows
)
select encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object(
  'source_row_id', source_row_id,
  'field_name', field_name,
  'new_value', new_value,
  'evidence_sha256', evidence_sha256,
  'rule_version', rule_version
) order by source_row_id, field_name), '[]'::jsonb)::text, 'UTF8'), 'sha256'), 'hex')
from state;
$$;

revoke execute on function audit.row_correction_set_hash_v3(text, jsonb)
  from public, anon, authenticated, web_reader;

-- Reuse the frozen analytical formulas through exact-definition clones. Only
-- the effective-value and subject inputs are rewired to the batch overlay.
do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_subject_v1(text,uuid)'::regprocedure
  );
  definition := replace(definition, 'row_correction_subject_v1', 'row_correction_subject_v3');
  definition := replace(definition,
    'analysis.row_correction_active_values_v1',
    'analysis.row_correction_active_values_v3');
  execute definition;
end;
$$;

revoke execute on function analysis.row_correction_subject_v3(text, uuid)
  from public, anon, authenticated, web_reader;

create view analysis.row_correction_target_keys_v3
with (security_invoker = true) as
select proposal ->> 'season' as season, subject.team_key,
  (item ->> 'source_row_id')::uuid as source_row_id
from analysis.row_correction_current_batch_v3() proposal
cross join lateral jsonb_array_elements(proposal -> 'items') item
cross join lateral analysis.row_correction_subject_v3(
  proposal ->> 'season', (item ->> 'source_row_id')::uuid
) subject
where proposal is not null
union
select batch.season, batch.team_key, item.source_row_id
from audit.correction_batches_v3 batch
join audit.correction_batch_items_v3 item on item.batch_id = batch.id
where not exists (
  select 1 from reporting.correction_release_context_v1 released
  where released.correction_set_id = batch.correction_set_id
) or exists (
  select 1
  from reporting.correction_release_context_v1 released
  join reporting.aggregate_releases release
    on release.id = released.bundle_release_id
  where released.correction_set_id = batch.correction_set_id
    and release.status = 'draft'
);

do $$
declare
  source_names text[] := array[
    'row_correction_effective_subjects_v1',
    'row_correction_effective_injury_cohort_v1',
    'row_correction_reporting_classification_v1',
    'row_correction_team_summary_v1',
    'row_correction_setting_split_v1',
    'row_correction_injury_profiles_v1',
    'row_correction_effective_injury_profiles_v1',
    'row_correction_diagnosis_profiles_v1',
    'row_correction_monthly_v1',
    'row_correction_severity_distribution_v1',
    'row_correction_contact_distribution_v1',
    'row_correction_league_contact_distribution_v1',
    'row_correction_league_summary_v1',
    'row_correction_league_setting_split_v1',
    'row_correction_league_injury_profiles_v1',
    'row_correction_league_effective_injury_profiles_v1',
    'row_correction_league_diagnosis_profiles_v1',
    'row_correction_league_monthly_v1',
    'row_correction_league_severity_distribution_v1'
  ];
  target_names text[] := array[
    'row_correction_effective_subjects_v3',
    'row_correction_effective_injury_cohort_v3',
    'row_correction_reporting_classification_v3',
    'row_correction_team_summary_v3',
    'row_correction_setting_split_v3',
    'row_correction_injury_profiles_v3',
    'row_correction_effective_injury_profiles_v3',
    'row_correction_diagnosis_profiles_v3',
    'row_correction_monthly_v3',
    'row_correction_severity_distribution_v3',
    'row_correction_contact_distribution_v3',
    'row_correction_league_contact_distribution_v3',
    'row_correction_league_summary_v3',
    'row_correction_league_setting_split_v3',
    'row_correction_league_injury_profiles_v3',
    'row_correction_league_effective_injury_profiles_v3',
    'row_correction_league_diagnosis_profiles_v3',
    'row_correction_league_monthly_v3',
    'row_correction_league_severity_distribution_v3'
  ];
  definition text;
  i integer;
  j integer;
begin
  for i in 1..array_length(source_names, 1) loop
    definition := pg_get_viewdef(
      ('analysis.' || source_names[i])::regclass, true
    );
    definition := replace(definition,
      'analysis.row_correction_effective_values_v1',
      'analysis.row_correction_effective_values_v3');
    definition := replace(definition,
      'row_correction_effective_values_v1',
      'row_correction_effective_values_v3');
    definition := replace(definition,
      'analysis.row_correction_subject_v1',
      'analysis.row_correction_subject_v3');
    definition := replace(definition,
      'row_correction_subject_v1',
      'row_correction_subject_v3');
    for j in 1..i loop
      definition := replace(definition,
        'analysis.' || source_names[j],
        'analysis.' || target_names[j]);
      definition := replace(definition, source_names[j], target_names[j]);
    end loop;
    execute 'create view analysis.' || quote_ident(target_names[i])
      || ' with (security_invoker = true) as ' || definition;
  end loop;
end;
$$;

create view analysis.row_correction_reporting_classification_origin_v3
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
  case when exists (
    select 1 from analysis.row_correction_effective_values_v3 effective
    where effective.season = classification.season
      and effective.source_row_id = injury.source_row_id
      and effective.field_name = 'body_location_code'
  ) then 'row_correction' else classification.body_location_origin end
    as body_location_origin,
  case when exists (
    select 1 from analysis.row_correction_effective_values_v3 effective
    where effective.season = classification.season
      and effective.source_row_id = injury.source_row_id
      and effective.field_name = 'injury_type_code'
  ) then 'row_correction' else classification.injury_type_origin end
    as injury_type_origin,
  case when exists (
    select 1 from analysis.row_correction_effective_values_v3 effective
    where effective.season = classification.season
      and effective.source_row_id = injury.source_row_id
      and effective.field_name = 'diagnosis_code'
  ) then 'row_correction' else classification.diagnosis_origin end
    as diagnosis_origin,
  classification.injury_type_candidate_count,
  classification.candidate_injury_types
from analysis.row_correction_reporting_classification_v3 classification
join curated.injuries injury
  on injury.id = classification.injury_id
 and injury.curated_build_id = classification.curated_build_id
 and injury.team_key = classification.team_key
 and injury.season = classification.season;

create view analysis.row_correction_target_teams_v3
with (security_invoker = true) as
select distinct season, team_key
from analysis.row_correction_target_keys_v3;

do $$
declare
  definition text;
  source_names text[] := array[
    'row_correction_team_summary_v1', 'row_correction_setting_split_v1',
    'row_correction_injury_profiles_v1', 'row_correction_effective_injury_profiles_v1',
    'row_correction_diagnosis_profiles_v1', 'row_correction_monthly_v1',
    'row_correction_severity_distribution_v1', 'row_correction_contact_distribution_v1'
  ];
  target_names text[] := array[
    'row_correction_team_summary_v3', 'row_correction_setting_split_v3',
    'row_correction_injury_profiles_v3', 'row_correction_effective_injury_profiles_v3',
    'row_correction_diagnosis_profiles_v3', 'row_correction_monthly_v3',
    'row_correction_severity_distribution_v3', 'row_correction_contact_distribution_v3'
  ];
  i integer;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_team_dashboard_payload_data_v2_internal()'::regprocedure
  );
  definition := replace(definition,
    'row_correction_team_dashboard_payload_data_v2_internal',
    'row_correction_team_dashboard_payload_data_v3_internal');
  definition := replace(definition,
    'analysis.row_correction_target_teams_v2',
    'analysis.row_correction_target_teams_v3');
  definition := replace(definition,
    'analysis.row_correction_reporting_classification_v2',
    'analysis.row_correction_reporting_classification_origin_v3');
  definition := replace(definition,
    'row_correction_reporting_classification_v2',
    'row_correction_reporting_classification_origin_v3');
  for i in 1..array_length(source_names, 1) loop
    definition := replace(definition,
      'analysis.' || source_names[i], 'analysis.' || target_names[i]);
    definition := replace(definition, source_names[i], target_names[i]);
  end loop;
  execute definition;
end;
$$;

revoke execute on function
  analysis.row_correction_team_dashboard_payload_data_v3_internal()
from public, anon, authenticated, web_reader;

do $$
declare
  definition text;
  source_names text[] := array[
    'row_correction_effective_injury_cohort_v1',
    'row_correction_exposure_hours_v1',
    'row_correction_league_contact_distribution_v1',
    'row_correction_league_summary_v1',
    'row_correction_league_setting_split_v1',
    'row_correction_league_injury_profiles_v1',
    'row_correction_league_effective_injury_profiles_v1',
    'row_correction_league_diagnosis_profiles_v1',
    'row_correction_league_monthly_v1',
    'row_correction_league_severity_distribution_v1'
  ];
  target_names text[] := array[
    'row_correction_effective_injury_cohort_v3',
    'row_correction_exposure_hours_v1',
    'row_correction_league_contact_distribution_v3',
    'row_correction_league_summary_v3',
    'row_correction_league_setting_split_v3',
    'row_correction_league_injury_profiles_v3',
    'row_correction_league_effective_injury_profiles_v3',
    'row_correction_league_diagnosis_profiles_v3',
    'row_correction_league_monthly_v3',
    'row_correction_league_severity_distribution_v3'
  ];
  i integer;
begin
  definition := pg_get_viewdef(
    'analysis.row_correction_incremental_context_v2'::regclass, true
  );
  definition := replace(definition,
    'analysis.row_correction_target_teams_v2',
    'analysis.row_correction_target_teams_v3');
  definition := replace(definition,
    'row_correction_target_teams_v2',
    'row_correction_target_teams_v3');
  execute 'create view analysis.row_correction_incremental_context_v3 '
    'with (security_invoker = true) as ' || definition;

  definition := pg_get_viewdef(
    'analysis.row_correction_team_payload_candidates_incremental_v2'::regclass,
    true
  );
  definition := replace(definition,
    'analysis.row_correction_incremental_context_v2',
    'analysis.row_correction_incremental_context_v3');
  definition := replace(definition,
    'row_correction_incremental_context_v2',
    'row_correction_incremental_context_v3');
  definition := replace(definition,
    'analysis.row_correction_team_dashboard_payload_data_v2_internal()',
    'analysis.row_correction_team_dashboard_payload_data_v3_internal()');
  definition := replace(definition,
    'row_correction_team_dashboard_payload_data_v2_internal',
    'row_correction_team_dashboard_payload_data_v3_internal');
  execute 'create view analysis.row_correction_team_payload_candidates_incremental_v3 '
    'with (security_invoker = true) as ' || definition;

  definition := pg_get_viewdef(
    'analysis.row_correction_league_dashboard_payload_incremental_v2'::regclass,
    true
  );
  definition := replace(definition,
    'analysis.row_correction_team_payload_candidates_incremental_v2',
    'analysis.row_correction_team_payload_candidates_incremental_v3');
  definition := replace(definition,
    'row_correction_team_payload_candidates_incremental_v2',
    'row_correction_team_payload_candidates_incremental_v3');
  definition := replace(definition,
    'analysis.row_correction_incremental_context_v2',
    'analysis.row_correction_incremental_context_v3');
  for i in 1..array_length(source_names, 1) loop
    definition := replace(definition,
      'analysis.' || source_names[i], 'analysis.' || target_names[i]);
    definition := replace(definition, source_names[i], target_names[i]);
  end loop;
  execute 'create view analysis.row_correction_league_dashboard_payload_incremental_v3 '
    'with (security_invoker = true) as ' || definition;
end;
$$;

create view analysis.row_correction_pending_context_v3
with (security_invoker = true) as
with preview as (
  select null::uuid as correction_set_id,
    proposal ->> 'season' as season,
    proposal ->> 'proposal_hash' as proposal_hash,
    proposal ->> 'team_key' as affected_team_key,
    1 as priority
  from analysis.row_correction_current_batch_v3() proposal
  where proposal is not null
), pending as (
  select batch.correction_set_id, batch.season, batch.proposal_hash,
    batch.team_key as affected_team_key, 0 as priority
  from audit.correction_batches_v3 batch
  where not exists (
    select 1 from reporting.correction_release_context_v1 released
    where released.correction_set_id = batch.correction_set_id
  ) or exists (
    select 1
    from reporting.correction_release_context_v1 released
    join reporting.aggregate_releases release
      on release.id = released.bundle_release_id
    where released.correction_set_id = batch.correction_set_id
      and release.status = 'draft'
  )
)
select distinct on (context.season)
  context.correction_set_id, context.season, context.proposal_hash,
  context.affected_team_key,
  bundle.release_id as predecessor_bundle_id,
  release.release_label as predecessor_release_label,
  analysis.row_correction_bundle_hash_v1(bundle.release_id)
    as predecessor_bundle_sha256,
  bundle_context.classification_view_version,
  bundle_context.classification_evidence_sha256,
  bundle_context.cohort_view_version,
  bundle_context.cohort_evidence_sha256
from (
  select * from pending
  union all
  select * from preview
) context
join reporting.latest_approved_dashboard_bundle_v4 bundle
  on bundle.season = context.season
join reporting.aggregate_releases release on release.id = bundle.release_id
join reporting.dashboard_bundle_context_v1 bundle_context
  on bundle_context.release_id = bundle.release_id
order by context.season, context.priority desc,
  context.correction_set_id desc nulls first;

create view analysis.team_dashboard_release_candidates_correction_v3
with (security_invoker = true) as
select candidate.team_key, candidate.season, candidate.team_release_id,
  candidate.curated_build_id, 'correction_batch_v3'::text as analysis_version,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version, context.cohort_evidence_sha256,
  candidate.dashboard
from analysis.row_correction_pending_context_v3 context
join analysis.row_correction_team_payload_candidates_incremental_v3 candidate
  using (season)
where context.season = nullif(
  current_setting('urc.row_correction_target_season', true), ''
);

create view analysis.league_dashboard_release_candidates_correction_v3
with (security_invoker = true) as
select context.season, 'correction_batch_v3'::text as analysis_version,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version, context.cohort_evidence_sha256,
  corrected.dashboard
from analysis.row_correction_pending_context_v3 context
join analysis.row_correction_league_dashboard_payload_incremental_v3 corrected
  on corrected.season = context.season
where context.season = nullif(
  current_setting('urc.row_correction_target_season', true), ''
);

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'analysis.row_correction_pending_candidate_data_v2(text)'::regprocedure
  );
  definition := replace(definition,
    'row_correction_pending_candidate_data_v2',
    'row_correction_pending_candidate_data_v3');
  definition := replace(definition,
    'analysis.row_correction_pending_context_v1',
    'analysis.row_correction_pending_context_v3');
  definition := replace(definition,
    'analysis.league_dashboard_release_candidates_correction_v2',
    'analysis.league_dashboard_release_candidates_correction_v3');
  definition := replace(definition,
    'analysis.team_dashboard_release_candidates_correction_v2',
    'analysis.team_dashboard_release_candidates_correction_v3');
  definition := replace(definition,
    'audit.row_correction_set_hash_v1(',
    'audit.row_correction_set_hash_v3(');
  definition := replace(definition,
    'analysis.row_correction_current_preview_v1()',
    'analysis.row_correction_current_batch_v3()');
  execute definition;
end;
$$;

revoke execute on function
  analysis.row_correction_pending_candidate_data_v3(text)
from public, anon, authenticated, web_reader;

create function analysis.validate_row_correction_value_v3(
  requested_field text,
  requested_new jsonb
)
returns void
language plpgsql
stable
set search_path = pg_catalog, curated
as $$
begin
  if requested_field = 'eligibility'
    and jsonb_typeof(requested_new) is distinct from 'boolean' then
    raise exception 'eligibility correction requires a boolean value';
  elsif requested_field = 'days_injured' and not (
    requested_new = 'null'::jsonb or (
      jsonb_typeof(requested_new) is not distinct from 'number'
      and (requested_new #>> '{}') ~ '^\d+$'
      and (requested_new #>> '{}')::numeric >= 0
    )
  ) then
    raise exception 'days_injured correction requires a non-negative integer or null';
  elsif requested_field in ('body_location_code', 'injury_type_code') then
    if jsonb_typeof(requested_new) is distinct from 'string'
      or not exists (
        select 1 from curated.code_lists code
        where code.list_name = case requested_field
          when 'body_location_code' then 'body_location'
          else 'injury_type'
        end
          and code.code = requested_new #>> '{}'
      ) then
      raise exception 'clinical correction is not a controlled IOC code';
    end if;
  elsif requested_field = 'diagnosis_code' and (
    jsonb_typeof(requested_new) is distinct from 'string' or not (
      requested_new #>> '{}' in ('unknown', 'concussion') or (
        requested_new #>> '{}' ~ '^compound__[a-z0-9_]+__[a-z0-9_]+$'
        and exists (
          select 1 from curated.code_lists body
          where body.list_name = 'body_location'
            and body.code = split_part(requested_new #>> '{}', '__', 2)
        )
        and exists (
          select 1 from curated.code_lists injury_type
          where injury_type.list_name = 'injury_type'
            and injury_type.code = split_part(requested_new #>> '{}', '__', 3)
        )
      )
    )
  ) then
    raise exception
      'diagnosis correction must be unknown, concussion, or controlled compound code';
  end if;
end;
$$;

revoke execute on function analysis.validate_row_correction_value_v3(text, jsonb)
  from public, anon, authenticated, web_reader;

create function analysis.row_correction_preview_v3(proposal jsonb)
returns table (
  subjects jsonb,
  predecessor_bundle jsonb,
  correction_set_hash_before text,
  correction_set_hash_after text,
  affected_team_before jsonb,
  affected_team_after jsonb,
  affected_team_before_sha256 text,
  affected_team_after_sha256 text,
  affected_league_before jsonb,
  affected_league_after jsonb,
  affected_league_before_sha256 text,
  affected_league_after_sha256 text,
  unchanged_team_hashes jsonb,
  candidate_bundle jsonb,
  draft_bundle_sha256 text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting,
  ingestion, curated, lineage
as $$
declare
  item jsonb;
  target record;
  requested_field text;
  current_value jsonb;
  active_correction_id uuid;
  target_team text;
  subject_docs jsonb := '[]'::jsonb;
  pending_count integer;
begin
  if proposal is null
    or nullif(proposal ->> 'season', '') is null
    or nullif(proposal ->> 'operator', '') is null
    or nullif(proposal ->> 'code_version', '') is null
    or coalesce(proposal ->> 'dependency_lock_hash', '') !~ '^[0-9a-f]{64}$'
    or coalesce(proposal ->> 'migration_sha256', '') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(proposal -> 'items') is distinct from 'array'
    or jsonb_array_length(proposal -> 'items') = 0 then
    raise exception 'invalid or incomplete row-correction batch proposal';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(proposal -> 'items') item
    group by item ->> 'source_row_id', item ->> 'field_name'
    having count(*) > 1
  ) then
    raise exception 'a correction batch cannot repeat a source-row field';
  end if;

  select count(*) into pending_count
  from audit.correction_sets_v1 correction_set
  where correction_set.season = proposal ->> 'season'
    and not exists (
      select 1 from reporting.correction_release_context_v1 released
      where released.correction_set_id = correction_set.id
    );
  if pending_count <> 0 then
    raise exception 'a correction is already applied but unpromoted for this season';
  end if;

  for item in select value from jsonb_array_elements(proposal -> 'items') loop
    requested_field := item ->> 'field_name';
    if not (item ? 'expected_value') or not (item ? 'new_value')
      or nullif(item ->> 'source_row_id', '') is null
      or requested_field not in (
        'eligibility', 'days_injured', 'body_location_code',
        'injury_type_code', 'diagnosis_code'
      )
      or nullif(item ->> 'reason', '') is null
      or coalesce(item ->> 'evidence_sha256', '') !~ '^[0-9a-f]{64}$'
      or nullif(item ->> 'rule_version', '') is null then
      raise exception 'invalid row-correction batch item';
    end if;

    select * into target
    from analysis.row_correction_subject_v3(
      proposal ->> 'season', (item ->> 'source_row_id')::uuid
    ) row_target;
    if not found then
      raise exception 'source row is not an allowlisted bridged injury row for this season';
    end if;
    if target_team is null then
      target_team := target.team_key;
    elsif target_team is distinct from target.team_key then
      raise exception 'a correction batch must target exactly one team';
    end if;

    current_value := case requested_field
      when 'eligibility' then target.eligibility_value
      when 'days_injured' then target.days_injured_value
      when 'body_location_code' then target.body_location_value
      when 'injury_type_code' then target.injury_type_value
      when 'diagnosis_code' then target.diagnosis_value
    end;
    if current_value is distinct from item -> 'expected_value' then
      raise exception 'expected current effective value does not match';
    end if;
    if item -> 'new_value' is not distinct from current_value then
      raise exception 'new value must differ from the current effective value';
    end if;
    perform analysis.validate_row_correction_value_v3(
      requested_field, item -> 'new_value'
    );

    select active.correction_id into active_correction_id
    from analysis.row_correction_active_values_v3 active
    where active.season = target.season
      and active.source_row_id = target.source_row_id
      and active.field_name = requested_field;
    if active_correction_id is distinct from
        nullif(item ->> 'supersedes_correction_id', '')::uuid then
      raise exception
        'supersedes_correction_id does not match the latest correction history';
    end if;

    subject_docs := subject_docs || jsonb_build_array(jsonb_build_object(
      'source_row_id', target.source_row_id,
      'source_row_sha256', target.source_row_sha256,
      'row_fingerprint', target.row_fingerprint,
      'team_key', target.team_key,
      'season', target.season,
      'field_name', requested_field,
      'current_effective_value', current_value
    ));
  end loop;

  if nullif(proposal ->> 'team_key', '') is not null
    and proposal ->> 'team_key' is distinct from target_team then
    raise exception 'proposal team binding changed';
  end if;
  proposal := jsonb_set(proposal, '{team_key}', to_jsonb(target_team), true);
  perform set_config('urc.row_correction_batch_v3', proposal::text, true);
  perform set_config('urc.row_correction_target_season', proposal ->> 'season', true);

  return query
  select subject_docs,
    candidate.predecessor_bundle,
    audit.row_correction_set_hash_v3(proposal ->> 'season', null),
    audit.row_correction_set_hash_v3(proposal ->> 'season', proposal),
    before_team.dashboard_payload,
    after_team.doc -> 'dashboard',
    before_team.payload_sha256,
    encode(extensions.digest(convert_to(
      (after_team.doc -> 'dashboard')::text, 'UTF8'
    ), 'sha256'), 'hex'),
    before_league.dashboard_payload,
    candidate.bundle -> 'league',
    before_league.payload_sha256,
    encode(extensions.digest(convert_to(
      (candidate.bundle -> 'league')::text, 'UTF8'
    ), 'sha256'), 'hex'),
    candidate.unchanged_team_hashes,
    candidate.bundle,
    candidate.draft_bundle_sha256
  from analysis.row_correction_pending_candidate_data_v3(
    proposal ->> 'season'
  ) candidate
  join analysis.row_correction_pending_context_v3 context
    on context.season = candidate.season
  join reporting.dashboard_bundle_team_payloads_v1 before_team
    on before_team.bundle_release_id = context.predecessor_bundle_id
   and before_team.team_key = target_team
  cross join lateral jsonb_array_elements(candidate.bundle -> 'teams') after_team(doc)
  join reporting.dashboard_bundle_league_payloads_v1 before_league
    on before_league.release_id = context.predecessor_bundle_id
  where candidate.season = proposal ->> 'season'
    and after_team.doc ->> 'team_key' = target_team;
end;
$$;

revoke execute on function analysis.row_correction_preview_v3(jsonb)
  from public, anon, authenticated, web_reader;

create function audit.apply_row_correction_batch_v3(
  proposal jsonb,
  approval_evidence_by_item jsonb,
  approval_reviewer text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting,
  ingestion, curated, lineage, supabase_migrations
as $$
declare
  preview_row record;
  target record;
  item jsonb;
  subject_doc jsonb;
  current_value jsonb;
  evidence_text text;
  item_key text;
  expected_proposal_hash text;
  current_bundle_id uuid;
  current_bundle_sha256 text;
  set_id uuid := gen_random_uuid();
  batch_id uuid := gen_random_uuid();
  batch_item_id uuid;
  run_id uuid := gen_random_uuid();
  apply_step_id uuid := gen_random_uuid();
  draft_step_id uuid := gen_random_uuid();
  draft_id uuid := gen_random_uuid();
  anchor_item jsonb := proposal -> 'items' -> 0;
  item_index integer := 0;
begin
  if approval_reviewer <> 'Abdel Babiker' then
    raise exception 'correction batch apply requires Abdel Babiker as reviewer';
  end if;
  if not exists (
    select 1 from supabase_migrations.schema_migrations migration
    where migration.version = '20260803153728'
      and migration.name = 'dynamic_row_correction_batch_v3'
      and migration.statements = array[
        'migration_sha256=' || coalesce(proposal ->> 'migration_sha256', '')
      ]
  ) then
    raise exception
      'proposal migration SHA does not match the installed batch implementation';
  end if;
  if jsonb_typeof(approval_evidence_by_item) is distinct from 'object' then
    raise exception 'correction batch approval evidence must be an object';
  end if;
  expected_proposal_hash := analysis.row_correction_proposal_hash_v1(proposal);
  if proposal ->> 'proposal_hash' is distinct from expected_proposal_hash then
    raise exception 'batch proposal hash is invalid';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('row-correction:' || (proposal ->> 'season'), 0)
  );
  if exists (
    select 1 from audit.correction_sets_v1 correction_set
    where correction_set.season = proposal ->> 'season'
      and not exists (
        select 1 from reporting.correction_release_context_v1 released
        where released.correction_set_id = correction_set.id
      )
  ) then
    raise exception
      'concurrent correction rejected: this season already has a pending set';
  end if;

  perform 1
  from ingestion.source_rows source
  join (
    select distinct (value ->> 'source_row_id')::uuid as source_row_id
    from jsonb_array_elements(proposal -> 'items')
  ) requested on requested.source_row_id = source.id
  order by source.id
  for update of source;

  select bundle.release_id,
    analysis.row_correction_bundle_hash_v1(bundle.release_id)
  into current_bundle_id, current_bundle_sha256
  from reporting.latest_approved_dashboard_bundle_v4 bundle
  join reporting.aggregate_releases release on release.id = bundle.release_id
  where bundle.season = proposal ->> 'season'
  for update of release;
  if current_bundle_id is null
    or current_bundle_id::text is distinct from
      proposal #>> '{predecessor_bundle,release_id}'
    or current_bundle_sha256 is distinct from
      proposal #>> '{predecessor_bundle,bundle_sha256}' then
    raise exception 'stale correction batch: predecessor bundle changed';
  end if;
  if audit.row_correction_set_hash_v3(proposal ->> 'season', null)
      is distinct from proposal ->> 'correction_set_hash_before' then
    raise exception 'concurrent correction rejected: correction-set hash changed';
  end if;

  select * into preview_row
  from analysis.row_correction_preview_v3(proposal);
  if preview_row.correction_set_hash_before is distinct from
      proposal ->> 'correction_set_hash_before'
    or preview_row.correction_set_hash_after is distinct from
      proposal ->> 'correction_set_hash_after'
    or preview_row.affected_team_before_sha256 is distinct from
      proposal ->> 'affected_team_before_sha256'
    or preview_row.affected_team_after_sha256 is distinct from
      proposal ->> 'affected_team_after_sha256'
    or preview_row.affected_league_before_sha256 is distinct from
      proposal ->> 'affected_league_before_sha256'
    or preview_row.affected_league_after_sha256 is distinct from
      proposal ->> 'affected_league_after_sha256'
    or preview_row.unchanged_team_hashes is distinct from
      proposal -> 'unchanged_team_hashes' then
    raise exception 'stale correction batch: downstream preview changed';
  end if;

  for item in select value from jsonb_array_elements(proposal -> 'items') loop
    select value into subject_doc
    from jsonb_array_elements(preview_row.subjects)
    where value ->> 'source_row_id' = item ->> 'source_row_id'
      and value ->> 'field_name' = item ->> 'field_name';
    if subject_doc is null
      or subject_doc ->> 'source_row_sha256' is distinct from
        item ->> 'source_row_sha256'
      or subject_doc ->> 'row_fingerprint' is distinct from
        item ->> 'row_fingerprint' then
      raise exception 'stale correction batch: source-row fingerprint changed';
    end if;
    item_key := item ->> 'source_row_id' || ':' || item ->> 'field_name';
    evidence_text := approval_evidence_by_item ->> item_key;
    if nullif(evidence_text, '') is null
      or encode(extensions.digest(convert_to(evidence_text, 'UTF8'), 'sha256'), 'hex')
        is distinct from item ->> 'evidence_sha256' then
      raise exception 'correction batch approval evidence does not match its hash';
    end if;
  end loop;

  insert into audit.pipeline_runs (
    id, command, team, season, status, parameters, input_hash,
    output_hash, operator, code_version, dependency_lock_hash
  ) values (
    run_id, 'correction-batch-apply', proposal ->> 'team_key',
    proposal ->> 'season', 'started',
    jsonb_build_object(
      'proposal_hash', expected_proposal_hash,
      'reviewer', approval_reviewer,
      'item_count', jsonb_array_length(proposal -> 'items'),
      'base_bundle_id', current_bundle_id,
      'migration_file',
        '20260803153728_dynamic_row_correction_batch_v3.sql',
      'migration_sha256', proposal ->> 'migration_sha256'
    ),
    expected_proposal_hash,
    proposal ->> 'correction_set_hash_after',
    proposal ->> 'operator',
    proposal ->> 'code_version',
    proposal ->> 'dependency_lock_hash'
  );
  insert into audit.step_runs (
    id, pipeline_run_id, step_name, step_version, reason_code,
    input_count, output_count, counts_by_team, input_hash, output_hash
  ) values (
    apply_step_id, run_id, 'apply_row_correction_batch',
    'row_correction_batch_2026-08-03_v3',
    'row_correction_batch_applied',
    jsonb_array_length(proposal -> 'items'),
    jsonb_array_length(proposal -> 'items'),
    jsonb_build_object(
      proposal ->> 'team_key', jsonb_array_length(proposal -> 'items')
    ),
    proposal ->> 'correction_set_hash_before',
    proposal ->> 'correction_set_hash_after'
  );

  select * into target
  from analysis.row_correction_subject_v3(
    proposal ->> 'season', (anchor_item ->> 'source_row_id')::uuid
  );
  current_value := case anchor_item ->> 'field_name'
    when 'eligibility' then target.eligibility_value
    when 'days_injured' then target.days_injured_value
    when 'body_location_code' then target.body_location_value
    when 'injury_type_code' then target.injury_type_value
    when 'diagnosis_code' then target.diagnosis_value
  end;

  -- The V1 correction-set row is a compatibility anchor for the existing
  -- immutable release and rollback lineage. All authoritative batch items are
  -- stored in correction_batch_items_v3 below.
  insert into audit.correction_sets_v1 (
    id, season, proposal_hash, source_row_id, team_key,
    base_bundle_id, base_bundle_sha256,
    correction_set_hash_before, correction_set_hash_after,
    source_row_sha256, row_fingerprint, field_name, old_value, new_value,
    reason, evidence_sha256, operator, reviewer, rule_version,
    code_version, dependency_lock_hash, migration_sha256,
    supersedes_correction_id, apply_pipeline_run_id
  ) values (
    set_id, proposal ->> 'season', expected_proposal_hash,
    (anchor_item ->> 'source_row_id')::uuid, proposal ->> 'team_key',
    current_bundle_id, current_bundle_sha256,
    proposal ->> 'correction_set_hash_before',
    proposal ->> 'correction_set_hash_after',
    anchor_item ->> 'source_row_sha256', anchor_item ->> 'row_fingerprint',
    anchor_item ->> 'field_name', current_value, anchor_item -> 'new_value',
    anchor_item ->> 'reason', anchor_item ->> 'evidence_sha256',
    proposal ->> 'operator', approval_reviewer,
    anchor_item ->> 'rule_version', proposal ->> 'code_version',
    proposal ->> 'dependency_lock_hash', proposal ->> 'migration_sha256',
    null, run_id
  );
  insert into audit.correction_batches_v3 (
    id, correction_set_id, season, team_key, proposal_hash,
    item_count, reviewer
  ) values (
    batch_id, set_id, proposal ->> 'season', proposal ->> 'team_key',
    expected_proposal_hash, jsonb_array_length(proposal -> 'items'),
    approval_reviewer
  );

  for item in select value from jsonb_array_elements(proposal -> 'items') loop
    batch_item_id := gen_random_uuid();
    select * into target
    from analysis.row_correction_subject_v3(
      proposal ->> 'season', (item ->> 'source_row_id')::uuid
    );
    current_value := case item ->> 'field_name'
      when 'eligibility' then target.eligibility_value
      when 'days_injured' then target.days_injured_value
      when 'body_location_code' then target.body_location_value
      when 'injury_type_code' then target.injury_type_value
      when 'diagnosis_code' then target.diagnosis_value
    end;
    insert into audit.correction_batch_items_v3 (
      id, batch_id, item_index, season, source_row_id, field_name,
      old_value, new_value, reason, evidence_sha256, operator, reviewer,
      rule_version, proposal_hash, supersedes_correction_id
    ) values (
      batch_item_id, batch_id, item_index, proposal ->> 'season',
      (item ->> 'source_row_id')::uuid, item ->> 'field_name',
      current_value, item -> 'new_value', item ->> 'reason',
      item ->> 'evidence_sha256', proposal ->> 'operator',
      approval_reviewer, item ->> 'rule_version', expected_proposal_hash,
      nullif(item ->> 'supersedes_correction_id', '')::uuid
    );
    insert into audit.record_events (
      step_run_id, source_row_id, field_name, old_value, new_value,
      action, reason_code, rationale, rule_version, review_status
    ) values (
      apply_step_id, (item ->> 'source_row_id')::uuid,
      item ->> 'field_name', current_value, item -> 'new_value',
      'row_correction_batch', 'row_correction_batch_applied',
      item ->> 'reason', item ->> 'rule_version', 'approved'
    );
    item_index := item_index + 1;
  end loop;

  if audit.row_correction_set_hash_v3(proposal ->> 'season', null)
      is distinct from proposal ->> 'correction_set_hash_after' then
    raise exception 'applied correction batch does not match the reviewed set hash';
  end if;

  insert into processing.correction_batch_versions_v3 (
    batch_item_id, source_row_id, field_name,
    effective_value_before, effective_value_after,
    input_row_fingerprint, output_row_fingerprint,
    input_hash, output_hash, step_run_id
  )
  select item.id, item.source_row_id, item.field_name,
    item.old_value, item.new_value,
    proposal_item ->> 'row_fingerprint', corrected.row_fingerprint,
    expected_proposal_hash, proposal ->> 'correction_set_hash_after',
    apply_step_id
  from audit.correction_batch_items_v3 item
  cross join lateral (
    select value as proposal_item
    from jsonb_array_elements(proposal -> 'items')
    where value ->> 'source_row_id' = item.source_row_id::text
      and value ->> 'field_name' = item.field_name
  ) proposal_match
  cross join lateral analysis.row_correction_subject_v3(
    item.season, item.source_row_id
  ) corrected
  where item.batch_id = batch_id;

  perform set_config('urc.row_correction_batch_v3', '', true);
  insert into audit.step_runs (
    id, pipeline_run_id, step_name, step_version, reason_code,
    input_count, output_count, counts_by_team, input_hash, output_hash
  ) values (
    draft_step_id, run_id, 'recompute_row_correction_batch_draft',
    'row_correction_batch_candidate_2026-08-03_v3',
    'row_correction_batch_draft',
    jsonb_array_length(proposal -> 'items'), 17,
    jsonb_build_object(proposal ->> 'team_key', 1),
    proposal ->> 'correction_set_hash_after',
    proposal ->> 'affected_league_after_sha256'
  );

  insert into processing.correction_drafts_v1 (
    id, correction_set_id, predecessor_bundle_id,
    predecessor_bundle_sha256, affected_team_key,
    affected_team_before_sha256, affected_team_after_sha256,
    affected_league_before_sha256, affected_league_after_sha256,
    affected_team_after_payload, affected_league_after_payload,
    unchanged_team_hashes, draft_bundle_sha256,
    proposal_hash, correction_set_hash, metric_change_detected, step_run_id
  ) values (
    draft_id, set_id, current_bundle_id, current_bundle_sha256,
    proposal ->> 'team_key',
    proposal ->> 'affected_team_before_sha256',
    proposal ->> 'affected_team_after_sha256',
    proposal ->> 'affected_league_before_sha256',
    proposal ->> 'affected_league_after_sha256',
    preview_row.affected_team_after, preview_row.affected_league_after,
    preview_row.unchanged_team_hashes, preview_row.draft_bundle_sha256,
    expected_proposal_hash, proposal ->> 'correction_set_hash_after',
    proposal ->> 'affected_team_before_sha256' is distinct from
      proposal ->> 'affected_team_after_sha256'
      or proposal ->> 'affected_league_before_sha256' is distinct from
        proposal ->> 'affected_league_after_sha256',
    draft_step_id
  );

  update audit.step_runs set ended_at = now()
  where id in (apply_step_id, draft_step_id);
  update audit.pipeline_runs
  set status = 'succeeded', ended_at = now(),
    output_hash = preview_row.draft_bundle_sha256
  where id = run_id;

  return jsonb_build_object(
    'correction_set_id', set_id,
    'batch_id', batch_id,
    'item_count', jsonb_array_length(proposal -> 'items'),
    'proposal_hash', expected_proposal_hash,
    'correction_set_hash', proposal ->> 'correction_set_hash_after',
    'draft_bundle_sha256', preview_row.draft_bundle_sha256,
    'metric_change_detected',
      proposal ->> 'affected_team_before_sha256' is distinct from
        proposal ->> 'affected_team_after_sha256'
      or proposal ->> 'affected_league_before_sha256' is distinct from
        proposal ->> 'affected_league_after_sha256'
  );
end;
$$;

revoke execute on function audit.apply_row_correction_batch_v3(jsonb, jsonb, text)
  from public, anon, authenticated, web_reader;

do $$
declare
  definition text;
begin
  definition := pg_get_functiondef(
    'reporting.promote_row_correction_v2(text,text,text)'::regprocedure
  );
  definition := replace(definition,
    'promote_row_correction_v2', 'promote_row_correction_batch_v3');
  definition := replace(definition,
    'analysis.row_correction_pending_candidate_data_v2(',
    'analysis.row_correction_pending_candidate_data_v3(');
  definition := replace(definition,
    '20260727010000_dynamic_row_correction_pipeline_hardening.sql',
    '20260803153728_dynamic_row_correction_batch_v3.sql');
  definition := replace(definition,
    'row_correction_release_2026-07-27_v2',
    'row_correction_batch_release_2026-08-03_v3');
  definition := replace(definition,
    '''correction-release''', '''correction-batch-release''');
  definition := replace(definition,
    '''row_correction_release''', '''row_correction_batch_release''');
  execute definition;
end;
$$;

revoke execute on function
  reporting.promote_row_correction_batch_v3(text, text, text)
from public, anon, authenticated, web_reader;

create function analysis.assert_legacy_row_correction_v2_available()
returns void
language plpgsql
stable
set search_path = pg_catalog
as $$
begin
  raise exception
    'single-row correction V2 is disabled after batch V3 installation; use a one-item V3 batch';
end;
$$;

revoke execute on function analysis.assert_legacy_row_correction_v2_available()
  from public, anon, authenticated, web_reader;

create view reporting.latest_dashboard_cache_token_v1
with (security_invoker = false, security_barrier = true) as
select bundle.season,
  encode(extensions.digest(
    convert_to(bundle.release_id::text, 'UTF8'), 'sha256'
  ), 'hex') as cache_token
from reporting.latest_approved_dashboard_bundle_v4 bundle;

grant select on reporting.latest_dashboard_cache_token_v1 to web_reader;

revoke all on
  analysis.row_correction_active_values_v3,
  analysis.row_correction_effective_values_v3,
  analysis.row_correction_reporting_classification_origin_v3,
  analysis.row_correction_target_keys_v3,
  analysis.row_correction_target_teams_v3,
  analysis.row_correction_pending_context_v3,
  analysis.row_correction_incremental_context_v3,
  analysis.row_correction_team_payload_candidates_incremental_v3,
  analysis.row_correction_league_dashboard_payload_incremental_v3,
  analysis.team_dashboard_release_candidates_correction_v3,
  analysis.league_dashboard_release_candidates_correction_v3
from public, anon, authenticated, web_reader;

do $$
begin
  if pg_get_functiondef(
      'analysis.row_correction_subject_v3(text,uuid)'::regprocedure
    ) not like '%analysis.row_correction_active_values_v3%'
    or pg_get_functiondef(
      'analysis.row_correction_subject_v3(text,uuid)'::regprocedure
    ) like '%analysis.row_correction_active_values_v1%'
    or pg_get_viewdef(
      'analysis.row_correction_effective_subjects_v3'::regclass, true
    ) not like '%analysis.row_correction_effective_values_v3%'
    or pg_get_viewdef(
      'analysis.row_correction_effective_subjects_v3'::regclass, true
    ) not like '%analysis.row_correction_subject_v3%'
    or pg_get_viewdef(
      'analysis.row_correction_reporting_classification_v3'::regclass, true
    ) not like '%analysis.row_correction_effective_injury_cohort_v3%'
    or pg_get_functiondef(
      'analysis.row_correction_team_dashboard_payload_data_v3_internal()'::regprocedure
    ) not like '%analysis.row_correction_target_teams_v3%'
    or pg_get_functiondef(
      'analysis.row_correction_team_dashboard_payload_data_v3_internal()'::regprocedure
    ) not like '%analysis.row_correction_reporting_classification_origin_v3%'
    or pg_get_functiondef(
      'analysis.row_correction_team_dashboard_payload_data_v3_internal()'::regprocedure
    ) like '%analysis.row_correction_target_teams_v2%'
    or pg_get_viewdef(
      'analysis.row_correction_incremental_context_v3'::regclass, true
    ) not like '%analysis.row_correction_target_teams_v3%'
    or pg_get_viewdef(
      'analysis.row_correction_team_payload_candidates_incremental_v3'::regclass,
      true
    ) not like
      '%analysis.row_correction_team_dashboard_payload_data_v3_internal()%'
    or pg_get_viewdef(
      'analysis.row_correction_league_dashboard_payload_incremental_v3'::regclass,
      true
    ) not like
      '%analysis.row_correction_team_payload_candidates_incremental_v3%'
    or pg_get_functiondef(
      'analysis.row_correction_pending_candidate_data_v3(text)'::regprocedure
    ) not like '%analysis.row_correction_pending_context_v3%'
    or pg_get_functiondef(
      'analysis.row_correction_pending_candidate_data_v3(text)'::regprocedure
    ) not like '%team_dashboard_release_candidates_correction_v3%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_batch_v3(text,text,text)'::regprocedure
    ) not like '%analysis.row_correction_pending_candidate_data_v3(%'
    or pg_get_functiondef(
      'reporting.promote_row_correction_batch_v3(text,text,text)'::regprocedure
    ) not like '%20260803153728_dynamic_row_correction_batch_v3.sql%'
    or to_regprocedure(
      'audit.apply_row_correction_batch_v3(jsonb,jsonb,text)'
    ) is null
    or to_regprocedure(
      'analysis.assert_legacy_row_correction_v2_available()'
    ) is null
    or to_regclass('reporting.latest_dashboard_cache_token_v1') is null
    or not has_table_privilege(
      'web_reader', 'reporting.latest_dashboard_cache_token_v1', 'SELECT'
    )
    or has_function_privilege(
      'web_reader',
      'audit.apply_row_correction_batch_v3(jsonb,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'row-correction batch V3 dependency graph was not rewired exactly';
  end if;

  if exists (select 1 from audit.correction_batches_v3)
    or exists (select 1 from audit.correction_batch_items_v3)
    or exists (select 1 from processing.correction_batch_versions_v3) then
    raise exception 'row-correction batch installation must be data-neutral';
  end if;
  if exists (
    select 1 from audit.correction_sets_v1 correction_set
    where not exists (
      select 1 from reporting.correction_release_context_v1 released
      where released.correction_set_id = correction_set.id
    )
  ) then
    raise exception
      'row-correction batch installation requires no pending legacy correction';
  end if;
  if exists (
    select season
    from reporting.latest_approved_dashboard_bundle_v4 bundle
    where (select count(*)
      from reporting.dashboard_bundle_team_payloads_v1 payload
      where payload.bundle_release_id = bundle.release_id) <> 16
  ) then
    raise exception 'row-correction batch V3 requires complete 16-team predecessors';
  end if;
end;
$$;
