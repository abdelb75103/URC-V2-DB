-- Apply the reviewed 2025-26 explicit-context exposure rule to 2024-25.
-- Source, curated exposure, injuries, fixtures and historical releases remain unchanged.

alter table audit.reporting_cohort_rule_adjudications_v3
  drop constraint reporting_cohort_rule_adjudications_v3_migration_version_check,
  add constraint reporting_cohort_rule_adjudications_v3_migration_version_check check (
    migration_version in (
      '20260720170000', '20260724181000', '20260725190000',
      '20260815010000', '20260830120000'
    )
  );

insert into analysis.reporting_season_windows_v3
  (cohort_view_version, season, season_start, season_end, decision_ref)
values (
  'analysis_window_2024-25_2026-08-30_v2', '2024-25',
  date '2024-09-01', date '2025-06-30', 'EXPOSURE-SCOPE-2024-25-01'
);

insert into audit.reporting_cohort_rule_adjudications_v3
  (adjudication_ref, cohort_view_version, season, decision, evidence_sha256,
   evidence_locator, reviewer, migration_version, decided_at)
values (
  'EXPOSURE-SCOPE-2024-25-01',
  'analysis_window_2024-25_2026-08-30_v2',
  '2024-25',
  '{
    "exposure_rule":"exclude only rows with exact reviewed academy, age-grade, named non-cohort or explicit non-URC match source context; retain all other V5 rows",
    "fixture_rule":"unchanged registered fixtures inside the immutable reporting window multiplied by 20 player-hours per team participation",
    "injury_rule":"unchanged reviewed master-plus-ledger lineage",
    "window_rule":"unchanged inclusive 2024-09-01 through 2025-06-30",
    "mutation_rule":"append-only source-bound decisions over the immutable V5 exposure snapshot"
  }'::jsonb,
  'a56372cc531076ab00102413417fabd08d289fa296afed4f244b2db2d1132010',
  'docs/evidence/urc_2024-25_exposure_scope_successor_2026-08-30.json',
  'Abdel Babiker', '20260830120000', timestamptz '2026-08-30 00:00:00+00'
);

create view analysis.accepted_urc_2024_25_exposure_scope_rule_v1
with (security_invoker = true) as
select adjudication.cohort_view_version, adjudication.season,
  encode(digest(convert_to(jsonb_build_object(
    'adjudication_ref', adjudication.adjudication_ref,
    'decision', adjudication.decision,
    'evidence_sha256', adjudication.evidence_sha256,
    'evidence_locator', adjudication.evidence_locator,
    'reviewer', adjudication.reviewer,
    'migration_version', adjudication.migration_version
  )::text, 'UTF8'), 'sha256'), 'hex') as cohort_evidence_sha256
from audit.reporting_cohort_rule_adjudications_v3 adjudication
join analysis.reporting_season_windows_v3 reporting_window
  using (cohort_view_version, season)
where adjudication.adjudication_ref = 'EXPOSURE-SCOPE-2024-25-01'
  and adjudication.cohort_view_version = 'analysis_window_2024-25_2026-08-30_v2'
  and adjudication.season = '2024-25'
  and adjudication.evidence_sha256 =
    'a56372cc531076ab00102413417fabd08d289fa296afed4f244b2db2d1132010'
  and adjudication.evidence_locator =
    'docs/evidence/urc_2024-25_exposure_scope_successor_2026-08-30.json'
  and adjudication.reviewer = 'Abdel Babiker'
  and adjudication.migration_version = '20260830120000';

create table audit.urc_2024_25_exposure_scope_decisions_v1 (
  exposure_id uuid primary key,
  source_row_id uuid not null unique,
  team_key text not null,
  source_row_sha256 text not null check (source_row_sha256 ~ '^[0-9a-f]{64}$'),
  reason_code text not null check (reason_code in (
    'explicit_non_urc_match', 'academy_or_age_grade', 'other_named_non_cohort'
  )),
  minutes_clean numeric not null,
  distance_m_clean numeric,
  decided_by text not null check (decided_by = 'Abdel Babiker'),
  cohort_view_version text not null check (
    cohort_view_version = 'analysis_window_2024-25_2026-08-30_v2'
  ),
  decided_at timestamptz not null
);
alter table audit.urc_2024_25_exposure_scope_decisions_v1 enable row level security;
create trigger urc_2024_25_exposure_scope_decisions_v1_immutable
before update or delete on audit.urc_2024_25_exposure_scope_decisions_v1
for each row execute function audit.reject_reporting_cohort_rule_adjudication_v3_mutation();

