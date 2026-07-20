# Canonical Source-to-Release Runbook

Status: current operating map. This document explains the accepted route; `AGENTS.md` remains the binding safety and approval contract.

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
| 8b. League bundle | `release-league --analysis-version v3 --classification-view-version reporting_classification_2026-07-20_v1 --cohort-view-version season_bound_2026-07-20_v1 --preflight`, then promote the reviewed exact file. | One immutable 16-team bundle, member release/build identities, classification/cohort evidence hashes, canonical payload hash. | Preflight is read-only. Promotion is a separately approved live write. |
| 9. Serve | `lib/reporting.ts` queries `reporting.latest_team_dashboard_v2` and `reporting.latest_league_dashboard_v2`. | Zod-validated, whitelisted aggregate payload only. | Website is read-only and fails closed. |

The 2024-25 V3 league bundle is an additive successor cohort. It does not rewrite frozen V1 team releases or historical migrations. Broader diagnosis inference in `tools/sql/dashboard_v3_preview.sql` remains a local experiment and is not part of the accepted pipeline.

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
