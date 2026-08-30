-- Performance-only successor to the Year 2 injury reconciliation guard.
-- Aggregate each signed source set once before joining the sixteen active builds.
-- Candidate columns, dashboard bytes and release predicates remain unchanged.

create or replace view analysis.urc_2025_26_injury_cohort_reconciliation_v1
with (security_invoker = true) as
with active as (
  select build.id as curated_build_id, build.team_key, build.season
  from curated.builds build
  join reporting.teams team
    on team.team_key = build.team_key
   and team.active
  where build.season = '2025-26'
    and build.status = 'active'
), processing_latest_versions as (
  select source_row_id, max(version_number) as version_number
  from processing.record_versions
  group by source_row_id
), processing as (
  select rv.id as record_version_id, alias.team_key, sf.file_sha256,
    step.step_version, rv.eligibility_status,
    rv.record_state ->> 'problem_type' as problem_type
  from processing.record_versions rv
  join processing_latest_versions latest
    on latest.source_row_id = rv.source_row_id
   and latest.version_number = rv.version_number
  join audit.step_runs step on step.id = rv.step_run_id
  join ingestion.source_rows sr on sr.id = rv.source_row_id
  join ingestion.source_files sf on sf.id = sr.source_file_id
  join reporting.team_key_aliases alias
    on alias.alias = sf.team
   and not alias.excluded
  where sf.season = '2025-26'
    and sf.file_name like '%injury%'
), processing_counts as (
  select team_key,
    count(*) filter (
      where eligibility_status = 'included_pending_protocol'
        and problem_type = 'injury'
    ) as processing_eligible_injury_count,
    encode(digest(convert_to(coalesce(
      string_agg(record_version_id::text, ',' order by record_version_id) filter (
        where eligibility_status = 'included_pending_protocol'
          and problem_type = 'injury'
      ),
      ''
    ), 'UTF8'), 'sha256'), 'hex') as processing_record_version_set_sha256,
    count(distinct file_sha256) as approved_injury_source_file_count,
    count(*) filter (
      where file_sha256 is distinct from
        evidence.approved_injury_source_sha256_by_team ->> team_key
    ) as unapproved_injury_source_row_count,
    count(*) filter (
      where step_version is distinct from
        'urc_2025_26_problem_type_2026-08-23_v1'
    ) as wrong_problem_type_rule_version_count
  from processing
  cross join analysis.accepted_urc_2025_26_injury_problem_type_successor_v1 evidence
  group by team_key
), eligible as (
  select injury.id as injury_id, injury.record_version_id,
    injury.curated_build_id, injury.team_key, injury.season, injury.problem_type
  from curated.injuries injury
  where injury.season = '2025-26'
    and injury.eligibility_status = 'included_pending_protocol'
), eligible_injury as (
  select *
  from eligible
  where problem_type = 'injury'
), eligible_counts as (
  select curated_build_id, team_key, season,
    count(*) filter (
      where problem_type is null or problem_type = 'unknown'
    ) as unknown_eligible_count,
    count(*) filter (
      where problem_type = 'injury'
    ) as eligible_curated_injury_count,
    encode(digest(convert_to(coalesce(
      string_agg(record_version_id::text, ',' order by record_version_id) filter (
        where problem_type = 'injury'
      ),
      ''
    ), 'UTF8'), 'sha256'), 'hex') as curated_record_version_set_sha256
  from eligible
  group by curated_build_id, team_key, season
), recorded as (
  select cohort.injury_id, injury.record_version_id, cohort.curated_build_id,
    cohort.team_key, cohort.season
  from analysis.analysis_window_injury_cohort_v6 cohort
  join curated.injuries injury
    on injury.id = cohort.injury_id
   and injury.curated_build_id = cohort.curated_build_id
  where cohort.season = '2025-26'
), recorded_counts as (
  select curated_build_id, team_key, season,
    count(*) as recorded_cohort_count,
    encode(digest(convert_to(coalesce(
      string_agg(record_version_id::text, ',' order by record_version_id),
      ''
    ), 'UTF8'), 'sha256'), 'hex') as reporting_record_version_set_sha256
  from recorded
  group by curated_build_id, team_key, season
), recorded_keys as (
  select distinct record_version_id, curated_build_id
  from recorded
), eligible_injury_keys as (
  select distinct record_version_id, curated_build_id
  from eligible_injury
), missing_counts as (
  select expected.curated_build_id, expected.team_key, expected.season,
    count(*) as missing_from_recorded_cohort_count
  from eligible_injury expected
  left join recorded_keys actual
    on actual.record_version_id = expected.record_version_id
   and actual.curated_build_id = expected.curated_build_id
  where actual.record_version_id is null
  group by expected.curated_build_id, expected.team_key, expected.season
), unexpected_counts as (
  select actual.curated_build_id, actual.team_key, actual.season,
    count(*) as unexpected_recorded_cohort_count
  from recorded actual
  left join eligible_injury_keys expected
    on expected.record_version_id = actual.record_version_id
   and expected.curated_build_id = actual.curated_build_id
  where expected.record_version_id is null
  group by actual.curated_build_id, actual.team_key, actual.season
), counts as (
  select active.curated_build_id, active.team_key, active.season,
    coalesce(processing_counts.processing_eligible_injury_count, 0)
      as processing_eligible_injury_count,
    coalesce(eligible_counts.unknown_eligible_count, 0) as unknown_eligible_count,
    coalesce(eligible_counts.eligible_curated_injury_count, 0)
      as eligible_curated_injury_count,
    coalesce(recorded_counts.recorded_cohort_count, 0) as recorded_cohort_count,
    coalesce(
      processing_counts.processing_record_version_set_sha256,
      encode(digest(convert_to('', 'UTF8'), 'sha256'), 'hex')
    ) as processing_record_version_set_sha256,
    coalesce(
      eligible_counts.curated_record_version_set_sha256,
      encode(digest(convert_to('', 'UTF8'), 'sha256'), 'hex')
    ) as curated_record_version_set_sha256,
    coalesce(
      recorded_counts.reporting_record_version_set_sha256,
      encode(digest(convert_to('', 'UTF8'), 'sha256'), 'hex')
    ) as reporting_record_version_set_sha256,
    coalesce(processing_counts.approved_injury_source_file_count, 0)
      as approved_injury_source_file_count,
    coalesce(processing_counts.unapproved_injury_source_row_count, 0)
      as unapproved_injury_source_row_count,
    coalesce(processing_counts.wrong_problem_type_rule_version_count, 0)
      as wrong_problem_type_rule_version_count,
    coalesce(missing_counts.missing_from_recorded_cohort_count, 0)
      as missing_from_recorded_cohort_count,
    coalesce(unexpected_counts.unexpected_recorded_cohort_count, 0)
      as unexpected_recorded_cohort_count,
    coalesce(summary.recorded_injuries, -1) as recorded_headline_count
  from active
  cross join analysis.accepted_urc_2025_26_injury_problem_type_successor_v1
    release_evidence
  left join processing_counts
    on processing_counts.team_key = active.team_key
  left join eligible_counts
    on eligible_counts.curated_build_id = active.curated_build_id
   and eligible_counts.team_key = active.team_key
   and eligible_counts.season = active.season
  left join recorded_counts
    on recorded_counts.curated_build_id = active.curated_build_id
   and recorded_counts.team_key = active.team_key
   and recorded_counts.season = active.season
  left join missing_counts
    on missing_counts.curated_build_id = active.curated_build_id
   and missing_counts.team_key = active.team_key
   and missing_counts.season = active.season
  left join unexpected_counts
    on unexpected_counts.curated_build_id = active.curated_build_id
   and unexpected_counts.team_key = active.team_key
   and unexpected_counts.season = active.season
  left join analysis.analysis_window_team_summary_v6 summary
    on summary.curated_build_id = active.curated_build_id
   and summary.team_key = active.team_key
   and summary.season = active.season
)
select counts.*,
  counts.unknown_eligible_count = 0
    and counts.approved_injury_source_file_count = 1
    and counts.unapproved_injury_source_row_count = 0
    and counts.wrong_problem_type_rule_version_count = 0
    and counts.missing_from_recorded_cohort_count = 0
    and counts.unexpected_recorded_cohort_count = 0
    and counts.processing_record_version_set_sha256 =
      counts.curated_record_version_set_sha256
    and counts.curated_record_version_set_sha256 =
      counts.reporting_record_version_set_sha256
    and counts.processing_eligible_injury_count =
      counts.eligible_curated_injury_count
    and counts.recorded_cohort_count = counts.eligible_curated_injury_count
    and counts.recorded_headline_count = counts.eligible_curated_injury_count
    as release_ready
