select jsonb_build_object(
  'lineage_master_v3_columns', (
    select jsonb_agg(jsonb_build_object(
      'name', column_name,
      'type', data_type,
      'nullable', is_nullable
    ) order by ordinal_position)
    from information_schema.columns
    where table_schema = 'lineage'
      and table_name = 'injury_master_rows_v3'
  ),
  'lineage_inclusion_v3_columns', (
    select jsonb_agg(jsonb_build_object(
      'name', column_name,
      'type', data_type,
      'nullable', is_nullable
    ) order by ordinal_position)
    from information_schema.columns
    where table_schema = 'lineage'
      and table_name = 'injury_inclusion_rows_v3'
  ),
  'active_build_columns', (
    select jsonb_agg(jsonb_build_object(
      'name', column_name,
      'type', data_type
    ) order by ordinal_position)
    from information_schema.columns
    where table_schema = 'analysis'
      and table_name = 'analysis_window_active_builds_v6'
  ),
  'current_cohort_columns', (
    select jsonb_agg(jsonb_build_object(
      'name', column_name,
      'type', data_type
    ) order by ordinal_position)
    from information_schema.columns
    where table_schema = 'analysis'
      and table_name = 'analysis_window_injury_cohort_v6'
  ),
  'current_cohort_definition', pg_get_viewdef(
    'analysis.analysis_window_injury_cohort_v6'::regclass,
    true
  ),
  'reporting_classification_definition', pg_get_viewdef(
    'analysis.analysis_window_reporting_classification_v6'::regclass,
    true
  ),
  'lineage_version_definition', (
    select jsonb_build_object(
      'column_names', jsonb_agg(column_name order by ordinal_position)
    )
    from information_schema.columns
    where table_schema = 'lineage'
      and table_name = 'injury_master_versions_v3'
  ),
  'ingestion_source_file_columns', (
    select jsonb_agg(jsonb_build_object(
      'name', column_name,
      'type', data_type
    ) order by ordinal_position)
    from information_schema.columns
    where table_schema = 'ingestion'
      and table_name = 'source_files'
  ),
  'ingestion_source_row_columns', (
    select jsonb_agg(jsonb_build_object(
      'name', column_name,
      'type', data_type
    ) order by ordinal_position)
    from information_schema.columns
    where table_schema = 'ingestion'
      and table_name = 'source_rows'
  ),
  'lineage_row_value_keys', (
    select jsonb_agg(key order by key)
    from (
      select distinct jsonb_object_keys(master.row_values) as key
      from lineage.injury_master_rows_v3 master
      where master.version_id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
    ) keys
  )
);
