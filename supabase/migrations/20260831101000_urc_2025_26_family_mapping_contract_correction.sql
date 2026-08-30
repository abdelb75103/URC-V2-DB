-- Preserve the frozen public family taxonomy identifier. The reporting-key
-- correction changed the severity calculation, not the taxonomy mapping.

create function analysis.injury_type_families_from_payload_v3(profiles jsonb)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, analysis
as $$
  select coalesce(jsonb_agg(
    family.value || jsonb_build_object(
      'mapping_version', 'injury_type_family_2026-07-21_v1'
    )
    order by family.ordinality
  ), '[]'::jsonb)
  from jsonb_array_elements(
    analysis.injury_type_families_from_payload_v2(profiles)
  ) with ordinality as family(value, ordinality);
$$;

revoke execute on function analysis.injury_type_families_from_payload_v3(jsonb)
  from public, anon, authenticated, web_reader;

comment on function analysis.injury_type_families_from_payload_v3(jsonb) is
  'Corrected known-duration family severity with the unchanged, frozen 2026-07-21 taxonomy mapping identifier.';

create view analysis.urc_2025_26_family_mapping_contract_candidate_material_v3
with (security_invoker = true) as
select source.active_state_sha256, source.team_key, source.season,
  source.curated_build_id, source.analysis_version,
  source.classification_view_version,
  source.classification_evidence_sha256,
  source.cohort_view_version, source.cohort_evidence_sha256,
  source.injury_lineage_version_id,
  '20260831101000'::text as injury_lineage_snapshot_version,
  source.injury_lineage_member_sha256,
  jsonb_set(
    source.dashboard,
    '{injury_type_families}',
    analysis.injury_type_families_from_payload_v3(
      source.dashboard -> 'injury_profiles'
    ),
    false
  ) as dashboard
from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys source
where source.snapshot_version = '20260831100000'
  and source.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(source.dashboard);

revoke all on analysis.urc_2025_26_family_mapping_contract_candidate_material_v3
  from public, anon, authenticated, web_reader;

create table analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract (
  snapshot_version text not null check (snapshot_version = '20260831101000'),
  active_state_sha256 text not null check (active_state_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  team_key text not null references reporting.teams(team_key),
  season text not null check (season = '2025-26'),
  curated_build_id uuid not null references curated.builds(id),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (
    classification_view_version =
      'reporting_classification_2025-26_2026-08-31_v3'
  ),
  classification_evidence_sha256 text not null check (
    classification_evidence_sha256 =
      'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'injury_lineage_2025-26_2026-08-30_v2'
  ),
  cohort_evidence_sha256 text not null check (
    cohort_evidence_sha256 ~ '^[0-9a-f]{64}$'
  ),
  injury_lineage_version_id uuid not null
    references lineage.injury_master_versions_v3(id),
  injury_lineage_snapshot_version text not null check (
    injury_lineage_snapshot_version = '20260831101000'
  ),
  injury_lineage_member_sha256 text not null check (
    injury_lineage_member_sha256 ~ '^[0-9a-f]{64}$'
  ),
  dashboard jsonb not null check (jsonb_typeof(dashboard) = 'object'),
  created_at timestamptz not null default now(),
  primary key (snapshot_version, team_key),
  unique (snapshot_version, curated_build_id),
  unique (snapshot_version, team_key, injury_lineage_member_sha256),
  check (payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard))
);

alter table analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract
  enable row level security;
revoke all on analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract
  from public, anon, authenticated, web_reader;

create trigger urc_2025_26_family_mapping_contract_candidate_immutable
before update or delete
on analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract
for each row execute function
  analysis.reject_urc_2025_26_injury_successor_candidate_mutation();

