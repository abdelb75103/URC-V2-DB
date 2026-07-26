# Canonical Source-to-Release Runbook

Status: current operating map. This document explains the accepted route; `AGENTS.md` remains the binding safety and approval contract.

## 2024-25 injury-lineage restructure (2026-07-24)

The human-review lineage is the authoritative clean of 2024-25 (`docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md`, complete). The live dashboards now serve the accepted analysis-window v5 bundle `urc-2024-25-v5-45169a66a7da-a1`; the 24 July v4 bundle remains retained for rollback. The local route is four verbs under `tools/`:

1. `render.py`: canonical master data table to the formatted master workbook (extract, render, compare, mark-excluded). Baseline hashes: `data/2024-25/master/baseline_record.json`.
2. `replay.py`: v5 baseline plus `data/2024-25/decisions/ledger.json` to the inclusion CSV, its manifest, and generated `docs/METHODOLOGY.md`. Must reproduce the accepted CSV byte-for-byte; conflicts stop the line.
3. `intake.py`: a new team/season standardized pseudonymised injury CSV into a season master, append-only; frozen seasons refuse appends; validate mode reconciles against a baseline without writing.
4. `checks.py`: standing season-keyed comparability suite; structural FAIL, observations FLAG.

Routine change loop: author one decision record, run replay, read the diff summary and flags, stop for Abdel's review. That covers the data layer and stops there; reaching the website is the separate, separately approved release path (lineage load, `release-league` preflight, recorded yes, promotion, then `export-team-dashboards`). The table below remains the DB-side operating map; releases in this lineage now use the simplified path recorded in the 2026-07-24 changelog entry.

## Completion contract

A team/season is reproducible only when all of the following are true:

1. The supplied pseudonymised, standardised intake and its manifest are retained with checksums and source-row locators.
2. Every loaded row has a stable `source_row_id` tied to its source file, sheet/table, and original row number.
3. Every derived, mapped, inferred, corrected, flagged, or excluded value is represented by a versioned processing state and, where a value or eligibility changes, a row-level audit event.
4. Every audit event states the field, before/after values where applicable, action, controlled reason code, rationale, rule version, and review status.
5. Manual decisions are immutable adjudications keyed to the exact source evidence; they are reapplied by the pipeline rather than hand-edited into outputs.
6. Curated rows retain both `source_row_id` and `record_version_id` and belong to one active, non-stale, checksummed build.
7. Published metrics come from versioned SQL analysis views and retain their numerator, denominator, view/cohort version, build, and release identity.
8. The public payload is an immutable reviewed snapshot, and the website reads only the least-privilege reporting views.

The formal boundary begins at the supplied pseudonymised, standardised intake. Upstream pseudonymisation or standardisation is claimed as reproducible only when its retained script, checksum bridge, locator evidence, and row reconciliation prove it.

## One accepted path

