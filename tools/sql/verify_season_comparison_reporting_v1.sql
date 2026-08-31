with league as (
  select comparison
  from reporting.latest_league_season_comparison_v1
), team_checks as (
  select count(*) as row_count,
    bool_and(comparison ->> 'scope' = 'team') as scopes_match,
    bool_and(comparison ->> 'previous_season' = '2024-25')
      as previous_seasons_match,
    bool_and(comparison ->> 'current_season' = '2025-26')
      as current_seasons_match,
    bool_and(jsonb_array_length(comparison -> 'monthly') = 10)
      as monthly_domains_match
  from reporting.latest_team_season_comparison_v1
), registration as (
  select exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831140000'
      and name = 'season_comparison_reporting_v1'
      and statements = array[
        'migration_sha256=77b1e1cb6bc19eb53e264742d2e950431f327960744f36588b2352ad46bfa60b',
        'rule_version=season_comparison_reporting_2026_08_31_v1',
        'season_pair=2024-25_to_2025-26'
      ]
  ) as exact
)
select jsonb_build_object(
  'migration_registered_exactly', registration.exact,
  'target_v3_attested', (
    select target_attested
    from reporting.approved_dashboard_reader_target_v3
  ),
  'team_contract', to_jsonb(team_checks),
  'league_contract', jsonb_build_object(
    'scope', league.comparison ->> 'scope',
    'rule_version', league.comparison ->> 'rule_version',
    'previous_season', league.comparison ->> 'previous_season',
    'current_season', league.comparison ->> 'current_season',
    'monthly_rows', jsonb_array_length(league.comparison -> 'monthly'),
    'diagnosis_settings', jsonb_array_length(
      league.comparison -> 'diagnoses'
    ),
    'previous_incidence', league.comparison
      #>> '{kpis,0,previous,value}',
    'current_incidence', league.comparison
      #>> '{kpis,0,current,value}',
    'previous_severe_count', league.comparison
      #>> '{severe,previous,numerator}',
    'current_severe_count', league.comparison
      #>> '{severe,current,numerator}'
  ),
  'reader_boundary', jsonb_build_object(
    'team_view_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v1', 'select'
    ),
    'league_view_select', has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v1', 'select'
    ),
    'target_v3_select', has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v3', 'select'
    ),
    'builder_execute', has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v1(jsonb,jsonb,text)',
      'execute'
    ),
    'exposure_helper_execute', has_function_privilege(
      'web_reader',
      'reporting.season_comparison_exposure_qualification_v1(jsonb)',
      'execute'
    ),
    'severe_helper_execute', has_function_privilege(
      'web_reader',
      'reporting.season_comparison_severe_value_v1(jsonb)',
      'execute'
    )
  )
) as verification
from league, team_checks, registration;
