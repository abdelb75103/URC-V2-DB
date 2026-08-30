-- Private additive successor for the accepted 2025-26 injury adjudication delta.
-- The load clones the immutable v2 predecessor in-database and replaces only
-- checksum-bound changed rows. It creates no reporting or release surface.

create table lineage.injury_classification_rules_v3 (
  rule_version text primary key,
  predecessor_rule_version text not null
    references lineage.injury_classification_rules_v2(rule_version),
  season text not null unique check (season = '2025-26'),
  precedence jsonb not null check (jsonb_typeof(precedence) = 'array'),
  field_contract jsonb not null check (jsonb_typeof(field_contract) = 'object'),
  method_note text not null,
  accepted_at timestamptz not null default now()
);

insert into lineage.injury_classification_rules_v3 (
  rule_version,
  predecessor_rule_version,
  season,
  precedence,
  field_contract,
  method_note
) values (
  'urc_2025_26_injury_review_triage_2026_08_30_v5',
  'urc_2025_26_injury_classification_2026_08_29_v2',
  '2025-26',
  '[
    "Usable zero Days Injured is Medical Attention before a source Time Loss display label. A same-day or next-day return with zero reported days remains zero-day Medical Attention.",
    "For Irish-team sources without return dates, reported Days Injured is authoritative: zero is Medical Attention and a positive value is Time Loss. Missing Irish return dates stay missing.",
    "Explicit source Time Loss or Medical Attention classification wins when the accepted zero-day and source-specific rules do not apply.",
    "Included non-Scottish date-duration disagreements use ordinary return date minus injury date. Scottish reported duration is retained within plus or minus one day, otherwise dates win.",
    "Explicit red, orange, unavailable or modified participation is Time Loss; green-only or full participation is Medical Attention.",
    "Positive clinical duration alone never overrides explicit Medical Attention and never independently defines Time Loss.",
    "Missing duration is not zero.",
    "An open non-Medical-Attention record without unrestricted-participation evidence is Time Loss, with null return date and null Time Loss days.",
    "A valid Fit For Selection Date later than Date Injured is direct participation-restriction evidence when stronger contrary evidence is absent.",
    "An audited static Zebre closing date on a non-ongoing record is direct restriction evidence even when formula-driven Days out is blank.",
    "Resolved source disagreements stay in audit lineage but do not remain active adjudications.",
    "Excluded rows are source-only and audit-only unless eligibility is reconsidered."
  ]'::jsonb,
  '{
    "classification":"separate",
    "clinical_duration_days":"separate",
    "time_loss_days":"separate",
    "classification_basis":"required",
    "clinical_duration_basis":"required",
    "return_date_basis":"required",
    "open_status":"required",
    "participation_restriction_evidence":"required",
    "unrestricted_participation_evidence":"required",
    "medical_attention_time_loss_days":null,
    "open_fallback_time_loss_days":null
  }'::jsonb,
  'Accepted 2025-26 review-triage successor. It changes derived classification and duration evidence only and creates no dashboard or release access.'
);

