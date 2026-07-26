-- Dynamic, audited row corrections for immutable reporting bundles.
--
-- This migration is additive. It does not mutate ingestion.source_rows,
-- processing.record_versions, curated rows, the frozen V1 analysis family,
-- V5 materialised snapshots, or the reporting reader selection. Corrections
-- are append-only overlays. Only a separately approved correction bundle can
-- become visible, and every unaffected team payload is copied byte-for-byte
-- from its retained predecessor.
-- Original source values and clinical source evidence remain preserved. The
-- overlay stores only typed effective decisions and their evidence bindings.

insert into audit.reason_codes (code, description) values
  (
    'row_correction_applied',
    'An exact, evidence-backed correction was appended for an existing source '
    'row after optimistic-concurrency, old-value and source-fingerprint checks.'
  ),
  (
    'row_correction_draft',
    'The affected team and pooled league correction candidates were recomputed '
    'from versioned SQL; unaffected team payload hashes were retained exactly.'
  ),
  (
    'row_correction_release',
    'A reviewed correction draft was promoted as a new immutable league bundle.'
  ),
  (
    'row_correction_rollback',
    'The exact retained predecessor bundle was restored without deleting the '
    'correction bundle or its audit evidence.'
  )
on conflict (code) do nothing;

create table audit.correction_sets_v1 (
  id uuid primary key default gen_random_uuid(),
  season text not null,
  proposal_hash text not null unique
    check (proposal_hash ~ '^[0-9a-f]{64}$'),
  source_row_id uuid not null references ingestion.source_rows(id),
  team_key text not null references reporting.teams(team_key),
  base_bundle_id uuid not null references reporting.aggregate_releases(id),
  base_bundle_sha256 text not null
    check (base_bundle_sha256 ~ '^[0-9a-f]{64}$'),
  correction_set_hash_before text not null
    check (correction_set_hash_before ~ '^[0-9a-f]{64}$'),
  correction_set_hash_after text not null
    check (correction_set_hash_after ~ '^[0-9a-f]{64}$'),
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  row_fingerprint text not null check (row_fingerprint ~ '^[0-9a-f]{64}$'),
  field_name text not null check (
    field_name in (
      'eligibility', 'days_injured', 'body_location_code',
      'injury_type_code', 'diagnosis_code'
    )
  ),
  old_value jsonb,
  new_value jsonb,
  reason text not null check (btrim(reason) <> ''),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  operator text not null check (btrim(operator) <> ''),
  reviewer text not null check (btrim(reviewer) <> ''),
  rule_version text not null check (btrim(rule_version) <> ''),
  code_version text not null check (btrim(code_version) <> ''),
  dependency_lock_hash text not null
    check (dependency_lock_hash ~ '^[0-9a-f]{64}$'),
  migration_sha256 text not null
    check (migration_sha256 ~ '^[0-9a-f]{64}$'),
  supersedes_correction_id uuid,
  apply_pipeline_run_id uuid not null references audit.pipeline_runs(id),
  applied_at timestamptz not null default now()
);

create table audit.row_corrections_v1 (
  id uuid primary key default gen_random_uuid(),
  correction_set_id uuid not null unique
    references audit.correction_sets_v1(id),
  season text not null,
  source_row_id uuid not null references ingestion.source_rows(id),
  field_name text not null check (
    field_name in (
      'eligibility', 'days_injured', 'body_location_code',
      'injury_type_code', 'diagnosis_code'
    )
  ),
  old_value jsonb,
  new_value jsonb,
  reason text not null,
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  operator text not null,
  reviewer text not null,
  rule_version text not null,
  proposal_hash text not null check (proposal_hash ~ '^[0-9a-f]{64}$'),
  supersedes_correction_id uuid
    references audit.row_corrections_v1(id),
  created_at timestamptz not null default now(),
  unique (source_row_id, field_name, supersedes_correction_id),
  check (supersedes_correction_id is null or supersedes_correction_id <> id)
);

alter table audit.correction_sets_v1
  add constraint correction_sets_v1_supersedes_fk
  foreign key (supersedes_correction_id)
  references audit.row_corrections_v1(id);

create unique index row_corrections_v1_single_root
  on audit.row_corrections_v1 (source_row_id, field_name)
  where supersedes_correction_id is null;
create unique index row_corrections_v1_single_successor
  on audit.row_corrections_v1 (supersedes_correction_id)
  where supersedes_correction_id is not null;

create table processing.correction_versions_v1 (
  id uuid primary key default gen_random_uuid(),
  correction_set_id uuid not null unique
    references audit.correction_sets_v1(id),
  source_row_id uuid not null references ingestion.source_rows(id),
  field_name text not null,
  effective_value_before jsonb,
  effective_value_after jsonb,
  input_row_fingerprint text not null
    check (input_row_fingerprint ~ '^[0-9a-f]{64}$'),
  output_row_fingerprint text not null
    check (output_row_fingerprint ~ '^[0-9a-f]{64}$'),
  input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
  output_hash text not null check (output_hash ~ '^[0-9a-f]{64}$'),
  step_run_id uuid not null references audit.step_runs(id),
  created_at timestamptz not null default now()
);

create table processing.correction_drafts_v1 (
  id uuid primary key default gen_random_uuid(),
  correction_set_id uuid not null unique
    references audit.correction_sets_v1(id),
  predecessor_bundle_id uuid not null references reporting.aggregate_releases(id),
  predecessor_bundle_sha256 text not null
    check (predecessor_bundle_sha256 ~ '^[0-9a-f]{64}$'),
  affected_team_key text not null references reporting.teams(team_key),
  affected_team_before_sha256 text not null
    check (affected_team_before_sha256 ~ '^[0-9a-f]{64}$'),
  affected_team_after_sha256 text not null
    check (affected_team_after_sha256 ~ '^[0-9a-f]{64}$'),
  affected_league_before_sha256 text not null
    check (affected_league_before_sha256 ~ '^[0-9a-f]{64}$'),
  affected_league_after_sha256 text not null
    check (affected_league_after_sha256 ~ '^[0-9a-f]{64}$'),
  affected_team_after_payload jsonb not null,
  affected_league_after_payload jsonb not null,
  unchanged_team_hashes jsonb not null
    check (jsonb_typeof(unchanged_team_hashes) = 'array'),
  draft_bundle_sha256 text not null
    check (draft_bundle_sha256 ~ '^[0-9a-f]{64}$'),
  proposal_hash text not null unique check (proposal_hash ~ '^[0-9a-f]{64}$'),
  correction_set_hash text not null
    check (correction_set_hash ~ '^[0-9a-f]{64}$'),
  metric_change_detected boolean not null,
  step_run_id uuid not null references audit.step_runs(id),
  created_at timestamptz not null default now()
);

create table reporting.correction_release_context_v1 (
  bundle_release_id uuid primary key
    references reporting.aggregate_releases(id),
  correction_set_id uuid not null unique
    references audit.correction_sets_v1(id),
  correction_draft_id uuid not null unique
    references processing.correction_drafts_v1(id),
  predecessor_bundle_id uuid not null references reporting.aggregate_releases(id),
  season text not null,
  analysis_version text not null,
  generated_at timestamptz not null,
  expected_member_count integer not null check (expected_member_count = 16),
  match_exposure_decision text not null,
  decision_reviewer text not null,
  decision_recorded_at date not null,
  classification_view_version text not null,
  classification_evidence_sha256 text
    check (
      classification_evidence_sha256 is null
      or classification_evidence_sha256 ~ '^[0-9a-f]{64}$'
    ),
  cohort_view_version text not null,
  cohort_evidence_sha256 text
    check (
      cohort_evidence_sha256 is null
      or cohort_evidence_sha256 ~ '^[0-9a-f]{64}$'
    ),
  affected_team_key text not null references reporting.teams(team_key),
  proposal_hash text not null unique check (proposal_hash ~ '^[0-9a-f]{64}$'),
  correction_set_hash text not null
    check (correction_set_hash ~ '^[0-9a-f]{64}$'),
  reviewer text not null check (btrim(reviewer) <> ''),
  promoted_at timestamptz not null default now()
);

