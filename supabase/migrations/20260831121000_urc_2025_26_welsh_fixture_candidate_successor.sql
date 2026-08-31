-- Build the reviewed Welsh exact-date cohort into one immutable V6 team candidate.
-- The other fourteen stored dashboard payloads remain byte-identical.

create view analysis.urc_2025_26_reporting_key_rows_v3
with (security_invoker = true) as
select source.*,
  coalesce(body.code, 'unknown') as reporting_body_location_code,
  coalesce(body.label, 'Unknown') as reporting_body_location_label,
  body.code is not null as body_location_mapping_found,
  coalesce(injury_type.code, 'unknown') as reporting_injury_type_code,
  coalesce(injury_type.label, 'Unknown') as reporting_injury_type_label,
  injury_type.code is not null as injury_type_mapping_found,
  coalesce(nullif(regexp_replace(
    lower(btrim(source.diagnosis_label)), '[^a-z0-9]+', '_', 'g'
  ), ''), 'unknown') as reporting_diagnosis_code
from analysis.urc_2025_26_injury_fixture_corrected_rows_v2 source
left join lateral (
  select controlled.code, controlled.label
  from curated.code_lists controlled
  where controlled.list_name = 'body_location'
    and controlled.active
    and (
      lower(controlled.code) = lower(source.body_location_label)
      or lower(controlled.label) = lower(source.body_location_label)
    )
  order by
    (lower(controlled.label) = lower(source.body_location_label)) desc,
    controlled.code
  limit 1
) body on true
left join lateral (
  select controlled.code, controlled.label
  from curated.code_lists controlled
  where controlled.list_name = 'injury_type'
    and controlled.active
    and (
      lower(controlled.code) = lower(source.injury_type_label)
      or lower(controlled.label) = lower(source.injury_type_label)
    )
  order by
    (lower(controlled.label) = lower(source.injury_type_label)) desc,
    controlled.code
  limit 1
) injury_type on true;

create view analysis.urc_2025_26_reporting_key_profiles_v3
with (security_invoker = true) as
with expanded as (
  select rows.team_key, settings.setting_code,
    dimensions.dimension, dimensions.code, dimensions.label,
    rows.is_time_loss, rows.days_lost
  from analysis.urc_2025_26_reporting_key_rows_v3 rows
  cross join lateral (values
    ('body_location'::text, rows.reporting_body_location_code,
      rows.reporting_body_location_label),
    ('injury_type'::text, rows.reporting_injury_type_code,
      rows.reporting_injury_type_label),
    ('diagnosis'::text, rows.reporting_diagnosis_code,
      rows.diagnosis_label)
  ) dimensions(dimension, code, label)
  cross join lateral (values ('all'::text), (rows.setting_code))
    settings(setting_code)
)
select team_key, setting_code, dimension, code, label,
  count(*)::bigint as recorded_injuries,
  count(*) filter (where is_time_loss)::bigint as time_loss_injuries,
  count(*) filter (where is_time_loss and days_lost is not null)::bigint
    as known_duration_time_loss_injuries,
  coalesce(sum(days_lost) filter (where is_time_loss), 0)::numeric as days_lost
from expanded
group by team_key, setting_code, dimension, code, label;

revoke all on analysis.urc_2025_26_reporting_key_rows_v3,
  analysis.urc_2025_26_reporting_key_profiles_v3
  from public, anon, authenticated, web_reader;

create view analysis.urc_2025_26_injury_fixture_corrected_cohort_v2
with (security_invoker = true) as
select active.curated_build_id, active.team_key, active.season,
  injury.is_time_loss, injury.injury_date is null as is_undated
from analysis.analysis_window_active_builds_v6 active
join analysis.urc_2025_26_injury_fixture_corrected_rows_v2 injury
  on injury.team_key = active.team_key;

