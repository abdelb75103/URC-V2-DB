-- V5 candidate-query performance completion.
-- Versioned successor only: no data mutation, cohort change, or release-tuple change.
-- The payload definitions materialise shared analytical components once per query.

create or replace view analysis.team_dashboard_payload_analysis_window_v5
with (security_invoker = true) as
with effective_profiles_data as materialized (
  select *
  from analysis.analysis_window_effective_injury_profiles_v5
), diagnosis_data as materialized (
  select *
  from analysis.analysis_window_diagnosis_profiles_v5
), setting_data as materialized (
  select *
  from analysis.analysis_window_setting_split_v5
), monthly_data as materialized (
  select *
  from analysis.analysis_window_monthly_v5
), severity_data as materialized (
  select *
  from analysis.analysis_window_severity_distribution_v5
), summary_data as materialized (
  select *
  from analysis.analysis_window_team_summary_v5
), exposure_data as materialized (
  select *
  from analysis.exposure_hours_by_build_analysis_window_v5
), body as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from effective_profiles_data p
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), types as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from effective_profiles_data p
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), profile_rows as (
  select p.curated_build_id, p.team_key, p.season, p.dimension,
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from effective_profiles_data p
  union all
  select p.curated_build_id, p.team_key, p.season, 'diagnosis',
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from diagnosis_data p
), profiles as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code) as docs
  from profile_rows p
  group by p.curated_build_id, p.team_key, p.season
)
select m.team_key, m.season, m.team_release_id, m.curated_build_id,
  rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', m.generated_at,
    'team', d.team,
    'season', m.season,
    'analysis_window', jsonb_build_object(
      'start', w.season_start,
      'end', w.season_end,
      'basis', 'Immutable 2024-25 reporting window with effective row-level exposure eligibility.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.',
      'Match exposure = registered fixtures in the reporting window × 15 players × 80 minutes / 60 per team.',
      'Training exposure = effective included exposure in the reporting window minus fixture-derived match exposure.',
      'IOC-aligned body-location and tissue/pathology categories use the accepted mappings.',
      'Injury rows and values are restated from the reviewed 2024-25 master workbook and its ordered decision ledger.'
    ),
    'coverage',
      (coalesce(d.coverage, '{}'::jsonb) - 'injury_cohort_filters')
      || jsonb_build_object(
        'hours', e.total_hours,
        'match_hours', e.match_hours,
        'training_hours', e.training_hours,
        'exposure_grain', e.exposure_grain,
        'included_exposure_status', 'included',
        'analysis_window_start', w.season_start,
        'analysis_window_end', w.season_end
      ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', s.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', s.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(s.time_loss_injuries, e.total_hours),
        'unit', 'per 1,000 player-hours',
        'numerator', s.time_loss_injuries,
        'denominator', e.total_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', s.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', s.days_lost, 'denominator', s.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', s.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(s.days_lost, e.total_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', s.days_lost, 'denominator', e.total_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from setting_data x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from setting_data x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from monthly_data x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from severity_data x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'prior_season', d.prior_season,
    'limitations', jsonb_build_array(
      'The immutable reporting window, rather than team-specific exposure coverage, defines numerator and denominator eligibility.',
      'Historical exposure state is retained; V5 exposes effective eligibility without mutating curated rows.',
      'Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.',
      'Unknown-setting injuries are included in overall metrics but have no match/training rate.',
      'Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.',
      'The reviewed master-plus-ledger lineage is the authoritative injury record.'
    )
  ) as dashboard
from analysis.league_member_releases_v2 m
join reporting.latest_team_dashboard d
  on d.release_id = m.team_release_id
 and d.team_key = m.team_key
 and d.season = m.season
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
 and w.season = m.season
join analysis.accepted_analysis_window_cohort_rules_v5 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
join summary_data s
  on s.curated_build_id = m.curated_build_id
 and s.team_key = m.team_key
 and s.season = m.season
join exposure_data e
  on e.curated_build_id = m.curated_build_id
 and e.team_key = m.team_key
 and e.season = m.season
left join body
  on body.curated_build_id = m.curated_build_id
 and body.team_key = m.team_key and body.season = m.season
left join types
  on types.curated_build_id = m.curated_build_id
 and types.team_key = m.team_key and types.season = m.season
