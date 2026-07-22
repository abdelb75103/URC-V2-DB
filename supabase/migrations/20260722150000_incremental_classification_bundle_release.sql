-- Classification-only bundle releases must not rebuild unrelated dashboard metrics.
-- These views inherit the latest approved immutable bundle and replace only the
-- three sections derived from the accepted OSIICS reporting classification.

create view analysis.team_dashboard_classification_sections_v4
with (security_invoker = true) as
with body as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
      'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
      'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
    ) order by p.code) as docs
  from analysis.season_bound_effective_injury_profiles_v4 p
  where p.dimension='body_location' and p.setting_code='all'
  group by p.curated_build_id,p.team_key,p.season
), types as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
      'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
      'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
    ) order by p.time_loss_injuries desc,p.days_lost desc,p.code) as docs
  from analysis.season_bound_effective_injury_profiles_v4 p
  where p.dimension='injury_type' and p.setting_code='all'
  group by p.curated_build_id,p.team_key,p.season
), profile_rows as (
  select p.curated_build_id,p.team_key,p.season,p.dimension,p.code,p.label,
    p.setting_code,p.time_loss_injuries,p.days_lost,p.exposure_hours,
    p.incidence_per_1000h,p.burden_per_1000h,p.mean_severity_days
  from analysis.season_bound_effective_injury_profiles_v4 p
  union all
  select p.curated_build_id,p.team_key,p.season,'diagnosis',p.code,p.label,
    p.setting_code,p.time_loss_injuries,p.days_lost,p.exposure_hours,
    p.incidence_per_1000h,p.burden_per_1000h,p.mean_severity_days
  from analysis.season_bound_diagnosis_profiles_v4 p
), profiles as (
  select p.curated_build_id,p.team_key,p.season,
    jsonb_agg(jsonb_build_object(
      'dimension',p.dimension,'code',p.code,'label',p.label,'setting',p.setting_code,
      'time_loss_injuries',p.time_loss_injuries,'days_lost',p.days_lost,
      'exposure_hours',p.exposure_hours,'incidence_per_1000h',p.incidence_per_1000h,
      'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
    ) order by case when p.dimension='diagnosis' then 1 else 0 end,
      p.dimension,p.setting_code,p.time_loss_injuries desc,p.days_lost desc,p.code) as docs
  from profile_rows p
  group by p.curated_build_id,p.team_key,p.season
)
select m.curated_build_id,m.team_key,m.season,
  coalesce(body.docs,'[]'::jsonb) as body_locations,
  coalesce(types.docs,'[]'::jsonb) as injury_types,
  coalesce(profiles.docs,'[]'::jsonb) as injury_profiles
from analysis.league_member_releases_v2 m
left join body using (curated_build_id,team_key,season)
left join types using (curated_build_id,team_key,season)
left join profiles using (curated_build_id,team_key,season);

create view analysis.league_dashboard_classification_sections_v4
with (security_invoker = true) as
with body as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
      'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
      'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
    ) order by p.code) as docs
  from analysis.season_bound_league_effective_injury_profiles_v4 p
  where p.dimension='body_location' and p.setting_code='all'
  group by p.season
), types as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
      'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
      'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
    ) order by p.time_loss_injuries desc,p.days_lost desc,p.code) as docs
  from analysis.season_bound_league_effective_injury_profiles_v4 p
  where p.dimension='injury_type' and p.setting_code='all'
  group by p.season
), profile_rows as (
  select p.season,p.dimension,p.code,p.label,p.setting_code,p.time_loss_injuries,
    p.days_lost,p.exposure_hours,p.incidence_per_1000h,p.burden_per_1000h,
    p.mean_severity_days
  from analysis.season_bound_league_effective_injury_profiles_v4 p
  union all
  select p.season,'diagnosis',p.code,p.label,p.setting_code,p.time_loss_injuries,
    p.days_lost,p.exposure_hours,p.incidence_per_1000h,p.burden_per_1000h,
    p.mean_severity_days
  from analysis.season_bound_league_diagnosis_profiles_v4 p
), profiles as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'dimension',p.dimension,'code',p.code,'label',p.label,'setting',p.setting_code,
      'time_loss_injuries',p.time_loss_injuries,'days_lost',p.days_lost,
      'exposure_hours',p.exposure_hours,'incidence_per_1000h',p.incidence_per_1000h,
      'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
    ) order by case when p.dimension='diagnosis' then 1 else 0 end,
      p.dimension,p.setting_code,p.time_loss_injuries desc,p.days_lost desc,p.code) as docs
  from profile_rows p
  group by p.season
), seasons as (
  select distinct season from analysis.league_member_releases_v2
)
select seasons.season,
  coalesce(body.docs,'[]'::jsonb) as body_locations,
  coalesce(types.docs,'[]'::jsonb) as injury_types,
  coalesce(profiles.docs,'[]'::jsonb) as injury_profiles
from seasons
left join body using (season)
left join types using (season)
left join profiles using (season);

