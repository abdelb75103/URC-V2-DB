do $$
begin
  if to_regclass('reporting.latest_team_season_comparison_v1') is null
    or to_regclass('reporting.latest_league_season_comparison_v1') is null
    or to_regclass('reporting.approved_dashboard_reader_target_v3') is null
    or to_regprocedure(
      'reporting.build_season_comparison_v1(jsonb,jsonb,text)'
    ) is null
    or to_regprocedure(
      'reporting.season_comparison_exposure_qualification_v1(jsonb)'
    ) is null
    or to_regprocedure(
      'reporting.season_comparison_severe_value_v1(jsonb)'
    ) is null
    or (select count(*) from reporting.latest_team_season_comparison_v1) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v1) <> 1
    or (select count(*) from reporting.approved_dashboard_reader_target_v3
        where target_attested) <> 1
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v1', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v1', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v3', 'select'
    )
    or not has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v1(jsonb,jsonb,text)',
      'execute'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.season_comparison_exposure_qualification_v1(jsonb)',
      'execute'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.season_comparison_severe_value_v1(jsonb)',
      'execute'
    )
    or has_table_privilege(
      'anon', 'reporting.latest_team_season_comparison_v1', 'select'
    )
    or has_table_privilege(
      'authenticated',
      'reporting.latest_league_season_comparison_v1',
      'select'
    )
  then
    raise exception 'Season comparison reporting objects or grants are invalid';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831140000',
  'season_comparison_reporting_v1',
  array[
    'migration_sha256=77b1e1cb6bc19eb53e264742d2e950431f327960744f36588b2352ad46bfa60b',
    'rule_version=season_comparison_reporting_2026_08_31_v1',
    'season_pair=2024-25_to_2025-26'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831140000'
      and name = 'season_comparison_reporting_v1'
      and statements = array[
        'migration_sha256=77b1e1cb6bc19eb53e264742d2e950431f327960744f36588b2352ad46bfa60b',
        'rule_version=season_comparison_reporting_2026_08_31_v1',
        'season_pair=2024-25_to_2025-26'
      ]
  ) then
    raise exception 'Season comparison reporting migration registration is invalid';
  end if;
end;
$$;
