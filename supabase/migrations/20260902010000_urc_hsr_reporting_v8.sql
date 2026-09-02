-- HSR reporting successor. The input is an attested, row-level payload from
-- the canonical HSR artefacts. It never changes source, curated, or V7 rows.

create table analysis.hsr_team_season_metadata_v1 (
  season text not null check (season in ('2024-25', '2025-26')),
  team_key text not null references reporting.teams(team_key),
  accepted_exposure_sha256 text not null check (accepted_exposure_sha256 ~ '^[0-9a-f]{64}$'),
  canonical_output_sha256 text not null check (canonical_output_sha256 ~ '^[0-9a-f]{64}$'),
  mapping_sha256 text not null check (mapping_sha256 ~ '^[0-9a-f]{64}$'),
  source_available boolean not null,
  source_mode text not null,
  units text not null,
  threshold_or_zone text not null,
  comparability_status text not null,
  accepted_row_count bigint not null check (accepted_row_count >= 0),
  actual_hsr_row_count bigint not null check (actual_hsr_row_count >= 0),
  blank_hsr_row_count bigint not null check (blank_hsr_row_count >= 0),
  source_gap_reason text,
  created_at timestamptz not null default now(),
  primary key (season, team_key),
  check (accepted_row_count = actual_hsr_row_count + blank_hsr_row_count),
  check ((source_available and source_gap_reason is null)
    or (not source_available and source_gap_reason is not null)),
  check (not source_available or actual_hsr_row_count > 0)
);

create table analysis.hsr_ingestion_batches_v1 (
  parameter_payload_sha256 text primary key check (parameter_payload_sha256 ~ '^[0-9a-f]{64}$'),
  team_season_count integer not null check (team_season_count = 32),
  observation_count bigint not null check (observation_count > 0),
  created_at timestamptz not null default now()
);

create table analysis.hsr_source_observation_events_v1 (
  event_id bigint generated always as identity primary key,
  source_row_id uuid not null references ingestion.source_rows(id),
  curated_exposure_id uuid not null references curated.exposure(id),
  team_key text not null references reporting.teams(team_key),
  season text not null check (season in ('2024-25', '2025-26')),
  source_status text not null check (source_status in ('actual', 'unknown')),
  hsr_distance_m numeric,
  blank_reason text,
  units text not null,
  threshold_or_zone text not null,
  comparability_status text not null,
  hsr_source_file_sha256 text,
  hsr_source_sheet text,
  hsr_source_row_number text,
  hsr_source_row_sha256 text,
  observation_sha256 text not null check (observation_sha256 ~ '^[0-9a-f]{64}$'),
  parameter_payload_sha256 text not null references analysis.hsr_ingestion_batches_v1(parameter_payload_sha256),
  created_at timestamptz not null default now(),
  unique (source_row_id, observation_sha256),
  check ((source_status = 'actual' and hsr_distance_m is not null
      and hsr_distance_m >= 0 and blank_reason is null)
    or (source_status = 'unknown' and hsr_distance_m is null
      and blank_reason is not null))
);

alter table analysis.hsr_team_season_metadata_v1 enable row level security;
alter table analysis.hsr_ingestion_batches_v1 enable row level security;
alter table analysis.hsr_source_observation_events_v1 enable row level security;
revoke all on analysis.hsr_team_season_metadata_v1,
  analysis.hsr_ingestion_batches_v1,
  analysis.hsr_source_observation_events_v1
from public, anon, authenticated, web_reader;

create function analysis.reject_hsr_reporting_mutation_v1()
returns trigger language plpgsql as $$
begin
  raise exception 'HSR reporting records are append-only';
end;
$$;

revoke execute on function analysis.reject_hsr_reporting_mutation_v1()
from public, anon, authenticated, web_reader;

create trigger hsr_team_season_metadata_v1_immutable
before update or delete on analysis.hsr_team_season_metadata_v1
for each row execute function analysis.reject_hsr_reporting_mutation_v1();

create trigger hsr_ingestion_batches_v1_immutable
before update or delete on analysis.hsr_ingestion_batches_v1
for each row execute function analysis.reject_hsr_reporting_mutation_v1();

create trigger hsr_source_observation_events_v1_immutable
before update or delete on analysis.hsr_source_observation_events_v1
for each row execute function analysis.reject_hsr_reporting_mutation_v1();

create view analysis.hsr_active_curated_exposure_rows_v1
with (security_invoker = false) as
select exposure.id as curated_exposure_id, exposure.source_row_id,
  exposure.team_key, exposure.season, exposure.distance_m_clean,
  source.source_values ->> 'source_file_sha256' as accepted_source_file_sha256,
  source.source_values ->> 'source_sheet' as accepted_source_sheet,
  source.source_values ->> 'source_row_number' as accepted_source_row_number,
  source.source_values ->> 'source_row_sha256' as accepted_source_row_sha256
from curated.exposure exposure
join curated.builds build on build.id = exposure.curated_build_id
join ingestion.source_rows source on source.id = exposure.source_row_id
where build.status = 'active'
  and exposure.season in ('2024-25', '2025-26');

create unique index hsr_source_observation_events_v1_active_lookup
  on analysis.hsr_source_observation_events_v1 (source_row_id, event_id desc);

create view analysis.hsr_active_source_observations_v1
with (security_invoker = false) as
select distinct on (event.source_row_id)
  event.source_row_id, event.curated_exposure_id, event.team_key, event.season,
  event.source_status, event.hsr_distance_m, event.blank_reason, event.units,
  event.threshold_or_zone, event.comparability_status,
  event.hsr_source_file_sha256, event.hsr_source_sheet,
  event.hsr_source_row_number, event.hsr_source_row_sha256,
  event.observation_sha256, event.parameter_payload_sha256, event.created_at