create view analysis.league_dashboard_classification_incremental_20260722_v1
with (security_invoker = true) as
select context.season,context.analysis_version,
  rules.classification_view_version,rules.classification_evidence_sha256,
  context.cohort_view_version,context.cohort_evidence_sha256,
  jsonb_set(jsonb_set(jsonb_set(payload.dashboard_payload,
    '{body_locations}',sections.body_locations),
    '{injury_types}',sections.injury_types),
    '{injury_profiles}',sections.injury_profiles) as dashboard
from reporting.aggregate_releases release
join reporting.league_release_context_v2 context on context.release_id=release.id
join reporting.league_release_payloads_v2 payload on payload.release_id=release.id
join analysis.league_dashboard_classification_sections_v4 sections using (season)
cross join analysis.accepted_reporting_classification_rules_v4 rules
where release.status='approved'
  and context.analysis_version='v3'
  and context.classification_view_version='reporting_classification_2026-07-20_v1'
  and context.cohort_view_version='season_bound_2026-07-20_v1';

create view analysis.team_dashboard_classification_incremental_20260722_v1
with (security_invoker = true) as
select payload.team_key,context.season,payload.team_release_id,payload.curated_build_id,
  context.analysis_version,rules.classification_view_version,
  rules.classification_evidence_sha256,context.cohort_view_version,
  context.cohort_evidence_sha256,
  jsonb_set(jsonb_set(jsonb_set(payload.dashboard_payload,
    '{body_locations}',sections.body_locations),
    '{injury_types}',sections.injury_types),
    '{injury_profiles}',sections.injury_profiles) as dashboard
from reporting.aggregate_releases release
join reporting.league_release_context_v2 context on context.release_id=release.id
join reporting.team_dashboard_payloads_v2 payload on payload.bundle_release_id=release.id
join analysis.team_dashboard_classification_sections_v4 sections
  using (curated_build_id,team_key)
cross join analysis.accepted_reporting_classification_rules_v4 rules
where release.status='approved'
  and sections.season=context.season
  and context.analysis_version='v3'
  and context.classification_view_version='reporting_classification_2026-07-20_v1'
  and context.cohort_view_version='season_bound_2026-07-20_v1';

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
declare
  target_classification_version text;
begin
  select classification_view_version into target_classification_version
  from reporting.league_release_context_v2 where release_id=new.release_id;

  if target_classification_version='reporting_classification_2026-07-22_v2' then
    if not exists (
      select 1 from reporting.league_release_context_v2 context
      join analysis.league_dashboard_classification_incremental_20260722_v1 candidate
        on candidate.season=context.season and candidate.analysis_version=context.analysis_version
       and candidate.classification_view_version=context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
       and candidate.cohort_view_version=context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
       and candidate.dashboard=new.dashboard_payload
      where context.release_id=new.release_id
    ) then
      raise exception 'incremental league dashboard snapshot changed fields outside the accepted classification sections';
    end if;
  elsif not exists (
    select 1 from reporting.league_release_context_v2 context
    join analysis.league_dashboard_release_candidates_v5 candidate
      on candidate.season=context.season and candidate.analysis_version=context.analysis_version
     and candidate.classification_view_version=context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version=context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard=new.dashboard_payload
    where context.release_id=new.release_id
  ) then
    raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
  end if;
  return new;
end;
$$;

create or replace function reporting.validate_team_dashboard_v2_candidates()
returns trigger language plpgsql as $$
begin
  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id=payload.bundle_release_id
    left join analysis.team_dashboard_classification_incremental_20260722_v1 candidate
      on candidate.season=context.season and candidate.team_key=payload.team_key
     and candidate.team_release_id=payload.team_release_id
     and candidate.curated_build_id=payload.curated_build_id
     and candidate.analysis_version=context.analysis_version
     and candidate.classification_view_version=context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version=context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard=payload.dashboard_payload
    where context.classification_view_version='reporting_classification_2026-07-22_v2'
      and candidate.team_key is null
  ) then
    raise exception 'incremental team dashboard snapshots changed fields outside the accepted classification sections';
  end if;

  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id=payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v5 candidate
      on candidate.season=context.season and candidate.team_key=payload.team_key
     and candidate.team_release_id=payload.team_release_id
     and candidate.curated_build_id=payload.curated_build_id
     and candidate.analysis_version=context.analysis_version
     and candidate.classification_view_version=context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version=context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard=payload.dashboard_payload
    where context.classification_view_version<>'reporting_classification_2026-07-22_v2'
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;
  return null;
end;
$$;

comment on view analysis.league_dashboard_classification_incremental_20260722_v1 is
  'Copies the approved league dashboard and replaces only body_locations, injury_types, and injury_profiles for OSIICS-01.';
comment on view analysis.team_dashboard_classification_incremental_20260722_v1 is
  'Copies approved team dashboards and replaces only body_locations, injury_types, and injury_profiles for OSIICS-01.';
comment on function reporting.validate_league_dashboard_v2_candidate() is
  'Validates full releases against full candidates and OSIICS classification-only releases against the immutable incremental candidate.';
comment on function reporting.validate_team_dashboard_v2_candidates() is
  'Statement trigger validating full or classification-only team dashboard candidates without rebuilding unrelated metrics.';

revoke execute on function reporting.validate_league_dashboard_v2_candidate() from public;
revoke execute on function reporting.validate_team_dashboard_v2_candidates() from public;