left join profiles
  on profiles.curated_build_id = m.curated_build_id
 and profiles.team_key = m.team_key and profiles.season = m.season;

create or replace view analysis.league_dashboard_payload_analysis_window_v5
with (security_invoker = true) as
with effective_profiles_data as materialized (
  select *
  from analysis.analysis_window_league_effective_injury_profiles_v5
), diagnosis_data as materialized (
  select *
  from analysis.analysis_window_league_diagnosis_profiles_v5
), setting_data as materialized (
  select *
  from analysis.analysis_window_league_setting_split_v5
), monthly_data as materialized (
  select *
  from analysis.analysis_window_league_monthly_v5
), severity_data as materialized (
  select *
  from analysis.analysis_window_league_severity_distribution_v5
), summary_data as materialized (
  select *
  from analysis.analysis_window_league_summary_v5
), body as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from effective_profiles_data p
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.season
), types as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from effective_profiles_data p
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.season
), profile_rows as (
  select p.season, p.dimension, p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from effective_profiles_data p
  union all
  select p.season, 'diagnosis', p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from diagnosis_data p
), profiles as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code) as docs
  from profile_rows p
  group by p.season
)
select h.season,
  rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', (
      select max(m.generated_at)
      from analysis.league_member_releases_v2 m
      where m.season = h.season
    ),
    'team', 'URC Overall',
    'season', h.season,
    'analysis_window', jsonb_build_object(
      'start', w.season_start,
      'end', w.season_end,
      'basis', 'Immutable 2024-25 reporting window with effective row-level exposure eligibility.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.',
      'Match exposure = registered fixtures in the reporting window × 15 players × 80 minutes / 60 per team.',
      'Training exposure = effective included exposure in the reporting window minus fixture-derived match exposure.',
      'IOC-aligned body-location and tissue/pathology categories use the accepted mappings.',
      'Injury rows and values are restated from the reviewed 2024-25 master workbook and its ordered decision ledger.'
    ),
    'coverage', coalesce((
      select b.dashboard -> 'coverage'
      from analysis.league_dashboard_payload_v2 b
      where b.season = h.season
    ), '{}'::jsonb) || jsonb_build_object(
      'hours', h.exposure_hours,
      'match_hours', h.match_exposure_hours,
      'training_hours', h.training_exposure_hours,
      'teams_included', (
        select count(*)
        from analysis.league_member_releases_v2 m
        where m.season = h.season
      ),
      'included_exposure_status', 'included',
      'analysis_window_start', w.season_start,
      'analysis_window_end', w.season_end
    ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', h.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', h.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(
          h.time_loss_injuries, h.exposure_hours),
        'unit', 'per 1,000 player-hours',
        'numerator', h.time_loss_injuries,
        'denominator', h.exposure_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', h.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', h.days_lost, 'denominator', h.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', h.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(h.days_lost, h.exposure_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', h.days_lost, 'denominator', h.exposure_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from setting_data x
      where x.season = h.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from setting_data x
      where x.season = h.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from monthly_data x
      where x.season = h.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from severity_data x
      where x.season = h.season
    ), '[]'::jsonb),
    'prior_season', jsonb_build_object(
      'season', '2023-24',
      'status', 'pending',
      'note', 'No prior-season league injury and exposure denominator pair has passed the V2 workflow.'
    ),
    'limitations', jsonb_build_array(
      'The immutable reporting window, rather than team-specific exposure coverage, defines numerator and denominator eligibility.',
      'Historical exposure state is retained; V5 exposes effective eligibility without mutating curated rows.',
      'Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.',
      'Unknown-setting injuries are included in overall metrics but have no match/training rate.',
      'Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.',
      'The reviewed master-plus-ledger lineage is the authoritative injury record.'
    )
  ) as dashboard
from summary_data h
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
 and w.season = h.season
join analysis.accepted_analysis_window_cohort_rules_v5 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
left join body on body.season = h.season
left join types on types.season = h.season
left join profiles on profiles.season = h.season;

comment on view analysis.team_dashboard_payload_analysis_window_v5 is
  'V5 team payload. Shared analytical components are materialised once per candidate query.';
comment on view analysis.league_dashboard_payload_analysis_window_v5 is
  'V5 league payload. Shared analytical components are materialised once per candidate query.';

