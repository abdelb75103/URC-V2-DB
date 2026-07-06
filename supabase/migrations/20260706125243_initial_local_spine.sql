create extension if not exists pgcrypto;

create schema if not exists ingestion;
create schema if not exists processing;
create schema if not exists audit;
create schema if not exists reporting;

revoke all on schema ingestion from anon, authenticated;
revoke all on schema processing from anon, authenticated;
revoke all on schema audit from anon, authenticated;
revoke all on schema reporting from anon, authenticated;

create table ingestion.source_files (
  id uuid primary key default gen_random_uuid(),
  team text not null,
  season text not null,
  file_name text not null,
  file_sha256 text not null,
  file_size_bytes bigint not null,
  intake_manifest jsonb not null default '{}'::jsonb,
  prepared_by text,
  prepared_at timestamptz,
  codebook_version text,
  secure_source_locator text,
  row_count integer,
  created_at timestamptz not null default now(),
  unique (team, season, file_sha256)
);

create table ingestion.source_rows (
  id uuid primary key default gen_random_uuid(),
  source_file_id uuid not null references ingestion.source_files(id),
  sheet_name text not null default 'file',
  source_row_number integer not null,
  raw_record_id text not null,
  row_sha256 text not null,
  source_values jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (source_file_id, sheet_name, source_row_number),
  unique (raw_record_id)
);

create table audit.reason_codes (
  code text primary key,
  description text not null,
  active boolean not null default true
);

insert into audit.reason_codes (code, description) values
  ('registered_source', 'Source file registered without row transformation.'),
  ('placeholder_step', 'Local pipeline smoke step; no analytical transformation.'),
  ('aggregate_release', 'Aggregate metric released for read-only website smoke path.')
on conflict (code) do nothing;

create table audit.pipeline_runs (
  id uuid primary key default gen_random_uuid(),
  command text not null,
  team text,
  season text,
  status text not null check (status in ('started', 'succeeded', 'failed')),
  parameters jsonb not null default '{}'::jsonb,
  code_version text,
  dependency_lock_hash text,
  input_hash text,
  output_hash text,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create table audit.step_runs (
  id uuid primary key default gen_random_uuid(),
  pipeline_run_id uuid not null references audit.pipeline_runs(id),
  step_name text not null,
  step_version text not null,
  reason_code text references audit.reason_codes(code),
  input_count integer,
  output_count integer,
  counts_by_team jsonb not null default '{}'::jsonb,
  input_hash text,
  output_hash text,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create table processing.record_versions (
  id uuid primary key default gen_random_uuid(),
  source_row_id uuid not null references ingestion.source_rows(id),
  step_run_id uuid references audit.step_runs(id),
  version_number integer not null,
  record_state jsonb not null default '{}'::jsonb,
  eligibility_status text not null default 'included',
  created_at timestamptz not null default now(),
  unique (source_row_id, version_number)
);

create table audit.record_events (
  id uuid primary key default gen_random_uuid(),
  step_run_id uuid references audit.step_runs(id),
  source_row_id uuid references ingestion.source_rows(id),
  field_name text,
  old_value jsonb,
  new_value jsonb,
  action text not null,
  reason_code text references audit.reason_codes(code),
  rationale text,
  rule_version text,
  review_status text not null default 'not_required',
  created_at timestamptz not null default now()
);

create table audit.adjudications (
  id uuid primary key default gen_random_uuid(),
  source_row_id uuid not null references ingestion.source_rows(id),
  field_name text not null,
  decision jsonb not null,
  rationale text not null,
  reviewer text not null,
  decided_at timestamptz not null default now(),
  consumed_by_step_run_id uuid references audit.step_runs(id)
);

create table reporting.aggregate_releases (
  id uuid primary key default gen_random_uuid(),
  release_label text not null,
  status text not null check (status in ('draft', 'approved', 'retired')) default 'draft',
  pipeline_run_id uuid references audit.pipeline_runs(id),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  unique (release_label)
);

create table reporting.team_metric_aggregates (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references reporting.aggregate_releases(id),
  team text not null,
  season text not null,
  metric_key text not null,
  metric_label text not null,
  scope text not null default 'team',
  value numeric,
  numerator numeric,
  denominator numeric,
  unit text,
  coverage_note text not null,
  suppressed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (release_id, team, season, metric_key, scope)
);

create view reporting.latest_team_metric_aggregates
with (security_invoker = true) as
select m.*
from reporting.team_metric_aggregates m
join reporting.aggregate_releases r on r.id = m.release_id
where r.status = 'approved'
  and r.approved_at = (
    select max(r2.approved_at)
    from reporting.aggregate_releases r2
    where r2.status = 'approved'
  );

create view public.dashboard_team_metrics
with (security_invoker = true) as
select
  team,
  season,
  metric_key,
  metric_label,
  scope,
  value,
  numerator,
  denominator,
  unit,
  coverage_note,
  suppressed
from reporting.latest_team_metric_aggregates;

alter table ingestion.source_files enable row level security;
alter table ingestion.source_rows enable row level security;
alter table processing.record_versions enable row level security;
alter table audit.reason_codes enable row level security;
alter table audit.pipeline_runs enable row level security;
alter table audit.step_runs enable row level security;
alter table audit.record_events enable row level security;
alter table audit.adjudications enable row level security;
alter table reporting.aggregate_releases enable row level security;
alter table reporting.team_metric_aggregates enable row level security;

revoke all on public.dashboard_team_metrics from anon, authenticated;
