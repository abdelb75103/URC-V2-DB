-- Report the partial Year 2 exposure that is actually available. This is a
-- release-bound successor: source values stay source-backed, Benetton and
-- Edinburgh remain explicitly labelled temporary season estimates, and no
-- missing month is converted to zero.

create view analysis.accepted_urc_2025_26_partial_exposure_reporting_evidence_v1
with (security_invoker = true) as
select
  'docs/evidence/urc_2025_26_partial_exposure_reporting_v1.json'::text
    as evidence_locator,
  'e79107210e2344026b7f895c40fc4a5dd1a34c538256a4fc25db89bbf6ca4e30'::text
    as evidence_sha256;

-- This relation is deliberately derived from the active build rather than an
-- agent hand-off table. It is empty unless the active Zebre build retains the
-- registered V14 source and is fully projected from one checksum-bound input
-- representation correction, retains all October and November source rows, and
-- restores 953 valid rows while retaining the 23 clean-rule exclusions inside
-- ordinary per-session distance bounds.
create view analysis.urc_2025_26_zebre_corrected_exposure_gate_v1
with (security_invoker = true) as
select active.curated_build_id,
  min(source_file.file_sha256) as source_file_sha256,
  min(pipeline_run.id::text) as correction_pipeline_run_id,
  min(step.id::text) as correction_step_run_id,
  min(pipeline_run.input_hash) as correction_candidate_sha256,
  count(*) filter (
    where exposure.session_date >= date '2025-10-01'
      and exposure.session_date < date '2025-11-01'
  )::integer as october_row_count,
  count(*) filter (
    where exposure.session_date >= date '2025-11-01'
      and exposure.session_date < date '2025-12-01'
  )::integer as november_row_count,
  sum(exposure.minutes_clean) filter (
    where exposure.session_date >= date '2025-10-01'
      and exposure.session_date < date '2025-11-01'
  ) / 60 as october_hours,
  sum(exposure.minutes_clean) filter (
    where exposure.session_date >= date '2025-11-01'
      and exposure.session_date < date '2025-12-01'
  ) / 60 as november_hours
from analysis.analysis_window_active_builds_v6 active
join curated.exposure exposure
  on exposure.curated_build_id = active.curated_build_id
 and exposure.team_key = active.team_key
 and exposure.season = active.season
join ingestion.source_rows source_row on source_row.id = exposure.source_row_id
join ingestion.source_files source_file on source_file.id = source_row.source_file_id
join processing.record_versions record_version
  on record_version.id = exposure.record_version_id
join audit.step_runs step on step.id = record_version.step_run_id
join audit.pipeline_runs pipeline_run on pipeline_run.id = step.pipeline_run_id
where active.team_key = 'zebre'
  and active.season = '2025-26'
  and (
    select count(*)
    from analysis.analysis_window_active_builds_v6 active_zebre
    where active_zebre.team_key = 'zebre'
      and active_zebre.season = '2025-26'
  ) = 1
  and (
    select count(*)
    from curated.exposure active_exposure
    where active_exposure.curated_build_id = active.curated_build_id
      and active_exposure.team_key = active.team_key
      and active_exposure.season = active.season
  ) = 6694
group by active.curated_build_id
having count(*) = 6694
  and count(distinct source_file.file_sha256) = 1
  and min(source_file.file_sha256) =
    '26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa'
  and count(distinct record_version.version_number) = 1
  and min(record_version.version_number) = 102
  and count(distinct step.id) = 1
  and count(distinct pipeline_run.id) = 1
  and bool_and(
    pipeline_run.command = 'process-exposure'
    and pipeline_run.status = 'succeeded'
    and step.step_name = 'exposure_cleaning'
    and step.step_version = 'input_representation_correction_2026-07-13_v1'
    and pipeline_run.input_hash =
      'b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394'
    and step.input_hash =
      'b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394'
    and pipeline_run.output_hash = step.output_hash
    and step.input_count = 6694
    and pipeline_run.parameters ->> 'registered_source_file_sha256' =
      '26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa'
    and pipeline_run.parameters ->> 'candidate_sha256' =
      'b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394'
    and pipeline_run.parameters ->> 'version_number' = '102'
    and pipeline_run.parameters ->> 'source_row_count' = '6694'
    and pipeline_run.parameters ->> 'patched_rows' = '976'
    and pipeline_run.parameters ->> 'newly_included_rows' = '953'
    and pipeline_run.parameters ->> 'retained_exclusions' = '23'
    and pipeline_run.parameters ->> 'mapping_sha256' =
      'eddb583ddca717e2489d483fd0e8189b0e916ace34c4669bbcdbfb1507cb8dc1'
    and pipeline_run.parameters ->> 'profile_sha256' =
      'ca11e601021966f5b2b1c8b018d8fbd11cd445cfda2f183ba3145b6e19e15e67'
    and pipeline_run.parameters ->> 'adapter_qc_sha256' =
      'a8cde7fa8bf7620b567f129311b5063cc85006849ca6c1a94e3e2333eaf77710'
    and pipeline_run.parameters ->> 'manifest_sha256' =
      '8190b8eaa6d66692dfa27c6da48f6fb3eb20a84ebec7b5522799e13f3156c199'
  )
  and count(*) filter (
    where exposure.session_date >= date '2025-10-01'
      and exposure.session_date < date '2025-11-01'
  ) = 624
  and count(*) filter (
    where exposure.session_date >= date '2025-11-01'
      and exposure.session_date < date '2025-12-01'
  ) = 352
  and count(*) filter (
    where exposure.session_date >= date '2025-10-01'
      and exposure.session_date < date '2025-12-01'
      and exposure.eligibility_status = 'included_pending_protocol'
  ) = 953
  and count(*) filter (
    where exposure.session_date >= date '2025-10-01'
      and exposure.session_date < date '2025-12-01'
      and exposure.eligibility_status is distinct from 'included_pending_protocol'
  ) = 23
  and count(*) filter (
    where exposure.session_date >= date '2025-10-01'
      and exposure.session_date < date '2025-12-01'
      and exposure.eligibility_status = 'included_pending_protocol'
      and (exposure.distance_m_clean <= 0 or exposure.distance_m_clean > 20000)
  ) = 0;

