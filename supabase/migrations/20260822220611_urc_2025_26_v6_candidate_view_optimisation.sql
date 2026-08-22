-- Performance-only successor. The filtered MATERIALIZED CTEs evaluate each
-- repeated V6 aggregate relation once per selected team or league season.
-- Output columns, JSON keys, values and ordering remain unchanged.

create or replace view analysis.team_dashboard_payload_analysis_window_v6_enriched
with (security_invoker = true) as
select base.team_key, base.season, base.team_release_id, base.curated_build_id,
  base.classification_view_version, base.classification_evidence_sha256,
  base.cohort_view_version, base.cohort_evidence_sha256,
  base.dashboard || sections.dashboard_sections || sections.family_section as dashboard
from analysis.team_dashboard_payload_analysis_window_v6 base
cross join lateral (
  with profiles as materialized (
    select *
    from analysis.analysis_window_profiles_v6
    where curated_build_id = base.curated_build_id
      and team_key = base.team_key
      and season = base.season
  ), severity as materialized (
    select *
    from analysis.analysis_window_severity_v6
    where curated_build_id = base.curated_build_id
      and team_key = base.team_key
      and season = base.season
  ), setting_metrics as materialized (
    select *
    from analysis.analysis_window_setting_metrics_v6
    where curated_build_id = base.curated_build_id
      and team_key = base.team_key
      and season = base.season
  ), contact_distribution as materialized (
    select *
    from analysis.analysis_window_contact_distribution_v6
    where curated_build_id = base.curated_build_id
      and team_key = base.team_key
      and season = base.season
  )
  select jsonb_build_object(
    'body_locations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', code, 'label', label,
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours,
        'incidence_per_1000h', incidence_per_1000h,
        'burden_per_1000h', burden_per_1000h,
        'mean_severity_days', mean_severity_days
      ) order by code)
      from profiles
      where dimension = 'body_location' and setting_code = 'all'
    ), '[]'::jsonb),
    'injury_types', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', code, 'label', label,
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours,
        'incidence_per_1000h', incidence_per_1000h,
        'burden_per_1000h', burden_per_1000h,
        'mean_severity_days', mean_severity_days
      ) order by time_loss_injuries desc, code)
      from profiles
      where dimension = 'injury_type' and setting_code = 'all'
    ), '[]'::jsonb),
    'injury_profiles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dimension', dimension, 'code', code, 'label', label,
        'setting', setting_code, 'time_loss_injuries', time_loss_injuries,
        'days_lost', days_lost, 'exposure_hours', exposure_hours,
        'incidence_per_1000h', incidence_per_1000h,
        'burden_per_1000h', burden_per_1000h,
        'mean_severity_days', mean_severity_days
      ) order by dimension, setting_code, code)
      from profiles
    ), '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', severity_code,
        'label', initcap(replace(severity_code, '_', ' ')),
        'recorded_injuries', recorded_injuries,
        'time_loss_injuries', time_loss_injuries,
        'days_lost', days_lost
      ) order by severity_code)
      from severity
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', setting_code, 'label', initcap(setting_code),
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours,
        'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, exposure_hours),
        'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
        'mean_severity_days', days_lost / nullif(time_loss_injuries, 0)
      ) order by setting_code)
      from setting_metrics
    ), '[]'::jsonb),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', setting_code, 'label', initcap(setting_code),
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours
      ) order by setting_code)
      from setting_metrics
    ), '[]'::jsonb),
    'contact_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', contact_context, 'label', contact_label,
        'setting', setting_code, 'recorded_injuries', recorded_injuries,
        'time_loss_injuries', time_loss_injuries
      ) order by
        array_position(array['all', 'match', 'training', 'unknown'], setting_code),
        array_position(array['contact', 'non_contact', 'unknown'], contact_context)
      )
      from contact_distribution
    ), '[]'::jsonb)
  ) as dashboard_sections,
  jsonb_build_object(
    'injury_type_families', analysis.injury_type_families_from_payload_v1(
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', dimension, 'code', code, 'label', label,
          'setting', setting_code, 'time_loss_injuries', time_loss_injuries,
          'days_lost', days_lost, 'exposure_hours', exposure_hours,
          'incidence_per_1000h', incidence_per_1000h,
          'burden_per_1000h', burden_per_1000h,
          'mean_severity_days', mean_severity_days
        ) order by dimension, setting_code, code)
        from profiles
      ), '[]'::jsonb)
    )
  ) as family_section
) sections;