insert into audit.urc_2024_25_exposure_scope_decisions_v1 (
  exposure_id, source_row_id, team_key, source_row_sha256, reason_code,
  minutes_clean, distance_m_clean, decided_by, cohort_view_version, decided_at
)
select exposure.exposure_id, exposure.source_row_id, exposure.team_key,
  source.source_values ->> 'source_row_sha256',
  case
    when exposure.team_key = 'cardiff'
      and source.source_values ->> 'Competition' = 'Age Grade'
      then 'academy_or_age_grade'
    when exposure.team_key = 'edinburgh'
      and source.source_values ->> 'session type' in (
        'Academy Training', 'Academy Units', 'Academy Units & Training'
      ) then 'academy_or_age_grade'
    when exposure.team_key = 'glasgow'
      and source.source_values ->> 'Training With' = 'Scottish Prem'
      then 'other_named_non_cohort'
    else 'explicit_non_urc_match'
  end,
  exposure.minutes_clean, exposure.distance_m_clean, 'Abdel Babiker',
  'analysis_window_2024-25_2026-08-30_v2', timestamptz '2026-08-30 00:00:00+00'
from analysis.analysis_window_effective_exposure_cohort_v5_snapshot exposure
join analysis.league_member_releases_v2 member
  using (curated_build_id, team_key, season)
join ingestion.source_rows source on source.id = exposure.source_row_id
where exposure.season = '2024-25'
  and exposure.effective_eligibility_status = 'included_pending_protocol'
  and (
    (exposure.team_key = 'cardiff' and (
      source.source_values ->> 'Competition' = 'Age Grade'
      or (
        source.source_values ->> 'session type' = 'Match'
        and source.source_values ->> 'Competition' in (
          'Europe Challenge Cup', 'Pro 14', 'SRC'
        )
      )
    ))
    or (exposure.team_key = 'dragons'
      and source.source_values ->> 'session type' = 'Match'
      and source.source_values ->> 'Competition' = 'Europe Challenge Cup')
    or (exposure.team_key = 'edinburgh'
      and source.source_values ->> 'session type' in (
        'Academy Training', 'Academy Units', 'Academy Units & Training'
      ))
    or (exposure.team_key = 'glasgow'
      and source.source_values ->> 'Training With' = 'Scottish Prem')
    or (exposure.team_key = 'ospreys' and (
      source.source_values ->> 'session type' = 'SRC Match'
      or (
        source.source_values ->> 'session type' = 'Match'
        and source.source_values ->> 'Competition' in (
          'Europe Challenge Cup', 'Friendly'
        )
      )
    ))
    or (exposure.team_key = 'scarlets'
      and source.source_values ->> 'session type' = 'Match'
      and source.source_values ->> 'Competition' in (
        'Europe Challenge Cup', 'Friendly'
      ))
  );

create materialized view analysis.urc_2024_25_effective_exposure_scope_v1 as
select exposure.*
from analysis.analysis_window_effective_exposure_cohort_v5_snapshot exposure
join analysis.league_member_releases_v2 member
  using (curated_build_id, team_key, season)
left join audit.urc_2024_25_exposure_scope_decisions_v1 decision
  on decision.exposure_id = exposure.exposure_id
where exposure.season = '2024-25'
  and exposure.effective_eligibility_status = 'included_pending_protocol'
  and decision.exposure_id is null;
create unique index urc_2024_25_effective_exposure_scope_v1_row
  on analysis.urc_2024_25_effective_exposure_scope_v1 (exposure_id);