from analysis.hsr_source_observation_events_v1 event
order by event.source_row_id, (event.source_status = 'actual') desc, event.event_id desc;

revoke all on analysis.hsr_active_curated_exposure_rows_v1,
  analysis.hsr_active_source_observations_v1
from public, anon, authenticated, web_reader;

create function analysis.hsr_payload_team_seasons_v1(payload jsonb)
returns table (
  season text, team_key text, accepted_exposure_sha256 text,
  canonical_output_sha256 text, mapping_sha256 text, source_available boolean,
  source_mode text, units text, threshold_or_zone text,
  comparability_status text, source_gap_reason text, accepted_row_count bigint,
  actual_hsr_row_count bigint, blank_hsr_row_count bigint
) language sql immutable strict
set search_path = pg_catalog, pg_temp as $$
  select item.season, item.team_key, item.accepted_exposure_sha256,
    item.canonical_output_sha256, item.mapping_sha256, item.source_available,
    item.source_mode, item.units, item.threshold_or_zone,
    item.comparability_status, item.gap_reason, item.accepted_row_count,
    item.canonical_populated_row_count, item.canonical_blank_row_count
  from jsonb_to_recordset(payload) as item(
    kind text, season text, team_key text,
    accepted_exposure_sha256 text, canonical_output_sha256 text,
    mapping_sha256 text, source_available boolean, source_mode text,
    units text, threshold_or_zone text, comparability_status text,
    gap_reason text, accepted_row_count bigint,
    canonical_populated_row_count bigint, canonical_blank_row_count bigint
  ) where item.kind = 'team_season';
$$;

create function analysis.hsr_payload_observations_v1(payload jsonb)
returns table (
  season text, team_key text, accepted_source_file_sha256 text,
  accepted_source_sheet text, accepted_source_row_number text,
  accepted_source_row_sha256 text, accepted_total_distance_m numeric, hsr_distance_m numeric,
  blank_reason text, hsr_source_file_sha256 text, hsr_source_sheet text,
  hsr_source_row_number text, hsr_source_row_sha256 text
) language sql immutable strict
set search_path = pg_catalog, pg_temp as $$
  select item.season, item.team_key,
    item.accepted_locator ->> 'source_file_sha256',
    item.accepted_locator ->> 'source_sheet',
    item.accepted_locator ->> 'source_row_number',
    item.accepted_locator ->> 'source_row_sha256',
    item.accepted_total_distance_m, item.hsr_distance_m, item.blank_reason,
    null::text, null::text, null::text,
    nullif(item.hsr_source_row_sha256, '')
  from jsonb_to_recordset(payload) as item(
    kind text, season text, team_key text, accepted_locator jsonb,
    accepted_total_distance_m numeric, blank_reason text,
    hsr_distance_m numeric, hsr_source_row_sha256 text
  ) where item.kind = 'observation';
$$;

revoke execute on function analysis.hsr_payload_team_seasons_v1(jsonb),
  analysis.hsr_payload_observations_v1(jsonb)
from public, anon, authenticated, web_reader;

create function analysis.apply_hsr_payload_v1(
  payload jsonb,
  parameter_payload_sha256 text
)
returns void language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare
  metadata_count integer;
  observation_count bigint;
