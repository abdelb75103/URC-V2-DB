-- Additive Year 2 cutover.  The private v3 successor is the sole injury
-- source for this candidate.  Exposure remains the reviewed V6 base.

create view analysis.accepted_urc_2025_26_injury_successor_evidence_v1
with (security_invoker = true) as
select
  'reporting_classification_2025-26_2026-08-30_v2'::text
    as successor_classification_identity,
  'injury_lineage_2025-26_2026-08-30_v2'::text
    as successor_cohort_identity,
  version.id as successor_version_id,
  version.classification_rule_version,
  version.migration_version,
  version.migration_sha256,
  version.master_csv_sha256,
  version.master_workbook_sha256,
  version.inclusion_csv_sha256,
  version.classification_evidence_sha256,
  version.manifest_sha256,
  version.source_bundle_sha256,
  version.master_json_sha256,
  version.inclusion_json_sha256,
  version.delta_payload_sha256,
  version.delta_evidence_sha256,
  version.master_row_count,
  version.included_row_count,
  version.excluded_row_count,
  version.dashboard_injury_row_count,
  version.team_count
from lineage.injury_master_versions_v3 version
where version.id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
  and version.season = '2025-26'
  and version.status = 'valid_ingested_successor'
  and version.classification_rule_version =
    'urc_2025_26_injury_review_triage_2026_08_30_v5'
  and version.migration_version = '20260830140000'
  and version.migration_sha256 =
    '76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a'
  and version.manifest_sha256 =
    '7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab'
  and version.delta_payload_sha256 =
    '111328427560503939a66e845d4a6e0fb8fa606f9dbf4a6f508aa0df04cab637'
  and version.delta_evidence_sha256 =
    'f9e8d82998232a2e7e6f7325f319a685546197b4f4c3ff022f366fafa854c78a'
  and version.master_workbook_sha256 =
    '2b5e2243bfc912fac1561789e9327987d058a5543233f068f3bef9928c397670'
  and version.master_row_count = 2993
  and version.included_row_count = 1923
  and version.excluded_row_count = 1070
  and version.dashboard_injury_row_count = 1484
  and version.team_count = 16;

-- This relation is private.  The frozen row JSON is interpreted only here,
-- then reduced to aggregate candidate sections before a reader release.
create view analysis.urc_2025_26_injury_successor_rows_v1
with (security_invoker = true) as
with frozen as (
  select inclusion.team_key, inclusion.source_row, master.row_values,
    master.final_classification, master.time_loss_days,
    nullif(btrim(master.row_values ->> 'Date Injured'), '') as raw_injury_date
  from lineage.injury_inclusion_rows_v3 inclusion
  join lineage.injury_master_rows_v3 master
    on master.version_id = inclusion.version_id
   and master.source_row = inclusion.source_row
  cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
  where inclusion.version_id = evidence.successor_version_id
    and inclusion.dashboard_eligible
), parsed as (
  select frozen.*,
    case when raw_injury_date ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
      and to_char(to_date(raw_injury_date, 'DD/MM/YYYY'), 'DD/MM/YYYY') = raw_injury_date
      then to_date(raw_injury_date, 'DD/MM/YYYY') end as injury_date
  from frozen
), normalised as (
  select parsed.*,
    case
      when lower(coalesce(row_values ->> 'Occasion category', '')) ~ 'match'
        then 'match'
      when lower(coalesce(row_values ->> 'Occasion category', '')) ~ 'training'
        then 'training'
      else 'unknown'
    end as setting_code,
    case lower(btrim(coalesce(row_values ->> 'Is Contact', '')))
      when 'contact' then 'contact'
      when 'non-contact' then 'non_contact'
      when 'non contact' then 'non_contact'
      else 'unknown'
    end as contact_context,
    coalesce(nullif(lower(regexp_replace(btrim(coalesce(row_values ->> 'Body Part', '')), '[^a-z0-9]+', '_', 'g')), ''), 'unknown')
      as body_location_code,
    coalesce(nullif(lower(regexp_replace(btrim(coalesce(row_values ->> 'Injury Tissue Type/s', '')), '[^a-z0-9]+', '_', 'g')), ''), 'unknown')
      as injury_type_code,
    coalesce(nullif(lower(regexp_replace(btrim(coalesce(row_values ->> 'Specific Diagnosis', '')), '[^a-z0-9]+', '_', 'g')), ''), 'unknown')
      as diagnosis_code
  from parsed
)
select team_key, source_row, injury_date, final_classification = 'Time Loss' as is_time_loss,
  time_loss_days as days_lost, setting_code, contact_context,
  body_location_code, coalesce(nullif(btrim(row_values ->> 'Body Part'), ''), 'Unknown') as body_location_label,
  injury_type_code, coalesce(nullif(btrim(row_values ->> 'Injury Tissue Type/s'), ''), 'Unknown') as injury_type_label,
  diagnosis_code, coalesce(nullif(btrim(row_values ->> 'Specific Diagnosis'), ''), 'Unknown') as diagnosis_label,
  case
    when final_classification = 'Medical Attention' then 'zero_days_medical_attention_only'
    when time_loss_days is null then 'unknown_or_censored'
    when time_loss_days = 1 then 'one_day'
    when time_loss_days between 2 and 3 then 'two_to_three_days'
    when time_loss_days between 4 and 7 then 'four_to_seven_days'
    when time_loss_days between 8 and 28 then 'eight_to_twenty_eight_days'
    else 'greater_than_twenty_eight_days'
  end as severity_code
