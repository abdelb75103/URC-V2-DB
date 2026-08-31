-- Seal the corrected Year 2 league candidate from the exact sixteen approved
-- team successors. This migration creates no public release. Member drift
-- makes the candidate view return no row.

do $$
begin
  if current_setting('transaction_isolation') <> 'repeatable read' then
    raise exception 'Corrected V6 league snapshot requires repeatable-read isolation';
  end if;
end;
$$;

create temporary table _urc_v6_corrected_members on commit drop as
with expected(
  team_key, release_id, curated_build_id, payload_sha256, member_sha256
) as (values
  ('benetton', '578d6c8d-9dce-4a42-a607-36e41f5acda7'::uuid, '526f90e4-60b5-4c00-8252-725ae4409018'::uuid, '16eb1c06fed9f4251af27d79e6ecaaa5f51d8191144a19a838ba84afe33e2f3e', 'ccbcae121047b35006f3bb9c3834d311b134157ded2b51d73d1a17b33e8e87dc'),
  ('bulls', '4ace6ac5-5c89-4025-90d5-86be53f18d61'::uuid, '8e9e90dd-b6e6-46ee-a3a1-6f15631c9601'::uuid, 'f0b5d1aa983b0343b72ee44d4fa107e64f3a1006d0d311359958e25f46dc3e5f', 'dda9cbe341cb0ae42a8f90593ff5ce86ff57108f1de5eef2b7ef521e61826802'),
  ('cardiff', '937a8cbc-0508-4bef-9055-cab3f508e909'::uuid, '554ea736-41f8-4c78-b5e8-0914efce9e08'::uuid, '8b4aa4132ad080592f13b68b38abda4552fd9de0b85d6f30fe207e8a20fe8f92', 'a0e935932f5743cd948cb28a5641fd56f30e02534de4782ba1270f6c3fb6fba6'),
  ('connacht', '5a139497-50a5-462c-b2f9-e4ddc1bc5c29'::uuid, '3fd8be15-4959-4d0c-9982-b8a65c73b2fa'::uuid, '724d031b17513c459b34b0db1065cf3758c7a3ba1005fc4a8fe334757b699f05', 'bd5043f7ac877aae7232cab13b7a74a1eca0fe984fd27a0dedee86d58013262e'),
  ('dragons', 'f9bce99a-d244-41ff-8758-22371c4bbde8'::uuid, '5e0eabe1-fa58-463a-ab29-f4dd213d025d'::uuid, '13c2fdeaa66bef3f863bae08eb3b45429a0ce4630ac958582b0eaceb8e819ed2', '1dd7ad39661b851da370004c1a41df97238316f0a1cef7d99dcf16e3d27f2744'),
  ('edinburgh', '23ba5ec9-f522-46df-8c39-c7e524fd75ec'::uuid, 'f871b7f9-72b8-406f-87ad-b076a7c9772a'::uuid, '3a41ec78ac5093b18d1da42aee74712c8f6d6f6f2d48c9eb1474b23882dd7fc7', '2cf2b620ccc207c3ed3d7257430dff8158e52d15ba89af2cc73ed55f9cf591e6'),
  ('glasgow', '7061da59-94c3-4e43-a124-e6bb0d21dc44'::uuid, '3bbe28cc-93e7-4d29-a5dc-b91dca0ce89d'::uuid, '6eaecf3b1f510d809f45cd24b45f91717e558d943899d0e786b0cd3cfec7f51a', '70c2558cebe40b2888afa51148a705a085b29882ce0f807d3d62d65790a74a48'),
  ('leinster', '6cd84dc2-3fc4-44bd-a1ed-6fb2883b61ad'::uuid, 'edb0ef0c-b3d3-44ee-8107-112b2fd134c8'::uuid, '6a158046253c70f7d493abc0305cc16a175e823ecc6d036ad2adb21c49b900ab', '232def54f07361df88d52fadbc811ff329077019705e02936fedd77fec874667'),
  ('lions', 'c4c73952-49c0-4ea6-8299-0e2bfcfcf99a'::uuid, 'dd550d27-969f-4f86-b590-a3c5e603c467'::uuid, 'ea4d6871ec4c9c78039770f08f2e48e5e364289ec1f34172c9f1e871bd772837', '1058005138e5a253a60e8c48373bcd884fbed1d89b53ad1a3d165469ba783975'),
  ('munster', '6d225fd3-9e9e-4aac-883f-dbab7fd8f8d7'::uuid, 'e7c003f3-5a15-4b98-a3f0-70b8d32d9fa5'::uuid, '6c268f5910637dcdf8a32e27a65fb117dd96433ad4b3c805f205f32bb2e3495f', 'd07ff2e232688f8aeda8c57e53744afcbe5aebd820d38e924b3420b0494cd362'),
  ('ospreys', 'c786bdf5-6057-4bab-b114-666190770e21'::uuid, '983e6f70-a2d5-4df6-ae23-b6ecf3970e8e'::uuid, 'cf75f7327dcebbebd2731a6e191117caccea48620d699ded93bcd6703907caf4', '332b5a2bb1c73c89aaf372645aa4b8811f0090bb5a87c89cd1f36ecf570026bd'),
  ('scarlets', 'ce2fad6d-33a9-4b00-8590-75aafb14edf7'::uuid, '572d6be2-c961-4172-abbe-9c3398fca109'::uuid, '54afb536c4405d05f67360fdb5a51a37ceba8c70adac8be4239d5947ecabb864', '58f3595b234592401f2a9875aa01f934c6aa1186b94f9e2d67c939eb0277875a'),
  ('sharks', '93be1cbe-bdce-43ba-9200-483aef48afe2'::uuid, 'a77a26f9-5e29-4241-9fb5-bd262c33f7a4'::uuid, '11be1c314b1013339ea7271612121f97d6e553ec8db90556e917f614b92be3c7', '436117c59fea0d61872d52888af6b1cb8e1f116ca36ccc6057c598bbf266f68b'),
  ('stormers', 'eb0b5486-1370-4f4f-9f68-f4ad57abb2b0'::uuid, '0721018b-17c0-462c-8d61-34e9a71b3afe'::uuid, '9997bf9d653175ddb2ce9edb2ca58ed29045a946addf6b90d02d5b872e67238f', 'b82c6b496ae4e46d7e384c28bcdf32c00b28d76c06306ff360417fe79dc04599'),
  ('ulster', '7f357b01-fbdf-4dab-b4b7-c3fefc29a55d'::uuid, 'a1b4d093-60c4-4c06-85a5-7d665de76023'::uuid, 'c9f94c5d8f21a925c83b939c23649f9f13e7f6d124d1bd300421860fad996459', '5303f874c8c3ca5e778c0d567acd8ca39898b3c9c7b35ac3438ae860c74f2a9a'),
  ('zebre', '58939fb6-d161-43be-826d-f4bd4ff616b7'::uuid, '22188bd8-4ed2-4ffb-a3dd-a7fbe68617eb'::uuid, 'a1ea5ae9c8b0157695a7be0403688680494444584d3729e45ccc88d046d4cb74', '64ee2ceb764ffe1b99e0c391192d7baa951c786b98e0ece850f20a9cea441417')
)
select expected.*, payload.dashboard_payload as dashboard,
  payload.classification_evidence_sha256,
  payload.cohort_evidence_sha256
