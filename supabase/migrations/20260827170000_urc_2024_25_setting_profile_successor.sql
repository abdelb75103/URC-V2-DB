-- Restore the setting grain omitted from the 2024-25 classification successor.
-- The injury cohort, classification, monthly series and headline values remain
-- unchanged. Diagnosis rows remain injury-only.

create view analysis.urc_2024_25_team_profiles_v2
with (security_invoker = true) as
with observed as (
  select f.curated_build_id, f.team_key, f.season, setting.setting_code,
    dimension.dimension, dimension.code, dimension.label,
    count(*) filter (where f.final_classification = 'Time Loss')::bigint
      as time_loss_injuries,
    coalesce(sum(f.days_lost) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    ), 0)::numeric as days_lost,
    count(*) filter (
      where f.final_classification = 'Time Loss' and f.duration_usable
    )::bigint as known_duration_time_loss_injuries
  from analysis.urc_2024_25_final_injury_classification_v1 f
  left join audit.urc_2024_25_specific_diagnosis_mappings_v1 diagnosis
    on diagnosis.season = f.season
   and diagnosis.source_row = f.source_row
  cross join lateral (
    select f.setting_code where f.setting_code in ('match', 'training', 'unknown')
    union all select 'all'::text
  ) setting
  cross join lateral (values
    ('body_location'::text, f.body_location_code, f.body_location_label),
    ('injury_type'::text, f.injury_type_code, f.injury_type_label),
    ('injury_profile'::text,
      f.body_location_code || '__' || f.injury_type_code,
      f.body_location_label || ' · ' || f.injury_type_label),
    ('diagnosis'::text,
      coalesce(diagnosis.diagnosis_group_code, 'unknown'),
      coalesce(diagnosis.diagnosis_group_label, 'Unknown'))
  ) dimension(dimension, code, label)
  where dimension.dimension <> 'diagnosis'
     or f.canonical_problem_type = 'injury'
  group by f.curated_build_id, f.team_key, f.season, setting.setting_code,
    dimension.dimension, dimension.code, dimension.label
), exposure as (
  select payload.team_key, payload.curated_build_id,
    (payload.dashboard_payload -> 'coverage' ->> 'hours')::numeric as all_hours,
    (payload.dashboard_payload -> 'coverage' ->> 'match_hours')::numeric as match_hours,
    (payload.dashboard_payload -> 'coverage' ->> 'training_hours')::numeric as training_hours
  from reporting.dashboard_bundle_team_payloads_v1 payload
  where payload.bundle_release_id =
    '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
)
select observed.*,
  case observed.setting_code
    when 'all' then exposure.all_hours
    when 'match' then exposure.match_hours
    when 'training' then exposure.training_hours
    else null::numeric
  end as exposure_hours,
  observed.time_loss_injuries::numeric * 1000 / nullif(case observed.setting_code
    when 'all' then exposure.all_hours
    when 'match' then exposure.match_hours
    when 'training' then exposure.training_hours
    else null::numeric
  end, 0) as incidence_per_1000h,
  observed.days_lost * 1000 / nullif(case observed.setting_code
    when 'all' then exposure.all_hours
    when 'match' then exposure.match_hours
    when 'training' then exposure.training_hours
    else null::numeric
  end, 0) as burden_per_1000h,
  observed.days_lost / nullif(observed.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from observed
join exposure using (team_key, curated_build_id);

create view analysis.urc_2024_25_league_profiles_v2
with (security_invoker = true) as
with grouped as (
  select setting_code, dimension, code, label,
    sum(time_loss_injuries)::bigint as time_loss_injuries,
    sum(days_lost)::numeric as days_lost,
    sum(known_duration_time_loss_injuries)::bigint
      as known_duration_time_loss_injuries
  from analysis.urc_2024_25_team_profiles_v2
  group by setting_code, dimension, code, label
), exposure as (
  select
    (dashboard_payload -> 'coverage' ->> 'hours')::numeric as all_hours,
    (dashboard_payload -> 'coverage' ->> 'match_hours')::numeric as match_hours,
    (dashboard_payload -> 'coverage' ->> 'training_hours')::numeric as training_hours
  from reporting.dashboard_bundle_league_payloads_v1
  where release_id = '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
)
select grouped.*,
  case grouped.setting_code
    when 'all' then exposure.all_hours
    when 'match' then exposure.match_hours
    when 'training' then exposure.training_hours
    else null::numeric
  end as exposure_hours,
  grouped.time_loss_injuries::numeric * 1000 / nullif(case grouped.setting_code
    when 'all' then exposure.all_hours
    when 'match' then exposure.match_hours
    when 'training' then exposure.training_hours
    else null::numeric
  end, 0) as incidence_per_1000h,
  grouped.days_lost * 1000 / nullif(case grouped.setting_code
    when 'all' then exposure.all_hours
    when 'match' then exposure.match_hours
    when 'training' then exposure.training_hours
    else null::numeric
  end, 0) as burden_per_1000h,
  grouped.days_lost / nullif(grouped.known_duration_time_loss_injuries, 0)
    as mean_severity_days
from grouped cross join exposure;

create view analysis.urc_2024_25_team_severity_distribution_v2
with (security_invoker = true) as
select f.curated_build_id, f.team_key, f.season, setting.setting_code,
  f.severity_code, f.severity_label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where f.final_classification = 'Time Loss')::bigint
    as time_loss_injuries,
  coalesce(sum(f.days_lost) filter (
    where f.final_classification = 'Time Loss' and f.duration_usable
  ), 0)::numeric as days_lost,
  case f.severity_code
    when 'zero_days_medical_attention_only' then 0
    when 'one_day' then 1
    when 'two_to_three_days' then 2
    when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4
    when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.urc_2024_25_final_injury_classification_v1 f