begin
  if parameter_payload_sha256 !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(payload) <> 'array'
    or jsonb_array_length(payload) <> 166239
  then
    raise exception 'HSR payload is not a checksum-attested canonical record array';
  end if;

  select count(*) into metadata_count
  from analysis.hsr_payload_team_seasons_v1(payload);
  select count(*) into observation_count
  from analysis.hsr_payload_observations_v1(payload);

  if metadata_count <> 32 or observation_count <> 166207 then
    raise exception 'HSR payload must contain exactly 32 team-seasons and 166207 observations';
  end if;

  if exists (
    with incoming as (select * from analysis.hsr_payload_team_seasons_v1(payload))
    select 1 from incoming
    full join (select season, team_key from reporting.teams
      cross join (values ('2024-25'::text), ('2025-26'::text)) seasons(season)
    ) expected using (season, team_key)
    group by coalesce(incoming.season, expected.season),
      coalesce(incoming.team_key, expected.team_key)
    having count(incoming.team_key) <> 1
  ) then
    raise exception 'HSR payload team-season roster is not the exact 32-team contract';
  end if;

  if (select count(*) from analysis.hsr_payload_team_seasons_v1(payload)
        where season = '2024-25' and source_available) <> 16
    or (select count(*) from analysis.hsr_payload_team_seasons_v1(payload)
        where season = '2025-26' and source_available) <> 14
    or (select count(*) from analysis.hsr_payload_team_seasons_v1(payload)
      where season = '2025-26' and not source_available
        and team_key in ('benetton', 'edinburgh')) <> 2
  then
    raise exception 'HSR source-availability gate requires 16/16 then 14/16 with Benetton and Edinburgh gaps';
  end if;

  if exists (
    select 1 from analysis.hsr_payload_team_seasons_v1(payload)
    where (season = '2024-25' and mapping_sha256
        <> '578dce00e0055be4b5aed07a59d518effd0fc79677bb16cdbe02d7006038c22f')
      or (season = '2025-26' and mapping_sha256
        <> '6d1232124beb4bb61021ecf75321bcc9ba2734107627c968b680752b266cfb0a')
      or accepted_exposure_sha256 !~ '^[0-9a-f]{64}$'
      or canonical_output_sha256 !~ '^[0-9a-f]{64}$'
      or units is null or threshold_or_zone is null
      or comparability_status is null or source_mode is null
  ) then
    raise exception 'HSR payload metadata does not match the accepted mapping contract';
  end if;

  if exists (
    with incoming as (select * from analysis.hsr_payload_team_seasons_v1(payload)), counts as (
      select season, team_key, count(*)::bigint as accepted_row_count,
        count(*) filter (where hsr_distance_m is not null)::bigint as actual_hsr_row_count,
        count(*) filter (where hsr_distance_m is null)::bigint as blank_hsr_row_count
      from analysis.hsr_payload_observations_v1(payload)
      group by season, team_key
    )
    select 1 from incoming left join counts using (season, team_key)
    where incoming.accepted_row_count is distinct from counts.accepted_row_count
      or incoming.actual_hsr_row_count is distinct from counts.actual_hsr_row_count
      or incoming.blank_hsr_row_count is distinct from counts.blank_hsr_row_count
      or incoming.accepted_row_count <> incoming.actual_hsr_row_count + incoming.blank_hsr_row_count
      or (incoming.source_available and incoming.actual_hsr_row_count = 0)
      or (not incoming.source_available and incoming.actual_hsr_row_count <> 0)
  ) then
    raise exception 'HSR payload observation counts do not match the team-season evidence';
  end if;

  if exists (
    with incoming as (select * from analysis.hsr_payload_observations_v1(payload))
    select 1 from incoming
    group by season, team_key, accepted_source_file_sha256,
      accepted_source_sheet, accepted_source_row_number, accepted_source_row_sha256
    having count(*) <> 1
  ) then
    raise exception 'HSR payload contains duplicate accepted-source locators';
  end if;

  if exists (
    with incoming as (select * from analysis.hsr_payload_observations_v1(payload)), resolved as (
      select incoming.*, active.curated_exposure_id,
        source.id as resolved_source_row_id,
        active.distance_m_clean
      from incoming
      left join analysis.hsr_active_curated_exposure_rows_v1 active
        on active.team_key = incoming.team_key and active.season = incoming.season
      left join ingestion.source_rows source on source.id = active.source_row_id
        and source.source_values ->> 'source_file_sha256' = incoming.accepted_source_file_sha256
        and coalesce(source.source_values ->> 'source_sheet', '')
          = coalesce(incoming.accepted_source_sheet, '')
        and source.source_values ->> 'source_row_number' = incoming.accepted_source_row_number
        and source.source_values ->> 'source_row_sha256' = incoming.accepted_source_row_sha256
    )
    select 1 from resolved
    where resolved_source_row_id is null
      or (hsr_distance_m is null and nullif(blank_reason, '') is null)
      or (hsr_distance_m is not null and blank_reason is not null)
      or accepted_total_distance_m is distinct from distance_m_clean
      or (hsr_distance_m is not null and distance_m_clean is not null
        and hsr_distance_m > distance_m_clean)
  ) then
    raise exception 'HSR observations must resolve to one active accepted exposure row with a valid same-row distance';
  end if;

  if exists (
    with incoming as (select * from analysis.hsr_payload_observations_v1(payload))
    select 1
    from incoming
    join analysis.hsr_active_curated_exposure_rows_v1 active
      on active.team_key = incoming.team_key and active.season = incoming.season
    join ingestion.source_rows source on source.id = active.source_row_id
      and source.source_values ->> 'source_file_sha256' = incoming.accepted_source_file_sha256
      and coalesce(source.source_values ->> 'source_sheet', '')
        = coalesce(incoming.accepted_source_sheet, '')
      and source.source_values ->> 'source_row_number' = incoming.accepted_source_row_number
      and source.source_values ->> 'source_row_sha256' = incoming.accepted_source_row_sha256
    group by incoming.season, incoming.team_key, incoming.accepted_source_file_sha256,
      incoming.accepted_source_sheet, incoming.accepted_source_row_number,
      incoming.accepted_source_row_sha256
    having count(*) <> 1
  ) then
    raise exception 'HSR observations must resolve to exactly one active accepted exposure row';
  end if;

  if exists (
    with incoming as (select * from analysis.hsr_payload_team_seasons_v1(payload))
    select 1 from incoming join analysis.hsr_team_season_metadata_v1 stored
      using (season, team_key)
    where stored.accepted_exposure_sha256 is distinct from incoming.accepted_exposure_sha256
      or stored.mapping_sha256 is distinct from incoming.mapping_sha256
      or stored.source_mode is distinct from incoming.source_mode
      or stored.units is distinct from incoming.units
      or stored.threshold_or_zone is distinct from incoming.threshold_or_zone
      or stored.comparability_status is distinct from incoming.comparability_status
  ) then
    raise exception 'HSR payload conflicts with immutable team-season source metadata';
  end if;

  if exists (
    with incoming as (select * from analysis.hsr_payload_observations_v1(payload)), resolved as (
      select incoming.*, active.source_row_id
      from incoming
      join analysis.hsr_active_curated_exposure_rows_v1 active
        on active.team_key = incoming.team_key and active.season = incoming.season
      join ingestion.source_rows source on source.id = active.source_row_id
        and source.source_values ->> 'source_file_sha256' = incoming.accepted_source_file_sha256
        and coalesce(source.source_values ->> 'source_sheet', '')
          = coalesce(incoming.accepted_source_sheet, '')
        and source.source_values ->> 'source_row_number' = incoming.accepted_source_row_number
        and source.source_values ->> 'source_row_sha256' = incoming.accepted_source_row_sha256
    )
    select 1 from resolved join analysis.hsr_source_observation_events_v1 stored
      on stored.source_row_id = resolved.source_row_id
     and stored.source_status = 'actual'
    where resolved.hsr_distance_m is not null
      and stored.hsr_distance_m is distinct from resolved.hsr_distance_m
  ) then
    raise exception 'HSR payload conflicts with an immutable actual HSR observation';
  end if;

  if exists (select 1 from analysis.hsr_ingestion_batches_v1 batch
      where batch.parameter_payload_sha256 = $2) then
    return;
  end if;

  insert into analysis.hsr_ingestion_batches_v1 (
    parameter_payload_sha256, team_season_count, observation_count
  ) values (
    $2, metadata_count, observation_count
  );

  insert into analysis.hsr_team_season_metadata_v1 (
    season, team_key, accepted_exposure_sha256, canonical_output_sha256,
    mapping_sha256, source_available, source_mode, units, threshold_or_zone,
    comparability_status, accepted_row_count, actual_hsr_row_count,
    blank_hsr_row_count, source_gap_reason
  )
  select season, team_key, accepted_exposure_sha256, canonical_output_sha256,
    mapping_sha256, source_available, source_mode, units, threshold_or_zone,
    comparability_status, accepted_row_count, actual_hsr_row_count,
    blank_hsr_row_count, source_gap_reason
  from analysis.hsr_payload_team_seasons_v1(payload)
  on conflict (season, team_key) do nothing;

  with incoming as (select * from analysis.hsr_payload_observations_v1(payload)), resolved as (
    select incoming.*, active.curated_exposure_id, active.source_row_id,
      metadata.units, metadata.threshold_or_zone, metadata.comparability_status
    from incoming
    join analysis.hsr_active_curated_exposure_rows_v1 active
      on active.team_key = incoming.team_key and active.season = incoming.season
    join ingestion.source_rows source on source.id = active.source_row_id
      and source.source_values ->> 'source_file_sha256' = incoming.accepted_source_file_sha256
      and coalesce(source.source_values ->> 'source_sheet', '')
        = coalesce(incoming.accepted_source_sheet, '')
      and source.source_values ->> 'source_row_number' = incoming.accepted_source_row_number
      and source.source_values ->> 'source_row_sha256' = incoming.accepted_source_row_sha256
    join analysis.hsr_team_season_metadata_v1 metadata
      on metadata.team_key = incoming.team_key and metadata.season = incoming.season
  )
  insert into analysis.hsr_source_observation_events_v1 (
    source_row_id, curated_exposure_id, team_key, season, source_status,
    hsr_distance_m, blank_reason, units, threshold_or_zone,
    comparability_status, hsr_source_file_sha256, hsr_source_sheet,
    hsr_source_row_number, hsr_source_row_sha256, observation_sha256,
    parameter_payload_sha256
  )
  select source_row_id, curated_exposure_id, team_key, season,
    case when hsr_distance_m is null then 'unknown' else 'actual' end,
    hsr_distance_m, blank_reason, units, threshold_or_zone,
    comparability_status, hsr_source_file_sha256, hsr_source_sheet,
    hsr_source_row_number, hsr_source_row_sha256,
    encode(extensions.digest(convert_to(jsonb_build_object(
      'source_row_id', source_row_id::text, 'hsr_distance_m', hsr_distance_m,
      'blank_reason', blank_reason, 'hsr_source_file_sha256', hsr_source_file_sha256,
      'hsr_source_sheet', hsr_source_sheet,
      'hsr_source_row_number', hsr_source_row_number,
      'hsr_source_row_sha256', hsr_source_row_sha256
    )::text, 'UTF8'), 'sha256'), 'hex'),
    parameter_payload_sha256
  from resolved
  on conflict (source_row_id, observation_sha256) do nothing;

  if to_regclass('analysis.hsr_dashboard_monthly_actual_v1') is not null then
    refresh materialized view analysis.hsr_dashboard_monthly_actual_v1;
  end if;
