# Draft V3 inference-view promotion

This directory is deliberately outside `supabase/migrations/`. Nothing here has been applied, and the SQL is guarded so an accidental execution aborts before DDL.

`20260717_DRAFT_analysis_injury_inference_v3.sql` records the proposed versioned-view shape and the draft.5 rule catalogue. The executable review source remains `tools/sql/dashboard_v3_preview.sql`; promotion must copy the accepted rules exactly and prove row/count parity before this draft can become a real migration.

Promotion requires all of the following:

1. Abdel approves a recorded adjudication explaining the rule change, its scientific basis, accepted ambiguities, affected fields, season(s), and teams.
2. Every body-location and tissue/pathology output is rechecked against `docs/IOC_TAXONOMY_BUCKETS.csv`; source values remain unchanged and every derived value retains an origin/rule version.
3. The accepted SQL becomes a new timestamped migration under `supabase/migrations/` creating only `_v3` views. Frozen `_v1`/`_v2` views are never edited in place.
4. The exact hosted Supabase/Postgres target and each live write are separately confirmed and explicitly approved before migration or pipeline execution.
5. Preview, reconciliation, ambiguity-ledger, and migration rule catalogues are checksum- and row-parity checked. Every origin distribution must partition the same cohort exactly; ambiguous rows must remain Unknown unless adjudicated.
6. Every affected team/season is rerun through the versioned pipeline and re-released. Each release follows its applicable preflight/reconciliation/parity/sign-off/diff gate, with predecessor history retained rather than deleted.
7. Protected-alias checks, audit run/step/record events, before/after counts, parameters, input/output hashes, dependency version, and final reviewer are recorded.
8. The methodology, limitations, dashboard copy, and release documentation are updated to name V3, the inference precedence, the Unknown policy, and the restatement scope.
9. The `italian elite championship` non-URC marker and `injury_processing_2026-07-07_v2` rule identity are covered by a recorded adjudication before any team is reprocessed.

Do not promote by removing the guard alone. The draft view body must first be reconciled line-for-line with the accepted preview rule version.
