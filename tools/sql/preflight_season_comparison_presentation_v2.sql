select jsonb_build_object(
  'predecessor_attested', (
    select target_attested
    from reporting.approved_dashboard_reader_target_v3
  ),
  'predecessor_team_rows', (
    select count(*) from reporting.latest_team_season_comparison_v1
  ),
  'predecessor_league_rows', (
    select count(*) from reporting.latest_league_season_comparison_v1
  ),
  'predecessor_registered_exactly', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831140000'
      and name = 'season_comparison_reporting_v1'
      and statements = array[
        'migration_sha256=77b1e1cb6bc19eb53e264742d2e950431f327960744f36588b2352ad46bfa60b',
        'rule_version=season_comparison_reporting_2026_08_31_v1',
        'season_pair=2024-25_to_2025-26'
      ]
  ),
  'migration_already_tracked', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831150000'
  ),
  'objects_already_exist', jsonb_build_object(
    'team_view', to_regclass(
      'reporting.latest_team_season_comparison_v2'
    ) is not null,
    'league_view', to_regclass(
      'reporting.latest_league_season_comparison_v2'
    ) is not null,
    'target_v4', to_regclass(
      'reporting.approved_dashboard_reader_target_v4'
    ) is not null,
    'presentation_function', to_regprocedure(
      'reporting.season_comparison_presentation_v2(jsonb)'
    ) is not null
  )
) as verification;
