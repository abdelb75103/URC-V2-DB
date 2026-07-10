-- Controlled reason code for automatic reapplication of a standing
-- audit.adjudications decision when process-intake/process-exposure rerun
-- and recompute processing.record_versions. Reason codes are controlled:
-- seed by migration, never ad hoc inside a pipeline command.
--
-- Per AGENTS.md's audit trail contract: "Manual corrections must enter
-- through a recorded adjudication table/file and then be reapplied by the
-- pipeline." Before this fix, a process-intake rerun recomputed every row's
-- eligibility_status from build_processing_state alone and never consulted
-- audit.adjudications, so a prior adjudicated exclusion could be silently
-- dropped by the next rerun. Verified read-only on 10 July 2026 against live
-- data: Leinster row 48, Ulster row 18 and Connacht row 125 each show this
-- exact pattern in processing.record_versions -- version 2 carried the
-- adjudicated 'excluded_duplicate_adjudicated' status, a later process-
-- intake rerun's version 3 silently reverted it to 'review_required', and an
-- operator had to manually rerun adjudicate-duplicate-exclusion a second
-- time (version 4) to restore it. That manual workaround is exactly the gap
-- this reason code and its pipeline hook close automatically.

insert into audit.reason_codes (code, description) values
  (
    'adjudication_reapplied',
    'A standing audit.adjudications decision was reapplied to a new '
    'processing.record_versions row created by a process-intake or '
    'process-exposure rerun (or by the reapply-adjudications backfill '
    'command), preserving the adjudicated eligibility state instead of '
    'silently reverting it to the freshly computed value.'
  )
on conflict (code) do nothing;