create materialized view analysis.urc_2024_25_exposure_scope_team_v1 as
with included as (
  select exposure.*, source.player_uid
  from analysis.urc_2024_25_effective_exposure_scope_v1 exposure
  join curated.exposure source on source.id = exposure.exposure_id
), scope_counts as (
  select team_key, curated_build_id,
    jsonb_object_agg(scope_status, rows order by scope_status) as counts
  from (
    select team_key, curated_build_id, scope_status, count(*) as rows
    from included where scope_status is not null
    group by team_key, curated_build_id, scope_status
  ) grouped
  group by team_key, curated_build_id
)
select included.team_key, included.curated_build_id, included.season,
  count(*)::bigint as exposure_rows,
  count(distinct nullif(included.player_uid, ''))::bigint as exposed_players,
  count(distinct case when included.reporting_grain = 'weekly'
    then included.effective_period_start end)::bigint as weeks,
  count(distinct included.effective_period_start)::bigint as exposure_periods,
  sum(included.minutes_clean) / 60 as exposure_hours,
  sum(included.distance_m_clean) / 1000 as distance_km,
  min(included.effective_period_start) as coverage_start,
  max(included.effective_period_end) as coverage_end,
  case when count(distinct included.reporting_grain) = 1
    then min(included.reporting_grain) else 'mixed' end as exposure_grain,
  coalesce(scope_counts.counts, '{}'::jsonb) as scope_status_counts
from included
left join scope_counts using (team_key, curated_build_id)
group by included.team_key, included.curated_build_id, included.season,
  scope_counts.counts;
create unique index urc_2024_25_exposure_scope_team_v1_key
  on analysis.urc_2024_25_exposure_scope_team_v1 (team_key, curated_build_id);

create materialized view analysis.urc_2024_25_exposure_scope_monthly_v1 as
select team_key, curated_build_id, season,
  to_char(date_trunc('month', effective_period_start), 'Mon YYYY') as month,
  sum(minutes_clean) / 60 as exposure_hours,
  sum(distance_m_clean) / 1000 as distance_km
from analysis.urc_2024_25_effective_exposure_scope_v1
group by team_key, curated_build_id, season,
  date_trunc('month', effective_period_start);
create unique index urc_2024_25_exposure_scope_monthly_v1_key
  on analysis.urc_2024_25_exposure_scope_monthly_v1
  (team_key, curated_build_id, month);

create view analysis.urc_2024_25_exposure_scope_league_summary_v1
with (security_invoker = true) as
select season, sum(exposure_hours) as exposure_hours
from analysis.urc_2024_25_exposure_scope_team_v1 group by season;

create view analysis.urc_2024_25_exposure_scope_league_monthly_v1
with (security_invoker = true) as
select monthly.season, monthly.month,
  sum(monthly.exposure_hours) as exposure_hours,
  sum(monthly.distance_km) as distance_km,
  max((source ->> 'time_loss_injuries')::bigint) as time_loss_injuries
from analysis.urc_2024_25_exposure_scope_monthly_v1 monthly
join analysis.urc_2024_25_league_dashboard_candidate_v3 candidate
  on candidate.season = monthly.season
join lateral jsonb_array_elements(candidate.dashboard -> 'monthly') source
  on source ->> 'month' = monthly.month
group by monthly.season, monthly.month;

create function analysis.urc_2024_25_rebase_metric_v1(item jsonb, hours numeric)
returns jsonb language sql immutable as $$
select case when hours is null then item else item
  || jsonb_build_object('exposure_hours', hours)
  || case when item ? 'incidence_per_1000h' then jsonb_build_object(
       'incidence_per_1000h', (item ->> 'time_loss_injuries')::numeric * 1000 / nullif(hours, 0)
     ) else '{}'::jsonb end
  || case when item ? 'overall_incidence_per_1000h' then jsonb_build_object(
       'overall_incidence_per_1000h', (item ->> 'recorded_injuries')::numeric * 1000 / nullif(hours, 0)
     ) else '{}'::jsonb end
  || case when item ? 'burden_per_1000h' then jsonb_build_object(
       'burden_per_1000h', (item ->> 'days_lost')::numeric * 1000 / nullif(hours, 0)
     ) else '{}'::jsonb end end
$$;

create function analysis.urc_2024_25_rebase_dashboard_v1(
  dashboard jsonb, total_hours numeric, match_hours numeric,
  coverage jsonb, monthly_rows jsonb
) returns jsonb language plpgsql immutable as $$
declare
  training_hours numeric := total_hours - match_hours;
  result jsonb := dashboard;
  rows jsonb;
