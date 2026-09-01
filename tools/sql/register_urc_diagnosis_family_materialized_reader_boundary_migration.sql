do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901020000'
      and name = 'urc_diagnosis_family_reader_execution_boundary'
      and statements[1] = 'migration_sha256=f9d0cdce9b30e1bbe12dc6caacb2b37d60d1107833063281a158f0a1cc00b4b2'
  )
    or (select count(*) from reporting.diagnosis_family_team_dashboard_payloads_v2) <> 32
    or (select count(*) from reporting.diagnosis_family_league_dashboard_payloads_v2) <> 2
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_team_dashboard_payloads_v2', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_league_dashboard_payloads_v2', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_dashboard_v7', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_dashboard_v7', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v5', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v5', 'select'
    )
    or has_function_privilege(
      'web_reader', 'reporting.replace_diagnosis_profiles_v1(jsonb,jsonb)', 'execute'
    )
  then
    raise exception 'Diagnosis-family materialized-reader boundary is invalid';
  end if;
end;
$$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260901021000',
  'urc_diagnosis_family_materialized_reader_boundary',
  array[
    'migration_sha256=eb015ecaa8ca3db1d4992f4c4d3498ff5f5aa65aac60f16693b780104443e5d0',
    'predecessor=20260901020000_urc_diagnosis_family_reader_execution_boundary',
    'scope=private_materialized_dashboard_payloads_no_helper_or_snapshot_reader_grants',
    'reader_contract=reporting_v7_and_season_comparison_v5'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
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
  )
  then
    raise exception 'Diagnosis-family materialized-reader registration is invalid';
  end if;
end;
$$;
