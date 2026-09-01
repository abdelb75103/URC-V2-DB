select jsonb_build_object(
  'predecessor_registered_exactly', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901010000'
      and name = 'urc_diagnosis_family_reporting_successor'
      and statements[1] = 'migration_sha256=b2d6af31bad2a49d26be8fe135c304fdc5a9c55a888f56cd26a5e32249cc903d'
  ),
  'migration_absent', not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260901020000'
  ),
  'team_intermediate_invoker', exists (
    select 1
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'reporting'
      and relation.relname = 'diagnosis_family_team_dashboards_v1'
      and coalesce(relation.reloptions, '{}'::text[])
        @> array['security_invoker=true']
  ),
  'league_intermediate_invoker', exists (
    select 1
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'reporting'
      and relation.relname = 'diagnosis_family_league_dashboards_v1'
      and coalesce(relation.reloptions, '{}'::text[])
        @> array['security_invoker=true']
  ),
  'private_intermediates_ungranted',
    not has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_team_dashboards_v1', 'select'
    )
    and not has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_league_dashboards_v1', 'select'
    ),
  'approved_readers_granted',
    has_table_privilege(
      'web_reader', 'reporting.latest_team_dashboard_v7', 'select'
    )
    and has_table_privilege(
      'web_reader', 'reporting.latest_league_dashboard_v7', 'select'
    )
    and has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v5', 'select'
    )
    and has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v5', 'select'
    )
) as preflight;