begin
  select jsonb_agg(case item ->> 'key'
    when 'overall_incidence_per_1000h' then item || jsonb_build_object(
      'value', (item ->> 'numerator')::numeric * 1000 / nullif(total_hours, 0),
      'denominator', total_hours)
    when 'incidence_per_1000h' then item || jsonb_build_object(
      'value', (item ->> 'numerator')::numeric * 1000 / nullif(total_hours, 0),
      'denominator', total_hours)
    when 'burden_per_1000h' then item || jsonb_build_object(
      'value', (item ->> 'numerator')::numeric * 1000 / nullif(total_hours, 0),
      'denominator', total_hours)
    else item end order by ordinality) into rows
  from jsonb_array_elements(result -> 'headline') with ordinality source(item, ordinality);
  result := jsonb_set(result, '{headline}', rows) || jsonb_build_object('coverage', coverage);

  select jsonb_agg(analysis.urc_2024_25_rebase_metric_v1(item, total_hours)
    order by ordinality) into rows
  from jsonb_array_elements(result -> 'body_locations') with ordinality source(item, ordinality);
  result := jsonb_set(result, '{body_locations}', rows);
  select jsonb_agg(analysis.urc_2024_25_rebase_metric_v1(item, total_hours)
    order by ordinality) into rows
  from jsonb_array_elements(result -> 'injury_types') with ordinality source(item, ordinality);
  result := jsonb_set(result, '{injury_types}', rows);

  select jsonb_agg(analysis.urc_2024_25_rebase_metric_v1(item,
    case item ->> 'setting' when 'all' then total_hours
      when 'training' then training_hours when 'match' then match_hours end)
    order by ordinality) into rows
  from jsonb_array_elements(result -> 'injury_profiles') with ordinality source(item, ordinality);
  result := jsonb_set(result, '{injury_profiles}', rows);

  select jsonb_agg(analysis.urc_2024_25_rebase_metric_v1(item,
    case coalesce(item ->> 'setting', item ->> 'key')
      when 'training' then training_hours when 'match' then match_hours end)
    order by ordinality) into rows
  from jsonb_array_elements(result -> 'setting_split') with ordinality source(item, ordinality);
  result := jsonb_set(result, '{setting_split}', rows);
  select jsonb_agg(analysis.urc_2024_25_rebase_metric_v1(item,
    case item ->> 'setting' when 'training' then training_hours
      when 'match' then match_hours end) order by ordinality) into rows
  from jsonb_array_elements(result -> 'setting_metrics') with ordinality source(item, ordinality);
  result := jsonb_set(result, '{setting_metrics}', rows);

  result := jsonb_set(result, '{injury_type_families}',
    analysis.injury_type_families_from_payload_v1(result -> 'injury_profiles'));

  select jsonb_agg(analysis.urc_2024_25_rebase_metric_v1(
    item || jsonb_build_object('distance_km', coalesce(
      (month_row ->> 'distance_km')::numeric,
      (item ->> 'distance_km')::numeric)),
    coalesce((month_row ->> 'exposure_hours')::numeric,
      (item ->> 'exposure_hours')::numeric)) order by ordinality) into rows
  from jsonb_array_elements(result -> 'monthly') with ordinality source(item, ordinality)
  left join lateral (
    select candidate_month as month_row
    from jsonb_array_elements(monthly_rows) candidate_month
    where candidate_month ->> 'month' = item ->> 'month'
  ) matched on true;
  result := jsonb_set(result, '{monthly}', rows);
  return result;
end;
$$;