end;
$$;

revoke execute on function analysis.apply_hsr_payload_v1(jsonb, text)
from public, anon, authenticated, web_reader;

do $$
declare payload jsonb; attestation text;
begin
  if to_regclass('pg_temp._pipeline_params') is null
    or to_regclass('pg_temp._pipeline_params_attestation') is null
    or (select count(*) from _pipeline_params) <> 166239
    or (select count(*) from _pipeline_params_attestation) <> 1
  then
    raise exception 'HSR migration requires one checksum-attested _pipeline_params payload';
  end if;
  select jsonb_agg(value order by idx) into payload from _pipeline_params;
  select payload_sha256 into attestation from _pipeline_params_attestation;
  if attestation <> '821a3b15eddfdb444a564ffa709410fdc3062b6f3cb49bf4740dabd625735149' then
    raise exception 'HSR migration payload checksum does not match the reviewed canonical artefact';
  end if;
  perform analysis.apply_hsr_payload_v1(payload, attestation);
end;
$$;

create view analysis.hsr_dashboard_exposure_rows_v1
with (security_invoker = false) as
select scope.season, scope.team_key, scope.curated_build_id,
  scope.exposure_id as curated_exposure_id, scope.source_row_id,
  scope.effective_period_start as period_start, scope.distance_m_clean,
  observation.source_status, observation.hsr_distance_m
