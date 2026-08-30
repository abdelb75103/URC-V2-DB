-- Year 2 exposure successor. The 14 submitted denominators stay source-backed.
-- Benetton and Edinburgh receive one explicitly labelled season-total estimate;
-- monthly exposure and distance stay null because no source rows support them.

create view analysis.accepted_urc_2025_26_exposure_successor_evidence_v6
with (security_invoker = true) as
select
  'docs/evidence/urc_2025_26_exposure_successor_v6.json'::text as evidence_locator,
  '66ba0a272de96510106a68c74046d4bf59ab04570ed38d83cbb98665f51c3ce1'::text
    as evidence_sha256;

create table analysis.exposure_placeholder_events_v1 (
  event_id bigint generated always as identity primary key,
  season text not null,
  team_key text not null references reporting.teams(team_key),
  event_action text not null check (event_action in ('activate', 'retire')),
  method text not null,
  estimated_total_hours numeric,
  limitation text not null,
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  approved_by text not null,
  created_at timestamptz not null default now(),
  check (
    (event_action = 'activate' and estimated_total_hours > 0)
    or (event_action = 'retire' and estimated_total_hours is null)
  )
);

alter table analysis.exposure_placeholder_events_v1 enable row level security;
revoke all on analysis.exposure_placeholder_events_v1
  from public, anon, authenticated, web_reader;

create function analysis.reject_exposure_placeholder_event_mutation_v1()
returns trigger language plpgsql as $$
begin
  raise exception 'exposure placeholder events are append-only';
end;
$$;

create trigger exposure_placeholder_events_v1_append_only
before update or delete on analysis.exposure_placeholder_events_v1
for each row execute function analysis.reject_exposure_placeholder_event_mutation_v1();

create view analysis.active_exposure_placeholders_v1
with (security_invoker = true) as
select event_id, season, team_key, method, estimated_total_hours, limitation,
  evidence_sha256, approved_by, created_at
from (
  select event.*, row_number() over (
    partition by season, team_key order by event_id desc
  ) as event_rank
  from analysis.exposure_placeholder_events_v1 event
) ranked
where event_rank = 1 and event_action = 'activate';

do $$
declare
  source_team_count integer;
  source_hours numeric;
