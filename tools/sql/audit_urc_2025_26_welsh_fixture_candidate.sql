with corrected_totals as (
  select
    count(*) as recorded_injuries,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    count(*) filter (where is_time_loss and days_lost is not null)
      as known_duration_time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
), decision_totals as (
  select
    count(*) as decision_rows,
    count(*) filter (where team_key = 'cardiff') as cardiff_rows,
    count(*) filter (where team_key = 'dragons') as dragons_rows
  from audit.urc_2025_26_fixture_reconciliation_decisions_v1
), candidate_audit as (
  select
    count(*) as candidate_teams,
    count(*) filter (
      where candidate.dashboard <> predecessor.dashboard
    ) as changed_teams,
    count(*) filter (
      where candidate.team_key not in ('cardiff', 'dragons')
        and candidate.dashboard = predecessor.dashboard
    ) as unchanged_other_teams,
    count(*) filter (
      where candidate.payload_sha256 <>
        reporting.canonical_jsonb_sha256_v1(candidate.dashboard)
    ) as invalid_payload_hashes
  from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
  join analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract predecessor
    using (team_key, season, curated_build_id)
), match_metrics as (
  select jsonb_object_agg(candidate.team_key, setting) as affected_teams
  from analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture candidate
  cross join lateral jsonb_array_elements(candidate.dashboard -> 'setting_metrics') setting
  where candidate.team_key in ('cardiff', 'dragons')
    and setting ->> 'setting' = 'match'
)
select jsonb_build_object(
  'decision_rows', decision_totals.decision_rows,
  'cardiff_rows', decision_totals.cardiff_rows,
  'dragons_rows', decision_totals.dragons_rows,
  'recorded_injuries', corrected_totals.recorded_injuries,
  'time_loss_injuries', corrected_totals.time_loss_injuries,
  'known_duration_time_loss_injuries',
    corrected_totals.known_duration_time_loss_injuries,
  'days_lost', corrected_totals.days_lost,
  'candidate_teams', candidate_audit.candidate_teams,
  'changed_teams', candidate_audit.changed_teams,
  'unchanged_other_teams', candidate_audit.unchanged_other_teams,
  'invalid_payload_hashes', candidate_audit.invalid_payload_hashes,
  'affected_team_match_metrics', match_metrics.affected_teams,
  'web_reader_can_select_private_candidate', has_table_privilege(
    'web_reader',
    'analysis.team_dashboard_release_candidate_snapshot_v6_20260831_welsh_fixture',
    'select'
  ),
  'web_reader_can_select_private_decisions', has_table_privilege(
    'web_reader',
    'audit.urc_2025_26_fixture_reconciliation_decisions_v1',
    'select'
  )
) as audit
from corrected_totals
cross join decision_totals
cross join candidate_audit
cross join match_metrics;