from expected
join reporting.aggregate_releases release
  on release.id = expected.release_id and release.status = 'approved'
join reporting.team_release_payloads_v6 payload
  on payload.release_id = expected.release_id
 and payload.team_key = expected.team_key
 and payload.curated_build_id = expected.curated_build_id
 and payload.payload_sha256 = expected.payload_sha256
 and payload.payload_sha256 =
   reporting.canonical_jsonb_sha256_v1(payload.dashboard_payload)
 and payload.season = '2025-26'
 and payload.analysis_version = 'v6'
 and payload.classification_view_version =
   'reporting_classification_2025-26_2026-08-31_v3'
 and payload.classification_evidence_sha256 =
   'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'
 and payload.cohort_view_version =
   'injury_lineage_2025-26_2026-08-30_v2'
 and payload.cohort_evidence_sha256 =
   '7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab'
join reporting.team_release_injury_lineage_v1 binding
  on binding.release_id = expected.release_id
 and binding.team_key = expected.team_key
 and binding.season = '2025-26'
 and binding.lineage_version_id =
   '2f419706-8c36-58dd-b4cb-e92162e782b8'::uuid
 and binding.candidate_snapshot_version = '20260831101000'
 and binding.member_sha256 = expected.member_sha256;

analyze _urc_v6_corrected_members;

do $$
begin
  if (select count(*) from _urc_v6_corrected_members) <> 16
    or (select count(distinct team_key) from _urc_v6_corrected_members) <> 16
  then
    raise exception 'The corrected Year 2 team member set changed before league sealing';
  end if;
