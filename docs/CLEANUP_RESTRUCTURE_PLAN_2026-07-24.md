# URC 2024-25 Data Workflow: Cleanup and Restructure Plan

Date: 2026-07-24. Status: **COMPLETE, all six phases executed 2026-07-24.** Phases 0 to 3 and 6 landed first; Phase 4 promoted the restated bundle `urc-2024-25-v4-6f04bd64d2a6-a2` after Abdel's recorded yes on the diff summary; Phase 5 deleted 93 items (354.5 MB) per the manifest below with Abdel's approval. See `docs/PIPELINE_RULE_CHANGELOG.md`, entry "2026-07-24: 2024-25 lineage restatement released, and Phase 5 cleanup executed", for the released figures, the equivalence argument for the performance-only migration, and the recorded deviation on ledger-evidence marking. This document is retained as the plan of record; it is not a live task list.

Both hard gates are closed. Two items deliberately remain open and are not part of this plan: the ledger `open_items` (source rows 1735 and 210) await Abdel's adjudication, and the access-control restoration gate in `AGENTS.md` is untouched.

This plan superseded the workflow described in the former AGENTS.md section "Included Dataset Column Cleanup" and the heavyweight per-release ceremony for this lineage. Phase 6 completed that AGENTS.md rewrite, so the temporary precedence this plan held over AGENTS.md has lapsed: **AGENTS.md is now the binding contract and governs where the two differ.** Scientific rules (IOC buckets, no imputation, preserve source values, pseudonymisation, privacy) are unchanged and still binding.

## Decisions locked (Abdel, 2026-07-24)

1. The human-review lineage (master workbook to inclusion CSV) is the authoritative clean of 2024-25. The Supabase DB and the released dashboards will be restated from it. The two-truths situation ends.
2. Re-baseline on successor v4 values. The formatted review workbook (red excluded rows, green pipeline-filled cells, blue URC marks) must be a buildable, script-generated artifact, never hand-edited again.
3. Three-layer contract:
   - Master: every standardized source row, append-only, never deleted. Carries only row-level inclusion/exclusion decisions with reasons. Value edits allowed only as recorded standardization/transcription fixes that make it MORE faithful to source.
   - Decision ledger (master to inclusion): all value cleaning and inference (date corrections, Days Injured recalcs, Unknown to Time Loss inference, squad normalization) lives here as replayable, versioned decisions. Never written into master. Master and inclusion will visibly disagree on inferred cells by design; that is correct (source preserved, inference labelled).
   - Analysis: consumes the inclusion dataset only.
4. DB-centric truth: the master dataset plus decisions live in the database. The formatted workbook and inclusion CSV are generated exports of DB state. Files are the intake, the DB is the truth, artifacts are renders.
5. Simple change loop: author one decision record (row, field, old to new, reason), run one replay command, read the printed diff summary and flags, approve. Anomaly checks (out-of-window dates, negative days, category drift) flag but do not block. Manual review by Abdel is the gate; no preflight/candidate/checksum-envelope ceremony for routine updates.
6. Evidence standard split:
   - master to inclusion: fully replayable, byte-verified.
   - dirty source to master: documented, not re-executed, for 2024-25. One consolidated Standardization Record per team (source checksum, header mappings, steps applied, pseudonymisation note, row reconciliation), mined from existing per-team QA/audit files.
   - The scripted per-team pipeline is built as the go-forward path (Year 2 and any resupplied team) and validated by re-running 2 or 3 teams against the baseline as a spot check.
7. Scalability: everything keyed by season from the start. One `intake <team> <season>` command per new team file. Carry-forward rules live once as versioned rules; row adjudications are season-scoped and never blindly carried over. The master comparability checks become a standing check suite for every future season.
8. Handoff-readiness is an acceptance criterion: a cold reader understands the project in ten minutes; no version-suffix soup in filenames (versions live in Git and the ledger).
9. Deletions: Abdel wants superseded/redundant files deleted outright, no archive, per the manifest below, at the Phase 5 gate.

## Verified state of the repo (2026-07-24)