-- The append-only V1 events preserve the prior decision. V2 is the current
-- derived projection: both estimates are recomputed from the corrected 14
-- source-backed active builds and never supply monthly or distance values.
create view analysis.active_exposure_placeholders_v2
with (security_invoker = true) as
with source_backed as (
  select completeness.team_key, completeness.season, completeness.total_hours
  from analysis.analysis_window_team_exposure_completeness_v6 completeness
  where completeness.season = '2025-26'
    and completeness.team_key not in ('benetton', 'edinburgh')
    and completeness.denominator_available
), aggregate as (
  select season, count(*)::integer as source_backed_team_count,
    sum(total_hours) as source_backed_hours
  from source_backed
  group by season
  having count(*) = 14
), pending as (
  select count(*)::integer as pending_team_count
  from analysis.analysis_window_team_exposure_completeness_v6 completeness
  where completeness.season = '2025-26'
    and completeness.team_key in ('benetton', 'edinburgh')
    and completeness.source_backed_hours = 0
    and not completeness.denominator_available
  having count(*) = 2
)
select '2025-26'::text as season, target.team_key,
  'mean_of_other_14_source_backed_team_hours_v2'::text as method,
  aggregate.source_backed_hours / 14 as estimated_total_hours,
  'Temporary league-mean season total. Awaiting source-backed exposure; monthly exposure and distance remain unavailable.'::text
    as limitation,
  'e79107210e2344026b7f895c40fc4a5dd1a34c538256a4fc25db89bbf6ca4e30'::text
    as evidence_sha256
from aggregate
cross join (values ('benetton'::text), ('edinburgh'::text)) target(team_key)
cross join pending
cross join analysis.urc_2025_26_zebre_corrected_exposure_gate_v1 gate;

create or replace view analysis.analysis_window_team_hours_v6
with (security_invoker = true) as
select completeness.curated_build_id, completeness.team_key, completeness.season,
  case when completeness.denominator_available then completeness.total_hours
    else placeholder.estimated_total_hours end as total_hours,
  completeness.match_hours,
  case when completeness.denominator_available then completeness.training_hours
    else placeholder.estimated_total_hours - completeness.match_hours end as training_hours,
  case when completeness.denominator_available then completeness.distance_km
    else null::numeric end as distance_km,
  completeness.exposure_grain
from analysis.analysis_window_team_exposure_completeness_v6 completeness
left join analysis.active_exposure_placeholders_v2 placeholder
  on placeholder.team_key = completeness.team_key
 and placeholder.season = completeness.season;

-- Snapshot the canonical candidates once. The material view uses `now()` for
-- its generated timestamp, so a stable private snapshot is essential: it lets
-- the three team preflights remain byte-identical through release review.
create table analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000 (
  snapshot_version text not null check (snapshot_version = '20260831130000'),
  active_state_sha256 text not null check (active_state_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  team_key text not null references reporting.teams(team_key),
  season text not null check (season = '2025-26'),
  curated_build_id uuid not null references curated.builds(id),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null,
  classification_evidence_sha256 text not null,
  cohort_view_version text not null,
  cohort_evidence_sha256 text not null,
  injury_lineage_version_id uuid not null
    references lineage.injury_master_versions_v3(id),
  injury_lineage_member_sha256 text not null check (
    injury_lineage_member_sha256 ~ '^[0-9a-f]{64}$'
  ),
  dashboard jsonb not null check (jsonb_typeof(dashboard) = 'object'),
  created_at timestamptz not null default now(),
  primary key (snapshot_version, team_key),
  unique (snapshot_version, curated_build_id),
  check (payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard))
);

alter table analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000
  enable row level security;
revoke all on analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000
  from public, anon, authenticated, web_reader;

create function analysis.reject_urc_2025_26_partial_exposure_team_candidate_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'Partial Year 2 exposure team candidate snapshot is immutable';
end;
$$;