end;
$$;

create temporary table _urc_v6_league_coverage on commit drop as
select sum((dashboard #>> '{coverage,hours}')::numeric) as exposure_hours,
  case when count(dashboard #>> '{coverage,match_hours}') = 16
    then sum((dashboard #>> '{coverage,match_hours}')::numeric) end
    as match_hours,
  case when count(dashboard #>> '{coverage,training_hours}') = 16
    then sum((dashboard #>> '{coverage,training_hours}')::numeric) end
    as training_hours,
  case when count(dashboard #>> '{coverage,distance_km}') = 16
    then sum((dashboard #>> '{coverage,distance_km}')::numeric) end
    as distance_km,
  sum((dashboard #>> '{coverage,exposure_rows}')::bigint) as exposure_rows,
  sum((dashboard #>> '{coverage,exposed_players}')::bigint) as exposed_players,
  sum((dashboard #>> '{coverage,weeks}')::bigint) as weeks
from _urc_v6_corrected_members;

create temporary table _urc_v6_league_summary on commit drop as
with headlines as (
  select member.team_key, item
  from _urc_v6_corrected_members member
  cross join lateral jsonb_array_elements(member.dashboard -> 'headline') item
), totals as (
  select
    sum((item ->> 'value')::numeric)
      filter (where item ->> 'key' = 'recorded_injuries') as recorded_injuries,
    sum((item ->> 'value')::numeric)
      filter (where item ->> 'key' = 'time_loss_injuries') as time_loss_injuries,
    sum((item ->> 'numerator')::numeric)
      filter (where item ->> 'key' = 'severity_mean_days') as days_lost,
    sum((item ->> 'denominator')::numeric)
      filter (where item ->> 'key' = 'severity_mean_days')
      as known_duration_time_loss_injuries
  from headlines
), median as (
  select percentile_cont(0.5) within group (order by days_lost)
    as median_severity_days
  from analysis.urc_2025_26_injury_successor_rows_v1
  where is_time_loss and days_lost is not null
)
select totals.*, median.median_severity_days
from totals cross join median;

create temporary table _urc_v6_league_monthly on commit drop as
with rows as (
  select member.team_key, to_date(item ->> 'month', 'Mon YYYY') as month_start,
    (item ->> 'recorded_injuries')::bigint as recorded_injuries,
    (item ->> 'time_loss_injuries')::bigint as time_loss_injuries,
    (item ->> 'days_lost')::numeric as days_lost,
    (item ->> 'exposure_hours')::numeric as exposure_hours,
    (item ->> 'distance_km')::numeric as distance_km
  from _urc_v6_corrected_members member
  cross join lateral jsonb_array_elements(member.dashboard -> 'monthly') item
), domain as (
  select distinct month_start from rows
)
select domain.month_start,
  coalesce(sum(rows.recorded_injuries), 0)::bigint as recorded_injuries,
  coalesce(sum(rows.time_loss_injuries), 0)::bigint as time_loss_injuries,
  coalesce(sum(rows.days_lost), 0)::numeric as days_lost,
  case when count(rows.exposure_hours) = 16 then sum(rows.exposure_hours) end
    as exposure_hours,
  case when count(rows.distance_km) = 16 then sum(rows.distance_km) end
    as distance_km
from domain
left join rows using (month_start)
group by domain.month_start;

create temporary table _urc_v6_league_profiles on commit drop as
with rows as (
  select item ->> 'dimension' as dimension,
    item ->> 'code' as code, item ->> 'label' as label,
    item ->> 'setting' as setting_code,
    (item ->> 'recorded_injuries')::numeric as recorded_injuries,
    (item ->> 'time_loss_injuries')::numeric as time_loss_injuries,
    (item ->> 'days_lost')::numeric as days_lost,
    case when coalesce((item ->> 'days_lost')::numeric, 0) > 0
          and coalesce((item ->> 'mean_severity_days')::numeric, 0) > 0
      then round((item ->> 'days_lost')::numeric
        / (item ->> 'mean_severity_days')::numeric)
      else 0::numeric end as known_duration_time_loss_injuries
  from _urc_v6_corrected_members member
  cross join lateral jsonb_array_elements(member.dashboard -> 'injury_profiles') item
), grouped as (
  select dimension, code, label, setting_code,
    sum(recorded_injuries) as recorded_injuries,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost,
    sum(known_duration_time_loss_injuries)
      as known_duration_time_loss_injuries
  from rows
  group by dimension, code, label, setting_code
)
select grouped.*,
  case grouped.setting_code
    when 'all' then coverage.exposure_hours
    when 'match' then coverage.match_hours
    when 'training' then coverage.training_hours
  end as exposure_hours
from grouped cross join _urc_v6_league_coverage coverage;

create temporary table _urc_v6_league_settings on commit drop as
with rows as (
  select item ->> 'setting' as setting_code, item ->> 'label' as label,
    (item ->> 'recorded_injuries')::numeric as recorded_injuries,
    (item ->> 'time_loss_injuries')::numeric as time_loss_injuries,
    (item ->> 'days_lost')::numeric as days_lost,
    case when coalesce((item ->> 'days_lost')::numeric, 0) > 0
          and coalesce((item ->> 'mean_severity_days')::numeric, 0) > 0
      then round((item ->> 'days_lost')::numeric
        / (item ->> 'mean_severity_days')::numeric)
      else 0::numeric end as known_duration_time_loss_injuries
  from _urc_v6_corrected_members member
  cross join lateral jsonb_array_elements(member.dashboard -> 'setting_metrics') item
), grouped as (
  select setting_code, min(label) as label,
    sum(recorded_injuries) as recorded_injuries,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost,
    sum(known_duration_time_loss_injuries)
      as known_duration_time_loss_injuries
  from rows group by setting_code
)
select grouped.*,
  case grouped.setting_code
    when 'all' then coverage.exposure_hours
    when 'match' then coverage.match_hours
    when 'training' then coverage.training_hours
  end as exposure_hours
from grouped cross join _urc_v6_league_coverage coverage;

create temporary table _urc_v6_league_severity on commit drop as
select item ->> 'key' as key, min(item ->> 'label') as label,
  item ->> 'setting' as setting_code,
  sum((item ->> 'recorded_injuries')::numeric) as recorded_injuries,
  sum((item ->> 'time_loss_injuries')::numeric) as time_loss_injuries,
  sum((item ->> 'days_lost')::numeric) as days_lost
from _urc_v6_corrected_members member
cross join lateral jsonb_array_elements(member.dashboard -> 'severity_distribution') item
group by item ->> 'key', item ->> 'setting';

create temporary table _urc_v6_league_contact on commit drop as
select item ->> 'key' as key, min(item ->> 'label') as label,
  item ->> 'setting' as setting_code,
  sum((item ->> 'recorded_injuries')::numeric) as recorded_injuries,
  sum((item ->> 'time_loss_injuries')::numeric) as time_loss_injuries
from _urc_v6_corrected_members member
cross join lateral jsonb_array_elements(member.dashboard -> 'contact_distribution') item
group by item ->> 'key', item ->> 'setting';

create table analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000 (
  snapshot_version text primary key check (snapshot_version = '20260831110000'),
  season text not null check (season = '2025-26'),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (
    classification_view_version =
      'reporting_classification_2025-26_2026-08-31_v3'
  ),
  classification_evidence_sha256 text not null check (
    classification_evidence_sha256 =
      'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'injury_lineage_2025-26_2026-08-30_v2'
  ),
  cohort_evidence_sha256 text not null check (
    cohort_evidence_sha256 =
      '7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab'
  ),
  member_count integer not null check (member_count = 16),
  member_set_sha256 text not null check (member_set_sha256 ~ '^[0-9a-f]{64}$'),
  member_manifest jsonb not null check (jsonb_typeof(member_manifest) = 'array'),
  member_manifest_sha256 text not null check (
    member_manifest_sha256 ~ '^[0-9a-f]{64}$'
    and member_manifest_sha256 =
      reporting.canonical_jsonb_sha256_v1(member_manifest)
  ),
  dashboard jsonb not null check (jsonb_typeof(dashboard) = 'object'),
  payload_sha256 text not null check (
    payload_sha256 ~ '^[0-9a-f]{64}$'
    and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
  ),
  created_at timestamptz not null default now()
);

alter table analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000
  enable row level security;
revoke all on analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000
  from public, anon, authenticated, web_reader;

create function analysis.reject_urc_2025_26_corrected_league_candidate_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'Corrected Year 2 league candidate snapshot is immutable';
end;
$$;

revoke execute on function
  analysis.reject_urc_2025_26_corrected_league_candidate_mutation()
  from public, anon, authenticated, web_reader;

create trigger urc_2025_26_corrected_league_candidate_immutable
before update or delete
on analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000
for each row execute function
  analysis.reject_urc_2025_26_corrected_league_candidate_mutation();

with member_state as (
  select count(*)::integer as member_count,
    jsonb_agg(jsonb_build_object(
      'team_key', team_key,
      'team_release_id', release_id::text,
      'curated_build_id', curated_build_id::text
    ) order by team_key) as member_set,
    jsonb_agg(jsonb_build_object(
      'team_key', team_key,
      'team_release_id', release_id::text,
      'curated_build_id', curated_build_id::text,
      'payload_sha256', payload_sha256,
      'lineage_member_sha256', member_sha256
    ) order by team_key) as member_manifest
  from _urc_v6_corrected_members
), profile_payload as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'dimension', dimension, 'code', code, 'label', label,
    'setting', setting_code, 'recorded_injuries', recorded_injuries,
    'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
    'exposure_hours', exposure_hours,
    'incidence_per_1000h', analysis.rate_per_1000_v1(
      time_loss_injuries, exposure_hours
    ),
    'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
    'mean_severity_days', days_lost
      / nullif(known_duration_time_loss_injuries, 0)
  ) order by dimension, setting_code, code), '[]'::jsonb) as rows
  from _urc_v6_league_profiles
), dashboard as (
  select jsonb_build_object(
    'generated_at', now(),
    'team', 'URC Overall',
    'season', '2025-26',
    'analysis_window', jsonb_build_object(
      'start', '2025-09-01', 'end', '2026-06-30',
      'basis', 'Exact corrected V3-bound team release set with reviewed V6 exposure.'
    ),
    'method', jsonb_build_array(
      'League values pool the exact sixteen approved corrected team payloads.',
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
      'teams_included', 16
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
      'month', to_char(month_start, 'Mon YYYY'),
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost,
      'exposure_hours', exposure_hours,
      'distance_km', distance_km,
      'overall_incidence_per_1000h', analysis.rate_per_1000_v1(
        recorded_injuries, exposure_hours
      ),
      'incidence_per_1000h', analysis.rate_per_1000_v1(
        time_loss_injuries, exposure_hours
      ),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours)
    ) order by month_start) from _urc_v6_league_monthly), '[]'::jsonb),
    'body_locations', coalesce((select jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', exposure_hours,
      'incidence_per_1000h', analysis.rate_per_1000_v1(
        time_loss_injuries, exposure_hours
      ),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
      'mean_severity_days', days_lost
        / nullif(known_duration_time_loss_injuries, 0)
    ) order by code) from _urc_v6_league_profiles
      where dimension = 'body_location' and setting_code = 'all'), '[]'::jsonb),
    'injury_types', coalesce((select jsonb_agg(jsonb_build_object(
      'key', code, 'label', label, 'time_loss_injuries', time_loss_injuries,
      'days_lost', days_lost, 'exposure_hours', exposure_hours,
      'incidence_per_1000h', analysis.rate_per_1000_v1(
        time_loss_injuries, exposure_hours
      ),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
      'mean_severity_days', days_lost
        / nullif(known_duration_time_loss_injuries, 0)
    ) order by time_loss_injuries desc, code) from _urc_v6_league_profiles
      where dimension = 'injury_type' and setting_code = 'all'), '[]'::jsonb),
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
    ], key)) from _urc_v6_league_severity), '[]'::jsonb),
    'setting_split', coalesce((select jsonb_agg(jsonb_build_object(
      'key', setting_code, 'label', label,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', exposure_hours,
      'overall_incidence_per_1000h', analysis.rate_per_1000_v1(
        recorded_injuries, exposure_hours
      ),
      'incidence_per_1000h', analysis.rate_per_1000_v1(
        time_loss_injuries, exposure_hours
      ),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
      'mean_severity_days', days_lost
        / nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code))
      from _urc_v6_league_settings), '[]'::jsonb),
    'setting_metrics', coalesce((select jsonb_agg(jsonb_build_object(
      'setting', setting_code, 'label', label,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
      'exposure_hours', exposure_hours,
      'overall_incidence_per_1000h', analysis.rate_per_1000_v1(
        recorded_injuries, exposure_hours
      ),
      'incidence_per_1000h', analysis.rate_per_1000_v1(
        time_loss_injuries, exposure_hours
      ),
      'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
      'mean_severity_days', days_lost
        / nullif(known_duration_time_loss_injuries, 0)
    ) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code))
      from _urc_v6_league_settings), '[]'::jsonb),
    'contact_distribution', coalesce((select jsonb_agg(jsonb_build_object(
      'key', key, 'label', label, 'setting', setting_code,
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries
    ) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code),
      array_position(array['contact', 'non_contact', 'unknown'], key))
      from _urc_v6_league_contact), '[]'::jsonb),
    'prior_season', jsonb_build_object(
      'season', '2024-25', 'status', 'frozen',
      'note', 'Prior season remains frozen.'
    ),
    'limitations', jsonb_build_array(
      'Benetton and Edinburgh season exposure hours are temporary league-mean estimates.',
      'Monthly exposure, rates and distance are unavailable because two teams have no source exposure rows.',
      'The release is bound to the private immutable V3 injury lineage.'
    )
  ) as value
  from _urc_v6_league_summary summary
  cross join _urc_v6_league_coverage coverage
  cross join profile_payload
)
insert into analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000 (
  snapshot_version, season, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  member_count, member_set_sha256,
  member_manifest, member_manifest_sha256,
  dashboard, payload_sha256
)
select '20260831110000', '2025-26', 'v6',
  'reporting_classification_2025-26_2026-08-31_v3',
  'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172',
  'injury_lineage_2025-26_2026-08-30_v2',
  '7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab',
  member_state.member_count,
  reporting.canonical_jsonb_sha256_v1(member_state.member_set),
  member_state.member_manifest,
  reporting.canonical_jsonb_sha256_v1(member_state.member_manifest),
  dashboard.value,
  reporting.canonical_jsonb_sha256_v1(dashboard.value)
