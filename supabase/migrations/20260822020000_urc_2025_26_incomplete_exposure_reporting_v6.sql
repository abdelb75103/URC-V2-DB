-- Additive Year 2 V6 successor for incomplete submitted exposure. It leaves
-- every 2024-25 relation and every V6 release storage/release view untouched.
-- Evidence: docs/evidence/urc_2025_26_incomplete_exposure_reporting_v6.json
-- SHA-256: b6fae7ce7e4609000337c29d7965e99809da3733b126522a1faabf600fdcc23c

create view analysis.accepted_urc_2025_26_incomplete_exposure_reporting_evidence_v6
with (security_invoker = true) as
select
  'docs/evidence/urc_2025_26_incomplete_exposure_reporting_v6.json'::text
    as evidence_locator,
  'b6fae7ce7e4609000337c29d7965e99809da3733b126522a1faabf600fdcc23c'::text
    as evidence_sha256;

-- The existing V6 view intentionally contains only included exposure rows.
-- This companion view keeps its source-backed aggregate separate from the
-- grain evidence, which may be available on curated rows that were excluded.
create view analysis.analysis_window_team_exposure_completeness_v6
with (security_invoker = true) as
with source_backed as (
  select member.curated_build_id, member.team_key, member.season,
    coalesce(sum(exposure.minutes_clean), 0) / 60 as source_backed_hours,
    coalesce(sum(exposure.distance_m_clean), 0) / 1000 as source_backed_distance_km
  from analysis.analysis_window_active_builds_v6 member
  left join analysis.analysis_window_team_exposure_v6 exposure
    using (curated_build_id, team_key, season)
  group by member.curated_build_id, member.team_key, member.season
), grain_metadata as (
  select member.curated_build_id, member.team_key, member.season,
    case
      when count(distinct exposure.grain) filter (
        where exposure.grain in ('session', 'weekly')
      ) = 1 then min(exposure.grain) filter (
        where exposure.grain in ('session', 'weekly')
      )
      else 'unknown'
    end as exposure_grain
  from analysis.analysis_window_active_builds_v6 member
  left join curated.exposure exposure
    on exposure.curated_build_id = member.curated_build_id
   and exposure.team_key = member.team_key
   and exposure.season = member.season
  group by member.curated_build_id, member.team_key, member.season
), fixtures as (
  select member.team_key, member.season, count(*) * 20.0 as match_hours
  from analysis.analysis_window_active_builds_v6 member
  join analysis.accepted_urc_fixtures_v6 fixture
    on fixture.season = member.season
   and (fixture.home_team_key = member.team_key or fixture.away_team_key = member.team_key)
  join analysis.reporting_season_windows_v3 season_window
    on season_window.cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
   and season_window.season = fixture.season
  where fixture.match_date between season_window.season_start and season_window.season_end
  group by member.team_key, member.season
)
select source_backed.curated_build_id, source_backed.team_key, source_backed.season,
  source_backed.source_backed_hours,
  fixtures.match_hours,
  source_backed.source_backed_hours >= fixtures.match_hours as denominator_available,
  case when source_backed.source_backed_hours >= fixtures.match_hours
    then source_backed.source_backed_hours else null::numeric end as total_hours,
  case when source_backed.source_backed_hours >= fixtures.match_hours
    then source_backed.source_backed_hours - fixtures.match_hours else null::numeric end as training_hours,
  case when source_backed.source_backed_hours >= fixtures.match_hours
    then source_backed.source_backed_distance_km else null::numeric end as distance_km,
  grain_metadata.exposure_grain
from source_backed
join fixtures using (team_key, season)
join grain_metadata using (curated_build_id, team_key, season);

-- Keep the original V6 relation name, column order and types. The sole
-- behavioural change is that every active build now has a row. An unavailable
-- denominator is represented by null, never a substituted value.
create or replace view analysis.analysis_window_team_hours_v6
with (security_invoker = true) as
select curated_build_id, team_key, season, total_hours, match_hours,
  training_hours, distance_km, exposure_grain
