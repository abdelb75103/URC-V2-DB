with bundle as (
  select latest.release_id, latest.season
  from reporting.latest_approved_dashboard_bundle_v4 latest
  where latest.season = '2024-25'
), context as (
  select context.*
  from reporting.dashboard_bundle_context_v1 context
  join bundle on bundle.release_id = context.release_id
), league as (
  select payload.*
  from reporting.dashboard_bundle_league_payloads_v1 payload
  join bundle on bundle.release_id = payload.release_id
), teams as (
  select payload.*
  from reporting.dashboard_bundle_team_payloads_v1 payload
  join bundle on bundle.release_id = payload.bundle_release_id
)
select
  bundle.release_id,
  release.release_label,
  release.status,
  release.approved_at,
  bundle.season,
  context.analysis_version,
  context.classification_view_version,
  context.cohort_view_version,
  context.expected_member_count,
  league.payload_sha256 as league_payload_sha256,
  analysis.row_correction_bundle_hash_v1(bundle.release_id)
    as canonical_bundle_sha256,
  (select count(*)::integer from teams) as team_count,
  (
    select encode(
      extensions.digest(
        convert_to(
          string_agg(team_key || ':' || payload_sha256, E'\n' order by team_key),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
    from teams
  ) as team_payload_set_sha256,
  league.dashboard_payload -> 'analysis_window' as analysis_window,
  league.dashboard_payload -> 'headline' as headline,
  league.dashboard_payload -> 'coverage' as coverage,
  (
    select jsonb_agg(
      jsonb_build_object(
        'team_key', team_key,
        'payload_sha256', payload_sha256
      )
      order by team_key
    )
    from teams
  ) as team_payloads
from bundle
join reporting.aggregate_releases release on release.id = bundle.release_id
join context on context.release_id = bundle.release_id
join league on league.release_id = bundle.release_id;