create table reporting.correction_rollback_context_v1 (
  bundle_release_id uuid primary key
    references reporting.aggregate_releases(id),
  rolled_back_release_id uuid not null
    references reporting.aggregate_releases(id),
  restored_bundle_id uuid not null
    references reporting.aggregate_releases(id),
  season text not null,
  analysis_version text not null,
  generated_at timestamptz not null,
  expected_member_count integer not null check (expected_member_count = 16),
  match_exposure_decision text not null,
  decision_reviewer text not null,
  decision_recorded_at date not null,
  classification_view_version text not null,
  classification_evidence_sha256 text
    check (
      classification_evidence_sha256 is null
      or classification_evidence_sha256 ~ '^[0-9a-f]{64}$'
    ),
  cohort_view_version text not null,
  cohort_evidence_sha256 text
    check (
      cohort_evidence_sha256 is null
      or cohort_evidence_sha256 ~ '^[0-9a-f]{64}$'
    ),
  reason text not null check (btrim(reason) <> ''),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  operator text not null check (btrim(operator) <> ''),
  reviewer text not null check (btrim(reviewer) <> ''),
  code_version text not null check (btrim(code_version) <> ''),
  dependency_lock_hash text not null
    check (dependency_lock_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  check (bundle_release_id <> rolled_back_release_id),
  check (bundle_release_id <> restored_bundle_id)
);

create table reporting.correction_league_payloads_v1 (
  bundle_release_id uuid primary key
    references reporting.aggregate_releases(id),
  dashboard_payload jsonb not null
    check (jsonb_typeof(dashboard_payload) = 'object'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create table reporting.correction_team_payloads_v1 (
  bundle_release_id uuid not null references reporting.aggregate_releases(id),
  team_key text not null references reporting.teams(team_key),
  team_release_id uuid not null references reporting.aggregate_releases(id),
  curated_build_id uuid not null references curated.builds(id),
  dashboard_payload jsonb not null
    check (jsonb_typeof(dashboard_payload) = 'object'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (bundle_release_id, team_key),
  unique (bundle_release_id, team_release_id),
  unique (bundle_release_id, curated_build_id)
);

alter table audit.correction_sets_v1 enable row level security;
alter table audit.row_corrections_v1 enable row level security;
alter table processing.correction_versions_v1 enable row level security;
alter table processing.correction_drafts_v1 enable row level security;
alter table reporting.correction_release_context_v1 enable row level security;
alter table reporting.correction_rollback_context_v1 enable row level security;
alter table reporting.correction_league_payloads_v1 enable row level security;
alter table reporting.correction_team_payloads_v1 enable row level security;

revoke all on audit.correction_sets_v1 from public, anon, authenticated;
revoke all on audit.row_corrections_v1 from public, anon, authenticated;
revoke all on processing.correction_versions_v1 from public, anon, authenticated;
revoke all on processing.correction_drafts_v1 from public, anon, authenticated;
revoke all on reporting.correction_release_context_v1
  from public, anon, authenticated;
revoke all on reporting.correction_rollback_context_v1
  from public, anon, authenticated;
revoke all on reporting.correction_league_payloads_v1
  from public, anon, authenticated;
revoke all on reporting.correction_team_payloads_v1
  from public, anon, authenticated;

create function audit.reject_row_correction_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception
    'row-correction history is append-only; append a successor or rollback event';
end;
$$;

revoke execute on function audit.reject_row_correction_history_mutation_v1()
  from public, anon, authenticated;

create trigger correction_sets_v1_append_only
before update or delete on audit.correction_sets_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger row_corrections_v1_append_only
before update or delete on audit.row_corrections_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_versions_v1_append_only
before update or delete on processing.correction_versions_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_drafts_v1_append_only
before update or delete on processing.correction_drafts_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_release_context_v1_append_only
before update or delete on reporting.correction_release_context_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_rollback_context_v1_append_only
before update or delete on reporting.correction_rollback_context_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_league_payloads_v1_append_only
before update or delete on reporting.correction_league_payloads_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();
create trigger correction_team_payloads_v1_append_only
before update or delete on reporting.correction_team_payloads_v1
for each row execute function audit.reject_row_correction_history_mutation_v1();

create function reporting.guard_dynamic_context_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, audit, processing, reporting
as $$
declare
  release_status text;
begin
  select release.status into release_status
  from reporting.aggregate_releases release
  where release.id = new.bundle_release_id;
  if release_status is distinct from 'draft' then
    raise exception
      'dynamic bundle context requires an existing draft aggregate release';
  end if;

  if exists (
    select 1
    from reporting.league_release_context_v2 frozen
    where frozen.release_id = new.bundle_release_id
  )
    or exists (
      select 1
      from reporting.correction_release_context_v1 correction
      where correction.bundle_release_id = new.bundle_release_id
    )
    or exists (
      select 1
      from reporting.correction_rollback_context_v1 rollback
      where rollback.bundle_release_id = new.bundle_release_id
    ) then
    raise exception
      'aggregate release already has an immutable bundle context';
  end if;

  if tg_table_name = 'correction_release_context_v1' then
    if not exists (
      select 1
      from audit.correction_sets_v1 correction_set
      join processing.correction_drafts_v1 draft
        on draft.id = new.correction_draft_id
       and draft.correction_set_id = correction_set.id
       and draft.predecessor_bundle_id = new.predecessor_bundle_id
       and draft.affected_team_key = new.affected_team_key
       and draft.proposal_hash = new.proposal_hash
       and draft.correction_set_hash = new.correction_set_hash
      where correction_set.id = new.correction_set_id
        and correction_set.season = new.season
        and correction_set.team_key = new.affected_team_key
        and correction_set.proposal_hash = new.proposal_hash
        and correction_set.correction_set_hash_after =
          new.correction_set_hash
        and correction_set.base_bundle_id = new.predecessor_bundle_id
    ) then
      raise exception
        'correction context does not match its audited set and draft';
    end if;
  elsif tg_table_name = 'correction_rollback_context_v1' then
    if not exists (
      select 1
      from reporting.aggregate_releases rolled_back
      where rolled_back.id = new.rolled_back_release_id
        and rolled_back.status = 'approved'
        and (
          exists (
            select 1
            from reporting.league_release_context_v2 restored
            where restored.release_id = new.restored_bundle_id
              and restored.season = new.season
          )
          or exists (
            select 1
            from reporting.correction_release_context_v1 restored
            where restored.bundle_release_id = new.restored_bundle_id
              and restored.season = new.season
          )
          or exists (
            select 1
            from reporting.correction_rollback_context_v1 restored
            where restored.bundle_release_id = new.restored_bundle_id
              and restored.season = new.season
          )
        )
    ) then
      raise exception
        'rollback context requires an approved target and retained predecessor';
    end if;
  else
    raise exception 'unsupported dynamic bundle context';
  end if;
  return new;
end;
$$;

revoke execute on function reporting.guard_dynamic_context_insert_v1()
  from public, anon, authenticated;
create trigger correction_release_context_v1_insert_guard
before insert on reporting.correction_release_context_v1
for each row execute function reporting.guard_dynamic_context_insert_v1();
create trigger correction_rollback_context_v1_insert_guard
before insert on reporting.correction_rollback_context_v1
for each row execute function reporting.guard_dynamic_context_insert_v1();

create function reporting.set_correction_payload_hash_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  new.payload_sha256 := encode(extensions.digest(
    convert_to(new.dashboard_payload::text, 'UTF8'), 'sha256'
  ), 'hex');
  return new;
end;
$$;

revoke execute on function reporting.set_correction_payload_hash_v1()
  from public, anon, authenticated;
create trigger correction_league_payloads_v1_hash
before insert on reporting.correction_league_payloads_v1
for each row execute function reporting.set_correction_payload_hash_v1();
create trigger correction_team_payloads_v1_hash
before insert on reporting.correction_team_payloads_v1
for each row execute function reporting.set_correction_payload_hash_v1();

create function analysis.row_correction_current_preview_v1()
returns jsonb
language sql
volatile
set search_path = pg_catalog
as $$
  select case
    when nullif(current_setting('urc.row_correction_preview', true), '') is null
      then null
    else current_setting('urc.row_correction_preview', true)::jsonb
  end;
$$;

revoke execute on function analysis.row_correction_current_preview_v1()
  from public;

create view reporting.dashboard_bundle_context_v1
with (security_invoker = false, security_barrier = true) as
select
  context.release_id,
  context.season,
  context.analysis_version,
  context.generated_at,
  context.expected_member_count,
  context.match_exposure_decision,
  context.decision_reviewer,
  context.decision_recorded_at,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256
from reporting.league_release_context_v2 context
union all
select
  context.bundle_release_id,
  context.season,
  context.analysis_version,
  context.generated_at,
  context.expected_member_count,
  context.match_exposure_decision,
  context.decision_reviewer,
  context.decision_recorded_at,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256
from reporting.correction_release_context_v1 context
union all
select
  context.bundle_release_id,
  context.season,
  context.analysis_version,
  context.generated_at,
  context.expected_member_count,
  context.match_exposure_decision,
  context.decision_reviewer,
  context.decision_recorded_at,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256
from reporting.correction_rollback_context_v1 context;

create view reporting.dashboard_bundle_league_payloads_v1
with (security_invoker = false, security_barrier = true) as
select
  payload.release_id,
  payload.dashboard_payload,
  payload.payload_sha256
from reporting.league_release_payloads_v2 payload
union all
select
  payload.bundle_release_id,
  payload.dashboard_payload,
  payload.payload_sha256
from reporting.correction_league_payloads_v1 payload;

create view reporting.dashboard_bundle_team_payloads_v1
with (security_invoker = false, security_barrier = true) as
select
  payload.bundle_release_id,
  payload.team_key,
  payload.team_release_id,
  payload.curated_build_id,
  payload.dashboard_payload,
  payload.payload_sha256
from reporting.team_dashboard_payloads_v2 payload
union all
select
  payload.bundle_release_id,
  payload.team_key,
  payload.team_release_id,
  payload.curated_build_id,
  payload.dashboard_payload,
  payload.payload_sha256
from reporting.correction_team_payloads_v1 payload;

revoke all on reporting.dashboard_bundle_context_v1
  from public, anon, authenticated, web_reader;
revoke all on reporting.dashboard_bundle_league_payloads_v1
  from public, anon, authenticated, web_reader;
revoke all on reporting.dashboard_bundle_team_payloads_v1
  from public, anon, authenticated, web_reader;

create view reporting.latest_approved_dashboard_bundle_v4
with (security_invoker = false, security_barrier = true) as
with eligible as (
  select
    bundle.release_id,
    bundle.season,
    release.approved_at,
    release.created_at
  from reporting.latest_approved_dashboard_bundle_v2 bundle
  join reporting.aggregate_releases release
    on release.id = bundle.release_id
  union all
  select
    context.release_id,
    context.season,
    release.approved_at,
    release.created_at
  from reporting.dashboard_bundle_context_v1 context
  join reporting.aggregate_releases release
    on release.id = context.release_id
   and release.status = 'approved'
  where (
    exists (
      select 1
      from reporting.correction_release_context_v1 correction
      where correction.bundle_release_id = context.release_id
    )
    or exists (
      select 1
      from reporting.correction_rollback_context_v1 rollback
      where rollback.bundle_release_id = context.release_id
    )
  )
    and exists (
      select 1
      from reporting.correction_league_payloads_v1 league
      where league.bundle_release_id = context.release_id
    )
    and (
      select count(*)
      from reporting.correction_team_payloads_v1 team
      where team.bundle_release_id = context.release_id
    ) = 16
    and not exists (
      select 1
      from reporting.teams roster
      where not exists (
        select 1
        from reporting.correction_team_payloads_v1 team
        where team.bundle_release_id = context.release_id
          and team.team_key = roster.team_key
      )
    )
), ranked as (
  select eligible.*,
    row_number() over (
      partition by eligible.season
      order by eligible.approved_at desc nulls last,
        eligible.created_at desc, eligible.release_id desc
    ) as rank
  from eligible
)
select ranked.release_id, ranked.season
from ranked
where ranked.rank = 1;

revoke all on reporting.latest_approved_dashboard_bundle_v4
  from public, anon, authenticated, web_reader;

create view analysis.row_correction_member_releases_v1
with (security_invoker = true) as
select
  member.team_key,
  context.season,
  member.team_release_id,
  member.curated_build_id,
  context.generated_at,
  bundle.release_id as predecessor_bundle_id,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256
from reporting.latest_approved_dashboard_bundle_v4 bundle
join reporting.dashboard_bundle_context_v1 context
  on context.release_id = bundle.release_id
join reporting.dashboard_bundle_team_payloads_v1 member
  on member.bundle_release_id = bundle.release_id;

create view analysis.row_correction_cohort_rules_v1
with (security_invoker = true) as
select distinct
  cohort_view_version,
  season,
  cohort_evidence_sha256
from analysis.row_correction_member_releases_v1;

create view analysis.row_correction_base_injury_cohort_v1
with (security_invoker = true) as
select cohort.*
from analysis.row_correction_member_releases_v1 member
cross join lateral (
  select v5.*
  from analysis.analysis_window_injury_cohort_v5_snapshot v5
  where member.cohort_view_version =
      'analysis_window_2024-25_2026-07-25_v1'
    and v5.cohort_view_version = member.cohort_view_version
    and v5.curated_build_id = member.curated_build_id
    and v5.team_key = member.team_key
    and v5.season = member.season
  union all
  select
    later.injury_id,
    later.curated_build_id,
    later.team_key,
    later.season,
    injury.source_row_id,
    null::integer as source_row,
    later.date_injured,
    later.days_lost::numeric,
    later.is_time_loss,
    later.setting_code,
    later.body_location_code,
    later.body_location_label,
    later.injury_type_code,
    later.injury_type_label,
    later.severity_code,
    later.severity_label,
    later.is_undated,
    member.cohort_view_version
  from analysis.injury_cohort_by_build_season_bound_v3 later
  join curated.injuries injury on injury.id = later.injury_id
  where member.cohort_view_version <>
      'analysis_window_2024-25_2026-07-25_v1'
    and later.curated_build_id = member.curated_build_id
    and later.team_key = member.team_key
    and later.season = member.season
) cohort;

create view analysis.row_correction_base_classification_v1
with (security_invoker = true) as
select classification.*
from analysis.row_correction_member_releases_v1 member
cross join lateral (
  select v5.*
  from analysis.analysis_window_reporting_classification_v5_snapshot v5
  where member.cohort_view_version =
      'analysis_window_2024-25_2026-07-25_v1'
    and v5.curated_build_id = member.curated_build_id
    and v5.team_key = member.team_key
    and v5.season = member.season
  union all
  select later.*
  from analysis.season_bound_reporting_classification_v4 later
  where member.cohort_view_version <>
      'analysis_window_2024-25_2026-07-25_v1'
    and later.curated_build_id = member.curated_build_id
    and later.team_key = member.team_key
    and later.season = member.season
) classification;

create view analysis.row_correction_served_sets_v1
with (security_invoker = true) as
with recursive bundle_lineage as (
  select
    bundle.season,
    bundle.release_id,
    array[bundle.release_id]::uuid[] as visited
  from reporting.latest_approved_dashboard_bundle_v4 bundle
  union all
  select
    lineage.season,
    coalesce(
      correction.predecessor_bundle_id,
      rollback.restored_bundle_id
    ) as release_id,
    lineage.visited || coalesce(
      correction.predecessor_bundle_id,
      rollback.restored_bundle_id
    )
  from bundle_lineage lineage
  left join reporting.correction_release_context_v1 correction
    on correction.bundle_release_id = lineage.release_id
  left join reporting.correction_rollback_context_v1 rollback
    on rollback.bundle_release_id = lineage.release_id
  where coalesce(
    correction.predecessor_bundle_id,
    rollback.restored_bundle_id
  ) is not null
    and not coalesce(
      correction.predecessor_bundle_id,
      rollback.restored_bundle_id
    ) = any(lineage.visited)
)
select
  lineage.season,
  correction.correction_set_id,
  correction.bundle_release_id
from bundle_lineage lineage
join reporting.correction_release_context_v1 correction
  on correction.bundle_release_id = lineage.release_id;

create view analysis.row_correction_active_values_v1
with (security_invoker = true) as
with eligible_sets as (
  select served.correction_set_id
  from analysis.row_correction_served_sets_v1 served
  union
  select correction_set.id
  from audit.correction_sets_v1 correction_set
  where (
    not exists (
      select 1
      from reporting.correction_release_context_v1 released
      where released.correction_set_id = correction_set.id
    )
    or exists (
      select 1
      from reporting.correction_release_context_v1 released
      join reporting.aggregate_releases release
        on release.id = released.bundle_release_id
      where released.correction_set_id = correction_set.id
        and release.status = 'draft'
    )
  )
)
select distinct on (correction.season, correction.source_row_id, correction.field_name)
  correction.id as correction_id,
  correction.correction_set_id,
  correction.season,
  correction.source_row_id,
  correction.field_name,
  correction.new_value,
  correction.proposal_hash,
  correction.created_at
from audit.row_corrections_v1 correction
join audit.correction_sets_v1 correction_set
  on correction_set.id = correction.correction_set_id
join eligible_sets eligible
  on eligible.correction_set_id = correction_set.id
order by
  correction.season, correction.source_row_id, correction.field_name,
  correction.created_at desc, correction.id desc;

create view analysis.row_correction_effective_values_v1
with (security_invoker = true) as
with proposed as (
  select
    null::uuid as correction_id,
    null::uuid as correction_set_id,
    preview ->> 'season' as season,
    (preview ->> 'source_row_id')::uuid as source_row_id,
    preview ->> 'field_name' as field_name,
    preview -> 'new_value' as new_value,
    coalesce(preview ->> 'proposal_hash', '') as proposal_hash,
    clock_timestamp() as created_at,
    1 as priority
  from analysis.row_correction_current_preview_v1() preview
  where preview is not null
), active as (
  select active.*, 0 as priority
  from analysis.row_correction_active_values_v1 active
)
select distinct on (season, source_row_id, field_name)
  correction_id, correction_set_id, season, source_row_id, field_name,
  new_value, proposal_hash, created_at
from (
  select * from active
  union all
  select * from proposed
) overlay
order by
  season, source_row_id, field_name, priority desc, created_at desc,
  correction_id desc nulls first;

create function audit.row_correction_set_hash_v1(
  target_season text,
  proposed jsonb default null
)
returns text
language sql
stable
set search_path = pg_catalog, analysis, audit, reporting, processing, public
as $$
with active as (
  select
    active.source_row_id,
    active.field_name,
    active.new_value,
    correction.evidence_sha256,
    correction.rule_version
  from analysis.row_correction_active_values_v1 active
  join audit.row_corrections_v1 correction
    on correction.id = active.correction_id
  where active.season = target_season
    and (
      proposed is null
      or active.source_row_id <> (proposed ->> 'source_row_id')::uuid
      or active.field_name <> proposed ->> 'field_name'
    )
), proposed_row as (
  select
    (proposed ->> 'source_row_id')::uuid as source_row_id,
    proposed ->> 'field_name' as field_name,
    proposed -> 'new_value' as new_value,
    proposed ->> 'evidence_sha256' as evidence_sha256,
    proposed ->> 'rule_version' as rule_version
  where proposed is not null
    and proposed ->> 'season' = target_season
), state as (
  select * from active
  union all
  select * from proposed_row
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

create function analysis.row_correction_proposal_hash_v1(proposal jsonb)
returns text
language sql
immutable
set search_path = pg_catalog, public
as $$
  select encode(extensions.digest(
    convert_to((proposal - 'proposal_hash')::text, 'UTF8'),
    'sha256'
  ), 'hex');
$$;

revoke execute on function audit.row_correction_set_hash_v1(text, jsonb)
  from public;
revoke execute on function analysis.row_correction_proposal_hash_v1(jsonb)
  from public;

create view analysis.row_correction_subjects_v1
with (security_invoker = true) as
with master_final as (
  select
    master.season,
    master.source_row,
    master.team,
    master.excluded,
    master.row_values || coalesce(overrides.final_overrides, '{}'::jsonb)
      as final_values,
    not master.excluded
      and not exists (
        select 1
        from lineage.ledger_entries removal
        where removal.season = master.season
          and removal.source_row = master.source_row
          and removal.is_removal
      ) as ledger_included
  from lineage.master_rows master
  left join lateral (
    select jsonb_object_agg(last_entry.field, coalesce(last_entry.new_value, ''))
      as final_overrides
    from (
      select distinct on (entry.field) entry.field, entry.new_value
      from lineage.ledger_entries entry
      where entry.season = master.season
        and entry.source_row = master.source_row
        and not entry.is_removal
      order by entry.field, entry.step_order desc, entry.entry_index desc
    ) last_entry
  ) overrides on true
), subjects as (
  select
    member.season,
    bridge.source_row,
    injury.source_row_id,
    source.row_sha256 as source_row_sha256,
    injury.team_key,
    injury.id as injury_id,
    injury.curated_build_id,
    coalesce(
      final.final_values,
      jsonb_build_object(
        'Date Injured', coalesce(to_char(injury.date_injured, 'DD/MM/YYYY'), ''),
        'Days Injured', coalesce(injury.days_injured::text, ''),
        'Problem type', coalesce(initcap(injury.problem_type), ''),
        'Occasion category', case injury.activity_context
          when 'urc_match' then 'Match'
          when 'match' then 'Match'
          when 'training' then 'Training'
          else 'Other'
        end
      )
    ) as final_values,
    coalesce(cohort.injury_id is not null, false) as baseline_is_included,
    coalesce(cohort.date_injured, injury.date_injured)
      as baseline_date_injured,
    coalesce(
      cohort.days_lost,
      case
        when trim(coalesce(final.final_values ->> 'Days Injured', ''))
          ~ '^\d+(\.0+)?$'
          then trim(final.final_values ->> 'Days Injured')::numeric
        else injury.days_injured::numeric
      end
    ) as baseline_days_injured,
    coalesce(cohort.setting_code,
      case trim(coalesce(
        final.final_values ->> 'Occasion category',
        injury.activity_context
      ))
        when 'Match' then 'match'
        when 'match' then 'match'
        when 'urc_match' then 'match'
        when 'Training' then 'training'
        when 'training' then 'training'
        else 'unknown'
      end
    ) as setting_code,
    coalesce(classification.effective_body_location_code,
      injury.body_location, 'unknown') as baseline_body_location_code,
    coalesce(classification.effective_injury_type_code,
      injury.injury_type, 'unknown') as baseline_injury_type_code,
    coalesce(classification.diagnosis_code, 'unknown')
      as baseline_diagnosis_code,
    coalesce(final.ledger_included, cohort.injury_id is not null)
      as ledger_included
  from analysis.row_correction_member_releases_v1 member
  join curated.injuries injury
    on injury.season = member.season
   and injury.team_key = member.team_key
   and injury.curated_build_id = member.curated_build_id
  join ingestion.source_rows source
    on source.id = injury.source_row_id
  left join lineage.master_source_bridge bridge
    on bridge.season = member.season
   and bridge.source_row_id = injury.source_row_id
   and bridge.injury_id = injury.id
   and bridge.curated_build_id = injury.curated_build_id
  left join master_final final
    on final.season = bridge.season
   and final.source_row = bridge.source_row
  left join lateral (
    select
      v5.injury_id, v5.date_injured, v5.days_lost, v5.setting_code
    from analysis.analysis_window_injury_cohort_v5_snapshot v5
    where member.cohort_view_version =
        'analysis_window_2024-25_2026-07-25_v1'
      and v5.cohort_view_version = member.cohort_view_version
      and v5.injury_id = injury.id
      and v5.curated_build_id = injury.curated_build_id
      and v5.team_key = injury.team_key
      and v5.season = injury.season
    union all
    select
      later.injury_id, later.date_injured, later.days_lost::numeric,
      later.setting_code
    from analysis.injury_cohort_by_build_season_bound_v3 later
    where member.cohort_view_version <>
        'analysis_window_2024-25_2026-07-25_v1'
      and later.injury_id = injury.id
      and later.curated_build_id = injury.curated_build_id
      and later.team_key = injury.team_key
      and later.season = injury.season
  ) cohort on true
  left join lateral (
    select
      v5.injury_id, v5.effective_body_location_code,
      v5.effective_injury_type_code, v5.diagnosis_code
    from analysis.analysis_window_reporting_classification_v5_snapshot v5
    where member.cohort_view_version =
        'analysis_window_2024-25_2026-07-25_v1'
      and v5.injury_id = injury.id
      and v5.curated_build_id = injury.curated_build_id
      and v5.team_key = injury.team_key
      and v5.season = injury.season
    union all
    select
      later.injury_id, later.effective_body_location_code,
      later.effective_injury_type_code, later.diagnosis_code
    from analysis.season_bound_reporting_classification_v4 later
    where member.cohort_view_version <>
        'analysis_window_2024-25_2026-07-25_v1'
      and later.injury_id = injury.id
      and later.curated_build_id = injury.curated_build_id
      and later.team_key = injury.team_key
      and later.season = injury.season
  ) classification on true
), effective as (
  select subject.*,
    coalesce(
      (select overlay.new_value
       from analysis.row_correction_active_values_v1 overlay
       where overlay.season = subject.season
         and overlay.source_row_id = subject.source_row_id
         and overlay.field_name = 'eligibility'),
      to_jsonb(subject.baseline_is_included)
    ) as eligibility_value,
    coalesce(
      (select overlay.new_value
       from analysis.row_correction_active_values_v1 overlay
       where overlay.season = subject.season
         and overlay.source_row_id = subject.source_row_id
         and overlay.field_name = 'days_injured'),
      to_jsonb(subject.baseline_days_injured),
      'null'::jsonb
    ) as days_injured_value,
    coalesce(
      (select overlay.new_value
       from analysis.row_correction_active_values_v1 overlay
       where overlay.season = subject.season
         and overlay.source_row_id = subject.source_row_id
         and overlay.field_name = 'body_location_code'),
      to_jsonb(subject.baseline_body_location_code)
    ) as body_location_value,
    coalesce(
      (select overlay.new_value
       from analysis.row_correction_active_values_v1 overlay
       where overlay.season = subject.season
         and overlay.source_row_id = subject.source_row_id
         and overlay.field_name = 'injury_type_code'),
      to_jsonb(subject.baseline_injury_type_code)
    ) as injury_type_value,
    coalesce(
      (select overlay.new_value
       from analysis.row_correction_active_values_v1 overlay
       where overlay.season = subject.season
         and overlay.source_row_id = subject.source_row_id
         and overlay.field_name = 'diagnosis_code'),
      to_jsonb(subject.baseline_diagnosis_code)
    ) as diagnosis_value
  from subjects subject
)
select effective.*,
  encode(extensions.digest(convert_to(jsonb_build_object(
    'source_row_id', source_row_id,
    'source_row_sha256', source_row_sha256,
    'eligibility', eligibility_value,
    'days_injured', days_injured_value,
    'body_location_code', body_location_value,
    'injury_type_code', injury_type_value,
    'diagnosis_code', diagnosis_value
  )::text, 'UTF8'), 'sha256'), 'hex') as row_fingerprint
from effective;

create function analysis.row_correction_subject_v1(
  target_season text,
  target_source_row_id uuid
)
returns setof analysis.row_correction_subjects_v1
language sql
stable
set search_path = pg_catalog, analysis, audit, reporting, processing,
  ingestion, curated, lineage
as $$
with subjects as (
  select
    member.season,
    bridge.source_row,
    injury.source_row_id,
    source.row_sha256 as source_row_sha256,
    injury.team_key,
    injury.id as injury_id,
    injury.curated_build_id,
    coalesce(
      final.final_values,
      jsonb_build_object(
        'Date Injured', coalesce(to_char(injury.date_injured, 'DD/MM/YYYY'), ''),
        'Days Injured', coalesce(injury.days_injured::text, ''),
        'Problem type', coalesce(initcap(injury.problem_type), ''),
        'Occasion category', case injury.activity_context
          when 'urc_match' then 'Match'
          when 'match' then 'Match'
          when 'training' then 'Training'
          else 'Other'
        end
      )
    ) as final_values,
    coalesce(cohort.injury_id is not null, false) as baseline_is_included,
    coalesce(cohort.date_injured, injury.date_injured)
      as baseline_date_injured,
    coalesce(
      cohort.days_lost,
      case
        when trim(coalesce(final.final_values ->> 'Days Injured', ''))
          ~ '^\d+(\.0+)?$'
          then trim(final.final_values ->> 'Days Injured')::numeric
        else injury.days_injured::numeric
      end
    ) as baseline_days_injured,
    coalesce(cohort.setting_code,
      case trim(coalesce(
        final.final_values ->> 'Occasion category',
        injury.activity_context
      ))
        when 'Match' then 'match'
        when 'match' then 'match'
        when 'urc_match' then 'match'
        when 'Training' then 'training'
        when 'training' then 'training'
        else 'unknown'
      end
    ) as setting_code,
    coalesce(classification.effective_body_location_code,
      injury.body_location, 'unknown') as baseline_body_location_code,
    coalesce(classification.effective_injury_type_code,
      injury.injury_type, 'unknown') as baseline_injury_type_code,
    coalesce(classification.diagnosis_code, 'unknown')
      as baseline_diagnosis_code,
    coalesce(final.ledger_included, cohort.injury_id is not null)
      as ledger_included
  from ingestion.source_rows source
  join curated.injuries injury
    on injury.source_row_id = source.id
  join analysis.row_correction_member_releases_v1 member
    on member.season = injury.season
   and member.team_key = injury.team_key
   and member.curated_build_id = injury.curated_build_id
  left join lineage.master_source_bridge bridge
    on bridge.season = member.season
   and bridge.source_row_id = injury.source_row_id
   and bridge.injury_id = injury.id
   and bridge.curated_build_id = injury.curated_build_id
  left join lineage.master_rows master
    on master.season = bridge.season
   and master.source_row = bridge.source_row
  left join lateral (
    select
      master.row_values || coalesce(jsonb_object_agg(
        latest.field, coalesce(latest.new_value, '')
      ), '{}'::jsonb) as final_values,
      not master.excluded
        and not exists (
          select 1
          from lineage.ledger_entries removal
          where removal.season = master.season
            and removal.source_row = master.source_row
            and removal.is_removal
        ) as ledger_included
    from (
      select distinct on (entry.field)
        entry.field, entry.new_value
      from lineage.ledger_entries entry
      where entry.season = master.season
        and entry.source_row = master.source_row
        and not entry.is_removal
      order by entry.field, entry.step_order desc, entry.entry_index desc
    ) latest
  ) final on master.source_row is not null
  left join lateral (
    select
      v5.injury_id, v5.date_injured, v5.days_lost, v5.setting_code
    from analysis.analysis_window_injury_cohort_v5_snapshot v5
    where member.cohort_view_version =
        'analysis_window_2024-25_2026-07-25_v1'
      and v5.cohort_view_version = member.cohort_view_version
      and v5.injury_id = injury.id
      and v5.curated_build_id = injury.curated_build_id
      and v5.team_key = injury.team_key
      and v5.season = injury.season
    union all
    select
      later.injury_id, later.date_injured, later.days_lost::numeric,
      later.setting_code
    from analysis.injury_cohort_by_build_season_bound_v3 later
    where member.cohort_view_version <>
        'analysis_window_2024-25_2026-07-25_v1'
      and later.injury_id = injury.id
      and later.curated_build_id = injury.curated_build_id
      and later.team_key = injury.team_key
      and later.season = injury.season
  ) cohort on true
  left join lateral (
    select
      v5.injury_id, v5.effective_body_location_code,
      v5.effective_injury_type_code, v5.diagnosis_code
    from analysis.analysis_window_reporting_classification_v5_snapshot v5
    where member.cohort_view_version =
        'analysis_window_2024-25_2026-07-25_v1'
      and v5.injury_id = injury.id
      and v5.curated_build_id = injury.curated_build_id
      and v5.team_key = injury.team_key
      and v5.season = injury.season
    union all
    select
      later.injury_id, later.effective_body_location_code,
      later.effective_injury_type_code, later.diagnosis_code
    from analysis.season_bound_reporting_classification_v4 later
    where member.cohort_view_version <>
        'analysis_window_2024-25_2026-07-25_v1'
      and later.injury_id = injury.id
      and later.curated_build_id = injury.curated_build_id
      and later.team_key = injury.team_key
      and later.season = injury.season
  ) classification on true
  where source.id = target_source_row_id
    and injury.season = target_season
), effective as (
  select subject.*,
    coalesce(overlays.values_by_field -> 'eligibility',
      to_jsonb(subject.baseline_is_included)
    ) as eligibility_value,
    coalesce(overlays.values_by_field -> 'days_injured',
      to_jsonb(subject.baseline_days_injured),
      'null'::jsonb
    ) as days_injured_value,
    coalesce(overlays.values_by_field -> 'body_location_code',
      to_jsonb(subject.baseline_body_location_code)
    ) as body_location_value,
    coalesce(overlays.values_by_field -> 'injury_type_code',
      to_jsonb(subject.baseline_injury_type_code)
    ) as injury_type_value,
    coalesce(overlays.values_by_field -> 'diagnosis_code',
      to_jsonb(subject.baseline_diagnosis_code)
    ) as diagnosis_value
  from subjects subject
  left join lateral (
    select jsonb_object_agg(overlay.field_name, overlay.new_value)
      as values_by_field
    from analysis.row_correction_active_values_v1 overlay
    where overlay.season = subject.season
      and overlay.source_row_id = subject.source_row_id
  ) overlays on true
)
select effective.*,
  encode(extensions.digest(convert_to(jsonb_build_object(
    'source_row_id', source_row_id,
    'source_row_sha256', source_row_sha256,
    'eligibility', eligibility_value,
    'days_injured', days_injured_value,
    'body_location_code', body_location_value,
    'injury_type_code', injury_type_value,
    'diagnosis_code', diagnosis_value
  )::text, 'UTF8'), 'sha256'), 'hex') as row_fingerprint
from effective;
$$;

revoke execute on function analysis.row_correction_subject_v1(text, uuid)
  from public, anon, authenticated;

create view analysis.row_correction_target_keys_v1
with (security_invoker = true) as
select
  preview ->> 'season' as season,
  subject.team_key,
  (preview ->> 'source_row_id')::uuid as source_row_id
from analysis.row_correction_current_preview_v1() preview
cross join lateral analysis.row_correction_subject_v1(
  preview ->> 'season',
  (preview ->> 'source_row_id')::uuid
) subject
where preview is not null
union
select
  correction_set.season,
  correction_set.team_key,
  correction_set.source_row_id
from audit.correction_sets_v1 correction_set
where (
  not exists (
    select 1
    from reporting.correction_release_context_v1 released
    where released.correction_set_id = correction_set.id
  )
  or exists (
    select 1
    from reporting.correction_release_context_v1 released
    join reporting.aggregate_releases release
      on release.id = released.bundle_release_id
    where released.correction_set_id = correction_set.id
      and release.status = 'draft'
  )
);

create view analysis.row_correction_effective_subjects_v1
with (security_invoker = true) as
select subject.*,
  coalesce(
    (select overlay.new_value
     from analysis.row_correction_effective_values_v1 overlay
     where overlay.season = subject.season
       and overlay.source_row_id = subject.source_row_id
       and overlay.field_name = 'eligibility'),
    subject.eligibility_value
  ) as effective_eligibility_value,
  coalesce(
    (select overlay.new_value
     from analysis.row_correction_effective_values_v1 overlay
     where overlay.season = subject.season
       and overlay.source_row_id = subject.source_row_id
       and overlay.field_name = 'days_injured'),
    subject.days_injured_value
  ) as effective_days_injured_value,
  coalesce(
    (select overlay.new_value
     from analysis.row_correction_effective_values_v1 overlay
     where overlay.season = subject.season
       and overlay.source_row_id = subject.source_row_id
       and overlay.field_name = 'body_location_code'),
    subject.body_location_value
  ) as effective_body_location_value,
  coalesce(
    (select overlay.new_value
     from analysis.row_correction_effective_values_v1 overlay
     where overlay.season = subject.season
       and overlay.source_row_id = subject.source_row_id
       and overlay.field_name = 'injury_type_code'),
    subject.injury_type_value
  ) as effective_injury_type_value,
  coalesce(
    (select overlay.new_value
     from analysis.row_correction_effective_values_v1 overlay
     where overlay.season = subject.season
       and overlay.source_row_id = subject.source_row_id
       and overlay.field_name = 'diagnosis_code'),
    subject.diagnosis_value
  ) as effective_diagnosis_value
from (
  select distinct season, source_row_id
  from analysis.row_correction_effective_values_v1
) changed
cross join lateral analysis.row_correction_subject_v1(
  changed.season,
  changed.source_row_id
) subject;

create view analysis.row_correction_effective_injury_cohort_v1
with (security_invoker = true) as
with changed as (
  select distinct season, source_row_id
  from analysis.row_correction_effective_values_v1
), unchanged as (
  select base.*
  from analysis.row_correction_base_injury_cohort_v1 base
  where not exists (
    select 1
    from changed
    where changed.season = base.season
      and changed.source_row_id = base.source_row_id
  )
), recalculated as (
  select
    subject.injury_id,
    subject.curated_build_id,
    subject.team_key,
    subject.season,
    subject.source_row_id,
    subject.source_row,
    coalesce(
      subject.baseline_date_injured,
      case
        when trim(subject.final_values ->> 'Date Injured')
          ~ '^\d{2}/\d{2}/\d{4}$'
          then to_date(
            trim(subject.final_values ->> 'Date Injured'),
            'DD/MM/YYYY'
          )
        else null
      end
    ) as date_injured,
    case
      when jsonb_typeof(subject.effective_days_injured_value) <> 'number'
        then null::numeric
      else (subject.effective_days_injured_value #>> '{}')::numeric
    end as days_lost,
    case
      when jsonb_typeof(subject.effective_days_injured_value) = 'number'
        then (subject.effective_days_injured_value #>> '{}')::numeric > 0
      else false
    end as is_time_loss,
    subject.setting_code,
    subject.effective_body_location_value #>> '{}' as body_location_code,
    coalesce(body.label, 'Unknown') as body_location_label,
    subject.effective_injury_type_value #>> '{}' as injury_type_code,
    coalesce(injury_type.label, 'Unknown') as injury_type_label,
    case
      when jsonb_typeof(subject.effective_days_injured_value) <> 'number'
        then 'unknown_or_censored'
      when (subject.effective_days_injured_value #>> '{}')::numeric = 0
        then 'zero_days_medical_attention_only'
      when (subject.effective_days_injured_value #>> '{}')::numeric = 1
        then 'one_day'
      when (subject.effective_days_injured_value #>> '{}')::numeric between 2 and 3
        then 'two_to_three_days'
      when (subject.effective_days_injured_value #>> '{}')::numeric between 4 and 7
        then 'four_to_seven_days'
      when (subject.effective_days_injured_value #>> '{}')::numeric between 8 and 28
        then 'eight_to_twenty_eight_days'
      when (subject.effective_days_injured_value #>> '{}')::numeric > 28
        then 'greater_than_twenty_eight_days'
      else 'unknown_or_censored'
    end as severity_code,
    case
      when jsonb_typeof(subject.effective_days_injured_value) <> 'number'
        then 'Unknown or censored'
      when (subject.effective_days_injured_value #>> '{}')::numeric = 0
        then 'Medical attention'
      when (subject.effective_days_injured_value #>> '{}')::numeric = 1
        then '1 day'
      when (subject.effective_days_injured_value #>> '{}')::numeric between 2 and 3
        then '2-3 days'
      when (subject.effective_days_injured_value #>> '{}')::numeric between 4 and 7
        then '4-7 days'
      when (subject.effective_days_injured_value #>> '{}')::numeric between 8 and 28
        then '8-28 days'
      when (subject.effective_days_injured_value #>> '{}')::numeric > 28
        then '>28 days'
      else 'Unknown or censored'
    end as severity_label,
    coalesce(
      subject.baseline_date_injured,
      case
        when trim(subject.final_values ->> 'Date Injured')
          ~ '^\d{2}/\d{2}/\d{4}$'
          then to_date(
            trim(subject.final_values ->> 'Date Injured'),
            'DD/MM/YYYY'
          )
        else null
      end
    ) is null as is_undated,
    member.cohort_view_version
  from analysis.row_correction_effective_subjects_v1 subject
  join changed
    on changed.season = subject.season
   and changed.source_row_id = subject.source_row_id
  join analysis.row_correction_member_releases_v1 member
    on member.season = subject.season
   and member.team_key = subject.team_key
   and member.curated_build_id = subject.curated_build_id
  join analysis.reporting_season_windows_v3 season_window
    on season_window.cohort_view_version = member.cohort_view_version
   and season_window.season = member.season
  left join curated.code_lists body
    on body.list_name = 'body_location'
   and body.code = subject.effective_body_location_value #>> '{}'
  left join curated.code_lists injury_type
    on injury_type.list_name = 'injury_type'
   and injury_type.code = subject.effective_injury_type_value #>> '{}'
  where subject.effective_eligibility_value = 'true'::jsonb
    and lower(trim(subject.final_values ->> 'Problem type')) = 'injury'
    and (
      coalesce(
        subject.baseline_date_injured,
        case
          when trim(subject.final_values ->> 'Date Injured')
            ~ '^\d{2}/\d{2}/\d{4}$'
            then to_date(
              trim(subject.final_values ->> 'Date Injured'),
              'DD/MM/YYYY'
            )
          else null
        end
      ) is null
      or coalesce(
        subject.baseline_date_injured,
        case
          when trim(subject.final_values ->> 'Date Injured')
            ~ '^\d{2}/\d{2}/\d{4}$'
            then to_date(
              trim(subject.final_values ->> 'Date Injured'),
              'DD/MM/YYYY'
            )
          else null
        end
      ) between season_window.season_start and season_window.season_end
    )
)
select * from unchanged
union all
select * from recalculated;

create view analysis.row_correction_reporting_classification_v1
with (security_invoker = true) as
with changed as (
  select distinct season, source_row_id
  from analysis.row_correction_effective_values_v1
), unchanged as (
  select classification.*
  from analysis.row_correction_base_classification_v1 classification
  join analysis.row_correction_base_injury_cohort_v1 cohort
    using (injury_id, curated_build_id, team_key, season)
  where not exists (
    select 1
    from changed
    where changed.season = cohort.season
      and changed.source_row_id = cohort.source_row_id
  )
), recalculated as (
  select
    cohort.injury_id,
    cohort.curated_build_id,
    cohort.team_key,
    cohort.season,
    cohort.setting_code,
    cohort.is_time_loss,
    cohort.days_lost,
    subject.effective_diagnosis_value #>> '{}' as diagnosis_code,
    case
      when subject.effective_diagnosis_value #>> '{}' = 'unknown'
        then 'Unknown diagnosis'
      when subject.effective_diagnosis_value #>> '{}' = 'concussion'
        then 'Concussion'
      when diagnosis_body.label is not null and diagnosis_type.label is not null
        then diagnosis_body.label || ' · ' || diagnosis_type.label
      else coalesce(
        predecessor.diagnosis_label,
        initcap(replace(
          subject.effective_diagnosis_value #>> '{}', '_', ' '
        ))
      )
    end as diagnosis_label,
    coalesce(
      predecessor.original_body_location_code,
      subject.baseline_body_location_code
    ) as original_body_location_code,
    coalesce(
      predecessor.original_injury_type_code,
      subject.baseline_injury_type_code
    ) as original_injury_type_code,
    subject.effective_body_location_value #>> '{}'
      as effective_body_location_code,
    subject.effective_injury_type_value #>> '{}'
      as effective_injury_type_code,
    case
      when subject.effective_body_location_value <> subject.body_location_value
        then 'row_correction'
      else coalesce(predecessor.body_location_origin, 'predecessor_curated')
    end as body_location_origin,
    case
      when subject.effective_injury_type_value <> subject.injury_type_value
        then 'row_correction'
      else coalesce(predecessor.injury_type_origin, 'predecessor_curated')
    end as injury_type_origin,
    case
      when subject.effective_diagnosis_value <> subject.diagnosis_value
        then 'row_correction'
      else coalesce(predecessor.diagnosis_origin, 'remaining_unknown')
    end as diagnosis_origin,
    coalesce(predecessor.injury_type_candidate_count, 0)
      as injury_type_candidate_count,
    predecessor.candidate_injury_types
  from analysis.row_correction_effective_injury_cohort_v1 cohort
  join analysis.row_correction_effective_subjects_v1 subject
    on subject.season = cohort.season
   and subject.source_row_id = cohort.source_row_id
  join changed
    on changed.season = cohort.season
   and changed.source_row_id = cohort.source_row_id
  left join analysis.row_correction_base_classification_v1 predecessor
    on predecessor.injury_id = cohort.injury_id
   and predecessor.curated_build_id = cohort.curated_build_id
   and predecessor.team_key = cohort.team_key
   and predecessor.season = cohort.season
  left join lateral (
    select split_part(
      subject.effective_diagnosis_value #>> '{}', '__', 2
    ) as body_code
  ) diagnosis_parts on true
  left join lateral (
    select split_part(
      subject.effective_diagnosis_value #>> '{}', '__', 3
    ) as type_code
  ) diagnosis_type_parts on true
  left join curated.code_lists diagnosis_body
    on diagnosis_body.list_name = 'body_location'
   and diagnosis_body.code = diagnosis_parts.body_code
  left join curated.code_lists diagnosis_type
    on diagnosis_type.list_name = 'injury_type'
   and diagnosis_type.code = diagnosis_type_parts.type_code
)
select * from unchanged
union all
select * from recalculated;

create view analysis.row_correction_effective_exposure_cohort_v1
with (security_invoker = true) as
select
  exposure.curated_build_id,
  exposure.team_key,
  exposure.season,
  exposure.effective_period_start,
  exposure.minutes_clean,
  exposure.distance_m_clean,
  exposure.effective_eligibility_status,
  exposure.cohort_view_version
from analysis.analysis_window_effective_exposure_cohort_v5_snapshot exposure
join analysis.row_correction_member_releases_v1 member
  using (curated_build_id, team_key, season)
where member.cohort_view_version = exposure.cohort_view_version
union all
select
  exposure.curated_build_id,
  exposure.team_key,
  exposure.season,
  coalesce(exposure.session_date, exposure.week_start_date),
  exposure.minutes_clean,
  exposure.distance_m_clean,
  case
    when exposure.eligibility_status = 'included_pending_protocol'
      then 'included_pending_protocol'
    else 'excluded_from_primary'
  end,
  member.cohort_view_version
from curated.exposure exposure
join analysis.row_correction_member_releases_v1 member
  using (curated_build_id, team_key, season)
join analysis.reporting_season_windows_v3 season_window
  on season_window.season = member.season
 and season_window.cohort_view_version = member.cohort_view_version
where member.cohort_view_version <>
  'analysis_window_2024-25_2026-07-25_v1'
  and coalesce(exposure.session_date, exposure.week_start_date)
    between season_window.season_start and season_window.season_end;

create view analysis.row_correction_exposure_hours_v1
with (security_invoker = true) as
select v5.*
from analysis.exposure_hours_by_build_analysis_window_v5 v5
join analysis.row_correction_member_releases_v1 member
  using (curated_build_id, team_key, season)
where member.cohort_view_version =
  'analysis_window_2024-25_2026-07-25_v1'
union all
select
  exposure.curated_build_id,
  exposure.team_key,
  exposure.season,
  exposure.matches_played,
  exposure.match_hours,
  exposure.training_hours,
  exposure.total_hours,
  exposure.exposure_grain,
  exposure.method_note
from analysis.exposure_hours_by_build_season_bound_v3 exposure
join analysis.row_correction_member_releases_v1 member
  using (curated_build_id, team_key, season)
where member.cohort_view_version <>
  'analysis_window_2024-25_2026-07-25_v1';

create view analysis.row_correction_team_summary_v1
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days
from analysis.row_correction_effective_injury_cohort_v1 c
group by c.curated_build_id, c.team_key, c.season;

create view analysis.row_correction_setting_split_v1
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, c.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.row_correction_effective_injury_cohort_v1 c
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, c.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_exposure_hours_v1 e
  using (curated_build_id, team_key, season);

create view analysis.row_correction_injury_profiles_v1
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.row_correction_effective_injury_cohort_v1 c
  cross join lateral (values
    ('body_location'::text, c.body_location_code, c.body_location_label),
    ('injury_type'::text, c.injury_type_code, c.injury_type_label),
    ('injury_profile'::text,
      c.body_location_code || '__' || c.injury_type_code,
      c.body_location_label || ' · ' || c.injury_type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_exposure_hours_v1 e
  using (curated_build_id, team_key, season);

create view analysis.row_correction_effective_injury_profiles_v1
with (security_invoker = true) as
with labelled as (
  select c.*,
    coalesce(bl.label,
      initcap(replace(c.effective_body_location_code, '_', ' '))) as body_label,
    coalesce(it.label,
      initcap(replace(c.effective_injury_type_code, '_', ' '))) as type_label
  from analysis.row_correction_reporting_classification_v1 c
  left join curated.code_lists bl
    on bl.list_name = 'body_location'
   and bl.code = c.effective_body_location_code
  left join curated.code_lists it
    on it.list_name = 'injury_type'
   and it.code = c.effective_injury_type_code
), grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from labelled c
  join analysis.row_correction_member_releases_v1 m
    using (curated_build_id, team_key, season)
  cross join lateral (values
    ('body_location'::text, c.effective_body_location_code, c.body_label),
    ('injury_type'::text, c.effective_injury_type_code, c.type_label),
    ('injury_profile'::text,
      c.effective_body_location_code || '__' || c.effective_injury_type_code,
      c.body_label || ' · ' || c.type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_exposure_hours_v1 e
  using (curated_build_id, team_key, season);

create view analysis.row_correction_diagnosis_profiles_v1
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code as code, c.diagnosis_label as label,
    s.setting_code, count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.row_correction_reporting_classification_v1 c
  join analysis.row_correction_member_releases_v1 m
    using (curated_build_id, team_key, season)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code, c.diagnosis_label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_exposure_hours_v1 e
  using (curated_build_id, team_key, season);

create view analysis.row_correction_monthly_v1
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season,
    date_trunc('month', e.effective_period_start)::date as month_start,
    sum(e.minutes_clean) / 60 as exposure_hours,
    sum(e.distance_m_clean) / 1000 as distance_km
  from analysis.row_correction_effective_exposure_cohort_v1 e
  where e.effective_eligibility_status = 'included_pending_protocol'
  group by e.curated_build_id, e.team_key, e.season,
    date_trunc('month', e.effective_period_start)
), injuries as (
  select curated_build_id, team_key, season,
    date_trunc('month', date_injured)::date as month_start,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from analysis.row_correction_effective_injury_cohort_v1
  where date_injured is not null
  group by curated_build_id, team_key, season, date_trunc('month', date_injured)
), months as (
  select curated_build_id, team_key, season, month_start from exposure
  union
  select curated_build_id, team_key, season, month_start from injuries
)
select m.curated_build_id, m.team_key, m.season, m.month_start,
  to_char(m.month_start, 'Mon YYYY') as month_label,
  coalesce(e.exposure_hours, 0) as exposure_hours,
  coalesce(e.distance_km, 0) as distance_km,
  coalesce(i.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(i.days_lost, 0) as days_lost,
  analysis.rate_per_1000_v1(coalesce(i.time_loss_injuries, 0),
    coalesce(e.exposure_hours, 0)) as incidence_per_1000h,
  analysis.rate_per_1000_v1(coalesce(i.days_lost, 0),
    coalesce(e.exposure_hours, 0)) as burden_per_1000h
from months m
left join exposure e using (curated_build_id, team_key, season, month_start)
left join injuries i using (curated_build_id, team_key, season, month_start);

create view analysis.row_correction_severity_distribution_v1
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  case c.severity_code
    when 'zero_days_medical_attention_only' then 0
    when 'one_day' then 1
    when 'two_to_three_days' then 2
    when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4
    when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.row_correction_effective_injury_cohort_v1 c
group by c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label;

create view analysis.row_correction_contact_distribution_v1
with (security_invoker = true) as
with cohort as (
  select
    cohort.curated_build_id,
    cohort.team_key,
    cohort.season,
    cohort.setting_code,
    injury.contact_context,
    cohort.is_time_loss
  from analysis.row_correction_effective_injury_cohort_v1 cohort
  join curated.injuries injury on injury.id = cohort.injury_id
), observed as (
  select
    curated_build_id, team_key, season, setting_code, contact_context,
    count(*) as recorded_injuries,
    count(*) filter (where is_time_loss) as time_loss_injuries
  from cohort
  group by curated_build_id, team_key, season, setting_code, contact_context
  union all
  select
    curated_build_id, team_key, season, 'all'::text, contact_context,
    count(*),
    count(*) filter (where is_time_loss)
  from cohort
  group by curated_build_id, team_key, season, contact_context
), setting_domain(setting_code) as (
  values ('all'), ('match'), ('training'), ('unknown')
), contact_domain(contact_context, contact_label) as (
  values ('contact', 'Contact'),
         ('non_contact', 'Non-contact'),
         ('unknown', 'Unknown')
)
select
  member.curated_build_id,
  member.team_key,
  member.season,
  setting_domain.setting_code,
  contact_domain.contact_context,
  contact_domain.contact_label,
  coalesce(observed.recorded_injuries, 0)::bigint as recorded_injuries,
  coalesce(observed.time_loss_injuries, 0)::bigint as time_loss_injuries
from analysis.row_correction_member_releases_v1 member
cross join setting_domain
cross join contact_domain
left join observed
  on observed.curated_build_id = member.curated_build_id
 and observed.team_key = member.team_key
 and observed.season = member.season
 and observed.setting_code = setting_domain.setting_code
 and observed.contact_context = contact_domain.contact_context;

create view analysis.row_correction_league_contact_distribution_v1
with (security_invoker = true) as
select
  season,
  setting_code,
  contact_context,
  contact_label,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries
from analysis.row_correction_contact_distribution_v1
group by season, setting_code, contact_context, contact_label;

create view analysis.row_correction_league_summary_v1
with (security_invoker = true) as
with cohort as (
  select c.*
  from analysis.row_correction_effective_injury_cohort_v1 c
  join analysis.row_correction_member_releases_v1 m
    using (curated_build_id, team_key, season)
), exposure as (
  select e.season,
    sum(e.total_hours) as exposure_hours,
    sum(e.match_hours) as match_exposure_hours,
    sum(e.training_hours) as training_exposure_hours
  from analysis.row_correction_exposure_hours_v1 e
  join analysis.row_correction_member_releases_v1 m
    using (curated_build_id, team_key, season)
  group by e.season
)
select c.season,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days,
  e.exposure_hours,
  e.match_exposure_hours,
  e.training_exposure_hours
from cohort c
join exposure e using (season)
group by c.season, e.exposure_hours,
  e.match_exposure_hours, e.training_exposure_hours;

create view analysis.row_correction_league_setting_split_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.row_correction_setting_split_v1 x
  join analysis.row_correction_member_releases_v1 m
    using (curated_build_id, team_key, season)
  group by x.season, x.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_league_summary_v1 h using (season);

create view analysis.row_correction_league_injury_profiles_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.row_correction_injury_profiles_v1 x
  join analysis.row_correction_member_releases_v1 m
    using (curated_build_id, team_key, season)
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_league_summary_v1 h using (season);

create view analysis.row_correction_league_effective_injury_profiles_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.row_correction_effective_injury_profiles_v1 x
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_league_summary_v1 h using (season);

create view analysis.row_correction_league_diagnosis_profiles_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.row_correction_diagnosis_profiles_v1 x
  group by x.season, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.row_correction_league_summary_v1 h using (season);

create view analysis.row_correction_league_monthly_v1
with (security_invoker = true) as
select x.season, x.month_start, x.month_label,
  sum(x.exposure_hours) as exposure_hours,
  sum(x.distance_km) as distance_km,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  analysis.rate_per_1000_v1(sum(x.time_loss_injuries), sum(x.exposure_hours))
    as incidence_per_1000h,
  analysis.rate_per_1000_v1(sum(x.days_lost), sum(x.exposure_hours))
    as burden_per_1000h
from analysis.row_correction_monthly_v1 x
join analysis.row_correction_member_releases_v1 m
  using (curated_build_id, team_key, season)
group by x.season, x.month_start, x.month_label;

create view analysis.row_correction_league_severity_distribution_v1
with (security_invoker = true) as
select x.season, x.severity_code, x.severity_label,
  sum(x.recorded_injuries) as recorded_injuries,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  min(x.band_order) as band_order
from analysis.row_correction_severity_distribution_v1 x
join analysis.row_correction_member_releases_v1 m
  using (curated_build_id, team_key, season)
group by x.season, x.severity_code, x.severity_label;

create view analysis.row_correction_target_teams_v1
with (security_invoker = true) as
select distinct target.season, target.team_key
from analysis.row_correction_target_keys_v1 target;

create view analysis.row_correction_team_dashboard_payload_v1
with (security_invoker = true) as
with body as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from analysis.row_correction_effective_injury_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target
    using (team_key, season)
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), types as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.row_correction_effective_injury_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target
    using (team_key, season)
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), profile_rows as (
  select p.curated_build_id, p.team_key, p.season, p.dimension,
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from analysis.row_correction_effective_injury_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target
    using (team_key, season)
  union all
  select p.curated_build_id, p.team_key, p.season, 'diagnosis',
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from analysis.row_correction_diagnosis_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target
    using (team_key, season)
), profiles as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code) as docs
  from profile_rows p
  group by p.curated_build_id, p.team_key, p.season
)
select m.team_key, m.season, m.team_release_id, m.curated_build_id,
  rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  predecessor.dashboard_payload || jsonb_build_object(
    'generated_at', m.generated_at,
    'team', predecessor.dashboard_payload -> 'team',
    'season', m.season,
    'analysis_window', predecessor.dashboard_payload -> 'analysis_window',
    'method', predecessor.dashboard_payload -> 'method',
    'coverage', coalesce(
      predecessor.dashboard_payload -> 'coverage',
      '{}'::jsonb
    ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', s.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', s.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(s.time_loss_injuries, e.total_hours),
        'unit', 'per 1,000 player-hours',
        'numerator', s.time_loss_injuries,
        'denominator', e.total_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', s.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', s.days_lost, 'denominator', s.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', s.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(s.days_lost, e.total_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', s.days_lost, 'denominator', e.total_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.row_correction_setting_split_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.row_correction_setting_split_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from analysis.row_correction_monthly_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from analysis.row_correction_severity_distribution_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'contact_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.contact_context,
        'label', x.contact_label,
        'setting', x.setting_code,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries
      ) order by
        array_position(
          array['all', 'match', 'training', 'unknown'],
          x.setting_code
        ),
        array_position(
          array['contact', 'non_contact', 'unknown'],
          x.contact_context
        ))
      from analysis.row_correction_contact_distribution_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'prior_season', predecessor.dashboard_payload -> 'prior_season',
    'limitations', predecessor.dashboard_payload -> 'limitations'
  ) as dashboard
from analysis.row_correction_member_releases_v1 m
join analysis.row_correction_target_teams_v1 target
  using (team_key, season)
join reporting.dashboard_bundle_team_payloads_v1 predecessor
  on predecessor.bundle_release_id = m.predecessor_bundle_id
 and predecessor.team_key = m.team_key
join analysis.reporting_season_windows_v3 w
  on w.season = m.season
join analysis.row_correction_cohort_rules_v1 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
join analysis.row_correction_team_summary_v1 s
  on s.curated_build_id = m.curated_build_id
 and s.team_key = m.team_key
 and s.season = m.season
join analysis.row_correction_exposure_hours_v1 e
  on e.curated_build_id = m.curated_build_id
 and e.team_key = m.team_key
 and e.season = m.season
left join body
  on body.curated_build_id = m.curated_build_id
 and body.team_key = m.team_key and body.season = m.season
left join types
  on types.curated_build_id = m.curated_build_id
 and types.team_key = m.team_key and types.season = m.season
left join profiles
  on profiles.curated_build_id = m.curated_build_id
 and profiles.team_key = m.team_key and profiles.season = m.season;

create view analysis.row_correction_league_dashboard_payload_v1
with (security_invoker = true) as
with body as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from analysis.row_correction_league_effective_injury_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target using (season)
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.season
), types as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.row_correction_league_effective_injury_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target using (season)
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.season
), profile_rows as (
  select p.season, p.dimension, p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from analysis.row_correction_league_effective_injury_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target using (season)
  union all
  select p.season, 'diagnosis', p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from analysis.row_correction_league_diagnosis_profiles_v1 p
  join analysis.row_correction_target_teams_v1 target using (season)
), profiles as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code) as docs
  from profile_rows p
  group by p.season
)
select h.season,
  rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  predecessor.dashboard_payload || jsonb_build_object(
    'generated_at', (
      select max(m.generated_at)
      from analysis.row_correction_member_releases_v1 m
      where m.season = h.season
    ),
    'team', predecessor.dashboard_payload -> 'team',
    'season', h.season,
    'analysis_window', predecessor.dashboard_payload -> 'analysis_window',
    'method', predecessor.dashboard_payload -> 'method',
    'coverage', coalesce(
      predecessor.dashboard_payload -> 'coverage',
      '{}'::jsonb
    ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', h.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', h.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(
          h.time_loss_injuries, h.exposure_hours),
        'unit', 'per 1,000 player-hours',
        'numerator', h.time_loss_injuries,
        'denominator', h.exposure_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', h.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', h.days_lost, 'denominator', h.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', h.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(h.days_lost, h.exposure_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', h.days_lost, 'denominator', h.exposure_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.row_correction_league_setting_split_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.row_correction_league_setting_split_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from analysis.row_correction_league_monthly_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from analysis.row_correction_league_severity_distribution_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'contact_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.contact_context,
        'label', x.contact_label,
        'setting', x.setting_code,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries
      ) order by
        array_position(
          array['all', 'match', 'training', 'unknown'],
          x.setting_code
        ),
        array_position(
          array['contact', 'non_contact', 'unknown'],
          x.contact_context
        ))
      from analysis.row_correction_league_contact_distribution_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'prior_season', predecessor.dashboard_payload -> 'prior_season',
    'limitations', predecessor.dashboard_payload -> 'limitations'
  ) as dashboard
from analysis.row_correction_league_summary_v1 h
join analysis.row_correction_target_teams_v1 target using (season)
join reporting.latest_approved_dashboard_bundle_v4 bundle
  on bundle.season = h.season
join reporting.dashboard_bundle_league_payloads_v1 predecessor
  on predecessor.release_id = bundle.release_id
join analysis.reporting_season_windows_v3 w
  on w.season = h.season
join analysis.row_correction_cohort_rules_v1 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
left join body on body.season = h.season
left join types on types.season = h.season
left join profiles on profiles.season = h.season;

do $$
begin
  if exists (select 1 from audit.correction_sets_v1)
    or exists (select 1 from processing.correction_drafts_v1)
    or exists (select 1 from reporting.correction_release_context_v1)
    or exists (select 1 from reporting.correction_rollback_context_v1)
    or exists (select 1 from analysis.row_correction_target_teams_v1) then
    raise exception
      'row-correction installation must be data-neutral and targetless';
  end if;
end;
$$;

create function analysis.row_correction_bundle_hash_v1(bundle_release_id uuid)
returns text
language sql
stable
set search_path = pg_catalog, reporting, public
as $$
select encode(extensions.digest(convert_to(jsonb_build_object(
  'schema_version', 'urc_dashboard_bundle_v2',
  'season', context.season,
  'league', league.dashboard_payload,
  'teams', coalesce((
    select jsonb_agg(jsonb_build_object(
      'team_key', team.team_key,
      'dashboard', team.dashboard_payload
    ) order by team.team_key)
    from reporting.dashboard_bundle_team_payloads_v1 team
    where team.bundle_release_id = context.release_id
  ), '[]'::jsonb)
)::text, 'UTF8'), 'sha256'), 'hex')
from reporting.dashboard_bundle_context_v1 context
join reporting.dashboard_bundle_league_payloads_v1 league
  on league.release_id = context.release_id
where context.release_id = bundle_release_id;
$$;

create view analysis.row_correction_pending_context_v1
with (security_invoker = true) as
with preview as (
  select
    null::uuid as correction_set_id,
    proposal ->> 'season' as season,
    proposal ->> 'proposal_hash' as proposal_hash,
    (proposal ->> 'source_row_id')::uuid as source_row_id,
    1 as priority
  from analysis.row_correction_current_preview_v1() proposal
  where proposal is not null
), pending as (
  select
    correction_set.id as correction_set_id,
    correction_set.season,
    correction_set.proposal_hash,
    correction_set.source_row_id,
    0 as priority
  from audit.correction_sets_v1 correction_set
  where (
    not exists (
      select 1
      from reporting.correction_release_context_v1 released
      where released.correction_set_id = correction_set.id
    )
    or exists (
      select 1
      from reporting.correction_release_context_v1 released
      join reporting.aggregate_releases release
        on release.id = released.bundle_release_id
      where released.correction_set_id = correction_set.id
        and release.status = 'draft'
    )
  )
)
select distinct on (season)
  context.correction_set_id,
  context.season,
  context.proposal_hash,
  context.source_row_id,
  subject.team_key as affected_team_key,
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
cross join lateral analysis.row_correction_subject_v1(
  context.season,
  context.source_row_id
) subject
join reporting.latest_approved_dashboard_bundle_v4 bundle
  on bundle.season = context.season
join reporting.aggregate_releases release
  on release.id = bundle.release_id
join reporting.dashboard_bundle_context_v1 bundle_context
  on bundle_context.release_id = bundle.release_id
order by
  context.season, context.priority desc,
  context.correction_set_id desc nulls first;

create view analysis.team_dashboard_release_candidates_correction_v1
with (security_invoker = true) as
select
  predecessor.team_key,
  context.season,
  predecessor.team_release_id,
  predecessor.curated_build_id,
  'correction_v1'::text as analysis_version,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256,
  case
    when predecessor.team_key = context.affected_team_key
      then corrected.dashboard
    else predecessor.dashboard_payload
  end as dashboard
from analysis.row_correction_pending_context_v1 context
join reporting.dashboard_bundle_team_payloads_v1 predecessor
  on predecessor.bundle_release_id = context.predecessor_bundle_id
left join analysis.row_correction_team_dashboard_payload_v1 corrected
  on corrected.season = context.season
 and corrected.team_key = context.affected_team_key
 and corrected.team_release_id = predecessor.team_release_id
 and corrected.curated_build_id = predecessor.curated_build_id
 and predecessor.team_key = context.affected_team_key
where predecessor.team_key <> context.affected_team_key
   or corrected.team_key is not null;

create view analysis.league_dashboard_release_candidates_correction_v1
with (security_invoker = true) as
select
  context.season,
  'correction_v1'::text as analysis_version,
  context.classification_view_version,
  context.classification_evidence_sha256,
  context.cohort_view_version,
  context.cohort_evidence_sha256,
  corrected.dashboard
from analysis.row_correction_pending_context_v1 context
join analysis.row_correction_league_dashboard_payload_v1 corrected
  on corrected.season = context.season;

create function analysis.row_correction_pending_candidate_data_v1()
returns table (
  season text,
  proposal_hash text,
  correction_set_id uuid,
  correction_set_hash text,
  predecessor_bundle jsonb,
  affected_team_key text,
  bundle jsonb,
  draft_bundle_sha256 text,
  unchanged_team_hashes jsonb
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting
as $$
declare
  context_row record;
  correction_set_row audit.correction_sets_v1%rowtype;
  stored_draft processing.correction_drafts_v1%rowtype;
  league_payload jsonb;
  team_payloads jsonb;
  unchanged_hashes jsonb;
  candidate_bundle jsonb;
  candidate_hash text;
begin
  select context.* into context_row
  from analysis.row_correction_pending_context_v1 context;
  if not found then
    return;
  end if;

  if context_row.correction_set_id is not null then
    select correction_set.* into correction_set_row
    from audit.correction_sets_v1 correction_set
    where correction_set.id = context_row.correction_set_id;
    select draft.* into stored_draft
    from processing.correction_drafts_v1 draft
    where draft.correction_set_id = context_row.correction_set_id;
  end if;

  if stored_draft.id is not null then
    league_payload := stored_draft.affected_league_after_payload;
    select coalesce(jsonb_agg(jsonb_build_object(
      'team_key', predecessor.team_key,
      'dashboard', case
        when predecessor.team_key = context_row.affected_team_key
          then stored_draft.affected_team_after_payload
        else predecessor.dashboard_payload
      end
    ) order by predecessor.team_key), '[]'::jsonb)
    into team_payloads
    from reporting.dashboard_bundle_team_payloads_v1 predecessor
    where predecessor.bundle_release_id = context_row.predecessor_bundle_id;
    unchanged_hashes := stored_draft.unchanged_team_hashes;
  else
    select candidate.dashboard into league_payload
    from analysis.league_dashboard_release_candidates_correction_v1 candidate
    where candidate.season = context_row.season;
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'team_key', candidate.team_key,
        'dashboard', candidate.dashboard
      ) order by candidate.team_key), '[]'::jsonb),
      coalesce(jsonb_agg(jsonb_build_object(
        'team_key', predecessor.team_key,
        'payload_sha256', predecessor.payload_sha256
      ) order by predecessor.team_key)
        filter (
          where candidate.dashboard = predecessor.dashboard_payload
        ), '[]'::jsonb)
    into team_payloads, unchanged_hashes
    from analysis.team_dashboard_release_candidates_correction_v1 candidate
    join reporting.dashboard_bundle_team_payloads_v1 predecessor
      on predecessor.bundle_release_id = context_row.predecessor_bundle_id
     and predecessor.team_key = candidate.team_key
    where candidate.season = context_row.season;
  end if;

  if league_payload is null
    or jsonb_array_length(team_payloads) <> 16 then
    raise exception
      'row-correction candidate must contain one league and 16 team payloads';
  end if;

  candidate_bundle := jsonb_build_object(
    'schema_version', 'urc_dashboard_bundle_v2',
    'season', context_row.season,
    'league', league_payload,
    'teams', team_payloads
  );
  candidate_hash := encode(extensions.digest(
    convert_to(candidate_bundle::text, 'UTF8'), 'sha256'
  ), 'hex');
  if stored_draft.id is not null
    and candidate_hash is distinct from stored_draft.draft_bundle_sha256 then
    raise exception 'stored correction draft payloads do not match their hash';
  end if;

  return query select
    context_row.season,
    context_row.proposal_hash,
    context_row.correction_set_id,
    case
      when context_row.correction_set_id is null
        then audit.row_correction_set_hash_v1(
          context_row.season,
          analysis.row_correction_current_preview_v1()
        )
      else correction_set_row.correction_set_hash_after
    end,
    jsonb_build_object(
      'release_id', context_row.predecessor_bundle_id,
      'release_label', context_row.predecessor_release_label,
      'bundle_sha256', context_row.predecessor_bundle_sha256
    ),
    context_row.affected_team_key,
    candidate_bundle,
    candidate_hash,
    unchanged_hashes;
end;
$$;

revoke execute on function
  analysis.row_correction_pending_candidate_data_v1()
  from public, anon, authenticated;

create view analysis.row_correction_pending_candidate_v1
with (security_invoker = true) as
select candidate.*
from analysis.row_correction_pending_candidate_data_v1() candidate;

create function analysis.row_correction_preview_v1(proposal jsonb)
returns table (
  subject jsonb,
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
set search_path = pg_catalog, analysis, audit, processing, reporting, ingestion,
  curated, lineage
as $$
declare
  target record;
  requested_field text := proposal ->> 'field_name';
  requested_old jsonb := proposal -> 'expected_value';
  requested_new jsonb := proposal -> 'new_value';
  current_value jsonb;
  active_correction_id uuid;
  superseded_id uuid;
  pending_count integer;
begin
  if proposal is null
    or not (proposal ? 'expected_value')
    or not (proposal ? 'new_value')
    or nullif(proposal ->> 'season', '') is null
    or nullif(proposal ->> 'source_row_id', '') is null
    or requested_field not in (
      'eligibility', 'days_injured', 'body_location_code',
      'injury_type_code', 'diagnosis_code'
    )
    or nullif(proposal ->> 'reason', '') is null
    or coalesce(proposal ->> 'evidence_sha256', '') !~ '^[0-9a-f]{64}$'
    or nullif(proposal ->> 'operator', '') is null
    or nullif(proposal ->> 'rule_version', '') is null
    or nullif(proposal ->> 'code_version', '') is null
    or coalesce(proposal ->> 'dependency_lock_hash', '')
      !~ '^[0-9a-f]{64}$'
    or coalesce(proposal ->> 'migration_sha256', '')
      !~ '^[0-9a-f]{64}$'
  then
    raise exception 'invalid or incomplete row-correction proposal';
  end if;

  select count(*) into pending_count
  from audit.correction_sets_v1 correction_set
  where correction_set.season = proposal ->> 'season'
    and not exists (
      select 1
      from reporting.correction_release_context_v1 released
      where released.correction_set_id = correction_set.id
    );
  if pending_count <> 0 then
    raise exception
      'a correction is already applied but unpromoted for this season';
  end if;

  select * into target
  from analysis.row_correction_subject_v1(
    proposal ->> 'season',
    (proposal ->> 'source_row_id')::uuid
  ) row_target;
  if not found then
    raise exception
      'source row is not an allowlisted bridged injury row for this season';
  end if;

  current_value := case requested_field
    when 'eligibility' then target.eligibility_value
    when 'days_injured' then target.days_injured_value
    when 'body_location_code' then target.body_location_value
    when 'injury_type_code' then target.injury_type_value
    when 'diagnosis_code' then target.diagnosis_value
  end;
  if current_value is distinct from requested_old then
    raise exception 'expected current effective value does not match';
  end if;
  if requested_new is not distinct from current_value then
    raise exception 'new value must differ from the current effective value';
  end if;

  if requested_field = 'eligibility'
    and jsonb_typeof(requested_new) is distinct from 'boolean' then
    raise exception 'eligibility correction requires a boolean value';
  elsif requested_field = 'days_injured'
    and not (
      requested_new = 'null'::jsonb
      or (
        jsonb_typeof(requested_new) is not distinct from 'number'
        and (requested_new #>> '{}') ~ '^\d+$'
        and (requested_new #>> '{}')::numeric >= 0
      )
    ) then
    raise exception 'days_injured correction requires a non-negative integer or null';
  elsif requested_field in ('body_location_code', 'injury_type_code') then
    if jsonb_typeof(requested_new) is distinct from 'string'
      or not exists (
        select 1
        from curated.code_lists code
        where code.list_name = case requested_field
          when 'body_location_code' then 'body_location'
          else 'injury_type'
        end
          and code.code = requested_new #>> '{}'
      ) then
      raise exception 'clinical correction is not a controlled IOC code';
    end if;
  elsif requested_field = 'diagnosis_code'
    and (
      jsonb_typeof(requested_new) is distinct from 'string'
      or not (
        requested_new #>> '{}' in ('unknown', 'concussion')
        or (
          requested_new #>> '{}' ~
            '^compound__[a-z0-9_]+__[a-z0-9_]+$'
          and exists (
            select 1
            from curated.code_lists body
            where body.list_name = 'body_location'
              and body.code = split_part(
                requested_new #>> '{}', '__', 2
              )
          )
          and exists (
            select 1
            from curated.code_lists injury_type
            where injury_type.list_name = 'injury_type'
              and injury_type.code = split_part(
                requested_new #>> '{}', '__', 3
              )
          )
        )
      )
    ) then
    raise exception
      'diagnosis correction must be unknown, concussion, or controlled compound code';
  end if;

  select correction.id into active_correction_id
  from audit.row_corrections_v1 correction
  where correction.season = target.season
    and correction.source_row_id = target.source_row_id
    and correction.field_name = requested_field
  order by correction.created_at desc, correction.id desc
  limit 1;
  superseded_id := nullif(proposal ->> 'supersedes_correction_id', '')::uuid;
  if active_correction_id is distinct from superseded_id then
    raise exception
      'supersedes_correction_id does not match the latest correction history';
  end if;

  perform set_config('urc.row_correction_preview', proposal::text, true);

  return query
  select
    jsonb_build_object(
      'source_row_id', target.source_row_id,
      'source_row_sha256', target.source_row_sha256,
      'row_fingerprint', target.row_fingerprint,
      'team_key', target.team_key,
      'season', target.season,
      'field_name', requested_field,
      'current_effective_value', current_value
    ),
    candidate.predecessor_bundle,
    audit.row_correction_set_hash_v1(target.season, null),
    audit.row_correction_set_hash_v1(target.season, proposal),
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
  from analysis.row_correction_pending_candidate_v1 candidate
  join analysis.row_correction_pending_context_v1 context
    on context.season = candidate.season
  join reporting.dashboard_bundle_team_payloads_v1 before_team
    on before_team.bundle_release_id = context.predecessor_bundle_id
   and before_team.team_key = context.affected_team_key
  cross join lateral jsonb_array_elements(
    candidate.bundle -> 'teams'
  ) after_team(doc)
  join reporting.dashboard_bundle_league_payloads_v1 before_league
    on before_league.release_id = context.predecessor_bundle_id
  where candidate.season = target.season
    and after_team.doc ->> 'team_key' = context.affected_team_key;
end;
$$;

revoke execute on function analysis.row_correction_preview_v1(jsonb)
  from public, anon, authenticated;

create function audit.apply_row_correction_v1(
  proposal jsonb,
  approval_evidence text,
  approval_reviewer text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting, ingestion,
  curated, lineage
as $$
declare
  target record;
  preview_row record;
  current_bundle_id uuid;
  current_bundle_sha256 text;
  current_value jsonb;
  expected_proposal_hash text;
  set_id uuid := gen_random_uuid();
  correction_id uuid := gen_random_uuid();
  run_id uuid := gen_random_uuid();
  apply_step_id uuid := gen_random_uuid();
  draft_step_id uuid := gen_random_uuid();
  draft_id uuid := gen_random_uuid();
  requested_field text := proposal ->> 'field_name';
  superseded_id uuid :=
    nullif(proposal ->> 'supersedes_correction_id', '')::uuid;
begin
  if approval_reviewer <> 'Abdel Babiker' then
    raise exception 'correction apply requires Abdel Babiker as reviewer';
  end if;
  if nullif(approval_evidence, '') is null
    or encode(extensions.digest(convert_to(approval_evidence, 'UTF8'), 'sha256'),
      'hex') is distinct from proposal ->> 'evidence_sha256' then
    raise exception 'correction approval evidence does not match its hash';
  end if;
  if nullif(proposal ->> 'code_version', '') is null
    or proposal ->> 'dependency_lock_hash' !~ '^[0-9a-f]{64}$'
    or proposal ->> 'migration_sha256' !~ '^[0-9a-f]{64}$' then
    raise exception 'correction proposal provenance is incomplete';
  end if;
  expected_proposal_hash :=
    analysis.row_correction_proposal_hash_v1(proposal);
  if proposal ->> 'proposal_hash' is distinct from expected_proposal_hash then
    raise exception 'proposal hash is invalid';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('row-correction:' || proposal ->> 'season', 0)
  );

  if exists (
    select 1
    from audit.correction_sets_v1 correction_set
    where correction_set.season = proposal ->> 'season'
      and not exists (
        select 1
        from reporting.correction_release_context_v1 released
        where released.correction_set_id = correction_set.id
      )
  ) then
    raise exception
      'concurrent correction rejected: this season already has a pending set';
  end if;

  perform 1
  from ingestion.source_rows source
  where source.id = (proposal ->> 'source_row_id')::uuid
  for update;

  select * into target
  from analysis.row_correction_subject_v1(
    proposal ->> 'season',
    (proposal ->> 'source_row_id')::uuid
  ) row_target;
  if not found then
    raise exception 'stale correction proposal: source row is unavailable';
  end if;
  if target.source_row_sha256 is distinct from
      proposal ->> 'source_row_sha256'
    or target.row_fingerprint is distinct from
      proposal ->> 'row_fingerprint' then
    raise exception 'stale correction proposal: source-row fingerprint changed';
  end if;

  current_value := case requested_field
    when 'eligibility' then target.eligibility_value
    when 'days_injured' then target.days_injured_value
    when 'body_location_code' then target.body_location_value
    when 'injury_type_code' then target.injury_type_value
    when 'diagnosis_code' then target.diagnosis_value
    else null
  end;
  if current_value is distinct from proposal -> 'expected_value' then
    raise exception 'stale correction proposal: current effective value changed';
  end if;
  if audit.row_correction_set_hash_v1(target.season, null) is distinct from
      proposal ->> 'correction_set_hash_before' then
    raise exception 'concurrent correction rejected: correction-set hash changed';
  end if;

  select correction.id into superseded_id
  from audit.row_corrections_v1 correction
  where correction.season = target.season
    and correction.source_row_id = target.source_row_id
    and correction.field_name = requested_field
  order by correction.created_at desc, correction.id desc
  limit 1;
  if superseded_id is distinct from
      nullif(proposal ->> 'supersedes_correction_id', '')::uuid then
    raise exception
      'concurrent correction rejected: active predecessor changed';
  end if;

  select bundle.release_id,
    analysis.row_correction_bundle_hash_v1(bundle.release_id)
  into current_bundle_id, current_bundle_sha256
  from reporting.latest_approved_dashboard_bundle_v4 bundle
  join reporting.aggregate_releases release
    on release.id = bundle.release_id
  where bundle.season = target.season
  for update of release;
  if current_bundle_id is null
    or current_bundle_id::text is distinct from
      proposal #>> '{predecessor_bundle,release_id}'
    or current_bundle_sha256 is distinct from
      proposal #>> '{predecessor_bundle,bundle_sha256}' then
    raise exception 'stale correction proposal: predecessor bundle changed';
  end if;

  select * into preview_row
  from analysis.row_correction_preview_v1(proposal);
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
    raise exception 'stale correction proposal: downstream preview changed';
  end if;

  insert into audit.pipeline_runs (
    id, command, team, season, status, parameters, input_hash,
    output_hash, operator, code_version, dependency_lock_hash
  ) values (
    run_id, 'correction-apply', target.team_key, target.season, 'started',
    jsonb_build_object(
      'proposal_hash', expected_proposal_hash,
      'reviewer', approval_reviewer,
      'rule_version', proposal ->> 'rule_version',
      'base_bundle_id', current_bundle_id,
      'source_row_fingerprint', target.row_fingerprint,
      'migration_file',
        '20260726200000_dynamic_row_correction_pipeline.sql',
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
    apply_step_id, run_id, 'apply_row_correction',
    proposal ->> 'rule_version', 'row_correction_applied',
    1, 1, jsonb_build_object(target.team_key, 1),
    target.row_fingerprint,
    proposal ->> 'correction_set_hash_after'
  );

  insert into audit.correction_sets_v1 (
    id, season, proposal_hash, source_row_id, team_key,
    base_bundle_id, base_bundle_sha256,
    correction_set_hash_before, correction_set_hash_after,
    source_row_sha256, row_fingerprint, field_name, old_value, new_value,
    reason, evidence_sha256, operator, reviewer, rule_version,
    code_version, dependency_lock_hash, migration_sha256,
    supersedes_correction_id, apply_pipeline_run_id
  ) values (
    set_id, target.season, expected_proposal_hash, target.source_row_id,
    target.team_key, current_bundle_id, current_bundle_sha256,
    proposal ->> 'correction_set_hash_before',
    proposal ->> 'correction_set_hash_after',
    target.source_row_sha256, target.row_fingerprint, requested_field,
    current_value, proposal -> 'new_value', proposal ->> 'reason',
    proposal ->> 'evidence_sha256', proposal ->> 'operator',
    approval_reviewer, proposal ->> 'rule_version',
    proposal ->> 'code_version', proposal ->> 'dependency_lock_hash',
    proposal ->> 'migration_sha256',
    superseded_id, run_id
  );

  insert into audit.row_corrections_v1 (
    id, correction_set_id, season, source_row_id, field_name,
    old_value, new_value, reason, evidence_sha256, operator, reviewer,
    rule_version, proposal_hash, supersedes_correction_id
  ) values (
    correction_id, set_id, target.season, target.source_row_id,
    requested_field, current_value, proposal -> 'new_value',
    proposal ->> 'reason', proposal ->> 'evidence_sha256',
    proposal ->> 'operator', approval_reviewer,
    proposal ->> 'rule_version', expected_proposal_hash, superseded_id
  );

  insert into audit.record_events (
    step_run_id, source_row_id, field_name, old_value, new_value,
    action, reason_code, rationale, rule_version, review_status
  ) values (
    apply_step_id, target.source_row_id, requested_field,
    current_value, proposal -> 'new_value', 'row_correction',
    'row_correction_applied', proposal ->> 'reason',
    proposal ->> 'rule_version', 'approved'
  );

  -- processing.record_versions remains the immutable intake-processing
  -- history. Correction processing evidence uses its own append-only typed
  -- successor so a reporting overlay cannot masquerade as re-ingestion.
  insert into processing.correction_versions_v1 (
    correction_set_id, source_row_id, field_name,
    effective_value_before, effective_value_after,
    input_row_fingerprint, output_row_fingerprint,
    input_hash, output_hash, step_run_id
  ) values (
    set_id, target.source_row_id, requested_field,
    current_value, proposal -> 'new_value',
    target.row_fingerprint,
    (
      select corrected.row_fingerprint
      from analysis.row_correction_subject_v1(
        target.season,
        target.source_row_id
      ) corrected
    ),
    expected_proposal_hash,
    proposal ->> 'correction_set_hash_after',
    apply_step_id
  );

  perform set_config('urc.row_correction_preview', '', true);

  insert into audit.step_runs (
    id, pipeline_run_id, step_name, step_version, reason_code,
    input_count, output_count, counts_by_team, input_hash, output_hash
  ) values (
    draft_step_id, run_id, 'recompute_row_correction_draft',
    'row_correction_candidate_2026-07-26_v1', 'row_correction_draft',
    1, 17, jsonb_build_object(target.team_key, 1),
    proposal ->> 'correction_set_hash_after',
    proposal ->> 'affected_league_after_sha256'
  );

  if audit.row_correction_set_hash_v1(target.season, null) is distinct from
      proposal ->> 'correction_set_hash_after' then
    raise exception
      'applied correction set does not match the reviewed correction hash';
  end if;

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
    target.team_key,
    proposal ->> 'affected_team_before_sha256',
    proposal ->> 'affected_team_after_sha256',
    proposal ->> 'affected_league_before_sha256',
    proposal ->> 'affected_league_after_sha256',
    preview_row.affected_team_after,
    preview_row.affected_league_after,
    preview_row.unchanged_team_hashes,
    preview_row.draft_bundle_sha256,
    expected_proposal_hash,
    proposal ->> 'correction_set_hash_after',
    (
      proposal ->> 'affected_team_before_sha256' is distinct from
        proposal ->> 'affected_team_after_sha256'
      or proposal ->> 'affected_league_before_sha256' is distinct from
        proposal ->> 'affected_league_after_sha256'
    ),
    draft_step_id
  );

  update audit.step_runs
  set ended_at = now()
  where id in (apply_step_id, draft_step_id);
  update audit.pipeline_runs
  set status = 'succeeded', ended_at = now(),
    output_hash = preview_row.draft_bundle_sha256
  where id = run_id;

  return jsonb_build_object(
    'correction_set_id', set_id,
    'correction_id', correction_id,
    'proposal_hash', expected_proposal_hash,
    'correction_set_hash', proposal ->> 'correction_set_hash_after',
    'draft_bundle_sha256', preview_row.draft_bundle_sha256,
    'metric_change_detected',
      (
        proposal ->> 'affected_team_before_sha256' is distinct from
          proposal ->> 'affected_team_after_sha256'
        or proposal ->> 'affected_league_before_sha256' is distinct from
          proposal ->> 'affected_league_after_sha256'
      )
  );
end;
$$;

revoke execute on function audit.apply_row_correction_v1(jsonb, text, text)
  from public, anon, authenticated;

create function reporting.validate_dynamic_league_payload_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting
as $$
declare
  expected_payload jsonb;
  context_count integer;
begin
  select count(*) into context_count
  from (
    select correction.bundle_release_id
    from reporting.correction_release_context_v1 correction
    where correction.bundle_release_id = new.bundle_release_id
    union all
    select rollback.bundle_release_id
    from reporting.correction_rollback_context_v1 rollback
    where rollback.bundle_release_id = new.bundle_release_id
  ) dynamic_context;
  if context_count <> 1 then
    raise exception
      'dynamic league payload requires exactly one correction or rollback context';
  end if;

  if exists (
    select 1
    from reporting.correction_release_context_v1 context
    where context.bundle_release_id = new.bundle_release_id
  ) then
    select draft.affected_league_after_payload into expected_payload
    from reporting.correction_release_context_v1 context
    join processing.correction_drafts_v1 draft
      on draft.id = context.correction_draft_id
    where context.bundle_release_id = new.bundle_release_id;
  elsif exists (
    select 1
    from reporting.correction_rollback_context_v1 context
    where context.bundle_release_id = new.bundle_release_id
  ) then
    select restored.dashboard_payload into expected_payload
    from reporting.correction_rollback_context_v1 context
    join reporting.dashboard_bundle_league_payloads_v1 restored
      on restored.release_id = context.restored_bundle_id
    where context.bundle_release_id = new.bundle_release_id;
  end if;

  if expected_payload is null
    or new.dashboard_payload is distinct from expected_payload then
    raise exception
      'dynamic league payload differs from its versioned candidate';
  end if;
  return new;
end;
$$;

create function reporting.validate_dynamic_team_payloads_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting
as $$
begin
  if exists (
    select 1
    from new_dynamic_team_payloads_v1 payload
    where (
      select count(*)
      from (
        select correction.bundle_release_id
        from reporting.correction_release_context_v1 correction
        where correction.bundle_release_id = payload.bundle_release_id
        union all
        select rollback.bundle_release_id
        from reporting.correction_rollback_context_v1 rollback
        where rollback.bundle_release_id = payload.bundle_release_id
      ) dynamic_context
    ) <> 1
  ) then
    raise exception
      'dynamic team payload requires exactly one correction or rollback context';
  end if;

  if exists (
    select 1
    from new_dynamic_team_payloads_v1 payload
    join reporting.correction_release_context_v1 context
      on context.bundle_release_id = payload.bundle_release_id
    join processing.correction_drafts_v1 draft
      on draft.id = context.correction_draft_id
    left join reporting.dashboard_bundle_team_payloads_v1 predecessor
      on predecessor.bundle_release_id = context.predecessor_bundle_id
     and predecessor.team_key = payload.team_key
     and predecessor.team_release_id = payload.team_release_id
     and predecessor.curated_build_id = payload.curated_build_id
    where predecessor.team_key is null
      or payload.dashboard_payload is distinct from case
        when payload.team_key = context.affected_team_key
          then draft.affected_team_after_payload
        else predecessor.dashboard_payload
      end
  ) then
    raise exception
      'dynamic correction team payload differs from its versioned candidate';
  end if;

  if exists (
    select 1
    from new_dynamic_team_payloads_v1 payload
    join reporting.correction_rollback_context_v1 context
      on context.bundle_release_id = payload.bundle_release_id
    left join reporting.dashboard_bundle_team_payloads_v1 restored
      on restored.bundle_release_id = context.restored_bundle_id
     and restored.team_key = payload.team_key
     and restored.team_release_id = payload.team_release_id
     and restored.curated_build_id = payload.curated_build_id
     and restored.dashboard_payload = payload.dashboard_payload
    where restored.team_key is null
  ) then
    raise exception
      'dynamic rollback team payload differs from its retained predecessor';
  end if;
  return null;
end;
$$;

create function reporting.validate_dynamic_bundle_context_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting
as $$
declare
  correction_context reporting.correction_release_context_v1%rowtype;
  rollback_context reporting.correction_rollback_context_v1%rowtype;
  predecessor_context record;
  draft processing.correction_drafts_v1%rowtype;
  payload_count integer;
begin
  if new.status <> 'approved'
    or (
      tg_op = 'UPDATE'
      and old.status is not distinct from new.status
    ) then
    return new;
  end if;

  select context.* into correction_context
  from reporting.correction_release_context_v1 context
  where context.bundle_release_id = new.id;
  select context.* into rollback_context
  from reporting.correction_rollback_context_v1 context
  where context.bundle_release_id = new.id;
  if correction_context.bundle_release_id is not null
    and rollback_context.bundle_release_id is not null then
    raise exception
      'a dynamic bundle cannot be both a correction and a rollback';
  end if;

  if correction_context.bundle_release_id is not null then
    select context.* into predecessor_context
    from reporting.dashboard_bundle_context_v1 context
    where context.release_id = correction_context.predecessor_bundle_id;
    select draft_row.* into draft
    from processing.correction_drafts_v1 draft_row
    where draft_row.id = correction_context.correction_draft_id;
    if predecessor_context.release_id is null
      or draft.id is null
      or draft.correction_set_id is distinct from
        correction_context.correction_set_id
      or draft.predecessor_bundle_id is distinct from
        correction_context.predecessor_bundle_id
      or draft.affected_team_key is distinct from
        correction_context.affected_team_key
      or draft.proposal_hash is distinct from
        correction_context.proposal_hash
      or draft.correction_set_hash is distinct from
        correction_context.correction_set_hash
      or not exists (
        select 1
        from audit.correction_sets_v1 correction_set
        where correction_set.id = correction_context.correction_set_id
          and correction_set.season = correction_context.season
          and correction_set.team_key =
            correction_context.affected_team_key
          and correction_set.proposal_hash =
            correction_context.proposal_hash
          and correction_set.correction_set_hash_after =
            correction_context.correction_set_hash
          and correction_set.base_bundle_id =
            correction_context.predecessor_bundle_id
      )
      or correction_context.season is distinct from
        predecessor_context.season
      or correction_context.analysis_version is distinct from
        predecessor_context.analysis_version
      or correction_context.generated_at is distinct from
        predecessor_context.generated_at
      or correction_context.expected_member_count is distinct from
        predecessor_context.expected_member_count
      or correction_context.match_exposure_decision is distinct from
        predecessor_context.match_exposure_decision
      or correction_context.decision_reviewer is distinct from
        predecessor_context.decision_reviewer
      or correction_context.decision_recorded_at is distinct from
        predecessor_context.decision_recorded_at
      or correction_context.classification_view_version is distinct from
        predecessor_context.classification_view_version
      or correction_context.classification_evidence_sha256 is distinct from
        predecessor_context.classification_evidence_sha256
      or correction_context.cohort_view_version is distinct from
        predecessor_context.cohort_view_version
      or correction_context.cohort_evidence_sha256 is distinct from
        predecessor_context.cohort_evidence_sha256 then
      raise exception
        'correction bundle context must exactly retain predecessor semantics';
    end if;
    select count(*) into payload_count
    from reporting.correction_team_payloads_v1 payload
    where payload.bundle_release_id = new.id;
    if payload_count <> 16
      or not exists (
        select 1
        from reporting.correction_league_payloads_v1 payload
        where payload.bundle_release_id = new.id
      )
      or analysis.row_correction_bundle_hash_v1(new.id)
        is distinct from draft.draft_bundle_sha256 then
      raise exception 'correction bundle is incomplete or hash-mismatched';
    end if;
  elsif rollback_context.bundle_release_id is not null then
    select context.* into predecessor_context
    from reporting.dashboard_bundle_context_v1 context
    where context.release_id = rollback_context.restored_bundle_id;
    if predecessor_context.release_id is null
      or rollback_context.season is distinct from predecessor_context.season
      or rollback_context.analysis_version is distinct from
        predecessor_context.analysis_version
      or rollback_context.generated_at is distinct from
        predecessor_context.generated_at
      or rollback_context.expected_member_count is distinct from
        predecessor_context.expected_member_count
      or rollback_context.match_exposure_decision is distinct from
        predecessor_context.match_exposure_decision
      or rollback_context.decision_reviewer is distinct from
        predecessor_context.decision_reviewer
      or rollback_context.decision_recorded_at is distinct from
        predecessor_context.decision_recorded_at
      or rollback_context.classification_view_version is distinct from
        predecessor_context.classification_view_version
      or rollback_context.classification_evidence_sha256 is distinct from
        predecessor_context.classification_evidence_sha256
      or rollback_context.cohort_view_version is distinct from
        predecessor_context.cohort_view_version
      or rollback_context.cohort_evidence_sha256 is distinct from
        predecessor_context.cohort_evidence_sha256
      or analysis.row_correction_bundle_hash_v1(new.id)
        is distinct from analysis.row_correction_bundle_hash_v1(
          rollback_context.restored_bundle_id
        ) then
      raise exception
        'rollback bundle must be an exact immutable predecessor snapshot';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function reporting.validate_dynamic_league_payload_v1()
  from public, anon, authenticated;
revoke execute on function reporting.validate_dynamic_team_payloads_v1()
  from public, anon, authenticated;
revoke execute on function reporting.validate_dynamic_bundle_context_v1()
  from public, anon, authenticated;

create trigger validate_dynamic_league_payload_v1
after insert on reporting.correction_league_payloads_v1
for each row execute function reporting.validate_dynamic_league_payload_v1();
create trigger validate_dynamic_team_payloads_v1
after insert on reporting.correction_team_payloads_v1
referencing new table as new_dynamic_team_payloads_v1
for each statement
execute function reporting.validate_dynamic_team_payloads_v1();
create trigger validate_dynamic_bundle_context_v1
before insert or update of status on reporting.aggregate_releases
for each row execute function reporting.validate_dynamic_bundle_context_v1();

create function reporting.guard_active_row_corrections_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, analysis, audit, reporting
as $$
declare
  target_season text;
begin
  if old.status = 'draft' and new.status = 'approved'
    and not exists (
      select 1
      from reporting.correction_release_context_v1 correction
      where correction.bundle_release_id = new.id
    )
    and not exists (
      select 1
      from reporting.correction_rollback_context_v1 rollback
      where rollback.bundle_release_id = new.id
    ) then
    select context.season into target_season
    from reporting.league_release_context_v2 context
    where context.release_id = new.id;
    if target_season is not null
      and (
        exists (
          select 1
          from analysis.row_correction_served_sets_v1 served
          where served.season = target_season
        )
        or exists (
          select 1
          from audit.correction_sets_v1 pending
          where pending.season = target_season
            and not exists (
              select 1
              from reporting.correction_release_context_v1 promoted
              where promoted.correction_set_id = pending.id
            )
        )
      ) then
      raise exception
        'ordinary release approval blocked while served row corrections are active or a correction is pending';
    end if;
  end if;

  if old.status = 'approved' and new.status = 'retired' then
    select context.season into target_season
    from reporting.dashboard_bundle_context_v1 context
    where context.release_id = old.id;
    if exists (
      select 1
      from analysis.row_correction_served_sets_v1 served
      where served.season = target_season
    ) and not exists (
      select 1
      from reporting.aggregate_releases successor
      join reporting.dashboard_bundle_context_v1 successor_context
        on successor_context.release_id = successor.id
      left join reporting.correction_release_context_v1 correction
        on correction.bundle_release_id = successor.id
      left join reporting.correction_rollback_context_v1 rollback
        on rollback.bundle_release_id = successor.id
      where successor.status = 'draft'
        and successor_context.season = target_season
        and (
          correction.bundle_release_id is not null
          or rollback.bundle_release_id is not null
        )
    ) then
      raise exception
        'ordinary release blocked while served row corrections are active';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function reporting.guard_active_row_corrections_v1()
  from public, anon, authenticated;
create trigger guard_active_row_corrections_v1
before update of status on reporting.aggregate_releases
for each row execute function reporting.guard_active_row_corrections_v1();

create function reporting.promote_row_correction_v1(
  target_proposal_hash text,
  promotion_reviewer text,
  target_release_label text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, analysis, audit, processing, reporting, ingestion,
  curated, lineage
as $$
declare
  correction_set audit.correction_sets_v1%rowtype;
  draft processing.correction_drafts_v1%rowtype;
  pending record;
  new_release_id uuid := gen_random_uuid();
  run_id uuid := gen_random_uuid();
  step_id uuid := gen_random_uuid();
  current_bundle_id uuid;
  member_count integer;
  affected_count integer;
  unchanged_count integer;
begin
  if nullif(promotion_reviewer, '') is null
    or promotion_reviewer <> 'Abdel Babiker' then
    raise exception 'correction promotion requires Abdel Babiker as reviewer';
  end if;
  if nullif(target_release_label, '') is null then
    raise exception 'correction release label is required';
  end if;
  if target_proposal_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid correction proposal hash';
  end if;

  select correction_set_row.* into correction_set
  from audit.correction_sets_v1 correction_set_row
  where correction_set_row.proposal_hash = target_proposal_hash;
  if not found then
    raise exception 'no applied correction matches this proposal';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('row-correction:' || correction_set.season, 0)
  );
  if exists (
    select 1
    from reporting.correction_release_context_v1 released
    where released.correction_set_id = correction_set.id
  ) then
    raise exception 'correction set has already been promoted';
  end if;

  select draft_row.* into draft
  from processing.correction_drafts_v1 draft_row
  where draft_row.correction_set_id = correction_set.id;
  if not found then
    raise exception 'correction set has no audited draft';
  end if;

  select bundle.release_id into current_bundle_id
  from reporting.latest_approved_dashboard_bundle_v4 bundle
  join reporting.aggregate_releases release
    on release.id = bundle.release_id
  where bundle.season = correction_set.season
  for update of release;
  if current_bundle_id is distinct from draft.predecessor_bundle_id
    or analysis.row_correction_bundle_hash_v1(current_bundle_id) is distinct
      from draft.predecessor_bundle_sha256 then
    raise exception 'approved predecessor changed after correction preflight';
  end if;

  select * into pending
  from analysis.row_correction_pending_candidate_v1 candidate
  where candidate.season = correction_set.season
    and candidate.proposal_hash = target_proposal_hash;
  if not found
    or pending.correction_set_id is distinct from correction_set.id
    or pending.correction_set_hash is distinct from
      correction_set.correction_set_hash_after
    or pending.draft_bundle_sha256 is distinct from
      draft.draft_bundle_sha256
    or pending.unchanged_team_hashes is distinct from
      draft.unchanged_team_hashes then
    raise exception 'pending correction candidate differs from reviewed draft';
  end if;

  select count(*) into member_count
  from reporting.dashboard_bundle_team_payloads_v1 predecessor
  where predecessor.bundle_release_id = draft.predecessor_bundle_id;
  affected_count := case
    when draft.affected_team_before_sha256 is distinct from
      draft.affected_team_after_sha256 then 1
    else 0
  end;
  unchanged_count := jsonb_array_length(draft.unchanged_team_hashes);
  if member_count <> 16
    or not (
      (affected_count = 1 and unchanged_count = 15)
      or (affected_count = 0 and unchanged_count = 16)
    )
    or encode(extensions.digest(convert_to(
      draft.affected_team_after_payload::text, 'UTF8'
    ), 'sha256'), 'hex') is distinct from
      draft.affected_team_after_sha256
    or encode(extensions.digest(convert_to(
      draft.affected_league_after_payload::text, 'UTF8'
    ), 'sha256'), 'hex') is distinct from
      draft.affected_league_after_sha256 then
    raise exception
      'incremental correction must change at most one team and retain all other predecessor payloads';
  end if;

  insert into audit.pipeline_runs (
    id, command, team, season, status, parameters,
    input_hash, output_hash, operator, code_version, dependency_lock_hash
  ) values (
    run_id, 'correction-release', 'URC Overall', correction_set.season,
    'started',
    jsonb_build_object(
      'proposal_hash', target_proposal_hash,
      'correction_set_id', correction_set.id,
      'correction_set_hash', correction_set.correction_set_hash_after,
      'predecessor_bundle_id', draft.predecessor_bundle_id,
      'predecessor_bundle_sha256', draft.predecessor_bundle_sha256,
      'unchanged_team_hashes', draft.unchanged_team_hashes,
      'reviewer', promotion_reviewer,
      'migration_file',
        '20260726200000_dynamic_row_correction_pipeline.sql',
      'migration_sha256', correction_set.migration_sha256
    ),
    draft.predecessor_bundle_sha256,
    draft.draft_bundle_sha256,
    correction_set.operator,
    correction_set.code_version,
    correction_set.dependency_lock_hash
  );
  insert into audit.step_runs (
    id, pipeline_run_id, step_name, step_version, reason_code,
    input_count, output_count, counts_by_team, input_hash, output_hash
  ) values (
    step_id, run_id, 'promote_row_correction_bundle',
    'row_correction_release_2026-07-26_v1',
    'row_correction_release', 16, 17,
    jsonb_build_object(correction_set.team_key, 1, 'unchanged_teams', 15),
    draft.predecessor_bundle_sha256,
    draft.draft_bundle_sha256
  );
  insert into reporting.aggregate_releases (
    id, release_label, status, pipeline_run_id
  ) values (
    new_release_id, target_release_label, 'draft', run_id
  );
  insert into reporting.correction_release_context_v1 (
    bundle_release_id, correction_set_id, correction_draft_id,
    predecessor_bundle_id,
    season, analysis_version, generated_at, expected_member_count,
    match_exposure_decision, decision_reviewer, decision_recorded_at,
    classification_view_version, classification_evidence_sha256,
    cohort_view_version, cohort_evidence_sha256,
    affected_team_key, proposal_hash,
    correction_set_hash, reviewer
  )
  select
    new_release_id, correction_set.id, draft.id,
    draft.predecessor_bundle_id,
    predecessor.season, predecessor.analysis_version,
    predecessor.generated_at, predecessor.expected_member_count,
    predecessor.match_exposure_decision,
    predecessor.decision_reviewer, predecessor.decision_recorded_at,
    predecessor.classification_view_version,
    predecessor.classification_evidence_sha256,
    predecessor.cohort_view_version,
    predecessor.cohort_evidence_sha256,
    correction_set.team_key, target_proposal_hash,
    correction_set.correction_set_hash_after, promotion_reviewer
  from reporting.dashboard_bundle_context_v1 predecessor
  where predecessor.release_id = draft.predecessor_bundle_id;
  if not found then
    raise exception 'correction predecessor context is unavailable';
  end if;
  insert into reporting.correction_league_payloads_v1 (
    bundle_release_id, dashboard_payload
  ) values (
    new_release_id, draft.affected_league_after_payload
  );
  insert into reporting.correction_team_payloads_v1 (
    bundle_release_id, team_key, team_release_id,
    curated_build_id, dashboard_payload
  )
  select
    new_release_id, predecessor.team_key, predecessor.team_release_id,
    predecessor.curated_build_id,
    case
      when predecessor.team_key = correction_set.team_key
        then draft.affected_team_after_payload
      else predecessor.dashboard_payload
    end
  from reporting.dashboard_bundle_team_payloads_v1 predecessor
  where predecessor.bundle_release_id = draft.predecessor_bundle_id;

  update reporting.aggregate_releases
  set status = 'retired'
  where id = draft.predecessor_bundle_id
    and status = 'approved';
  if not found then
    raise exception 'approved predecessor changed during promotion';
  end if;
  update reporting.aggregate_releases
  set status = 'approved', approved_at = now()
  where id = new_release_id and status = 'draft';
  update audit.step_runs set ended_at = now() where id = step_id;
  update audit.pipeline_runs
  set status = 'succeeded', ended_at = now()
  where id = run_id;

  return jsonb_build_object(
    'release_id', new_release_id,
    'release_label', target_release_label,
    'proposal_hash', target_proposal_hash,
    'predecessor_bundle_id', draft.predecessor_bundle_id,
    'draft_bundle_sha256', draft.draft_bundle_sha256,
    'affected_team_count', affected_count,
    'reused_team_count', 16 - affected_count,
    'metric_change_detected', draft.metric_change_detected
  );
end;
$$;

create function reporting.rollback_row_correction_bundle_v1(
  target_release_label text,
  rollback_release_label text,
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
set search_path = pg_catalog, analysis, audit, processing, reporting
as $$
declare
  correction_context reporting.correction_release_context_v1%rowtype;
  correction_release reporting.aggregate_releases%rowtype;
  predecessor reporting.aggregate_releases%rowtype;
  season_value text;
  rollback_release_id uuid := gen_random_uuid();
  run_id uuid := gen_random_uuid();
  step_id uuid := gen_random_uuid();
begin
  if nullif(rollback_reviewer, '') is null
    or rollback_reviewer <> 'Abdel Babiker' then
    raise exception 'correction rollback requires Abdel Babiker as reviewer';
  end if;
  if nullif(rollback_release_label, '') is null
    or nullif(rollback_reason, '') is null
    or rollback_evidence_sha256 !~ '^[0-9a-f]{64}$'
    or nullif(rollback_operator, '') is null
    or nullif(rollback_code_version, '') is null
    or rollback_dependency_lock_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'correction rollback evidence or provenance is incomplete';
  end if;

  -- Resolve the season without a row lock, acquire the season lock first, then
  -- lock and revalidate releases in the same order as apply and promotion.
  select context.season into season_value
  from reporting.aggregate_releases release
  join reporting.dashboard_bundle_context_v1 context
    on context.release_id = release.id
  where release.release_label = target_release_label;
  if season_value is null then
    raise exception 'target correction release is unavailable';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('row-correction:' || season_value, 0)
  );

  select release.* into correction_release
  from reporting.aggregate_releases release
  where release.release_label = target_release_label
  for update;
  if not found or correction_release.status <> 'approved' then
    raise exception 'target correction release is not currently approved';
  end if;
  select context.* into correction_context
  from reporting.correction_release_context_v1 context
  where context.bundle_release_id = correction_release.id;
  if not found then
    raise exception 'target release is not a correction bundle';
  end if;
  if not exists (
    select 1
    from reporting.latest_approved_dashboard_bundle_v4 current_bundle
    where current_bundle.release_id = correction_release.id
  ) then
    raise exception 'target correction release is not the served bundle';
  end if;

  select release.* into predecessor
  from reporting.aggregate_releases release
  where release.id = correction_context.predecessor_bundle_id
  for update;
  if not found or predecessor.status <> 'retired' then
    raise exception 'retained predecessor is not available for rollback';
  end if;

  insert into audit.pipeline_runs (
    id, command, team, season, status, parameters,
    input_hash, output_hash, operator, code_version, dependency_lock_hash
  ) values (
    run_id, 'correction-rollback', 'URC Overall', season_value, 'started',
    jsonb_build_object(
      'correction_release_id', correction_release.id,
      'correction_release_label', correction_release.release_label,
      'predecessor_release_id', predecessor.id,
      'predecessor_release_label', predecessor.release_label,
      'reviewer', rollback_reviewer,
      'reason', rollback_reason,
      'evidence_sha256', rollback_evidence_sha256,
      'rollback_release_id', rollback_release_id,
      'rollback_release_label', rollback_release_label
    ),
    analysis.row_correction_bundle_hash_v1(correction_release.id),
    analysis.row_correction_bundle_hash_v1(predecessor.id),
    rollback_operator,
    rollback_code_version,
    rollback_dependency_lock_hash
  );
  insert into audit.step_runs (
    id, pipeline_run_id, step_name, step_version, reason_code,
    input_count, output_count, input_hash, output_hash
  ) values (
    step_id, run_id, 'restore_row_correction_predecessor',
    'row_correction_rollback_2026-07-26_v1',
    'row_correction_rollback', 1, 1,
    analysis.row_correction_bundle_hash_v1(correction_release.id),
    analysis.row_correction_bundle_hash_v1(predecessor.id)
  );

  insert into reporting.aggregate_releases (
    id, release_label, status, pipeline_run_id
  ) values (
    rollback_release_id, rollback_release_label, 'draft', run_id
  );
  insert into reporting.correction_rollback_context_v1 (
    bundle_release_id, rolled_back_release_id, restored_bundle_id,
    season, analysis_version, generated_at, expected_member_count,
    match_exposure_decision, decision_reviewer, decision_recorded_at,
    classification_view_version, classification_evidence_sha256,
    cohort_view_version, cohort_evidence_sha256,
    reason, evidence_sha256, operator, reviewer,
    code_version, dependency_lock_hash
  )
  select
    rollback_release_id, correction_release.id, predecessor.id,
    context.season, context.analysis_version, context.generated_at,
    context.expected_member_count, context.match_exposure_decision,
    context.decision_reviewer, context.decision_recorded_at,
    context.classification_view_version,
    context.classification_evidence_sha256,
    context.cohort_view_version, context.cohort_evidence_sha256,
    rollback_reason, rollback_evidence_sha256, rollback_operator,
    rollback_reviewer, rollback_code_version,
    rollback_dependency_lock_hash
  from reporting.dashboard_bundle_context_v1 context
  where context.release_id = predecessor.id;
  if not found then
    raise exception 'rollback predecessor context is unavailable';
  end if;
  insert into reporting.correction_league_payloads_v1 (
    bundle_release_id, dashboard_payload
  )
  select rollback_release_id, payload.dashboard_payload
  from reporting.dashboard_bundle_league_payloads_v1 payload
  where payload.release_id = predecessor.id;
  insert into reporting.correction_team_payloads_v1 (
    bundle_release_id, team_key, team_release_id,
    curated_build_id, dashboard_payload
  )
  select
    rollback_release_id, payload.team_key, payload.team_release_id,
    payload.curated_build_id, payload.dashboard_payload
  from reporting.dashboard_bundle_team_payloads_v1 payload
  where payload.bundle_release_id = predecessor.id;

  update reporting.aggregate_releases
  set status = 'retired'
  where id = correction_release.id and status = 'approved';
  if not found then
    raise exception 'served correction bundle changed during rollback';
  end if;
  update reporting.aggregate_releases
  set status = 'approved', approved_at = now()
  where id = rollback_release_id and status = 'draft';
  update audit.step_runs set ended_at = now() where id = step_id;
  update audit.pipeline_runs
  set status = 'succeeded', ended_at = now()
  where id = run_id;

  return jsonb_build_object(
    'retired_correction_release_id', correction_release.id,
    'rollback_release_id', rollback_release_id,
    'rollback_release_label', rollback_release_label,
    'restored_predecessor_release_id', predecessor.id,
    'restored_bundle_sha256',
      analysis.row_correction_bundle_hash_v1(rollback_release_id),
    'season', season_value,
    'active_correction_state_restored_from_predecessor', true
  );
end;
$$;

revoke execute on function reporting.promote_row_correction_v1(
  text, text, text
) from public, anon, authenticated;
revoke execute on function reporting.rollback_row_correction_bundle_v1(
  text, text, text, text, text, text, text, text
) from public, anon, authenticated;

create view reporting.latest_league_dashboard_v5
with (security_invoker = false, security_barrier = true) as
select
  bundle.season,
  (payload.dashboard_payload ->> 'team')::text as team,
  (payload.dashboard_payload ->> 'generated_at')::timestamptz as generated_at,
  payload.dashboard_payload -> 'analysis_window' as analysis_window,
  payload.dashboard_payload -> 'method' as method,
  payload.dashboard_payload -> 'coverage' as coverage,
  payload.dashboard_payload -> 'headline' as headline,
  payload.dashboard_payload -> 'setting_split' as setting_split,
  payload.dashboard_payload -> 'setting_metrics' as setting_metrics,
  payload.dashboard_payload -> 'monthly' as monthly,
  payload.dashboard_payload -> 'body_locations' as body_locations,
  payload.dashboard_payload -> 'injury_types' as injury_types,
  payload.dashboard_payload -> 'injury_profiles' as injury_profiles,
  analysis.injury_type_families_from_payload_v1(
    payload.dashboard_payload -> 'injury_profiles'
  ) as injury_type_families,
  payload.dashboard_payload -> 'severity_distribution'
    as severity_distribution,
  payload.dashboard_payload -> 'contact_distribution'
    as contact_distribution,
  payload.dashboard_payload -> 'prior_season' as prior_season,
  payload.dashboard_payload -> 'limitations' as limitations
from reporting.latest_approved_dashboard_bundle_v4 bundle
join reporting.dashboard_bundle_league_payloads_v1 payload
  on payload.release_id = bundle.release_id;

create view reporting.latest_team_dashboard_v5
with (security_invoker = false, security_barrier = true) as
select
  payload.team_key,
  bundle.season,
  (payload.dashboard_payload ->> 'team')::text as team,
  (payload.dashboard_payload ->> 'generated_at')::timestamptz as generated_at,
  payload.dashboard_payload -> 'analysis_window' as analysis_window,
  payload.dashboard_payload -> 'method' as method,
  payload.dashboard_payload -> 'coverage' as coverage,
  payload.dashboard_payload -> 'headline' as headline,
  payload.dashboard_payload -> 'setting_split' as setting_split,
  payload.dashboard_payload -> 'setting_metrics' as setting_metrics,
  payload.dashboard_payload -> 'monthly' as monthly,
  payload.dashboard_payload -> 'body_locations' as body_locations,
  payload.dashboard_payload -> 'injury_types' as injury_types,
  payload.dashboard_payload -> 'injury_profiles' as injury_profiles,
  analysis.injury_type_families_from_payload_v1(
    payload.dashboard_payload -> 'injury_profiles'
  ) as injury_type_families,
  payload.dashboard_payload -> 'severity_distribution'
    as severity_distribution,
  payload.dashboard_payload -> 'contact_distribution'
    as contact_distribution,
  payload.dashboard_payload -> 'prior_season' as prior_season,
  payload.dashboard_payload -> 'limitations' as limitations
from reporting.latest_approved_dashboard_bundle_v4 bundle
join reporting.dashboard_bundle_team_payloads_v1 payload
  on payload.bundle_release_id = bundle.release_id;

grant select on reporting.latest_league_dashboard_v5 to web_reader;
grant select on reporting.latest_team_dashboard_v5 to web_reader;

comment on table audit.correction_sets_v1 is
  'Append-only season-keyed optimistic-concurrency envelopes for exact existing-row corrections.';
comment on table audit.row_corrections_v1 is
  'Append-only typed row corrections. Supersession and compensation append successors; history is never deleted.';
comment on table processing.correction_drafts_v1 is
  'Audited SQL recomputation evidence: one affected team, pooled league, and 15 exact predecessor team hashes.';
comment on view analysis.row_correction_pending_candidate_v1 is
  'One pending proposal candidate per season, with the full immutable bundle, candidate hash, and unchanged-team proof.';
comment on function analysis.row_correction_preview_v1(jsonb) is
  'Read-only hypothetical overlay preview through the same versioned SQL dependency graph used by correction release candidates.';
comment on function reporting.promote_row_correction_v1(text, text, text) is
  'Atomic incremental promotion: one recomputed team, one pooled league payload, and 15 byte-identical predecessor team payloads.';
comment on view reporting.latest_approved_dashboard_bundle_v4 is
  'Correction-aware approved bundle selector. The current V5 V2 bundle is projected unchanged until an audited correction or rollback successor is approved.';
comment on view reporting.latest_team_dashboard_v5 is
  'Allowlisted team projection over immutable V2 or additive correction payload storage, with versioned injury-type display families.';
comment on view reporting.latest_league_dashboard_v5 is
  'Allowlisted pooled league projection over immutable V2 or additive correction payload storage, with versioned injury-type display families.';