from analysis.analysis_window_team_exposure_completeness_v6;

create or replace view analysis.analysis_window_monthly_v6
with (security_invoker = true) as
with exposure as (
  select curated_build_id, team_key, season,
    date_trunc('month', period_start)::date as month_start,
    sum(minutes_clean) / 60 as exposure_hours,
    sum(distance_m_clean) / 1000 as distance_km
  from analysis.analysis_window_team_exposure_v6
  group by curated_build_id, team_key, season, date_trunc('month', period_start)
), injuries as (
  select curated_build_id, team_key, season,
    date_trunc('month', date_injured)::date as month_start,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from analysis.analysis_window_injury_cohort_v6
  where cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
    and date_injured is not null
  group by curated_build_id, team_key, season, date_trunc('month', date_injured)
), months as (
  select curated_build_id, team_key, season, month_start from exposure
  union
  select curated_build_id, team_key, season, month_start from injuries
)
select months.curated_build_id, months.team_key, months.season,
  months.month_start, to_char(months.month_start, 'Mon YYYY') as month_label,
  case when hours.total_hours is not null and exposure.exposure_hours is not null
    then exposure.exposure_hours else null::numeric end as exposure_hours,
  case when hours.total_hours is not null and exposure.exposure_hours is not null
    then exposure.distance_km else null::numeric end as distance_km,
  coalesce(injuries.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(injuries.days_lost, 0) as days_lost,
  case when hours.total_hours is not null and exposure.exposure_hours is not null
    then analysis.rate_per_1000_v1(coalesce(injuries.time_loss_injuries, 0), exposure.exposure_hours)
    else null::numeric end as incidence_per_1000h,
  case when hours.total_hours is not null and exposure.exposure_hours is not null
    then analysis.rate_per_1000_v1(coalesce(injuries.days_lost, 0), exposure.exposure_hours)
    else null::numeric end as burden_per_1000h
from months
join analysis.analysis_window_team_hours_v6 hours
  using (curated_build_id, team_key, season)
left join exposure using (curated_build_id, team_key, season, month_start)
left join injuries using (curated_build_id, team_key, season, month_start);

create or replace view analysis.analysis_window_league_monthly_v6
with (security_invoker = true) as
with month_domain as (
  select distinct season, month_start
  from analysis.analysis_window_monthly_v6
), team_months as (
  select hours.curated_build_id, hours.team_key, hours.season,
    month_domain.month_start,
    hours.total_hours is not null as team_denominator_available,
    monthly.exposure_hours, monthly.distance_km,
    coalesce(monthly.time_loss_injuries, 0) as time_loss_injuries,
    coalesce(monthly.days_lost, 0) as days_lost
  from analysis.analysis_window_team_hours_v6 hours
  join month_domain on month_domain.season = hours.season
  left join analysis.analysis_window_monthly_v6 monthly
    on monthly.curated_build_id = hours.curated_build_id
   and monthly.team_key = hours.team_key
   and monthly.season = hours.season
   and monthly.month_start = month_domain.month_start
), aggregated as (
  select season, month_start,
    count(*) filter (where exposure_hours is not null) as source_backed_team_months,
    bool_and(team_denominator_available) as all_team_denominators_available,
    sum(exposure_hours) as source_backed_exposure_hours,
    sum(distance_km) as source_backed_distance_km,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost
  from team_months
  group by season, month_start
)
select season, month_start, to_char(month_start, 'Mon YYYY') as month_label,
  case when all_team_denominators_available and source_backed_team_months = 16
    then source_backed_exposure_hours else null::numeric end as exposure_hours,
  case when all_team_denominators_available and source_backed_team_months = 16
    then source_backed_distance_km else null::numeric end as distance_km,
  time_loss_injuries, days_lost,
  case when all_team_denominators_available and source_backed_team_months = 16
    then analysis.rate_per_1000_v1(time_loss_injuries, source_backed_exposure_hours)
    else null::numeric end as incidence_per_1000h,
  case when all_team_denominators_available and source_backed_team_months = 16
    then analysis.rate_per_1000_v1(days_lost, source_backed_exposure_hours)
    else null::numeric end as burden_per_1000h
from aggregated;

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
    count(*) filter (where hours.total_hours is not null) as complete_team_count,
    sum(hours.total_hours) as source_backed_exposure_hours,
    sum(hours.match_hours) as match_exposure_hours,
    sum(hours.training_hours) as source_backed_training_hours
  from analysis.analysis_window_team_summary_v6 summary
  join analysis.analysis_window_team_hours_v6 hours
    using (curated_build_id, team_key, season)
  group by summary.season
)
select season, recorded_injuries, time_loss_injuries, days_lost,
  mean_severity_days, median_severity_days,
  case when complete_team_count = 16 then source_backed_exposure_hours
    else null::numeric end as exposure_hours,
  match_exposure_hours,
  case when complete_team_count = 16 then source_backed_training_hours
    else null::numeric end as training_exposure_hours