create view analysis.urc_2025_26_injury_fixture_corrected_league_monthly_v2
with (security_invoker = true) as
with injuries as (
  select '2025-26'::text as season,
    date_trunc('month', injury.injury_date)::date as month_start,
    count(*) filter (where injury.is_time_loss)::bigint as time_loss_injuries
  from analysis.urc_2025_26_injury_fixture_corrected_rows_v2 injury
  where injury.injury_date is not null
  group by date_trunc('month', injury.injury_date)
), source_exposure as (
  select exposure.season,
    date_trunc('month', exposure.period_start)::date as month_start,
    sum(exposure.minutes_clean) / 60 as exposure_hours
  from analysis.analysis_window_team_exposure_v6 exposure
  left join analysis.active_exposure_placeholders_v1 placeholder
    on placeholder.team_key = exposure.team_key
   and placeholder.season = exposure.season
  where placeholder.event_id is null
  group by exposure.season, date_trunc('month', exposure.period_start)
)
select coalesce(injuries.season, source_exposure.season) as season,
  coalesce(injuries.month_start, source_exposure.month_start) as month_start,
  source_exposure.exposure_hours,
  coalesce(injuries.time_loss_injuries, 0)::bigint as time_loss_injuries
from injuries
full join source_exposure using (season, month_start);

create view analysis.urc_2025_26_injury_fixture_corrected_league_summary_v2
with (security_invoker = true) as
select '2025-26'::text as season, sum(hours.total_hours) as exposure_hours
from analysis.analysis_window_team_hours_v6 hours
where hours.season = '2025-26'
having count(*) = 16
  and sum(hours.total_hours) = 87854.0133391047619046::numeric;

revoke all on
  analysis.urc_2025_26_injury_fixture_corrected_cohort_v2,
  analysis.urc_2025_26_injury_fixture_corrected_league_monthly_v2,
  analysis.urc_2025_26_injury_fixture_corrected_league_summary_v2
  from public, anon, authenticated, web_reader;