from analysis.urc_2024_25_effective_exposure_scope_v1 scope
left join analysis.hsr_active_source_observations_v1 observation
  on observation.source_row_id = scope.source_row_id
 and observation.curated_exposure_id = scope.exposure_id
where scope.season = '2024-25'
union all
select exposure.season, exposure.team_key, exposure.curated_build_id,
  exposure.id, exposure.source_row_id,
  coalesce(exposure.session_date, exposure.week_start_date), exposure.distance_m_clean,
  observation.source_status, observation.hsr_distance_m
from analysis.analysis_window_active_builds_v6 active
join curated.exposure exposure on exposure.curated_build_id = active.curated_build_id
 and exposure.team_key = active.team_key and exposure.season = active.season
join analysis.reporting_season_windows_v3 season_window
  on season_window.cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
 and season_window.season = exposure.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort_rule
  on cohort_rule.cohort_view_version = season_window.cohort_view_version
 and cohort_rule.season = season_window.season
left join analysis.hsr_active_source_observations_v1 observation
  on observation.source_row_id = exposure.source_row_id
 and observation.curated_exposure_id = exposure.id
where exposure.season = '2025-26'
  and exposure.eligibility_status = 'included_pending_protocol'
  and coalesce(exposure.session_date, exposure.week_start_date) is not null
  and coalesce(exposure.session_date, exposure.week_start_date) <= season_window.season_end
  and coalesce(exposure.session_date, exposure.week_start_date)
    + case when exposure.grain = 'weekly' then 6 else 0 end >= season_window.season_start;

create materialized view analysis.hsr_dashboard_monthly_actual_v1 as
select season, team_key, date_trunc('month', period_start)::date as month_start,
  count(*)::bigint as exposure_row_count,
  count(*) filter (where source_status = 'actual' and distance_m_clean is not null)::bigint
    as valid_paired_row_count,
  count(*) filter (where source_status is distinct from 'actual' or distance_m_clean is null)::bigint
    as unknown_hsr_row_count,
  sum(distance_m_clean) filter (where distance_m_clean is not null) as total_distance_m,
  sum(hsr_distance_m) filter (where source_status = 'actual' and distance_m_clean is not null)
    as actual_hsr_distance_m,
  sum(distance_m_clean) filter (where source_status = 'actual' and distance_m_clean is not null)
    as paired_total_distance_m
from analysis.hsr_dashboard_exposure_rows_v1
group by season, team_key, date_trunc('month', period_start)::date;

create unique index hsr_dashboard_monthly_actual_v1_key
  on analysis.hsr_dashboard_monthly_actual_v1 (season, team_key, month_start);
revoke all on analysis.hsr_dashboard_exposure_rows_v1,
  analysis.hsr_dashboard_monthly_actual_v1
from public, anon, authenticated, web_reader;

create view analysis.hsr_dashboard_monthly_display_v1
with (security_invoker = false) as
with means as (
  select season, month_start,
    100 * sum(actual_hsr_distance_m) / nullif(sum(paired_total_distance_m), 0)
      as hsr_percentage,
    count(*) filter (where valid_paired_row_count > 0)::integer as hsr_contributor_count
  from analysis.hsr_dashboard_monthly_actual_v1
  where valid_paired_row_count > 0
  group by season, month_start
)
select actual.season, actual.team_key, actual.month_start,
  actual.total_distance_m, actual.exposure_row_count, actual.valid_paired_row_count,
  actual.unknown_hsr_row_count,
  actual.actual_hsr_distance_m / 1000 as actual_hsr_distance_km,
  case when actual.valid_paired_row_count > 0 then actual.actual_hsr_distance_m / 1000
    when actual.total_distance_m is not null and means.hsr_percentage is not null
      then actual.total_distance_m * means.hsr_percentage / 100000
  end as hsr_distance_km,
  case when actual.valid_paired_row_count > 0
      then 100 * actual.actual_hsr_distance_m / nullif(actual.paired_total_distance_m, 0)
    when actual.total_distance_m is not null then means.hsr_percentage
  end as hsr_percentage,
  actual.valid_paired_row_count = 0
    and actual.total_distance_m is not null and means.hsr_percentage is not null as is_imputed,
  case when actual.valid_paired_row_count = 0
      and actual.total_distance_m is not null and means.hsr_percentage is not null
    then 'season_month_pooled_valid_hsr_percentage_v1' end as imputation_method,
  case when actual.valid_paired_row_count = 0
      and actual.total_distance_m is not null and means.hsr_percentage is not null
    then 'League-mean placeholder pending source data.' end as display_note,
  case when actual.valid_paired_row_count > 0 then 1
    else coalesce(means.hsr_contributor_count, 0) end as hsr_contributor_count,
  case when actual.valid_paired_row_count > 0 and actual.unknown_hsr_row_count > 0
      then 'actual_partial_source_blanks'
    when actual.valid_paired_row_count > 0 then 'actual'
    when actual.total_distance_m is null then 'unknown_no_total_distance'
    when means.hsr_percentage is not null and metadata.source_available
      then 'source_blank_unknown_display_placeholder'
    when means.hsr_percentage is not null then 'source_unavailable_display_placeholder'
    when metadata.source_available then 'source_blank_unknown'
    else 'source_unavailable' end as hsr_source_status,
  case when actual.valid_paired_row_count > 0 then actual.paired_total_distance_m
    when actual.total_distance_m is not null and means.hsr_percentage is not null
      then actual.total_distance_m end as display_denominator_m