from aggregated;

-- When a team lacks a season denominator, setting and profile figures retain
-- their counts and severity but never borrow fixture hours for a rate.
create or replace view analysis.analysis_window_profiles_v6
with (security_invoker = true) as
select profile.curated_build_id, profile.team_key, profile.season,
  profile.setting_code, profile.dimension, profile.code, profile.label,
  count(*) as time_loss_injuries, sum(profile.days_lost) as days_lost,
  case when hours.total_hours is null then null::numeric
    when profile.setting_code = 'all' then hours.total_hours
    when profile.setting_code = 'match' then hours.match_hours
    when profile.setting_code = 'training' then hours.training_hours
    else null::numeric end as exposure_hours,
  case when hours.total_hours is null then null::numeric
    else analysis.rate_per_1000_v1(count(*), case profile.setting_code
      when 'all' then hours.total_hours
      when 'match' then hours.match_hours
      when 'training' then hours.training_hours
      else null::numeric end) end as incidence_per_1000h,
  case when hours.total_hours is null then null::numeric
    else analysis.rate_per_1000_v1(sum(profile.days_lost), case profile.setting_code
      when 'all' then hours.total_hours
      when 'match' then hours.match_hours
      when 'training' then hours.training_hours
      else null::numeric end) end as burden_per_1000h,
  sum(profile.days_lost) / nullif(count(*), 0) as mean_severity_days
from analysis.analysis_window_profile_rows_v6 profile
join analysis.analysis_window_team_hours_v6 hours
  using (curated_build_id, team_key, season)
group by profile.curated_build_id, profile.team_key, profile.season,
  profile.setting_code, profile.dimension, profile.code, profile.label,
  hours.total_hours, hours.match_hours, hours.training_hours;

create or replace view analysis.analysis_window_setting_metrics_v6
with (security_invoker = true) as
with observed as (
  select curated_build_id, team_key, season, 'all'::text as setting_code,
    is_time_loss, days_lost
  from analysis.analysis_window_injury_cohort_v6
  union all
  select curated_build_id, team_key, season, setting_code, is_time_loss, days_lost
  from analysis.analysis_window_injury_cohort_v6
), grouped as (
  select curated_build_id, team_key, season, setting_code,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from observed
  group by curated_build_id, team_key, season, setting_code
), setting_domain(setting_code) as (
  values ('all'), ('match'), ('training'), ('unknown')
)
select hours.curated_build_id, hours.team_key, hours.season,
  setting_domain.setting_code,
  coalesce(grouped.time_loss_injuries, 0)::bigint as time_loss_injuries,
  coalesce(grouped.days_lost, 0) as days_lost,
  case when hours.total_hours is null then null::numeric
    when setting_domain.setting_code = 'all' then hours.total_hours
    when setting_domain.setting_code = 'match' then hours.match_hours
    when setting_domain.setting_code = 'training' then hours.training_hours
    else null::numeric end as exposure_hours