| Stage | Supported operation | Persistent evidence | Gate |
|---|---|---|---|
| 0. Profile | Follow `TEAM_INTAKE_PROFILING_GATE.md`; use team-specific adapters only when approved. | Checksummed profile JSON, mapping version, source inventories, AI review, human approval, unresolved-adjudication list. | Local/read-only. Must pass before ingest. |
| 1a. Prepare injury input | Use the supplied pseudonymised standardised injury CSV unchanged when it already matches the approved profile. If the profile requires an adapter, run only that approved adapter and retain its QC, source checksum, output checksum, locator reconciliation, and mapping version in the manifest. | Supplied file plus checksummed profile/manifest; adapter QC when applicable. | Local/read-only. The artifact that will be registered must be named as an approved input checksum. |
| 1b. Prepare exposure input | Run `prepare-exposure` and then `clean-exposure` with the current profile's explicit `--reporting-grain`; pass explicit `--window-start <YYYY-MM-DD> --window-end <YYYY-MM-DD>` to cleaning. Both commands update the manifest and emit checksummed QC. | Prepared/cleaned file hashes, source-row locators, native grain, action/reason counts, protocol/rule version, QC hashes. | Local only. Review the exact cleaned artifact and add/confirm its checksum in the approval envelope before ingest. |
| 2a. Register injury | `python3 -m pipeline ingest --team <name> --season <season> --file <approved-injury.csv> --manifest <manifest.json>` | `ingestion.source_files`, `ingestion.source_rows`, file/row hashes, row cardinality, `audit.pipeline_runs`. | Live write; approve the exact hosted target, file checksum, team/season, and action. |
| 2b. Register exposure | Run `ingest` separately for the exact approved cleaned exposure CSV and checksum-matched manifest. The file name must identify it as exposure because the curated-build gate distinguishes processed injury and exposure sources. | A separate immutable source-file/source-row registration and ingest run. | Separate live write approval. A later `process-exposure` must use these exact registered bytes. |
| 3a. Process injuries | `python3 -m pipeline process-intake --team <name> --season <season> --file <registered-or-approved-adapted.csv> --window-start <YYYY-MM-DD> --window-end <YYYY-MM-DD> ...` | `processing.record_versions`; field-level `audit.record_events`; run/step versions, counts, hashes, origins, reason codes. | Live write. The file must reconcile one-to-one to the registered injury rows. Never rely on the 2024-25 CLI defaults for another season. |
| 3b. Process exposure | `python3 -m pipeline process-exposure --team <name> --season <season> --file <registered-cleaned-exposure.csv> --reporting-grain <weekly|session>` | The same processing/run/event chain plus explicit native grain and exclusion reasons. | Live write. Grain must match every prepared row and come from the current profile, never the team name. |
| 4. Load fixtures | Once per season, register/review the canonical fixture file and run `python3 -m pipeline load-curated-fixtures --season <season> --file <approved-fixtures.csv>`. | `curated.fixtures`, source checksum, fixture-load run/step evidence. | Live write; approve the exact fixture checksum, season, hosted target, and action. `build-curated` refuses a season with no fixtures. |
| 5. Adjudicate | Use the narrow adjudication command matching the approved decision; then reprocess/reapply through the pipeline. | Immutable `audit.adjudications`, evidence fingerprint, reviewer, post-decision processing state and events. | Live write; exact decision and target require approval. |
| 6. Curate | `python3 -m pipeline build-curated --team <name> --season <season>` | `curated.builds`, typed injuries/exposure, source and record-version FKs, output hash, counts, denominators. | Live write; requires exactly one processed injury source, one processed exposure source, season fixtures, and exactly one active non-stale build for release. |
| 7. Verify | `reconcile-curated` and `verify-analysis-parity` against the exact candidate. | Count/metric reconciliation and candidate parity evidence. | Read-only against the database; no promotion. |
| 8a. Team release | First: `release --preflight`, review, then `release --preflight-file ... --preflight-reviewer ...`. Re-release: use the exact approved predecessor snapshot and, for numeric drift, an approved restatement envelope. | `reporting.aggregate_releases`, `release_context`, `release_table_rows`, reviewer and candidate hashes, build/view/run identity. | Preflight is read-only. Promotion is a separately approved live write. |
| 8b. League bundle | Run `release-league` with the accepted analysis/classification/cohort tuple, then promote the reviewed exact file. Classification-only successors use the incremental candidate views: they inherit the approved payload and replace only `body_locations`, `injury_types`, and `injury_profiles`. | One immutable 16-team bundle, member release/build identities, classification/cohort evidence hashes, canonical payload hash, and retained predecessor. | Preflight is read-only. Promotion is a separately approved live write. Never rebuild or overwrite unrelated metrics for a classification-only change. |
| 9. Serve | `lib/reporting.ts` queries `reporting.latest_team_dashboard_v2` and `reporting.latest_league_dashboard_v2`. | Zod-validated, whitelisted aggregate payload only. | Website is read-only and fails closed. |

The 2024-25 V3 league bundle is an additive successor cohort. It does not rewrite frozen V1 team releases or historical migrations. Broader diagnosis inference in `tools/sql/dashboard_v3_preview.sql` remains a local experiment and is not part of the accepted pipeline.

### Classification-only league release

