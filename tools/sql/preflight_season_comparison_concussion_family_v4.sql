select jsonb_build_object(
  'predecessor_attested', (
    select target_attested
    from reporting.approved_dashboard_reader_target_v5
  ),
  'predecessor_team_rows', (
    select count(*) from reporting.latest_team_season_comparison_v3
  ),
  'predecessor_league_rows', (
    select count(*) from reporting.latest_league_season_comparison_v3
  ),
  'predecessor_registered_exactly', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831160000'
      and name = 'season_comparison_diagnosis_top_three_v3'
      and statements = array[
        'migration_sha256=4803835b90a840e321414f0965daf8958bf9b100db4fecfd7a8342c90b4902ea',
        'rule_version=season_comparison_reporting_2026_08_31_v3',
        'change=ranked_top_three_diagnosis_families_by_setting_and_season'
      ]
  ),
  'migration_already_tracked', exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260831170000'
  ),
  'objects_already_exist', jsonb_build_object(
    'team_view', to_regclass('reporting.latest_team_season_comparison_v4') is not null,
    'league_view', to_regclass('reporting.latest_league_season_comparison_v4') is not null,
    'target_v6', to_regclass('reporting.approved_dashboard_reader_target_v6') is not null,
    'builder', to_regprocedure(
      'reporting.build_season_comparison_v4(jsonb,jsonb,text)'
    ) is not null
  )
) as verification;
