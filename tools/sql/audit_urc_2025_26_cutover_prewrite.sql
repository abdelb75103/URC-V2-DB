select jsonb_build_object(
  'target', jsonb_build_object(
    'database', current_database(),
    'database_role', current_user,
    'expected_database', 'postgres',
    'expected_project_ref', 'eukkvswaxweenovqqgzr'
  ),
  'cutover_migration_absent', not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260830170000'
  ),
  'required_constraints', (
    select jsonb_agg(
      jsonb_build_object(
        'table', conrelid::regclass::text,
        'name', conname,
        'definition', pg_get_constraintdef(oid, true)
      ) order by conrelid::regclass::text, conname
    )
    from pg_constraint
    where conrelid in (
      'reporting.team_release_payloads_v6'::regclass,
      'reporting.league_release_context_v2'::regclass
    )
      and conname in (
        'team_release_payloads_v6_classification_view_version_check',
        'team_release_payloads_v6_cohort_view_version_check',
        'league_release_context_v2_classification_view_version_check',
        'league_release_context_v2_classification_evidence',
        'league_release_context_v2_cohort_view_version_check',
        'league_release_context_v2_cohort_evidence'
      )
  ),
  'required_relation_columns', (
    select jsonb_agg(
      jsonb_build_object(
        'relation', table_schema || '.' || table_name,
        'columns', columns
      ) order by table_schema, table_name
    )
    from (
      select table_schema, table_name,
             jsonb_agg(column_name order by ordinal_position) as columns
      from information_schema.columns
      where (table_schema, table_name) in (
        ('analysis', 'analysis_window_team_hours_v6'),
        ('analysis', 'analysis_window_team_exposure_completeness_v6'),
        ('analysis', 'team_dashboard_release_candidates_analysis_window_v6'),
        ('reporting', 'team_release_payloads_v6'),
        ('reporting', 'league_release_context_v2'),
        ('lineage', 'injury_master_versions_v3'),
        ('lineage', 'injury_master_rows_v3'),
        ('lineage', 'injury_inclusion_rows_v3')
      )
      group by table_schema, table_name
    ) relations
  ),
  'successor_aggregate', (
    select jsonb_build_object(
      'version_id', version.id,
      'version_label', version.version_label,
      'manifest_sha256', version.manifest_sha256,
      'master_rows', version.master_row_count,
      'included_rows', version.included_row_count,
      'dashboard_rows', version.dashboard_injury_row_count,
      'review_required_rows', (
        select count(*)
        from lineage.injury_master_rows_v3 master
        where master.version_id = version.id
          and master.review_required
      )
    )
    from lineage.injury_master_versions_v3 version
    where version.id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
  ),
  'exposure_aggregate', (
    select jsonb_build_object(
      'teams', count(*),
      'league_hours', sum(total_hours),
      'source_backed_teams', count(*) filter (where team_key not in ('benetton', 'edinburgh')),
      'source_backed_hours', sum(total_hours) filter (where team_key not in ('benetton', 'edinburgh')),
      'estimated_hours', jsonb_object_agg(team_key, total_hours)
        filter (where team_key in ('benetton', 'edinburgh'))
    )
    from analysis.analysis_window_team_hours_v6
    where season = '2025-26'
  ),
  'future_lineage_relations_absent', jsonb_build_object(
    'candidate_snapshot', to_regclass('analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor') is null,
    'release_binding', to_regclass('reporting.team_release_injury_lineage_v1') is null,
    'successor_cohort', to_regclass('analysis.urc_2025_26_injury_successor_cohort_v1') is null
  ),
  'web_reader_has_private_lineage_access', (
    select coalesce(bool_or(has_table_privilege(
      'web_reader', quote_ident(table_schema) || '.' || quote_ident(table_name), 'select'
    )), false)
    from information_schema.tables
    where table_schema = 'lineage'
      and table_name in ('injury_master_versions_v3', 'injury_master_rows_v3', 'injury_inclusion_rows_v3')
  )
);
