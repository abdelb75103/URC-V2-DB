select jsonb_build_object(
  'captured_at', now(),
  'target', jsonb_build_object(
    'database', current_database(),
    'role', current_user,
    'target_attested', (
      select target_attested
      from reporting.approved_dashboard_reader_target_v2
    )
  ),
  'injury_successor', (
    select jsonb_build_object(
      'version_id', version.id,
      'predecessor_version_id', version.predecessor_version_id,
      'master_rows', version.master_row_count,
      'included_rows', version.included_row_count,
      'dashboard_injury_rows', version.dashboard_injury_row_count,
      'review_required_rows', (
        select count(*)
        from lineage.injury_master_rows_v3 row_state
        where row_state.version_id = version.id
          and row_state.review_required
      ),
      'dashboard_classifications', (
        select jsonb_object_agg(classification, row_count order by classification)
        from (
          select master.final_classification as classification, count(*) as row_count
          from lineage.injury_inclusion_rows_v3 inclusion
          join lineage.injury_master_rows_v3 master
            on master.version_id = inclusion.version_id
           and master.source_row = inclusion.source_row
          where inclusion.version_id = version.id
            and inclusion.dashboard_eligible
          group by master.final_classification
        ) counts
      )
    )
    from lineage.injury_master_versions_v3 version
    where version.id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
  ),
  'active_v6_injury_cohort', jsonb_build_object(
    'rows', (select count(*) from analysis.analysis_window_injury_cohort_v6 where season = '2025-26'),
    'time_loss', (select count(*) from analysis.analysis_window_injury_cohort_v6 where season = '2025-26' and is_time_loss),
    'days_lost', (select coalesce(sum(days_lost), 0) from analysis.analysis_window_injury_cohort_v6 where season = '2025-26')
  ),
  'exposure', jsonb_build_object(
    'included_rows', (
      select count(*)
      from analysis.analysis_window_team_exposure_v6
      where season = '2025-26'
    ),
    'source_backed_hours', (
      select coalesce(sum(total_hours), 0)
      from analysis.analysis_window_team_exposure_completeness_v6
      where season = '2025-26'
        and denominator_available
    ),
    'source_backed_teams', (
      select count(*)
      from analysis.analysis_window_team_exposure_completeness_v6
      where season = '2025-26'
        and denominator_available
    )
  ),
  'team_releases', jsonb_build_object(
    'approved', (
      select count(*)
      from reporting.team_release_payloads_v6 payload
      join reporting.aggregate_releases release on release.id = payload.release_id
      where payload.season = '2025-26'
        and release.status = 'approved'
    ),
    'retired', (
      select count(*)
      from reporting.team_release_payloads_v6 payload
      join reporting.aggregate_releases release on release.id = payload.release_id
      where payload.season = '2025-26'
        and release.status = 'retired'
    )
  ),
  'served_bundle', (
    select jsonb_build_object(
      'release_id', bundle.release_id,
      'release_label', release.release_label,
      'bundle_payload_sha256', run.output_hash,
      'league_payload_sha256', payload.payload_sha256,
      'team_count', (
        select count(*)
        from reporting.league_release_members_v2 member
        where member.release_id = bundle.release_id
      )
    )
    from reporting.latest_approved_league_bundle_v6 bundle
    join reporting.aggregate_releases release on release.id = bundle.release_id
    join reporting.league_release_context_v2 context on context.release_id = bundle.release_id
    join reporting.league_release_payloads_v6 payload on payload.release_id = bundle.release_id
    join audit.pipeline_runs run on run.id = release.pipeline_run_id
    where bundle.season = '2025-26'
  ),
  'reader_counts', jsonb_build_object(
    'teams_2025_26', (
      select count(*) from reporting.latest_team_dashboard_v6 where season = '2025-26'
    ),
    'league_2025_26', (
      select count(*) from reporting.latest_league_dashboard_v6 where season = '2025-26'
    ),
    'teams_2024_25', (
      select count(*) from reporting.latest_team_dashboard_v6 where season = '2024-25'
    ),
    'league_2024_25', (
      select count(*) from reporting.latest_league_dashboard_v6 where season = '2024-25'
    )
  ),
  'successor_migrations', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'version', migration.version,
      'name', migration.name,
      'statements', migration.statements
    ) order by migration.version), '[]'::jsonb)
    from supabase_migrations.schema_migrations migration
    where migration.version between '20260822000000' and '20260830170000'
  )
);
