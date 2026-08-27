-- Publish recorded-injury prevalence beside the established Time Loss profile
-- metrics. This changes profile selection evidence only. The injury cohort,
-- classification, denominators, monthly series and headline values are fixed.

create materialized view analysis.urc_2024_25_team_profiles_v3 as
with recorded as (
  select injury.curated_build_id, injury.team_key, injury.season,
    setting.setting_code, dimension.dimension, dimension.code, dimension.label,
    count(*)::bigint as recorded_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 injury
  left join audit.urc_2024_25_specific_diagnosis_mappings_v1 diagnosis
    on diagnosis.season = injury.season
   and diagnosis.source_row = injury.source_row
  cross join lateral (
    select injury.setting_code
      where injury.setting_code in ('match', 'training', 'unknown')
    union all select 'all'::text
  ) setting
  cross join lateral (values
    ('body_location'::text,
      injury.body_location_code, injury.body_location_label),
    ('injury_type'::text,
      injury.injury_type_code, injury.injury_type_label),
    ('injury_profile'::text,
      injury.body_location_code || '__' || injury.injury_type_code,
      injury.body_location_label || ' · ' || injury.injury_type_label),
    ('diagnosis'::text,
      coalesce(diagnosis.diagnosis_group_code, 'unknown'),
      coalesce(diagnosis.diagnosis_group_label, 'Unknown'))
  ) dimension(dimension, code, label)
  where dimension.dimension <> 'diagnosis'
     or injury.canonical_problem_type = 'injury'
  group by injury.curated_build_id, injury.team_key, injury.season,
    setting.setting_code, dimension.dimension, dimension.code, dimension.label
)
select profile.*, recorded.recorded_injuries
from analysis.urc_2024_25_team_profiles_v2 profile
join recorded using (
  curated_build_id, team_key, season, setting_code, dimension, code, label
);

create view analysis.urc_2024_25_league_profiles_v3
with (security_invoker = true) as
with recorded as (
  select setting_code, dimension, code, label,
    sum(recorded_injuries)::bigint as recorded_injuries
  from analysis.urc_2024_25_team_profiles_v3
  group by setting_code, dimension, code, label
)
select profile.*, recorded.recorded_injuries
from analysis.urc_2024_25_league_profiles_v2 profile
join recorded using (setting_code, dimension, code, label);

create materialized view analysis.urc_2024_25_team_dashboard_candidate_v3 as
with profiles as (
  select source.team_key, source.curated_build_id,
    coalesce(jsonb_agg(jsonb_build_object(
      'dimension', source.dimension,
      'code', source.code,
      'label', source.label,
      'setting', source.setting_code,
      'recorded_injuries', source.recorded_injuries,
      'time_loss_injuries', source.time_loss_injuries,
      'days_lost', source.days_lost,
      'exposure_hours', source.exposure_hours,
      'incidence_per_1000h', source.incidence_per_1000h,
      'burden_per_1000h', source.burden_per_1000h,
      'mean_severity_days', source.mean_severity_days
    ) order by source.dimension, source.setting_code,
      source.recorded_injuries desc, source.time_loss_injuries desc,
      source.days_lost desc, source.code), '[]'::jsonb) as rows
  from analysis.urc_2024_25_team_profiles_v3 source
  group by source.team_key, source.curated_build_id
)
select candidate.team_key, candidate.season, candidate.team_release_id,
  candidate.curated_build_id, candidate.analysis_version,
  candidate.classification_view_version, candidate.cohort_view_version,
  candidate.cohort_evidence_sha256, candidate.classification_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'injury_profiles', profiles.rows,
    'injury_type_families',
      analysis.injury_type_families_from_payload_v1(profiles.rows)
  ) as dashboard,
  candidate.predecessor_release_id,
  candidate.predecessor_canonical_bundle_sha256,
  candidate.predecessor_league_payload_sha256,
  candidate.predecessor_team_payload_set_sha256
from analysis.urc_2024_25_team_dashboard_candidate_v2 candidate
join profiles using (team_key, curated_build_id);

create materialized view analysis.urc_2024_25_league_dashboard_candidate_v3 as
with profiles as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension', source.dimension,
    'code', source.code,
    'label', source.label,
    'setting', source.setting_code,
    'recorded_injuries', source.recorded_injuries,
    'time_loss_injuries', source.time_loss_injuries,
    'days_lost', source.days_lost,
    'exposure_hours', source.exposure_hours,
    'incidence_per_1000h', source.incidence_per_1000h,
    'burden_per_1000h', source.burden_per_1000h,
    'mean_severity_days', source.mean_severity_days
  ) order by source.dimension, source.setting_code,
    source.recorded_injuries desc, source.time_loss_injuries desc,
    source.days_lost desc, source.code), '[]'::jsonb) as rows
  from analysis.urc_2024_25_league_profiles_v3 source
)
select candidate.season, candidate.team, candidate.analysis_version,
  candidate.classification_view_version, candidate.cohort_view_version,
  candidate.cohort_evidence_sha256, candidate.classification_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'injury_profiles', profiles.rows,
    'injury_type_families',
      analysis.injury_type_families_from_payload_v1(profiles.rows)
  ) as dashboard,
  candidate.predecessor_release_id,
  candidate.predecessor_canonical_bundle_sha256,
  candidate.predecessor_league_payload_sha256,
  candidate.predecessor_team_payload_set_sha256
