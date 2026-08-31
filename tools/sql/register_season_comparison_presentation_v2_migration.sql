do $$
begin
  if to_regclass('reporting.latest_team_season_comparison_v2') is null
    or to_regclass('reporting.latest_league_season_comparison_v2') is null
    or to_regclass('reporting.approved_dashboard_reader_target_v4') is null
    or to_regprocedure(
      'reporting.season_comparison_presentation_v2(jsonb)'
    ) is null
    or (select count(*) from reporting.latest_team_season_comparison_v2) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v2) <> 1
    or (select count(*) from reporting.approved_dashboard_reader_target_v4
        where target_attested) <> 1
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v2', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v2', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v4', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v1', 'select'
    )
    or not has_function_privilege(
      'web_reader',
      'reporting.season_comparison_presentation_v2(jsonb)',
      'execute'
    )
    or has_table_privilege(
      'anon', 'reporting.latest_team_season_comparison_v2', 'select'
    )
    or has_table_privilege(
      'authenticated',
      'reporting.latest_league_season_comparison_v2',
      'select'
    )
  then
    raise exception 'Season comparison presentation V2 objects or grants are invalid';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831150000',
  'season_comparison_presentation_v2',
  array[
    'migration_sha256=85722743687a87ce76d0d927687a2113b9e27b11b9ada8da0da3741e474384c3',
    'rule_version=season_comparison_reporting_2026_08_31_v2',
    'change=governed_hamstring_display_alias_and_remove_severe_browser_projection'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831150000'
      and name = 'season_comparison_presentation_v2'
      and statements = array[
        'migration_sha256=85722743687a87ce76d0d927687a2113b9e27b11b9ada8da0da3741e474384c3',
        'rule_version=season_comparison_reporting_2026_08_31_v2',
        'change=governed_hamstring_display_alias_and_remove_severe_browser_projection'
      ]
  ) then
    raise exception 'Season comparison presentation V2 migration registration is invalid';
  end if;
end;
$$;