from analysis.analysis_window_team_hours_v6 hours
cross join setting_domain
left join grouped using (curated_build_id, team_key, season, setting_code);

create or replace view analysis.analysis_window_league_profiles_v6
with (security_invoker = true) as
with grouped as (
  select season, setting_code, dimension, code, label,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost
  from analysis.analysis_window_profiles_v6
  group by season, setting_code, dimension, code, label
)
select grouped.season, grouped.setting_code, grouped.dimension, grouped.code,
  grouped.label, grouped.time_loss_injuries, grouped.days_lost,
  case when summary.exposure_hours is null then null::numeric
    when grouped.setting_code = 'all' then summary.exposure_hours
    when grouped.setting_code = 'match' then summary.match_exposure_hours
    when grouped.setting_code = 'training' then summary.training_exposure_hours
    else null::numeric end as exposure_hours,
  case when summary.exposure_hours is null then null::numeric
    else analysis.rate_per_1000_v1(grouped.time_loss_injuries, case grouped.setting_code
      when 'all' then summary.exposure_hours
      when 'match' then summary.match_exposure_hours
      when 'training' then summary.training_exposure_hours
      else null::numeric end) end as incidence_per_1000h,
  case when summary.exposure_hours is null then null::numeric
    else analysis.rate_per_1000_v1(grouped.days_lost, case grouped.setting_code
      when 'all' then summary.exposure_hours
      when 'match' then summary.match_exposure_hours
      when 'training' then summary.training_exposure_hours
      else null::numeric end) end as burden_per_1000h,
  grouped.days_lost / nullif(grouped.time_loss_injuries, 0) as mean_severity_days
from grouped
join analysis.analysis_window_league_summary_v6 summary using (season);

create or replace view analysis.analysis_window_league_setting_metrics_v6
with (security_invoker = true) as
with grouped as (
  select season, setting_code,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost
  from analysis.analysis_window_setting_metrics_v6
  group by season, setting_code
)
select grouped.season, grouped.setting_code,
  grouped.time_loss_injuries, grouped.days_lost,
  case when summary.exposure_hours is null then null::numeric
    when grouped.setting_code = 'all' then summary.exposure_hours
    when grouped.setting_code = 'match' then summary.match_exposure_hours
    when grouped.setting_code = 'training' then summary.training_exposure_hours
    else null::numeric end as exposure_hours
from grouped
join analysis.analysis_window_league_summary_v6 summary using (season);