Use the normal `release-league` command with the successor classification tuple. The utility selects the versioned incremental candidates automatically. Those candidates start from the currently approved immutable league and team payloads and replace exactly three classification-dependent keys: `body_locations`, `injury_types`, and `injury_profiles`. Headline, exposure, monthly, setting, severity, coverage, method, limitations, and every other payload key are inherited unchanged. Promotion still inserts a new immutable bundle, validates all 16 member identities and canonical hashes, retires rather than deletes the predecessor, and records the run and reviewer. A rule that changes cohort membership, denominators, severity, or any other dashboard section must use a new full-release version; it must not be routed through this incremental path.

### 2024-25 analysis-window v5 full release

Status: all five v5 migrations are applied and tracked; corrected release
`urc-2024-25-v5-45169a66a7da-a1` is approved and all 16 parity exports reconcile.
This is a full successor release because the reporting cohort, exposure denominator,
monthly series, and headline figures change. It is not a classification-only
incremental release.

The exact v5 tuple is:

```text
analysis_version=v5
classification_view_version=reporting_classification_2026-07-22_v2
cohort_view_version=analysis_window_2024-25_2026-07-25_v1
```

The immutable rule evidence is
`docs/evidence/analysis_window_2024-25_v5.json`
(`c9530c949c60ff4abe91753571dfed6dd9d1146f33cc466dfbbc7fdeddb8443d`).
The reviewed migration path is
`supabase/migrations/20260725190000_analysis_window_reporting_v5.sql`;
its SHA-256 is
`23970db6b4bc38aa91f2ca0ecf41203603c6361dc1c0fc4235a55a5f2dfcccde`.
The performance-only successors are:

- `supabase/migrations/20260726010000_analysis_window_v5_candidate_query_optimization.sql`,
  SHA-256 `eb4809f61912312375757eb545e5c237de12bbcd9fcab2892c59c9389e796ff4`.
- `supabase/migrations/20260726015000_analysis_window_v5_shared_cohort_snapshots.sql`,
  SHA-256 `622376306cda12840a684ad110b9ed21f52ec25448ef05d67f19f479a13799c0`.
- `supabase/migrations/20260726020000_analysis_window_v5_release_candidate_snapshots.sql`,
  SHA-256 `9deca17947a98d4667302793ad0b2326e1188964b113b1c975eff0ce20b357d5`.
- `supabase/migrations/20260726120000_analysis_window_v5_coverage_payload_snapshots.sql`,
  SHA-256 `83d3950b6a1838c73e089aa10d4913025fb48ba85a7637115168e89c5a3cbdfa`.

The first successor changes execution only and is statically proven equivalent
to the base payload definitions. The shared-cohort successor computes the
accepted injury, classification and exposure rows once and statically preserves
every downstream aggregate definition. The final successor computes the exact
reviewed team and league payloads from those shared rows, then routes v5
preflight and promotion to the build-pinned snapshots. The fifth migration
corrects cohort-derived coverage counters that the original payload inherited
from v4; it patches only the coverage object and proves that headline
denominators and every non-coverage section are unchanged. None alters source,
cohort or metric data.
Do not alter any frozen migration or historical `v4` view.

The required sequence is:

1. Complete and verify the additive v5 migration, direct v5 candidate views,
   release-path support, and focused tests locally. Do not apply the migration.
2. Generate the safe injury-side evidence without replaying the inclusion
   lineage:

   ```bash
   python3 tools/generate_analysis_window_v5_evidence.py injury-audit
   ```

   This produces the 208-row, hashed-key v5 injury cohort audit. It neither
   writes the inclusion CSV nor its manifest.
3. Obtain the mandatory independent review, inspect the migration SHA, static
   scans, and local reconciliation. The v5 acceptance targets are 64,511
   included exposure rows, 81,352.919497 exposure hours, 6,040 fixture-derived
   match hours, 1,658 recorded injuries, 785 time-loss injuries, and 17,573
   days lost. The 815 semantic pre-URC exclusions must total 865.830 hours;
   the four weekly reporters move zero rows.
