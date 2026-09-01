select jsonb_build_object(
  'migration_registered_exactly', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901020000'
      and name = 'urc_diagnosis_family_reader_execution_boundary'
      and statements = array[
        'migration_sha256=f9d0cdce9b30e1bbe12dc6caacb2b37d60d1107833063281a158f0a1cc00b4b2',
        'predecessor=20260901010000_urc_diagnosis_family_reporting_successor',
        'scope=private_intermediate_view_execution_context_only_no_direct_reader_grant',
        'reader_contract=reporting_v7_and_season_comparison_v5'
      ]
  ),
  'team_intermediate_definer', exists (
    select 1
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'reporting'
      and relation.relname = 'diagnosis_family_team_dashboards_v1'
      and coalesce(relation.reloptions, '{}'::text[])
        @> array['security_invoker=false']
  ),
  'league_intermediate_definer', exists (
    select 1
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'reporting'
      and relation.relname = 'diagnosis_family_league_dashboards_v1'
      and coalesce(relation.reloptions, '{}'::text[])
        @> array['security_invoker=false']
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
    ),
  'cohorts_unchanged',
    (select count(*) from analysis.urc_diagnosis_family_rows_v1
      where season = '2024-25') = 1662
    and (select count(*) from analysis.urc_diagnosis_family_rows_v1
      where season = '2025-26') = 1545
    and (select count(*) from analysis.urc_illness_profile_rows_v1
      where season = '2024-25') = 392
    and (select count(*) from analysis.urc_illness_profile_rows_v1
      where season = '2025-26') = 439
) as verification;