create materialized view analysis.urc_2024_25_team_dashboard_candidate_v4 as
with monthly as (
  select team_key, curated_build_id,
    jsonb_agg(jsonb_build_object('month', month, 'exposure_hours', exposure_hours,
      'distance_km', distance_km) order by to_date(month, 'Mon YYYY')) as rows
  from analysis.urc_2024_25_exposure_scope_monthly_v1
  group by team_key, curated_build_id
), prepared as (
  select candidate.*, coverage.exposure_hours,
    (candidate.dashboard -> 'coverage' ->> 'match_hours')::numeric as match_hours,
    candidate.dashboard -> 'coverage' || jsonb_build_object(
      'hours', coverage.exposure_hours,
      'training_hours', coverage.exposure_hours -
        (candidate.dashboard -> 'coverage' ->> 'match_hours')::numeric,
      'distance_km', coverage.distance_km,
      'exposure_rows', coverage.exposure_rows,
      'exposed_players', coverage.exposed_players,
      'weeks', coverage.weeks,
      'exposure_periods', coverage.exposure_periods,
      'exposure_grain', coverage.exposure_grain,
      'scope_status_counts', coverage.scope_status_counts
    ) as corrected_coverage,
    monthly.rows as corrected_monthly
  from analysis.urc_2024_25_team_dashboard_candidate_v3 candidate
  join analysis.urc_2024_25_exposure_scope_team_v1 coverage
    using (team_key, curated_build_id, season)
  join monthly using (team_key, curated_build_id)
)
select prepared.team_key, prepared.season, prepared.team_release_id,
  prepared.curated_build_id, prepared.analysis_version,
  prepared.classification_view_version,
  rule.cohort_view_version, rule.cohort_evidence_sha256,
  prepared.classification_evidence_sha256,
  analysis.urc_2024_25_rebase_dashboard_v1(
    prepared.dashboard, prepared.exposure_hours, prepared.match_hours,
    prepared.corrected_coverage, prepared.corrected_monthly
  ) as dashboard,
  prepared.predecessor_release_id,
  prepared.predecessor_canonical_bundle_sha256,
  prepared.predecessor_league_payload_sha256,
  prepared.predecessor_team_payload_set_sha256
from prepared cross join analysis.accepted_urc_2024_25_exposure_scope_rule_v1 rule;

create materialized view analysis.urc_2024_25_league_dashboard_candidate_v4 as
with coverage_windows as (
  select jsonb_agg(jsonb_build_object('start', coverage_start, 'end', coverage_end,
    'teams', teams) order by coverage_start, coverage_end) as rows
  from (select coverage_start, coverage_end, count(*) as teams
    from analysis.urc_2024_25_exposure_scope_team_v1
    group by coverage_start, coverage_end) grouped
), coverage as (
  select sum(exposure_rows) as exposure_rows,
    sum(exposed_players) as exposed_players, sum(weeks) as weeks,
    sum(exposure_periods) as exposure_periods,
    sum(exposure_hours) as exposure_hours, sum(distance_km) as distance_km,
    case when count(distinct exposure_grain) = 1 then min(exposure_grain)
      else 'mixed' end as exposure_grain
  from analysis.urc_2024_25_exposure_scope_team_v1
), monthly as (
  select jsonb_agg(jsonb_build_object('month', month,
    'exposure_hours', exposure_hours, 'distance_km', distance_km)
    order by to_date(month, 'Mon YYYY')) as rows
  from analysis.urc_2024_25_exposure_scope_league_monthly_v1
)
select candidate.season, candidate.team, candidate.analysis_version,
  candidate.classification_view_version, rule.cohort_view_version,
  rule.cohort_evidence_sha256, candidate.classification_evidence_sha256,
  analysis.urc_2024_25_rebase_dashboard_v1(
    candidate.dashboard, coverage.exposure_hours,
    (candidate.dashboard -> 'coverage' ->> 'match_hours')::numeric,
    candidate.dashboard -> 'coverage' || jsonb_build_object(
      'hours', coverage.exposure_hours,
      'training_hours', coverage.exposure_hours -
        (candidate.dashboard -> 'coverage' ->> 'match_hours')::numeric,
      'distance_km', coverage.distance_km,
      'exposure_rows', coverage.exposure_rows,
      'exposed_players', coverage.exposed_players,
      'weeks', coverage.weeks,
      'exposure_periods', coverage.exposure_periods,
      'exposure_grain', coverage.exposure_grain,
      'coverage_windows', coverage_windows.rows
    ), monthly.rows
  ) as dashboard,
  candidate.predecessor_release_id,
  candidate.predecessor_canonical_bundle_sha256,
  candidate.predecessor_league_payload_sha256,
  candidate.predecessor_team_payload_set_sha256