4. The base and query-optimisation migrations are already applied and tracked
   on the approved live target. Verify those two tracking rows and hashes
   read-only. Do not rerun them. Obtain Abdel's explicit approval for the
   remaining shared-cohort and candidate-snapshot migrations and their exact
   `supabase_migrations.schema_migrations` tracking-row inserts, then apply
   only those exact files in order with the credential-safe wrapper:

   ```bash
   node pipeline/run_with_pooler.mjs node pipeline/sql_exec.mjs \
     supabase/migrations/20260726015000_analysis_window_v5_shared_cohort_snapshots.sql
   node pipeline/run_with_pooler.mjs node pipeline/sql_exec.mjs \
     tools/sql/register_analysis_window_v5_shared_cohort_snapshot_migration.sql
   node pipeline/run_with_pooler.mjs node pipeline/sql_exec.mjs \
     supabase/migrations/20260726020000_analysis_window_v5_release_candidate_snapshots.sql
   node pipeline/run_with_pooler.mjs node pipeline/sql_exec.mjs \
     tools/sql/register_analysis_window_v5_snapshot_migration.sql
   node pipeline/run_with_pooler.mjs node pipeline/sql_exec.mjs \
     supabase/migrations/20260726120000_analysis_window_v5_coverage_payload_snapshots.sql
   node pipeline/run_with_pooler.mjs node pipeline/sql_exec.mjs \
     tools/sql/register_analysis_window_v5_coverage_snapshot_migration.sql
   ```

   Each registration proves the expected objects and bindings before inserting
   its one exact tracking row. Then verify all five tracked versions,
   view definitions, snapshot row counts and hashes read-only. The snapshot
   shared-cohort migration deliberately leaves its three materialised views
   unpopulated, so V5 candidates are intentionally unavailable between the two
   migrations while V4 continues serving unchanged. The candidate-snapshot
   migration populates its five snapshots atomically, then the coverage
   correction creates the final shared coverage and patched-candidate
   snapshots. If either fails, correct the cause and retry only the failed,
   untracked migration. A corrective versioned rollback must
   restore every V5 aggregate view's dynamic source binding, not only repoint
   the candidate views; V4 remains the live release throughout. If a later
   source decision changes v5, obtain fresh explicit approval for the live refresh, then
   refresh the three shared cohorts and both payload snapshots in one
   repeatable-read transaction with
   `node pipeline/run_with_pooler.mjs node pipeline/sql_exec.mjs
   tools/sql/refresh_analysis_window_v5_candidate_snapshots.sql` before a new
   preflight. The refresh fails closed unless the 16 team identities, one
   league row and approved tuple reconcile. A corrective
   versioned migration can repoint the v5 candidates to the dynamic views;
   v4 remains available throughout as the release rollback tuple.
5. Perform read-only post-migration reconciliation. Stream the reviewed,
   build-pinned evidence result directly into the generator:

   ```bash
   node pipeline/run_with_pooler.mjs node pipeline/sql_query.mjs \
     tools/sql/analysis_window_v5_exposure_evidence.sql |
     python3 tools/generate_analysis_window_v5_evidence.py \
       exposure-evidence --input-json -
   ```

   The committed SQL fixes the season, requires `approved_member_build = true`,
   and selects only changed rows. It includes `curated_build_id` in the
   in-memory stream so the generator can reject superseded builds, duplicate
   source rows, or multiple builds for one team. The committed output hashes
   build IDs, stable source rows, and raw semantic labels, so none of those raw
   values is written to disk. It must pass the six recorded team-level
   rejection row/hour contracts as well as the league 815-row and 865.830-hour
   gate before promotion.
