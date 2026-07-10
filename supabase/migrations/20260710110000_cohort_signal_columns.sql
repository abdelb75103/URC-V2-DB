-- Phase 3.5: cohort-signal capture (Adjudication 4, 10 July 2026,
-- data/reporting/analysis_parity_adjudications_2026-07-10.json). Adds two
-- nullable curated.injuries columns that make the two documented
-- analysis.injury_cohort_v1 gaps (see 20260710100000_analysis_views_v1.sql
-- header, gaps (1) and (2)) queryable without the protected team-alias map
-- or the raw Match Type marker scan at report time.
--
-- Both columns are populated ONLY by process-intake, from
-- processing.record_versions.record_state ->> 'received_in_team_status' /
-- 'urc_match_scope' (pipeline/__main__.py received_in_team_status() /
-- urc_match_scope()), which derive the category in memory against the
-- Git-ignored data/intake/team_alias_map.json and the existing
-- NON_URC_MATCH_TYPE_MARKERS list. The protected alias value itself is
-- never stored in either column, nor anywhere else in this schema: only
-- the resulting controlled category. Existing curated.injuries rows (built
-- from a record_version written before this migration) get NULL for both
-- columns -- record_state has no such key yet, so
-- record_state ->> 'key' evaluates to SQL NULL. analysis.injury_cohort_v1's
-- amendment (20260710120000_injury_cohort_v1_amendment.sql) treats NULL as
-- non-excluding, so this migration alone changes no published number; a
-- team's cohort output changes only once that team's injuries are
-- reprocessed (process-intake rerun) and its curated build is rebuilt.
--
-- Validation pattern: plain CHECK constraints (matching curated.exposure's
-- grain / scope_status columns), not curated.code_lists. These two
-- categories are not part of the IOC 2020 taxonomy and are not reused by
-- any other curated column, so the code_lists composite-FK disambiguation
-- machinery (see 20260709233356_curated_layer.sql header) is not needed
-- here.

alter table curated.injuries
  add column received_in_team_status text
    check (received_in_team_status in ('own_team', 'other_team', 'club', 'missing')),
  add column urc_match_scope text
    check (urc_match_scope in ('urc', 'non_urc_marker', 'training', 'unknown'));

comment on column curated.injuries.received_in_team_status is
  'Phase 3.5 cohort signal. Reproduces the dashboard exclusion check '
  'injury_cohort_exclusion_reasons()''s "received_or_injured_in_other_team" '
  'reason as a stored category: own_team only on an exact match to this '
  'team''s own protected alias; club is broken out from other_team for '
  'audit readability. NULL means not yet (re)computed for this row (built '
  'from a pre-Phase-3.5 record_version), never "computed, blank source '
  'value" -- that case is the literal value ''missing''.';

comment on column curated.injuries.urc_match_scope is
  'Phase 3.5 cohort signal. Reproduces the dashboard exclusion check '
  'injury_cohort_exclusion_reasons()''s "explicit_non_urc_match_type" '
  'reason (the NON_URC_MATCH_TYPE_MARKERS scan over Match Type) as a '
  'stored category. NULL means not yet (re)computed for this row, never '
  '"Match Type missing" -- that case is the literal value ''unknown''.';

-- Controlled reason code for the process-intake events that populate these
-- two columns (action 'derive', field_name received_in_team_status /
-- urc_match_scope). Migration-seeded only (not self-seeded by
-- process-intake's per-run baseline insert), matching the
-- adjudication_reapplied precedent in
-- 20260710000137_adjudication_reapplication.sql: process-intake refuses to
-- run until this migration has been applied.
insert into audit.reason_codes (code, description) values
  (
    'cohort_signal_derivation',
    'Curated cohort-signal category (received_in_team_status or '
    'urc_match_scope) derived deterministically at process-intake from the '
    'source "Received/Injured In Team" or "Match Type" column, compared '
    'against the protected team alias map or the non-URC match-type '
    'marker list. Only the resulting category is stored; the alias value '
    'itself is never persisted. Added by the Phase 3.5 cohort-signal fix '
    '(Adjudication 4, 10 July 2026).'
  )
on conflict (code) do nothing;
