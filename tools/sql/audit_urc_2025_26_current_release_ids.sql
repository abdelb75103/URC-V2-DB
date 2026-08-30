select jsonb_build_object(
  'migration_1700', (
    select jsonb_build_object(
      'version', version,
      'name', name,
      'statements', statements
    )
    from supabase_migrations.schema_migrations
    where version = '20260830170000'
  ),
  'approved_team_releases', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'team_key', payload.team_key,
      'release_id', payload.release_id,
      'release_label', release.release_label,
      'payload_sha256', payload.payload_sha256,
      'classification_view_version', payload.classification_view_version,
      'cohort_view_version', payload.cohort_view_version,
      'lineage_version_id', lineage.lineage_version_id,
      'lineage_snapshot_version', lineage.candidate_snapshot_version,
      'lineage_member_sha256', lineage.member_sha256
    ) order by payload.team_key), '[]'::jsonb)
    from reporting.team_release_payloads_v6 payload
    join reporting.aggregate_releases release on release.id = payload.release_id
    left join reporting.team_release_injury_lineage_v1 lineage
      on lineage.release_id = payload.release_id
     and lineage.team_key = payload.team_key
     and lineage.season = payload.season
    where payload.season = '2025-26'
      and release.status = 'approved'
  ),
  'current_league_bundle', (
    select jsonb_build_object(
      'release_id', bundle.release_id,
      'release_label', release.release_label,
      'classification_view_version', context.classification_view_version,
      'cohort_view_version', context.cohort_view_version,
      'league_payload_sha256', payload.payload_sha256,
      'approved_at', release.approved_at
    )
    from reporting.latest_approved_league_bundle_v6 bundle
    join reporting.aggregate_releases release on release.id = bundle.release_id
    join reporting.league_release_context_v2 context on context.release_id = bundle.release_id
    join reporting.league_release_payloads_v6 payload on payload.release_id = bundle.release_id
    where bundle.season = '2025-26'
  ),
  'new_tuple_league_releases', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'release_id', context.release_id,
      'release_label', release.release_label,
      'status', release.status,
      'classification_view_version', context.classification_view_version,
      'cohort_view_version', context.cohort_view_version
    ) order by release.created_at), '[]'::jsonb)
    from reporting.league_release_context_v2 context
    join reporting.aggregate_releases release on release.id = context.release_id
    where context.season = '2025-26'
      and context.classification_view_version = 'reporting_classification_2025-26_2026-08-30_v2'
      and context.cohort_view_version = 'injury_lineage_2025-26_2026-08-30_v2'
  )
);
