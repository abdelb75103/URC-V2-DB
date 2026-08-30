-- Register the additive V3 injury-authority cutover only after its private
-- snapshot and source-bound candidate remain complete.

do $$
begin
  if to_regclass('analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor') is null
    or to_regclass('reporting.team_release_injury_lineage_v1') is null
    or not exists (
      select 1 from analysis.accepted_urc_2025_26_injury_successor_evidence_v1
      where successor_version_id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
        and successor_classification_identity = 'reporting_classification_2025-26_2026-08-30_v2'
        and successor_cohort_identity = 'injury_lineage_2025-26_2026-08-30_v2'
        and migration_sha256 = '76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a'
        and manifest_sha256 = '7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab'
        and delta_payload_sha256 = '111328427560503939a66e845d4a6e0fb8fa606f9dbf4a6f508aa0df04cab637'
        and delta_evidence_sha256 = 'f9e8d82998232a2e7e6f7325f319a685546197b4f4c3ff022f366fafa854c78a'
        and master_row_count = 2993 and included_row_count = 1923
        and dashboard_injury_row_count = 1484 and team_count = 16
    )
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1) <> 1484
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1 where is_time_loss) <> 877
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1 where not is_time_loss) <> 607
    or (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1 where is_time_loss and days_lost is not null) <> 731
    or (select coalesce(sum(days_lost), 0) from analysis.urc_2025_26_injury_successor_rows_v1 where is_time_loss) <> 19047
    or (select count(*) from analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor where snapshot_version = '20260830170000') <> 16
    or (select count(*) from analysis.team_dashboard_release_candidates_analysis_window_v6 where season = '2025-26') <> 16
    or has_table_privilege('web_reader', 'lineage.injury_master_rows_v3', 'select')
    or has_table_privilege('web_reader', 'analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor', 'select')
    or has_table_privilege('web_reader', 'reporting.team_release_injury_lineage_v1', 'select')
  then
    raise exception 'Year 2 injury-successor cutover is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830170000',
  'urc_2025_26_injury_successor_cutover',
  array[
    'migration_sha256=3df4c44f3e49cad5b2589d4bd6346a7274b11155c20fa30cb582b2a2231ad99e',
    'injury_successor_version_id=2f419706-8c36-58dd-b4cb-e92162e782b8',
    'classification_view_version=reporting_classification_2025-26_2026-08-30_v2',
    'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260830170000'
      and name = 'urc_2025_26_injury_successor_cutover'
      and statements = array[
        'migration_sha256=3df4c44f3e49cad5b2589d4bd6346a7274b11155c20fa30cb582b2a2231ad99e',
        'injury_successor_version_id=2f419706-8c36-58dd-b4cb-e92162e782b8',
        'classification_view_version=reporting_classification_2025-26_2026-08-30_v2',
        'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2'
      ]
  ) then
    raise exception 'Year 2 injury-successor cutover registration is invalid';
  end if;
end;
$$;
