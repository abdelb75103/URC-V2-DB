-- Controlled reason code for the backfill-standing-adjudications command.
-- Reason codes are controlled: seed by migration, never ad hoc inside a
-- pipeline command.
--
-- Context: the audit.adjudications insert was only added to
-- adjudicate-duplicate-exclusion in commit 6e4c50f (Glasgow release,
-- 7 July 2026 evening). The Leinster (row 48), Ulster (row 18) and
-- Connacht (row 125) adjudication runs that morning therefore recorded
-- their decisions in audit.pipeline_runs.parameters, audit.record_events
-- and processing.record_versions, but never registered a standing decision
-- row in audit.adjudications. Without that row, the adjudication-
-- reapplication safety net (reason code 'adjudication_reapplied', migration
-- 20260710000137) cannot protect those rows on a future process-intake
-- rerun. The backfill command copies each decision verbatim from the
-- recorded evidence into audit.adjudications; it changes no record state.

insert into audit.reason_codes (code, description) values
  (
    'standing_adjudication_backfill',
    'Evidence-based backfill of a standing decision into audit.adjudications '
    'for an adjudication run that predates the adjudications-table insert in '
    'the adjudicate command; the decision JSON is copied verbatim from the '
    'recorded pipeline run, record events, and record version state, and no '
    'record state is changed.'
  )
on conflict (code) do nothing;
