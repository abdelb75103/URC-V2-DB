do $$
begin
  if to_regclass('reporting.latest_team_season_comparison_v3') is null
    or to_regclass('reporting.latest_league_season_comparison_v3') is null
    or to_regclass('reporting.approved_dashboard_reader_target_v5') is null
    or to_regprocedure(
      'reporting.build_season_comparison_v3(jsonb,jsonb,text)'
    ) is null
    or (select count(*) from reporting.latest_team_season_comparison_v3) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v3) <> 1
    or (select count(*) from reporting.approved_dashboard_reader_target_v5
        where target_attested) <> 1
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v3', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v3', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v5', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v2', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v2', 'select'
    )
    or not has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v3(jsonb,jsonb,text)',
      'execute'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.season_comparison_top_diagnoses_v3(jsonb,text)',
      'execute'
    )
    or has_table_privilege(
      'anon', 'reporting.latest_team_season_comparison_v3', 'select'
    )
    or has_table_privilege(
      'authenticated',
      'reporting.latest_league_season_comparison_v3',
      'select'
    )
  then
    raise exception 'Season comparison diagnosis top-three V3 objects or grants are invalid';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831160000',
  'season_comparison_diagnosis_top_three_v3',
  array[
    'migration_sha256=4803835b90a840e321414f0965daf8958bf9b100db4fecfd7a8342c90b4902ea',
    'rule_version=season_comparison_reporting_2026_08_31_v3',
    'change=ranked_top_three_diagnosis_families_by_setting_and_season'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831160000'
      and name = 'season_comparison_diagnosis_top_three_v3'
      and statements = array[
        'migration_sha256=4803835b90a840e321414f0965daf8958bf9b100db4fecfd7a8342c90b4902ea',
        'rule_version=season_comparison_reporting_2026_08_31_v3',
        'change=ranked_top_three_diagnosis_families_by_setting_and_season'
      ]
  ) then
    raise exception 'Season comparison diagnosis top-three V3 migration registration is invalid';
  end if;
end;
$$;
