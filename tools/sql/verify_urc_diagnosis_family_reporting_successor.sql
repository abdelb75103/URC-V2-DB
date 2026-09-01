with registration as (
  select exists (
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
  ) as exact
), pinned as (
  select jsonb_object_agg(
    season || ':' || setting_code || ':' || family_label,
    jsonb_build_object(
      'recorded_injuries', recorded_injuries,
      'time_loss_injuries', time_loss_injuries,
      'known_duration_time_loss_injuries', known_duration_time_loss_injuries,
      'days_lost', days_lost
    )
  ) as rows
  from analysis.urc_diagnosis_family_league_families_v1
  where (season, setting_code, family_label) in (
    ('2024-25', 'all', 'Concussion'),
    ('2025-26', 'all', 'Concussion'),
    ('2025-26', 'match', 'Concussion'),
    ('2025-26', 'training', 'Concussion'),
    ('2025-26', 'all', 'Hamstring muscle injury')
  )
)
select jsonb_build_object(
  'migration_registered_exactly', registration.exact,
  'target_v7_attested', (
    select target_attested from reporting.approved_dashboard_reader_target_v7
  ),
  'reader_counts', jsonb_build_object(
    'teams', (
      select count(*) from reporting.diagnosis_family_base_team_payloads_v1
    ),
    'leagues', (
      select count(*) from reporting.diagnosis_family_base_league_payloads_v1
    ),
    'team_comparisons', (
      select count(*)
      from reporting.diagnosis_family_base_team_payloads_v1 previous
      join reporting.diagnosis_family_base_team_payloads_v1 current
        using (team_key)
      where previous.season = '2024-25'
        and current.season = '2025-26'
    ),
    'league_comparisons', (
      select count(*)
      from reporting.diagnosis_family_base_league_payloads_v1 previous
      join reporting.diagnosis_family_base_league_payloads_v1 current
        on previous.season = '2024-25'
       and current.season = '2025-26'
    )
  ),
  'mapping_counts', jsonb_build_object(
    '2024-25_source_rows', (
      select count(*) from audit.urc_2024_25_diagnosis_family_source_rows_v1
    ),
    '2024-25_illness_source_rows', (
      select count(*) from audit.urc_2024_25_illness_profile_source_rows_v1
    ),
    '2025-26_exact_labels', (
      select count(*) from audit.urc_2025_26_diagnosis_family_exact_labels_v1
    ),
    '2025-26_illness_exact_labels', (
      select count(*) from audit.urc_2025_26_illness_exact_labels_v1
    ),
    '2025-26_illness_groups', (
      select count(distinct (illness_code, illness_label))
      from audit.urc_2025_26_illness_exact_labels_v1
    )
  ),
  'canonical_cohorts', jsonb_build_object(
    '2025-26_injuries', (
      select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
    ),
    '2025-26_time_loss_injuries', (
      select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
      where is_time_loss
    ),
    '2025-26_known_duration_time_loss_injuries', (
      select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1
      where is_time_loss and days_lost is not null
    ),
    '2025-26_days_lost', (
      select coalesce(sum(days_lost), 0)
      from analysis.urc_2025_26_canonical_injury_rows_v1
      where is_time_loss
    ),
    '2025-26_illnesses', (
      select count(*) from analysis.urc_illness_profile_rows_v1
      where season = '2025-26'
    ),
    '2025-26_known_duration_illnesses', (
      select count(*) from analysis.urc_illness_profile_rows_v1
      where season = '2025-26' and duration_known
    ),
    '2025-26_illness_days_lost', (
      select coalesce(sum(days_lost), 0)
      from analysis.urc_illness_profile_rows_v1
      where season = '2025-26' and duration_known
    ),
    '2024-25_illnesses', (
      select count(*) from analysis.urc_illness_profile_rows_v1
      where season = '2024-25'
    )
  ),
  'family_boundary', jsonb_build_object(
    '2025-26_non_unknown_rows', (select count(*)
      from analysis.urc_diagnosis_family_rows_v1
      where season = '2025-26' and family_code <> 'unknown'),
    '2025-26_internal_unknown_rows', (select count(*)
      from analysis.urc_diagnosis_family_rows_v1
      where season = '2025-26' and family_code = 'unknown'),
    '2025-26_internal_unknown_time_loss_injuries', (select count(*)
      from analysis.urc_diagnosis_family_rows_v1
      where season = '2025-26' and family_code = 'unknown' and is_time_loss),
    '2025-26_internal_unknown_days_lost', (select coalesce(sum(days_lost), 0)
      from analysis.urc_diagnosis_family_rows_v1
      where season = '2025-26' and family_code = 'unknown' and is_time_loss),
    '2025-26_source_conflict_rows', (select count(*)
      from analysis.urc_2025_26_canonical_injury_rows_v1 injury
      left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
        on family.source_label = injury.diagnosis_label
      where family.family_code is null),
    '2025-26_source_conflict_time_loss_injuries', (select count(*)
      from analysis.urc_2025_26_canonical_injury_rows_v1 injury
      left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
        on family.source_label = injury.diagnosis_label
      where family.family_code is null and injury.is_time_loss),
    '2025-26_source_conflict_days_lost', (select coalesce(sum(injury.days_lost), 0)
      from analysis.urc_2025_26_canonical_injury_rows_v1 injury
      left join audit.urc_2025_26_diagnosis_family_exact_labels_v1 family
        on family.source_label = injury.diagnosis_label
      where family.family_code is null and injury.is_time_loss),
    '2024-25_mapped_rows', (select count(*)
      from analysis.urc_diagnosis_family_rows_v1
      where season = '2024-25' and family_code <> 'unknown'),
    '2024-25_unknown_rows', (select count(*)
      from analysis.urc_diagnosis_family_rows_v1
      where season = '2024-25' and family_code = 'unknown'),
    '2024-25_stale_source_mappings', (select count(*)
      from audit.urc_2024_25_diagnosis_family_source_rows_v1 family
      left join analysis.urc_2024_25_final_injury_classification_v1 injury
        on injury.source_row = family.source_row
       and injury.canonical_problem_type = 'injury'
      where injury.source_row is null)
  ),
  'pinned_families', pinned.rows,
  'reader_boundary', jsonb_build_object(
    'team_v7_select', has_table_privilege(
      'web_reader', 'reporting.latest_team_dashboard_v7', 'select'
    ),
    'league_v7_select', has_table_privilege(
      'web_reader', 'reporting.latest_league_dashboard_v7', 'select'
    ),
    'private_2024_map_select', has_table_privilege(
      'web_reader', 'audit.urc_2024_25_diagnosis_family_source_rows_v1', 'select'
    ),
    'private_2024_illness_map_select', has_table_privilege(
      'web_reader', 'audit.urc_2024_25_illness_profile_source_rows_v1', 'select'
    ),
    'private_2025_map_select', has_table_privilege(
      'web_reader', 'audit.urc_2025_26_diagnosis_family_exact_labels_v1', 'select'
    ),
    'private_2025_illness_map_select', has_table_privilege(
      'web_reader', 'audit.urc_2025_26_illness_exact_labels_v1', 'select'
    ),
    'comparison_builder_execute', has_function_privilege(
      'web_reader',
      'reporting.build_season_comparison_v5(jsonb,jsonb,text)',
      'execute'
    ),
    'comparison_helper_execute', has_function_privilege(
      'web_reader',
      'reporting.season_comparison_top_diagnoses_v5(jsonb,text)',
      'execute'
    )
  )
) as verification
from registration, pinned;
