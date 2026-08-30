-- Year 2 problem-type release guard. The processing pipeline owns clinical
-- classification. This migration rejects a residual eligible Unknown at the
-- active-build boundary and proves that the reporting cohort is the exact set
-- of eligible curated injury rows. It does not infer episode identity.

insert into audit.reason_codes (code, description) values
  (
    'year2_problem_type_successor',
    'The approved Year 2 rule applies clear illness precedence, then direct injury evidence, then the signed injury-input fallback for eligible rows.'
  ),
  (
    'year2_episode_grain_unresolved',
    'Candidate duplicate and repeated status rows remain included because available evidence does not prove episode identity. No silent episode deduplication was applied.'
  )
on conflict (code) do update set description = excluded.description;

create view analysis.accepted_urc_2025_26_injury_problem_type_successor_v1
with (security_invoker = true) as
select
  'urc_2025_26_injury_problem_type_successor_v1'::text as rule_version,
  '3e857b9ed8192722d22f51ebe32469d230951072705924425e14b6923de1f3fb'::text
    as evidence_sha256,
  '01dd17a82ab1835fd84f2c84048b9e15b4072a4f9bca3b3d3a348817a68d7241'::text
    as protected_v12_root_manifest_sha256,
  '5ea322d4e246510ce82075f5690ea2ac5715dace31ead35bff9db3bacc6a7abd'::text
    as protected_v12_file_set_sha256,
  'clear_illness_evidence_wins'::text as conflict_rule,
  '{
    "benetton":"58602000b171e29d0db271eec95b4357508a484602a1e80d95b20d1d1cde4d9b",
    "bulls":"f2a069c5f235d5b82b135de03c38fb96cba645b34b7622853a19d1fef5f53717",
    "cardiff":"011e8c7c6cf84ab34e7425eb4e8d018b88717e9251410d5cffb9c2a438b5e0a7",
    "connacht":"6da2bbcfce008ecc7ccff30bfcc7d1b23fc262865f976d784ced4236bebd4d0d",
    "dragons":"2c9ee7fe0860f3d7a7063b860f7c5d60e5c088d8504e8d9d58d8c9bb7f410b22",
    "edinburgh":"214e0eec95972245363f9fd61e3f3cb04b335e1c6243091e2c3b7562ae91ad17",
    "glasgow":"e1a63d8f7a896c09e7d555f1b9cf9faa704b011af0f50eb49223baf050177f1f",
    "leinster":"11e0aaba4abc77259d76008909cdd0b42bf2c121a75fd8ba622d5f8b0fc8fa52",
    "lions":"21a9288bed1767cd9f25044b166111d8759c5daf845fcc7a3a1e435f85c2acff",
    "munster":"b7206d5c75ff7a9cd2f15ae82bfe788d47a88ef4602d8ce21cb5255003d71c79",
    "ospreys":"870216b1d3570f869d684694c3256116bb31c5ad20ad50b1aa8035415ec529a4",
    "scarlets":"eb21acd209a662782f7c9e1f3b92e77cf8b2fe418758c6e23ff44b59f81fa14b",
    "sharks":"5cc526aa901cd3eb167caeaf8c424070e50ff243f6c0c30b7d5e3c4ea8ec9cf8",
    "stormers":"4f598ec18e230dae104b2b08e6fb19826629e77673169ac791665a0547bfd1dd",
    "ulster":"cbb18d92e8253414ed3abfcf02161e11b80259b258fbb8572827ae40b97c6dc9",
    "zebre":"318bd3303fe5c91e9480ab204f938fa17de77dc7fe4757e3a353e398cfaed95a"
  }'::jsonb as approved_injury_source_sha256_by_team,
  'Eligible signed injury-source rows are retained as recorded injuries. Candidate duplicate and repeated status rows remain included because the available source evidence does not yet prove episode identity. No silent episode deduplication was applied.'::text
    as release_limitation
where (
  select count(*)
  from audit.reason_codes
  where code in (
    'year2_problem_type_successor',
    'year2_episode_grain_unresolved'
  )
) = 2;

revoke all on analysis.accepted_urc_2025_26_injury_problem_type_successor_v1
  from public, anon, authenticated, web_reader;

create function analysis.reject_active_year2_eligible_unknown_injury_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_table_schema = 'curated' and tg_table_name = 'injuries' then
    if exists (
      select 1
      from curated.injuries injury
      join curated.builds build on build.id = injury.curated_build_id
      where injury.id = new.id
        and injury.season = '2025-26'
        and injury.eligibility_status = 'included_pending_protocol'
        and (injury.problem_type is null or injury.problem_type = 'unknown')
        and build.status = 'active'
    )
    then
      raise exception 'Eligible 2025-26 injury-source row cannot remain problem_type=unknown in an active build';
    end if;
  elsif tg_table_schema = 'curated' and tg_table_name = 'builds' then
    if exists (
      select 1
      from curated.builds build
      join curated.injuries injury on injury.curated_build_id = build.id
      where build.id = new.id
        and build.season = '2025-26'
        and build.status = 'active'
        and injury.eligibility_status = 'included_pending_protocol'
        and (injury.problem_type is null or injury.problem_type = 'unknown')
    )
    then
      raise exception 'Eligible 2025-26 injury-source row cannot remain problem_type=unknown in an active build';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function
  analysis.reject_active_year2_eligible_unknown_injury_v1()
  from public, anon, authenticated, web_reader;

create constraint trigger curated_injuries_year2_problem_type_guard_v1
after insert or update
on curated.injuries
deferrable initially deferred
for each row execute function
  analysis.reject_active_year2_eligible_unknown_injury_v1();

create constraint trigger curated_builds_year2_problem_type_guard_v1
after insert or update
on curated.builds
deferrable initially deferred
for each row execute function
  analysis.reject_active_year2_eligible_unknown_injury_v1();

create view analysis.urc_2025_26_injury_cohort_reconciliation_v1
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
      select (headline ->> 'value')::bigint
      from analysis.team_dashboard_payload_analysis_window_v6_enriched payload
      cross join lateral jsonb_array_elements(payload.dashboard -> 'headline') headline
      where payload.curated_build_id = active.curated_build_id
        and payload.team_key = active.team_key
        and payload.season = active.season
        and headline ->> 'key' = 'recorded_injuries'
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
  ) as dashboard
from analysis.team_dashboard_payload_analysis_window_v6_enriched active
join analysis.urc_2025_26_injury_cohort_reconciliation_v1 reconciliation
  on reconciliation.curated_build_id = active.curated_build_id
 and reconciliation.team_key = active.team_key
 and reconciliation.season = active.season
 and reconciliation.release_ready
cross join analysis.accepted_urc_2025_26_injury_problem_type_successor_v1 evidence;
