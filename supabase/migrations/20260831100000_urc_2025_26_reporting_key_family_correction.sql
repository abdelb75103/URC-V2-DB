-- Additive correction for the private Year 2 injury-successor candidate.
-- The predecessor snapshot remains immutable. This successor maps retained
-- source labels to controlled reporting identifiers and corrects the family
-- mean-severity denominator without changing cohort membership or totals.

create function analysis.injury_type_families_from_payload_v2(profiles jsonb)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, analysis
as $$
  with family_map(family_code, family_label, family_order, type_code) as (
    values
      ('muscle', 'Muscle', 1, 'muscle_injury'),
      ('muscle', 'Muscle', 1, 'muscle_contusion'),
      ('muscle', 'Muscle', 1, 'muscle_compartment_syndrome'),
      ('tendon', 'Tendon', 2, 'tendinopathy'),
      ('tendon', 'Tendon', 2, 'tendon_rupture'),
      ('ligament_sprain', 'Ligament / sprain', 3, 'joint_sprain'),
      ('joint_capsule', 'Joint & capsule', 4, 'arthritis'),
      ('joint_capsule', 'Joint & capsule', 4, 'bursitis'),
      ('joint_capsule', 'Joint & capsule', 4, 'chronic_instability'),
      ('joint_capsule', 'Joint & capsule', 4, 'synovitis_capsulitis'),
      ('bone', 'Bone', 5, 'bone_contusion'),
      ('bone', 'Bone', 5, 'bone_stress_injury'),
      ('bone', 'Bone', 5, 'fracture'),
      ('bone', 'Bone', 5, 'avascular_necrosis'),
      ('bone', 'Bone', 5, 'physis_injury'),
      ('cartilage', 'Cartilage', 6, 'cartilage_injury'),
      ('nervous_system', 'Nervous system', 7, 'brain_spinal_cord_injury'),
      ('nervous_system', 'Nervous system', 7, 'peripheral_nerve_injury'),
      ('skin_superficial', 'Skin & superficial tissue', 8, 'abrasion'),
      ('skin_superficial', 'Skin & superficial tissue', 8, 'contusion_superficial'),
      ('skin_superficial', 'Skin & superficial tissue', 8, 'laceration'),
      ('internal_organ', 'Internal organ', 9, 'internal_organ_trauma'),
      ('vascular', 'Vascular', 10, 'vascular_trauma'),
      ('other_unclassified', 'Other / unclassified', 11, 'stump_injury'),
      ('other_unclassified', 'Other / unclassified', 11, 'nonspecific'),
      ('other_unclassified', 'Other / unclassified', 11, 'unknown')
  ), profile_rows as (
    select p.*,
      case
        when coalesce(p.days_lost, 0) > 0
         and coalesce(p.mean_severity_days, 0) > 0
          then round(p.days_lost / p.mean_severity_days)
        else 0::numeric
      end as known_duration_time_loss_injuries
    from jsonb_to_recordset(coalesce(profiles, '[]'::jsonb)) as p(
      dimension text,
      code text,
      label text,
      setting text,
      recorded_injuries numeric,
      time_loss_injuries numeric,
      days_lost numeric,
      exposure_hours numeric,
      incidence_per_1000h numeric,
      burden_per_1000h numeric,
      mean_severity_days numeric
    )
    where p.dimension = 'injury_type'
  ), mapped as (
    select
      coalesce(map.family_code, 'unmapped_review') as family_code,
      coalesce(map.family_label, 'Review required') as family_label,
      coalesce(map.family_order, 99) as family_order,
      profile.*
    from profile_rows profile
    left join family_map map on map.type_code = profile.code
  ), pooled as (
    select family_code, family_label, family_order, setting,
      sum(time_loss_injuries) as time_loss_injuries,
      sum(known_duration_time_loss_injuries)
        as known_duration_time_loss_injuries,
      sum(days_lost) as days_lost,
      case
        when count(exposure_hours) = count(*)
         and count(distinct exposure_hours) = 1
          then max(exposure_hours)
        else null
      end as exposure_hours
    from mapped
    group by family_code, family_label, family_order, setting
  ), scored as (
    select pooled.*,
      analysis.rate_per_1000_v1(time_loss_injuries, exposure_hours)
        as incidence_per_1000h,
      analysis.rate_per_1000_v1(days_lost, exposure_hours)
        as burden_per_1000h,
      days_lost / nullif(known_duration_time_loss_injuries, 0)
        as mean_severity_days
    from pooled
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension', 'injury_type_family',
    'code', scored.family_code,
    'label', scored.family_label,
    'setting', scored.setting,
    'time_loss_injuries', scored.time_loss_injuries,
    'days_lost', scored.days_lost,
    'exposure_hours', scored.exposure_hours,
    'incidence_per_1000h', scored.incidence_per_1000h,
    'burden_per_1000h', scored.burden_per_1000h,
    'mean_severity_days', scored.mean_severity_days,
    'mapping_version', 'injury_type_family_2026-08-31_v2',
    'subtypes', (
      select jsonb_agg(jsonb_build_object(
        'dimension', subtype.dimension,
        'code', subtype.code,
        'label', subtype.label,
        'setting', subtype.setting,
        'time_loss_injuries', subtype.time_loss_injuries,
        'days_lost', subtype.days_lost,
        'exposure_hours', subtype.exposure_hours,
        'incidence_per_1000h', subtype.incidence_per_1000h,
        'burden_per_1000h', subtype.burden_per_1000h,
        'mean_severity_days', subtype.mean_severity_days
      ) order by subtype.time_loss_injuries desc,
        subtype.days_lost desc, subtype.code)
      from mapped subtype
      where subtype.family_code = scored.family_code
        and subtype.setting = scored.setting
    )
  ) order by scored.setting, scored.family_order), '[]'::jsonb)
  from scored;