revoke execute on function
  analysis.reject_urc_2025_26_partial_exposure_team_candidate_mutation()
  from public, anon, authenticated, web_reader;

create trigger urc_2025_26_partial_exposure_team_candidate_immutable
before update or delete
on analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000
for each row execute function
  analysis.reject_urc_2025_26_partial_exposure_team_candidate_mutation();

with active_builds as materialized (
  select team_key, season, curated_build_id
  from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), build_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key, 'curated_build_id', curated_build_id::text
  ) order by team_key) as builds
  from active_builds
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct curated_build_id) = 16
), placeholder_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key, 'method', method,
    'estimated_total_hours', estimated_total_hours,
    'evidence_sha256', evidence_sha256
  ) order by team_key) as placeholders
  from analysis.active_exposure_placeholders_v2
  where season = '2025-26'
  having count(*) = 2
    and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
), active_state as (
  select reporting.canonical_jsonb_sha256_v1(jsonb_build_object(
    'builds', build_state.builds,
    'placeholders', placeholder_state.placeholders,
    'corrected_zebre', jsonb_build_object(
      'curated_build_id', gate.curated_build_id::text,
      'source_file_sha256', gate.source_file_sha256,
      'pipeline_run_id', gate.correction_pipeline_run_id,
      'step_run_id', gate.correction_step_run_id,
      'candidate_sha256', gate.correction_candidate_sha256,
      'october_rows', gate.october_row_count,
      'november_rows', gate.november_row_count,
      'october_hours', gate.october_hours,
      'november_hours', gate.november_hours
    )
  )) as active_state_sha256
  from build_state
  cross join placeholder_state
  cross join analysis.urc_2025_26_zebre_corrected_exposure_gate_v1 gate
), material as materialized (
  select material.*
  from analysis.urc_2025_26_welsh_fixture_candidate_material_v3 material
  where material.season = '2025-26'
)
insert into analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000 (
  snapshot_version, active_state_sha256, payload_sha256,
  team_key, season, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  injury_lineage_version_id, injury_lineage_member_sha256, dashboard
)
select '20260831130000', active_state.active_state_sha256,
  reporting.canonical_jsonb_sha256_v1(material.dashboard),
  material.team_key, material.season, material.curated_build_id,
  material.analysis_version, material.classification_view_version,
  material.classification_evidence_sha256, material.cohort_view_version,
  material.cohort_evidence_sha256, material.injury_lineage_version_id,
  material.injury_lineage_member_sha256, material.dashboard
from material
cross join active_state;

-- Team preflight reads only the sealed candidate while the corrected active
-- build and recomputed temporary estimates still match the snapshot state.
create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with active_builds as materialized (
  select team_key, season, curated_build_id
  from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), build_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key, 'curated_build_id', curated_build_id::text
  ) order by team_key) as builds
  from active_builds
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct curated_build_id) = 16
), placeholder_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key, 'method', method,
    'estimated_total_hours', estimated_total_hours,
    'evidence_sha256', evidence_sha256
  ) order by team_key) as placeholders
  from analysis.active_exposure_placeholders_v2
  where season = '2025-26'
  having count(*) = 2
    and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
), active_state as (
  select reporting.canonical_jsonb_sha256_v1(jsonb_build_object(
    'builds', build_state.builds,
    'placeholders', placeholder_state.placeholders,
    'corrected_zebre', jsonb_build_object(
      'curated_build_id', gate.curated_build_id::text,
      'source_file_sha256', gate.source_file_sha256,
      'pipeline_run_id', gate.correction_pipeline_run_id,
      'step_run_id', gate.correction_step_run_id,
      'candidate_sha256', gate.correction_candidate_sha256,
      'october_rows', gate.october_row_count,
      'november_rows', gate.november_row_count,
      'october_hours', gate.october_hours,
      'november_hours', gate.november_hours
    )
  )) as active_state_sha256
  from build_state
  cross join placeholder_state
  cross join analysis.urc_2025_26_zebre_corrected_exposure_gate_v1 gate
)
select snapshot.team_key, snapshot.season, null::uuid as team_release_id,
  snapshot.curated_build_id, snapshot.analysis_version,
  snapshot.classification_view_version,
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
  '20260831130000'::text as injury_lineage_snapshot_version,
  snapshot.injury_lineage_member_sha256
from analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000 snapshot
join active_state
  on active_state.active_state_sha256 = snapshot.active_state_sha256
where snapshot.snapshot_version = '20260831130000'
  and snapshot.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

alter table reporting.team_release_injury_lineage_v1
  drop constraint team_release_injury_lineage_v1_candidate_snapshot_version_check,
  add constraint team_release_injury_lineage_v1_candidate_snapshot_version_check check (
    candidate_snapshot_version in (
      '20260830170000', '20260831100000', '20260831101000',
      '20260831121000', '20260831130000'
    )
  );

