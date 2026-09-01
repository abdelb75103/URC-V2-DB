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
  ) or (select count(*) from reporting.approved_dashboard_reader_target_v6
        where target_attested) <> 1
  then raise exception 'Diagnosis-family predecessor is not exactly attested'; end if;

  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260831120000'
      and name = 'urc_2025_26_welsh_fixture_alias_correction'
      and statements = array[
        'migration_sha256=457ab116338396172393db7156a9c56cd9c77e3a6c6f30ae6a1c6701d4a2d678',
        'decision_version=welsh_fixture_alias_exact_date_2026_08_31_v1',
        'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
        'evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
        'reason_code=fixture_team_alias_exact_date_restoration',
        'restored_cardiff_rows=19',
        'restored_dragons_rows=42',
        'restored_other_team_rows=0'
      ]
  ) or not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260831121000'
      and name = 'urc_2025_26_welsh_fixture_candidate_successor'
      and statements = array[
        'migration_sha256=b2627d530759579077af62ebc65be2cc6707ceb6cd946461dc3f97c96c1e0474',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
        'cohort_evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
        'candidate_snapshot_version=20260831121000',
        'changed_teams=cardiff,dragons',
        'unchanged_team_count=14'
      ]
  ) then raise exception 'Welsh injury-cohort predecessors are not exactly registered'; end if;

  if not exists (
    select 1
    from reporting.latest_approved_dashboard_bundle_v4 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join reporting.dashboard_bundle_league_payloads_v1 payload
      on payload.release_id = latest.release_id
    where latest.season = '2024-25'
      and latest.release_id = '0f0def1e-021f-471f-979f-6d73d98859c4'::uuid
      and release.release_label = 'urc-2024-25-v5-a80040f6afaa-a1'
      and payload.payload_sha256 =
        '4517f50bdf03688c087a34062071d97bd635576011e02f6f8ca5d1dc69a156ae'
      and (select count(*) from reporting.dashboard_bundle_team_payloads_v1 team
        where team.bundle_release_id = latest.release_id) = 16
  ) or not exists (
    select 1
    from reporting.latest_approved_league_bundle_v6 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join audit.pipeline_runs run on run.id = release.pipeline_run_id
    join reporting.league_release_payloads_v6 payload
      on payload.release_id = latest.release_id
    where latest.season = '2025-26'
      and latest.release_id = 'f1d9c2cc-f70c-4dcc-a18d-3f2dc92d4cfc'::uuid
      and release.release_label = 'urc-2025-26-v6-b2bae1158257-a2'
      and run.output_hash =
        'b2bae1158257976b8e7da2385a7df065a2cd621492017bfb192a293ac16a1f41'
      and payload.payload_sha256 =
        '4eafb2dc32d155c69d968e833a354c145e08e0f13356b300234cefc1e2889c05'
      and (select count(*) from reporting.team_dashboard_payloads_v2 team
        where team.bundle_release_id = latest.release_id) = 16
  ) then raise exception 'Approved release identity or membership drifted'; end if;

  if to_regclass('analysis.urc_2024_25_final_injury_classification_v1') is null
    or to_regclass('analysis.urc_2025_26_reporting_key_rows_v3') is null
    or to_regclass('analysis.urc_2025_26_injury_fixture_corrected_rows_v2') is null
    or to_regclass('audit.urc_2025_26_fixture_reconciliation_decisions_v1') is null
    or to_regclass('lineage.injury_inclusion_rows_v3') is null
    or to_regclass('lineage.injury_master_rows_v3') is null
    or to_regclass('audit.urc_2024_25_specific_diagnosis_mappings_v1') is null
    or to_regclass('reporting.latest_team_dashboard_v6') is null
    or to_regclass('reporting.latest_league_dashboard_v6') is null
  then raise exception 'Required approved private lineage or reader is absent'; end if;

  -- The 1,484-row checks attest the historical pre-Welsh predecessor.
  -- The governed current cohort is the separately pinned 1,545-row V3 view.
  if not exists (
    select 1 from analysis.accepted_urc_2025_26_injury_successor_evidence_v1
    where included_row_count = 1923 and dashboard_injury_row_count = 1484
  ) or (select count(*) from lineage.injury_inclusion_rows_v3 inclusion
        join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
          on evidence.successor_version_id = inclusion.version_id
        where inclusion.dashboard_eligible) <> 1484
    or (select count(*) from lineage.injury_inclusion_rows_v3 inclusion
        join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
          on evidence.successor_version_id = inclusion.version_id
        where inclusion.dashboard_eligibility_reason =
          'illness_record_not_in_injury_cohort') <> 439
    or (select count(*) from lineage.injury_inclusion_rows_v3 inclusion
        join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
          on evidence.successor_version_id = inclusion.version_id
        join lineage.injury_master_rows_v3 master
          on master.version_id = inclusion.version_id
         and master.source_row = inclusion.source_row
        where lower(btrim(master.row_values ->> 'Problem type')) = 'injury') <> 1484
    or (select count(*) from lineage.injury_inclusion_rows_v3 inclusion
        join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
          on evidence.successor_version_id = inclusion.version_id
        join lineage.injury_master_rows_v3 master
          on master.version_id = inclusion.version_id
         and master.source_row = inclusion.source_row
        where lower(btrim(master.row_values ->> 'Problem type')) = 'illness') <> 439
    or (select count(*) from lineage.injury_inclusion_rows_v3 inclusion
        join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
          on evidence.successor_version_id = inclusion.version_id
        join lineage.injury_master_rows_v3 master
          on master.version_id = inclusion.version_id
         and master.source_row = inclusion.source_row
        where inclusion.dashboard_eligibility_reason =
          'illness_record_not_in_injury_cohort'
          and lower(btrim(master.row_values ->> 'Problem type')) = 'illness'
          and master.time_loss_days is not null) <> 202
    or (select coalesce(sum(master.time_loss_days), 0)
        from lineage.injury_inclusion_rows_v3 inclusion
        join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
          on evidence.successor_version_id = inclusion.version_id
        join lineage.injury_master_rows_v3 master
          on master.version_id = inclusion.version_id
         and master.source_row = inclusion.source_row
        where inclusion.dashboard_eligibility_reason =
          'illness_record_not_in_injury_cohort'
          and lower(btrim(master.row_values ->> 'Problem type')) = 'illness'
          and master.time_loss_days is not null) <> 927
    or (select count(*) filter (where team_key = 'cardiff') = 19
          and count(*) filter (where team_key = 'dragons') = 42
          and count(*) = 61
        from audit.urc_2025_26_fixture_reconciliation_decisions_v1) is not true
    or (select count(*) from analysis.urc_2025_26_reporting_key_rows_v3) <> 1545
    or (select count(distinct source_row)
        from analysis.urc_2025_26_reporting_key_rows_v3) <> 1545
    or (select count(*) from analysis.urc_2025_26_reporting_key_rows_v3
        where is_time_loss) <> 938
    or (select count(*) from analysis.urc_2025_26_reporting_key_rows_v3
        where is_time_loss and days_lost is not null) <> 782
    or (select coalesce(sum(days_lost), 0)
        from analysis.urc_2025_26_reporting_key_rows_v3
        where is_time_loss) <> 20665
    or (select count(*) from analysis.urc_2025_26_injury_fixture_corrected_rows_v2)
        <> 1545
    or exists (
      select source_row from analysis.urc_2025_26_reporting_key_rows_v3
      except
      select source_row from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
    )
    or exists (
      select source_row from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      except
      select source_row from analysis.urc_2025_26_reporting_key_rows_v3
    )
    or not exists (
      select 1 from analysis.urc_2024_25_classification_evidence_v1
      where specific_diagnosis_illness_rows_excluded = 392
        and specific_diagnosis_injury_rows = 1660
        and specific_diagnosis_evidence_sha256 =
          'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167'
    )
  then raise exception 'Approved 1545 injury, 439 illness or 392 illness cohort drifted'; end if;

  if exists (select 1 from supabase_migrations.schema_migrations
      where version = '20260901010000')
    or to_regclass('reporting.latest_team_dashboard_v7') is not null
    or to_regclass('reporting.latest_league_dashboard_v7') is not null
    or to_regclass('audit.urc_diagnosis_family_adjudication_evidence_v1') is not null
    or to_regclass('audit.urc_2025_26_illness_exact_labels_v1') is not null
  then raise exception 'Diagnosis-family successor is already present'; end if;