from analysis.urc_2024_25_league_dashboard_candidate_v3 candidate
cross join coverage cross join coverage_windows cross join monthly
cross join analysis.accepted_urc_2024_25_exposure_scope_rule_v1 rule;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_team_dashboard_candidate_v4
union all
select team_key, season, team_release_id, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_team_dashboard_candidate_v3;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, analysis_version, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_league_dashboard_candidate_v4
union all
select season, analysis_version, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.urc_2024_25_league_dashboard_candidate_v3;

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_cohort_view_version_check,
  add constraint league_release_context_v2_cohort_view_version_check check (
    cohort_view_version in (
      'v2', 'season_bound_2026-07-20_v1',
      'lineage_2024-25_2026-07-24_v1',
      'analysis_window_2024-25_2026-07-25_v1',
      'analysis_window_2024-25_2026-08-30_v2',
      'analysis_window_2025-26_2026-08-15_v1'
    )
  );
alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_decision_recorded_at_check,
  add constraint league_release_context_v2_decision_recorded_at_check check (
    (analysis_version = 'v2' and decision_recorded_at = date '2026-07-14') or
    (analysis_version = 'v3' and decision_recorded_at = date '2026-07-19') or
    (analysis_version = 'v4' and decision_recorded_at = date '2026-07-24') or
    (analysis_version = 'v5' and cohort_view_version =
      'analysis_window_2024-25_2026-07-25_v1'
      and decision_recorded_at = date '2026-07-25') or
    (analysis_version = 'v5' and cohort_view_version =
      'analysis_window_2024-25_2026-08-30_v2'
      and decision_recorded_at = date '2026-08-30') or
    (analysis_version = 'v6' and decision_recorded_at = date '2026-08-15')
  );

-- The correction-aware guard remains tied to the same accepted injury set.
create or replace function reporting.guard_active_row_corrections_v1()
returns trigger language plpgsql security definer
set search_path = pg_catalog, analysis, audit, reporting as $$
declare target_season text; successor_is_correction_aware boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status = 'approved' then
      raise exception 'aggregate releases must be inserted as draft before approval';
    end if;
    return new;
  end if;
  if old.status = 'draft' and new.status = 'approved'
    and not exists (select 1 from reporting.correction_release_context_v1 where bundle_release_id = new.id)
    and not exists (select 1 from reporting.correction_rollback_context_v1 where bundle_release_id = new.id) then
    select context.season,
      context.analysis_version = 'v5'
      and context.classification_view_version = 'reporting_classification_2024-25_2026-08-27_v1'
      and context.cohort_view_version in (
        'analysis_window_2024-25_2026-07-25_v1',
        'analysis_window_2024-25_2026-08-30_v2'
      )
      and audit.row_correction_set_hash_v3(context.season, null) =
        'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'
    into target_season, successor_is_correction_aware
    from reporting.league_release_context_v2 context where context.release_id = new.id;
    if target_season is not null and not coalesce(successor_is_correction_aware, false)
      and (exists (select 1 from analysis.row_correction_served_sets_v1 where season = target_season)
        or exists (select 1 from audit.correction_sets_v1 pending where pending.season = target_season
          and not exists (select 1 from reporting.correction_release_context_v1 promoted
            where promoted.correction_set_id = pending.id))) then
      raise exception 'ordinary release approval blocked while served row corrections are active or a correction is pending';
    end if;
  end if;
  if old.status = 'approved' and new.status = 'retired' then
    select context.season into target_season
    from reporting.dashboard_bundle_context_v1 context where context.release_id = old.id;
    if exists (select 1 from analysis.row_correction_served_sets_v1 where season = target_season)
      and not exists (
        select 1 from reporting.aggregate_releases successor
        join reporting.dashboard_bundle_context_v1 successor_context on successor_context.release_id = successor.id
        left join reporting.league_release_context_v2 league_context on league_context.release_id = successor.id
        left join reporting.correction_release_context_v1 correction on correction.bundle_release_id = successor.id
        left join reporting.correction_rollback_context_v1 rollback on rollback.bundle_release_id = successor.id
        where successor.status = 'draft' and successor_context.season = target_season
          and (correction.bundle_release_id is not null or rollback.bundle_release_id is not null
            or (league_context.analysis_version = 'v5'
              and league_context.classification_view_version = 'reporting_classification_2024-25_2026-08-27_v1'
              and league_context.cohort_view_version in (
                'analysis_window_2024-25_2026-07-25_v1',
                'analysis_window_2024-25_2026-08-30_v2'
              )
              and audit.row_correction_set_hash_v3(target_season, null) =
                'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'))
      ) then raise exception 'ordinary release blocked while served row corrections are active';
    end if;
  end if;
  return new;