from member_state cross join dashboard;

do $$
begin
  if (select recorded_injuries from _urc_v6_league_summary) <> 1484
    or (select time_loss_injuries from _urc_v6_league_summary) <> 877
    or (select known_duration_time_loss_injuries from _urc_v6_league_summary) <> 731
    or (select days_lost from _urc_v6_league_summary) <> 19047
    or (select exposure_hours from _urc_v6_league_coverage)
      <> 87854.0133391047619046::numeric
    or (select exposure_rows from _urc_v6_league_coverage) <> 62481
    or (
      select count(*)
      from analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000
      where payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
        and jsonb_array_length(dashboard -> 'headline') = 7
        and jsonb_array_length(member_manifest) = 16
    ) <> 1
    or exists (
      select 1
      from analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000 snapshot
      cross join lateral jsonb_array_elements(snapshot.dashboard -> 'monthly') month
      where month -> 'exposure_hours' <> 'null'::jsonb
        or month -> 'distance_km' <> 'null'::jsonb
        or month -> 'overall_incidence_per_1000h' <> 'null'::jsonb
        or month -> 'incidence_per_1000h' <> 'null'::jsonb
        or month -> 'burden_per_1000h' <> 'null'::jsonb
    )
    or exists (
      select 1
      from analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000 snapshot
      cross join lateral jsonb_array_elements(
        snapshot.dashboard -> 'injury_type_families'
      ) family
      where family ->> 'mapping_version' <>
        'injury_type_family_2026-07-21_v1'
        or family ->> 'code' = 'unmapped_review'
    )
  then
    raise exception 'Corrected Year 2 league candidate failed its exact gates';
  end if;
end;
$$;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with current_members as materialized (
  select member.team_key, member.season, member.team_release_id,
    member.curated_build_id
  from analysis.league_member_releases_v6 member
  where member.season = '2025-26'
), member_set as (
  select season, count(*)::integer as member_count,
    reporting.canonical_jsonb_sha256_v1(jsonb_agg(jsonb_build_object(
      'team_key', team_key,
      'team_release_id', team_release_id::text,
      'curated_build_id', curated_build_id::text
    ) order by team_key)) as member_set_sha256
  from current_members
  group by season
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct team_release_id) = 16
    and count(distinct curated_build_id) = 16
)
select snapshot.season, snapshot.analysis_version,
  snapshot.classification_view_version,
  snapshot.classification_evidence_sha256,
  snapshot.cohort_view_version, snapshot.cohort_evidence_sha256,
  snapshot.dashboard
from analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000 snapshot
join member_set members
  on members.season = snapshot.season
 and members.member_count = snapshot.member_count
 and members.member_set_sha256 = snapshot.member_set_sha256
where snapshot.snapshot_version = '20260831110000'
  and snapshot.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.league_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;