cross join lateral (
  select f.setting_code where f.setting_code in ('match', 'training', 'unknown')
  union all select 'all'::text
) setting
where f.severity_code is not null
group by f.curated_build_id, f.team_key, f.season, setting.setting_code,
  f.severity_code, f.severity_label;

create view analysis.urc_2024_25_league_severity_distribution_v2
with (security_invoker = true) as
select setting_code, severity_code, severity_label,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries,
  sum(days_lost)::numeric as days_lost,
  min(band_order) as band_order
from analysis.urc_2024_25_team_severity_distribution_v2
group by setting_code, severity_code, severity_label;

create materialized view analysis.urc_2024_25_team_dashboard_candidate_v2 as
with profiles as (
  select source.team_key, source.curated_build_id,
    coalesce(jsonb_agg(jsonb_build_object(
      'dimension', source.dimension,
      'code', source.code,
      'label', source.label,
      'setting', source.setting_code,
      'time_loss_injuries', source.time_loss_injuries,
      'days_lost', source.days_lost,
      'exposure_hours', source.exposure_hours,
      'incidence_per_1000h', source.incidence_per_1000h,
      'burden_per_1000h', source.burden_per_1000h,
      'mean_severity_days', source.mean_severity_days
    ) order by source.dimension, source.setting_code,
      source.time_loss_injuries desc, source.days_lost desc, source.code), '[]'::jsonb)
      as rows
  from analysis.urc_2024_25_team_profiles_v2 source
  group by source.team_key, source.curated_build_id
), severity as (
  select source.team_key, source.curated_build_id,
    coalesce(jsonb_agg(jsonb_build_object(
      'key', source.severity_code,
      'label', source.severity_label,
      'setting', source.setting_code,
      'recorded_injuries', source.recorded_injuries,
      'time_loss_injuries', source.time_loss_injuries,
      'days_lost', source.days_lost
    ) order by source.setting_code, source.band_order), '[]'::jsonb) as rows
  from analysis.urc_2024_25_team_severity_distribution_v2 source
  where source.setting_code in ('all', 'match', 'training')
  group by source.team_key, source.curated_build_id
)
select candidate.team_key, candidate.season, candidate.team_release_id,
  candidate.curated_build_id, candidate.analysis_version,
  candidate.classification_view_version, candidate.cohort_view_version,
  candidate.cohort_evidence_sha256, candidate.classification_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'injury_profiles', profiles.rows,
    'injury_type_families',
      analysis.injury_type_families_from_payload_v1(profiles.rows),
    'severity_distribution', severity.rows
  ) as dashboard,
  candidate.predecessor_release_id,
  candidate.predecessor_canonical_bundle_sha256,
  candidate.predecessor_league_payload_sha256,
  candidate.predecessor_team_payload_set_sha256
