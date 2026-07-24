-- Phase 4 (docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md): restate the 2024-25
-- injury lineage in the database. New `lineage` schema holding the v5 master
-- (append-only source rows with row-level exclusions), the ordered decision
-- ledger, and the verified row-level bridge from master rows to the already
-- ingested source rows / curated injuries. Additive: no frozen view, table,
-- or snapshot is changed. Same revoke/RLS posture as every other schema.

create schema if not exists lineage;
revoke all on schema lineage from anon, authenticated;

insert into audit.reason_codes (code, description) values
  (
    'lineage_baseline_load',
    'Checksummed load of a reviewed season master baseline plus its ordered '
    'decision ledger into the lineage schema (Phase 4 restatement). '
    'Master rows are append-only; exclusions carry controlled reasons; all '
    'value cleaning and inference stays in the ledger, never in master.'
  ),
  (
    'lineage_master_source_bridge',
    'Verified one-to-one mapping between reviewed master workbook rows and '
    'registered ingestion.source_rows / curated.injuries rows of the pinned '
    'league member builds. Every assignment is deterministic or confined to '
    'byte-identical duplicate source rows; ambiguity outside identical rows '
    'is a review case, never silently matched.'
  )
on conflict (code) do nothing;

-- One row per loaded season baseline: binds the exact artifact hashes the
-- load was checksummed against (master v5 JSON, ledger, accepted inclusion
-- CSV, retained source-row mapping).
create table lineage.baselines (
  season text primary key,
  baseline_identity text not null,
  baseline_record jsonb not null check (jsonb_typeof(baseline_record) = 'object'),
  baseline_record_sha256 text not null check (baseline_record_sha256 ~ '^[0-9a-f]{64}$'),
  master_json_sha256 text not null check (master_json_sha256 ~ '^[0-9a-f]{64}$'),
  ledger_sha256 text not null check (ledger_sha256 ~ '^[0-9a-f]{64}$'),
  inclusion_csv_sha256 text not null check (inclusion_csv_sha256 ~ '^[0-9a-f]{64}$'),
  source_row_mapping_sha256 text not null check (source_row_mapping_sha256 ~ '^[0-9a-f]{64}$'),
  pipeline_run_id uuid references audit.pipeline_runs(id),
  loaded_at timestamptz not null default now()
);

-- Every standardized source row of the season master, append-only. Values
-- are the serialized cell strings the accepted replay/export path produces
-- (tools/replay.py serialize_master_value), keyed by the 28 canonical
-- headers. Exclusions are row-level decisions with controlled reasons; a
-- row is excluded exactly when its Exclusion Reason value is non-blank.
create table lineage.master_rows (
  season text not null references lineage.baselines(season),
  source_row integer not null check (source_row >= 2),
  team text not null,
  row_values jsonb not null check (jsonb_typeof(row_values) = 'object'),
  excluded boolean not null,
  exclusion_reason text,
  primary key (season, source_row),
  check (excluded = (exclusion_reason is not null))
);

create index master_rows_season_team on lineage.master_rows (season, team);

-- Ordered, replayable decision ledger: one row per step.
create table lineage.ledger_steps (
  season text not null references lineage.baselines(season),
  step_order integer not null check (step_order >= 1),
  rule_version text not null,
  applied_at timestamptz not null,
  carry_forward text not null,
  description text not null,
  evidence jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence) = 'array'),
  primary key (season, step_order),
  unique (season, rule_version)
);

-- One row per ledger entry, in replay order within its step. Removal
-- entries (is_removal) drop the row from the inclusion selection; value
-- entries override one field. Old values are always preserved.
create table lineage.ledger_entries (
  season text not null references lineage.baselines(season),
  step_order integer not null,
  entry_index integer not null check (entry_index >= 0),
  source_row integer not null,
  team text not null,
  player_id text not null,
  field text not null,
  old_value text,
  new_value text,
  action text not null,
  reason text not null,
  evidence_origin text,
  value_origin text,
  is_removal boolean not null,
  primary key (season, step_order, entry_index),
  foreign key (season, step_order) references lineage.ledger_steps(season, step_order),
  foreign key (season, source_row) references lineage.master_rows(season, source_row)
);

create index ledger_entries_row_field
  on lineage.ledger_entries (season, source_row, field, step_order, entry_index);

-- Verified 1:1 bridge from master workbook rows to the registered source
-- rows and curated injuries of the pinned league member builds. This is how
-- the restated lineage reuses the approved IOC bucket mappings and OSIICS
-- classification evidence without re-deriving clinical facts. match_method
-- records how the pair was established; identical-duplicate assignments are
-- confined to byte-identical source rows and marked as such.
create table lineage.master_source_bridge (
  season text not null references lineage.baselines(season),
  source_row integer not null,
  team_key text not null references reporting.teams(team_key),
  source_row_id uuid not null references ingestion.source_rows(id),
  injury_id uuid not null references curated.injuries(id),
  curated_build_id uuid not null references curated.builds(id),
  match_method text not null,
  match_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(match_evidence) = 'object'),
  primary key (season, source_row),
  unique (season, source_row_id),
  unique (season, injury_id),
  foreign key (season, source_row) references lineage.master_rows(season, source_row)
);

alter table lineage.baselines enable row level security;
alter table lineage.master_rows enable row level security;
alter table lineage.ledger_steps enable row level security;
alter table lineage.ledger_entries enable row level security;
alter table lineage.master_source_bridge enable row level security;

-- The loaded baseline, master, ledger, and bridge are immutable snapshots
-- of reviewed artifacts: corrections happen in the file-based ledger and
-- re-enter through a fresh checksummed load, never by editing rows here.
create function lineage.reject_lineage_mutation()
returns trigger language plpgsql as $$
begin
  raise exception '% is immutable; author a ledger decision and reload the season baseline', tg_table_name;
end;
$$;
revoke execute on function lineage.reject_lineage_mutation() from public;

create trigger lineage_baselines_immutable
before update or delete on lineage.baselines
for each row execute function lineage.reject_lineage_mutation();
create trigger lineage_master_rows_immutable
before update or delete on lineage.master_rows
for each row execute function lineage.reject_lineage_mutation();
create trigger lineage_ledger_steps_immutable
before update or delete on lineage.ledger_steps
for each row execute function lineage.reject_lineage_mutation();
create trigger lineage_ledger_entries_immutable
before update or delete on lineage.ledger_entries
for each row execute function lineage.reject_lineage_mutation();
create trigger lineage_master_source_bridge_immutable
before update or delete on lineage.master_source_bridge
for each row execute function lineage.reject_lineage_mutation();

comment on schema lineage is
  'Restated 2024-25 injury lineage (Phase 4): v5 master rows, ordered decision ledger, and the verified bridge to ingested source rows.';
comment on table lineage.master_rows is
  'Append-only reviewed master rows (3,060 for 2024-25); excluded rows carry controlled reasons; values are the serialized replay cell strings.';
comment on table lineage.ledger_entries is
  'Replayable row-level decisions: value overrides and inclusion removals with old/new values, action, reason, and origin preserved.';
comment on table lineage.master_source_bridge is
  'Verified 1:1 master-row to source-row/curated-injury mapping used to reuse approved IOC and OSIICS classification without re-deriving clinical facts.';
