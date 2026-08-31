with current_bundle as (
  select bundle.release_id, bundle.season,
    release.release_label, release.status, release.approved_at,
    context.analysis_version, context.classification_view_version,
    context.classification_evidence_sha256,
    context.cohort_view_version, context.cohort_evidence_sha256,
    context.decision_recorded_at,
    payload.payload_sha256 as league_payload_sha256,
    payload.dashboard_payload as dashboard
  from reporting.latest_approved_league_bundle_v6 bundle
  join reporting.aggregate_releases release on release.id = bundle.release_id
  join reporting.league_release_context_v2 context
    on context.release_id = bundle.release_id
  join reporting.league_release_payloads_v6 payload
    on payload.release_id = bundle.release_id
  where bundle.season = '2025-26'
), member_audit as (
  select count(*) as member_count,
    count(distinct member.team_key) as team_count,
    count(*) filter (
      where payload.payload_sha256 <>
        reporting.canonical_jsonb_sha256_v1(payload.dashboard_payload)
    ) as invalid_payload_hashes
  from current_bundle bundle
  join reporting.league_release_members_v2 member
    on member.release_id = bundle.release_id
  join reporting.team_dashboard_payloads_v2 payload
    on payload.bundle_release_id = bundle.release_id
   and payload.team_key = member.team_key
   and payload.team_release_id = member.team_release_id
   and payload.curated_build_id = member.curated_build_id
), headline as (
  select max((item ->> 'value')::numeric)
      filter (where item ->> 'key' = 'recorded_injuries')
      as recorded_injuries,
    max((item ->> 'value')::numeric)
      filter (where item ->> 'key' = 'time_loss_injuries')
      as time_loss_injuries,
    max((item ->> 'numerator')::numeric)
      filter (where item ->> 'key' = 'severity_mean_days')
      as days_lost,
    max((item ->> 'denominator')::numeric)
      filter (where item ->> 'key' = 'severity_mean_days')
      as known_duration_time_loss_injuries
  from current_bundle bundle
  cross join lateral jsonb_array_elements(bundle.dashboard -> 'headline') item
), presentation_audit as (
  select count(*) filter (
      where family ->> 'mapping_version' <>
        'injury_type_family_2026-07-21_v1'
    ) as wrong_mapping_version_rows,
    count(*) filter (
      where family ->> 'code' = 'unmapped_review'
    ) as unmapped_review_rows,
    (
      select count(*)
      from current_bundle monthly_bundle
      cross join lateral jsonb_array_elements(
        monthly_bundle.dashboard -> 'monthly'
      ) month
      where month -> 'exposure_hours' <> 'null'::jsonb
        or month -> 'distance_km' <> 'null'::jsonb
        or month -> 'overall_incidence_per_1000h' <> 'null'::jsonb
        or month -> 'incidence_per_1000h' <> 'null'::jsonb
        or month -> 'burden_per_1000h' <> 'null'::jsonb
    ) as invalid_monthly_estimate_rows
  from current_bundle bundle
  cross join lateral jsonb_array_elements(
    bundle.dashboard -> 'injury_type_families'
  ) family
), reader_audit as (
  select
    (select count(*) from reporting.latest_league_dashboard_v6
      where season = '2025-26') as league_reader_rows,
    (select count(*) from reporting.latest_team_dashboard_v6
      where season = '2025-26') as team_reader_rows,
    (select count(*) from reporting.latest_dashboard_cache_token_v2
      where season = '2025-26') as cache_token_rows
), privacy_audit as (
  select
    has_table_privilege(
      'web_reader',
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000',
      'select'
    ) as reader_can_select_private_league_candidate,
    has_table_privilege(
      'web_reader',
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract',
      'select'
    ) as reader_can_select_private_team_candidate,
    has_table_privilege(
      'web_reader', 'reporting.team_release_payloads_v6', 'select'
    ) as reader_can_select_private_team_releases
)
select jsonb_build_object(
  'release_id', current_bundle.release_id,
  'release_label', current_bundle.release_label,
  'status', current_bundle.status,
  'approved_at', current_bundle.approved_at,
  'analysis_version', current_bundle.analysis_version,
  'classification_view_version', current_bundle.classification_view_version,
  'classification_evidence_sha256',
    current_bundle.classification_evidence_sha256,
  'cohort_view_version', current_bundle.cohort_view_version,
  'cohort_evidence_sha256', current_bundle.cohort_evidence_sha256,
  'decision_recorded_at', current_bundle.decision_recorded_at,
  'league_payload_sha256', current_bundle.league_payload_sha256,
  'league_payload_hash_valid', current_bundle.league_payload_sha256 =
    reporting.canonical_jsonb_sha256_v1(current_bundle.dashboard),
  'member_count', member_audit.member_count,
  'team_count', member_audit.team_count,
  'invalid_member_payload_hashes', member_audit.invalid_payload_hashes,
  'recorded_injuries', headline.recorded_injuries,
  'time_loss_injuries', headline.time_loss_injuries,
  'known_duration_time_loss_injuries',
    headline.known_duration_time_loss_injuries,
  'days_lost', headline.days_lost,
  'wrong_mapping_version_rows',
    presentation_audit.wrong_mapping_version_rows,
  'unmapped_review_rows', presentation_audit.unmapped_review_rows,
  'invalid_monthly_estimate_rows',
    presentation_audit.invalid_monthly_estimate_rows,
  'league_reader_rows', reader_audit.league_reader_rows,
  'team_reader_rows', reader_audit.team_reader_rows,
  'cache_token_rows', reader_audit.cache_token_rows,
  'reader_can_select_private_league_candidate',
    privacy_audit.reader_can_select_private_league_candidate,
  'reader_can_select_private_team_candidate',
    privacy_audit.reader_can_select_private_team_candidate,
  'reader_can_select_private_team_releases',
    privacy_audit.reader_can_select_private_team_releases,
  'predecessor_status', (
    select status from reporting.aggregate_releases
    where id = '6c3cdfb3-450a-4c5c-b099-b343561d56d8'::uuid
  )
) as post_release_audit
from current_bundle
cross join member_audit
cross join headline
cross join presentation_audit
cross join reader_audit
cross join privacy_audit;