create or replace view analysis.team_dashboard_payload_analysis_window_v6
with (security_invoker = true) as
select member.team_key, member.season, null::uuid as team_release_id,
  member.curated_build_id, rules.classification_view_version,
  rules.classification_evidence_sha256, cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', member.generated_at,
    'team', roster.display_name,
    'season', member.season,
    'analysis_window', jsonb_build_object(
      'start', season_window.season_start,
      'end', season_window.season_end,
      'basis', 'Registered Year 2 reporting window.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in totals but excluded from monthly series.',
      'Curated IOC categories are carried forward; unsupported mappings remain Unknown.'
    ),
    'coverage', jsonb_build_object(
      'hours', hours.total_hours,
      'match_hours', hours.match_hours,
      'training_hours', hours.training_hours,
      'distance_km', hours.distance_km,
      'exposure_grain', hours.exposure_grain,
      'exposure_rows', (
        select count(*) from analysis.analysis_window_team_exposure_v6 exposure
        where exposure.curated_build_id = member.curated_build_id
      ),
      'exposed_players', (
        select count(distinct nullif(exposure.player_uid, 'Unknown'))
        from analysis.analysis_window_team_exposure_v6 exposure
        where exposure.curated_build_id = member.curated_build_id
      ),
      'weeks', (
        select count(distinct date_trunc('week', exposure.period_start))
        from analysis.analysis_window_team_exposure_v6 exposure
        where exposure.curated_build_id = member.curated_build_id
      ),
      'included_exposure_status', case when hours.total_hours is null
        then 'source_backed_denominator_unavailable_no_imputation'
        else 'source_backed_exposure_submitted_may_be_incomplete' end,
      'analysis_window_start', season_window.season_start,
      'analysis_window_end', season_window.season_end
    ),
    'headline', jsonb_build_array(
      jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', summary.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'),
      jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', summary.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'),
      jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(summary.time_loss_injuries, hours.total_hours),
        'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries,
        'denominator', hours.total_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity',
        'value', summary.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', summary.days_lost, 'denominator', summary.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'),
      jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity',
        'value', summary.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'),
      jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(summary.days_lost, hours.total_hours),
        'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost,
        'denominator', hours.total_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000')
    ),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', monthly.month_label,
        'exposure_hours', monthly.exposure_hours,
        'distance_km', monthly.distance_km,
        'time_loss_injuries', monthly.time_loss_injuries,
        'days_lost', monthly.days_lost,
        'incidence_per_1000h', monthly.incidence_per_1000h,
        'burden_per_1000h', monthly.burden_per_1000h
      ) order by monthly.month_start)
      from analysis.analysis_window_monthly_v6 monthly
      where monthly.curated_build_id = member.curated_build_id
        and monthly.team_key = member.team_key
        and monthly.season = member.season
    ), '[]'::jsonb),
    'body_locations', '[]'::jsonb,
    'injury_types', '[]'::jsonb,
    'injury_profiles', '[]'::jsonb,
    'injury_type_families', '[]'::jsonb,
    'severity_distribution', '[]'::jsonb,
    'setting_split', '[]'::jsonb,
    'setting_metrics', '[]'::jsonb,
    'contact_distribution', '[]'::jsonb,
    'prior_season', jsonb_build_object(
      'season', '2024-25', 'status', 'frozen',
      'note', 'Prior season remains frozen and is not recomputed by V6.'
    ),
    'limitations', case when hours.total_hours is null then jsonb_build_array(
      'Source-backed exposure denominator is unavailable. Exposure hours, distance, incidence and burden are null. No imputation was applied.'
    ) else jsonb_build_array(
      'Submitted exposure may be incomplete. Reported exposure values use source-backed rows only and no imputation was applied.'
    ) end
  ) as dashboard
from analysis.analysis_window_active_builds_v6 member
join analysis.analysis_window_team_summary_v6 summary
  using (curated_build_id, team_key, season)
join analysis.analysis_window_team_hours_v6 hours
  using (curated_build_id, team_key, season)
join reporting.teams roster on roster.team_key = member.team_key
join analysis.reporting_season_windows_v3 season_window
  on season_window.cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
 and season_window.season = member.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort
  on cohort.cohort_view_version = season_window.cohort_view_version
 and cohort.season = season_window.season
cross join analysis.accepted_year2_reporting_classification_rules_v6 rules
cross join analysis.accepted_urc_2025_26_incomplete_exposure_reporting_evidence_v6 evidence
where rules.classification_view_version = 'reporting_classification_2026-07-22_v2'
  and evidence.evidence_sha256 = 'b6fae7ce7e4609000337c29d7965e99809da3733b126522a1faabf600fdcc23c';