begin
  if (
    select count(*) from analysis.analysis_window_active_builds_v6
    where season = '2025-26'
  ) <> 16 then
    raise exception 'Year 2 placeholder seed requires exactly 16 active builds';
  end if;

  if exists (
    select 1
    from analysis.analysis_window_team_exposure_completeness_v6 completeness
    where completeness.season = '2025-26'
      and completeness.team_key in ('benetton', 'edinburgh')
      and (completeness.source_backed_hours <> 0 or completeness.denominator_available)
  ) or (
    select count(*)
    from analysis.analysis_window_team_exposure_completeness_v6 completeness
    where completeness.season = '2025-26'
      and completeness.team_key in ('benetton', 'edinburgh')
  ) <> 2 then
    raise exception 'Benetton and Edinburgh must have zero source-backed Year 2 hours';
  end if;

  if exists (
    with expected(team_key, file_sha256) as (values
      ('bulls', 'eb10d32f46e0eb85bf5f246b7a30f7778860a447cc5f633cdfc3f6c4c66c2ca3'),
      ('cardiff', '0462c28deb1bdde6dad780b9e7410e74c6bf7b1bbbc1b9b56ed301353e775438'),
      ('connacht', 'db65fead17ddd81882fc7a7076b3a1a7f05eabe9a6224324f5e20b3e62b8c4e6'),
      ('dragons', 'd179be4b86753792e726b649c75a93bb8fa0b59da528d1e8f6272e7efd74b3f0'),
      ('glasgow', 'cc914cf335d506325148e263b6ead6eb968af9f06933f93e787030ce40e0fddb'),
      ('leinster', 'd003759fb23c70f94ee6cda8dd6ec3bdd22a7ece45b6efc57689f6043e922639'),
      ('lions', 'b9b756d0dbd2dd285baa8b3e7f600fdc3d141e302500a28257dc39dbf6d0cbb1'),
      ('munster', 'aacb57fd82c46b41f9479068bd4ada6966ca218052254fae28b4a411db663bf4'),
      ('ospreys', 'e99c4b44b2faba4d1e3bb76802f30c6817e9a89116a7edf6e97e31a02ca79c28'),
      ('scarlets', 'db6123174ebcbd65845a9f294aa44b23a39990d7aace0c6b3c6d843ba0b6b775'),
      ('sharks', '9e5f3653d66c359f1b72586224edab6942edb771a6aaa7b4f82295d31bd1b722'),
      ('stormers', 'cce607106b672eb7be05cf955638f603b03cd543546776c4d3fec39691049b1e'),
      ('ulster', '9ad6331f328f75af9a408ea5f8bdef6f093678f5d808592f0a47329a22e357d8'),
      ('zebre', '26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa')
    )
    select 1
    from expected
    left join analysis.analysis_window_active_builds_v6 build
      on build.team_key = expected.team_key and build.season = '2025-26'
    left join curated.exposure exposure on exposure.curated_build_id = build.curated_build_id
    left join ingestion.source_rows source_row on source_row.id = exposure.source_row_id
    left join ingestion.source_files source_file on source_file.id = source_row.source_file_id
    group by expected.team_key, expected.file_sha256
    having count(distinct build.curated_build_id) <> 1
      or count(distinct source_file.file_sha256) <> 1
      or min(source_file.file_sha256) <> expected.file_sha256
  ) then
    raise exception 'active Year 2 builds do not bind every reviewed source-backed exposure file';
  end if;

  select count(*), sum(completeness.total_hours)
  into source_team_count, source_hours
  from analysis.analysis_window_team_exposure_completeness_v6 completeness
  where completeness.season = '2025-26'
    and completeness.team_key not in ('benetton', 'edinburgh')
    and completeness.denominator_available;

  if source_team_count <> 14 or round(source_hours, 6) <> 76872.261672 then
    raise exception 'Year 2 source-backed exposure does not match the reviewed 14-team candidate';
  end if;

  insert into analysis.exposure_placeholder_events_v1 (
    season, team_key, event_action, method, estimated_total_hours,
    limitation, evidence_sha256, approved_by
  )
  select '2025-26', team_key, 'activate',
    'mean_of_other_14_source_backed_team_hours_v1', source_hours / 14,
    'Temporary league-mean season total. Monthly exposure and distance are unavailable; a valid source-backed denominator takes precedence.',
    '66ba0a272de96510106a68c74046d4bf59ab04570ed38d83cbb98665f51c3ce1',
    'Abdel Babiker'
  from (values ('benetton'::text), ('edinburgh'::text)) target(team_key);
end;
$$;

-- Preserve the established V6 shape. Source-backed data wins automatically,
-- which makes a later valid submission the retirement mechanism in readers.
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
left join analysis.active_exposure_placeholders_v1 placeholder
  on placeholder.team_key = completeness.team_key
 and placeholder.season = completeness.season;

create or replace view analysis.analysis_window_league_summary_v6
with (security_invoker = true) as
with aggregated as (
  select summary.season,
    sum(summary.recorded_injuries) as recorded_injuries,
    sum(summary.time_loss_injuries) as time_loss_injuries,
    sum(summary.days_lost) as days_lost,
    sum(summary.days_lost) / nullif(sum(summary.time_loss_injuries), 0) as mean_severity_days,
    (select percentile_cont(0.5) within group (order by cohort.days_lost)
     from analysis.analysis_window_injury_cohort_v6 cohort
     where cohort.season = summary.season and cohort.is_time_loss) as median_severity_days,
    count(*) filter (where hours.total_hours is not null) as available_team_count,
    sum(hours.total_hours) as exposure_hours,
    sum(hours.match_hours) as match_exposure_hours,
    sum(hours.training_hours) as training_exposure_hours
  from analysis.analysis_window_team_summary_v6 summary
  join analysis.analysis_window_team_hours_v6 hours
    using (curated_build_id, team_key, season)
  group by summary.season
)
select season, recorded_injuries, time_loss_injuries, days_lost,
  mean_severity_days, median_severity_days,
  case when available_team_count = 16 then exposure_hours else null::numeric end as exposure_hours,
  match_exposure_hours,
  case when available_team_count = 16 then training_exposure_hours else null::numeric end
    as training_exposure_hours
from aggregated;