from analysis.urc_2024_25_league_dashboard_candidate_v2 candidate
cross join profiles;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_team_dashboard_candidate_v3;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, analysis_version, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_league_dashboard_candidate_v3;

create function analysis.assert_urc_2024_25_recorded_profile_successor_v1()
returns void
language plpgsql
set search_path = pg_catalog, analysis, audit, reporting
as $$
declare
  league_dashboard jsonb;
begin
  perform analysis.assert_urc_2024_25_setting_profile_successor_v1();

  if (select count(*) from analysis.urc_2024_25_team_dashboard_candidate_v3) <> 16
     or (select count(*) from analysis.urc_2024_25_league_dashboard_candidate_v3) <> 1
  then
    raise exception 'recorded-profile successor is not atomic 16-team plus league';
  end if;

  select dashboard into league_dashboard
  from analysis.urc_2024_25_league_dashboard_candidate_v3;
  if (select (item ->> 'value')::bigint
      from jsonb_array_elements(league_dashboard -> 'headline') item
      where item ->> 'key' = 'recorded_injuries') <> 1662
     or (select (item ->> 'value')::bigint
         from jsonb_array_elements(league_dashboard -> 'headline') item
         where item ->> 'key' = 'time_loss_injuries') <> 913
     or (select (item ->> 'numerator')::numeric
         from jsonb_array_elements(league_dashboard -> 'headline') item
         where item ->> 'key' = 'severity_mean_days') <> 17575
  then
    raise exception 'recorded-profile successor changed approved totals';
  end if;

  if exists (
    with expected as (
      select injury.team_key, setting.setting_code,
        count(*)::bigint as recorded_injuries
      from analysis.urc_2024_25_final_injury_classification_v1 injury
      cross join lateral (
        select injury.setting_code
          where injury.setting_code in ('match', 'training', 'unknown')
        union all select 'all'::text
      ) setting
      where injury.canonical_problem_type = 'injury'
      group by injury.team_key, setting.setting_code
    ), published as (
      select profile.team_key, profile.setting_code,
        sum(profile.recorded_injuries)::bigint as recorded_injuries
      from analysis.urc_2024_25_team_profiles_v3 profile
      where profile.dimension = 'diagnosis'
      group by profile.team_key, profile.setting_code
    )
    select 1
    from expected full join published using (team_key, setting_code)
    where expected.recorded_injuries is distinct from published.recorded_injuries
  ) then
    raise exception 'recorded diagnosis profiles do not match injury-only source rows';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_team_profiles_v3 overall
    left join lateral (
      select sum(setting.recorded_injuries)::bigint as recorded_injuries
      from analysis.urc_2024_25_team_profiles_v3 setting
      where setting.team_key = overall.team_key
        and setting.curated_build_id = overall.curated_build_id
        and setting.dimension = overall.dimension
        and setting.code = overall.code
        and setting.label = overall.label
        and setting.setting_code in ('match', 'training', 'unknown')
    ) settings on true
    where overall.setting_code = 'all'
      and overall.recorded_injuries is distinct from settings.recorded_injuries
  ) then
    raise exception 'recorded profile all row does not reconcile by setting';
  end if;

  if exists (
    with expected(code, recorded_injuries) as (values
      ('dx_hamstring_injury_f17cabd810'::text, 120::bigint),
      ('dx_lumbar_spine_pain_2022547a07', 41),
      ('dx_acromioclavicular_joint_injury_1a8d08823b', 39),
      ('dx_groin_and_adductor_injury_476e2d09eb', 37)
    )
    select 1
    from expected
    left join analysis.urc_2024_25_league_profiles_v3 profile
      on profile.setting_code = 'all'
     and profile.dimension = 'diagnosis'
     and profile.code = expected.code
    where profile.recorded_injuries is distinct from expected.recorded_injuries
  ) then
    raise exception 'recorded diagnosis prevalence does not match reviewed groups';
  end if;

  if jsonb_array_length(league_dashboard -> 'injury_type_families') = 0
     or exists (
       select 1
       from jsonb_to_recordset(league_dashboard -> 'injury_profiles') as profile(
         dimension text, setting text, recorded_injuries bigint
       )
       where profile.recorded_injuries is null
     )
  then
    raise exception 'recorded profiles or injury-type families are incomplete';
  end if;
end;
$$;

select analysis.assert_urc_2024_25_recorded_profile_successor_v1();

revoke all on analysis.urc_2024_25_team_profiles_v3,
  analysis.urc_2024_25_league_profiles_v3,
  analysis.urc_2024_25_team_dashboard_candidate_v3,
  analysis.urc_2024_25_league_dashboard_candidate_v3
from public, anon, authenticated, web_reader;
revoke execute on function
  analysis.assert_urc_2024_25_recorded_profile_successor_v1()
from public, anon, authenticated, web_reader;

comment on function analysis.assert_urc_2024_25_recorded_profile_successor_v1() is
  'Fails closed unless recorded injury prevalence reconciles from injury-only source rows through setting profiles without changing approved totals.';