from analysis.hsr_dashboard_monthly_actual_v1 actual
join analysis.hsr_team_season_metadata_v1 metadata
  on metadata.season = actual.season and metadata.team_key = actual.team_key
left join means using (season, month_start);

create view analysis.hsr_dashboard_team_display_v1
with (security_invoker = false) as
select monthly.season, monthly.team_key,
  sum(monthly.actual_hsr_distance_km) as actual_hsr_distance_km,
  sum(monthly.hsr_distance_km) as hsr_distance_km,
  100 * sum(monthly.hsr_distance_km * 1000)
    / nullif(sum(monthly.display_denominator_m), 0) as hsr_percentage,
  bool_or(monthly.is_imputed) as is_imputed,
  case when bool_or(monthly.is_imputed)
    then 'season_month_pooled_valid_hsr_percentage_v1' end as imputation_method,
  case when bool_or(monthly.is_imputed)
    then 'League-mean placeholder pending source data.' end as display_note,
  case when count(*) filter (where monthly.valid_paired_row_count > 0) > 0
    then 1 else 0 end as hsr_contributor_count,
  case when count(*) filter (where monthly.valid_paired_row_count > 0) > 0
      and bool_or(monthly.is_imputed) then 'actual_with_display_placeholders'
    when count(*) filter (where monthly.valid_paired_row_count > 0) > 0 then 'actual'
    when bool_or(monthly.is_imputed) then 'league_mean_placeholder_pending_source_data'
    when bool_or(monthly.hsr_source_status = 'unknown_no_total_distance')
      then 'unknown_no_total_distance'
    when metadata.source_available then 'source_blank_unknown'
    else 'source_unavailable' end as hsr_source_status,
  metadata.accepted_row_count as source_row_count,
  sum(monthly.valid_paired_row_count)::bigint as valid_paired_row_count,
  count(*) filter (where monthly.valid_paired_row_count > 0)::integer as actual_month_count,
  count(*) filter (where monthly.is_imputed)::integer as placeholder_month_count,
  metadata.units, metadata.threshold_or_zone, metadata.comparability_status,
  case when monthly.season = '2025-26'
      and (monthly.team_key = 'zebre' or bool_or(monthly.is_imputed))
    then jsonb_build_array(
      'The accepted Zebre total-distance anomaly remains uncorrected and affects league-mean placeholders.'
    )
    else '[]'::jsonb end as data_quality_warnings
from analysis.hsr_dashboard_monthly_display_v1 monthly
join analysis.hsr_team_season_metadata_v1 metadata
  on metadata.season = monthly.season and metadata.team_key = monthly.team_key
group by monthly.season, monthly.team_key, metadata.source_available,
  metadata.accepted_row_count, metadata.units, metadata.threshold_or_zone,
  metadata.comparability_status;

create view analysis.hsr_dashboard_league_monthly_display_v1
with (security_invoker = false) as
select season, month_start,
  sum(actual_hsr_distance_km) as actual_hsr_distance_km,
  sum(hsr_distance_km) as hsr_distance_km,
  100 * sum(hsr_distance_km * 1000) / nullif(sum(display_denominator_m), 0)
    as hsr_percentage,
  bool_or(is_imputed) as is_imputed,
  case when bool_or(is_imputed)
    then 'team_month_league_mean_placeholders_v1' end as imputation_method,
  case when bool_or(is_imputed)
    then 'League-mean placeholder pending source data.' end as display_note,
  count(*) filter (where valid_paired_row_count > 0)::integer as hsr_contributor_count,
  case when bool_or(is_imputed) then 'actual_with_team_placeholders'
    when count(*) filter (where valid_paired_row_count > 0) > 0 then 'actual'
    else 'unknown' end as hsr_source_status
from analysis.hsr_dashboard_monthly_display_v1
group by season, month_start;

create view analysis.hsr_dashboard_league_display_v1
with (security_invoker = false) as
with coverage as (
  select season, bool_or(is_imputed) as is_imputed,
    sum(hsr_contributor_count)::integer as hsr_contributor_count,
    sum(source_row_count) as source_row_count,
    sum(valid_paired_row_count) as valid_paired_row_count,
    sum(actual_month_count)::integer as actual_month_count,
    sum(placeholder_month_count)::integer as placeholder_month_count
  from analysis.hsr_dashboard_team_display_v1
  group by season
), aggregate_values as (
  select season, sum(actual_hsr_distance_km) as actual_hsr_distance_km,
    sum(hsr_distance_km) as hsr_distance_km,
    100 * sum(hsr_distance_km * 1000) / nullif(sum(display_denominator_m), 0)
      as hsr_percentage,
    count(*) filter (where valid_paired_row_count > 0) as actual_month_rows
  from analysis.hsr_dashboard_monthly_display_v1
  group by season
)
select aggregate_values.season,
  aggregate_values.actual_hsr_distance_km, aggregate_values.hsr_distance_km,
  aggregate_values.hsr_percentage, coverage.is_imputed,
  case when coverage.is_imputed
    then 'team_month_league_mean_placeholders_v1' end as imputation_method,
  case when coverage.is_imputed
    then 'League-mean placeholder pending source data.' end as display_note,
  coverage.hsr_contributor_count,
  case when coverage.is_imputed then 'actual_with_team_placeholders'
    when aggregate_values.actual_month_rows > 0 then 'actual'
    else 'unknown' end as hsr_source_status,
  coverage.source_row_count, coverage.valid_paired_row_count,
  coverage.actual_month_count, coverage.placeholder_month_count,
  'varies_by_team'::text as units,
  'varies_by_team'::text as threshold_or_zone,
  'not_cross_team_comparable'::text as comparability_status,
  case when aggregate_values.season = '2025-26'
    then jsonb_build_array(
      'The accepted Zebre total-distance anomaly remains uncorrected and affects league-mean placeholders.'
    )
    else '[]'::jsonb end as data_quality_warnings