- Current inclusion CSV: `outputs/urc_final_human_review_2024-25/urc_injury_included_dataset_2024-25.csv`, SHA-256 `e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb`, head of a 9-step scripted chain recorded in its `.manifest.json` `cleanup_history`. AGENTS.md still records the stale step-6 hash (`5a01bcbc...`).
- Chain steps 1 to 6 scripts are committed; steps 7 to 9 are untracked: `tools/resolve_unknown_injury_fit_dates.py`, `tools/apply_unknown_injury_inference_rules.py`, `tools/apply_bulls_cardiff_unknown_adjudications.py`, plus matching tests in `tests/` and two uncommitted entries in `docs/PIPELINE_RULE_CHANGELOG.md`.
- Frozen workbook vs successor v4 (`outputs/urc_final_human_review_2024-25/urc_injury_reviewed_master_with_exclusion_decisions_2024-25_frozen_2026-07-23.xlsx` vs `..._successor_2026-07-23_v4.xlsx`): exactly 180 value diffs, all accounted for by existing audit records (178 Sharks "Other team" to "Sharks"; row 535 date typo fix; row 1530 "Confirmed duplicate" exclusion plus red row font). No rows added or removed. Red/green cues are direct per-cell fonts (no conditional formatting anywhere) and are preserved cell-for-cell.
- Provenance caveat requiring a correcting addendum: v3/v4 were rebuilt via openpyxl after a failed native-Excel save (see `..._successor_2026-07-23_v3.failed_excel_ui_attempt.xlsx` and `work/snapshot_live_v3_master_values.applescript`). The Sharks normalization audit wrongly claims a native Excel edit. Side effects (sharedStrings table dropped, 4 built-in numFmt declarations trimmed, Review Queue empty formatted range truncated) are benign; data verified intact.
- The 120 Non-Rugby/Gym rows were removed in the CSV only and correctly deferred for the master per `outputs/urc_final_human_review_2024-25/DEFERRED_MASTER_WORKBOOK_CHANGES_2026-07-23.md`. Row 1735 remains unresolved; both carry into the ledger as open items.
- The Welsh (Dragons/Ospreys/Scarlets) manual edits predate the frozen baseline and are equally present in frozen and v4; evidence in `work/` and per-team QA JSONs.

## Target end-state

```
dirty team file -> per-team standardize + pseudonymize (scripted, recorded)
                              |
               16 teams combined -> MASTER dataset (DB = source of truth)
                                     every source row, append-only, never deleted
                                     exclusions marked with reason (red)
                                     pipeline-filled cells (green), URC marks (blue)
                                     master-level comparability check suite
                                     |
                     decision ledger (exclusions, corrections, inferences)
                                     |
                        INCLUSION dataset (derived, deterministic)
                                     |
                        analysis tables (incidence, burden, severity, contact)
                                     |
                                 website
```

Target tree (post-cleanup):

```
data/<season>/intake/       per-team standardized inputs + Standardization Records
data/<season>/master/       baseline workbook (generated) + master table
data/<season>/decisions/    the ordered decision ledger
data/<season>/inclusion/    inclusion CSV + manifest
docs/METHODOLOGY.md         source to master to inclusion, generated from the ledger
docs/HANDOFF.md             what this is, how to run it, where truth lives
tools/                      four verbs only: intake, replay, render, checks
```

## Phases

Execution order: 0, 1, 2, 3, 6 on the general go; 4 and 5 each on a separate explicit go.

### Phase 0: Secure what is in flight (no live writes)
- Commit the three untracked step scripts, their tests, and the changelog entries so the current chain head is in Git.
- Write the provenance addendum correcting the Sharks audit record (openpyxl re-serialization after failed native save; data verified intact; 180/180 diffs accounted for).

### Phase 1: Bless the baseline (v5)
- Extract v4 values into a canonical master data table.
- Build the workbook generator that renders the formatted master (red/green/blue) from data plus decisions. Verify the render reproduces v4 values and formatting cues exactly.
- Produce v5 = v4 plus the deferred exclusion markings (the 120 Non-Rugby/Gym rows marked excluded in the master with reason, red rows). v5 is generated, checksummed, and becomes the frozen 2024-25 anchor. Keep the original frozen 2026-07-23 workbook as the pre-baseline reference.