$$;

revoke execute on function analysis.injury_type_families_from_payload_v2(jsonb)
  from public, anon, authenticated, web_reader;

comment on function analysis.injury_type_families_from_payload_v2(jsonb) is
  'Year 2 controlled-code family roll-up. Mean severity pools only the known-duration Time Loss denominator represented by subtype means.';

create view analysis.urc_2025_26_reporting_key_rows_v2
with (security_invoker = true) as
select source.*,
  coalesce(body.code, 'unknown') as reporting_body_location_code,
  coalesce(body.label, 'Unknown') as reporting_body_location_label,
  body.code is not null as body_location_mapping_found,
  coalesce(injury_type.code, 'unknown') as reporting_injury_type_code,
  coalesce(injury_type.label, 'Unknown') as reporting_injury_type_label,
  injury_type.code is not null as injury_type_mapping_found,
  coalesce(nullif(regexp_replace(
    lower(btrim(source.diagnosis_label)), '[^a-z0-9]+', '_', 'g'
  ), ''), 'unknown') as reporting_diagnosis_code
from analysis.urc_2025_26_injury_successor_rows_v1 source
left join lateral (
  select controlled.code, controlled.label
  from curated.code_lists controlled
  where controlled.list_name = 'body_location'
    and controlled.active
    and (
      lower(controlled.code) = lower(source.body_location_label)
      or lower(controlled.label) = lower(source.body_location_label)
    )
  order by
    (lower(controlled.label) = lower(source.body_location_label)) desc,
    controlled.code
  limit 1
) body on true
left join lateral (
  select controlled.code, controlled.label
  from curated.code_lists controlled
  where controlled.list_name = 'injury_type'
    and controlled.active
    and (
      lower(controlled.code) = lower(source.injury_type_label)
      or lower(controlled.label) = lower(source.injury_type_label)
    )
  order by
    (lower(controlled.label) = lower(source.injury_type_label)) desc,
    controlled.code
  limit 1
) injury_type on true;

create view analysis.urc_2025_26_reporting_key_profiles_v2
with (security_invoker = true) as
with expanded as (
  select rows.team_key, settings.setting_code,
    dimensions.dimension, dimensions.code, dimensions.label,
    rows.is_time_loss, rows.days_lost
  from analysis.urc_2025_26_reporting_key_rows_v2 rows
  cross join lateral (values
    ('body_location'::text, rows.reporting_body_location_code,
      rows.reporting_body_location_label),
    ('injury_type'::text, rows.reporting_injury_type_code,
      rows.reporting_injury_type_label),
    ('diagnosis'::text, rows.reporting_diagnosis_code,
      rows.diagnosis_label)
  ) dimensions(dimension, code, label)
  cross join lateral (values ('all'::text), (rows.setting_code))
    settings(setting_code)
)
select team_key, setting_code, dimension, code, label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
  count(*) filter (where is_time_loss and days_lost is not null)::bigint
    as known_duration_time_loss_injuries,
  coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
from expanded
group by team_key, setting_code, dimension, code, label;

revoke all on analysis.urc_2025_26_reporting_key_rows_v2,
  analysis.urc_2025_26_reporting_key_profiles_v2
  from public, anon, authenticated, web_reader;