from normalised;

create view analysis.urc_2025_26_injury_successor_cohort_v1
with (security_invoker = true) as
select active.curated_build_id, active.team_key, active.season,
  injury.is_time_loss, injury.injury_date is null as is_undated
from analysis.analysis_window_active_builds_v6 active
join analysis.urc_2025_26_injury_successor_rows_v1 injury
  on injury.team_key = active.team_key;

create view analysis.urc_2025_26_injury_successor_league_monthly_v1
with (security_invoker = true) as
with injuries as (
  select '2025-26'::text as season, date_trunc('month', injury.injury_date)::date as month_start,
    count(*) filter (where injury.is_time_loss)::bigint as time_loss_injuries
  from analysis.urc_2025_26_injury_successor_rows_v1 injury
  where injury.injury_date is not null
  group by date_trunc('month', injury.injury_date)
), source_exposure as (
  select exposure.season, date_trunc('month', exposure.period_start)::date as month_start,
    sum(exposure.minutes_clean) / 60 as exposure_hours
  from analysis.analysis_window_team_exposure_v6 exposure
  left join analysis.active_exposure_placeholders_v1 placeholder
    on placeholder.team_key = exposure.team_key and placeholder.season = exposure.season
  where placeholder.event_id is null
  group by exposure.season, date_trunc('month', exposure.period_start)
)
select coalesce(injuries.season, source_exposure.season) as season,
  coalesce(injuries.month_start, source_exposure.month_start) as month_start,
  source_exposure.exposure_hours,
  coalesce(injuries.time_loss_injuries, 0)::bigint as time_loss_injuries
from injuries
full join source_exposure using (season, month_start);

create view analysis.urc_2025_26_injury_successor_league_summary_v1
with (security_invoker = true) as
select '2025-26'::text as season, sum(hours.total_hours) as exposure_hours
from analysis.analysis_window_team_hours_v6 hours
where hours.season = '2025-26'
having count(*) = 16
  and sum(hours.total_hours) = 87854.0133391047619046::numeric;

create table analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor (
  snapshot_version text not null check (snapshot_version = '20260830170000'),
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
  injury_lineage_version_id uuid not null references lineage.injury_master_versions_v3(id),
  injury_lineage_snapshot_version text not null check (injury_lineage_snapshot_version = '20260830170000'),
  injury_lineage_member_sha256 text not null check (injury_lineage_member_sha256 ~ '^[0-9a-f]{64}$'),
  dashboard jsonb not null check (jsonb_typeof(dashboard) = 'object'),
  created_at timestamptz not null default now(),
  primary key (snapshot_version, team_key),
  unique (snapshot_version, curated_build_id),
  unique (snapshot_version, team_key, injury_lineage_member_sha256),
  check (payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard))
);

alter table analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor
  enable row level security;
revoke all on analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor,
  analysis.accepted_urc_2025_26_injury_successor_evidence_v1,
  analysis.urc_2025_26_injury_successor_rows_v1,
  analysis.urc_2025_26_injury_successor_cohort_v1,
  analysis.urc_2025_26_injury_successor_league_monthly_v1,
  analysis.urc_2025_26_injury_successor_league_summary_v1
  from public, anon, authenticated, web_reader;

create function analysis.reject_urc_2025_26_injury_successor_candidate_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'Year 2 injury-successor candidate snapshot is immutable';
end;
$$;

revoke execute on function analysis.reject_urc_2025_26_injury_successor_candidate_mutation()
  from public, anon, authenticated, web_reader;

