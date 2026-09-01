import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LEDGER_PATH = 'docs/evidence/diagnosis-families/diagnosis_family_adjudication_v1.json';
const EVIDENCE_2024_PATH = 'docs/evidence/urc_2024-25_specific_diagnosis_evidence.json';
export const OUTPUT = 'supabase/migrations/20260901010000_urc_diagnosis_family_reporting_successor.sql';

const readJson = (relativePath) => JSON.parse(fs.readFileSync(path.join(ROOT, relativePath), 'utf8'));
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const fileSha256 = (relativePath) => sha256(fs.readFileSync(path.join(ROOT, relativePath)));
const quote = (value) => value === null ? 'null' : `'${String(value).replaceAll("'", "''")}'`;
const slug = (value) => value.normalize('NFKD')
  .replace(/[^\x00-\x7F]/g, '')
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '_')
  .replace(/^_+|_+$/g, '');
const subtypeCode = (label) => `subtype_${slug(label)}_${sha256(label).slice(0, 10)}`;

const renderValues = (rows) => rows.map((row, index) =>
  `  (${row.map(quote).join(', ')})${index === rows.length - 1 ? ';' : ','}`
).join('\n');

export const buildSql = () => {
  const ledger = readJson(LEDGER_PATH);
  const evidence2024 = readJson(EVIDENCE_2024_PATH);
  const decisions2024 = new Map(
    ledger.rows.filter((row) => row.season === '2024-25').map((row) => [row.source_label, row]),
  );
  const rows2024 = evidence2024.rows
    .filter((row) => row.injury_metric_eligible)
    .map((row) => {
      const decision = decisions2024.get(row.specific_diagnosis_source_label);
      if (!decision?.diagnosis_group_code || !decision?.diagnosis_group_label) {
        throw new Error(`Missing 2024 injury family decision: ${row.specific_diagnosis_source_label}`);
      }
      return [
        row.master_source_row,
        row.source_row_sha256,
        row.specific_diagnosis_source_label,
        subtypeCode(row.specific_diagnosis_source_label),
        decision.diagnosis_group_code,
        decision.diagnosis_group_label,
        decision.review_status,
      ];
    })
    .sort((a, b) => a[0] - b[0]);
  const illnessRows2024 = evidence2024.rows
    .filter((row) => row.problem_type_code === 'illness')
    .map((row) => {
      const decision = decisions2024.get(row.specific_diagnosis_source_label);
      if (!decision?.source_group_code || !decision?.source_group_label) {
        throw new Error(`Missing 2024 illness profile decision: ${row.specific_diagnosis_source_label}`);
      }
      return [
        row.master_source_row,
        row.source_row_sha256,
        row.specific_diagnosis_source_label,
        decision.source_group_code,
        decision.source_group_label,
      ];
    })
    .sort((a, b) => a[0] - b[0]);
  const rows2025 = ledger.rows
    .filter((row) => row.season === '2025-26')
    .map((row) => [
        row.source_label,
        row.source_profile_code,
        row.diagnosis_group_code,
        row.diagnosis_group_label,
        row.problem_type_scope,
        row.review_status,
        row.row_filter_required,
      ])
    .sort((a, b) => a[0].localeCompare(b[0]));
  const illnessRows2025 = ledger.illness_mapping['2025-26_source_label_mapping']
    .map((row) => [
      row.source_label,
      row.illness_group_code,
      row.illness_group_label,
      row.review_status,
    ])
    .sort((a, b) => a[0].localeCompare(b[0]));

  if (rows2024.length !== 1660 || illnessRows2024.length !== 392
      || rows2025.length !== 420 || illnessRows2025.length !== 113) {
    throw new Error(
      `Unexpected mapping cardinality: ${rows2024.length}/${illnessRows2024.length}/${rows2025.length}/${illnessRows2025.length}`,
    );
  }
  if (new Set(illnessRows2025.map((row) => row[0])).size !== 113
      || new Set(illnessRows2025.map((row) => `${row[1]}\0${row[2]}`)).size !== 50) {
    throw new Error('Unexpected 2025-26 illness label or group cardinality');
  }
  if (ledger.illness_mapping['2025-26_source_label_count'] !== 113
      || ledger.illness_mapping['2025-26_source_label_mapping_sha256']
        !== ledger.mapping_hashes.illness_mapping_rows_sha256
      || ledger.illness_mapping['2025-26_inventory_reconciliation'].recorded_illnesses !== 439
      || ledger.illness_mapping['2025-26_inventory_reconciliation'].known_duration_illnesses !== 202
      || ledger.illness_mapping['2025-26_inventory_reconciliation'].days_lost !== 927) {
    throw new Error('Unexpected 2025-26 illness mapping evidence');
  }

  const ledgerSha = fileSha256(LEDGER_PATH);
  const evidenceSha = fileSha256(EVIDENCE_2024_PATH);
  const mappingSha = ledger.mapping_hashes.mapping_rows_sha256;
  const completeLedgerSha = ledger.mapping_hashes.complete_ledger_sha256;
  const illnessInventorySha = ledger.source_artifacts['2025-26_illness_inventory'].sha256;
  if (fileSha256(ledger.source_artifacts['2025-26_illness_inventory'].path)
      !== illnessInventorySha) {
    throw new Error('2025-26 illness inventory hash drifted');
  }
  const illnessMappingSha = ledger.mapping_hashes.illness_mapping_rows_sha256;
  const illnessLedgerSha = ledger.mapping_hashes.illness_ledger_sha256;
  const values2024 = renderValues(rows2024);
  const illnessValues2024 = renderValues(illnessRows2024);
  const values2025 = renderValues(rows2025);
  const illnessValues2025 = renderValues(illnessRows2025);

  return `begin;

-- Add one governed injury and illness presentation over the exact approved
-- 2024-25 and 2025-26 immutable bundles. Source rows and release rows remain
-- unchanged. Canonical families replace only the diagnosis dimension. The
-- current 1,545-row 2025-26 cohort supplies setting severity and the qualified
-- preliminary_monthly_rates; every other injury section remains unchanged.
-- Separate illness rows supply Overall illness_profiles and illness_summary.

do $$
begin
  if not exists (
    select 1
    from reporting.latest_approved_dashboard_bundle_v4 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join reporting.dashboard_bundle_league_payloads_v1 payload
      on payload.release_id = latest.release_id
    where latest.season = '2024-25'
      and latest.release_id = '0f0def1e-021f-471f-979f-6d73d98859c4'::uuid
      and release.release_label = 'urc-2024-25-v5-a80040f6afaa-a1'
      and payload.payload_sha256 =
        '4517f50bdf03688c087a34062071d97bd635576011e02f6f8ca5d1dc69a156ae'
      and (select count(*) from reporting.dashboard_bundle_team_payloads_v1 team
        where team.bundle_release_id = latest.release_id) = 16
  ) or not exists (
    select 1
    from reporting.latest_approved_league_bundle_v6 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join audit.pipeline_runs run on run.id = release.pipeline_run_id
    join reporting.league_release_payloads_v6 payload
      on payload.release_id = latest.release_id
    where latest.season = '2025-26'
      and latest.release_id = 'f1d9c2cc-f70c-4dcc-a18d-3f2dc92d4cfc'::uuid
      and release.release_label = 'urc-2025-26-v6-b2bae1158257-a2'
      and run.output_hash =
        'b2bae1158257976b8e7da2385a7df065a2cd621492017bfb192a293ac16a1f41'
      and payload.payload_sha256 =
        '4eafb2dc32d155c69d968e833a354c145e08e0f13356b300234cefc1e2889c05'
      and (select count(*) from reporting.team_dashboard_payloads_v2 team
        where team.bundle_release_id = latest.release_id) = 16
  ) then
    raise exception 'Diagnosis-family successor approved bundle identity drift';
  end if;
end;
$$;

create table audit.urc_diagnosis_family_adjudication_evidence_v1 (
  adjudication_version text primary key check (
    adjudication_version = 'urc_diagnosis_family_adjudication_v1'
  ),
  ledger_sha256 text not null check (ledger_sha256 = '${ledgerSha}'),
  mapping_rows_sha256 text not null check (mapping_rows_sha256 = '${mappingSha}'),
  complete_ledger_sha256 text not null check (complete_ledger_sha256 = '${completeLedgerSha}'),
  illness_inventory_sha256 text not null check (
    illness_inventory_sha256 = '${illnessInventorySha}'
  ),
  illness_mapping_rows_sha256 text not null check (
    illness_mapping_rows_sha256 = '${illnessMappingSha}'
  ),
  illness_ledger_sha256 text not null check (
    illness_ledger_sha256 = '${illnessLedgerSha}'
  ),
  specific_diagnosis_evidence_sha256 text not null check (
    specific_diagnosis_evidence_sha256 = '${evidenceSha}'
  ),
  accepted_2024_workbook_sha256 text not null check (
    accepted_2024_workbook_sha256 =
      '4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73'
  ),
  accepted_by text not null check (accepted_by = 'Abdel Babiker'),
  accepted_on date not null check (accepted_on = date '2026-09-01')
);

insert into audit.urc_diagnosis_family_adjudication_evidence_v1 values (
  'urc_diagnosis_family_adjudication_v1', '${ledgerSha}', '${mappingSha}',
  '${completeLedgerSha}', '${illnessInventorySha}', '${illnessMappingSha}',
  '${illnessLedgerSha}', '${evidenceSha}',
  '4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73',
  'Abdel Babiker', date '2026-09-01'
);

create table audit.urc_2024_25_diagnosis_family_source_rows_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_row integer not null check (source_row > 1),
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  source_label text not null,
  subtype_code text not null,
  family_code text not null,
  family_label text not null,
  review_status text not null,
  primary key (adjudication_version, source_row),
  unique (adjudication_version, source_row_sha256)
);

insert into audit.urc_2024_25_diagnosis_family_source_rows_v1 (
  source_row, source_row_sha256, source_label, subtype_code,
  family_code, family_label, review_status
)
values
${values2024}

create table audit.urc_2024_25_illness_profile_source_rows_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_row integer not null check (source_row > 1),
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  source_label text not null,
  illness_code text not null,
  illness_label text not null,
  primary key (adjudication_version, source_row),
  unique (adjudication_version, source_row_sha256)
);

insert into audit.urc_2024_25_illness_profile_source_rows_v1 (
  source_row, source_row_sha256, source_label, illness_code, illness_label
)
values
${illnessValues2024}

create table audit.urc_2025_26_diagnosis_family_exact_labels_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_label text not null,
  subtype_code text not null,
  family_code text,
  family_label text,
  problem_type_scope text not null,
  review_status text not null,
  row_filter_required boolean not null,
  primary key (adjudication_version, source_label),
  check ((family_code is null) = (family_label is null))
);

insert into audit.urc_2025_26_diagnosis_family_exact_labels_v1 (
  source_label, subtype_code, family_code, family_label,
  problem_type_scope, review_status, row_filter_required
)
values
${values2025}

create table audit.urc_2025_26_illness_exact_labels_v1 (
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
    default 'urc_diagnosis_family_adjudication_v1',
  source_label text not null,
  illness_code text not null,
  illness_label text not null,
  review_status text not null,
  primary key (adjudication_version, source_label)
);

insert into audit.urc_2025_26_illness_exact_labels_v1 (
  source_label, illness_code, illness_label, review_status
)
values
${illnessValues2025}

create function audit.reject_urc_diagnosis_family_adjudication_mutation_v1()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'Diagnosis-family adjudication evidence is immutable';
end;
$$;

create trigger urc_diagnosis_family_evidence_immutable
before update or delete on audit.urc_diagnosis_family_adjudication_evidence_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2024_25_diagnosis_family_rows_immutable
before update or delete on audit.urc_2024_25_diagnosis_family_source_rows_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2024_25_illness_profile_rows_immutable
before update or delete on audit.urc_2024_25_illness_profile_source_rows_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2025_26_diagnosis_family_labels_immutable
before update or delete on audit.urc_2025_26_diagnosis_family_exact_labels_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger urc_2025_26_illness_labels_immutable
before update or delete on audit.urc_2025_26_illness_exact_labels_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();

alter table audit.urc_diagnosis_family_adjudication_evidence_v1 enable row level security;
alter table audit.urc_2024_25_diagnosis_family_source_rows_v1 enable row level security;
alter table audit.urc_2024_25_illness_profile_source_rows_v1 enable row level security;
alter table audit.urc_2025_26_diagnosis_family_exact_labels_v1 enable row level security;
alter table audit.urc_2025_26_illness_exact_labels_v1 enable row level security;
revoke all on audit.urc_diagnosis_family_adjudication_evidence_v1,
  audit.urc_2024_25_diagnosis_family_source_rows_v1,
  audit.urc_2024_25_illness_profile_source_rows_v1,
  audit.urc_2025_26_diagnosis_family_exact_labels_v1,
  audit.urc_2025_26_illness_exact_labels_v1
from public, anon, authenticated, web_reader;
revoke execute on function
  audit.reject_urc_diagnosis_family_adjudication_mutation_v1()
from public, anon, authenticated, web_reader;

create table reporting.diagnosis_family_release_bindings_v1 (
  season text primary key check (season in ('2024-25', '2025-26')),
  release_id uuid not null unique references reporting.aggregate_releases(id),
  release_label text not null,
  league_payload_sha256 text not null check (league_payload_sha256 ~ '^[0-9a-f]{64}$'),
  team_count integer not null check (team_count = 16),
  adjudication_version text not null references
    audit.urc_diagnosis_family_adjudication_evidence_v1(adjudication_version)
);

insert into reporting.diagnosis_family_release_bindings_v1 (
  season, release_id, release_label, league_payload_sha256, team_count,
  adjudication_version
)
select latest.season, latest.release_id, release.release_label,
  payload.payload_sha256, 16,
  'urc_diagnosis_family_adjudication_v1'
from reporting.latest_approved_dashboard_bundle_v4 latest
join reporting.aggregate_releases release on release.id = latest.release_id
join reporting.dashboard_bundle_league_payloads_v1 payload
  on payload.release_id = latest.release_id
where latest.season = '2024-25'
union all
select latest.season, latest.release_id, release.release_label,
  payload.payload_sha256, 16,
  'urc_diagnosis_family_adjudication_v1'
from reporting.latest_approved_league_bundle_v6 latest
join reporting.aggregate_releases release on release.id = latest.release_id
join reporting.league_release_payloads_v6 payload on payload.release_id = latest.release_id
where latest.season = '2025-26';

alter table reporting.diagnosis_family_release_bindings_v1 enable row level security;
create trigger urc_diagnosis_family_release_bindings_immutable
before update or delete on reporting.diagnosis_family_release_bindings_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
revoke all on reporting.diagnosis_family_release_bindings_v1
from public, anon, authenticated, web_reader;

create view reporting.diagnosis_family_base_team_payloads_v1
with (security_invoker = true) as
select binding.season, payload.team_key, payload.dashboard_payload as dashboard
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.dashboard_bundle_team_payloads_v1 payload
  on payload.bundle_release_id = binding.release_id
where binding.season = '2024-25'
union all
select binding.season, payload.team_key, payload.dashboard_payload
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.team_dashboard_payloads_v2 payload
  on payload.bundle_release_id = binding.release_id
where binding.season = '2025-26';

create view reporting.diagnosis_family_base_league_payloads_v1
with (security_invoker = true) as
select binding.season, payload.dashboard_payload as dashboard
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.dashboard_bundle_league_payloads_v1 payload
  on payload.release_id = binding.release_id
where binding.season = '2024-25'
union all
select binding.season, payload.dashboard_payload
from reporting.diagnosis_family_release_bindings_v1 binding
join reporting.league_release_payloads_v6 payload
  on payload.release_id = binding.release_id
where binding.season = '2025-26';

revoke all on reporting.diagnosis_family_base_team_payloads_v1,
  reporting.diagnosis_family_base_league_payloads_v1
from public, anon, authenticated, web_reader;

create view analysis.urc_2025_26_canonical_injury_rows_v1
with (security_invoker = true) as
select injury.team_key, injury.source_row, injury.injury_date,
  injury.is_time_loss, injury.days_lost, injury.setting_code,
  injury.contact_context,
  injury.reporting_body_location_code as body_location_code,
  injury.reporting_body_location_label as body_location_label,
  injury.reporting_injury_type_code as injury_type_code,
  injury.reporting_injury_type_label as injury_type_label,
  injury.reporting_diagnosis_code as diagnosis_code,
  injury.diagnosis_label, injury.severity_code
from analysis.urc_2025_26_reporting_key_rows_v3 injury
join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence on true
join lineage.injury_master_rows_v3 master
  on master.version_id = evidence.successor_version_id
 and master.source_row = injury.source_row
where lower(btrim(master.row_values ->> 'Problem type')) = 'injury';

create view analysis.urc_canonical_injury_rows_v1
with (security_invoker = true) as
select injury.season, injury.team_key, injury.source_row, injury.date_injured
  as injury_date, injury.final_classification = 'Time Loss' as is_time_loss,
  case when injury.duration_usable then injury.days_lost end as days_lost,
  injury.setting_code, injury.contact_context, injury.body_location_code,
  injury.body_location_label, injury.injury_type_code, injury.injury_type_label,
  injury.diagnosis_code, injury.diagnosis_label,
  coalesce(injury.severity_code, 'unknown_or_censored') as severity_code
from analysis.urc_2024_25_final_injury_classification_v1 injury
where injury.canonical_problem_type = 'injury'
union all
select '2025-26', injury.team_key, injury.source_row, injury.injury_date,
  injury.is_time_loss, injury.days_lost, injury.setting_code,
  injury.contact_context, injury.body_location_code, injury.body_location_label,
  injury.injury_type_code, injury.injury_type_label, injury.diagnosis_code,
  injury.diagnosis_label, injury.severity_code
from analysis.urc_2025_26_canonical_injury_rows_v1 injury;

create materialized view analysis.urc_diagnosis_family_rows_v1 as
select injury.season, injury.team_key, injury.source_row,
  injury.setting_code, injury.final_classification = 'Time Loss' as is_time_loss,
  case when injury.duration_usable then injury.days_lost end as days_lost,
  family.family_code, family.family_label,
  family.subtype_code, family.source_label as subtype_label
from analysis.urc_2024_25_final_injury_classification_v1 injury
join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
  on family.source_row = injury.source_row
join audit.urc_2024_25_specific_diagnosis_mappings_v1 source_evidence
  on source_evidence.season = injury.season
 and source_evidence.source_row = family.source_row
 and source_evidence.source_row_sha256 = family.source_row_sha256
where injury.canonical_problem_type = 'injury'
union all
select injury.season, injury.team_key, injury.source_row,
  injury.setting_code, injury.final_classification = 'Time Loss',
  case when injury.duration_usable then injury.days_lost end,
  'unknown', 'Unknown', 'subtype_unknown',
  coalesce(nullif(injury.diagnosis_label, ''), 'Unknown')
from analysis.urc_2024_25_final_injury_classification_v1 injury
left join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
  on family.source_row = injury.source_row
where injury.canonical_problem_type = 'injury' and family.source_row is null
union all
select '2025-26', injury.team_key, injury.source_row, injury.setting_code,
  injury.is_time_loss, injury.days_lost,
  family.family_code, family.family_label,
  family.subtype_code, family.source_label
from analysis.urc_2025_26_canonical_injury_rows_v1 injury
join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
  on family.source_label = injury.diagnosis_label
 and family.family_code is not null
union all
select '2025-26', injury.team_key, injury.source_row, injury.setting_code,
  injury.is_time_loss, injury.days_lost,
  'unknown', 'Unknown diagnosis', 'subtype_unknown', injury.diagnosis_label
from analysis.urc_2025_26_canonical_injury_rows_v1 injury
left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
  on family.source_label = injury.diagnosis_label
where family.family_code is null;

revoke all on analysis.urc_2025_26_canonical_injury_rows_v1,
  analysis.urc_canonical_injury_rows_v1,
  analysis.urc_diagnosis_family_rows_v1
from public, anon, authenticated, web_reader;

create view analysis.urc_diagnosis_family_team_exposure_v1
with (security_invoker = true) as
select payload.season, payload.team_key, setting.setting_code,
  case setting.setting_code
    when 'all' then (payload.dashboard #>> '{coverage,hours}')::numeric
    when 'match' then (payload.dashboard #>> '{coverage,match_hours}')::numeric
    when 'training' then (payload.dashboard #>> '{coverage,training_hours}')::numeric
  end as exposure_hours
from reporting.diagnosis_family_base_team_payloads_v1 payload
cross join (values ('all'::text), ('match'::text), ('training'::text), ('unknown'::text))
  setting(setting_code);

create view analysis.urc_diagnosis_family_team_subtypes_v1
with (security_invoker = true) as
with expanded as (
  select row.season, row.team_key, row.source_row, setting.setting_code,
    row.is_time_loss, row.days_lost, row.family_code, row.family_label,
    row.subtype_code, row.subtype_label
  from analysis.urc_diagnosis_family_rows_v1 row
  cross join lateral (
    select 'all'::text as setting_code
    union all select row.setting_code
  ) setting
)
select season, team_key, setting_code, family_code, family_label,
  subtype_code, subtype_label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
  count(*) filter (where is_time_loss and days_lost is not null)::bigint
    as known_duration_time_loss_injuries,
  coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
from expanded
group by season, team_key, setting_code, family_code, family_label,
  subtype_code, subtype_label;

create view analysis.urc_diagnosis_family_team_families_v1
with (security_invoker = true) as
with grouped as (
  select season, team_key, setting_code, family_code, family_label,
    sum(recorded_injuries)::bigint as recorded_injuries,
    sum(time_loss_injuries)::bigint as time_loss_injuries,
    sum(known_duration_time_loss_injuries)::bigint
      as known_duration_time_loss_injuries,
    sum(days_lost)::numeric as days_lost
  from analysis.urc_diagnosis_family_team_subtypes_v1
  group by season, team_key, setting_code, family_code, family_label
)
select grouped.*, exposure.exposure_hours,
  grouped.time_loss_injuries * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_team_exposure_v1 exposure
  using (season, team_key, setting_code);

create view analysis.urc_diagnosis_family_league_exposure_v1
with (security_invoker = true) as
select season, setting_code,
  case when count(exposure_hours) = 16 then sum(exposure_hours) end as exposure_hours
from analysis.urc_diagnosis_family_team_exposure_v1
group by season, setting_code;

create view analysis.urc_diagnosis_family_league_subtypes_v1
with (security_invoker = true) as
select season, setting_code, family_code, family_label,
  subtype_code, subtype_label,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries,
  sum(known_duration_time_loss_injuries)::bigint
    as known_duration_time_loss_injuries,
  sum(days_lost)::numeric as days_lost
from analysis.urc_diagnosis_family_team_subtypes_v1
group by season, setting_code, family_code, family_label,
  subtype_code, subtype_label;

create view analysis.urc_diagnosis_family_league_families_v1
with (security_invoker = true) as
with grouped as (
  select season, setting_code, family_code, family_label,
    sum(recorded_injuries)::bigint as recorded_injuries,
    sum(time_loss_injuries)::bigint as time_loss_injuries,
    sum(known_duration_time_loss_injuries)::bigint
      as known_duration_time_loss_injuries,
    sum(days_lost)::numeric as days_lost
  from analysis.urc_diagnosis_family_league_subtypes_v1
  group by season, setting_code, family_code, family_label
)
select grouped.*, exposure.exposure_hours,
  grouped.time_loss_injuries * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_league_exposure_v1 exposure
  using (season, setting_code);

create materialized view analysis.urc_illness_profile_rows_v1 as
select illness.season, illness.team_key, illness.source_row,
  illness.illness_code, illness.illness_label,
  illness.days_lost is not null as duration_known, illness.days_lost
from (
  select '2024-25'::text as season, bridge.team_key, profile.source_row,
    profile.illness_code, profile.illness_label,
    case when btrim(subject.final_values ->> 'Days Injured')
      ~ '^[0-9]+(\\.[0-9]+)?$'
      then btrim(subject.final_values ->> 'Days Injured')::numeric end as days_lost
  from audit.urc_2024_25_illness_profile_source_rows_v1 profile
  join lineage.master_source_bridge bridge
    on bridge.season = '2024-25' and bridge.source_row = profile.source_row
  cross join lateral analysis.row_correction_subject_v3(
    '2024-25', bridge.source_row_id
  ) subject
  where lower(btrim(subject.final_values ->> 'Problem type')) = 'illness'
) illness
union all
select '2025-26', inclusion.team_key, inclusion.source_row,
  profile.illness_code, profile.illness_label,
  master.time_loss_days is not null,
  master.time_loss_days
from lineage.injury_inclusion_rows_v3 inclusion
join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
  on inclusion.version_id = evidence.successor_version_id
join lineage.injury_master_rows_v3 master
  on master.version_id = inclusion.version_id
 and master.source_row = inclusion.source_row
join audit.urc_2025_26_illness_exact_labels_v1 profile
  on profile.source_label = coalesce(
    nullif(btrim(master.row_values ->> 'Specific Diagnosis'), ''), 'Unknown'
  )
where inclusion.dashboard_eligibility_reason = 'illness_record_not_in_injury_cohort'
  and lower(btrim(master.row_values ->> 'Problem type')) = 'illness';

create view analysis.urc_illness_team_profiles_v1
with (security_invoker = true) as
with grouped as (
  select season, team_key, illness_code, illness_label,
    count(*)::bigint as recorded_illnesses,
    count(*) filter (where duration_known)::bigint as known_duration_illnesses,
    coalesce(sum(days_lost) filter (where duration_known), 0)::numeric as days_lost
  from analysis.urc_illness_profile_rows_v1
  group by season, team_key, illness_code, illness_label
)
select grouped.*, 'all'::text as setting, exposure.exposure_hours,
  grouped.recorded_illnesses * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_illnesses, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_team_exposure_v1 exposure
  on exposure.season = grouped.season
 and exposure.team_key = grouped.team_key
 and exposure.setting_code = 'all';

create view analysis.urc_illness_league_profiles_v1
with (security_invoker = true) as
with grouped as (
  select season, illness_code, illness_label,
    sum(recorded_illnesses)::bigint as recorded_illnesses,
    sum(known_duration_illnesses)::bigint as known_duration_illnesses,
    sum(days_lost)::numeric as days_lost
  from analysis.urc_illness_team_profiles_v1
  group by season, illness_code, illness_label
)
select grouped.*, 'all'::text as setting, exposure.exposure_hours,
  grouped.recorded_illnesses * 1000 / nullif(exposure.exposure_hours, 0)
    as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(exposure.exposure_hours, 0)
    as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_illnesses, 0)
    as mean_severity_days
from grouped
join analysis.urc_diagnosis_family_league_exposure_v1 exposure
  on exposure.season = grouped.season and exposure.setting_code = 'all';

revoke all on analysis.urc_diagnosis_family_team_exposure_v1,
  analysis.urc_diagnosis_family_team_subtypes_v1,
  analysis.urc_diagnosis_family_team_families_v1,
  analysis.urc_diagnosis_family_league_exposure_v1,
  analysis.urc_diagnosis_family_league_subtypes_v1,
  analysis.urc_diagnosis_family_league_families_v1,
  analysis.urc_illness_profile_rows_v1,
  analysis.urc_illness_team_profiles_v1,
  analysis.urc_illness_league_profiles_v1
from public, anon, authenticated, web_reader;

create function reporting.diagnosis_family_rows_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, analysis as $$
declare result jsonb;
begin
  if target_team is null then
    with subtypes as materialized (
      select * from analysis.urc_diagnosis_family_league_subtypes_v1
      where season = target_season
    ), subtype_json as (
      select season, setting_code, family_code,
        jsonb_agg(jsonb_build_object(
          'code', subtype_code, 'label', subtype_label,
          'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries,
          'known_duration_time_loss_injuries',
            known_duration_time_loss_injuries,
          'days_lost', days_lost
        ) order by recorded_injuries desc, subtype_label, subtype_code) as rows
      from subtypes
      group by season, setting_code, family_code
    ), family_counts as (
      select season, setting_code, family_code, family_label,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint
          as known_duration_time_loss_injuries,
        sum(days_lost)::numeric as days_lost
      from subtypes
      group by season, setting_code, family_code, family_label
    ), families as materialized (
      select family_counts.*, exposure.exposure_hours,
        family_counts.time_loss_injuries * 1000 /
          nullif(exposure.exposure_hours, 0) as incidence_per_1000h,
        family_counts.days_lost * 1000 /
          nullif(exposure.exposure_hours, 0) as burden_per_1000h,
        family_counts.days_lost /
          nullif(family_counts.known_duration_time_loss_injuries, 0)
          as mean_severity_days
      from family_counts
      join analysis.urc_diagnosis_family_league_exposure_v1 exposure
        using (season, setting_code)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', families.family_code, 'label', families.family_label,
      'setting', families.setting_code,
      'recorded_injuries', families.recorded_injuries,
      'time_loss_injuries', families.time_loss_injuries,
      'known_duration_time_loss_injuries',
        families.known_duration_time_loss_injuries,
      'days_lost', families.days_lost,
      'exposure_hours', families.exposure_hours,
      'incidence_per_1000h', families.incidence_per_1000h,
      'burden_per_1000h', families.burden_per_1000h,
      'mean_severity_days', families.mean_severity_days,
      'subtypes', subtype_json.rows
    ) order by array_position(array['all','match','training','unknown'],
      families.setting_code), families.recorded_injuries desc,
      families.family_label, families.family_code), '[]'::jsonb)
    into result
    from families
    join subtype_json using (season, setting_code, family_code);
  else
    with subtypes as materialized (
      select * from analysis.urc_diagnosis_family_team_subtypes_v1
      where season = target_season and team_key = target_team
    ), subtype_json as (
      select season, team_key, setting_code, family_code,
        jsonb_agg(jsonb_build_object(
          'code', subtype_code, 'label', subtype_label,
          'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries,
          'known_duration_time_loss_injuries',
            known_duration_time_loss_injuries,
          'days_lost', days_lost
        ) order by recorded_injuries desc, subtype_label, subtype_code) as rows
      from subtypes
      group by season, team_key, setting_code, family_code
    ), family_counts as (
      select season, team_key, setting_code, family_code, family_label,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint
          as known_duration_time_loss_injuries,
        sum(days_lost)::numeric as days_lost
      from subtypes
      group by season, team_key, setting_code, family_code, family_label
    ), families as materialized (
      select family_counts.*, exposure.exposure_hours,
        family_counts.time_loss_injuries * 1000 /
          nullif(exposure.exposure_hours, 0) as incidence_per_1000h,
        family_counts.days_lost * 1000 /
          nullif(exposure.exposure_hours, 0) as burden_per_1000h,
        family_counts.days_lost /
          nullif(family_counts.known_duration_time_loss_injuries, 0)
          as mean_severity_days
      from family_counts
      join analysis.urc_diagnosis_family_team_exposure_v1 exposure
        using (season, team_key, setting_code)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'code', families.family_code, 'label', families.family_label,
      'setting', families.setting_code,
      'recorded_injuries', families.recorded_injuries,
      'time_loss_injuries', families.time_loss_injuries,
      'known_duration_time_loss_injuries',
        families.known_duration_time_loss_injuries,
      'days_lost', families.days_lost,
      'exposure_hours', families.exposure_hours,
      'incidence_per_1000h', families.incidence_per_1000h,
      'burden_per_1000h', families.burden_per_1000h,
      'mean_severity_days', families.mean_severity_days,
      'subtypes', subtype_json.rows
    ) order by array_position(array['all','match','training','unknown'],
      families.setting_code), families.recorded_injuries desc,
      families.family_label, families.family_code), '[]'::jsonb)
    into result
    from families
    join subtype_json using (season, team_key, setting_code, family_code);
  end if;
  return result;
end;
$$;

create function reporting.illness_profile_rows_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', illness_code, 'label', illness_label, 'setting', setting,
    'recorded_illnesses', recorded_illnesses,
    'known_duration_illnesses', known_duration_illnesses,
    'days_lost', days_lost, 'exposure_hours', exposure_hours,
    'incidence_per_1000h', incidence_per_1000h,
    'burden_per_1000h', burden_per_1000h,
    'mean_severity_days', mean_severity_days
  ) order by recorded_illnesses desc, illness_label, illness_code), '[]'::jsonb)
  from (
    select illness_code, illness_label, setting, recorded_illnesses,
      known_duration_illnesses, days_lost, exposure_hours,
      incidence_per_1000h, burden_per_1000h, mean_severity_days
    from analysis.urc_illness_league_profiles_v1
    where target_team is null and season = target_season
    union all
    select illness_code, illness_label, setting, recorded_illnesses,
      known_duration_illnesses, days_lost, exposure_hours,
      incidence_per_1000h, burden_per_1000h, mean_severity_days
    from analysis.urc_illness_team_profiles_v1
    where target_team is not null and season = target_season
      and team_key = target_team
  ) rows;
$$;

create function reporting.illness_summary_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  with exposure as (
    select exposure_hours
    from analysis.urc_diagnosis_family_league_exposure_v1
    where target_team is null and season = target_season and setting_code = 'all'
    union all
    select exposure_hours
    from analysis.urc_diagnosis_family_team_exposure_v1
    where target_team is not null and season = target_season
      and team_key = target_team and setting_code = 'all'
  ), totals as (
    select coalesce(sum(recorded_illnesses), 0)::bigint as recorded_illnesses,
      coalesce(sum(known_duration_illnesses), 0)::bigint
        as known_duration_illnesses,
      coalesce(sum(days_lost), 0)::numeric as days_lost
    from (
      select recorded_illnesses, known_duration_illnesses, days_lost
      from analysis.urc_illness_league_profiles_v1
      where target_team is null and season = target_season
      union all
      select recorded_illnesses, known_duration_illnesses, days_lost
      from analysis.urc_illness_team_profiles_v1
      where target_team is not null and season = target_season
        and team_key = target_team
    ) rows
  )
  select jsonb_build_object(
    'setting', 'all', 'recorded_illnesses', totals.recorded_illnesses,
    'known_duration_illnesses', totals.known_duration_illnesses,
    'days_lost', totals.days_lost, 'exposure_hours', exposure.exposure_hours,
    'incidence_per_1000h', totals.recorded_illnesses * 1000 /
      nullif(exposure.exposure_hours, 0),
    'burden_per_1000h', totals.days_lost * 1000 /
      nullif(exposure.exposure_hours, 0),
    'mean_severity_days', totals.days_lost /
      nullif(totals.known_duration_illnesses, 0),
    'qualification', 'Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training.'
  )
  from totals cross join exposure;
$$;

create function reporting.diagnosis_family_profiles_json_v1(families jsonb)
returns jsonb language sql immutable strict
set search_path = pg_catalog, pg_temp as $$
  select coalesce(jsonb_agg((family - 'subtypes') || jsonb_build_object(
    'dimension', 'diagnosis'
  ) order by array_position(array['all','match','training','unknown'], family ->> 'setting'),
    (family ->> 'recorded_injuries')::numeric desc,
    family ->> 'label', family ->> 'code'), '[]'::jsonb)
  from jsonb_array_elements(families) family;
$$;

create function reporting.replace_diagnosis_profiles_v1(
  profiles jsonb,
  families jsonb
)
returns jsonb language sql immutable strict
set search_path = pg_catalog, reporting, pg_temp as $$
  select coalesce(jsonb_agg(item order by source_order, item_order), '[]'::jsonb)
  from (
    select item, 1 as source_order, ordinality as item_order
    from jsonb_array_elements(profiles) with ordinality source(item, ordinality)
    where item ->> 'dimension' <> 'diagnosis'
    union all
    select item, 2, ordinality
    from jsonb_array_elements(
      reporting.diagnosis_family_profiles_json_v1(families)
    ) with ordinality source(item, ordinality)
  ) rows;
$$;

create view analysis.urc_2025_26_setting_severity_v1
with (security_invoker = true) as
with expanded as (
  select injury.team_key, setting.setting_code, injury.severity_code,
    injury.is_time_loss, injury.days_lost
  from analysis.urc_2025_26_canonical_injury_rows_v1 injury
  cross join lateral (
    select 'all'::text as setting_code
    union all select injury.setting_code
      where injury.setting_code in ('match', 'training')
  ) setting
)
select team_key, setting_code, severity_code,
  case severity_code
    when 'zero_days_medical_attention_only' then 'Medical attention'
    when 'one_day' then '1 day'
    when 'two_to_three_days' then '2-3 days'
    when 'four_to_seven_days' then '4-7 days'
    when 'eight_to_twenty_eight_days' then '8-28 days'
    when 'greater_than_twenty_eight_days' then '>28 days'
    else 'Unknown or censored'
  end as severity_label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
  coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
from expanded
group by team_key, setting_code, severity_code;

create function reporting.urc_2025_26_setting_severity_json_v1(target_team text default null)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  with rows as (
    select setting_code, severity_code, severity_label,
      sum(recorded_injuries)::bigint as recorded_injuries,
      sum(time_loss_injuries)::bigint as time_loss_injuries,
      sum(days_lost)::numeric as days_lost
    from analysis.urc_2025_26_setting_severity_v1
    where target_team is null or team_key = target_team
    group by setting_code, severity_code, severity_label
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', severity_code, 'label', severity_label, 'setting', setting_code,
    'recorded_injuries', recorded_injuries,
    'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost
  ) order by array_position(array['all','match','training','unknown'], setting_code),
    array_position(array['zero_days_medical_attention_only','one_day',
      'two_to_three_days','four_to_seven_days','eight_to_twenty_eight_days',
      'greater_than_twenty_eight_days','unknown_or_censored'], severity_code)), '[]'::jsonb)
  from rows;
$$;

create function reporting.urc_canonical_injury_sections_json_v1(
  target_season text,
  target_team text default null
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, reporting, pg_temp as $$
  with payload as (
    select dashboard
    from reporting.diagnosis_family_base_league_payloads_v1
    where target_team is null and season = target_season
    union all
    select dashboard
    from reporting.diagnosis_family_base_team_payloads_v1
    where target_team is not null and season = target_season
      and team_key = target_team
  ), rows as materialized (
    select * from analysis.urc_canonical_injury_rows_v1 injury
    where injury.season = target_season
      and (target_team is null or injury.team_key = target_team)
  ), coverage as (
    select (dashboard #>> '{coverage,hours}')::numeric as all_hours,
      (dashboard #>> '{coverage,match_hours}')::numeric as match_hours,
      (dashboard #>> '{coverage,training_hours}')::numeric as training_hours
    from payload
  ), summary as (
    select count(*)::bigint as recorded_injuries,
      count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
      count(*) filter (where is_time_loss and days_lost is not null)::bigint
        as known_duration_time_loss_injuries,
      coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost,
      percentile_cont(0.5) within group (order by days_lost)
        filter (where is_time_loss and days_lost is not null) as median_severity_days
    from rows
  ), monthly_source as (
    select month, to_date(month ->> 'month', 'Mon YYYY') as month_start
    from payload cross join lateral jsonb_array_elements(dashboard -> 'monthly') month
  ), monthly_injuries as (
    select date_trunc('month', injury_date)::date as month_start,
      count(*)::bigint as recorded_injuries,
      count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
      coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
    from rows where injury_date is not null
    group by date_trunc('month', injury_date)
  ), settings as (
    select domain.setting_code,
      count(rows.*) filter (
        where domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      )::bigint as recorded_injuries,
      count(rows.*) filter (where rows.is_time_loss and (
        domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      ))::bigint as time_loss_injuries,
      count(rows.*) filter (where rows.is_time_loss and rows.days_lost is not null
        and (domain.setting_code = 'all' or rows.setting_code = domain.setting_code)
      )::bigint as known_duration_time_loss_injuries,
      coalesce(sum(rows.days_lost) filter (where rows.is_time_loss and (
        domain.setting_code = 'all' or rows.setting_code = domain.setting_code
      )), 0)::numeric as days_lost
    from (values ('all'::text), ('match'::text), ('training'::text),
      ('unknown'::text)) domain(setting_code)
    left join rows on true
    group by domain.setting_code
  ), profiles as (
    select setting.setting_code, dimension.dimension, dimension.code,
      dimension.label, count(*)::bigint as recorded_injuries,
      count(*) filter (where injury.is_time_loss)::bigint as time_loss_injuries,
      count(*) filter (where injury.is_time_loss and injury.days_lost is not null)::bigint
        as known_duration_time_loss_injuries,
      coalesce(sum(injury.days_lost) filter (where injury.is_time_loss), 0)::numeric
        as days_lost
    from rows injury
    cross join lateral (
      select 'all'::text as setting_code union all select injury.setting_code
    ) setting
    cross join lateral (values
      ('body_location'::text, injury.body_location_code, injury.body_location_label),
      ('injury_type'::text, injury.injury_type_code, injury.injury_type_label)
    ) dimension(dimension, code, label)
    group by setting.setting_code, dimension.dimension, dimension.code,
      dimension.label
  ), severity as (
    select setting.setting_code, band.severity_code,
      count(rows.*) filter (where rows.severity_code = band.severity_code)::bigint
        as recorded_injuries,
      count(rows.*) filter (where rows.severity_code = band.severity_code
        and rows.is_time_loss)::bigint as time_loss_injuries,
      coalesce(sum(rows.days_lost) filter (where rows.severity_code = band.severity_code
        and rows.is_time_loss), 0)::numeric as days_lost
    from (values ('all'::text), ('match'::text), ('training'::text))
      setting(setting_code)
    cross join (values ('zero_days_medical_attention_only'::text),
      ('one_day'::text), ('two_to_three_days'::text),
      ('four_to_seven_days'::text), ('eight_to_twenty_eight_days'::text),
      ('greater_than_twenty_eight_days'::text), ('unknown_or_censored'::text))
      band(severity_code)
    left join rows on (setting.setting_code = 'all'
      or rows.setting_code = setting.setting_code)
    group by setting.setting_code, band.severity_code
  ), contact as (
    select setting.setting_code, context.contact_context, context.contact_label,
      count(rows.*) filter (where rows.contact_context = context.contact_context)::bigint
        as recorded_injuries,
      count(rows.*) filter (where rows.contact_context = context.contact_context
        and rows.is_time_loss)::bigint as time_loss_injuries
    from (values ('all'::text), ('match'::text), ('training'::text),
      ('unknown'::text)) setting(setting_code)
    cross join (values ('contact'::text, 'Contact'::text),
      ('non_contact'::text, 'Non-contact'::text),
      ('unknown'::text, 'Unknown'::text))
      context(contact_context, contact_label)
    left join rows on (setting.setting_code = 'all'
      or rows.setting_code = setting.setting_code)
    group by setting.setting_code, context.contact_context, context.contact_label
  ), profile_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'dimension', dimension, 'code', code, 'label', label,
      'setting', setting_code, 'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by dimension, setting_code, code), '[]'::jsonb) as rows
    from profiles cross join coverage
  )
  select jsonb_build_object(
    'method', jsonb_build_array(
      'Recorded injuries use approved canonically injury-coded lineage rows.',
      'Time-loss status uses final classification. Days lost use known duration only.'
    ),
    'headline', jsonb_build_array(
      jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', summary.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(canonical Problem type = Injury rows, including undated)'),
      jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', summary.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(canonical injury final classification = Time Loss)'),
      jsonb_build_object('key', 'overall_incidence_per_1000h',
        'label', 'Overall incidence',
        'value', summary.recorded_injuries * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'per 1,000 player-hours', 'numerator', summary.recorded_injuries,
        'denominator', coverage.all_hours,
        'formula', 'canonical recorded injuries / released exposure hours * 1000'),
      jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', summary.time_loss_injuries * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries,
        'denominator', coverage.all_hours,
        'formula', 'canonical Time Loss injuries / released exposure hours * 1000'),
      jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity',
        'value', summary.days_lost /
          nullif(summary.known_duration_time_loss_injuries, 0),
        'unit', 'days lost per injury', 'numerator', summary.days_lost,
        'denominator', summary.known_duration_time_loss_injuries,
        'formula', 'known-duration Time Loss days / known-duration Time Loss injuries'),
      jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity',
        'value', summary.median_severity_days, 'unit', 'days lost per injury',
        'denominator', summary.known_duration_time_loss_injuries,
        'formula', 'median known-duration Time Loss days'),
      jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden',
        'value', summary.days_lost * 1000 / nullif(coverage.all_hours, 0),
        'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost,
        'denominator', coverage.all_hours,
        'formula', 'known-duration Time Loss days / released exposure hours * 1000')
    ),
    'monthly', (select coalesce(jsonb_agg((monthly_source.month -
      array['recorded_injuries','time_loss_injuries','days_lost',
        'overall_incidence_per_1000h','incidence_per_1000h','burden_per_1000h'])
      || jsonb_build_object(
        'recorded_injuries', coalesce(monthly_injuries.recorded_injuries, 0),
        'time_loss_injuries', coalesce(monthly_injuries.time_loss_injuries, 0),
        'days_lost', coalesce(monthly_injuries.days_lost, 0),
        'overall_incidence_per_1000h',
          coalesce(monthly_injuries.recorded_injuries, 0) * 1000 /
            nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0),
        'incidence_per_1000h',
          coalesce(monthly_injuries.time_loss_injuries, 0) * 1000 /
            nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0),
        'burden_per_1000h', coalesce(monthly_injuries.days_lost, 0) * 1000 /
          nullif((monthly_source.month ->> 'exposure_hours')::numeric, 0)
      ) order by monthly_source.month_start), '[]'::jsonb)
      from monthly_source left join monthly_injuries using (month_start)),
    'body_locations', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.all_hours,
      'incidence_per_1000h', time_loss_injuries * 1000 /
        nullif(coverage.all_hours, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(coverage.all_hours, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by code), '[]'::jsonb) from profiles
      where dimension = 'body_location' and setting_code = 'all'),
    'injury_types', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.all_hours,
      'incidence_per_1000h', time_loss_injuries * 1000 /
        nullif(coverage.all_hours, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(coverage.all_hours, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by time_loss_injuries desc, code), '[]'::jsonb) from profiles
      where dimension = 'injury_type' and setting_code = 'all'),
    'injury_profiles', profile_json.rows,
    'injury_type_families', analysis.injury_type_families_from_payload_v3(
      profile_json.rows
    ),
    'severity_distribution', (select coalesce(jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'key', severity_code,
      'label', case severity_code
        when 'zero_days_medical_attention_only' then 'Medical attention'
        when 'one_day' then '1 day' when 'two_to_three_days' then '2-3 days'
        when 'four_to_seven_days' then '4-7 days'
        when 'eight_to_twenty_eight_days' then '8-28 days'
        when 'greater_than_twenty_eight_days' then '>28 days'
        else 'Unknown or censored' end,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost
    ) order by array_position(array['all','match','training'], setting_code),
      array_position(array['zero_days_medical_attention_only','one_day',
        'two_to_three_days','four_to_seven_days','eight_to_twenty_eight_days',
        'greater_than_twenty_eight_days','unknown_or_censored'], severity_code)
    ), '[]'::jsonb) from severity),
    'setting_split', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', setting_code, 'label', initcap(setting_code),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', recorded_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all','match','training','unknown'], setting_code)),
      '[]'::jsonb) from settings),
    'setting_metrics', (select coalesce(jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'label', initcap(setting_code),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code when 'all' then coverage.all_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', recorded_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'incidence_per_1000h', time_loss_injuries * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'burden_per_1000h', days_lost * 1000 / nullif(
        case setting_code when 'all' then coverage.all_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end, 0),
      'mean_severity_days', days_lost /
        nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all','match','training','unknown'], setting_code)),
      '[]'::jsonb) from settings),
    'contact_distribution', (select coalesce(jsonb_agg(jsonb_build_object(
      'key', contact_context, 'label', contact_label, 'setting', setting_code,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries
    ) order by array_position(array['all','match','training','unknown'], setting_code),
      array_position(array['contact','non_contact','unknown'], contact_context)),
      '[]'::jsonb) from contact)
  )
  from summary cross join coverage cross join profile_json;
$$;

create view analysis.urc_2025_26_preliminary_monthly_rates_v1
with (security_invoker = true) as
with months as (
  select payload.team_key, to_date(month ->> 'month', 'Mon YYYY') as month_start,
    (month ->> 'exposure_hours')::numeric as exposure_hours
  from reporting.diagnosis_family_base_team_payloads_v1 payload
  cross join lateral jsonb_array_elements(payload.dashboard -> 'monthly') month
  where payload.season = '2025-26'
    and (month ->> 'exposure_hours')::numeric > 0
), injuries as (
  select date_trunc('month', injury_date)::date as month_start,
    count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
  from analysis.urc_2025_26_canonical_injury_rows_v1
  where injury_date is not null
  group by date_trunc('month', injury_date)
), domain as (
  select value::date as month_start
  from generate_series(date '2025-09-01', date '2026-06-01', interval '1 month') value
), grouped as (
  select domain.month_start, count(months.team_key)::integer as contributor_count,
    sum(months.exposure_hours)::numeric as exposure_hours
  from domain left join months using (month_start)
  group by domain.month_start
)
select grouped.*, coalesce(injuries.time_loss_injuries, 0)::bigint
    as time_loss_injuries,
  coalesce(injuries.days_lost, 0)::numeric as days_lost,
  coalesce(injuries.time_loss_injuries, 0) * 1000 /
    nullif(grouped.exposure_hours, 0)
    as incidence_per_1000h,
  coalesce(injuries.days_lost, 0) * 1000 / nullif(grouped.exposure_hours, 0)
    as burden_per_1000h,
  'Preliminary contributor-aligned rate. Includes only teams with positive source-backed exposure in this month; not the official 16-team rate.'::text
    as qualification
from grouped left join injuries using (month_start);

create function reporting.urc_2025_26_preliminary_monthly_rates_json_v1()
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, pg_temp as $$
  select jsonb_agg(jsonb_build_object(
    'month', to_char(month_start, 'YYYY-MM'),
    'contributor_count', contributor_count, 'exposure_hours', exposure_hours,
    'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
    'incidence_per_1000h', incidence_per_1000h,
    'burden_per_1000h', burden_per_1000h, 'qualification', qualification
  ) order by month_start)
  from analysis.urc_2025_26_preliminary_monthly_rates_v1;
$$;

revoke all on analysis.urc_2025_26_setting_severity_v1,
  analysis.urc_2025_26_preliminary_monthly_rates_v1
from public, anon, authenticated, web_reader;

create view reporting.diagnosis_family_team_dashboards_v1
with (security_invoker = true) as
select base.team_key, base.season,
  base.dashboard || jsonb_build_object(
    'injury_profiles', reporting.replace_diagnosis_profiles_v1(
      base.dashboard -> 'injury_profiles', family.rows
    ),
    'diagnosis_families', family.rows,
    'illness_profiles', reporting.illness_profile_rows_json_v1(
      base.season, base.team_key
    ),
    'illness_summary', reporting.illness_summary_json_v1(
      base.season, base.team_key
    ),
    'severity_distribution', case when base.season = '2025-26'
      then reporting.urc_2025_26_setting_severity_json_v1(base.team_key)
      else base.dashboard -> 'severity_distribution' end,
    'preliminary_monthly_rates', null
  ) as dashboard
from reporting.diagnosis_family_base_team_payloads_v1 base
cross join lateral (
  select reporting.diagnosis_family_rows_json_v1(base.season, base.team_key) as rows
) family;

create view reporting.diagnosis_family_league_dashboards_v1
with (security_invoker = true) as
select base.season,
  base.dashboard || jsonb_build_object(
    'injury_profiles', reporting.replace_diagnosis_profiles_v1(
      base.dashboard -> 'injury_profiles', family.rows
    ),
    'diagnosis_families', family.rows,
    'illness_profiles', reporting.illness_profile_rows_json_v1(base.season, null),
    'illness_summary', reporting.illness_summary_json_v1(base.season, null),
    'severity_distribution', case when base.season = '2025-26'
      then reporting.urc_2025_26_setting_severity_json_v1()
      else base.dashboard -> 'severity_distribution' end,
    'preliminary_monthly_rates', case when base.season = '2025-26'
      then reporting.urc_2025_26_preliminary_monthly_rates_json_v1()
      else null end
  ) as dashboard
from reporting.diagnosis_family_base_league_payloads_v1 base
cross join lateral (
  select reporting.diagnosis_family_rows_json_v1(base.season, null) as rows
) family;

revoke all on reporting.diagnosis_family_team_dashboards_v1,
  reporting.diagnosis_family_league_dashboards_v1
from public, anon, authenticated, web_reader;

create view reporting.latest_team_dashboard_v7
with (security_invoker = false, security_barrier = true) as
select team_key, dashboard ->> 'team' as team, season,
  (dashboard ->> 'generated_at')::timestamptz as generated_at,
  dashboard -> 'analysis_window' as analysis_window,
  dashboard -> 'method' as method, dashboard -> 'coverage' as coverage,
  dashboard -> 'headline' as headline,
  dashboard -> 'setting_split' as setting_split,
  dashboard -> 'setting_metrics' as setting_metrics,
  dashboard -> 'monthly' as monthly,
  dashboard -> 'body_locations' as body_locations,
  dashboard -> 'injury_types' as injury_types,
  dashboard -> 'injury_profiles' as injury_profiles,
  dashboard -> 'diagnosis_families' as diagnosis_families,
  dashboard -> 'illness_profiles' as illness_profiles,
  dashboard -> 'illness_summary' as illness_summary,
  dashboard -> 'injury_type_families' as injury_type_families,
  dashboard -> 'severity_distribution' as severity_distribution,
  dashboard -> 'contact_distribution' as contact_distribution,
  dashboard -> 'prior_season' as prior_season,
  dashboard -> 'limitations' as limitations,
  dashboard -> 'preliminary_monthly_rates' as preliminary_monthly_rates
from reporting.diagnosis_family_team_dashboards_v1;

create view reporting.latest_league_dashboard_v7
with (security_invoker = false, security_barrier = true) as
select dashboard ->> 'team' as team, season,
  (dashboard ->> 'generated_at')::timestamptz as generated_at,
  dashboard -> 'analysis_window' as analysis_window,
  dashboard -> 'method' as method, dashboard -> 'coverage' as coverage,
  dashboard -> 'headline' as headline,
  dashboard -> 'setting_split' as setting_split,
  dashboard -> 'setting_metrics' as setting_metrics,
  dashboard -> 'monthly' as monthly,
  dashboard -> 'body_locations' as body_locations,
  dashboard -> 'injury_types' as injury_types,
  dashboard -> 'injury_profiles' as injury_profiles,
  dashboard -> 'diagnosis_families' as diagnosis_families,
  dashboard -> 'illness_profiles' as illness_profiles,
  dashboard -> 'illness_summary' as illness_summary,
  dashboard -> 'injury_type_families' as injury_type_families,
  dashboard -> 'severity_distribution' as severity_distribution,
  dashboard -> 'contact_distribution' as contact_distribution,
  dashboard -> 'prior_season' as prior_season,
  dashboard -> 'limitations' as limitations,
  dashboard -> 'preliminary_monthly_rates' as preliminary_monthly_rates
from reporting.diagnosis_family_league_dashboards_v1;

create function reporting.season_comparison_top_diagnoses_v5(
  dashboard jsonb,
  setting_name text
)
returns jsonb language sql immutable strict
set search_path = pg_catalog, pg_temp as $$
  with ranked as (
    select row_number() over (
      order by (family ->> 'time_loss_injuries')::numeric desc,
        (family ->> 'burden_per_1000h')::numeric desc nulls last,
        family ->> 'label', family ->> 'code'
    ) as rank, family
    from jsonb_array_elements(dashboard -> 'diagnosis_families') family
    where family ->> 'setting' = setting_name
      and (family ->> 'time_loss_injuries')::numeric > 0
      and lower(family ->> 'code') !~ '(^|__)unknown(_|__|$)'
      and lower(family ->> 'label') !~ '(^|[[:space:]·/])unknown($|[[:space:]/])'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank', rank, 'diagnosis', family ->> 'label',
    'time_loss_injuries', (family ->> 'time_loss_injuries')::numeric,
    'incidence_per_1000h', (family ->> 'incidence_per_1000h')::numeric,
    'burden_per_1000h', (family ->> 'burden_per_1000h')::numeric
  ) order by rank), '[]'::jsonb)
  from ranked where rank <= 3;
$$;

create function reporting.build_season_comparison_v5(
  previous_dashboard jsonb,
  current_dashboard jsonb,
  comparison_scope text
)
returns jsonb language plpgsql stable strict security definer
set search_path = pg_catalog, pg_temp as $$
declare comparison jsonb; diagnoses jsonb;
begin
  comparison := reporting.season_comparison_presentation_v2(
    reporting.build_season_comparison_v1(
      previous_dashboard, current_dashboard, comparison_scope
    )
  );
  with settings(ordinal, setting, label) as (values
    (1, 'all', 'Overall'), (2, 'match', 'Match'), (3, 'training', 'Training')
  )
  select jsonb_agg(jsonb_build_object(
    'setting', setting, 'label', label,
    'previous', reporting.season_comparison_top_diagnoses_v5(
      previous_dashboard, setting
    ),
    'current', reporting.season_comparison_top_diagnoses_v5(
      current_dashboard, setting
    )
  ) order by ordinal) into diagnoses from settings;
  return jsonb_set(jsonb_set(comparison, '{rule_version}',
    to_jsonb('season_comparison_reporting_2026_09_01_v5'::text), false),
    '{diagnoses}', diagnoses, false);
end;
$$;

create view reporting.latest_team_season_comparison_v5
with (security_invoker = false, security_barrier = true) as
select previous.team_key, reporting.build_season_comparison_v5(
  to_jsonb(previous) - 'team_key', to_jsonb(current) - 'team_key', 'team'
) as comparison
from reporting.latest_team_dashboard_v7 previous
join reporting.latest_team_dashboard_v7 current using (team_key)
where previous.season = '2024-25' and current.season = '2025-26'
  and jsonb_array_length(previous.diagnosis_families) > 0
  and jsonb_array_length(current.diagnosis_families) > 0;

create view reporting.latest_league_season_comparison_v5
with (security_invoker = false, security_barrier = true) as
select reporting.build_season_comparison_v5(
  to_jsonb(previous), to_jsonb(current), 'league'
) as comparison
from reporting.latest_league_dashboard_v7 previous
cross join reporting.latest_league_dashboard_v7 current
where previous.season = '2024-25' and current.season = '2025-26'
  and jsonb_array_length(previous.diagnosis_families) > 0
  and jsonb_array_length(current.diagnosis_families) > 0;

create view reporting.approved_dashboard_reader_target_v7
with (security_invoker = false, security_barrier = true) as
select target_attested
  and to_regclass('reporting.latest_team_dashboard_v7') is not null
  and to_regclass('reporting.latest_league_dashboard_v7') is not null
  and to_regclass('reporting.latest_team_season_comparison_v5') is not null
  and to_regclass('reporting.latest_league_season_comparison_v5') is not null
  and (select count(*) from reporting.diagnosis_family_release_bindings_v1) = 2
  as target_attested
from reporting.approved_dashboard_reader_target_v6;

create function analysis.assert_urc_diagnosis_family_reporting_v1()
returns void language plpgsql
set search_path = pg_catalog, analysis, reporting, audit as $$
begin
  if (select count(*) from audit.urc_2024_25_diagnosis_family_source_rows_v1) <> 1660
    or (select count(*) from audit.urc_2024_25_illness_profile_source_rows_v1) <> 392
    or (select count(*) from audit.urc_2025_26_diagnosis_family_exact_labels_v1) <> 420
    or (select count(*) from audit.urc_2025_26_illness_exact_labels_v1) <> 113
    or (select count(distinct (illness_code, illness_label))
        from audit.urc_2025_26_illness_exact_labels_v1) <> 50
    or (select count(*) from reporting.diagnosis_family_base_team_payloads_v1) <> 32
    or (select count(*) from reporting.diagnosis_family_base_league_payloads_v1) <> 2
    or (select count(*) from reporting.latest_team_dashboard_v7) <> 32
    or (select count(*) from reporting.latest_league_dashboard_v7) <> 2
    or (select count(*) from reporting.latest_team_season_comparison_v5) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v5) <> 1
  then raise exception 'Diagnosis-family reporting cardinality failed'; end if;

  if (select count(*) from analysis.urc_diagnosis_family_rows_v1
      where season = '2024-25') <> 1662
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1) <> 1545
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss) <> 938
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss and days_lost is not null) <> 782
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss) <> 20665
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26') <> 1545
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2024-25') <> 392
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2025-26') <> 439
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2025-26' and duration_known) <> 202
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_illness_profile_rows_v1
        where season = '2025-26' and duration_known) <> 927
    or (select count(distinct (illness_code, illness_label))
        from analysis.urc_illness_profile_rows_v1
        where season = '2025-26') <> 50
    or (select count(*)
        from audit.urc_2024_25_diagnosis_family_source_rows_v1 family
        join audit.urc_2024_25_specific_diagnosis_mappings_v1 source_evidence
          on source_evidence.season = '2024-25'
         and source_evidence.source_row = family.source_row
         and source_evidence.source_row_sha256 = family.source_row_sha256) <> 1660
    or (select count(*)
        from analysis.urc_2024_25_final_injury_classification_v1 injury
        join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
          on family.source_row = injury.source_row
        where injury.canonical_problem_type = 'injury') <> 1658
    or (select count(*)
        from analysis.urc_2024_25_final_injury_classification_v1 injury
        left join audit.urc_2024_25_diagnosis_family_source_rows_v1 family
          on family.source_row = injury.source_row
        where injury.canonical_problem_type = 'injury'
          and family.source_row is null) <> 4
    or (select count(*)
        from audit.urc_2024_25_diagnosis_family_source_rows_v1 family
        left join analysis.urc_2024_25_final_injury_classification_v1 injury
          on injury.source_row = family.source_row
         and injury.canonical_problem_type = 'injury'
        where injury.source_row is null) <> 2
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2024-25' and family_code = 'unknown') <> 4
    or exists (
      select season, family_code
      from analysis.urc_diagnosis_family_rows_v1
      group by season, family_code
      having count(distinct family_label) <> 1
    )
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code <> 'unknown') <> 1464
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown') <> 81
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown'
          and is_time_loss) <> 73
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown'
          and is_time_loss) <> 1042
    or (select count(*)
        from analysis.urc_2025_26_canonical_injury_rows_v1 injury
        left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
          on family.source_label = injury.diagnosis_label
        where family.family_code is null) <> 19
    or (select count(*)
        from analysis.urc_2025_26_canonical_injury_rows_v1 injury
        left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
          on family.source_label = injury.diagnosis_label
        where family.family_code is null and injury.is_time_loss) <> 18
    or (select coalesce(sum(injury.days_lost), 0)
        from analysis.urc_2025_26_canonical_injury_rows_v1 injury
        left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
          on family.source_label = injury.diagnosis_label
        where family.family_code is null and injury.is_time_loss) <> 73
    or exists (
      select 1
      from analysis.urc_diagnosis_family_rows_v1 rows
      cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
      join lineage.injury_master_rows_v3 master
        on master.version_id = evidence.successor_version_id
       and master.source_row = rows.source_row
      where rows.season = '2025-26'
        and lower(btrim(master.row_values ->> 'Problem type')) <> 'injury'
    )
  then raise exception 'Diagnosis-family row mapping or illness boundary failed'; end if;

  if exists (
    select 1 from reporting.latest_team_dashboard_v7 dashboard
    left join lateral (
      select count(*)::bigint as recorded,
        count(*) filter (where injury_date is not null)::bigint as dated,
        count(*) filter (where is_time_loss)::bigint as time_loss,
        coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days
      from analysis.urc_2025_26_canonical_injury_rows_v1 injury
      where injury.team_key = dashboard.team_key
    ) source on true
    where dashboard.season = '2025-26' and (
      (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'recorded_injuries') <> source.recorded
      or (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'time_loss_injuries') <> source.time_loss
      or (select (item ->> 'numerator')::numeric from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'burden_per_1000h') <> source.days
      or (select (item ->> 'recorded_injuries')::bigint
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' <> 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.monthly) item) <> source.dated
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.severity_distribution) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.contact_distribution) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.diagnosis_families) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.diagnosis_families) item
          where item ->> 'setting' <> 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'body_location') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'injury_type') <> source.recorded
    )
  ) then raise exception '2025-26 team injury sections do not reconcile'; end if;

  if exists (
    select 1 from reporting.latest_team_dashboard_v7 dashboard
    left join lateral (
      select count(*)::bigint as recorded,
        count(*) filter (where date_injured is not null)::bigint as dated,
        count(*) filter (where final_classification = 'Time Loss')::bigint
          as time_loss,
        coalesce(sum(days_lost) filter (where final_classification = 'Time Loss'
          and duration_usable), 0)::numeric as days
      from analysis.urc_2024_25_final_injury_classification_v1 injury
      where injury.team_key = dashboard.team_key
        and injury.canonical_problem_type = 'injury'
    ) source on true
    left join lateral (
      select count(*)::bigint as mapped
      from analysis.urc_diagnosis_family_rows_v1 family
      where family.season = '2024-25' and family.team_key = dashboard.team_key
    ) diagnosis on true
    where dashboard.season = '2024-25' and (
      (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'recorded_injuries') <> source.recorded
      or (select (item ->> 'value')::bigint from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'time_loss_injuries') <> source.time_loss
      or (select (item ->> 'numerator')::numeric from jsonb_array_elements(dashboard.headline) item
        where item ->> 'key' = 'burden_per_1000h') <> source.days
      or (select (item ->> 'recorded_injuries')::bigint
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.setting_metrics) item
          where item ->> 'setting' <> 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.monthly) item) <> source.dated
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.contact_distribution) item
          where item ->> 'setting' = 'all') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.diagnosis_families) item
          where item ->> 'setting' = 'all') <> diagnosis.mapped
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'body_location') <> source.recorded
      or (select sum((item ->> 'recorded_injuries')::bigint)
          from jsonb_array_elements(dashboard.injury_profiles) item
          where item ->> 'setting' = 'all'
            and item ->> 'dimension' = 'injury_type') <> source.recorded
    )
  ) then raise exception '2024-25 team injury sections do not reconcile'; end if;

  if not exists (
    select 1 from reporting.latest_league_dashboard_v7 dashboard
    where dashboard.season = '2025-26'
      and (select (item ->> 'value')::bigint
           from jsonb_array_elements(dashboard.headline) item
           where item ->> 'key' = 'recorded_injuries') = 1545
      and (select (item ->> 'recorded_injuries')::bigint
           from jsonb_array_elements(dashboard.setting_metrics) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.setting_metrics) item
           where item ->> 'setting' <> 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.monthly) item) =
          (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
           where injury_date is not null)
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.contact_distribution) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.diagnosis_families) item
           where item ->> 'setting' = 'all') = 1545
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.diagnosis_families) item
           where item ->> 'setting' <> 'all') = 1545
  ) then raise exception '2025-26 league injury sections do not reconcile to 1545'; end if;

  if not exists (
    select 1 from reporting.latest_league_dashboard_v7 dashboard
    where dashboard.season = '2024-25'
      and (select (item ->> 'value')::bigint
           from jsonb_array_elements(dashboard.headline) item
           where item ->> 'key' = 'recorded_injuries') =
          (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
           where canonical_problem_type = 'injury')
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 1518
      and (select sum((item ->> 'time_loss_injuries')::bigint)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 787
      and (select sum((item ->> 'days_lost')::numeric)
           from jsonb_array_elements(dashboard.severity_distribution) item
           where item ->> 'setting' = 'all') = 17575
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.diagnosis_families) item
           where item ->> 'setting' = 'all') = 1662
      and (select sum((item ->> 'recorded_injuries')::bigint)
           from jsonb_array_elements(dashboard.monthly) item) =
          (select count(*) from analysis.urc_2024_25_final_injury_classification_v1
           where canonical_problem_type = 'injury' and date_injured is not null)
  ) then raise exception '2024-25 league injury sections do not reconcile'; end if;

  if (select sum(recorded_illnesses) from analysis.urc_illness_league_profiles_v1
      where season = '2024-25') <> 392
    or (select sum(recorded_illnesses) from analysis.urc_illness_league_profiles_v1
        where season = '2025-26') <> 439
    or exists (select 1 from analysis.urc_illness_league_profiles_v1
      where setting <> 'all' or exposure_hours is null
        or incidence_per_1000h is null or burden_per_1000h is null)
    or exists (select 1 from analysis.urc_illness_team_profiles_v1
      where known_duration_illnesses = 0 and mean_severity_days is not null)
  then raise exception 'Illness profile cohort or metric rule failed'; end if;

  if exists (
    select 1 from (
      select season, team_key, illness_profiles, illness_summary
      from reporting.latest_team_dashboard_v7
      union all
      select season, null::text, illness_profiles, illness_summary
      from reporting.latest_league_dashboard_v7
    ) dashboard
    cross join lateral (
      select coalesce(sum((item ->> 'recorded_illnesses')::bigint), 0)::bigint
          as recorded,
        coalesce(sum((item ->> 'known_duration_illnesses')::bigint), 0)::bigint
          as known_duration,
        coalesce(sum((item ->> 'days_lost')::numeric), 0)::numeric as days_lost
      from jsonb_array_elements(dashboard.illness_profiles) item
    ) profile
    where jsonb_typeof(dashboard.illness_profiles) is distinct from 'array'
      or jsonb_typeof(dashboard.illness_summary) is distinct from 'object'
      or dashboard.illness_summary ->> 'setting' <> 'all'
      or dashboard.illness_summary ->> 'qualification' <>
        'Overall illness metrics use approved included illness rows and released total player-hours. Illness is not attributed to Match or Training.'
      or (dashboard.illness_summary ->> 'recorded_illnesses')::bigint <>
        profile.recorded
      or (dashboard.illness_summary ->> 'known_duration_illnesses')::bigint <>
        profile.known_duration
      or (dashboard.illness_summary ->> 'days_lost')::numeric <> profile.days_lost
      or ((dashboard.illness_summary ->> 'mean_severity_days')::numeric
          is distinct from profile.days_lost / nullif(profile.known_duration, 0))
  ) then raise exception 'Illness summary does not reconcile to illness profiles'; end if;

  if exists (
    select 1 from analysis.urc_diagnosis_family_team_families_v1 family
    left join (
      select season, team_key, setting_code, family_code,
        sum(recorded_injuries)::bigint as recorded_injuries,
        sum(time_loss_injuries)::bigint as time_loss_injuries,
        sum(known_duration_time_loss_injuries)::bigint as known_duration,
        sum(days_lost)::numeric as days_lost
      from analysis.urc_diagnosis_family_team_subtypes_v1
      group by season, team_key, setting_code, family_code
    ) subtype using (season, team_key, setting_code, family_code)
    where (family.recorded_injuries, family.time_loss_injuries,
      family.known_duration_time_loss_injuries, family.days_lost)
      is distinct from (subtype.recorded_injuries, subtype.time_loss_injuries,
        subtype.known_duration, subtype.days_lost)
  ) then raise exception 'Diagnosis family does not equal subtype sums'; end if;

  if not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'all'
      and family_label = 'Concussion' and recorded_injuries = 126
      and time_loss_injuries = 124 and days_lost = 1747
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'training'
      and family_label = 'Concussion' and recorded_injuries = 17
      and time_loss_injuries = 17 and days_lost = 217
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'match'
      and family_label = 'Concussion' and recorded_injuries = 109
      and time_loss_injuries = 107 and days_lost = 1530
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2025-26' and setting_code = 'all'
      and family_label = 'Hamstring muscle injury' and recorded_injuries = 82
      and time_loss_injuries = 78 and days_lost = 2323
  ) or not exists (
    select 1 from analysis.urc_diagnosis_family_league_families_v1
    where season = '2024-25' and setting_code = 'all'
      and family_label = 'Concussion' and recorded_injuries = 109
      and time_loss_injuries = 104 and days_lost = 1476
  ) then raise exception 'Pinned diagnosis-family reconciliation failed'; end if;

  if exists (
    select 1 from reporting.diagnosis_family_team_dashboards_v1 successor
    join reporting.diagnosis_family_base_team_payloads_v1 predecessor
      using (team_key, season)
    where successor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
      <> predecessor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
  ) or exists (
    select 1 from reporting.diagnosis_family_league_dashboards_v1 successor
    join reporting.diagnosis_family_base_league_payloads_v1 predecessor using (season)
    where successor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
      <> predecessor.dashboard - array['injury_profiles','diagnosis_families',
      'illness_profiles','illness_summary','severity_distribution',
      'preliminary_monthly_rates']
  ) then raise exception 'Diagnosis-family successor changed a non-presentation field'; end if;

  if exists (
    select 1
    from reporting.diagnosis_family_team_dashboards_v1 successor
    join reporting.diagnosis_family_base_team_payloads_v1 predecessor
      using (team_key, season)
    where (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(successor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
      <> (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(predecessor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
  ) or exists (
    select 1
    from reporting.diagnosis_family_league_dashboards_v1 successor
    join reporting.diagnosis_family_base_league_payloads_v1 predecessor using (season)
    where (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(successor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
      <> (select coalesce(jsonb_agg(item order by ordinality), '[]'::jsonb)
      from jsonb_array_elements(predecessor.dashboard -> 'injury_profiles')
        with ordinality rows(item, ordinality)
      where item ->> 'dimension' <> 'diagnosis')
  ) then raise exception 'Diagnosis replacement changed a non-diagnosis profile row'; end if;

  if exists (
    select 1 from analysis.urc_diagnosis_family_team_families_v1
    where setting_code = 'unknown' and (exposure_hours is not null
      or incidence_per_1000h is not null or burden_per_1000h is not null)
  ) or exists (
    select 1 from analysis.urc_diagnosis_family_team_families_v1
    where known_duration_time_loss_injuries = 0 and mean_severity_days is not null
  ) then raise exception 'Null rate or known-duration severity rule failed'; end if;

  if (select count(*) from analysis.urc_2025_26_preliminary_monthly_rates_v1) <> 10
    or exists (
      select 1 from analysis.urc_2025_26_preliminary_monthly_rates_v1
      where contributor_count < 1 or contributor_count > 16
        or exposure_hours <= 0 or incidence_per_1000h is null
        or burden_per_1000h is null
    )
    or (select count(*) from reporting.approved_dashboard_reader_target_v7
        where target_attested) <> 1
  then raise exception 'Preliminary rates or reader attestation failed'; end if;
end;
$$;

select analysis.assert_urc_diagnosis_family_reporting_v1();

revoke all on function reporting.diagnosis_family_rows_json_v1(text, text),
  reporting.illness_profile_rows_json_v1(text, text),
  reporting.illness_summary_json_v1(text, text),
  reporting.diagnosis_family_profiles_json_v1(jsonb),
  reporting.replace_diagnosis_profiles_v1(jsonb, jsonb),
  reporting.urc_2025_26_setting_severity_json_v1(text),
  reporting.urc_canonical_injury_sections_json_v1(text, text),
  reporting.urc_2025_26_preliminary_monthly_rates_json_v1(),
  reporting.season_comparison_top_diagnoses_v5(jsonb, text),
  reporting.build_season_comparison_v5(jsonb, jsonb, text),
  analysis.assert_urc_diagnosis_family_reporting_v1()
from public, anon, authenticated, web_reader;

revoke all on reporting.latest_team_dashboard_v7,
  reporting.latest_league_dashboard_v7,
  reporting.latest_team_season_comparison_v5,
  reporting.latest_league_season_comparison_v5,
  reporting.approved_dashboard_reader_target_v7
from public, anon, authenticated, web_reader;

grant select on reporting.latest_team_dashboard_v7,
  reporting.latest_league_dashboard_v7,
  reporting.latest_team_season_comparison_v5,
  reporting.latest_league_season_comparison_v5,
  reporting.approved_dashboard_reader_target_v7
to web_reader;
grant execute on function reporting.build_season_comparison_v5(jsonb, jsonb, text)
to web_reader;

commit;
`;
};

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const sql = buildSql();
  if (process.argv.includes('--check')) {
    const current = fs.readFileSync(path.join(ROOT, OUTPUT), 'utf8');
    if (current !== sql) throw new Error(`${OUTPUT} is stale`);
  } else {
    fs.writeFileSync(path.join(ROOT, OUTPUT), sql);
    console.log(JSON.stringify({ output: OUTPUT, sha256: sha256(sql) }));
  }
}