create view analysis.urc_2025_26_reporting_key_family_candidate_material_v2
with (security_invoker = true) as
select source.active_state_sha256, source.team_key, source.season,
  source.curated_build_id, source.analysis_version,
  'reporting_classification_2025-26_2026-08-31_v3'::text
    as classification_view_version,
  'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'::text
    as classification_evidence_sha256,
  source.cohort_view_version, source.cohort_evidence_sha256,
  source.injury_lineage_version_id,
  '20260831100000'::text as injury_lineage_snapshot_version,
  source.injury_lineage_member_sha256,
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          source.dashboard,
          '{body_locations}', body_locations.rows, false
        ),
        '{injury_types}', injury_types.rows, false
      ),
      '{injury_profiles}', profiles.rows, false
    ),
    '{injury_type_families}',
    analysis.injury_type_families_from_payload_v2(profiles.rows),
    false
  ) as dashboard
from analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor source
cross join lateral (
  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension', profile.dimension,
    'code', profile.code,
    'label', profile.label,
    'setting', profile.setting_code,
    'recorded_injuries', profile.recorded_injuries,
    'time_loss_injuries', profile.time_loss_injuries,
    'days_lost', profile.days_lost,
    'exposure_hours', case profile.setting_code
      when 'all' then (source.dashboard #>> '{coverage,hours}')::numeric
      when 'match' then (source.dashboard #>> '{coverage,match_hours}')::numeric
      when 'training' then (source.dashboard #>> '{coverage,training_hours}')::numeric
    end,
    'incidence_per_1000h', analysis.rate_per_1000_v1(
      profile.time_loss_injuries,
      case profile.setting_code
        when 'all' then (source.dashboard #>> '{coverage,hours}')::numeric
        when 'match' then (source.dashboard #>> '{coverage,match_hours}')::numeric
        when 'training' then (source.dashboard #>> '{coverage,training_hours}')::numeric
      end
    ),
    'burden_per_1000h', analysis.rate_per_1000_v1(
      profile.days_lost,
      case profile.setting_code
        when 'all' then (source.dashboard #>> '{coverage,hours}')::numeric
        when 'match' then (source.dashboard #>> '{coverage,match_hours}')::numeric
        when 'training' then (source.dashboard #>> '{coverage,training_hours}')::numeric
      end
    ),
    'mean_severity_days', profile.days_lost
      / nullif(profile.known_duration_time_loss_injuries, 0)
  ) order by profile.dimension, profile.setting_code, profile.code), '[]'::jsonb)
    as rows
  from analysis.urc_2025_26_reporting_key_profiles_v2 profile
  where profile.team_key = source.team_key
) profiles
cross join lateral (
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', profile.code,
    'label', profile.label,
    'time_loss_injuries', profile.time_loss_injuries,
    'days_lost', profile.days_lost,
    'exposure_hours', (source.dashboard #>> '{coverage,hours}')::numeric,
    'incidence_per_1000h', analysis.rate_per_1000_v1(
      profile.time_loss_injuries,
      (source.dashboard #>> '{coverage,hours}')::numeric
    ),
    'burden_per_1000h', analysis.rate_per_1000_v1(
      profile.days_lost,
      (source.dashboard #>> '{coverage,hours}')::numeric
    ),
    'mean_severity_days', profile.days_lost
      / nullif(profile.known_duration_time_loss_injuries, 0)
  ) order by profile.code), '[]'::jsonb) as rows
  from analysis.urc_2025_26_reporting_key_profiles_v2 profile
  where profile.team_key = source.team_key
    and profile.setting_code = 'all'
    and profile.dimension = 'body_location'
) body_locations
cross join lateral (
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', profile.code,
    'label', profile.label,
    'time_loss_injuries', profile.time_loss_injuries,
    'days_lost', profile.days_lost,
    'exposure_hours', (source.dashboard #>> '{coverage,hours}')::numeric,
    'incidence_per_1000h', analysis.rate_per_1000_v1(
      profile.time_loss_injuries,
      (source.dashboard #>> '{coverage,hours}')::numeric
    ),
    'burden_per_1000h', analysis.rate_per_1000_v1(
      profile.days_lost,
      (source.dashboard #>> '{coverage,hours}')::numeric
    ),
    'mean_severity_days', profile.days_lost
      / nullif(profile.known_duration_time_loss_injuries, 0)
  ) order by profile.time_loss_injuries desc, profile.code), '[]'::jsonb)
    as rows
  from analysis.urc_2025_26_reporting_key_profiles_v2 profile
  where profile.team_key = source.team_key
    and profile.setting_code = 'all'
    and profile.dimension = 'injury_type'
) injury_types
where source.snapshot_version = '20260830170000'
  and source.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(source.dashboard);

revoke all on analysis.urc_2025_26_reporting_key_family_candidate_material_v2
  from public, anon, authenticated, web_reader;

create table analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys (
  snapshot_version text not null check (snapshot_version = '20260831100000'),
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
    injury_lineage_snapshot_version = '20260831100000'
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

alter table analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys
  enable row level security;
revoke all on analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys
  from public, anon, authenticated, web_reader;

create trigger urc_2025_26_reporting_key_candidate_immutable
before update or delete
on analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys
for each row execute function
  analysis.reject_urc_2025_26_injury_successor_candidate_mutation();

insert into analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys (
  snapshot_version, active_state_sha256, payload_sha256,
  team_key, season, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  injury_lineage_version_id, injury_lineage_snapshot_version,
  injury_lineage_member_sha256, dashboard
)
select '20260831100000', material.active_state_sha256,
  reporting.canonical_jsonb_sha256_v1(material.dashboard),
  material.team_key, material.season, material.curated_build_id,
  material.analysis_version, material.classification_view_version,
  material.classification_evidence_sha256,
  material.cohort_view_version, material.cohort_evidence_sha256,
  material.injury_lineage_version_id,
  material.injury_lineage_snapshot_version,
  material.injury_lineage_member_sha256, material.dashboard
from analysis.urc_2025_26_reporting_key_family_candidate_material_v2 material;

alter table reporting.team_release_payloads_v6
  drop constraint team_release_payloads_v6_classification_view_version_check,
  add constraint team_release_payloads_v6_classification_view_version_check check (
    classification_view_version in (
      'reporting_classification_2026-07-22_v2',
      'reporting_classification_2025-26_2026-08-30_v2',
      'reporting_classification_2025-26_2026-08-31_v3'
    )
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_classification_view_version_check,
  add constraint league_release_context_v2_classification_view_version_check check (
    classification_view_version in (
      'v2',
      'reporting_classification_2026-07-20_v1',
      'reporting_classification_2026-07-22_v2',
      'reporting_classification_2024-25_2026-08-27_v1',
      'reporting_classification_2025-26_2026-08-30_v2',
      'reporting_classification_2025-26_2026-08-31_v3'
    )
  );

alter table reporting.team_release_injury_lineage_v1
  drop constraint team_release_injury_lineage_v1_candidate_snapshot_version_check,
  add constraint team_release_injury_lineage_v1_candidate_snapshot_version_check check (
    candidate_snapshot_version in ('20260830170000', '20260831100000')
  );

do $$
begin
  if (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys
    ) <> 16
    or (
      select count(*)
      from analysis.urc_2025_26_reporting_key_rows_v2
    ) <> 1484
    or (
      select count(*)
      from analysis.urc_2025_26_reporting_key_rows_v2
      where body_location_mapping_found
    ) <> 1457
    or (
      select count(*)
      from analysis.urc_2025_26_reporting_key_rows_v2
      where injury_type_mapping_found
    ) <> 1460
    or (
      select coalesce(sum(recorded_injuries), 0)
      from analysis.urc_2025_26_reporting_key_profiles_v2
      where dimension = 'injury_type' and setting_code = 'all'
    ) <> 1484
    or (
      select coalesce(sum(time_loss_injuries), 0)
      from analysis.urc_2025_26_reporting_key_profiles_v2
      where dimension = 'injury_type' and setting_code = 'all'
    ) <> 877
    or (
      select coalesce(sum(known_duration_time_loss_injuries), 0)
      from analysis.urc_2025_26_reporting_key_profiles_v2
      where dimension = 'injury_type' and setting_code = 'all'
    ) <> 731
    or (
      select coalesce(sum(days_lost), 0)
      from analysis.urc_2025_26_reporting_key_profiles_v2
      where dimension = 'injury_type' and setting_code = 'all'
    ) <> 19047
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys candidate
      cross join lateral jsonb_array_elements(
        candidate.dashboard -> 'injury_type_families'
      ) family
      where family ->> 'code' = 'unmapped_review'
    )
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys candidate
      join analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor predecessor
        using (team_key, season, curated_build_id)
      where candidate.dashboard - array[
        'body_locations', 'injury_types', 'injury_profiles',
        'injury_type_families'
      ] <> predecessor.dashboard - array[
        'body_locations', 'injury_types', 'injury_profiles',
        'injury_type_families'
      ]
    )
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys candidate
      where candidate.payload_sha256 <>
        reporting.canonical_jsonb_sha256_v1(candidate.dashboard)
        or candidate.injury_lineage_version_id <>
          '2f419706-8c36-58dd-b4cb-e92162e782b8'::uuid
        or candidate.cohort_view_version <>
          'injury_lineage_2025-26_2026-08-30_v2'
        or jsonb_array_length(candidate.dashboard -> 'headline') <> 7
    )
  then
    raise exception 'Year 2 reporting-key and family correction is incomplete';
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
from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys snapshot
join active_state
  on active_state.active_state_sha256 = snapshot.active_state_sha256
where snapshot.snapshot_version = '20260831100000'
  and snapshot.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.team_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;