from analysis.urc_2024_25_team_dashboard_candidate_v1 candidate
join profiles using (team_key, curated_build_id)
join severity using (team_key, curated_build_id);

create materialized view analysis.urc_2024_25_league_dashboard_candidate_v2 as
with profiles as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension', source.dimension,
    'code', source.code,
    'label', source.label,
    'setting', source.setting_code,
    'time_loss_injuries', source.time_loss_injuries,
    'days_lost', source.days_lost,
    'exposure_hours', source.exposure_hours,
    'incidence_per_1000h', source.incidence_per_1000h,
    'burden_per_1000h', source.burden_per_1000h,
    'mean_severity_days', source.mean_severity_days
  ) order by source.dimension, source.setting_code,
    source.time_loss_injuries desc, source.days_lost desc, source.code), '[]'::jsonb)
    as rows
  from analysis.urc_2024_25_league_profiles_v2 source
), severity as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', source.severity_code,
    'label', source.severity_label,
    'setting', source.setting_code,
    'recorded_injuries', source.recorded_injuries,
    'time_loss_injuries', source.time_loss_injuries,
    'days_lost', source.days_lost
  ) order by source.setting_code, source.band_order), '[]'::jsonb) as rows
  from analysis.urc_2024_25_league_severity_distribution_v2 source
  where source.setting_code in ('all', 'match', 'training')
)
select candidate.season, candidate.team, candidate.analysis_version,
  candidate.classification_view_version, candidate.cohort_view_version,
  candidate.cohort_evidence_sha256, candidate.classification_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'injury_profiles', profiles.rows,
    'injury_type_families',
      analysis.injury_type_families_from_payload_v1(profiles.rows),
    'severity_distribution', severity.rows
  ) as dashboard,
  candidate.predecessor_release_id,
  candidate.predecessor_canonical_bundle_sha256,
  candidate.predecessor_league_payload_sha256,
  candidate.predecessor_team_payload_set_sha256
from analysis.urc_2024_25_league_dashboard_candidate_v1 candidate
cross join profiles
cross join severity;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_team_dashboard_candidate_v2;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, analysis_version, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_league_dashboard_candidate_v2;

create function analysis.assert_urc_2024_25_setting_profile_successor_v1()
returns void
language plpgsql
set search_path = pg_catalog, analysis, audit, reporting
as $$
declare
  league_dashboard jsonb;