end;
$$;

do $$
declare decision_hash text; retained_hash text;
begin
  if not exists (
    select 1 from reporting.latest_approved_dashboard_bundle_v4 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join reporting.dashboard_bundle_league_payloads_v1 payload
      on payload.release_id = latest.release_id
    where latest.season = '2024-25'
      and latest.release_id = '20f2b6ed-d3d3-4349-88b9-fc5c9f143eed'::uuid
      and release.release_label = 'urc-2024-25-v5-0445139ad3a3-a1'
      and payload.payload_sha256 =
        'df8e86d801de8f6f7d3ebfeade21baa24d8763f36fa1f113ca2d0e1456a7e271'
      and (select count(*) from reporting.dashboard_bundle_team_payloads_v1 team
        where team.bundle_release_id = latest.release_id) = 16
  ) then raise exception 'exposure-scope successor predecessor drift'; end if;

  select encode(digest(convert_to(string_agg(
    team_key || '|' || source_row_sha256 || '|' || reason_code,
    E'\n' order by team_key || '|' || source_row_sha256 || '|' || reason_code
  ) || E'\n', 'UTF8'), 'sha256'), 'hex') into decision_hash
  from audit.urc_2024_25_exposure_scope_decisions_v1;
  if (select count(*) from audit.urc_2024_25_exposure_scope_decisions_v1) <> 1238
    or round((select sum(minutes_clean) / 60
      from audit.urc_2024_25_exposure_scope_decisions_v1), 6) <> 1444.576389
    or decision_hash <> '672f788e8fea5220fe30a8742eca6b1561a2ad092a545667a5ab50a697fa4086'
  then raise exception 'exposure-scope decision reconciliation failed'; end if;

  select encode(digest(convert_to(string_agg(
    exposure.team_key || '|' || (source.source_values ->> 'source_row_sha256'),
    E'\n' order by exposure.team_key || '|' ||
      (source.source_values ->> 'source_row_sha256')
  ) || E'\n', 'UTF8'), 'sha256'), 'hex') into retained_hash
  from analysis.urc_2024_25_effective_exposure_scope_v1 exposure
  join ingestion.source_rows source on source.id = exposure.source_row_id;
  if retained_hash <>
    '5cd015547c05a3910e4743e8a3b705b4cf718982ec76df55b8fc4bf6625d3075'
  then raise exception 'exposure-scope retained rowset reconciliation failed'; end if;

  if (select count(*) from analysis.urc_2024_25_effective_exposure_scope_v1) <> 63273
    or round((select sum(minutes_clean) / 60
      from analysis.urc_2024_25_effective_exposure_scope_v1), 6) <> 79908.343109
    or (select count(*) from analysis.urc_2024_25_team_dashboard_candidate_v4) <> 16
    or (select count(*) from analysis.urc_2024_25_league_dashboard_candidate_v4) <> 1
  then raise exception 'exposure-scope successor cardinality failed'; end if;

  if exists (
    with expected(team_key, rows, hours) as (values
      ('cardiff',341,363.778333::numeric), ('dragons',91,96.833333),
      ('edinburgh',391,524.938611), ('glasgow',40,60.797778),
      ('ospreys',235,254.391667), ('scarlets',140,143.836667)
    ), actual as (
      select team_key, count(*)::integer as rows, round(sum(minutes_clean) / 60, 6) as hours
      from audit.urc_2024_25_exposure_scope_decisions_v1 group by team_key
    ) select 1 from expected full join actual using (team_key)
      where (expected.rows, expected.hours) is distinct from (actual.rows, actual.hours)
  ) then raise exception 'exposure-scope team reconciliation failed'; end if;

  if exists (
    select 1 from analysis.urc_2024_25_team_dashboard_candidate_v4 successor
    join analysis.urc_2024_25_team_dashboard_candidate_v3 predecessor
      using (team_key, curated_build_id, season)
    where successor.team_key not in ('cardiff','dragons','edinburgh','glasgow','ospreys','scarlets')
      and successor.dashboard <> predecessor.dashboard
  ) then raise exception 'unaffected team payload drift'; end if;

  if exists (
    select 1 from analysis.urc_2024_25_team_dashboard_candidate_v4 successor
    join analysis.urc_2024_25_team_dashboard_candidate_v3 predecessor
      using (team_key, curated_build_id, season)
    where jsonb_array_length(successor.dashboard -> 'monthly') <>
        jsonb_array_length(predecessor.dashboard -> 'monthly')
      or successor.dashboard #>> '{coverage,match_hours}' <>
        predecessor.dashboard #>> '{coverage,match_hours}'
      or exists (
        select 1
        from jsonb_array_elements(successor.dashboard -> 'headline') metric
        where metric ->> 'key' in (
          'overall_incidence_per_1000h', 'incidence_per_1000h', 'burden_per_1000h'
        ) and (metric ->> 'denominator')::numeric <>
          (successor.dashboard #>> '{coverage,hours}')::numeric
      )
  ) then raise exception 'team exposure denominator reconciliation failed'; end if;

  if exists (
    select 1 from analysis.urc_2024_25_league_dashboard_candidate_v4 successor
    join analysis.urc_2024_25_league_dashboard_candidate_v3 predecessor using (season)
    where jsonb_array_length(successor.dashboard -> 'monthly') <>
        jsonb_array_length(predecessor.dashboard -> 'monthly')
      or successor.dashboard #>> '{coverage,match_hours}' <>
        predecessor.dashboard #>> '{coverage,match_hours}'
      or exists (
        select 1
        from jsonb_array_elements(successor.dashboard -> 'headline') metric
        where metric ->> 'key' in (
          'overall_incidence_per_1000h', 'incidence_per_1000h', 'burden_per_1000h'
        ) and (metric ->> 'denominator')::numeric <>
          (successor.dashboard #>> '{coverage,hours}')::numeric
      )
  ) then raise exception 'league exposure denominator reconciliation failed'; end if;

  if exists (
    select 1 from analysis.urc_2024_25_team_dashboard_candidate_v4 successor
    join analysis.urc_2024_25_team_dashboard_candidate_v3 predecessor
      using (team_key, curated_build_id, season)
    where successor.dashboard - array['coverage','headline','monthly','body_locations',
      'injury_types','injury_profiles','injury_type_families','setting_split','setting_metrics']
      <> predecessor.dashboard - array['coverage','headline','monthly','body_locations',
      'injury_types','injury_profiles','injury_type_families','setting_split','setting_metrics']
  ) then raise exception 'team successor changed a non-exposure payload section'; end if;

  if exists (
    select 1 from analysis.urc_2024_25_league_dashboard_candidate_v4 successor
    join analysis.urc_2024_25_league_dashboard_candidate_v3 predecessor using (season)
    where successor.dashboard - array['coverage','headline','monthly','body_locations',
      'injury_types','injury_profiles','injury_type_families','setting_split','setting_metrics']
      <> predecessor.dashboard - array['coverage','headline','monthly','body_locations',
      'injury_types','injury_profiles','injury_type_families','setting_split','setting_metrics']
  ) then raise exception 'league successor changed a non-exposure payload section'; end if;
end;
$$;

revoke all on audit.urc_2024_25_exposure_scope_decisions_v1,
  analysis.urc_2024_25_effective_exposure_scope_v1,
  analysis.urc_2024_25_exposure_scope_team_v1,
  analysis.urc_2024_25_exposure_scope_monthly_v1,
  analysis.urc_2024_25_team_dashboard_candidate_v4,
  analysis.urc_2024_25_league_dashboard_candidate_v4
from public, anon, authenticated;
