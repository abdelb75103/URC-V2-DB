-- V7 monthly payloads use both established label formats across seasons.

create or replace view reporting.latest_team_dashboard_v8
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
   and (item.value ->> 'month') in (
     to_char(display.month_start, 'Mon YYYY'),
     to_char(display.month_start, 'YYYY-MM')
   )
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

create or replace view reporting.latest_league_dashboard_v8
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
   and (item.value ->> 'month') in (
     to_char(display.month_start, 'Mon YYYY'),
     to_char(display.month_start, 'YYYY-MM')
   )
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
