do $$
begin
  if to_regclass(
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000'
    ) is null
    or to_regclass('analysis.accepted_release_contracts_v5') is null
    or (select count(*) from analysis.urc_2025_26_zebre_corrected_exposure_gate_v1) <> 1
    or (select count(*) from analysis.active_exposure_placeholders_v2) <> 2
    or (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000
      where snapshot_version = '20260831130000'
        and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
    ) <> 16
    or (
      select count(*)
      from analysis.team_dashboard_release_candidates_analysis_window_v6
      where season = '2025-26'
        and analysis_version = 'v6'
        and injury_lineage_snapshot_version = '20260831130000'
    ) <> 16
    or has_table_privilege(
      'web_reader',
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831130000',
      'select'
    )
    or has_table_privilege(
      'web_reader', 'analysis.accepted_release_contracts_v5', 'select'
    )
  then
    raise exception 'Partial Year 2 exposure reporting successor registration is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831130000',
  'urc_2025_26_partial_exposure_reporting_successor',
  array[
    'migration_sha256=fba07c9ff3dafc5291abdaa6077e7ebd6326a8925104a77b4c63599b1a6b3e0a',
    'evidence_sha256=e79107210e2344026b7f895c40fc4a5dd1a34c538256a4fc25db89bbf6ca4e30',
    'candidate_snapshot_version=20260831130000',
    'corrected_team=zebre',
    'registered_source_file_sha256=26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa',
    'correction_candidate_sha256=b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394',
    'corrected_record_version=102',
    'correction_step_version=input_representation_correction_2026-07-13_v1',
    'correction_source_row_count=6694',
    'correction_patched_rows=976',
    'correction_mapping_sha256=eddb583ddca717e2489d483fd0e8189b0e916ace34c4669bbcdbfb1507cb8dc1',
    'recomputed_estimate_teams=benetton,edinburgh',
    'corrected_zebre_included_rows=953',
    'corrected_zebre_clean_rule_exclusions=23',
    'source_backed_team_count=14',
    'temporary_estimate_team_count=2',
    'monthly_domain=2025-09_to_2026-06',
    'release_contract_table=analysis.accepted_release_contracts_v5'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831130000'
      and name = 'urc_2025_26_partial_exposure_reporting_successor'
      and statements = array[
        'migration_sha256=fba07c9ff3dafc5291abdaa6077e7ebd6326a8925104a77b4c63599b1a6b3e0a',
        'evidence_sha256=e79107210e2344026b7f895c40fc4a5dd1a34c538256a4fc25db89bbf6ca4e30',
        'candidate_snapshot_version=20260831130000',
        'corrected_team=zebre',
        'registered_source_file_sha256=26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa',
        'correction_candidate_sha256=b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394',
        'corrected_record_version=102',
        'correction_step_version=input_representation_correction_2026-07-13_v1',
        'correction_source_row_count=6694',
        'correction_patched_rows=976',
        'correction_mapping_sha256=eddb583ddca717e2489d483fd0e8189b0e916ace34c4669bbcdbfb1507cb8dc1',
        'recomputed_estimate_teams=benetton,edinburgh',
        'corrected_zebre_included_rows=953',
        'corrected_zebre_clean_rule_exclusions=23',
        'source_backed_team_count=14',
        'temporary_estimate_team_count=2',
        'monthly_domain=2025-09_to_2026-06',
        'release_contract_table=analysis.accepted_release_contracts_v5'
      ]
  ) then
    raise exception 'Partial Year 2 exposure reporting successor registration is invalid';
  end if;
end;
$$;
