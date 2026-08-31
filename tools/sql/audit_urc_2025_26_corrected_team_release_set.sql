with approved as (
  select payload.release_id, payload.team_key, payload.curated_build_id,
    payload.payload_sha256, payload.dashboard_payload,
    payload.classification_view_version,
    payload.classification_evidence_sha256,
    payload.cohort_view_version, payload.cohort_evidence_sha256,
    binding.lineage_version_id,
    binding.candidate_snapshot_version,
    binding.member_sha256
  from reporting.team_release_payloads_v6 payload
  join reporting.aggregate_releases release on release.id = payload.release_id
  join reporting.team_release_injury_lineage_v1 binding
    on binding.release_id = payload.release_id
  where payload.season = '2025-26'
    and release.status = 'approved'
), headlines as (
  select approved.release_id, approved.team_key,
    max((headline ->> 'value')::numeric)
      filter (where headline ->> 'key' = 'recorded_injuries')
      as recorded_injuries,
    max((headline ->> 'value')::numeric)
      filter (where headline ->> 'key' = 'time_loss_injuries')
      as time_loss_injuries,
    max((headline ->> 'numerator')::numeric)
      filter (where headline ->> 'key' = 'severity_mean_days')
      as days_lost,
    max((headline ->> 'denominator')::numeric)
      filter (where headline ->> 'key' = 'severity_mean_days')
      as known_duration_time_loss_injuries
  from approved
  cross join lateral jsonb_array_elements(
    approved.dashboard_payload -> 'headline'
  ) headline
  group by approved.release_id, approved.team_key
), family_audit as (
  select count(*) filter (
      where family ->> 'mapping_version' <>
        'injury_type_family_2026-07-21_v1'
    ) as wrong_mapping_version_rows,
    count(*) filter (
      where family ->> 'code' = 'unmapped_review'
    ) as unmapped_review_rows
  from approved
  cross join lateral jsonb_array_elements(
    approved.dashboard_payload -> 'injury_type_families'
  ) family
)
select jsonb_build_object(
  'release_count', (select count(*) from approved),
  'team_count', (select count(distinct team_key) from approved),
  'recorded_injuries', (select sum(recorded_injuries) from headlines),
  'time_loss_injuries', (select sum(time_loss_injuries) from headlines),
  'known_duration_time_loss_injuries', (
    select sum(known_duration_time_loss_injuries) from headlines
  ),
  'days_lost', (select sum(days_lost) from headlines),
  'wrong_mapping_version_rows', family_audit.wrong_mapping_version_rows,
  'unmapped_review_rows', family_audit.unmapped_review_rows,
  'members', (
    select jsonb_agg(jsonb_build_object(
      'team_key', team_key,
      'release_id', release_id,
      'curated_build_id', curated_build_id,
      'payload_sha256', payload_sha256,
      'classification_view_version', classification_view_version,
      'classification_evidence_sha256', classification_evidence_sha256,
      'cohort_view_version', cohort_view_version,
      'cohort_evidence_sha256', cohort_evidence_sha256,
      'lineage_version_id', lineage_version_id,
      'candidate_snapshot_version', candidate_snapshot_version,
      'member_sha256', member_sha256
    ) order by team_key)
    from approved
  )
) as corrected_team_release_set
from family_audit;