6. Run the complete read-only SQL contract and require every returned
   `passed` value to be `true`:

   ```bash
   node pipeline/run_with_pooler.mjs node pipeline/sql_query.mjs \
     tests/analysis_window_v5_sql_reconciliation.sql |
     tee docs/evidence/analysis_window_2024-25_v5_sql_reconciliation.json |
     node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{const r=JSON.parse(s);if(!r.length||r.some(x=>x.passed!==true))process.exit(1);console.log(`V5 SQL contracts passed: ${r.length}`)})'
   ```

   Then time the two direct candidate paths independently:

   ```bash
   node pipeline/run_with_pooler.mjs node pipeline/sql_query.mjs \
     tests/analysis_window_v5_candidate_performance.sql
   node pipeline/run_with_pooler.mjs node pipeline/sql_query.mjs \
     tests/analysis_window_v5_team_candidate_performance.sql
   ```

   Record both returned rows in
   `docs/evidence/analysis_window_2024-25_v5_candidate_performance.json`.
   Each path must return its exact candidate count, a non-empty payload and
   `candidate_payload_passed = true` within the five-minute database bound.
   Do not combine the two reconstructions into another gate. The subsequent
   preflight is the definitive candidate-equality and payload-hash check.
7. Review the generated exposure evidence and exact hashes, then create an
   intentional evidence checkpoint commit. By default the working tree must be
   clean before preflight. When Abdel explicitly authorises concurrent work,
   commit every release-owned file and set
   `PIPELINE_ALLOW_DIRTY_RELEASE_LEAGUE=1`; the release records
   `dirty_worktree_override=true` and leaves unrelated paths untouched. Never
   use this exception to release uncommitted pipeline, migration, evidence or
   payload changes. This commit binds the exact migration,
   injury audit, exposure evidence, SQL reconciliation, and direct candidate
   performance result used for promotion. Record the SHA-256 values for all
   four migrations, the injury audit, exposure evidence, SQL reconciliation
   and candidate-performance evidence in
   `docs/ANALYSIS_WINDOW_2024-25_BEFORE_AFTER.md` before committing.
8. Snapshot the v4 predecessor, then preflight the exact v5 tuple:

   ```bash
   node pipeline/run_with_pooler.mjs python3 -m pipeline \
     release-league --season 2024-25 --snapshot-current \
     --output data/reporting/urc_dashboard_2024-25_v4_previous.json

   node pipeline/run_with_pooler.mjs python3 -m pipeline \
     release-league --season 2024-25 \
     --analysis-version v5 \
     --classification-view-version reporting_classification_2026-07-22_v2 \
     --cohort-view-version analysis_window_2024-25_2026-07-25_v1 \
     --preflight \
     --output data/reporting/urc_dashboard_2024-25_v5_preflight.json
   ```

   Review all 16 team payloads, the league candidate, the Dragons change flag,
   candidate hashes, evidence hashes, and v4 rollback route. The preflight is
   read-only and is not promotion approval.
9. Obtain a separate recorded approval for the exact v5 `release-league`
   promotion, then promote the reviewed candidate:

   ```bash
   node pipeline/run_with_pooler.mjs python3 -m pipeline \
     release-league --season 2024-25 \
     --analysis-version v5 \
     --classification-view-version reporting_classification_2026-07-22_v2 \
     --cohort-view-version analysis_window_2024-25_2026-07-25_v1 \
     --previous-bundle-file data/reporting/urc_dashboard_2024-25_v4_previous.json \
     --preflight-file data/reporting/urc_dashboard_2024-25_v5_preflight.json \
     --preflight-reviewer "Abdel Babiker"

   node pipeline/run_with_pooler.mjs python3 -m pipeline \
     export-team-dashboards --season 2024-25
   ```

   Reconcile all 16 parity exports with the approved bundle. Then record the
   actual migration SHA, exposure-evidence hash, release ID, generated
   timestamp, and deployed verification in the before/after report and change
   log.

Rollback is reporting-only and retains every v5 object and evidence record:
re-promote the last approved tuple
`v4 / reporting_classification_2026-07-22_v2 /
lineage_2024-25_2026-07-24_v1`, then regenerate parity exports from that
approved v4 bundle.

## Retained V1 release ceremony (pre-restatement)

The 2024-25 injury lineage uses the simplified path recorded in the 2026-07-24 changelog entry: regenerate from baseline plus ledger, read the diff summary, obtain Abdel's recorded yes, then rewrite the per-team parity exports with `export-team-dashboards`. No preflight/candidate/checksum-envelope ceremony for routine updates; anomaly checks flag but do not block.

