-- Performance-only successor for the checksum-bound Year 2 injury release
-- guard. The enriched dashboard adds profile, severity, setting, contact and
-- family sections plus the release limitation, but never replaces headline.
-- Read the recorded-injury value from the exact team-summary relation that
-- supplies the candidate headline. The CLI still compares it with the actual
-- candidate JSON headline before either preflight or promotion.

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
), eligible as (
  select injury.id as injury_id, injury.record_version_id,
    injury.curated_build_id, injury.team_key, injury.season, injury.problem_type
  from curated.injuries injury
  join active
    on active.curated_build_id = injury.curated_build_id
   and active.team_key = injury.team_key
   and active.season = injury.season
  where injury.eligibility_status = 'included_pending_protocol'
), eligible_injury as (
  select *
  from eligible
  where problem_type = 'injury'
), recorded as (
  select cohort.injury_id, injury.record_version_id, cohort.curated_build_id,
    cohort.team_key, cohort.season
  from analysis.analysis_window_injury_cohort_v6 cohort
  join curated.injuries injury
    on injury.id = cohort.injury_id
   and injury.curated_build_id = cohort.curated_build_id
  join active
    on active.curated_build_id = cohort.curated_build_id
   and active.team_key = cohort.team_key
   and active.season = cohort.season
), processing as (
  select rv.id as record_version_id, alias.team_key, sf.file_sha256,
    step.step_version, rv.eligibility_status,
    rv.record_state ->> 'problem_type' as problem_type
  from processing.record_versions rv
  join audit.step_runs step on step.id = rv.step_run_id
  join ingestion.source_rows sr on sr.id = rv.source_row_id
  join ingestion.source_files sf on sf.id = sr.source_file_id
  join reporting.team_key_aliases alias
    on alias.alias = sf.team
   and not alias.excluded
  where sf.season = '2025-26'
    and sf.file_name like '%injury%'
    and rv.version_number = (
      select max(latest.version_number)
      from processing.record_versions latest
      where latest.source_row_id = rv.source_row_id
    )
), processing_eligible_injury as (
  select *
  from processing
  where eligibility_status = 'included_pending_protocol'
    and problem_type = 'injury'
), counts as (
  select active.curated_build_id, active.team_key, active.season,
    (select count(*) from processing_eligible_injury row_set
      where row_set.team_key = active.team_key)
      as processing_eligible_injury_count,
    (select count(*) from eligible row_set
      where row_set.curated_build_id = active.curated_build_id
        and (row_set.problem_type is null or row_set.problem_type = 'unknown'))
      as unknown_eligible_count,
    (select count(*) from eligible_injury row_set
      where row_set.curated_build_id = active.curated_build_id)
      as eligible_curated_injury_count,
    (select count(*) from recorded row_set
      where row_set.curated_build_id = active.curated_build_id)
      as recorded_cohort_count,
    encode(digest(convert_to(coalesce((
      select string_agg(row_set.record_version_id::text, ',' order by row_set.record_version_id)
      from processing_eligible_injury row_set
      where row_set.team_key = active.team_key
    ), ''), 'UTF8'), 'sha256'), 'hex') as processing_record_version_set_sha256,
    encode(digest(convert_to(coalesce((
      select string_agg(row_set.record_version_id::text, ',' order by row_set.record_version_id)
      from eligible_injury row_set
      where row_set.curated_build_id = active.curated_build_id
    ), ''), 'UTF8'), 'sha256'), 'hex') as curated_record_version_set_sha256,
    encode(digest(convert_to(coalesce((
      select string_agg(row_set.record_version_id::text, ',' order by row_set.record_version_id)
      from recorded row_set
      where row_set.curated_build_id = active.curated_build_id
    ), ''), 'UTF8'), 'sha256'), 'hex') as reporting_record_version_set_sha256,
    (select count(distinct row_set.file_sha256)
      from processing row_set
      where row_set.team_key = active.team_key)
      as approved_injury_source_file_count,
    (select count(*)
      from processing row_set
      where row_set.team_key = active.team_key
        and row_set.file_sha256 is distinct from
          evidence.approved_injury_source_sha256_by_team ->> active.team_key)
      as unapproved_injury_source_row_count,
    (select count(*)
      from processing row_set
      where row_set.team_key = active.team_key
        and row_set.step_version is distinct from
          'urc_2025_26_problem_type_2026-08-23_v1')
      as wrong_problem_type_rule_version_count,
    (select count(*) from eligible_injury expected
      where expected.curated_build_id = active.curated_build_id
        and not exists (
          select 1 from recorded actual
          where actual.record_version_id = expected.record_version_id
            and actual.curated_build_id = expected.curated_build_id
        )) as missing_from_recorded_cohort_count,
    (select count(*) from recorded actual
      where actual.curated_build_id = active.curated_build_id
        and not exists (
          select 1 from eligible_injury expected
          where expected.record_version_id = actual.record_version_id
            and expected.curated_build_id = actual.curated_build_id
        )) as unexpected_recorded_cohort_count,
    coalesce((
      select summary.recorded_injuries
      from analysis.analysis_window_team_summary_v6 summary
      where summary.curated_build_id = active.curated_build_id
        and summary.team_key = active.team_key
        and summary.season = active.season
    ), -1) as recorded_headline_count
  from active
  cross join analysis.accepted_urc_2025_26_injury_problem_type_successor_v1 evidence
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

-- Carry the one accepted reconciliation row with the candidate. This avoids
-- expanding the same reconciliation view again in preflight and promotion.
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
