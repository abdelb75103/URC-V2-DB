with team_checks as (
  select count(*) as row_count,
    bool_and(comparison ->> 'rule_version'
      = 'season_comparison_reporting_2026_08_31_v2') as versions_match,
    bool_and(not comparison ? 'severe') as severe_removed,
    bool_and(jsonb_array_length(comparison -> 'monthly') = 10)
      as monthly_domains_match
  from reporting.latest_team_season_comparison_v2
), league_checks as (
  select comparison
  from reporting.latest_league_season_comparison_v2
), preserved as (
  select bool_and(
    current.comparison - 'rule_version' - 'diagnoses'
      = predecessor.comparison - 'rule_version' - 'diagnoses' - 'severe'
  ) as non_presentation_values_match
  from reporting.latest_team_season_comparison_v2 current
  join reporting.latest_team_season_comparison_v1 predecessor using (team_key)
), registration as (
  select exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831150000'
      and name = 'season_comparison_presentation_v2'
      and statements = array[
        'migration_sha256=85722743687a87ce76d0d927687a2113b9e27b11b9ada8da0da3741e474384c3',
        'rule_version=season_comparison_reporting_2026_08_31_v2',
        'change=governed_hamstring_display_alias_and_remove_severe_browser_projection'
      ]
  ) as exact
)
select jsonb_build_object(
  'migration_registered_exactly', registration.exact,
  'target_v4_attested', (
    select target_attested
    from reporting.approved_dashboard_reader_target_v4
  ),
  'team_contract', to_jsonb(team_checks),
  'league_contract', jsonb_build_object(
    'rule_version', league_checks.comparison ->> 'rule_version',
    'scope', league_checks.comparison ->> 'scope',
    'severe_removed', not league_checks.comparison ? 'severe',
    'diagnosis_settings', jsonb_array_length(
      league_checks.comparison -> 'diagnoses'
    )
  ),
  'non_presentation_values_match',
    preserved.non_presentation_values_match,
  'reader_boundary', jsonb_build_object(
    'team_v2_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v2', 'select'
    ),
    'league_v2_select', has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v2', 'select'
    ),
    'target_v4_select', has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v4', 'select'
    ),
    'team_v1_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v1', 'select'
    ),
    'league_v1_select', has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v1', 'select'
    ),
    'presentation_execute', has_function_privilege(
      'web_reader',
      'reporting.season_comparison_presentation_v2(jsonb)',
      'execute'
    )
  )
) as verification
from team_checks, league_checks, preserved, registration;
