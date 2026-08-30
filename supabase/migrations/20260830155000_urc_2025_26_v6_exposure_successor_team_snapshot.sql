-- Seal the 16 exact team candidates after the reviewed exposure successor.
-- The public candidate relation remains available only while the active build
-- and placeholder event set matches the state used to create this snapshot.

set local statement_timeout = 0;

create table analysis.team_dashboard_release_candidate_snapshot_v6_20260830 (
  snapshot_version text not null,
  active_state_sha256 text not null check (active_state_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  team_key text not null,
  season text not null check (season = '2025-26'),
  team_release_id uuid,
  curated_build_id uuid not null,
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null,
  classification_evidence_sha256 text not null,
  cohort_view_version text not null,
  cohort_evidence_sha256 text not null,
  dashboard jsonb not null,
  processing_eligible_injury_count bigint not null,
  eligible_curated_injury_count bigint not null,
  recorded_cohort_count bigint not null,
  processing_record_version_set_sha256 text not null,
  curated_record_version_set_sha256 text not null,
  reporting_record_version_set_sha256 text not null,
  approved_injury_source_file_count bigint not null,
  unapproved_injury_source_row_count bigint not null,
  wrong_problem_type_rule_version_count bigint not null,
  created_at timestamptz not null default now(),
  primary key (snapshot_version, team_key),
  unique (snapshot_version, curated_build_id)
);

alter table analysis.team_dashboard_release_candidate_snapshot_v6_20260830
  enable row level security;
revoke all on analysis.team_dashboard_release_candidate_snapshot_v6_20260830
  from public, anon, authenticated, web_reader;

create function analysis.reject_team_candidate_snapshot_v6_20260830_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'Year 2 exposure-successor team candidate snapshot is immutable';
end;
$$;

create trigger team_candidate_snapshot_v6_20260830_immutable
before update or delete
on analysis.team_dashboard_release_candidate_snapshot_v6_20260830
for each row execute function analysis.reject_team_candidate_snapshot_v6_20260830_mutation();

with active_builds as materialized (
  select team_key, season, curated_build_id
  from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), build_state as (
  select season, jsonb_agg(
    jsonb_build_object(
      'team_key', team_key,
      'curated_build_id', curated_build_id::text
    ) order by team_key
  ) as builds
  from active_builds
  group by season
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct curated_build_id) = 16
), placeholder_state as (
  select season, jsonb_agg(
    jsonb_build_object(
      'team_key', team_key,
      'event_id', event_id,
      'method', method,
      'estimated_total_hours', estimated_total_hours,
      'evidence_sha256', evidence_sha256
    ) order by team_key
  ) as placeholders
  from analysis.active_exposure_placeholders_v1
  where season = '2025-26'
  group by season
  having count(*) = 2
    and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
    and min(estimated_total_hours) = max(estimated_total_hours)
    and count(*) filter (
      where method = 'mean_of_other_14_source_backed_team_hours_v1'
        and evidence_sha256 =
          '66ba0a272de96510106a68c74046d4bf59ab04570ed38d83cbb98665f51c3ce1'
    ) = 2
), active_state as (
  select build_state.season,
    reporting.canonical_jsonb_sha256_v1(jsonb_build_object(
      'builds', build_state.builds,
      'placeholders', placeholder_state.placeholders
    )) as active_state_sha256
  from build_state
  join placeholder_state using (season)
), candidate as materialized (
  select candidate.*
  from analysis.team_dashboard_release_candidates_analysis_window_v6 candidate
  where candidate.season = '2025-26'
)
insert into analysis.team_dashboard_release_candidate_snapshot_v6_20260830 (
  snapshot_version, active_state_sha256, payload_sha256,
  team_key, season, team_release_id, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard,
  processing_eligible_injury_count, eligible_curated_injury_count,
  recorded_cohort_count, processing_record_version_set_sha256,
  curated_record_version_set_sha256, reporting_record_version_set_sha256,
  approved_injury_source_file_count, unapproved_injury_source_row_count,
  wrong_problem_type_rule_version_count
)
select '20260830155000', active_state.active_state_sha256,
  reporting.canonical_jsonb_sha256_v1(candidate.dashboard),
  candidate.team_key, candidate.season, candidate.team_release_id,
  candidate.curated_build_id, candidate.analysis_version,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version, candidate.cohort_evidence_sha256,
  candidate.dashboard, candidate.processing_eligible_injury_count,
  candidate.eligible_curated_injury_count, candidate.recorded_cohort_count,
  candidate.processing_record_version_set_sha256,
  candidate.curated_record_version_set_sha256,
  candidate.reporting_record_version_set_sha256,
  candidate.approved_injury_source_file_count,
  candidate.unapproved_injury_source_row_count,
  candidate.wrong_problem_type_rule_version_count
from candidate
join active_state using (season);

do $$
begin
  if (
    select count(*)
    from analysis.team_dashboard_release_candidate_snapshot_v6_20260830
    where snapshot_version = '20260830155000'
      and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
  ) <> 16
    or (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260830
      where snapshot_version = '20260830155000'
        and dashboard #>> '{coverage,included_exposure_status}' =
          'temporary_league_mean_estimate_no_source_exposure'
        and team_key in ('benetton', 'edinburgh')
    ) <> 2
  then
    raise exception 'Year 2 exposure-successor team snapshot is incomplete';
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
  select season, jsonb_agg(
    jsonb_build_object(
      'team_key', team_key,
      'curated_build_id', curated_build_id::text
    ) order by team_key
  ) as builds
  from active_builds
  group by season
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct curated_build_id) = 16
), placeholder_state as (
  select season, jsonb_agg(
    jsonb_build_object(
      'team_key', team_key,
      'event_id', event_id,
      'method', method,
      'estimated_total_hours', estimated_total_hours,
      'evidence_sha256', evidence_sha256
    ) order by team_key
  ) as placeholders
  from analysis.active_exposure_placeholders_v1
  where season = '2025-26'
  group by season
  having count(*) = 2
    and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
    and min(estimated_total_hours) = max(estimated_total_hours)
    and count(*) filter (
      where method = 'mean_of_other_14_source_backed_team_hours_v1'
        and evidence_sha256 =
          '66ba0a272de96510106a68c74046d4bf59ab04570ed38d83cbb98665f51c3ce1'
    ) = 2
), active_state as (
  select build_state.season,
    reporting.canonical_jsonb_sha256_v1(jsonb_build_object(
      'builds', build_state.builds,
      'placeholders', placeholder_state.placeholders
    )) as active_state_sha256
  from build_state
  join placeholder_state using (season)
)
select snapshot.team_key, snapshot.season, snapshot.team_release_id,
  snapshot.curated_build_id, snapshot.analysis_version,
  snapshot.classification_view_version,
  snapshot.classification_evidence_sha256,
  snapshot.cohort_view_version, snapshot.cohort_evidence_sha256,
  snapshot.dashboard, snapshot.processing_eligible_injury_count,
  snapshot.eligible_curated_injury_count, snapshot.recorded_cohort_count,
  snapshot.processing_record_version_set_sha256,
  snapshot.curated_record_version_set_sha256,
  snapshot.reporting_record_version_set_sha256,
  snapshot.approved_injury_source_file_count,
  snapshot.unapproved_injury_source_row_count,
  snapshot.wrong_problem_type_rule_version_count
from analysis.team_dashboard_release_candidate_snapshot_v6_20260830 snapshot
join active_state
  on active_state.season = snapshot.season
 and active_state.active_state_sha256 = snapshot.active_state_sha256
where snapshot.snapshot_version = '20260830155000'
  and snapshot.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.team_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;