from aggregate_values join coverage using (season);

revoke all on analysis.hsr_dashboard_monthly_display_v1,
  analysis.hsr_dashboard_team_display_v1,
  analysis.hsr_dashboard_league_monthly_display_v1,
  analysis.hsr_dashboard_league_display_v1
from public, anon, authenticated, web_reader;

create view reporting.latest_team_dashboard_v8
with (security_invoker = false, security_barrier = true) as
select dashboard.team_key, dashboard.team, dashboard.season, dashboard.generated_at,
  dashboard.analysis_window, dashboard.method,
  dashboard.coverage || jsonb_build_object(
    'actual_hsr_distance_km', hsr.actual_hsr_distance_km,
    'hsr_distance_km', hsr.hsr_distance_km,
    'hsr_percentage', hsr.hsr_percentage,
    'is_imputed', hsr.is_imputed,
    'imputation_method', hsr.imputation_method,
    'display_note', hsr.display_note,
    'hsr_contributor_count', hsr.hsr_contributor_count,
    'hsr_source_status', hsr.hsr_source_status,
    'source_row_count', hsr.source_row_count,
    'valid_paired_row_count', hsr.valid_paired_row_count,
    'actual_month_count', hsr.actual_month_count,
    'placeholder_month_count', hsr.placeholder_month_count,
    'comparability_status', hsr.comparability_status,
    'units', hsr.units,
    'threshold_or_zone', hsr.threshold_or_zone,
    'data_quality_warnings', hsr.data_quality_warnings
  ) as coverage,
  dashboard.headline, dashboard.setting_split, dashboard.setting_metrics,
  monthly.monthly, dashboard.body_locations, dashboard.injury_types,
  dashboard.injury_profiles, dashboard.diagnosis_families,
  dashboard.illness_profiles, dashboard.illness_summary,
  dashboard.injury_type_families, dashboard.severity_distribution,
  dashboard.contact_distribution, dashboard.prior_season,
  dashboard.limitations || jsonb_build_array(
    'High-speed running definitions, thresholds, units and vendor calibration differ or are unknown. Do not compare teams directly.'
  ) as limitations,
  dashboard.preliminary_monthly_rates,
  comparison.rows as hsr_team_comparison
from reporting.latest_team_dashboard_v7 dashboard
join analysis.hsr_dashboard_team_display_v1 hsr
  on hsr.season = dashboard.season and hsr.team_key = dashboard.team_key
cross join lateral (
  select coalesce(jsonb_agg(item.value || jsonb_build_object(
    'actual_hsr_distance_km', display.actual_hsr_distance_km,
    'hsr_distance_km', display.hsr_distance_km,
    'hsr_percentage', display.hsr_percentage,
    'is_imputed', coalesce(display.is_imputed, false),
    'imputation_method', display.imputation_method,
    'display_note', display.display_note,
    'hsr_contributor_count', coalesce(display.hsr_contributor_count, 0),
    'hsr_source_status', coalesce(display.hsr_source_status, 'unknown_no_hsr_month')
  ) order by item.ordinality), '[]'::jsonb) as monthly
  from jsonb_array_elements(dashboard.monthly) with ordinality item(value, ordinality)
  left join analysis.hsr_dashboard_monthly_display_v1 display
    on display.season = dashboard.season and display.team_key = dashboard.team_key
   and to_char(display.month_start, 'Mon YYYY') = item.value ->> 'month'
) monthly
cross join lateral (
  select coalesce(jsonb_agg(jsonb_build_object(
    'team_key', row.team_key,
    'actual_hsr_distance_km', row.actual_hsr_distance_km,
    'hsr_distance_km', row.hsr_distance_km,
    'hsr_percentage', row.hsr_percentage,
    'is_imputed', row.is_imputed,
    'imputation_method', row.imputation_method,
    'display_note', row.display_note,
    'hsr_contributor_count', row.hsr_contributor_count,
    'hsr_source_status', row.hsr_source_status,
    'comparability_status', row.comparability_status
  ) order by row.team_key), '[]'::jsonb) as rows
  from analysis.hsr_dashboard_team_display_v1 row
  where row.season = dashboard.season
) comparison;

create view reporting.latest_league_dashboard_v8
with (security_invoker = false, security_barrier = true) as
select dashboard.team, dashboard.season, dashboard.generated_at,
  dashboard.analysis_window, dashboard.method,
  dashboard.coverage || jsonb_build_object(
    'actual_hsr_distance_km', hsr.actual_hsr_distance_km,
    'hsr_distance_km', hsr.hsr_distance_km,
    'hsr_percentage', hsr.hsr_percentage,
    'is_imputed', hsr.is_imputed,
    'imputation_method', hsr.imputation_method,
    'display_note', hsr.display_note,
    'hsr_contributor_count', hsr.hsr_contributor_count,
    'hsr_source_status', hsr.hsr_source_status,
    'source_row_count', hsr.source_row_count,
    'valid_paired_row_count', hsr.valid_paired_row_count,
    'actual_month_count', hsr.actual_month_count,
    'placeholder_month_count', hsr.placeholder_month_count,
    'comparability_status', hsr.comparability_status,
    'units', hsr.units,
    'threshold_or_zone', hsr.threshold_or_zone,
    'data_quality_warnings', hsr.data_quality_warnings
  ) as coverage,
  dashboard.headline, dashboard.setting_split, dashboard.setting_metrics,
  monthly.monthly, dashboard.body_locations, dashboard.injury_types,
  dashboard.injury_profiles, dashboard.diagnosis_families,
  dashboard.illness_profiles, dashboard.illness_summary,
  dashboard.injury_type_families, dashboard.severity_distribution,
  dashboard.contact_distribution, dashboard.prior_season,
  dashboard.limitations || jsonb_build_array(
    'High-speed running definitions, thresholds, units and vendor calibration differ or are unknown. Do not compare teams directly.'
  ) as limitations,
  dashboard.preliminary_monthly_rates,
  comparison.rows as hsr_team_comparison
