do $$
begin
  if to_regclass('reporting.latest_team_season_comparison_v4') is null
    or to_regclass('reporting.latest_league_season_comparison_v4') is null
    or to_regclass('reporting.approved_dashboard_reader_target_v6') is null
    or (select count(*) from reporting.latest_team_season_comparison_v4) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v4) <> 1
    or (select count(*) from reporting.approved_dashboard_reader_target_v6
        where target_attested) <> 1
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v4', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v4', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v6', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v3', 'select'
    )
    or not has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v4(jsonb,jsonb,text)',
      'execute'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v3(jsonb,jsonb,text)',
      'execute'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v1(jsonb,jsonb,text)',
      'execute'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.season_comparison_top_diagnoses_v4(jsonb,text)',
      'execute'
    )
  then
    raise exception 'Season comparison concussion-family V4 objects or grants are invalid';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831170000',
  'season_comparison_concussion_family_v4',
  array[
    'migration_sha256=076434262d9d9d107744116612baf324f8f0b9417b4e87d2f19fe39f5c171758',
    'rule_version=season_comparison_reporting_2026_08_31_v4',
    'change=include_released_acute_concussion_variants_in_concussion_family'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260831170000'
      and name = 'season_comparison_concussion_family_v4'
      and statements = array[
        'migration_sha256=076434262d9d9d107744116612baf324f8f0b9417b4e87d2f19fe39f5c171758',
        'rule_version=season_comparison_reporting_2026_08_31_v4',
        'change=include_released_acute_concussion_variants_in_concussion_family'
      ]
  ) then
    raise exception 'Season comparison concussion-family V4 migration registration is invalid';
  end if;
end;
$$;