create or replace view analysis.league_dashboard_payload_analysis_window_v6
with (security_invoker = true) as
select summary.season, rules.classification_view_version,
  rules.classification_evidence_sha256, cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', (select max(generated_at) from analysis.analysis_window_active_builds_v6),
    'team', 'URC Overall',
    'season', summary.season,
    'analysis_window', jsonb_build_object(
      'start', season_window.season_start,
      'end', season_window.season_end,
      'basis', 'Registered Year 2 reporting window.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in totals but excluded from monthly series.'
    ),
    'coverage', jsonb_build_object(
      'hours', summary.exposure_hours,
      'match_hours', summary.match_exposure_hours,
      'training_hours', summary.training_exposure_hours,
      'teams_included', 16,
      'distance_km', case when summary.exposure_hours is null then null::numeric else (
        select sum(hours.distance_km)
        from analysis.analysis_window_team_hours_v6 hours
        where hours.season = summary.season
      ) end,
      'exposure_rows', (select count(*) from analysis.analysis_window_team_exposure_v6),
      'exposed_players', (
        select count(distinct nullif(exposure.player_uid, 'Unknown'))
        from analysis.analysis_window_team_exposure_v6 exposure
      ),
      'weeks', (
        select count(distinct date_trunc('week', exposure.period_start))
        from analysis.analysis_window_team_exposure_v6 exposure
      ),
      'included_exposure_status', case when summary.exposure_hours is null
        then 'source_backed_denominators_incomplete_no_imputation'
        else 'source_backed_exposure_submitted_may_be_incomplete' end,
      'analysis_window_start', season_window.season_start,
      'analysis_window_end', season_window.season_end
    ),
    'headline', jsonb_build_array(
      jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', summary.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'),
      jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', summary.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'),
      jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(summary.time_loss_injuries, summary.exposure_hours),
        'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries,
        'denominator', summary.exposure_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity',
        'value', summary.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', summary.days_lost, 'denominator', summary.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'),
      jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity',
        'value', summary.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'),
      jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(summary.days_lost, summary.exposure_hours),
        'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost,
        'denominator', summary.exposure_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000')
    ),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', monthly.month_label,
        'exposure_hours', monthly.exposure_hours,
        'distance_km', monthly.distance_km,
        'time_loss_injuries', monthly.time_loss_injuries,
        'days_lost', monthly.days_lost,
        'incidence_per_1000h', monthly.incidence_per_1000h,
        'burden_per_1000h', monthly.burden_per_1000h
      ) order by monthly.month_start)
      from analysis.analysis_window_league_monthly_v6 monthly
      where monthly.season = summary.season
    ), '[]'::jsonb),
    'body_locations', '[]'::jsonb,
    'injury_types', '[]'::jsonb,
    'injury_profiles', '[]'::jsonb,
    'injury_type_families', '[]'::jsonb,
    'severity_distribution', '[]'::jsonb,
    'setting_split', '[]'::jsonb,
    'setting_metrics', '[]'::jsonb,
    'contact_distribution', '[]'::jsonb,
    'prior_season', jsonb_build_object(
      'season', '2024-25', 'status', 'frozen',
      'note', 'Prior season remains frozen and is not recomputed by V6.'
    ),
    'limitations', case when summary.exposure_hours is null then jsonb_build_array(
      'At least one source-backed team denominator is unavailable. League exposure hours, distance, incidence and burden are null. No imputation was applied.'
    ) else jsonb_build_array(
      'Submitted team exposure may be incomplete. Reported exposure values use source-backed rows only and no imputation was applied.'
    ) end
  ) as dashboard
from analysis.analysis_window_league_summary_v6 summary
join analysis.reporting_season_windows_v3 season_window
  on season_window.cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
 and season_window.season = summary.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort
  on cohort.cohort_view_version = season_window.cohort_view_version
 and cohort.season = season_window.season
cross join analysis.accepted_year2_reporting_classification_rules_v6 rules
cross join analysis.accepted_urc_2025_26_incomplete_exposure_reporting_evidence_v6 evidence
where rules.classification_view_version = 'reporting_classification_2026-07-22_v2'
  and evidence.evidence_sha256 = 'b6fae7ce7e4609000337c29d7965e99809da3733b126522a1faabf600fdcc23c';

do $$
begin
  if to_regclass('analysis.analysis_window_team_exposure_completeness_v6') is null
    or to_regclass('analysis.analysis_window_team_hours_v6') is null
    or to_regclass('analysis.analysis_window_monthly_v6') is null
    or to_regclass('analysis.analysis_window_league_monthly_v6') is null
    or to_regclass('analysis.analysis_window_league_summary_v6') is null
    or to_regclass('analysis.accepted_urc_2025_26_incomplete_exposure_reporting_evidence_v6') is null
  then
    raise exception 'URC 2025-26 incomplete exposure V6 successor objects are incomplete';
  end if;
end $$;
