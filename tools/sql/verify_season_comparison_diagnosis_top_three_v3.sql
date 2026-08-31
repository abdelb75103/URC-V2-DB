with team_checks as (
  select count(*) as row_count,
    bool_and(comparison ->> 'rule_version'
      = 'season_comparison_reporting_2026_08_31_v3') as versions_match,
    bool_and(jsonb_array_length(comparison -> 'diagnoses') = 3)
      as setting_groups_match,
    bool_and(not comparison ? 'severe') as severe_removed
  from reporting.latest_team_season_comparison_v3
), league_checks as (
  select comparison
  from reporting.latest_league_season_comparison_v3
), preserved as (
  select bool_and(
    current.comparison - 'rule_version' - 'diagnoses'
      = predecessor.comparison - 'rule_version' - 'diagnoses'
  ) as non_diagnosis_values_match
  from reporting.latest_team_season_comparison_v3 current
  join reporting.latest_team_season_comparison_v2 predecessor using (team_key)
), diagnosis_checks as (
  select bool_and(jsonb_typeof(setting -> 'previous') = 'array'
      and jsonb_typeof(setting -> 'current') = 'array'
      and jsonb_array_length(setting -> 'previous') <= 3
      and jsonb_array_length(setting -> 'current') <= 3)
      as arrays_valid,
    bool_and(coalesce((diagnosis ->> 'rank')::integer between 1 and 3, true))
      as ranks_valid,
    bool_and(coalesce(lower(diagnosis ->> 'diagnosis')
      !~ '(^|[[:space:]·/])unknown($|[[:space:]/])', true))
      as unknowns_suppressed
  from (
    select comparison from reporting.latest_team_season_comparison_v3
    union all
    select comparison from reporting.latest_league_season_comparison_v3
  ) comparisons
  cross join lateral jsonb_array_elements(
    comparisons.comparison -> 'diagnoses'
  ) setting
  left join lateral jsonb_array_elements(
    (setting -> 'previous') || (setting -> 'current')
  ) diagnosis on true
), registration as (
  select exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831160000'
      and name = 'season_comparison_diagnosis_top_three_v3'
      and statements = array[
        'migration_sha256=4803835b90a840e321414f0965daf8958bf9b100db4fecfd7a8342c90b4902ea',
        'rule_version=season_comparison_reporting_2026_08_31_v3',
        'change=ranked_top_three_diagnosis_families_by_setting_and_season'
      ]
  ) as exact
)
select jsonb_build_object(
  'migration_registered_exactly', registration.exact,
  'target_v5_attested', (
    select target_attested
    from reporting.approved_dashboard_reader_target_v5
  ),
  'team_contract', to_jsonb(team_checks),
  'league_contract', jsonb_build_object(
    'rule_version', league_checks.comparison ->> 'rule_version',
    'scope', league_checks.comparison ->> 'scope',
    'diagnosis_settings', jsonb_array_length(
      league_checks.comparison -> 'diagnoses'
    )
  ),
  'diagnosis_contract', to_jsonb(diagnosis_checks),
  'non_diagnosis_values_match', preserved.non_diagnosis_values_match,
  'reader_boundary', jsonb_build_object(
    'team_v3_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v3', 'select'
    ),
    'league_v3_select', has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v3', 'select'
    ),
    'target_v5_select', has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v5', 'select'
    ),
    'team_v2_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v2', 'select'
    ),
    'league_v2_select', has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v2', 'select'
    ),
    'builder_execute', has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v3(jsonb,jsonb,text)',
      'execute'
    ),
    'helper_execute', has_function_privilege(
      'web_reader',
      'reporting.season_comparison_top_diagnoses_v3(jsonb,text)',
      'execute'
    )
  )
) as verification
from team_checks, league_checks, preserved, diagnosis_checks, registration;
