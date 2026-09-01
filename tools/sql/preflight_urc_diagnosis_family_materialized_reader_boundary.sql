select jsonb_build_object(
  'predecessor_registered_exactly', exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901020000'
      and name = 'urc_diagnosis_family_reader_execution_boundary'
      and statements[1] = 'migration_sha256=f9d0cdce9b30e1bbe12dc6caacb2b37d60d1107833063281a158f0a1cc00b4b2'
  ),
  'migration_absent', not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260901021000'
  ),
  'snapshots_absent',
    to_regclass('reporting.diagnosis_family_team_dashboard_payloads_v2') is null
    and to_regclass('reporting.diagnosis_family_league_dashboard_payloads_v2') is null,
  'source_rows', jsonb_build_object(
    'teams', (select count(*) from reporting.diagnosis_family_team_dashboards_v1),
    'leagues', (select count(*) from reporting.diagnosis_family_league_dashboards_v1)
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
    )
) as preflight;