from counts;

revoke all on analysis.urc_2025_26_injury_cohort_reconciliation_v1
  from public, anon, authenticated, web_reader;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select active.team_key, active.season, null::uuid as team_release_id,
  active.curated_build_id, 'v6'::text as analysis_version,
  active.classification_view_version, active.classification_evidence_sha256,
  active.cohort_view_version, active.cohort_evidence_sha256,
  jsonb_set(
    active.dashboard,
    '{limitations}',
    coalesce(active.dashboard -> 'limitations', '[]'::jsonb)
      || jsonb_build_array(evidence.release_limitation),
    true
  ) as dashboard,
  reconciliation.processing_eligible_injury_count,
  reconciliation.eligible_curated_injury_count,
  reconciliation.recorded_cohort_count,
  reconciliation.processing_record_version_set_sha256,
  reconciliation.curated_record_version_set_sha256,
  reconciliation.reporting_record_version_set_sha256,
  reconciliation.approved_injury_source_file_count,
  reconciliation.unapproved_injury_source_row_count,
  reconciliation.wrong_problem_type_rule_version_count
from analysis.team_dashboard_payload_analysis_window_v6_enriched active
join analysis.urc_2025_26_injury_cohort_reconciliation_v1 reconciliation
  on reconciliation.curated_build_id = active.curated_build_id
 and reconciliation.team_key = active.team_key
 and reconciliation.season = active.season
 and reconciliation.release_ready
cross join analysis.accepted_urc_2025_26_injury_problem_type_successor_v1 evidence;