create view analysis.urc_2025_26_welsh_fixture_candidate_material_v3
with (security_invoker = true) as
with active_builds as materialized (
  select team_key, season, curated_build_id
  from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), rows as materialized (
  select active.curated_build_id, active.team_key, active.season,
    injury.source_row, injury.injury_date, injury.is_time_loss,
    injury.days_lost, injury.setting_code, injury.contact_context,
    injury.reporting_body_location_code as body_location_code, injury.reporting_body_location_label as body_location_label,
    injury.reporting_injury_type_code as injury_type_code, injury.reporting_injury_type_label as injury_type_label,
    injury.reporting_diagnosis_code as diagnosis_code, injury.diagnosis_label, injury.severity_code
  from active_builds active
  left join analysis.urc_2025_26_reporting_key_rows_v3 injury
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
  'reporting_classification_2025-26_2026-08-31_v3'::text as classification_view_version,
  'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'::text
    as classification_evidence_sha256,
  'injury_lineage_2025-26_2026-08-31_v3'::text as cohort_view_version,
  'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450'::text as cohort_evidence_sha256,
  evidence.successor_version_id as injury_lineage_version_id,
  '20260831121000'::text as injury_lineage_snapshot_version,
  lineage_members.member_sha256 as injury_lineage_member_sha256,
  jsonb_build_object(
    'generated_at', now(), 'team', roster.display_name, 'season', active.season,
    'analysis_window', jsonb_build_object('start', '2025-09-01', 'end', '2026-06-30', 'basis', 'Private V3 injury successor with reviewed Welsh exact-date fixture correction and V6 exposure.'),
    'method', jsonb_build_array('Recorded injuries use the 1,545 reviewed dashboard injury rows.', 'Time-loss status uses final classification. Days lost use known time_loss_days only.'),
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
    'injury_type_families', analysis.injury_type_families_from_payload_v3(coalesce((select jsonb_agg(jsonb_build_object('dimension', dimension, 'code', code, 'label', label, 'setting', setting_code, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end, 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by dimension, setting_code, code) from profiles where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb)),
    'severity_distribution', coalesce((select jsonb_agg(jsonb_build_object('setting', 'all', 'key', severity_code, 'label', case severity_code when 'zero_days_medical_attention_only' then 'Medical attention' when 'one_day' then '1 day' when 'two_to_three_days' then '2-3 days' when 'four_to_seven_days' then '4-7 days' when 'eight_to_twenty_eight_days' then '8-28 days' when 'greater_than_twenty_eight_days' then '>28 days' else 'Unknown or censored' end, 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost) order by array_position(array['zero_days_medical_attention_only', 'one_day', 'two_to_three_days', 'four_to_seven_days', 'eight_to_twenty_eight_days', 'greater_than_twenty_eight_days', 'unknown_or_censored'], severity_code)) from severity where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'setting_split', coalesce((select jsonb_agg(jsonb_build_object('key', setting_code, 'label', initcap(setting_code), 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end, 'overall_incidence_per_1000h', analysis.rate_per_1000_v1(recorded_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code)) from setting_metrics where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'setting_metrics', coalesce((select jsonb_agg(jsonb_build_object('setting', setting_code, 'label', initcap(setting_code), 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost, 'exposure_hours', case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end, 'overall_incidence_per_1000h', analysis.rate_per_1000_v1(recorded_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, case setting_code when 'all' then coverage.total_hours when 'match' then coverage.match_hours when 'training' then coverage.training_hours end), 'mean_severity_days', days_lost / nullif(known_duration_time_loss_injuries, 0)) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code)) from setting_metrics where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'contact_distribution', coalesce((select jsonb_agg(jsonb_build_object('key', contact_context, 'label', contact_label, 'setting', setting_code, 'recorded_injuries', recorded_injuries, 'time_loss_injuries', time_loss_injuries) order by array_position(array['all', 'match', 'training', 'unknown'], setting_code), array_position(array['contact', 'non_contact', 'unknown'], contact_context)) from contact where curated_build_id = active.curated_build_id and team_key = active.team_key), '[]'::jsonb),
    'prior_season', jsonb_build_object('season', '2024-25', 'status', 'frozen', 'note', 'Prior season remains frozen.'),
    'limitations', jsonb_build_array('V3 injury successor and Welsh exact-date fixture correction are bound to private immutable evidence.') || case when coverage.temporary_estimate then jsonb_build_array('Season exposure hours are a temporary mean of the other 14 source-backed team totals, not submitted exposure.', 'Monthly exposure, rates and distance are unavailable because no source rows support them.') else '[]'::jsonb end
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

revoke all on analysis.urc_2025_26_welsh_fixture_candidate_material_v3
  from public, anon, authenticated, web_reader;

create table analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture (
  snapshot_version text not null check (snapshot_version = '20260831121000'),
  active_state_sha256 text not null check (active_state_sha256 ~ '^[0-9a-f]{64}$'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  team_key text not null references reporting.teams(team_key),
  season text not null check (season = '2025-26'),
  curated_build_id uuid not null references curated.builds(id),
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
    cohort_view_version = 'injury_lineage_2025-26_2026-08-31_v3'
  ),
  cohort_evidence_sha256 text not null check (
    cohort_evidence_sha256 =
      'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450'
  ),
  injury_lineage_version_id uuid not null
    references lineage.injury_master_versions_v3(id),
  injury_lineage_snapshot_version text not null check (
    injury_lineage_snapshot_version = '20260831121000'
  ),
  injury_lineage_member_sha256 text not null check (
    injury_lineage_member_sha256 ~ '^[0-9a-f]{64}$'
  ),
  dashboard jsonb not null check (jsonb_typeof(dashboard) = 'object'),
  created_at timestamptz not null default now(),
  primary key (snapshot_version, team_key),
  unique (snapshot_version, curated_build_id),
  unique (snapshot_version, team_key, injury_lineage_member_sha256),
  check (payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard))
);

alter table analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture
  enable row level security;
revoke all on analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture
  from public, anon, authenticated, web_reader;

create trigger urc_2025_26_welsh_fixture_candidate_immutable
before update or delete
on analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture
for each row execute function
  analysis.reject_urc_2025_26_injury_successor_candidate_mutation();

insert into analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture (
  snapshot_version, active_state_sha256, payload_sha256,
  team_key, season, curated_build_id, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  injury_lineage_version_id, injury_lineage_snapshot_version,
  injury_lineage_member_sha256, dashboard
)
select '20260831121000', predecessor.active_state_sha256,
  reporting.canonical_jsonb_sha256_v1(chosen.dashboard),
  material.team_key, material.season, material.curated_build_id,
  material.analysis_version, material.classification_view_version,
  material.classification_evidence_sha256,
  material.cohort_view_version, material.cohort_evidence_sha256,
  material.injury_lineage_version_id,
  material.injury_lineage_snapshot_version,
  case when material.team_key in ('cardiff', 'dragons')
    then corrected_members.member_sha256
    else predecessor.injury_lineage_member_sha256
  end,
  chosen.dashboard
from analysis.urc_2025_26_welsh_fixture_candidate_material_v3 material
join analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract predecessor
  using (team_key, season, curated_build_id)
cross join lateral (
  select case when material.team_key in ('cardiff', 'dragons')
    then material.dashboard else predecessor.dashboard end as dashboard
) chosen
left join lateral (
  select reporting.canonical_jsonb_sha256_v1(coalesce(jsonb_agg(
    jsonb_build_object(
      'source_row', corrected.source_row,
      'row_sha256', master.final_master_row_sha256,
      'final_classification', master.final_classification,
      'time_loss_days', master.time_loss_days
    ) order by corrected.source_row
  ), '[]'::jsonb)) as member_sha256
  from analysis.urc_2025_26_injury_fixture_corrected_rows_v2 corrected
  join lineage.injury_master_rows_v3 master
    on master.version_id = material.injury_lineage_version_id
   and master.team_key = corrected.team_key
   and master.source_row = corrected.source_row
  where corrected.team_key = material.team_key
) corrected_members on material.team_key in ('cardiff', 'dragons')
where predecessor.snapshot_version = '20260831101000'
  and predecessor.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(predecessor.dashboard);

alter table reporting.team_release_payloads_v6
  drop constraint team_release_payloads_v6_cohort_view_version_check,
  add constraint team_release_payloads_v6_cohort_view_version_check check (
    cohort_view_version in (
      'analysis_window_2025-26_2026-08-15_v1',
      'injury_lineage_2025-26_2026-08-30_v2',
      'injury_lineage_2025-26_2026-08-31_v3'
    )
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_cohort_view_version_check,
  add constraint league_release_context_v2_cohort_view_version_check check (
    cohort_view_version in (
      'v2',
      'season_bound_2026-07-20_v1',
      'lineage_2024-25_2026-07-24_v1',
      'analysis_window_2024-25_2026-07-25_v1',
      'analysis_window_2024-25_2026-08-30_v2',
      'analysis_window_2025-26_2026-08-15_v1',
      'injury_lineage_2025-26_2026-08-30_v2',
      'injury_lineage_2025-26_2026-08-31_v3'
    )
  );

alter table reporting.team_release_injury_lineage_v1
  drop constraint team_release_injury_lineage_v1_candidate_snapshot_version_check,
  add constraint team_release_injury_lineage_v1_candidate_snapshot_version_check check (
    candidate_snapshot_version in (
      '20260830170000', '20260831100000', '20260831101000',
      '20260831121000'
    )
  );

create table analysis.accepted_release_contracts_v3 (
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
  required_scientific_relations jsonb not null,
  metric_contract jsonb not null,
  evidence_sha256 text not null check (
    evidence_sha256 =
      'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450'
  ),
  evidence_locator text not null check (
    evidence_locator =
      'docs/evidence/urc_2025_26_welsh_fixture_alias_exact_date_correction.json'
  ),
  created_at timestamptz not null default now(),
  unique (season, analysis_version, classification_view_version,
    cohort_view_version)
);

alter table analysis.accepted_release_contracts_v3 enable row level security;
revoke all on analysis.accepted_release_contracts_v3
  from public, anon, authenticated, web_reader;

create trigger accepted_release_contracts_v3_immutable
before update or delete on analysis.accepted_release_contracts_v3
for each row execute function analysis.reject_accepted_release_contract_mutation();

insert into analysis.accepted_release_contracts_v3 (
  season, analysis_version, classification_view_version,
  cohort_view_version, team_candidate_relation,
  league_team_candidate_relation, league_candidate_relation,
  required_scientific_relations, metric_contract,
  evidence_sha256, evidence_locator
) values (
  '2025-26', 'v6',
  'reporting_classification_2025-26_2026-08-31_v3',
  'injury_lineage_2025-26_2026-08-31_v3',
  'analysis.team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_dashboard_release_candidates_analysis_window_v6',
  '[
    "analysis.accepted_urc_fixtures_v6",
    "analysis.urc_2025_26_injury_fixture_corrected_rows_v2",
    "analysis.urc_2025_26_injury_fixture_corrected_cohort_v2",
    "analysis.urc_2025_26_injury_fixture_corrected_league_monthly_v2",
    "analysis.urc_2025_26_injury_fixture_corrected_league_summary_v2",
    "analysis.urc_2025_26_reporting_key_rows_v3",
    "analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture"
  ]'::jsonb,
  '{
    "recorded_injuries":"count(final classified eligible injury rows, including exact-date fixture corrections)",
    "time_loss_injuries":"count(final classification = Time Loss)",
    "overall_incidence":"pooled recorded injuries / pooled exposure hours * 1000",
    "incidence":"pooled final Time Loss injuries / pooled exposure hours * 1000",
    "mean_severity":"known-duration Time Loss days lost / known-duration Time Loss injuries",
    "burden":"known-duration Time Loss days lost / pooled exposure hours * 1000"
  }'::jsonb,
  'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
  'docs/evidence/urc_2025_26_welsh_fixture_alias_exact_date_correction.json'
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
    from analysis.accepted_release_contracts_v3 contract
    where contract.season = requested_season
      and contract.analysis_version = requested_analysis_version
      and contract.classification_view_version =
        requested_classification_view_version
      and contract.cohort_view_version = requested_cohort_view_version
      and to_regclass(contract.team_candidate_relation) is not null
      and to_regclass(contract.league_team_candidate_relation) is not null
      and to_regclass(contract.league_candidate_relation) is not null
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

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with active_builds as materialized (
  select team_key, season, curated_build_id
  from analysis.analysis_window_active_builds_v6
  where season = '2025-26'
), build_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key,
    'curated_build_id', curated_build_id::text
  ) order by team_key) as builds
  from active_builds
  having count(*) = 16 and count(distinct team_key) = 16
), placeholder_state as (
  select jsonb_agg(jsonb_build_object(
    'team_key', team_key,
    'event_id', event_id,
    'method', method,
    'estimated_total_hours', estimated_total_hours,
    'evidence_sha256', evidence_sha256
  ) order by team_key) as placeholders
  from analysis.active_exposure_placeholders_v1
  where season = '2025-26'
  having count(*) = 2
    and count(*) filter (where team_key in ('benetton', 'edinburgh')) = 2
), active_state as (
  select reporting.canonical_jsonb_sha256_v1(jsonb_build_object(
    'successor', to_jsonb(evidence),
    'builds', build_state.builds,
    'placeholders', placeholder_state.placeholders
  )) as active_state_sha256
  from build_state
  cross join placeholder_state
  cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
)
select snapshot.team_key, snapshot.season,
  null::uuid as team_release_id, snapshot.curated_build_id,
  snapshot.analysis_version, snapshot.classification_view_version,
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
  snapshot.injury_lineage_snapshot_version,
  snapshot.injury_lineage_member_sha256
from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture snapshot
join active_state
  on active_state.active_state_sha256 = snapshot.active_state_sha256
where snapshot.snapshot_version = '20260831121000'
  and snapshot.payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.team_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;

do $$
declare
  changed_teams text[];
begin
  select array_agg(candidate.team_key order by candidate.team_key)
  into changed_teams
  from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
  join analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract predecessor
    using (team_key, season, curated_build_id)
  where candidate.dashboard <> predecessor.dashboard;

  if (select count(*) from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture) <> 16
    or changed_teams <> array['cardiff', 'dragons']::text[]
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
      join analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract predecessor
        using (team_key, season, curated_build_id)
      where candidate.team_key not in ('cardiff', 'dragons')
        and candidate.dashboard <> predecessor.dashboard
    )
    or (select count(*) from analysis.urc_2025_26_injury_fixture_corrected_rows_v2) <> 1545
    or (select count(*) from analysis.urc_2025_26_injury_fixture_corrected_rows_v2 where is_time_loss) <> 938
    or (select count(*) from analysis.urc_2025_26_injury_fixture_corrected_rows_v2 where is_time_loss and days_lost is not null) <> 782
    or (select coalesce(sum(days_lost), 0) from analysis.urc_2025_26_injury_fixture_corrected_rows_v2 where is_time_loss) <> 20665
    or not exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
      cross join lateral jsonb_array_elements(candidate.dashboard -> 'setting_metrics') setting
      where candidate.team_key = 'cardiff'
        and setting ->> 'setting' = 'match'
        and (setting ->> 'recorded_injuries')::integer = 19
        and (setting ->> 'time_loss_injuries')::integer = 19
        and (setting ->> 'days_lost')::numeric = 460
        and (setting ->> 'exposure_hours')::numeric = 380
        and (setting ->> 'incidence_per_1000h')::numeric =
          analysis.rate_per_1000_v1(19, 380)
    )
    or not exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
      cross join lateral jsonb_array_elements(candidate.dashboard -> 'setting_metrics') setting
      where candidate.team_key = 'dragons'
        and setting ->> 'setting' = 'match'
        and (setting ->> 'recorded_injuries')::integer = 42
        and (setting ->> 'time_loss_injuries')::integer = 42
        and (setting ->> 'days_lost')::numeric = 1158
        and (setting ->> 'exposure_hours')::numeric = 360
        and (setting ->> 'incidence_per_1000h')::numeric =
          analysis.rate_per_1000_v1(42, 360)
    )
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
      cross join lateral jsonb_array_elements(candidate.dashboard -> 'injury_type_families') family
      where family ->> 'mapping_version' <> 'injury_type_family_2026-07-21_v1'
        or family ->> 'code' = 'unmapped_review'
    )
    or exists (
      select 1
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
      where candidate.payload_sha256 <>
          reporting.canonical_jsonb_sha256_v1(candidate.dashboard)
        or jsonb_array_length(candidate.dashboard -> 'headline') <> 7
    )
    or not analysis.release_contract_candidates_available_v1(
      '2025-26', 'v6',
      'reporting_classification_2025-26_2026-08-31_v3',
      'injury_lineage_2025-26_2026-08-31_v3'
    )
    or has_table_privilege(
      'web_reader',
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture',
      'select'
    )
    or has_table_privilege(
      'web_reader', 'analysis.accepted_release_contracts_v3', 'select'
    )
  then
    raise exception 'Welsh exact-date team candidate successor failed its accepted boundary';
  end if;
end;
$$;
