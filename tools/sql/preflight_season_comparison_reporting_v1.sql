with season_counts as (
  select jsonb_build_object(
    'team_2024_25', (
      select count(*) from reporting.latest_team_dashboard_v6
      where season = '2024-25'
    ),
    'team_2025_26', (
      select count(*) from reporting.latest_team_dashboard_v6
      where season = '2025-26'
    ),
    'league_2024_25', (
      select count(*) from reporting.latest_league_dashboard_v6
      where season = '2024-25'
    ),
    'league_2025_26', (
      select count(*) from reporting.latest_league_dashboard_v6
      where season = '2025-26'
    ),
    'cache_tokens', (
      select count(*) from reporting.latest_dashboard_cache_token_v2
      where season in ('2024-25', '2025-26')
    )
  ) as counts
)
select jsonb_build_object(
  'predecessor_attested', (
    select target_attested from reporting.approved_dashboard_reader_target_v2
  ),
  'approved_reader_counts', counts,
  'migration_already_tracked', exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260831140000'
  ),
  'objects_already_exist', jsonb_build_object(
    'team_view', to_regclass(
      'reporting.latest_team_season_comparison_v1'
    ) is not null,
    'league_view', to_regclass(
      'reporting.latest_league_season_comparison_v1'
    ) is not null,
    'target_v3', to_regclass(
      'reporting.approved_dashboard_reader_target_v3'
    ) is not null,
    'builder', to_regprocedure(
      'reporting.build_season_comparison_v1(jsonb,jsonb,text)'
    ) is not null
  )
) as verification
from season_counts;