create table lineage.injury_master_versions_v3 (
  id uuid primary key,
  predecessor_version_id uuid not null unique
    references lineage.injury_master_versions_v2(id),
  season text not null unique check (season = '2025-26'),
  version_label text not null unique,
  status text not null check (status = 'valid_ingested_successor'),
  classification_rule_version text not null
    references lineage.injury_classification_rules_v3(rule_version),
  migration_version text not null,
  migration_sha256 text not null check (migration_sha256 ~ '^[0-9a-f]{64}$'),
  master_csv_sha256 text not null check (master_csv_sha256 ~ '^[0-9a-f]{64}$'),
  master_workbook_sha256 text not null check (master_workbook_sha256 ~ '^[0-9a-f]{64}$'),
  inclusion_csv_sha256 text not null check (inclusion_csv_sha256 ~ '^[0-9a-f]{64}$'),
  classification_evidence_sha256 text not null check (classification_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  manifest_sha256 text not null check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  source_bundle_sha256 text not null check (source_bundle_sha256 ~ '^[0-9a-f]{64}$'),
  master_json_sha256 text not null check (master_json_sha256 ~ '^[0-9a-f]{64}$'),
  inclusion_json_sha256 text not null check (inclusion_json_sha256 ~ '^[0-9a-f]{64}$'),
  delta_payload_sha256 text not null check (delta_payload_sha256 ~ '^[0-9a-f]{64}$'),
  delta_evidence_sha256 text not null check (delta_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  master_row_count integer not null check (master_row_count = 2993),
  included_row_count integer not null check (included_row_count = 1923),
  excluded_row_count integer not null check (excluded_row_count = 1070),
  dashboard_injury_row_count integer not null check (dashboard_injury_row_count = 1484),
  team_count integer not null check (team_count = 16),
  affected_row_count integer not null check (affected_row_count > 0),
  changed_master_row_count integer not null check (changed_master_row_count >= 0),
  changed_classification_row_count integer not null check (changed_classification_row_count >= 0),
  changed_duration_row_count integer not null check (changed_duration_row_count >= 0),
  classification_contract jsonb not null check (jsonb_typeof(classification_contract) = 'object'),
  summary jsonb not null check (jsonb_typeof(summary) = 'object'),
  loaded_at timestamptz not null default now(),
  loaded_by text not null default current_user,
  check (master_row_count = included_row_count + excluded_row_count),
  check (dashboard_injury_row_count <= included_row_count)
);

create table lineage.injury_master_rows_v3 (
  version_id uuid not null references lineage.injury_master_versions_v3(id),
  source_row integer not null check (source_row >= 2),
  team_key text not null references reporting.teams(team_key),
  source_group text not null,
  source_task_id uuid not null,
  source_file_name text not null check (source_file_name = regexp_replace(source_file_name, '^.*/', '')),
  source_artifact_sha256 text not null check (source_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  source_row_number text not null,
  source_locator text not null,
  source_artifact_row_sha256 text not null check (source_artifact_row_sha256 ~ '^[0-9a-f]{64}$'),
  final_master_row_sha256 text not null check (final_master_row_sha256 ~ '^[0-9a-f]{64}$'),
  row_values jsonb not null check (lineage.valid_urc_injury_master_row_v2(row_values)),
  excluded boolean not null,
  exclusion_reason text,
  qualifying_source_classification text check (
    qualifying_source_classification is null
    or qualifying_source_classification in ('Time Loss', 'Medical Attention')
  ),
  final_classification text not null check (
    final_classification in ('Time Loss', 'Medical Attention', 'unclassified')
  ),
  classification_basis text not null check (classification_basis in (
    'excluded_not_adjudicated',
    'excluded_source_classification',
    'explicit_source_classification',
    'open_record_fallback',
    'reported_zero_days',
    'same_or_next_day_return',
    'source_fit_for_selection_date',
    'source_participation_restriction',
    'source_reported_zero_days',
    'source_static_closing_date',
    'source_unrestricted_participation'
  )),
  clinical_duration_days integer check (clinical_duration_days >= 0),
  clinical_duration_basis text not null check (clinical_duration_basis in (
    'source_reported', 'derived_from_dates', 'resolved_from_dates', 'missing'
  )),
  time_loss_days integer check (time_loss_days > 0),
  return_date date,
  return_date_basis text not null check (return_date_basis in (
    'source_confirmed_return_date',
    'source_fit_for_selection_date',
    'derived_zero_day_return',
    'missing',
    'missing_open_record'
  )),
  open_status boolean not null,
  participation_restriction_evidence boolean,
  unrestricted_participation_evidence boolean not null,
  source_conflict boolean not null,
  review_required boolean not null,
  review_reasons jsonb not null default '[]'::jsonb check (jsonb_typeof(review_reasons) = 'array'),
  derived_fields text[] not null default '{}',
  verified_urc_fixture boolean not null,
  primary key (version_id, source_row),
  check (excluded = (exclusion_reason is not null)),
  check (time_loss_days is null or final_classification = 'Time Loss'),
  check (final_classification <> 'Medical Attention' or time_loss_days is null),
  check (not review_required or not excluded),
  check (
    classification_basis <> 'open_record_fallback'
    or (
      final_classification = 'Time Loss'
      and open_status
      and return_date is null
      and time_loss_days is null
    )
  ),
  check (
    not (
      open_status
      and final_classification = 'Time Loss'
      and not unrestricted_participation_evidence
    )
    or (
      return_date is null
      and return_date_basis = 'missing_open_record'
      and time_loss_days is null
    )
  )
);

create index injury_master_rows_v3_version_team
  on lineage.injury_master_rows_v3(version_id, team_key);
create index injury_master_rows_v3_version_classification
  on lineage.injury_master_rows_v3(version_id, final_classification);

create table lineage.injury_inclusion_rows_v3 (
  version_id uuid not null references lineage.injury_master_versions_v3(id),
  inclusion_row integer not null check (inclusion_row >= 2),
  source_row integer not null,
  team_key text not null references reporting.teams(team_key),
  row_values jsonb not null check (lineage.valid_urc_injury_master_row_v2(row_values)),
  row_sha256 text not null check (row_sha256 ~ '^[0-9a-f]{64}$'),
  dashboard_eligible boolean not null,
  dashboard_eligibility_reason text not null check (dashboard_eligibility_reason in (
    'injury_record', 'illness_record_not_in_injury_cohort'
  )),
  primary key (version_id, inclusion_row),
  unique (version_id, source_row),
  foreign key (version_id, source_row)
    references lineage.injury_master_rows_v3(version_id, source_row),
  check (dashboard_eligible = (dashboard_eligibility_reason = 'injury_record'))
);

create index injury_inclusion_rows_v3_version_team
  on lineage.injury_inclusion_rows_v3(version_id, team_key);

alter table lineage.injury_classification_rules_v3 enable row level security;
alter table lineage.injury_master_versions_v3 enable row level security;
alter table lineage.injury_master_rows_v3 enable row level security;
alter table lineage.injury_inclusion_rows_v3 enable row level security;

revoke all on lineage.injury_classification_rules_v3 from public, anon, authenticated, web_reader;
revoke all on lineage.injury_master_versions_v3 from public, anon, authenticated, web_reader;
revoke all on lineage.injury_master_rows_v3 from public, anon, authenticated, web_reader;
revoke all on lineage.injury_inclusion_rows_v3 from public, anon, authenticated, web_reader;

create trigger injury_classification_rules_v3_immutable
before update or delete on lineage.injury_classification_rules_v3
for each row execute function lineage.reject_urc_injury_v2_mutation();
create trigger injury_master_versions_v3_immutable
before update or delete on lineage.injury_master_versions_v3
for each row execute function lineage.reject_urc_injury_v2_mutation();
create trigger injury_master_rows_v3_immutable
before update or delete on lineage.injury_master_rows_v3
for each row execute function lineage.reject_urc_injury_v2_mutation();
create trigger injury_inclusion_rows_v3_immutable
before update or delete on lineage.injury_inclusion_rows_v3
for each row execute function lineage.reject_urc_injury_v2_mutation();

comment on table lineage.injury_classification_rules_v3 is
  'Accepted 2025-26 zero-day and date-duration successor. Private and season-specific.';
comment on table lineage.injury_master_versions_v3 is
  'Checksum-bound additive successor cloned from one immutable v2 predecessor.';
comment on table lineage.injury_master_rows_v3 is
  'Complete v3 successor rows. The ingest replaces only checksum-bound changed row states.';
comment on table lineage.injury_inclusion_rows_v3 is
  'Unchanged inclusion membership with row values projected from the v3 successor master.';
