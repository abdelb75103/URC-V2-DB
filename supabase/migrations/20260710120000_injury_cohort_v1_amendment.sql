-- Phase 3.5 pre-freeze amendment to analysis.injury_cohort_v1
-- (Adjudication 4, 10 July 2026,
-- data/reporting/analysis_parity_adjudications_2026-07-10.json):
-- "Since _v1 is not frozen until Phase 6, the plan permits amending
-- injury_cohort_v1 by a versioned migration (create or replace + documented
-- amendment header) rather than proliferating _v2 pre-freeze -- recorded as
-- the chosen mechanism." This is the only _v1 view this migration touches;
-- every other analysis.*_v1 view is untouched and picks up the amendment
-- automatically at query time because they read injury_cohort_v1 by name.
--
-- What changes: closes the two documented gaps in
-- 20260710100000_analysis_views_v1.sql's header (gaps (1) and (2)) now that
-- curated.injuries carries received_in_team_status / urc_match_scope
-- (20260710110000_cohort_signal_columns.sql). Two new WHERE filters are
-- added, and the two new columns are exposed at the end of the SELECT list
-- (Postgres allows create-or-replace to append trailing columns to a view
-- without dropping it, but not to reorder or remove existing ones -- every
-- pre-existing column below is unchanged in name, position, and type).
--
-- NULL-safe by construction: a NULL received_in_team_status/urc_match_scope
-- (any curated.injuries row built from a record_version written before
-- 20260710110000, i.e. every team except a reprocessed-and-rebuilt one)
-- passes both new filters unconditionally. Until a team is reprocessed
-- (process-intake rerun) and rebuilt (build-curated --rebuild), this
-- amendment changes zero rows of its cohort. Verified read-only intent, 10
-- July 2026: connacht/leinster/munster/ulster's "Received/Injured In Team"
-- source column is entirely blank (would resolve to 'missing' even if
-- reprocessed) and glasgow's old dashboard-run exclusions are already
-- folded into eligibility_status by its analysis-audit-file reapplication,
-- so none of the five needs reprocessing for this amendment to apply
-- correctly; only edinburgh is reprocessed under this phase.
--
-- Interpretation decision flagged for orchestrator/Abdel sign-off before
-- live execution: the received_in_team_status filter excludes BOTH
-- 'other_team' and 'club', not only 'other_team'. This reproduces
-- injury_cohort_exclusion_reasons()'s actual current-rule behaviour exactly
-- -- that function excludes on "not missing AND not an exact match to the
-- team's own alias", so a literal 'Club' value is excluded today exactly
-- like a different team's alias is. Treating 'club' as non-excluding here
-- would NOT reproduce the current rule and would silently retain rows the
-- live dashboard code presently drops. 'club' stays a distinct stored
-- category (not collapsed into 'other_team') purely for audit readability;
-- a future _v2 view is where the protocol would decide to treat it
-- differently.
--
-- urc_match_scope's 'urc' bucket means "not excluded by the
-- NON_URC_MATCH_TYPE_MARKERS scan", not "confirmed URC competition" -- it
-- also catches values like 'Other' that the current rule never positively
-- verifies either. This is an inherited imprecision from the rule being
-- reproduced, not a new one introduced here.

create or replace view analysis.injury_cohort_v1
with (security_invoker = true) as
with exposure_window as (
  select
    e.team_key,
    e.season,
    min(coalesce(e.session_date, e.week_start_date)) as coverage_start,
    max(coalesce(e.session_date, e.week_start_date))
      + case when count(distinct e.grain) = 1 and min(e.grain) = 'weekly' then 6 else 0 end
      as coverage_end
  from curated.exposure e
  join curated.builds b on b.id = e.curated_build_id and b.status = 'active'
  where e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date) is not null
  group by e.team_key, e.season
)
select
  i.id as injury_id,
  i.team_key,
  i.season,
  i.source_row_id,
  i.record_version_id,
  i.curated_build_id,
  i.player_uid,
  i.injury_uid,
  i.date_injured,
  i.days_injured,
  coalesce(i.days_injured, 0) as days_lost,
  coalesce(i.days_injured, 0) > 0 as is_time_loss,
  i.is_closed,
  i.activity_context,
  case i.activity_context
    when 'urc_match' then 'match'
    when 'match' then 'match'
    when 'training' then 'training'
    else 'unknown'
  end as setting_label,
  i.contact_context,
  i.recurrence_status,
  coalesce(i.severity_category, 'unknown_or_censored') as severity_category,
  coalesce(sc.label, 'Unknown') as severity_label,
  coalesce(i.body_location, 'unknown') as body_location,
  coalesce(bl.label, 'Unknown') as body_location_label,
  coalesce(i.injury_type, 'unknown') as injury_type,
  coalesce(it.label, 'Unknown') as injury_type_label,
  i.problem_type,
  i.eligibility_status,
  w.coverage_start,
  w.coverage_end,
  i.received_in_team_status,
  i.urc_match_scope
from curated.injuries i
join curated.builds b on b.id = i.curated_build_id and b.status = 'active'
join exposure_window w on w.team_key = i.team_key and w.season = i.season
left join curated.code_lists sc
  on sc.list_name = 'severity_category' and sc.code = coalesce(i.severity_category, 'unknown_or_censored')
left join curated.code_lists bl
  on bl.list_name = 'body_location' and bl.code = coalesce(i.body_location, 'unknown')
left join curated.code_lists it
  on it.list_name = 'injury_type' and it.code = coalesce(i.injury_type, 'unknown')
where i.eligibility_status not in ('excluded_from_analysis', 'excluded_duplicate_adjudicated')
  and i.problem_type = 'injury'
  and i.date_injured is not null
  and i.date_injured >= w.coverage_start
  and i.date_injured <= w.coverage_end
  -- Phase 3.5 filter 1 of 2: reproduces
  -- injury_cohort_exclusion_reasons()'s received_or_injured_in_other_team
  -- check. NULL (not yet computed for this team) passes through unchanged.
  and (i.received_in_team_status is null or i.received_in_team_status not in ('other_team', 'club'))
  -- Phase 3.5 filter 2 of 2: reproduces
  -- injury_cohort_exclusion_reasons()'s explicit_non_urc_match_type check.
  -- NULL (not yet computed for this team) passes through unchanged.
  and (i.urc_match_scope is null or i.urc_match_scope <> 'non_urc_marker');

comment on view analysis.injury_cohort_v1 is
  'Frozen injury eligibility cohort (IOC 2020 / STROBE-SIIS), amended '
  '10 July 2026 (Phase 3.5, Adjudication 4) to add the two curated cohort '
  'signals that close analysis_views_v1''s documented gaps: '
  'received_in_team_status (excludes other_team and club) and '
  'urc_match_scope (excludes non_urc_marker), both NULL-safe so teams not '
  'yet reprocessed under the new signal are unaffected. See this '
  'migration''s header for the full amendment rationale and the flagged '
  'club-inclusion interpretation.';