create trigger urc_2025_26_injury_successor_candidate_immutable
before update or delete
on analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor
for each row execute function analysis.reject_urc_2025_26_injury_successor_candidate_mutation();

create table reporting.team_release_injury_lineage_v1 (
  release_id uuid primary key references reporting.aggregate_releases(id),
  team_key text not null references reporting.teams(team_key),
  season text not null check (season = '2025-26'),
  lineage_version_id uuid not null references lineage.injury_master_versions_v3(id),
  candidate_snapshot_version text not null check (candidate_snapshot_version = '20260830170000'),
  member_sha256 text not null check (member_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique (release_id, team_key, season, lineage_version_id, candidate_snapshot_version)
);

alter table reporting.team_release_injury_lineage_v1 enable row level security;
revoke all on reporting.team_release_injury_lineage_v1 from public, anon, authenticated, web_reader;

create function reporting.reject_team_release_injury_lineage_v1_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'team release injury-lineage bindings are immutable';
end;
$$;

revoke execute on function reporting.reject_team_release_injury_lineage_v1_mutation()
  from public, anon, authenticated, web_reader;

create trigger team_release_injury_lineage_v1_immutable
before update or delete on reporting.team_release_injury_lineage_v1
for each row execute function reporting.reject_team_release_injury_lineage_v1_mutation();

alter table reporting.team_release_payloads_v6
  drop constraint team_release_payloads_v6_classification_view_version_check,
  add constraint team_release_payloads_v6_classification_view_version_check check (
    classification_view_version in (
      'reporting_classification_2026-07-22_v2',
      'reporting_classification_2025-26_2026-08-30_v2'
    )
  ),
  drop constraint team_release_payloads_v6_cohort_view_version_check,
  add constraint team_release_payloads_v6_cohort_view_version_check check (
    cohort_view_version in (
      'analysis_window_2025-26_2026-08-15_v1',
      'injury_lineage_2025-26_2026-08-30_v2'
    )
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_classification_view_version_check,
  add constraint league_release_context_v2_classification_view_version_check check (
    classification_view_version in (
      'v2',
      'reporting_classification_2026-07-20_v1',
      'reporting_classification_2026-07-22_v2',
      'reporting_classification_2024-25_2026-08-27_v1',
      'reporting_classification_2025-26_2026-08-30_v2'
    )
  ),
  drop constraint league_release_context_v2_classification_evidence,
  add constraint league_release_context_v2_classification_evidence check (
    (classification_view_version = 'v2' and classification_evidence_sha256 is null)
    or (classification_view_version <> 'v2' and classification_evidence_sha256 is not null)
  ),
  drop constraint league_release_context_v2_cohort_view_version_check,
  add constraint league_release_context_v2_cohort_view_version_check check (
    cohort_view_version in (
      'v2',
      'season_bound_2026-07-20_v1',
      'lineage_2024-25_2026-07-24_v1',
      'analysis_window_2024-25_2026-07-25_v1',
      'analysis_window_2024-25_2026-08-30_v2',
      'analysis_window_2025-26_2026-08-15_v1',
      'injury_lineage_2025-26_2026-08-30_v2'
    )
  ),
  drop constraint league_release_context_v2_cohort_evidence,
  add constraint league_release_context_v2_cohort_evidence check (
    (cohort_view_version = 'v2' and cohort_evidence_sha256 is null)
    or (cohort_view_version <> 'v2' and cohort_evidence_sha256 is not null)
  );

create view analysis.urc_2025_26_injury_successor_candidate_material_v1
with (security_invoker = true) as
with active_builds as materialized (
  select team_key, season, curated_build_id
  from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), rows as materialized (
  select active.curated_build_id, active.team_key, active.season,
    injury.source_row, injury.injury_date, injury.is_time_loss,
    injury.days_lost, injury.setting_code, injury.contact_context,
    injury.body_location_code, injury.body_location_label,
    injury.injury_type_code, injury.injury_type_label,
    injury.diagnosis_code, injury.diagnosis_label, injury.severity_code
  from active_builds active
  left join analysis.urc_2025_26_injury_successor_rows_v1 injury
    on injury.team_key = active.team_key
), summary as materialized (
  select curated_build_id, team_key, season, count(source_row)::bigint as recorded_injuries,
    count(source_row) filter (where is_time_loss)::bigint as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost,
    avg(days_lost) filter (where is_time_loss and days_lost is not null) as mean_severity_days,
    percentile_cont(0.5) within group (order by days_lost)
      filter (where is_time_loss and days_lost is not null) as median_severity_days
  from rows group by curated_build_id, team_key, season
), coverage as materialized (
  select active.curated_build_id, active.team_key, active.season,
    hours.total_hours, hours.match_hours, hours.training_hours, hours.distance_km,
    hours.exposure_grain,
    count(exposure.*)::bigint as exposure_rows,
    count(distinct nullif(exposure.player_uid, 'Unknown'))::bigint as exposed_players,
    count(distinct date_trunc('week', exposure.period_start))::bigint as weeks,
    placeholder.event_id is not null
      and not completeness.denominator_available as temporary_estimate
  from active_builds active
  join analysis.analysis_window_team_hours_v6 hours
    on hours.curated_build_id = active.curated_build_id
   and hours.team_key = active.team_key and hours.season = active.season
  left join analysis.analysis_window_team_exposure_completeness_v6 completeness
    on completeness.curated_build_id = active.curated_build_id
   and completeness.team_key = active.team_key and completeness.season = active.season
  left join analysis.active_exposure_placeholders_v1 placeholder
    on placeholder.team_key = active.team_key and placeholder.season = active.season
  left join analysis.analysis_window_team_exposure_v6 exposure
    on exposure.curated_build_id = active.curated_build_id
   and exposure.team_key = active.team_key and exposure.season = active.season
  group by active.curated_build_id, active.team_key, active.season, hours.total_hours,
    hours.match_hours, hours.training_hours, hours.distance_km, hours.exposure_grain,
    placeholder.event_id, completeness.denominator_available
), monthly_exposure as materialized (
  select curated_build_id, team_key, season, date_trunc('month', period_start)::date as month_start,
    sum(minutes_clean) / 60 as exposure_hours, sum(distance_m_clean) / 1000 as distance_km
  from analysis.analysis_window_team_exposure_v6
  group by curated_build_id, team_key, season, date_trunc('month', period_start)
), monthly_injuries as materialized (
  select curated_build_id, team_key, season, date_trunc('month', injury_date)::date as month_start,
    count(rows.source_row)::bigint as recorded_injuries,
    count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
  from rows where injury_date is not null
  group by curated_build_id, team_key, season, date_trunc('month', injury_date)
), monthly as materialized (
  select domain.curated_build_id, domain.team_key, domain.season, domain.month_start,
    exposure.exposure_hours, exposure.distance_km,
    coalesce(injuries.recorded_injuries, 0)::bigint as recorded_injuries,
    coalesce(injuries.time_loss_injuries, 0)::bigint as time_loss_injuries,
    coalesce(injuries.days_lost, 0)::numeric as days_lost
  from (
    select curated_build_id, team_key, season, month_start from monthly_exposure
    union
    select curated_build_id, team_key, season, month_start from monthly_injuries
  ) domain
  left join monthly_exposure exposure using (curated_build_id, team_key, season, month_start)
  left join monthly_injuries injuries using (curated_build_id, team_key, season, month_start)
), profiles as materialized (
  select rows.curated_build_id, rows.team_key, rows.season, settings.setting_code,
    dimensions.dimension, dimensions.code, dimensions.label,
    count(rows.source_row)::bigint as recorded_injuries,
    count(*) filter (where rows.is_time_loss)::bigint as time_loss_injuries,
    count(*) filter (where rows.is_time_loss and rows.days_lost is not null)::bigint as known_duration_time_loss_injuries,
    coalesce(sum(rows.days_lost) filter (where rows.is_time_loss), 0)::numeric as days_lost
  from rows
  cross join lateral (values
    ('body_location'::text, rows.body_location_code, rows.body_location_label),
    ('injury_type'::text, rows.injury_type_code, rows.injury_type_label),
    ('diagnosis'::text, rows.diagnosis_code, rows.diagnosis_label)
  ) dimensions(dimension, code, label)
  cross join lateral (values ('all'::text), (rows.setting_code)) settings(setting_code)
  group by rows.curated_build_id, rows.team_key, rows.season, settings.setting_code,
    dimensions.dimension, dimensions.code, dimensions.label
), setting_metrics as materialized (
  select active.curated_build_id, active.team_key, active.season, domain.setting_code,
    count(rows.source_row) filter (where domain.setting_code = 'all' or rows.setting_code = domain.setting_code)::bigint as recorded_injuries,
    count(rows.source_row) filter (where rows.is_time_loss and (domain.setting_code = 'all' or rows.setting_code = domain.setting_code))::bigint as time_loss_injuries,
    count(rows.source_row) filter (where rows.is_time_loss and rows.days_lost is not null and (domain.setting_code = 'all' or rows.setting_code = domain.setting_code))::bigint as known_duration_time_loss_injuries,
    coalesce(sum(rows.days_lost) filter (where rows.is_time_loss and (domain.setting_code = 'all' or rows.setting_code = domain.setting_code)), 0)::numeric as days_lost
  from active_builds active
  cross join (values ('all'::text), ('match'::text), ('training'::text), ('unknown'::text)) domain(setting_code)
  left join rows on rows.curated_build_id = active.curated_build_id
    and rows.team_key = active.team_key and rows.season = active.season
  group by active.curated_build_id, active.team_key, active.season, domain.setting_code
), severity as materialized (
  select active.curated_build_id, active.team_key, active.season, domain.severity_code,
    count(rows.source_row) filter (where rows.severity_code = domain.severity_code)::bigint as recorded_injuries,
    count(rows.source_row) filter (where rows.severity_code = domain.severity_code and rows.is_time_loss)::bigint as time_loss_injuries,
    count(rows.source_row) filter (where rows.severity_code = domain.severity_code and rows.is_time_loss and rows.days_lost is not null)::bigint as known_duration_time_loss_injuries,
    coalesce(sum(rows.days_lost) filter (where rows.severity_code = domain.severity_code and rows.is_time_loss), 0)::numeric as days_lost
  from active_builds active
  cross join (values ('zero_days_medical_attention_only'::text), ('one_day'::text),
    ('two_to_three_days'::text), ('four_to_seven_days'::text),
    ('eight_to_twenty_eight_days'::text), ('greater_than_twenty_eight_days'::text),
    ('unknown_or_censored'::text)) domain(severity_code)
  left join rows on rows.curated_build_id = active.curated_build_id
    and rows.team_key = active.team_key and rows.season = active.season
  group by active.curated_build_id, active.team_key, active.season, domain.severity_code
), contact as materialized (
  select active.curated_build_id, active.team_key, active.season, settings.setting_code,
    contexts.contact_context, contexts.contact_label,
    count(rows.source_row) filter (where rows.contact_context = contexts.contact_context and (settings.setting_code = 'all' or rows.setting_code = settings.setting_code))::bigint as recorded_injuries,
    count(rows.source_row) filter (where rows.contact_context = contexts.contact_context and rows.is_time_loss and (settings.setting_code = 'all' or rows.setting_code = settings.setting_code))::bigint as time_loss_injuries
  from active_builds active
  cross join (values ('all'::text), ('match'::text), ('training'::text), ('unknown'::text)) settings(setting_code)
  cross join (values ('contact'::text, 'Contact'::text), ('non_contact'::text, 'Non-contact'::text), ('unknown'::text, 'Unknown'::text)) contexts(contact_context, contact_label)
  left join rows on rows.curated_build_id = active.curated_build_id
    and rows.team_key = active.team_key and rows.season = active.season
  group by active.curated_build_id, active.team_key, active.season, settings.setting_code,
    contexts.contact_context, contexts.contact_label
)
select active.team_key, active.season, active.curated_build_id,
  'v6'::text as analysis_version,
  'reporting_classification_2025-26_2026-08-30_v2'::text as classification_view_version,
  evidence.classification_evidence_sha256,
  'injury_lineage_2025-26_2026-08-30_v2'::text as cohort_view_version,
  evidence.manifest_sha256 as cohort_evidence_sha256,
  evidence.successor_version_id as injury_lineage_version_id,
  '20260830170000'::text as injury_lineage_snapshot_version,
  lineage_members.member_sha256 as injury_lineage_member_sha256,
  jsonb_build_object(
    'generated_at', now(), 'team', roster.display_name, 'season', active.season,
    'analysis_window', jsonb_build_object('start', '2025-09-01', 'end', '2026-06-30', 'basis', 'Private V3 injury successor with reviewed V6 exposure.'),
    'method', jsonb_build_array('Recorded injuries use the 1,484 dashboard-eligible V3 rows.', 'Time-loss status uses final classification. Days lost use known time_loss_days only.'),
    'coverage', jsonb_build_object('hours', coverage.total_hours, 'match_hours', coverage.match_hours,
      'training_hours', coverage.training_hours, 'distance_km', coverage.distance_km,
      'exposure_grain', coverage.exposure_grain, 'exposure_rows', coverage.exposure_rows,
      'exposed_players', coverage.exposed_players, 'weeks', coverage.weeks,
      'included_exposure_status', case when coverage.temporary_estimate then 'temporary_league_mean_estimate_no_source_exposure' else 'source_backed_exposure_submitted_may_be_incomplete' end,
      'analysis_window_start', '2025-09-01', 'analysis_window_end', '2026-06-30'),
    'headline', jsonb_build_array(
      jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries', 'value', summary.recorded_injuries, 'unit', 'injuries', 'formula', 'count(final classified eligible injury rows, including undated)'),
      jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries', 'value', summary.time_loss_injuries, 'unit', 'injuries', 'formula', 'count(final classification = Time Loss)'),
      jsonb_build_object('key', 'overall_incidence_per_1000h', 'label', 'Overall incidence', 'value', analysis.rate_per_1000_v1(summary.recorded_injuries, coverage.total_hours), 'unit', 'per 1,000 player-hours', 'numerator', summary.recorded_injuries, 'denominator', coverage.total_hours, 'formula', 'pooled recorded injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence', 'value', analysis.rate_per_1000_v1(summary.time_loss_injuries, coverage.total_hours), 'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries, 'denominator', coverage.total_hours, 'formula', 'pooled final Time Loss injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity', 'value', summary.mean_severity_days, 'unit', 'days lost per injury', 'numerator', summary.days_lost, 'denominator', count_rows.known_duration_time_loss, 'formula', 'known-duration Time Loss days lost / known-duration Time Loss injuries'),
      jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity', 'value', summary.median_severity_days, 'unit', 'days lost per injury', 'denominator', count_rows.known_duration_time_loss, 'formula', 'median known-duration Time Loss days lost'),
      jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden', 'value', analysis.rate_per_1000_v1(summary.days_lost, coverage.total_hours), 'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost, 'denominator', coverage.total_hours, 'formula', 'known-duration Time Loss days lost / pooled exposure hours * 1000')
    ),
    'monthly', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(month_start, 'Mon YYYY'), 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case when coverage.temporary_estimate then null else exposure_hours end, 'distance_km', case when coverage.temporary_estimate then null else distance_km end, 'overall_incidence_per_1000h', case when coverage.temporary_estimate then null else analysis.rate_per_1000_v1(recorded_injuries, exposure_hours) end, 'incidence_per_1000h', case when coverage.temporary_estimate then null else analysis.rate_per_1000_v1(time_loss_injuries, exposure_hours) end, 'burden_per_1000h', case when coverage.temporary_estimate then null else analysis.rate_per_1000_v1(days_lost, exposure_hours) end) order by month_start) from monthly where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'body_locations', coalesce((select jsonb_agg(jsonb_build_object('key', code, 'label', label, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', coverage.total_hours, 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, coverage.total_hours), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, coverage.total_hours), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by code) from profiles where curated_build_id = active.curated_build_id and team_key = active.team_key and setting_code = 'all' and dimension = 'body_location'), '[]'::jsonb),
    'injury_types', coalesce((select jsonb_agg(jsonb_build_object('key', code, 'label', label, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', coverage.total_hours, 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, coverage.total_hours), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, coverage.total_hours), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by time_loss_injuries desc, code) from profiles where curated_build_id = active.curated_build_id and team_key = active.team_key and setting_code = 'all' and dimension = 'injury_type'), '[]'::jsonb),
    'injury_profiles', coalesce((select jsonb_agg(jsonb_build_object('dimension', dimension, 'code', code, 'label', label, 'setting', setting_code, 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end, 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by dimension, setting_code, code) from profiles where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'injury_type_families', analysis.injury_type_families_from_payload_v1(coalesce((select jsonb_agg(jsonb_build_object('dimension', dimension, 'code', code, 'label', label, 'setting', setting_code, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end, 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by dimension, setting_code, code) from profiles where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb)),
    'severity_distribution', coalesce((select jsonb_agg(jsonb_build_object('setting', 'all', 'key', severity_code, 'label', case severity_code when 'zero_days_medical_attention_only' then 'Medical attention' when 'one_day' then '1 day' when 'two_to_three_days' then '2-3 days' when 'four_to_seven_days' then '4-7 days' when 'eight_to_twenty_eight_days' then '8-28 days' when 'greater_than_twenty_eight_days' then '>28 days' else 'Unknown or censored' end, 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost) order by array_position(array['zero_days_medical_attention_only', 'one_day', 'two_to_three_days', 'four_to_seven_days', 'eight_to_twenty_eight_days', 'greater_than_twenty_eight_days', 'unknown_or_censored'], severity_code)) from severity where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'setting_split', coalesce((select jsonb_agg(jsonb_build_object('key', setting_code, 'label', initcap(setting_code), 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end, 'overall_incidence_per_1000h', analysis.rate_per_1000_v1(recorded_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code)) from setting_metrics where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'setting_metrics', coalesce((select jsonb_agg(jsonb_build_object('setting', setting_code, 'label', initcap(setting_code), 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end, 'overall_incidence_per_1000h', analysis.rate_per_1000_v1(recorded_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code)) from setting_metrics where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'contact_distribution', coalesce((select jsonb_agg(jsonb_build_object('key', contact_context, 'label', contact_label, 'setting', setting_code, 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code), array_position(array['contact', 'non_contact', 'unknown'], contact_context)) from contact where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'prior_season', jsonb_build_object('season', '2024-25', 'status', 'frozen', 'note', 'Prior season remains frozen.'),
    'limitations', jsonb_build_array('V3 injury successor is bound to a private immutable lineage snapshot.') || case when coverage.temporary_estimate then jsonb_build_array('Season exposure hours are a temporary mean of the other 14 source-backed team totals, not submitted exposure.', 'Monthly exposure, rates and distance are unavailable because no source rows support them.') else '[]'::jsonb end
  ) as dashboard
from active_builds active
join reporting.teams roster on roster.team_key = active.team_key
join summary
  on summary.curated_build_id = active.curated_build_id
 and summary.team_key = active.team_key
 and summary.season = active.season
join coverage
  on coverage.curated_build_id = active.curated_build_id
 and coverage.team_key = active.team_key
 and coverage.season = active.season
cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
cross join lateral (select count(*) filter (where is_time_loss and days_lost is not null)::bigint as known_duration_time_loss from rows where curated_build_id = active.curated_build_id and team_key = active.team_key) count_rows
cross join lateral (
  select reporting.canonical_jsonb_sha256_v1(coalesce(jsonb_agg(jsonb_build_object(
    'source_row', inclusion.source_row, 'row_sha256', inclusion.row_sha256,
    'final_classification', master.final_classification, 'time_loss_days', master.time_loss_days
  ) order by inclusion.source_row), '[]'::jsonb)) as member_sha256
  from lineage.injury_inclusion_rows_v3 inclusion
  join lineage.injury_master_rows_v3 master
    on master.version_id = inclusion.version_id and master.source_row = inclusion.source_row
  where inclusion.version_id = evidence.successor_version_id
    and inclusion.team_key = active.team_key and inclusion.dashboard_eligible
) lineage_members;

with active_builds as materialized (
  select team_key, season, curated_build_id from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), build_state as (
  select jsonb_agg(jsonb_build_object('team_key', team_key, 'curated_build_id', curated_build_id::text) order by team_key) as builds
  from active_builds having count(*) = 16 and count(distinct team_key) = 16
), placeholder_state as (
  select jsonb_agg(jsonb_build_object('team_key', team_key, 'event_id', event_id, 'method', method, 'estimated_total_hours', estimated_total_hours, 'evidence_sha256', evidence_sha256) order by team_key) as placeholders
  from analysis.active_exposure_placeholders_v1 where season = '2025-26'
  having count(*) = 2 and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
), active_state as (
  select reporting.canonical_jsonb_sha256_v1(jsonb_build_object('successor', to_jsonb(evidence), 'builds', build_state.builds, 'placeholders', placeholder_state.placeholders)) as active_state_sha256
  from build_state cross join placeholder_state cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
)
insert into analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor (
  snapshot_version, active_state_sha256, payload_sha256, team_key, season, curated_build_id,
  analysis_version, classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, injury_lineage_version_id,
  injury_lineage_snapshot_version, injury_lineage_member_sha256, dashboard
)
select '20260830170000', active_state.active_state_sha256,
  reporting.canonical_jsonb_sha256_v1(material.dashboard), material.team_key, material.season,
  material.curated_build_id, material.analysis_version, material.classification_view_version,
  material.classification_evidence_sha256, material.cohort_view_version,
  material.cohort_evidence_sha256, material.injury_lineage_version_id,
  material.injury_lineage_snapshot_version, material.injury_lineage_member_sha256,
  material.dashboard
from analysis.urc_2025_26_injury_successor_candidate_material_v1 material
cross join active_state;

do $$
begin
  if (select count(*) from analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor) <> 16
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1) <> 1484
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1 where is_time_loss) <> 877
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1 where not is_time_loss) <> 607
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1 where days_lost is not null and not is_time_loss) <> 0
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1 where is_time_loss and days_lost is not null) <> 731
    or (select coalesce(sum(days_lost), 0) from analysis.urc_2025_26_injury_successor_rows_v1 where is_time_loss) <> 19047
    or (select coalesce(sum(total_hours), 0) from analysis.analysis_window_team_hours_v6 where season = '2025-26') <> 87854.0133391047619046::numeric
    or (select coalesce(sum(total_hours), 0) from analysis.analysis_window_team_exposure_completeness_v6 where season = '2025-26' and team_key not in ('benetton', 'edinburgh')) <> 76872.2616717166666666::numeric
    or (select count(*)
        from analysis.analysis_window_team_hours_v6
        where season = '2025-26'
          and team_key in ('benetton', 'edinburgh')
          and total_hours = 5490.8758336940476190::numeric) <> 2
    or (select coalesce(sum((dashboard -> 'coverage' ->> 'exposure_rows')::bigint), 0)
        from analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor
        where team_key not in ('benetton', 'edinburgh')) <> 62481
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor candidate
      where candidate.team_key in ('benetton', 'edinburgh')
        and (
          (candidate.dashboard -> 'coverage' ->> 'exposure_rows')::bigint <> 0
          or candidate.dashboard -> 'coverage' -> 'distance_km' <> 'null'::jsonb
          or candidate.dashboard -> 'coverage' ->> 'included_exposure_status'
             <> 'temporary_league_mean_estimate_no_source_exposure'
          or not (candidate.dashboard -> 'limitations' @> jsonb_build_array(
            'Season exposure hours are a temporary mean of the other 14 source-backed team totals, not submitted exposure.'
          ))
          or exists (
            select 1
            from jsonb_array_elements(candidate.dashboard -> 'monthly') month
            where month -> 'exposure_hours' <> 'null'::jsonb
               or month -> 'distance_km' <> 'null'::jsonb
          )
        )
    )
    or exists (select 1 from analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor where jsonb_array_length(dashboard -> 'headline') <> 7)
  then
    raise exception 'Year 2 injury-successor candidate snapshot is incomplete';
  end if;
end;
$$;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with active_builds as materialized (
  select team_key, season, curated_build_id from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), build_state as (
  select jsonb_agg(jsonb_build_object('team_key', team_key, 'curated_build_id', curated_build_id::text) order by team_key) as builds
  from active_builds having count(*) = 16 and count(distinct team_key) = 16
), placeholder_state as (
  select jsonb_agg(jsonb_build_object('team_key', team_key, 'event_id', event_id, 'method', method, 'estimated_total_hours', estimated_total_hours, 'evidence_sha256', evidence_sha256) order by team_key) as placeholders
  from analysis.active_exposure_placeholders_v1 where season = '2025-26'
  having count(*) = 2 and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
), active_state as (
  select reporting.canonical_jsonb_sha256_v1(jsonb_build_object('successor', to_jsonb(evidence), 'builds', build_state.builds, 'placeholders', placeholder_state.placeholders)) as active_state_sha256
  from build_state cross join placeholder_state cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
)
select snapshot.team_key, snapshot.season, null::uuid as team_release_id, snapshot.curated_build_id,
  snapshot.analysis_version, snapshot.classification_view_version, snapshot.classification_evidence_sha256,
  snapshot.cohort_view_version, snapshot.cohort_evidence_sha256, snapshot.dashboard,
  null::bigint as processing_eligible_injury_count,
  null::bigint as eligible_curated_injury_count,
  null::bigint as recorded_cohort_count,
  null::text as processing_record_version_set_sha256,
  null::text as curated_record_version_set_sha256,
  null::text as reporting_record_version_set_sha256,
  null::bigint as approved_injury_source_file_count,
  null::bigint as unapproved_injury_source_row_count,
  null::bigint as wrong_problem_type_rule_version_count,
  snapshot.injury_lineage_version_id, snapshot.injury_lineage_snapshot_version,
  snapshot.injury_lineage_member_sha256
from analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor snapshot
join active_state on active_state.active_state_sha256 = snapshot.active_state_sha256
where snapshot.snapshot_version = '20260830170000'
  and snapshot.payload_sha256 = reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.urc_2025_26_injury_successor_candidate_material_v1,
  analysis.team_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;
