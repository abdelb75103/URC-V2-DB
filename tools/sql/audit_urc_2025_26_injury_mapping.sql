with successor as (
  select master.*, inclusion.dashboard_eligible
  from lineage.injury_master_rows_v3 master
  join lineage.injury_inclusion_rows_v3 inclusion
    on inclusion.version_id = master.version_id
   and inclusion.source_row = master.source_row
  where master.version_id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
    and inclusion.dashboard_eligible
), source_files as (
  select source.id, source.team, source.file_name, source.file_sha256
  from ingestion.source_files source
  where source.season = '2025-26'
), exact_hash_matches as (
  select successor.source_row,
    count(distinct row_state.id) as matched_rows
  from successor
  join source_files source
    on source.file_sha256 = successor.source_artifact_sha256
  join ingestion.source_rows row_state
    on row_state.source_file_id = source.id
   and successor.source_row_number ~ '^\d+$'
   and row_state.source_row_number = successor.source_row_number::integer
  group by successor.source_row
), exact_filename_matches as (
  select successor.source_row,
    count(distinct row_state.id) as matched_rows
  from successor
  join source_files source
    on source.file_name = successor.source_file_name
  join ingestion.source_rows row_state
    on row_state.source_file_id = source.id
   and successor.source_row_number ~ '^\d+$'
   and row_state.source_row_number = successor.source_row_number::integer
  group by successor.source_row
), curated_source_membership as (
  select injury.source_row_id
  from analysis.analysis_window_active_builds_v6 build
  join curated.injuries injury
    on injury.curated_build_id = build.curated_build_id
   and injury.team_key = build.team_key
   and injury.season = build.season
  where build.season = '2025-26'
)
select jsonb_build_object(
  'successor_rows', (select count(*) from successor),
  'numeric_source_row_numbers', (
    select count(*) from successor where source_row_number ~ '^\d+$'
  ),
  'distinct_lineage_source_hashes', (
    select count(distinct source_artifact_sha256) from successor
  ),
  'lineage_hashes_present_in_ingestion', (
    select count(distinct successor.source_artifact_sha256)
    from successor
    join source_files source on source.file_sha256 = successor.source_artifact_sha256
  ),
  'hash_row_matches', jsonb_build_object(
    'exactly_one', (select count(*) from exact_hash_matches where matched_rows = 1),
    'ambiguous', (select count(*) from exact_hash_matches where matched_rows > 1),
    'unmatched', (
      select count(*) from successor
      left join exact_hash_matches match using (source_row)
      where match.source_row is null
    )
  ),
  'filename_row_matches', jsonb_build_object(
    'exactly_one', (select count(*) from exact_filename_matches where matched_rows = 1),
    'ambiguous', (select count(*) from exact_filename_matches where matched_rows > 1),
    'unmatched', (
      select count(*) from successor
      left join exact_filename_matches match using (source_row)
      where match.source_row is null
    )
  ),
  'hash_row_matches_in_active_curated_builds', (
    select count(*)
    from successor
    join source_files source
      on source.file_sha256 = successor.source_artifact_sha256
    join ingestion.source_rows row_state
      on row_state.source_file_id = source.id
     and successor.source_row_number ~ '^\d+$'
     and row_state.source_row_number = successor.source_row_number::integer
    join curated_source_membership curated
      on curated.source_row_id = row_state.id
  )
);