insert into analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract (
  snapshot_version, active_state_sha256, payload_sha256,
  team_key, season, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  injury_lineage_version_id, injury_lineage_snapshot_version,
  injury_lineage_member_sha256, dashboard
)
select '20260831101000', material.active_state_sha256,
  reporting.canonical_jsonb_sha256_v1(material.dashboard),
  material.team_key, material.season, material.curated_build_id,
  material.analysis_version, material.classification_view_version,
  material.classification_evidence_sha256,
  material.cohort_view_version, material.cohort_evidence_sha256,
  material.injury_lineage_version_id,
  material.injury_lineage_snapshot_version,
  material.injury_lineage_member_sha256, material.dashboard
from analysis.urc_2025_26_family_mapping_contract_candidate_material_v3 material;

alter table reporting.team_release_injury_lineage_v1
  drop constraint team_release_injury_lineage_v1_candidate_snapshot_version_check,
  add constraint team_release_injury_lineage_v1_candidate_snapshot_version_check check (
    candidate_snapshot_version in (
      '20260830170000', '20260831100000', '20260831101000'
    )
  );

do $$
begin
  if (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract
    ) <> 16
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract candidate
      cross join lateral jsonb_array_elements(
        candidate.dashboard -> 'injury_type_families'
      ) family
      where family ->> 'mapping_version' <>
        'injury_type_family_2026-07-21_v1'
        or family ->> 'code' = 'unmapped_review'
    )
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract candidate
      join analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys predecessor
        using (team_key, season, curated_build_id)
      where candidate.dashboard - 'injury_type_families'
        <> predecessor.dashboard - 'injury_type_families'
        or jsonb_array_length(candidate.dashboard -> 'headline') <> 7
        or candidate.injury_lineage_version_id <>
          '2f419706-8c36-58dd-b4cb-e92162e782b8'::uuid
        or candidate.payload_sha256 <>
          reporting.canonical_jsonb_sha256_v1(candidate.dashboard)
    )
  then
    raise exception 'Year 2 family mapping contract correction is incomplete';
  end if;
end;
$$;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with active_builds as materialized (
  select team_key, season, curated_build_id
  from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), build_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key,
    'curated_build_id', curated_build_id::text
  ) order by team_key) as builds
  from active_builds
  having count(*) = 16 and count(distinct team_key) = 16
), placeholder_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key,
    'event_id', event_id,
    'method', method,
    'estimated_total_hours', estimated_total_hours,
    'evidence_sha256', evidence_sha256
  ) order by team_key) as placeholders
  from analysis.active_exposure_placeholders_v1
  where season = '2025-26'
  having count(*) = 2
    and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
), active_state as (
  select reporting.canonical_jsonb_sha256_v1(jsonb_build_object(
    'successor', to_jsonb(evidence),
    'builds', build_state.builds,
    'placeholders', placeholder_state.placeholders
  )) as active_state_sha256
  from build_state
  cross join placeholder_state
  cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
)
select snapshot.team_key, snapshot.season,
  null::uuid as team_release_id, snapshot.curated_build_id,
  snapshot.analysis_version, snapshot.classification_view_version,
  snapshot.classification_evidence_sha256,
  snapshot.cohort_view_version, snapshot.cohort_evidence_sha256,
  snapshot.dashboard,
  null::bigint as processing_eligible_injury_count,
  null::bigint as eligible_curated_injury_count,
  null::bigint as recorded_cohort_count,
  null::text as processing_record_version_set_sha256,
  null::text as curated_record_version_set_sha256,
  null::text as reporting_record_version_set_sha256,
  null::bigint as approved_injury_source_file_count,
  null::bigint as unapproved_injury_source_row_count,
  null::bigint as wrong_problem_type_rule_version_count,
  snapshot.injury_lineage_version_id,
  snapshot.injury_lineage_snapshot_version,
  snapshot.injury_lineage_member_sha256
from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract snapshot
join active_state
  on active_state.active_state_sha256 = snapshot.active_state_sha256
where snapshot.snapshot_version = '20260831101000'
  and snapshot.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.team_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;