The ceremony below is retained as the record of how the retired pre-restatement releases were produced, and as the **governing path for any team/season outside that lineage**. Run it one step at a time with Abdel's per-team sign-off.

### Flag-level detail

**Profile gate (stage 0).** The checksummed profile JSON is the approval envelope and must match the manifest's team/season, profile/mapping metadata, decision, AI-review/approval fields, empty unresolved-adjudication list, and approved input checksums. `ingest --manifest` is required and fails before row loading or SQL unless that evidence is complete, current, checksum-matched, and approved with a `compatible` or `adapter_required` decision. `adapter_required` also requires matching-version JSON with a non-empty, structurally valid `mappings` list as defined in the profiling gate. **Profile approval never authorizes a database action:** reconfirm the exact hosted target and obtain separate approval for each named live action.

**Registration (stage 2).** Each file checksum must match the manifest/profile approval. Profile approval does not authorize either live ingest.

**Curated build (stage 6).** `build-curated` requires exactly one processed injury source and one processed exposure source for the team/season, and refuses a season with no fixtures. The release gate requires exactly one active, non-stale build.

**Before any release.** Commit implementation changes first: `release`, including preflight, refuses a dirty Git tree.

**First release for a team/season.**

```bash
python3 -m pipeline release --team <LegacyName> --season <season> --preflight
```

Executes the release gates read-only and writes the exact public-dashboard candidate to Git-ignored `data/reporting/<team_key>_dashboard_<season>_<release_hash>_preflight.json`. It never inserts a release and refuses a preflight output under `content/reporting`. Review the candidate, then run `reconcile-curated` and `verify-analysis-parity` with `--dashboard-file <candidate>` before obtaining Abdel's explicit sign-off. Then:

```bash
python3 -m pipeline release --team <LegacyName> --season <season> \
  --preflight-file <candidate> --preflight-reviewer "Abdel Babiker"
```

The CLI blocks before SQL if any field except `generated_at` changed, and records both reviewer and candidate checksum in audit parameters. It inserts an invisible draft with an open audit run, verifies and serializes that exact snapshot, then atomically promotes it to approved/succeeded. A failed attempt is retired/failed and an identical retry receives a new immutable label. If local artifact export fails after promotion, cleanup restores the exact prior approved predecessor when one existed. Confirm independently with `diff-dashboard-json --preflight-release --old <candidate> --new content/reporting/<team_key>_dashboard_<season>.json`; only `generated_at` may differ.

**Re-release for a team/season.** Snapshot the old JSON from HEAD first:

```bash
git show HEAD:content/reporting/<team_key>_dashboard_<season>.json \
  > data/reporting/<team_key>_dashboard_<season>_previous.json
python3 -m pipeline release --team <LegacyName> --season <season> \
  --previous-dashboard-file data/reporting/<team_key>_dashboard_<season>_previous.json
```

The CLI caches, parses, and hashes that snapshot before its first database query, requires its contents to exactly match the latest accepted full release, applies the historical whitelist to both the current candidate and serialized draft, and records the predecessor identity plus checksum in audit parameters. Any non-whitelisted drift blocks the release. Promotion serializes on the team row, rechecks that predecessor, and atomically retires superseded approved full releases. Confirm independently with `diff-dashboard-json --old <previous> --new content/reporting/<team_key>_dashboard_<season>.json`, which must return `ALLOWED_ONLY`.

**Whitelist scope.** Only `generated_at`, internal-key stripping, coverage shape, and regenerated method/limitations narrative. Any numeric, label, team-name, or analysis-window drift blocks the re-release unless separately adjudicated and approved.

**Per-team closeout.** Commit that team's `content/reporting/*.json` before the next team's release, then query for protected-alias pattern hits after live loads and before closeout.

**League bundle.** A team release does not update the website by itself. After all intended member releases are accepted:

```bash
python3 -m pipeline release-league --season <season> --snapshot-current \
  --output data/reporting/<bundle_previous>.json
```

Run the exact intended `release-league` analysis/classification/cohort combination with `--preflight`, review that canonical 16-team candidate, and obtain separate approval before promotion with `--preflight-file`/`--preflight-reviewer` plus `--previous-bundle-file` when a predecessor exists.

