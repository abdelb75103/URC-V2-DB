-- First valid 2025-26 injury lineage. This is an additive private successor
-- to the failed Year Two intake evidence. It does not change historical
-- ingestion rows, curated builds, exposure, reporting readers or releases.

create schema if not exists lineage;
revoke all on schema lineage from anon, authenticated, web_reader;

create table lineage.injury_classification_rules_v2 (
  rule_version text primary key,
  season text not null unique check (season = '2025-26'),
  precedence jsonb not null check (jsonb_typeof(precedence) = 'array'),
  field_contract jsonb not null check (jsonb_typeof(field_contract) = 'object'),
  method_note text not null,
  accepted_at timestamptz not null default now()
);

insert into lineage.injury_classification_rules_v2 (
  rule_version,
  season,
  precedence,
  field_contract,
  method_note
) values (
  'urc_2025_26_injury_classification_2026_08_29_v2',
  '2025-26',
  '[
    "Explicit source Time Loss or Medical Attention classification wins.",
    "Explicit red, orange, unavailable or modified participation is Time Loss; green-only or full participation is Medical Attention.",
    "A reported or validly derived zero-day duration is Medical Attention when no stronger contradictory evidence exists; a missing return date is derived as the injury date.",
    "Positive clinical duration alone never overrides explicit Medical Attention and never independently defines Time Loss.",
    "Missing duration is not zero.",
    "An open non-Medical-Attention record without unrestricted-participation evidence is Time Loss, with null return date and null Time Loss days.",
    "Source conflicts are retained for adjudication and never silently recast."
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
  'Season-specific successor used only for the corrected first-valid 2025-26 injury lineage. It creates no dashboard or release surface.'
);

create function lineage.valid_urc_injury_master_row_v2(row_values jsonb)
returns boolean
language sql
immutable
strict
as $$
  select jsonb_typeof(row_values) = 'object'
    and (
      select array_agg(key order by key)
      from jsonb_object_keys(row_values) key
    ) = array[
      'Body Part',
      'Confirmed Return Date',
      'Date Injured',
      'Days Injured',
      'Description',
      'Diagnosis',
      'Exclusion Reason',
      'Fit For Selection Date',
      'Illness Code',
      'Injury Surface Type',
      'Injury Tissue Type/s',
      'Is Contact',
      'Match Type',
      'Mechanism Notes',
      'Mechanism of Injury',
      'Nature of onset',
      'Occasion category',
      'Orchard Code',
      'PlayerID',
      'Problem type',
      'Received At Position',
      'Received/Injured In Team',
      'Recurrence',
      'Reporting At Club',
      'Required Surgery',
      'Side',
      'Specific Diagnosis',
      'Team',
      'TimeLoss vs Medical Attention'
    ]::text[];
$$;
revoke execute on function lineage.valid_urc_injury_master_row_v2(jsonb)
  from public, anon, authenticated, web_reader;

create table lineage.injury_master_versions_v2 (
  id uuid primary key,
  season text not null unique check (season = '2025-26'),
  version_label text not null unique check (version_label !~* '(^|[-_])v1($|[-_])'),
  status text not null check (status = 'valid_ingested'),
  classification_rule_version text not null
    references lineage.injury_classification_rules_v2(rule_version),
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
  load_payload_sha256 text not null check (load_payload_sha256 ~ '^[0-9a-f]{64}$'),
  master_row_count integer not null check (master_row_count > 0),
  included_row_count integer not null check (included_row_count >= 0),
  excluded_row_count integer not null check (excluded_row_count >= 0),
  dashboard_injury_row_count integer not null check (dashboard_injury_row_count >= 0),
  team_count integer not null check (team_count = 16),
  source_manifest jsonb not null check (jsonb_typeof(source_manifest) = 'object'),
  classification_contract jsonb not null check (jsonb_typeof(classification_contract) = 'object'),
  summary jsonb not null check (jsonb_typeof(summary) = 'object'),
  loaded_at timestamptz not null default now(),
  loaded_by text not null default current_user,
  check (master_row_count = included_row_count + excluded_row_count),
  check (dashboard_injury_row_count <= included_row_count)
);