create or replace view analysis.league_dashboard_payload_analysis_window_v6_enriched
with (security_invoker = true) as
select base.season, base.classification_view_version,
  base.classification_evidence_sha256, base.cohort_view_version,
  base.cohort_evidence_sha256,
  base.dashboard || sections.dashboard_sections || sections.family_section as dashboard
from analysis.league_dashboard_payload_analysis_window_v6 base
cross join lateral (
  with profiles as materialized (
    select *
    from analysis.analysis_window_league_profiles_v6
    where season = base.season
  ), severity as materialized (
    select *
    from analysis.analysis_window_league_severity_v6
    where season = base.season
  ), setting_metrics as materialized (
    select *
    from analysis.analysis_window_league_setting_metrics_v6
    where season = base.season
  ), contact_distribution as materialized (
    select *
    from analysis.analysis_window_league_contact_distribution_v6
    where season = base.season
  )
  select jsonb_build_object(
    'body_locations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', code, 'label', label,
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours,
        'incidence_per_1000h', incidence_per_1000h,
        'burden_per_1000h', burden_per_1000h,
        'mean_severity_days', mean_severity_days
      ) order by code)
      from profiles
      where dimension = 'body_location' and setting_code = 'all'
    ), '[]'::jsonb),
    'injury_types', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', code, 'label', label,
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours,
        'incidence_per_1000h', incidence_per_1000h,
        'burden_per_1000h', burden_per_1000h,
        'mean_severity_days', mean_severity_days
      ) order by time_loss_injuries desc, code)
      from profiles
      where dimension = 'injury_type' and setting_code = 'all'
    ), '[]'::jsonb),
    'injury_profiles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dimension', dimension, 'code', code, 'label', label,
        'setting', setting_code, 'time_loss_injuries', time_loss_injuries,
        'days_lost', days_lost, 'exposure_hours', exposure_hours,
        'incidence_per_1000h', incidence_per_1000h,
        'burden_per_1000h', burden_per_1000h,
        'mean_severity_days', mean_severity_days
      ) order by dimension, setting_code, code)
      from profiles
    ), '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', severity_code,
        'label', initcap(replace(severity_code, '_', ' ')),
        'recorded_injuries', recorded_injuries,
        'time_loss_injuries', time_loss_injuries,
        'days_lost', days_lost
      ) order by severity_code)
      from severity
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', setting_code, 'label', initcap(setting_code),
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours,
        'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, exposure_hours),
        'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
        'mean_severity_days', days_lost / nullif(time_loss_injuries, 0)
      ) order by setting_code)
      from setting_metrics
    ), '[]'::jsonb),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', setting_code, 'label', initcap(setting_code),
        'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
        'exposure_hours', exposure_hours
      ) order by setting_code)
      from setting_metrics
    ), '[]'::jsonb),
    'contact_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', contact_context, 'label', contact_label,
        'setting', setting_code, 'recorded_injuries', recorded_injuries,
        'time_loss_injuries', time_loss_injuries
      ) order by
        array_position(array['all', 'match', 'training', 'unknown'], setting_code),
        array_position(array['contact', 'non_contact', 'unknown'], contact_context)
      )
      from contact_distribution
    ), '[]'::jsonb)
  ) as dashboard_sections,
  jsonb_build_object(
    'injury_type_families', analysis.injury_type_families_from_payload_v1(
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', dimension, 'code', code, 'label', label,
          'setting', setting_code, 'time_loss_injuries', time_loss_injuries,
          'days_lost', days_lost, 'exposure_hours', exposure_hours,
          'incidence_per_1000h', incidence_per_1000h,
          'burden_per_1000h', burden_per_1000h,
          'mean_severity_days', mean_severity_days
        ) order by dimension, setting_code, code)
        from profiles
      ), '[]'::jsonb)
    )
  ) as family_section
) sections;