-- The league has no candidate until all sixteen active releases are present,
-- including the corrected Zebre release and recomputed Benetton/Edinburgh
-- estimates. It reads final release payloads only, never an unreviewed team
-- candidate or an ad-hoc JSON patch.
create or replace view analysis.league_team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with members as materialized (
  select member.team_key, member.season, member.team_release_id,
    member.curated_build_id, payload.analysis_version,
    payload.classification_view_version,
    payload.classification_evidence_sha256,
    payload.cohort_view_version, payload.cohort_evidence_sha256,
    payload.dashboard_payload as dashboard,
    lineage.candidate_snapshot_version
  from analysis.league_member_releases_v6 member
  join reporting.team_release_payloads_v6 payload
    on payload.release_id = member.team_release_id
   and payload.team_key = member.team_key
   and payload.season = member.season
   and payload.curated_build_id = member.curated_build_id
  join reporting.team_release_injury_lineage_v1 lineage
    on lineage.release_id = member.team_release_id
   and lineage.team_key = member.team_key
   and lineage.season = member.season
  where member.season = '2025-26'
), ready as (
  select count(*)::integer as team_count,
    count(distinct team_key)::integer as distinct_team_count,
    count(*) filter (
      where team_key in ('zebre', 'benetton', 'edinburgh')
        and candidate_snapshot_version = '20260831130000'
    )::integer as refreshed_team_count
  from members
)
select members.team_key, members.season, members.team_release_id,
  members.curated_build_id, members.analysis_version,
  members.classification_view_version,
  members.classification_evidence_sha256,
  members.cohort_view_version, members.cohort_evidence_sha256,
  members.dashboard
from members
cross join ready
cross join analysis.urc_2025_26_zebre_corrected_exposure_gate_v1 gate
where ready.team_count = 16
  and ready.distinct_team_count = 16
  and ready.refreshed_team_count = 3
  and exists (
    select 1
    from members zebre
    where zebre.team_key = 'zebre'
      and zebre.curated_build_id = gate.curated_build_id
  );

create or replace view analysis.urc_2025_26_partial_reporting_league_monthly_v3
with (security_invoker = true) as
with members as (
  select team_key, season, dashboard
  from analysis.league_team_dashboard_release_candidates_analysis_window_v6
), rows as (
  select members.season,
    to_date(item ->> 'month', 'Mon YYYY') as month_start,
    (item ->> 'exposure_hours')::numeric as exposure_hours,
    (item ->> 'time_loss_injuries')::bigint as time_loss_injuries
  from members
  cross join lateral jsonb_array_elements(members.dashboard -> 'monthly') item
), domain as (
  select value::date as month_start
  from generate_series(date '2025-09-01', date '2026-06-01', interval '1 month') value
)
select '2025-26'::text as season, domain.month_start,
  case when count(rows.exposure_hours) > 0 then sum(rows.exposure_hours) end
    as exposure_hours,
  coalesce(sum(rows.time_loss_injuries), 0)::bigint as time_loss_injuries
from domain
left join rows using (month_start)
group by domain.month_start;

