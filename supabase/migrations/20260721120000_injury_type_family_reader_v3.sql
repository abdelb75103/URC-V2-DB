-- Additive presentation roll-up for the Injury Types anatomy explorer.
-- The immutable approved dashboard bundle remains unchanged. The function
-- groups its exact injury_type profile rows and keeps every contributing
-- subtype in the returned evidence array.

create function analysis.injury_type_families_from_payload_v1(profiles jsonb)
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
  ),
  profile_rows as (
    select p.*
    from jsonb_to_recordset(coalesce(profiles, '[]'::jsonb)) as p(
      dimension text,
      code text,
      label text,
      setting text,
      time_loss_injuries numeric,
      days_lost numeric,
      exposure_hours numeric,
      incidence_per_1000h numeric,
      burden_per_1000h numeric,
      mean_severity_days numeric
    )
    where p.dimension = 'injury_type'
  ),
  mapped as (
    select
      coalesce(map.family_code, 'unmapped_review') as family_code,
      coalesce(map.family_label, 'Review required') as family_label,
      coalesce(map.family_order, 99) as family_order,
      profile.*
    from profile_rows profile
    left join family_map map on map.type_code = profile.code
  ),
  pooled as (
    select
      family_code,
      family_label,
      family_order,
      setting,
      sum(time_loss_injuries) as time_loss_injuries,
      sum(days_lost) as days_lost,
      case
        when count(exposure_hours) = count(*)
         and count(distinct exposure_hours) = 1
          then max(exposure_hours)
        else null
      end as exposure_hours
    from mapped
    group by family_code, family_label, family_order, setting
  ),
  scored as (
    select
      pooled.*,
      analysis.rate_per_1000_v1(time_loss_injuries, exposure_hours) as incidence_per_1000h,
      analysis.rate_per_1000_v1(days_lost, exposure_hours) as burden_per_1000h,
      case when time_loss_injuries > 0 then days_lost / time_loss_injuries else null end as mean_severity_days
    from pooled
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
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
        'mapping_version', 'injury_type_family_2026-07-21_v1',
        'subtypes', (
          select jsonb_agg(
            jsonb_build_object(
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
            )
            order by subtype.time_loss_injuries desc, subtype.days_lost desc, subtype.code
          )
          from mapped subtype
          where subtype.family_code = scored.family_code
            and subtype.setting = scored.setting
        )
      )
      order by scored.setting, scored.family_order
    ),
    '[]'::jsonb
  )
  from scored;
$$;

revoke execute on function analysis.injury_type_families_from_payload_v1(jsonb) from public;
grant execute on function analysis.injury_type_families_from_payload_v1(jsonb) to web_reader;

comment on function analysis.injury_type_families_from_payload_v1(jsonb) is
  'Versioned display-family roll-up over exact approved injury_type profile rows. Rates reuse analysis.rate_per_1000_v1; every contributing controlled subtype remains in the returned evidence.';

create view reporting.latest_team_dashboard_v3
with (security_invoker = false, security_barrier = true) as
select
  source.*,
  analysis.injury_type_families_from_payload_v1(source.injury_profiles) as injury_type_families
from reporting.latest_team_dashboard_v2 source;

create view reporting.latest_league_dashboard_v3
with (security_invoker = false, security_barrier = true) as
select
  source.*,
  analysis.injury_type_families_from_payload_v1(source.injury_profiles) as injury_type_families
from reporting.latest_league_dashboard_v2 source;

grant select on reporting.latest_team_dashboard_v3 to web_reader;
grant select on reporting.latest_league_dashboard_v3 to web_reader;

comment on view reporting.latest_team_dashboard_v3 is
  'V2 immutable team dashboard projection plus versioned injury-type display families and subtype evidence.';
comment on view reporting.latest_league_dashboard_v3 is
  'V2 immutable league dashboard projection plus versioned injury-type display families and subtype evidence.';
