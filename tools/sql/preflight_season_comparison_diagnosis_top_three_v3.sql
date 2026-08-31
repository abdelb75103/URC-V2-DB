select jsonb_build_object(
  'predecessor_attested', (
    select target_attested
    from reporting.approved_dashboard_reader_target_v4
  ),
  'predecessor_team_rows', (
    select count(*) from reporting.latest_team_season_comparison_v2
  ),
  'predecessor_league_rows', (
    select count(*) from reporting.latest_league_season_comparison_v2
  ),
  'predecessor_registered_exactly', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831150000'
      and name = 'season_comparison_presentation_v2'
      and statements = array[
        'migration_sha256=85722743687a87ce76d0d927687a2113b9e27b11b9ada8da0da3741e474384c3',
        'rule_version=season_comparison_reporting_2026_08_31_v2',
        'change=governed_hamstring_display_alias_and_remove_severe_browser_projection'
      ]
  ),
  'migration_already_tracked', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831160000'
  ),
  'objects_already_exist', jsonb_build_object(
    'team_view', to_regclass(
      'reporting.latest_team_season_comparison_v3'
    ) is not null,
    'league_view', to_regclass(
      'reporting.latest_league_season_comparison_v3'
    ) is not null,
    'target_v5', to_regclass(
      'reporting.approved_dashboard_reader_target_v5'
    ) is not null,
    'builder', to_regprocedure(
      'reporting.build_season_comparison_v3(jsonb,jsonb,text)'
    ) is not null
  )
) as verification;