**Analysis tuples.** The served 2024-25 lineage restatement uses `--analysis-version v4 --classification-view-version reporting_classification_2026-07-22_v2 --cohort-view-version lineage_2024-25_2026-07-24_v1` (release `urc-2024-25-v4-6f04bd64d2a6-a2`, promoted 2026-07-24). The earlier season-bound V3 tuple `--analysis-version v3 --classification-view-version reporting_classification_2026-07-20_v1 --cohort-view-version season_bound_2026-07-20_v1` is retired history, kept only to read the retired releases. Do not substitute the broader dev-only diagnosis preview.

**Mandatory after every accepted `release-league` promotion:**

```bash
python3 -m pipeline export-team-dashboards --season <season>
```

Otherwise the 16 committed per-team parity exports under `content/reporting/` go stale against the served bundle. That command reads the approved bundle through the existing snapshot path and rewrites them.

## How to explain one row

Start with the intake checksum and source row number, then follow this chain:

```text
ingestion.source_files
  -> ingestion.source_rows
  -> processing.record_versions
  -> audit.record_events / audit.adjudications
  -> curated.injuries or curated.exposure
  -> versioned analysis cohort/aggregate view
  -> reviewed release member/build
  -> immutable dashboard payload
```

For a local locator-enriched file, `python3 -m pipeline trace-row --file <file.csv> --row-number <n>` explains its carried source locator. `--include-source` may expose sensitive row data and should be used only in an appropriate local review context. Database lineage should be queried read-only by stable IDs; do not copy player-level results into Git, logs, screenshots, or reports.

### Exclusion example

An excluded row remains stored. Its processing state records the eligibility status; its audit event records the exclusion action, controlled reason code, rationale, and rule version; the curated layer either retains it with excluded status or omits it from the analysis cohort according to the versioned view. The release records aggregate cohort-filter counts. No source row is deleted.

### Inference or mapping example

The immutable source value remains in `ingestion.source_rows`. The computed value and origin live in `processing.record_versions`; `audit.record_events` records the mapping/inference action, old/new values, reason code such as `canonical_mapping` or `controlled_inference`, rationale, and rule version. Curated `field_origins` preserves that provenance into analysis.

## Where rules belong

| Kind | Canonical home | Carry-forward behavior |
|---|---|---|
| Shared scientific/analytical rule | New versioned migration/view plus `PIPELINE_RULE_CHANGELOG.md` | Carries forward only through the accepted version. Never edit a frozen migration/view in place. |
| Team source mapping | Approved team/season profile and adapter version | Revalidate whenever that team's export changes. |
| Row-specific human decision | `audit.adjudications` bound to source evidence | Does not carry blindly to another row or season. |
| Dev hypothesis | `tools/` with an explicit draft/preview marker | Has no production effect. Promote through the versioned-rule path or discard. |

## Repository hygiene rules

- `pipeline/` and versioned migrations are the executable pipeline. Do not add alternate production cleaning scripts under `data/`, `output/`, `outputs/`, or `tools/`.
- Keep accepted code and durable evidence; keep rejected or superseded scratch work out of tracked source.
- Local inputs and evidence are Git-ignored because some are sensitive or reproducible artifacts. “Ignored” does not mean “safe to delete”: accepted intake, manifests, adjudication evidence, release preflights, predecessor snapshots, and acceptance evidence require a verified backup/retention decision.
- Caches, build outputs, screenshots, duplicate previews, and abandoned drafts may be removed only after confirming that they are reproducible and are not the sole evidence for an accepted decision.
- `content/reporting/*.json` is a public parity/emergency export, not the website's analytical source of truth.
- Historical plans live in `docs/archive/` and are not operating instructions.

## Verification without a live write

```bash
npm run pipeline:check
python3 -m unittest discover -s tests -p 'test_*.py'
npm run test:dashboard-access
npm run typecheck
npm run build
```

Tests explicitly labelled `*_live*` are not part of routine local verification. No command in this runbook authorizes a database write, migration, release, deploy, or publication.
