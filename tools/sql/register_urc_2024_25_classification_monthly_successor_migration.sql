-- Registration is an integrity record, not a promotion. It is intentionally
-- separate from the additive migration and fails closed on any mismatch.

do $$
begin
  if to_regclass('audit.urc_2024_25_classification_adjudications_v1') is null
    or to_regclass('analysis.urc_2024_25_classification_evidence_v1') is null
    or to_regclass('analysis.urc_2024_25_final_injury_classification_v1') is null
    or to_regclass('analysis.urc_2024_25_team_dashboard_candidate_v1') is null
    or to_regclass('analysis.urc_2024_25_league_dashboard_candidate_v1') is null
    or to_regprocedure('analysis.assert_urc_2024_25_classification_successor_v1()') is null
    or to_regprocedure('audit.row_correction_set_hash_v3(text,jsonb)') is null
  then
    raise exception '2024-25 classification successor objects are incomplete';
  end if;

  if (select count(*) from analysis.urc_2024_25_team_dashboard_candidate_v1) <> 16
     or (select count(*) from analysis.urc_2024_25_league_dashboard_candidate_v1) <> 1
  then
    raise exception '2024-25 successor candidate is not atomic 16-team plus league';
  end if;

  if (select count(*) from analysis.row_correction_member_releases_v1
      where season = '2024-25'
        and predecessor_bundle_id =
          '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid) <> 16
  then
    raise exception '2024-25 successor is not bound to the exact predecessor release';
  end if;

  if audit.row_correction_set_hash_v3('2024-25', null) <>
      'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'
  then
    raise exception '2024-25 successor active correction set is not the approved Dragons correction hash';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260826100000',
  'urc_2024_25_classification_monthly_successor',
  array[
    'migration_sha256=480e990eb17805bb875afe2c13a97e4e2dd71832f40c243fd629a0c29074bd5b',
    'evidence_file_sha256=0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833',
    'specific_diagnosis_evidence_sha256=5855127dc199df1918cb906250809ad00b6f2d8ea03904a7ceee5d587996a753',
    'specific_diagnosis_mapping_rows_sha256=8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7',
    'successor_disclosure_method_sha256=9bd4ff3c60fb1aa33e3f4d1d1c5ff35f83bbd6cbd777aca90b6fbd3bc980de7c',
    'successor_disclosure_limitations_sha256=d8b32c5dddb9f740d238b44e4c40d099ed671ccc58bcdc95a5310471c78b75f9',
    'adjudication_manifest_sha256=cd5bed8cd5a98a6b5290194371fb92f01020ed8020ff3ddb859251741f349835',
    'source_master_sha256=15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63',
    'accepted_workbook_sha256=4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73',
    'adjudication_workbook_sha256=87ebb569afc45ef28116df98dc83c2d8799139eaecd1c249372c209fa783f155',
    'predecessor_release_id=8b50b9e2-023b-4f99-b6ae-e53d8e21706e',
    'predecessor_label=urc-2024-25-dragons-type-diagnosis-20260826-b1',
    'predecessor_analysis_version=v5',
    'predecessor_classification_view_version=reporting_classification_2026-07-22_v2',
    'predecessor_cohort_view_version=analysis_window_2024-25_2026-07-25_v1',
    'predecessor_canonical_bundle_sha256=93fdd34371aac097c4364d3c64c32135fba7e3f235747b9daeb285335b330a8f',
    'predecessor_league_payload_sha256=47853342b5f999810bdb151a3e4757a982bbaf3d6b49f002ee19f53e0378cc56',
    'predecessor_team_payload_set_sha256=1563ac044888003751c0294df242b4b83fec811be0779d9a4c3d65ac6163234e',
    'active_correction_set_hash=b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051',
    'successor_analysis_version=v5',
    'successor_classification_view_version=reporting_classification_2024-25_2026-08-27_v1',
    'successor_cohort_view_version=analysis_window_2024-25_2026-07-25_v1'
  ]
)
on conflict (version) do nothing;

do $$
declare
  expected_statements text[] := array[
    'migration_sha256=480e990eb17805bb875afe2c13a97e4e2dd71832f40c243fd629a0c29074bd5b',
    'evidence_file_sha256=0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833',
    'specific_diagnosis_evidence_sha256=5855127dc199df1918cb906250809ad00b6f2d8ea03904a7ceee5d587996a753',
    'specific_diagnosis_mapping_rows_sha256=8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7',
    'successor_disclosure_method_sha256=9bd4ff3c60fb1aa33e3f4d1d1c5ff35f83bbd6cbd777aca90b6fbd3bc980de7c',
    'successor_disclosure_limitations_sha256=d8b32c5dddb9f740d238b44e4c40d099ed671ccc58bcdc95a5310471c78b75f9',
    'adjudication_manifest_sha256=cd5bed8cd5a98a6b5290194371fb92f01020ed8020ff3ddb859251741f349835',
    'source_master_sha256=15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63',
    'accepted_workbook_sha256=4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73',
    'adjudication_workbook_sha256=87ebb569afc45ef28116df98dc83c2d8799139eaecd1c249372c209fa783f155',
    'predecessor_release_id=8b50b9e2-023b-4f99-b6ae-e53d8e21706e',
    'predecessor_label=urc-2024-25-dragons-type-diagnosis-20260826-b1',
    'predecessor_analysis_version=v5',
    'predecessor_classification_view_version=reporting_classification_2026-07-22_v2',
    'predecessor_cohort_view_version=analysis_window_2024-25_2026-07-25_v1',
    'predecessor_canonical_bundle_sha256=93fdd34371aac097c4364d3c64c32135fba7e3f235747b9daeb285335b330a8f',
    'predecessor_league_payload_sha256=47853342b5f999810bdb151a3e4757a982bbaf3d6b49f002ee19f53e0378cc56',
    'predecessor_team_payload_set_sha256=1563ac044888003751c0294df242b4b83fec811be0779d9a4c3d65ac6163234e',
    'active_correction_set_hash=b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051',
    'successor_analysis_version=v5',
    'successor_classification_view_version=reporting_classification_2024-25_2026-08-27_v1',
    'successor_cohort_view_version=analysis_window_2024-25_2026-07-25_v1'
  ];
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260826100000'
      and migration.name = 'urc_2024_25_classification_monthly_successor'
      and migration.statements = expected_statements
  ) then
    raise exception '2024-25 classification successor registration is absent or checksum-mismatched';
  end if;
end;
$$;
