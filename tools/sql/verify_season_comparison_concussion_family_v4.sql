with team_checks as (
  select count(*) as row_count,
    bool_and(comparison ->> 'rule_version'
      = 'season_comparison_reporting_2026_08_31_v4') as versions_match
  from reporting.latest_team_season_comparison_v4
), preserved as (
  select bool_and(
    current.comparison - 'rule_version' - 'diagnoses'
      = predecessor.comparison - 'rule_version' - 'diagnoses'
  ) as non_diagnosis_values_match
  from reporting.latest_team_season_comparison_v4 current
  join reporting.latest_team_season_comparison_v3 predecessor using (team_key)
), registration as (
  select exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260831170000'
      and name = 'season_comparison_concussion_family_v4'
      and statements = array[
        'migration_sha256=076434262d9d9d107744116612baf324f8f0b9417b4e87d2f19fe39f5c171758',
        'rule_version=season_comparison_reporting_2026_08_31_v4',
        'change=include_released_acute_concussion_variants_in_concussion_family'
      ]
  ) as exact
), league_concussion as (
  select diagnosis
  from reporting.latest_league_season_comparison_v4 comparison
  cross join lateral jsonb_array_elements(comparison.comparison -> 'diagnoses') setting
  cross join lateral jsonb_array_elements(setting -> 'current') diagnosis
  where setting ->> 'setting' = 'all'
    and diagnosis ->> 'diagnosis' = 'Concussion'
)
select jsonb_build_object(
  'migration_registered_exactly', registration.exact,
  'target_v6_attested', (
    select target_attested from reporting.approved_dashboard_reader_target_v6
  ),
  'team_contract', to_jsonb(team_checks),
  'non_diagnosis_values_match', preserved.non_diagnosis_values_match,
  'acute_variant_family', reporting.season_comparison_diagnosis_family_v4(
    'acute_concussion_with_visual_symptoms',
    'Acute Concussion with visual symptoms'
  ),
  'league_current_overall_concussion', (
    select diagnosis from league_concussion
  ),
  'reader_boundary', jsonb_build_object(
    'team_v4_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v4', 'select'
    ),
    'league_v4_select', has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v4', 'select'
    ),
    'team_v3_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v3', 'select'
    ),
    'builder_v4_execute', has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v4(jsonb,jsonb,text)',
      'execute'
    ),
    'builder_v3_execute', has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v3(jsonb,jsonb,text)',
      'execute'
    ),
    'builder_v1_execute', has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v1(jsonb,jsonb,text)',
      'execute'
    ),
    'helper_v4_execute', has_function_privilege(
      'web_reader',
      'reporting.season_comparison_top_diagnoses_v4(jsonb,text)',
      'execute'
    )
  )
) as verification
from team_checks, preserved, registration;