begin
  if not exists (
    select 1
    from reporting.latest_approved_dashboard_bundle_v4 approved
    join reporting.aggregate_releases release
      on release.id = approved.release_id
    join reporting.league_release_context_v2 context
      on context.release_id = approved.release_id
    where approved.season = '2024-25'
      and approved.release_id = 'c95aa8e5-59b9-4d4e-bf0c-478d5c95f2ca'::uuid
      and release.release_label = 'urc-2024-25-v5-15327d9c833f-a3'
      and context.classification_view_version =
        'reporting_classification_2024-25_2026-08-27_v1'
  ) then
    raise exception 'setting-profile successor is not based on the exact approved release';
  end if;

  if not exists (
    select 1
    from analysis.urc_2024_25_classification_evidence_v1 evidence
    where evidence.adjudication_rows = 32
      and evidence.specific_diagnosis_injury_rows = 1660
      and evidence.specific_diagnosis_illness_rows_excluded = 392
      and evidence.specific_diagnosis_evidence_sha256 =
        'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167'
      and evidence.specific_diagnosis_mapping_rows_sha256 =
        '8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7'
  ) then
    raise exception 'setting-profile successor diagnosis evidence is incomplete';
  end if;

  if (select count(*) from analysis.urc_2024_25_team_dashboard_candidate_v2) <> 16
     or (select count(*) from analysis.urc_2024_25_league_dashboard_candidate_v2) <> 1
  then
    raise exception 'setting-profile successor is not atomic 16-team plus league';
  end if;

  select dashboard into league_dashboard
  from analysis.urc_2024_25_league_dashboard_candidate_v2;
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
    raise exception 'setting-profile successor changed the approved headline totals';
  end if;

  if exists (
    with expected as (
      select injury.team_key, setting.setting_code,
        count(*) filter (
          where injury.final_classification = 'Time Loss'
        )::bigint as time_loss_injuries,
        coalesce(sum(injury.days_lost) filter (
          where injury.final_classification = 'Time Loss'
            and injury.duration_usable
        ), 0)::numeric as days_lost
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
        sum(profile.time_loss_injuries)::bigint as time_loss_injuries,
        sum(profile.days_lost)::numeric as days_lost
      from analysis.urc_2024_25_team_profiles_v2 profile
      where profile.dimension = 'diagnosis'
      group by profile.team_key, profile.setting_code
    )
    select 1
    from expected
    full join published using (team_key, setting_code)
    where (expected.time_loss_injuries, expected.days_lost)
      is distinct from (published.time_loss_injuries, published.days_lost)
  ) then
    raise exception 'published diagnosis totals do not match injury-only source rows';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_team_profiles_v2 profile
    join reporting.dashboard_bundle_team_payloads_v1 payload
      on payload.team_key = profile.team_key
     and payload.curated_build_id = profile.curated_build_id
     and payload.bundle_release_id =
       '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
    where profile.setting_code in ('all', 'match', 'training')
      and profile.exposure_hours is distinct from case profile.setting_code
        when 'all' then (payload.dashboard_payload -> 'coverage' ->> 'hours')::numeric
        when 'match' then (payload.dashboard_payload -> 'coverage' ->> 'match_hours')::numeric
        when 'training' then (payload.dashboard_payload -> 'coverage' ->> 'training_hours')::numeric
      end
  ) then
    raise exception 'team profile denominator does not match its setting';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_team_severity_distribution_v2 overall
    left join lateral (
      select sum(setting.recorded_injuries)::bigint as recorded_injuries,
        sum(setting.time_loss_injuries)::bigint as time_loss_injuries,
        sum(setting.days_lost)::numeric as days_lost
      from analysis.urc_2024_25_team_severity_distribution_v2 setting
      where setting.team_key = overall.team_key
        and setting.curated_build_id = overall.curated_build_id
        and setting.severity_code = overall.severity_code
        and setting.setting_code in ('match', 'training', 'unknown')
    ) settings on true
    where overall.setting_code = 'all'
      and (overall.recorded_injuries, overall.time_loss_injuries, overall.days_lost)
        is distinct from
          (settings.recorded_injuries, settings.time_loss_injuries, settings.days_lost)
  ) then
    raise exception 'severity all row does not reconcile to match, training and unknown';
  end if;

  if jsonb_array_length(league_dashboard -> 'injury_type_families') = 0
     or not (select bool_and(setting in ('all', 'match', 'training'))
             from jsonb_to_recordset(league_dashboard -> 'severity_distribution')
               as severity(setting text))
     or (select count(distinct setting)
         from jsonb_to_recordset(league_dashboard -> 'injury_profiles')
           as profile(setting text)
         where setting in ('all', 'match', 'training')) <> 3
  then
    raise exception 'published setting profiles, families or severity rows are incomplete';
  end if;
end;
$$;

select analysis.assert_urc_2024_25_setting_profile_successor_v1();

revoke all on analysis.urc_2024_25_team_profiles_v2,
  analysis.urc_2024_25_league_profiles_v2,
  analysis.urc_2024_25_team_severity_distribution_v2,
  analysis.urc_2024_25_league_severity_distribution_v2,
  analysis.urc_2024_25_team_dashboard_candidate_v2,
  analysis.urc_2024_25_league_dashboard_candidate_v2
from public, anon, authenticated, web_reader;
revoke execute on function
  analysis.assert_urc_2024_25_setting_profile_successor_v1()
from public, anon, authenticated, web_reader;

comment on function analysis.assert_urc_2024_25_setting_profile_successor_v1() is
  'Fails closed unless 2024-25 setting profiles, severity and injury-type families reconcile without changing approved headline totals.';