create table lineage.injury_master_rows_v2 (
  version_id uuid not null references lineage.injury_master_versions_v2(id),
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
    'explicit_source_classification',
    'source_participation_restriction',
    'source_unrestricted_participation',
    'reported_zero_days',
    'derived_zero_days',
    'open_record_fallback',
    'unclassified_no_qualifying_evidence',
    'source_conflict_preserved'
  )),
  clinical_duration_days integer check (clinical_duration_days >= 0),
  clinical_duration_basis text not null check (clinical_duration_basis in (
    'source_reported', 'derived_from_dates', 'missing'
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
  check (not source_conflict or review_required),
  check (
    classification_basis <> 'source_participation_restriction'
    or participation_restriction_evidence is true
  ),
  check (
    classification_basis <> 'source_unrestricted_participation'
    or participation_restriction_evidence is false
  ),
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

create index injury_master_rows_v2_version_team
  on lineage.injury_master_rows_v2(version_id, team_key);
create index injury_master_rows_v2_version_classification
  on lineage.injury_master_rows_v2(version_id, final_classification);

create table lineage.injury_inclusion_rows_v2 (
  version_id uuid not null references lineage.injury_master_versions_v2(id),
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
    references lineage.injury_master_rows_v2(version_id, source_row),
  check (dashboard_eligible = (dashboard_eligibility_reason = 'injury_record'))
);

create index injury_inclusion_rows_v2_version_team
  on lineage.injury_inclusion_rows_v2(version_id, team_key);

alter table lineage.injury_classification_rules_v2 enable row level security;
alter table lineage.injury_master_versions_v2 enable row level security;
alter table lineage.injury_master_rows_v2 enable row level security;
alter table lineage.injury_inclusion_rows_v2 enable row level security;

revoke all on lineage.injury_classification_rules_v2 from public, anon, authenticated, web_reader;
revoke all on lineage.injury_master_versions_v2 from public, anon, authenticated, web_reader;
revoke all on lineage.injury_master_rows_v2 from public, anon, authenticated, web_reader;
revoke all on lineage.injury_inclusion_rows_v2 from public, anon, authenticated, web_reader;

create function lineage.reject_urc_injury_v2_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is immutable; ingest a new checksum-bound successor', tg_table_name;
end;
$$;
revoke execute on function lineage.reject_urc_injury_v2_mutation()
  from public, anon, authenticated, web_reader;

create trigger injury_classification_rules_v2_immutable
before update or delete on lineage.injury_classification_rules_v2
for each row execute function lineage.reject_urc_injury_v2_mutation();
create trigger injury_master_versions_v2_immutable
before update or delete on lineage.injury_master_versions_v2
for each row execute function lineage.reject_urc_injury_v2_mutation();
create trigger injury_master_rows_v2_immutable
before update or delete on lineage.injury_master_rows_v2
for each row execute function lineage.reject_urc_injury_v2_mutation();
create trigger injury_inclusion_rows_v2_immutable
before update or delete on lineage.injury_inclusion_rows_v2
for each row execute function lineage.reject_urc_injury_v2_mutation();

comment on table lineage.injury_classification_rules_v2 is
  'Private season-specific classification successor. Positive clinical duration alone is not the Time Loss definition.';
comment on table lineage.injury_master_versions_v2 is
  'Checksum-bound first valid 2025-26 injury master versions, including the executor-attested load-payload digest. No dashboard reader grant or release semantics.';
comment on table lineage.injury_master_rows_v2 is
  'Complete genuine 2025-26 injury and illness source/master rows, including exclusions, with classification evidence kept outside the 29-column master shape.';
comment on table lineage.injury_inclusion_rows_v2 is
  'Separate accepted inclusion layer. Illness is retained but explicitly marked outside the dashboard injury cohort.';