create or replace view analysis.urc_2025_26_partial_reporting_league_summary_v3
with (security_invoker = true) as
select member.season,
  sum((member.dashboard #>> '{coverage,hours}')::numeric) as exposure_hours
from analysis.league_team_dashboard_release_candidates_analysis_window_v6 member
group by member.season
having count(*) = 16
  and count(member.dashboard #>> '{coverage,hours}') = 16;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with members as materialized (
  select member.team_key, member.season, member.dashboard
  from analysis.league_team_dashboard_release_candidates_analysis_window_v6 member
), coverage as materialized (
  select members.season,
    count(*)::integer as team_count,
    count(*) filter (
      where members.dashboard #>> '{coverage,included_exposure_status}' =
        'source_backed_exposure_submitted_may_be_incomplete'
    )::integer as source_backed_team_count,
    count(*) filter (
      where members.dashboard #>> '{coverage,included_exposure_status}' =
        'temporary_league_mean_estimate_no_source_exposure'
    )::integer as temporary_estimate_team_count,
    count(members.dashboard #>> '{coverage,distance_km}')::integer
      as distance_contributor_count,
    coalesce(jsonb_agg(members.dashboard ->> 'team' order by members.dashboard ->> 'team') filter (
      where members.dashboard #>> '{coverage,included_exposure_status}' =
        'temporary_league_mean_estimate_no_source_exposure'
    ), '[]'::jsonb) as pending_source_teams,
    sum((members.dashboard #>> '{coverage,hours}')::numeric) as exposure_hours,
    sum((members.dashboard #>> '{coverage,match_hours}')::numeric) as match_hours,
    sum((members.dashboard #>> '{coverage,training_hours}')::numeric) as training_hours,
    sum((members.dashboard #>> '{coverage,distance_km}')::numeric) as distance_km,
    sum((members.dashboard #>> '{coverage,exposure_rows}')::bigint) as exposure_rows,
    sum((members.dashboard #>> '{coverage,exposed_players}')::bigint) as exposed_players,
    sum((members.dashboard #>> '{coverage,weeks}')::bigint) as weeks
  from members
  group by members.season
), headline_rows as (
  select members.team_key, item
  from members
  cross join lateral jsonb_array_elements(members.dashboard -> 'headline') item
), summary as materialized (
  select
    sum((item ->> 'value')::numeric) filter (
      where item ->> 'key' = 'recorded_injuries'
    ) as recorded_injuries,
    sum((item ->> 'value')::numeric) filter (
      where item ->> 'key' = 'time_loss_injuries'
    ) as time_loss_injuries,
    sum((item ->> 'numerator')::numeric) filter (
      where item ->> 'key' = 'severity_mean_days'
    ) as days_lost,
    sum((item ->> 'denominator')::numeric) filter (
      where item ->> 'key' = 'severity_mean_days'
    ) as known_duration_time_loss_injuries,
    (select percentile_cont(0.5) within group (order by days_lost)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss and days_lost is not null) as median_severity_days
  from headline_rows
), monthly_rows as (
  select members.team_key, members.season,
    to_date(item ->> 'month', 'Mon YYYY') as month_start,
    (item ->> 'recorded_injuries')::bigint as recorded_injuries,
    (item ->> 'time_loss_injuries')::bigint as time_loss_injuries,
    (item ->> 'days_lost')::numeric as days_lost,
    (item ->> 'exposure_hours')::numeric as exposure_hours,
    (item ->> 'distance_km')::numeric as distance_km
  from members
  cross join lateral jsonb_array_elements(members.dashboard -> 'monthly') item
), monthly_domain as (
  select value::date as month_start
  from generate_series(date '2025-09-01', date '2026-06-01', interval '1 month') value
), monthly as materialized (
  select monthly_domain.month_start,
    coalesce(sum(monthly_rows.recorded_injuries), 0)::bigint as recorded_injuries,
    coalesce(sum(monthly_rows.time_loss_injuries), 0)::bigint as time_loss_injuries,
    coalesce(sum(monthly_rows.days_lost), 0)::numeric as days_lost,
    count(monthly_rows.exposure_hours)::integer as exposure_contributor_count,
    count(monthly_rows.distance_km)::integer as distance_contributor_count,
    case when count(monthly_rows.exposure_hours) > 0
      then sum(monthly_rows.exposure_hours) end as exposure_hours,
    case when count(monthly_rows.distance_km) > 0
      then sum(monthly_rows.distance_km) end as distance_km
  from monthly_domain
  left join monthly_rows using (month_start)
  group by monthly_domain.month_start
), profile_rows as (
  select item ->> 'dimension' as dimension,
    item ->> 'code' as code, item ->> 'label' as label,
    item ->> 'setting' as setting_code,
    (item ->> 'recorded_injuries')::numeric as recorded_injuries,
    (item ->> 'time_loss_injuries')::numeric as time_loss_injuries,
    (item ->> 'days_lost')::numeric as days_lost,
    case when coalesce((item ->> 'days_lost')::numeric, 0) > 0
          and coalesce((item ->> 'mean_severity_days')::numeric, 0) > 0
      then round((item ->> 'days_lost')::numeric /
        (item ->> 'mean_severity_days')::numeric)
      else 0::numeric end as known_duration_time_loss_injuries
  from members
  cross join lateral jsonb_array_elements(members.dashboard -> 'injury_profiles') item
), profiles as materialized (
  select dimension, code, label, setting_code,
    sum(recorded_injuries) as recorded_injuries,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost,
    sum(known_duration_time_loss_injuries) as known_duration_time_loss_injuries
  from profile_rows
  group by dimension, code, label, setting_code
), setting_rows as (
  select item ->> 'setting' as setting_code, item ->> 'label' as label,
    (item ->> 'recorded_injuries')::numeric as recorded_injuries,
    (item ->> 'time_loss_injuries')::numeric as time_loss_injuries,
    (item ->> 'days_lost')::numeric as days_lost,
    case when coalesce((item ->> 'days_lost')::numeric, 0) > 0
          and coalesce((item ->> 'mean_severity_days')::numeric, 0) > 0
      then round((item ->> 'days_lost')::numeric /
        (item ->> 'mean_severity_days')::numeric)
      else 0::numeric end as known_duration_time_loss_injuries
  from members
  cross join lateral jsonb_array_elements(members.dashboard -> 'setting_metrics') item
), settings as materialized (
  select setting_code, min(label) as label,
    sum(recorded_injuries) as recorded_injuries,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost,
    sum(known_duration_time_loss_injuries) as known_duration_time_loss_injuries
  from setting_rows
  group by setting_code
), severity as materialized (
  select item ->> 'key' as key, min(item ->> 'label') as label,
    item ->> 'setting' as setting_code,
    sum((item ->> 'recorded_injuries')::numeric) as recorded_injuries,
    sum((item ->> 'time_loss_injuries')::numeric) as time_loss_injuries,
    sum((item ->> 'days_lost')::numeric) as days_lost
  from members
  cross join lateral jsonb_array_elements(members.dashboard -> 'severity_distribution') item
  group by item ->> 'key', item ->> 'setting'
), contact as materialized (
  select item ->> 'key' as key, min(item ->> 'label') as label,
    item ->> 'setting' as setting_code,
    sum((item ->> 'recorded_injuries')::numeric) as recorded_injuries,
    sum((item ->> 'time_loss_injuries')::numeric) as time_loss_injuries
  from members
  cross join lateral jsonb_array_elements(members.dashboard -> 'contact_distribution') item
  group by item ->> 'key', item ->> 'setting'
), profile_payload as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension', dimension, 'code', code, 'label', label,
    'setting', setting_code, 'recorded_injuries', recorded_injuries,
    'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
    'exposure_hours', case setting_code
      when 'all' then coverage.exposure_hours
      when 'match' then coverage.match_hours
      when 'training' then coverage.training_hours end,
    'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries,
      case setting_code
        when 'all' then coverage.exposure_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end),
    'burden_per_1000h', analysis.rate_per_1000_v1(days_lost,
      case setting_code
        when 'all' then coverage.exposure_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end),
    'mean_severity_days', days_lost /
      nullif(known_duration_time_loss_injuries, 0)
  ) order by dimension, setting_code, code), '[]'::jsonb) as rows
  from profiles
  cross join coverage
)
select coverage.season, 'v6'::text as analysis_version,
  'reporting_classification_2025-26_2026-08-31_v3'::text
    as classification_view_version,
  'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'::text
    as classification_evidence_sha256,
  'injury_lineage_2025-26_2026-08-31_v3'::text as cohort_view_version,
  'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450'::text
    as cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', (select max(members.dashboard ->> 'generated_at') from members),
    'team', 'URC Overall',
    'season', coverage.season,
    'analysis_window', jsonb_build_object(
      'start', '2025-09-01', 'end', '2026-06-30',
      'basis', 'Final active team releases with source-backed reported monthly exposure.'
    ),
    'method', jsonb_build_array(
      'League values pool the final active team releases.',
      'Monthly hours and distance sum only reported source-backed contributors.',
      'Mean severity uses known-duration Time Loss injuries only.'
    ),
    'coverage', jsonb_build_object(
      'hours', coverage.exposure_hours,
      'match_hours', coverage.match_hours,
      'training_hours', coverage.training_hours,
      'distance_km', coverage.distance_km,
      'exposure_rows', coverage.exposure_rows,
      'exposed_players', coverage.exposed_players,
      'weeks', coverage.weeks,
      'included_exposure_status',
        '14_source_backed_teams_plus_2_temporary_league_mean_estimates',
      'analysis_window_start', '2025-09-01',
      'analysis_window_end', '2026-06-30',
      'teams_included', 16,
      'source_backed_team_count', coverage.source_backed_team_count,
      'temporary_estimate_team_count', coverage.temporary_estimate_team_count,
      'distance_contributor_count', coverage.distance_contributor_count,
      'pending_source_teams', coverage.pending_source_teams
    ),
    'headline', jsonb_build_array(
      jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries', 'value', summary.recorded_injuries, 'unit', 'injuries', 'formula', 'count(final classified eligible injury rows, including undated)'),
      jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries', 'value', summary.time_loss_injuries, 'unit', 'injuries', 'formula', 'count(final classification = Time Loss)'),
      jsonb_build_object('key', 'overall_incidence_per_1000h', 'label', 'Overall incidence', 'value', analysis.rate_per_1000_v1(summary.recorded_injuries, coverage.exposure_hours), 'unit', 'per 1,000 player-hours', 'numerator', summary.recorded_injuries, 'denominator', coverage.exposure_hours, 'formula', 'pooled recorded injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence', 'value', analysis.rate_per_1000_v1(summary.time_loss_injuries, coverage.exposure_hours), 'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries, 'denominator', coverage.exposure_hours, 'formula', 'pooled final Time Loss injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity', 'value', summary.days_lost / nullif(summary.known_duration_time_loss_injuries, 0), 'unit', 'days lost per injury', 'numerator', summary.days_lost, 'denominator', summary.known_duration_time_loss_injuries, 'formula', 'known-duration Time Loss days lost / known-duration Time Loss injuries'),
      jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity', 'value', summary.median_severity_days, 'unit', 'days lost per injury', 'denominator', summary.known_duration_time_loss_injuries, 'formula', 'median known-duration Time Loss days lost'),
      jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden', 'value', analysis.rate_per_1000_v1(summary.days_lost, coverage.exposure_hours), 'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost, 'denominator', coverage.exposure_hours, 'formula', 'known-duration Time Loss days lost / pooled exposure hours * 1000')
    ),
    'monthly', coalesce((select jsonb_agg(jsonb_build_object(
      'month', to_char(month_start, 'YYYY-MM'),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost,
      'exposure_hours', exposure_hours,
      'distance_km', distance_km,
      'exposure_contributor_count', exposure_contributor_count,
      'distance_contributor_count', distance_contributor_count,
      'overall_incidence_per_1000h', case
        when exposure_contributor_count = 16 and exposure_hours > 0
          then analysis.rate_per_1000_v1(recorded_injuries, exposure_hours) end,
      'incidence_per_1000h', case
        when exposure_contributor_count = 16 and exposure_hours > 0
          then analysis.rate_per_1000_v1(time_loss_injuries, exposure_hours) end,
      'burden_per_1000h', case
        when exposure_contributor_count = 16 and exposure_hours > 0
          then analysis.rate_per_1000_v1(days_lost, exposure_hours) end
    ) order by month_start) from monthly), '[]'::jsonb),
    'body_locations', coalesce((select jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.exposure_hours,
      'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, coverage.exposure_hours),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, coverage.exposure_hours),
      'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)
    ) order by code) from profiles where dimension = 'body_location'
      and setting_code = 'all'), '[]'::jsonb),
    'injury_types', coalesce((select jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', coverage.exposure_hours,
      'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, coverage.exposure_hours),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, coverage.exposure_hours),
      'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)
    ) order by time_loss_injuries desc, code) from profiles where dimension = 'injury_type'
      and setting_code = 'all'), '[]'::jsonb),
    'injury_profiles', profile_payload.rows,
    'injury_type_families',
      analysis.injury_type_families_from_payload_v3(profile_payload.rows),
    'severity_distribution', coalesce((select jsonb_agg(jsonb_build_object(
      'setting', 'all', 'key', key, 'label', label,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost
    ) order by array_position(array[
      'zero_days_medical_attention_only', 'one_day', 'two_to_three_days',
      'four_to_seven_days', 'eight_to_twenty_eight_days',
      'greater_than_twenty_eight_days', 'unknown_or_censored'
    ], key)) from severity where setting_code = 'all'), '[]'::jsonb),
    'setting_split', coalesce((select jsonb_agg(jsonb_build_object(
      'key', setting_code, 'label', label,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code
        when 'all' then coverage.exposure_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', analysis.rate_per_1000_v1(recorded_injuries,
        case setting_code
          when 'all' then coverage.exposure_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end),
      'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries,
        case setting_code
          when 'all' then coverage.exposure_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost,
        case setting_code
          when 'all' then coverage.exposure_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end),
      'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code))
      from settings), '[]'::jsonb),
    'setting_metrics', coalesce((select jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'label', label,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', case setting_code
        when 'all' then coverage.exposure_hours
        when 'match' then coverage.match_hours
        when 'training' then coverage.training_hours end,
      'overall_incidence_per_1000h', analysis.rate_per_1000_v1(recorded_injuries,
        case setting_code
          when 'all' then coverage.exposure_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end),
      'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries,
        case setting_code
          when 'all' then coverage.exposure_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost,
        case setting_code
          when 'all' then coverage.exposure_hours
          when 'match' then coverage.match_hours
          when 'training' then coverage.training_hours end),
      'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code))
      from settings), '[]'::jsonb),
    'contact_distribution', coalesce((select jsonb_agg(jsonb_build_object(
      'key', key, 'label', label, 'setting', setting_code,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries
    ) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code),
      array_position(array['contact', 'non_contact', 'unknown'], key))
      from contact), '[]'::jsonb),
    'prior_season', jsonb_build_object(
      'season', '2024-25', 'status', 'frozen', 'note', 'Prior season remains frozen.'
    ),
    'limitations', jsonb_build_array(
      'Benetton and Edinburgh season exposure hours are temporary league-mean estimates while source-backed exposure is awaited.',
      'Reported distance and monthly values include only teams with source-backed reported values; contributor counts show coverage.',
      'Monthly rates are unavailable unless all 16 teams report a positive exposure denominator.',
      'No zero is inferred for a month without a reported exposure value.'
    )
  ) as dashboard
from coverage
cross join summary
cross join profile_payload
where coverage.team_count = 16
  and coverage.source_backed_team_count = 14
  and coverage.temporary_estimate_team_count = 2
  and coverage.distance_contributor_count = 14
  and jsonb_array_length(coverage.pending_source_teams) = 2
  and coverage.exposure_hours is not null;

create table analysis.accepted_release_contracts_v5 (
  season text primary key check (season = '2025-26'),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (
    classification_view_version =
      'reporting_classification_2025-26_2026-08-31_v3'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'injury_lineage_2025-26_2026-08-31_v3'
  ),
  team_candidate_relation text not null check (
    team_candidate_relation =
      'analysis.team_dashboard_release_candidates_analysis_window_v6'
  ),
  league_team_candidate_relation text not null check (
    league_team_candidate_relation =
      'analysis.league_team_dashboard_release_candidates_analysis_window_v6'
  ),
  league_candidate_relation text not null check (
    league_candidate_relation =
      'analysis.league_dashboard_release_candidates_analysis_window_v6'
  ),
  league_candidate_aggregation_version text not null check (
    league_candidate_aggregation_version = '20260831130000'
  ),
  required_scientific_relations jsonb not null,
  metric_contract jsonb not null,
  evidence_sha256 text not null check (
    evidence_sha256 =
      'e79107210e2344026b7f895c40fc4a5dd1a34c538256a4fc25db89bbf6ca4e30'
  ),
  evidence_locator text not null check (
    evidence_locator =
      'docs/evidence/urc_2025_26_partial_exposure_reporting_v1.json'
  ),
  created_at timestamptz not null default now(),
  unique (season, analysis_version, classification_view_version,
    cohort_view_version)
);

alter table analysis.accepted_release_contracts_v5 enable row level security;
revoke all on analysis.accepted_release_contracts_v5
  from public, anon, authenticated, web_reader;

create trigger accepted_release_contracts_v5_immutable
before update or delete on analysis.accepted_release_contracts_v5
for each row execute function analysis.reject_accepted_release_contract_mutation();

insert into analysis.accepted_release_contracts_v5 (
  season, analysis_version, classification_view_version, cohort_view_version,
  team_candidate_relation, league_team_candidate_relation,
  league_candidate_relation, league_candidate_aggregation_version,
  required_scientific_relations, metric_contract,
  evidence_sha256, evidence_locator
) values (
  '2025-26', 'v6',
  'reporting_classification_2025-26_2026-08-31_v3',
  'injury_lineage_2025-26_2026-08-31_v3',
  'analysis.team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_dashboard_release_candidates_analysis_window_v6',
  '20260831130000',
  '[
    "analysis.accepted_urc_fixtures_v6",
    "analysis.urc_2025_26_injury_fixture_corrected_rows_v2",
    "analysis.urc_2025_26_injury_fixture_corrected_cohort_v2",
    "analysis.urc_2025_26_partial_reporting_league_monthly_v3",
    "analysis.urc_2025_26_partial_reporting_league_summary_v3",
    "analysis.urc_2025_26_zebre_corrected_exposure_gate_v1"
  ]'::jsonb,
  '{
    "hours":"sum all sixteen final active team releases, including two explicit temporary estimates",
    "distance":"sum final active source-backed distance contributors only",
    "monthly":"fixed September-to-June reported source-backed sums with contributor counts",
    "monthly_rates":"null unless 16 positive monthly exposure contributors"
  }'::jsonb,
  'e79107210e2344026b7f895c40fc4a5dd1a34c538256a4fc25db89bbf6ca4e30',
  'docs/evidence/urc_2025_26_partial_exposure_reporting_v1.json'
);

create or replace function analysis.release_contract_candidates_available_v1(
  requested_season text,
  requested_analysis_version text,
  requested_classification_view_version text,
  requested_cohort_view_version text
)
returns boolean
language sql
stable
set search_path = pg_catalog, analysis
as $$
  select exists (
    select 1
    from analysis.accepted_release_contracts_v5 contract
    where contract.season = requested_season
      and contract.analysis_version = requested_analysis_version
      and contract.classification_view_version =
        requested_classification_view_version
      and contract.cohort_view_version = requested_cohort_view_version
      and to_regclass(contract.team_candidate_relation) is not null
      and to_regclass(contract.league_team_candidate_relation) is not null
      and to_regclass(contract.league_candidate_relation) is not null
      and exists (
        select 1
        from analysis.league_dashboard_release_candidates_analysis_window_v6 candidate
        where candidate.season = requested_season
          and candidate.analysis_version = requested_analysis_version
          and candidate.classification_view_version =
            requested_classification_view_version
          and candidate.cohort_view_version = requested_cohort_view_version
          and reporting.canonical_jsonb_sha256_v1(candidate.dashboard) ~
            '^[0-9a-f]{64}$'
      )
      and not exists (
        select 1
        from jsonb_array_elements_text(contract.required_scientific_relations)
          required(relation_name)
        where to_regclass(required.relation_name) is null
      )
  );
$$;

revoke execute on function analysis.release_contract_candidates_available_v1(
  text, text, text, text
) from public, anon, authenticated, web_reader;

revoke all on
  analysis.accepted_urc_2025_26_partial_exposure_reporting_evidence_v1,
  analysis.urc_2025_26_zebre_corrected_exposure_gate_v1,
  analysis.active_exposure_placeholders_v2,
  analysis.urc_2025_26_partial_reporting_league_monthly_v3,
  analysis.urc_2025_26_partial_reporting_league_summary_v3,
  analysis.team_dashboard_release_candidates_analysis_window_v6,
  analysis.league_team_dashboard_release_candidates_analysis_window_v6,
  analysis.league_dashboard_release_candidates_analysis_window_v6
from public, anon, authenticated, web_reader;

do $$
begin
  if (select count(*) from analysis.urc_2025_26_zebre_corrected_exposure_gate_v1) <> 1
    or (select count(*) from analysis.active_exposure_placeholders_v2) <> 2
    or (select count(*) from analysis.team_dashboard_release_candidates_analysis_window_v6) <> 16
    or exists (
      select 1
      from analysis.team_dashboard_release_candidates_analysis_window_v6 candidate
      where candidate.team_key in ('benetton', 'edinburgh')
        and candidate.dashboard #>> '{coverage,hours}' is null
    )
    or has_table_privilege(
      'web_reader', 'analysis.accepted_release_contracts_v5', 'select'
    )
  then
    raise exception 'Partial Year 2 exposure reporting successor failed its active-build gate';
  end if;
end;
$$;
