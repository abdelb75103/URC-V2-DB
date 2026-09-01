do $$
begin
  if to_regclass('audit.urc_2024_25_diagnosis_family_source_rows_v1') is null
    or to_regclass('audit.urc_2024_25_illness_profile_source_rows_v1') is null
    or to_regclass('audit.urc_2025_26_diagnosis_family_exact_labels_v1') is null
    or to_regclass('audit.urc_2025_26_illness_exact_labels_v1') is null
    or to_regclass('analysis.urc_2025_26_canonical_injury_rows_v1') is null
    or to_regclass('analysis.urc_illness_profile_rows_v1') is null
    or to_regclass('reporting.latest_team_dashboard_v7') is null
    or to_regclass('reporting.latest_league_dashboard_v7') is null
    or to_regclass('reporting.latest_team_season_comparison_v5') is null
    or to_regclass('reporting.latest_league_season_comparison_v5') is null
    or to_regclass('reporting.approved_dashboard_reader_target_v7') is null
    or to_regprocedure('analysis.assert_urc_diagnosis_family_reporting_v1()') is null
    or (select count(*) from audit.urc_2024_25_diagnosis_family_source_rows_v1) <> 1660
    or (select count(*) from audit.urc_2024_25_illness_profile_source_rows_v1) <> 392
    or (select count(*) from audit.urc_2025_26_diagnosis_family_exact_labels_v1) <> 420
    or (select count(*) from audit.urc_2025_26_illness_exact_labels_v1) <> 113
    or (select count(distinct (illness_code, illness_label))
        from audit.urc_2025_26_illness_exact_labels_v1) <> 50
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1) <> 1545
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss) <> 938
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss and days_lost is not null) <> 782
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_2025_26_canonical_injury_rows_v1
        where is_time_loss) <> 20665
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code <> 'unknown') <> 1464
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown') <> 81
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown'
          and is_time_loss) <> 73
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_diagnosis_family_rows_v1
        where season = '2025-26' and family_code = 'unknown'
          and is_time_loss) <> 1042
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2024-25' and family_code <> 'unknown') <> 1658
    or (select count(*) from analysis.urc_diagnosis_family_rows_v1
        where season = '2024-25' and family_code = 'unknown') <> 4
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2024-25') <> 392
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2025-26') <> 439
    or (select count(*) from analysis.urc_illness_profile_rows_v1
        where season = '2025-26' and duration_known) <> 202
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_illness_profile_rows_v1
        where season = '2025-26' and duration_known) <> 927
    or (select count(distinct (illness_code, illness_label))
        from analysis.urc_illness_profile_rows_v1
        where season = '2025-26') <> 50
    or (select count(*) from reporting.latest_team_dashboard_v7) <> 32
    or (select count(*) from reporting.latest_league_dashboard_v7) <> 2
    or (select count(*) from reporting.latest_team_season_comparison_v5) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v5) <> 1
    or (select count(*) from reporting.approved_dashboard_reader_target_v7
        where target_attested) <> 1
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
    or not has_table_privilege(
      'web_reader', 'reporting.approved_dashboard_reader_target_v7', 'select'
    )
    or not has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v5(jsonb,jsonb,text)',
      'execute'
    )
    or has_table_privilege(
      'web_reader', 'audit.urc_2024_25_diagnosis_family_source_rows_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'audit.urc_2024_25_illness_profile_source_rows_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'audit.urc_2025_26_diagnosis_family_exact_labels_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'audit.urc_2025_26_illness_exact_labels_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'analysis.urc_diagnosis_family_rows_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'analysis.urc_canonical_injury_rows_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'analysis.urc_illness_profile_rows_v1', 'select'
    )
    or has_function_privilege(
      'web_reader',
      'reporting.season_comparison_top_diagnoses_v5(jsonb,text)',
      'execute'
    )
  then
    raise exception 'Diagnosis-family reporting successor objects or grants are invalid';
  end if;

  perform analysis.assert_urc_diagnosis_family_reporting_v1();
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260901010000',
  'urc_diagnosis_family_reporting_successor',
  array[
    'migration_sha256=b2d6af31bad2a49d26be8fe135c304fdc5a9c55a888f56cd26a5e32249cc903d',
    'ledger_sha256=cd319a12ab9fd73885c4e851bda11c2c277603a5e74665bd68bcb472738139dd',
    'mapping_rows_sha256=196f9c6765dfe83b2b205614aa61b4f5c3d53a85bc32983dabb1bdfdb5910f8e',
    'complete_ledger_sha256=7f3666de1309157843bade735bf79c4b30c39c75cc1542ef96f3254d5a840af5',
    'illness_inventory_sha256=6708f730cfa0faac40799b3eeafb99edd0e3e2e3c9a25de245daaaca1da3ef8d',
    'illness_mapping_rows_sha256=8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4',
    'illness_ledger_sha256=32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92',
    'rule_version=season_comparison_reporting_2026_09_01_v5',
    'scope=canonical_injury_and_separate_illness_reporting_overlay_no_release_or_source_mutation',
    'base_releases=urc-2024-25-v5-a80040f6afaa-a1,urc-2025-26-v6-b2bae1158257-a2',
    'cohorts=2024-25_injury_1662_illness_392,2025-26_injury_1545_illness_439',
    'illness_boundary=2025-26_labels_113_groups_50_recorded_439_known_202_days_927',
    'family_boundary=2024-25_mapped_1658_unknown_4,2025-26_non_unknown_1464_internal_unknown_81_source_conflict_19'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260901010000'
      and name = 'urc_diagnosis_family_reporting_successor'
      and statements = array[
        'migration_sha256=b2d6af31bad2a49d26be8fe135c304fdc5a9c55a888f56cd26a5e32249cc903d',
        'ledger_sha256=cd319a12ab9fd73885c4e851bda11c2c277603a5e74665bd68bcb472738139dd',
        'mapping_rows_sha256=196f9c6765dfe83b2b205614aa61b4f5c3d53a85bc32983dabb1bdfdb5910f8e',
        'complete_ledger_sha256=7f3666de1309157843bade735bf79c4b30c39c75cc1542ef96f3254d5a840af5',
        'illness_inventory_sha256=6708f730cfa0faac40799b3eeafb99edd0e3e2e3c9a25de245daaaca1da3ef8d',
        'illness_mapping_rows_sha256=8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4',
        'illness_ledger_sha256=32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92',
        'rule_version=season_comparison_reporting_2026_09_01_v5',
        'scope=canonical_injury_and_separate_illness_reporting_overlay_no_release_or_source_mutation',
        'base_releases=urc-2024-25-v5-a80040f6afaa-a1,urc-2025-26-v6-b2bae1158257-a2',
        'cohorts=2024-25_injury_1662_illness_392,2025-26_injury_1545_illness_439',
        'illness_boundary=2025-26_labels_113_groups_50_recorded_439_known_202_days_927',
        'family_boundary=2024-25_mapped_1658_unknown_4,2025-26_non_unknown_1464_internal_unknown_81_source_conflict_19'
      ]
  ) then
    raise exception 'Diagnosis-family reporting successor registration is invalid';
  end if;
end;
$$;