from reporting.latest_league_dashboard_v7 dashboard
join analysis.hsr_dashboard_league_display_v1 hsr using (season)
cross join lateral (
  select coalesce(jsonb_agg(item.value || jsonb_build_object(
    'actual_hsr_distance_km', display.actual_hsr_distance_km,
    'hsr_distance_km', display.hsr_distance_km,
    'hsr_percentage', display.hsr_percentage,
    'is_imputed', coalesce(display.is_imputed, false),
    'imputation_method', display.imputation_method,
    'display_note', display.display_note,
    'hsr_contributor_count', coalesce(display.hsr_contributor_count, 0),
    'hsr_source_status', coalesce(display.hsr_source_status, 'unknown_no_hsr_month')
  ) order by item.ordinality), '[]'::jsonb) as monthly
  from jsonb_array_elements(dashboard.monthly) with ordinality item(value, ordinality)
  left join analysis.hsr_dashboard_league_monthly_display_v1 display
    on display.season = dashboard.season
   and to_char(display.month_start, 'Mon YYYY') = item.value ->> 'month'
) monthly
cross join lateral (
  select coalesce(jsonb_agg(jsonb_build_object(
    'team_key', row.team_key,
    'actual_hsr_distance_km', row.actual_hsr_distance_km,
    'hsr_distance_km', row.hsr_distance_km,
    'hsr_percentage', row.hsr_percentage,
    'is_imputed', row.is_imputed,
    'imputation_method', row.imputation_method,
    'display_note', row.display_note,
    'hsr_contributor_count', row.hsr_contributor_count,
    'hsr_source_status', row.hsr_source_status,
    'comparability_status', row.comparability_status
  ) order by row.team_key), '[]'::jsonb) as rows
  from analysis.hsr_dashboard_team_display_v1 row
  where row.season = dashboard.season
) comparison;

create view reporting.approved_dashboard_reader_target_v8
with (security_invoker = false, security_barrier = true) as
select target.target_attested
  and to_regclass('reporting.latest_team_dashboard_v8') is not null
  and to_regclass('reporting.latest_league_dashboard_v8') is not null
  and (select count(*) from analysis.hsr_team_season_metadata_v1) = 32
  and not has_table_privilege('web_reader', 'analysis.hsr_team_season_metadata_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_ingestion_batches_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_source_observation_events_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_active_curated_exposure_rows_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_active_source_observations_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_dashboard_exposure_rows_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_dashboard_monthly_actual_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_dashboard_monthly_display_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_dashboard_team_display_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_dashboard_league_monthly_display_v1', 'select')
  and not has_table_privilege('web_reader', 'analysis.hsr_dashboard_league_display_v1', 'select')
  and not has_function_privilege('web_reader', 'analysis.hsr_payload_team_seasons_v1(jsonb)', 'execute')
  and not has_function_privilege('web_reader', 'analysis.hsr_payload_observations_v1(jsonb)', 'execute')
  and not has_function_privilege('web_reader', 'analysis.apply_hsr_payload_v1(jsonb,text)', 'execute')
  and not has_function_privilege('web_reader', 'analysis.reject_hsr_reporting_mutation_v1()', 'execute')
  and has_table_privilege('web_reader', 'reporting.latest_team_dashboard_v8', 'select')
  and has_table_privilege('web_reader', 'reporting.latest_league_dashboard_v8', 'select')
  as target_attested
from reporting.approved_dashboard_reader_target_v7 target;

revoke all on reporting.latest_team_dashboard_v8,
  reporting.latest_league_dashboard_v8,
  reporting.approved_dashboard_reader_target_v8
from public, anon, authenticated;
grant select on reporting.latest_team_dashboard_v8,
  reporting.latest_league_dashboard_v8,
  reporting.approved_dashboard_reader_target_v8
to web_reader;

do $$
begin
  if (select count(*) from analysis.hsr_team_season_metadata_v1) <> 32
    or (select count(*) from analysis.hsr_team_season_metadata_v1
      where season = '2024-25' and source_available) <> 16
    or (select count(*) from analysis.hsr_team_season_metadata_v1
      where season = '2025-26' and source_available) <> 14
    or (select count(*) from reporting.latest_team_dashboard_v8) <> 32
    or (select count(*) from reporting.latest_league_dashboard_v8) <> 2
    or exists (select 1 from reporting.latest_team_dashboard_v8
      where jsonb_array_length(hsr_team_comparison) <> 16)
    or exists (select 1 from reporting.latest_league_dashboard_v8
      where jsonb_array_length(hsr_team_comparison) <> 16)
    or not (select target_attested from reporting.approved_dashboard_reader_target_v8)
  then
    raise exception 'HSR V8 reporting contract is incomplete';
  end if;
end;
$$;