-- Patch only the two estimated team payloads. All other candidate bytes keep
-- the ordinary source-backed status produced by the existing enriched view.
create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with expected_exposure(team_key, file_sha256) as (values
  ('bulls', 'eb10d32f46e0eb85bf5f246b7a30f7778860a447cc5f633cdfc3f6c4c66c2ca3'),
  ('cardiff', '0462c28deb1bdde6dad780b9e7410e74c6bf7b1bbbc1b9b56ed301353e775438'),
  ('connacht', 'db65fead17ddd81882fc7a7076b3a1a7f05eabe9a6224324f5e20b3e62b8c4e6'),
  ('dragons', 'd179be4b86753792e726b649c75a93bb8fa0b59da528d1e8f6272e7efd74b3f0'),
  ('glasgow', 'cc914cf335d506325148e263b6ead6eb968af9f06933f93e787030ce40e0fddb'),
  ('leinster', 'd003759fb23c70f94ee6cda8dd6ec3bdd22a7ece45b6efc57689f6043e922639'),
  ('lions', 'b9b756d0dbd2dd285baa8b3e7f600fdc3d141e302500a28257dc39dbf6d0cbb1'),
  ('munster', 'aacb57fd82c46b41f9479068bd4ada6966ca218052254fae28b4a411db663bf4'),
  ('ospreys', 'e99c4b44b2faba4d1e3bb76802f30c6817e9a89116a7edf6e97e31a02ca79c28'),
  ('scarlets', 'db6123174ebcbd65845a9f294aa44b23a39990d7aace0c6b3c6d843ba0b6b775'),
  ('sharks', '9e5f3653d66c359f1b72586224edab6942edb771a6aaa7b4f82295d31bd1b722'),
  ('stormers', 'cce607106b672eb7be05cf955638f603b03cd543546776c4d3fec39691049b1e'),
  ('ulster', '9ad6331f328f75af9a408ea5f8bdef6f093678f5d808592f0a47329a22e357d8'),
  ('zebre', '26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa')
)
select active.team_key, active.season, null::uuid as team_release_id,
  active.curated_build_id, 'v6'::text as analysis_version,
  active.classification_view_version, active.classification_evidence_sha256,
  active.cohort_view_version, active.cohort_evidence_sha256,
  case when placeholder.event_id is null or completeness.denominator_available
    then active.dashboard else
    jsonb_set(
      jsonb_set(
        active.dashboard,
        '{coverage,included_exposure_status}',
        to_jsonb('temporary_league_mean_estimate_no_source_exposure'::text)
      ),
      '{limitations}',
      jsonb_build_array(
        'Season exposure hours are a temporary mean of the other 14 source-backed team totals, not submitted exposure.',
        'Training hours equal the estimated season total less fixture-derived match hours.',
        'Monthly exposure and distance remain unavailable because no session-level source rows support them.'
      )
    )
  end as dashboard
from analysis.team_dashboard_payload_analysis_window_v6_enriched active
left join analysis.active_exposure_placeholders_v1 placeholder
  on placeholder.team_key = active.team_key and placeholder.season = active.season
left join analysis.analysis_window_team_exposure_completeness_v6 completeness
  using (curated_build_id, team_key, season)
left join expected_exposure expected on expected.team_key = active.team_key
where expected.team_key is null or exists (
  select 1
  from curated.exposure exposure
  join ingestion.source_rows source_row on source_row.id = exposure.source_row_id
  join ingestion.source_files source_file on source_file.id = source_row.source_file_id
  where exposure.curated_build_id = active.curated_build_id
  group by exposure.curated_build_id
  having count(distinct source_file.file_sha256) = 1
    and min(source_file.file_sha256) = expected.file_sha256
);

revoke all on analysis.active_exposure_placeholders_v1,
  analysis.accepted_urc_2025_26_exposure_successor_evidence_v6
  from public, anon, authenticated, web_reader;

do $$
begin
  if (select count(*) from analysis.active_exposure_placeholders_v1
      where season = '2025-26') <> 2
    or exists (
      select 1 from analysis.active_exposure_placeholders_v1
      where season = '2025-26'
        and team_key not in ('benetton', 'edinburgh')
    )
    or (select count(*) from analysis.team_dashboard_release_candidates_analysis_window_v6
        where season = '2025-26') <> 16
  then
    raise exception 'Year 2 exposure successor placeholder boundary is incomplete';
  end if;
end;
$$;
