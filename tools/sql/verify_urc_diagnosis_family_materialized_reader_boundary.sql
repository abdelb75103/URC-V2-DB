select jsonb_build_object(
  'migration_registered_exactly', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901021000'
      and name = 'urc_diagnosis_family_materialized_reader_boundary'
      and statements = array[
        'migration_sha256=eb015ecaa8ca3db1d4992f4c4d3498ff5f5aa65aac60f16693b780104443e5d0',
        'predecessor=20260901020000_urc_diagnosis_family_reader_execution_boundary',
        'scope=private_materialized_dashboard_payloads_no_helper_or_snapshot_reader_grants',
        'reader_contract=reporting_v7_and_season_comparison_v5'
      ]
  ),
  'snapshot_rows', jsonb_build_object(
    'teams', (select count(*) from reporting.diagnosis_family_team_dashboard_payloads_v2),
    'leagues', (select count(*) from reporting.diagnosis_family_league_dashboard_payloads_v2)
  ),
  'private_snapshots_ungranted',
    not has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_team_dashboard_payloads_v2', 'select'
    )
    and not has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_league_dashboard_payloads_v2', 'select'
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
  'private_helpers_ungranted',
    not has_function_privilege(
      'web_reader', 'reporting.diagnosis_family_rows_json_v1(text,text)', 'execute'
    )
    and not has_function_privilege(
      'web_reader', 'reporting.illness_profile_rows_json_v1(text,text)', 'execute'
    )
    and not has_function_privilege(
      'web_reader', 'reporting.illness_summary_json_v1(text,text)', 'execute'
    )
    and not has_function_privilege(
      'web_reader', 'reporting.replace_diagnosis_profiles_v1(jsonb,jsonb)', 'execute'
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