end;
$$;

select jsonb_build_object(
  'predecessor_registered_exactly', true,
  'welsh_predecessors_registered_exactly', true,
  'predecessor_attested', true,
  'migration_absent', true,
  'approved_releases', jsonb_build_object(
    '2024-25', jsonb_build_object(
      'release_id', '0f0def1e-021f-471f-979f-6d73d98859c4',
      'release_label', 'urc-2024-25-v5-a80040f6afaa-a1',
      'league_payload_sha256',
        '4517f50bdf03688c087a34062071d97bd635576011e02f6f8ca5d1dc69a156ae'
    ),
    '2025-26', (select jsonb_build_object(
      'release_id', latest.release_id,
      'release_label', release.release_label,
      'league_payload_sha256', payload.payload_sha256,
      'bundle_payload_sha256', run.output_hash
    )
    from reporting.latest_approved_league_bundle_v6 latest
    join reporting.aggregate_releases release on release.id = latest.release_id
    join audit.pipeline_runs run on run.id = release.pipeline_run_id
    join reporting.league_release_payloads_v6 payload
      on payload.release_id = latest.release_id
    where latest.season = '2025-26'
      and latest.release_id = 'f1d9c2cc-f70c-4dcc-a18d-3f2dc92d4cfc'::uuid)
  ),
  'approved_cohorts', jsonb_build_object(
    '2025-26_historical_pre_welsh_injuries', 1484,
    '2025-26_welsh_restored_injuries', 61,
    '2025-26_current_injuries', 1545,
    '2025-26_current_time_loss_injuries', 938,
    '2025-26_current_known_duration_time_loss_injuries', 782,
    '2025-26_current_days_lost', 20665,
    '2025-26_illnesses', 439,
    '2025-26_known_duration_illnesses', 202,
    '2025-26_illness_days_lost', 927,
    '2024-25_illnesses', 392
  ),
  'illness_adjudication', jsonb_build_object(
    '2025-26_source_labels', 113,
    '2025-26_groups', 50,
    'inventory_sha256',
      '6708f730cfa0faac40799b3eeafb99edd0e3e2e3c9a25de245daaaca1da3ef8d',
    'mapping_rows_sha256',
      '8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4',
    'ledger_sha256',
      '32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92'
  ),
  'diagnosis_family_boundary', jsonb_build_object(
    '2025-26_non_unknown_rows', 1464,
    '2025-26_internal_unknown_rows', 81,
    '2025-26_internal_unknown_time_loss_injuries', 73,
    '2025-26_internal_unknown_days_lost', 1042,
    '2025-26_source_conflict_rows', 19,
    '2025-26_source_conflict_time_loss_injuries', 18,
    '2025-26_source_conflict_days_lost', 73,
    '2024-25_mapped_rows', 1658,
    '2024-25_internal_unknown_rows', 4
  )
) as preflight;