### Phase 2: One canonical decision record plus one replay command
- Consolidate the 9-step chain (JSON ledgers, audit CSVs, constants hardcoded in step scripts) into a single ordered ledger: each step has a rule version, a plain-English description, and row-level details.
- Build one replay command: baseline -> apply ledger -> inclusion CSV.
- Acceptance test: replay output byte-matches `e8da3caf...` (note: v5 marks the 120 rows excluded in master, so replay excludes them at export rather than via the step-6 removal; reconcile accordingly).
- The step-by-step methodology document is generated from this ledger.

### Phase 3: Per-team standardization records and the go-forward intake pipeline
- One consolidated Standardization Record per team, mined from existing per-team QA/audit files, `work/`, and `outputs/urc_final_human_review_2024-25/human_review_workflow_archive_2026-07-23/`.
- Build `intake <team> <season>` as the go-forward scripted path; validate by re-running 2 or 3 teams against the baseline.
- Build the standing comparability check suite (what Phase 1 checks on the 2024-25 master, generalized).

### Phase 4: DB restatement (live; each write needs Abdel's explicit target approval)
- Load baseline plus ledger into the approved Supabase target (master rows append-only; decisions as adjudication records).
- Analysis views derive inclusion, then incidence, burden, severity, contact per team and league. Versioned as a new lineage; old releases retired, never deleted.
- Re-release the 16 teams and the league bundle via the simplified path: regenerate, diff summary, Abdel's recorded yes. The website keeps serving the current approved bundle until this lands.

### Phase 5: Deletion cleanup (separate explicit go on the manifest below)

All under `outputs/urc_final_human_review_2024-25/` unless noted:
- Superseded workbooks: successors v2, v3, `v3.failed_excel_ui_attempt`, duplicate `urc_injury_human_review_master_2024-25.xlsx` (byte-identical to frozen), the `~$` lock file. Frozen original and v4 are kept until v5 is verified; then v4 becomes deletable.
- Pre-step backups: all 18 `pre_*_backup_*.xlsx`, `backups/`, `pre_settled_decisions_backup_2026-07-22/`.
- Intermediate CSV snapshots: all `pre_*` CSV plus manifest pairs (replay regenerates any intermediate state).
- Per-step audit/QA files: only after their content is consolidated into the canonical ledger (Phase 2 gate).
- Bulk artifacts: the 36 MB `.inspect.ndjson`, the 220 MB `review_data_2024-25.json`, `workbook_previews/`, `human_review_workflow_archive_2026-07-23/` (after Phase 3 mining).
- Repo root: entire `work/` dir (after Phase 3 mining); the 9 superseded step scripts in `tools/` once the replay command incorporates their rules.
- Held for verification, not deleted: `deferred_exposure/exposure_master_2024-25.csv` (64 MB); confirm it is not the only copy of the exposure master before touching it.

### Phase 6: Documentation overhaul
- Rewrite AGENTS.md: replace the stale "Included Dataset Column Cleanup" section (stale SHA-256, superseded workflow), the heavyweight release ceremony for this lineage, and stale watch-outs with the new contract (three layers, change loop, simplified release with manual review as the gate). Record the ceremony simplification itself as a dated, reasoned decision in `docs/PIPELINE_RULE_CHANGELOG.md`.
- Write `docs/HANDOFF.md` and generated `docs/METHODOLOGY.md`. Update `docs/PIPELINE_RUNBOOK.md`.

## Acceptance criteria

1. Replay from the v5 baseline reproduces the current inclusion CSV exactly, or every difference is listed and adjudicated.
2. The rendered workbook matches v5 values and formatting cues cell-for-cell.
3. One generated document tells the complete source to master to inclusion story.
4. A single small edit (for example, adding a confirmed return date) flows to the website preview through one command plus one review.
5. The working tree contains only: anchors, ledger, the four tools plus tests, current outputs, docs.
6. A cold reader understands the project from `docs/HANDOFF.md` in ten minutes.

## Open items carried in

- Stale AGENTS.md hash; uncommitted changelog entries (Phase 0/6).
- Row 1735 unresolved (stays flagged in the ledger).
- v4 provenance addendum (Phase 0).
- Exposure lineage is out of scope here except the held-for-verification file above.
- Union access model, demo tile, `/about` route, small-cell disclosure: untouched, remain open per AGENTS.md.
