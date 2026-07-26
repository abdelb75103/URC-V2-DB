# URC Injury Surveillance Database Pipeline

## Project Overview

A database-backed, reproducible research pipeline for URC injury and exposure data: cleaned season datasets, analysis, dashboards, league and club reports, and a defensible methodology. The legacy spreadsheet workflow is context only, never the source of truth.

**Frozen since 10 July 2026:** the `curated` schema, `analysis.*_v1` view definitions, controlled reason codes, release gates, and the dashboard-JSON diff whitelist. All 16 teams have approved 2024-25 releases and are `live`. Current phase: Abdel's private review of the passwordless pre-production V2 site, then the explicitly manual access-control restoration and production cutover.

Reuse the Year 1 workflow for Year 2 so cross-season comparisons rest on consistent definitions. Foundation and freeze record: `docs/V2_FOUNDATION.md` (§ "DB-Backed Reporting and the V1 Freeze").

**Any rule change requires a new versioned migration (e.g. `_v2` views), a recorded adjudication of why, and a rerun plus re-release for every affected team/season. Never an edit in place.**

Key documents:

| Need | Document |
|---|---|
| How to run the pipeline | `docs/PIPELINE_RUNBOOK.md` |
| New team/season intake | `docs/TEAM_INTAKE_PROFILING_GATE.md` |
| What changed and why | `docs/PIPELINE_RULE_CHANGELOG.md` |
| Source-to-inclusion story | `docs/METHODOLOGY.md` (generated) |
| Pre-share access restoration | `docs/ACCESS_RESTORATION_GATE.md` |
| IOC buckets | `docs/IOC_TAXONOMY_BUCKETS.csv` |

## Source Archive and Intake

- Reference-only legacy archive: `/Users/abdelbabiker/Desktop/URC` (145 files, 16 team folders). **Never edit it.** Record originals' SHA-256 checksums and secure locators as intake provenance; the pipeline ingests only supplied pseudonymised intake files.
- `V1 - FOR COMPARIOSN ONLY ....xlsx` at project root is a comparison reference only. Do not ingest, clean, release, or treat it as a pipeline source. PDFs are narrative context unless Abdel explicitly asks for report-level baselines.
- The archive is mainly 2024-25; historical reports include 2022-23. Record each team's actual reporting window and coverage first. Do not treat a team-specific window as the final comparable window. After all teams are profiled, choose the largest defensible comparable window and record late/missing coverage rather than silently changing denominators.
- Team inputs differ in schemas, units, daily versus weekly exposure, duration formats, and high-speed-running thresholds. **A populated standard column is not proof that values are comparable.**
- Treat spreadsheet "Analysis" outputs as claims until formula lineage is verified. A polished workbook can preserve row counts while misrouting metrics, hiding hard-coded summaries, or leaking unpseudonymised tokens.
- **Every new team/season must pass `docs/TEAM_INTAKE_PROFILING_GATE.md` before `ingest` or team-specific implementation.** Maximise defensible completeness, not filled-cell count: preserve evidence and origin for every derived or inferred value, send ambiguity to adjudication, otherwise use `Unknown`.
- Measure coverage as defensible non-`Unknown` canonical classifications, not populated supporting fields. Bind human decisions to exact evidence fingerprints. Version raw-restoration mappings separately from proposed-intake mappings.
- A shared source-workbook family justifies reusing the profile template or comparison skeleton only. Provenance, clinical mappings, anomaly set, input checksum, review, adjudication, and approval envelope stay team/season-specific.
- Team-specific body-location and tissue/pathology labels map into the shared IOC 2020 buckets using **that team's** codebook and actual cross-field evidence. Do not reuse another team's label mapping without proving equivalent meaning. AI may propose mappings but may not silently create clinical facts.
- If Step 0 finds unresolved provenance, reconstruction, or pseudonymisation issues, profile and checksum the legacy files in place. Do not copy them into the canonical intake boundary until an approved adapter produces a locator-enriched pseudonymised input.

## Architecture and Data Flow

Lakehouse (medallion) layout on Supabase Postgres, live since 10 July 2026:

`immutable intake files -> ingestion (source_files, source_rows) -> processing (record_versions) -> curated (builds, injuries, exposure, fixtures, code_lists, team_exposure_denominators) -> versioned analysis views -> reviewed team releases -> immutable 16-team league bundle -> reporting.latest_team_dashboard_v2 / reporting.latest_league_dashboard_v2 -> website`

The cross-cutting `audit` schema (`pipeline_runs`, `step_runs`, `record_events`, `adjudications`, `reason_codes`) is written at every step. Nothing moves between layers without a recorded run.

- **The database and versioned analysis views are the analytical source of truth.** Each accepted metric/cohort definition lives once in its versioned SQL view family, never reimplemented in Python, the website, or exports. The frozen `analysis.*_v1` team-release views stay frozen; accepted additive successors do not edit them in place.
- Releases are keyed by team + season. Superseded releases are retired, never deleted, so year-on-year comparison and restatement history are queries rather than re-cleans.
- The browser never connects directly to Supabase.
- **This project writes straight to the live Supabase/Postgres database. There is no Docker/local Supabase workflow.** Do not run `supabase start`, `supabase migration up --local`, or `supabase db query --local`. Treat every database write, migration, ingest, processing run, adjudication, or release as live-impact work requiring explicit approval of the exact hosted target.
- The formal V2 audit boundary starts at the supplied canonical pseudonymised intake file. Record its preparer, timestamp, mapping/codebook version, checksum, secure original-file locator/checksum where available, row reconciliation, and carried source-row locators. Do not claim upstream reproducibility without its retained script and evidence.
- Before live multi-entity ingest, preflight every manifest-facing display name against the canonical identity/alias dimension. Fixture aliases and lowercase keys do not prove the exact intake spelling is registered.
- Dashboards and reports must query shared views or exported pipeline results. Do not reimplement metrics or cleaning rules in presentation code. A private local review explicitly requested by Abdel may use a separate, Git-ignored, development-only aggregate preview artifact; it must stay disabled in production, must not overwrite an approved payload, and must not imply release approval.
- **Keep source-reported, deterministically derived, inferred, and manually adjudicated values distinguishable. Never overwrite the original value.**
- Correct immutable ingested source representations only through a one-to-one restatement tied to registered rows: allow deterministic field changes, preserve original values and stable IDs, emit row-level events, and require an exact checksummed restatement for published numeric drift.
- A human decision fingerprint that includes mutable draft outputs is the immutable pre-decision evidence binding. Do not recompute it after applying the choice; bind changed artifacts separately through a fresh post-decision review.
- Prefer exclusion/status fields and analysis views over deleting records.

## Audit Trail Contract

Every result must be traceable back to the source file and source row/cell.

- **At ingestion** record: source file, sheet/table, original row number, stable raw record ID, file checksum, import timestamp, source season/team.
- **For every run** record: run ID, ordered step ID, timestamp, final script/version or commit, parameters, environment/dependency lock, input/output hashes, before/after counts overall and by team.
- **For every changed, excluded, restored, or flagged record** record: raw record ID, field, old value, new value where applicable, action, controlled reason code, human-readable rationale, rule/version, reviewer/adjudication status.
- Retain excluded rows in an audit/quarantine table so "step 3 excluded source rows 1, 7, 10, and 12 for these reasons" reproduces exactly.
- **Ambiguous joins are review cases.** Do not silently choose the nearest date, duration, or distance match when a unique key is unavailable.
- Manual corrections enter through a recorded adjudication table/file and are then reapplied by the pipeline. **Never hand-edit a cleaned output.**
- Each published metric must trace to a pipeline run, analysis view/query, cohort definition, numerator, and denominator.
- **The workflow is human-in-the-loop.** Do not build or require a monolithic command that runs every step for every team. Each small verified step still records its inputs, rules/version, counts, hashes, and review/adjudication status.
- `run` may stay lightweight as orchestration. Any script/step that changes, derives, flags, excludes, validates, or exports data must capture what ran, on which inputs, with which rules/parameters, and what changed. `release` is the promotion boundary: provisional outputs can stay local/draft, but any dashboard/reporting aggregate used as a final output must record which processed inputs, checks, and run evidence produced it.
- Keep only the final scripts actually used by the accepted pipeline. Remove superseded scratch scripts once their logic is rejected or incorporated.
- **The web application is read-only.** Run ingestion, cleaning, adjudication, analysis generation, and releases through versioned Python commands.

## Scientific and Analytical Rules

Freeze a written protocol before the pilot clean: population, season window, injury case definition, time-loss definition, match/training scope, exposure denominator, severity categories, missing-data handling, recurrence rules, censoring, competition eligibility, and all exclusion thresholds.

- **Treat legacy cleaning rules as hypotheses.** The archive contains conflicting season endpoints and exposure filters, unverified GPS-noise thresholds, manual spreadsheet steps, and potentially unsafe closest-match reconciliation.
- Before comparing surveillance releases, reconcile case definition, setting scope, time-loss rule, and problem-type filter. A legacy "injury incidence" table may omit unknown settings yet include illnesses, so headline deltas can reflect definition differences rather than cleaning effects.
- **Do not infer clinical categories from free text** unless the protocol defines the rule and the output is labelled as inferred. Preserve the source value and confidence/review status.
- **Body location and injury tissue/pathology must always be bucketed into the controlled IOC 2020 categories** in `docs/IOC_TAXONOMY_BUCKETS.csv`, or left `Unknown` when no defensible source/code evidence exists. Orchard/OSIICS codes and source text are evidence for mapping into those buckets; they are not separate reporting buckets.
- Comparable injury-analysis columns must be standardised through the shared pipeline rules before cross-team analysis: `Occasion category`, `Match Type` (`URC`, `training`, `unknown`), problem type, injury status, fit-for-selection status, return date origin, severity/time-loss category, recurrence, contact context, body location, tissue/pathology. Preserve source values and carry origin fields for derived, mapped, or inferred values.

### Occasion category (human review workbook)

Preserve the strongest explicit activity context instead of forcing every record into match/training.

| Source evidence | `Occasion category` |
|---|---|
| Explicit `GAME` / `Match` | `Match` |
| Explicit training | `Training` |
| Explicit gym or non-rugby | Its source-supported label (`Gym-Based`, `GM`, `Non-Rugby`) |
| Blank / `Unknown` / `N/A`, non-illness record | `Training` |
| `Problem type` or equivalent identifies an illness | `Illness`, regardless of blank/unknown/N/A activity |
| No more specific supported context exists | `Other` |

**Never relabel an explicit gym, non-rugby, or illness context as training.**

An explicit source `GAME` or `Match` value determines the activity setting. Fixture alignment determines competition eligibility, not whether the activity was training: retain `Match` for an off-fixture game, set `Exclusion Reason` to `Non-URC match`, and apply the established excluded-row formatting. **Never recode an explicit game as `Training` solely because it falls outside an official URC fixture date.**

**Treat requested classification rules as hypotheses** when they conflict with source semantics, the protocol, or stronger record evidence. Surface the conflict and propose the scientifically defensible interpretation before editing, instead of executing the instruction literally.

### Analysis and export rules

- Per-team injury analysis source exports keep the original standardised-file columns only. Do not append origin/status/review columns. Format `Date Injured` and `Confirmed Return Date` as `DD/MM/YYYY`. Retain excluded rows, mark all excluded rows with red text in the Excel workbook, and mark only blank source cells populated by the pipeline with green text. The CSV is the machine-readable companion with the same rows, columns, and values.
- **Do not replace missing values with zero. Do not impute** unless the protocol and analysis plan explicitly require it.
- Handle ongoing/unclosed injuries as censored observations per the analysis plan. Do not silently drop them from severity analyses.
- Record match and training exposure separately. Preserve native daily/weekly granularity; aggregate to a common level for comparison rather than fabricating daily observations from weekly totals.
- Device-derived exposure filters require documented vendor/device context, an a priori rule, removal counts, and sensitivity analysis.
- Report data completeness and team coverage alongside estimates. Low or uneven reporting distorts incidence and burden.
- **League dashboards must pool raw injury counts, days lost, and exposure before deriving** incidence, burden, and mean severity. Snapshot team and league payloads from approved build-pinned sources and enforce candidate equality before insert.
- Likely core outputs, subject to the frozen analysis plan: counts, incidence per 1,000 player-hours, severity, burden, prevalence, confidence intervals, and stratification by match/training, diagnosis/body area, mechanism, and team/season.

References: [IOC 2020 consensus and STROBE-SIIS](https://bjsm.bmj.com/content/54/7/372) · [Fuller et al. 2007 rugby union consensus](https://bjsm.bmj.com/content/41/5/328) · [World Rugby injury surveillance](https://www.world.rugby/the-game/player-welfare/medical/injury/surveillance) · [2024 team-sport surveillance framework](https://doi.org/10.1186/s40621-024-00504-6)

## 2024-25 Injury Lineage: Master, Decision Ledger, Inclusion

Restructured 2026-07-24 per `docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md`. The human-review lineage is the authoritative clean of 2024-25; the Supabase DB and released dashboards were restated from it on 2026-07-24 as bundle release `urc-2024-25-v4-6f04bd64d2a6-a2`.

Three layers, strictly separated:

| Layer | Artifact | Rule |
|---|---|---|
| **Master** | `data/2024-25/master/master_2024-25_v5.json` + generated workbook (hashes in `baseline_record.json`) | All 3,060 standardized source rows, append-only, never deleted. Exclusions marked with a controlled reason and red row formatting (755 in master; 4 further inclusion-stage removals live only in the ledger, 759 excluded overall). Value edits enter master only as recorded standardization or transcription fixes that make it MORE faithful to source. |
| **Decision ledger** | `data/2024-25/decisions/ledger.json` | Ordered and replayable. All value cleaning and inference (date corrections, Days Injured recalcs, Unknown-to-Time-Loss decisions, squad normalization) lives here, never in master. Master and inclusion visibly disagree on inferred cells by design; that is correct. |
| **Inclusion** | `data/2024-25/inclusion/urc_injury_included_dataset_2024-25.csv` | 2,301 rows x 28 columns, SHA-256 `e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb`, retained source-row mapping SHA-256 `9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f`. Generated by replay; analysis consumes only this layer. Never add headline metrics to it. |

Working rules:

- The formatted master workbook and the inclusion CSV are **generated artifacts. Never hand-edit either.** The change loop is: author one decision record (row, field, old to new, reason), run `python3 tools/replay.py`, read the printed diff summary and flags, and stop for Abdel's manual review. That review is the gate. Anomaly checks flag but never block.
- `tools/` is four verbs: `render.py` (master data table to formatted workbook, plus extract/compare/mark-excluded), `replay.py` (baseline plus ledger to inclusion CSV, manifest, and generated `docs/METHODOLOGY.md`), `intake.py` (a team's supplied standardized pseudonymised injury CSV into a season master, append-only; frozen seasons refuse appends), `checks.py` (standing season-keyed comparability suite; structural problems FAIL, comparability observations FLAG).
- **Replay must reproduce the accepted inclusion CSV byte-for-byte from the v5 baseline.** Any difference is a defect or a new decision, never something to patch silently. Old-value guards classify ledger entries as applied, materialized-in-master, or conflict; conflicts stop the line for review.
- The frozen 2026-07-23 workbook under `outputs/urc_final_human_review_2024-25/` is the read-only pre-baseline reference and is kept. The v3/v4 provenance correction is recorded in `PROVENANCE_ADDENDUM_SHARKS_V3_V4_2026-07-24.md` there and in the rule changelog.
- Open items ride in the ledger's `open_items` (currently source row 1735, fit date precedes injury date; and source row 210, a manually applied fit-date year normalization recorded during ledger reconstruction). They stay flagged until Abdel adjudicates them.
- Per-team Standardization Records under `data/2024-25/intake/standardization_records/` document (never re-execute) each club's dirty-source bridge. Do not fill a gap without new evidence; record disagreements instead of picking a side.
- Preserve real missingness: never replace blanks with zero, never impute clinical or return-date fields without an approved ledger rule. Season-scoped row adjudications are never carried into a new season; versioned rules carry forward.

## Releases

Full procedure: `docs/PIPELINE_RUNBOOK.md`. Binding rules:

- **2024-25 injury lineage (simplified path, in force since 2026-07-24):** regenerate from baseline plus ledger, read the diff summary, obtain Abdel's recorded yes, then rewrite the per-team parity exports with `export-team-dashboards`. No preflight/candidate/checksum-envelope ceremony for routine updates.
- **Any team/season outside that lineage** uses the retained V1 ceremony in the runbook, one step at a time, with Abdel's per-team sign-off.
- Profile approval never authorizes a database action. Reconfirm the exact hosted target and obtain separate approval for each named live action.
- `release` and `release-league` refuse a dirty Git tree by default. Commit implementation changes first. If Abdel explicitly authorises concurrent work, `release-league` alone may use `PIPELINE_ALLOW_DIRTY_RELEASE_LEAGUE=1` after every release-owned file is committed; it records the override in release parameters and leaves unrelated paths untouched. Never use the override for uncommitted pipeline, migration, evidence, or payload changes.
- **After every accepted `release-league` promotion, run `python3 -m pipeline export-team-dashboards --season <season>`** or the 16 committed per-team parity exports go stale against the served bundle.
- An approved database release is **not** a route or public-promotion action. Any status change in `config/teams.ts`, access-control restoration, deployment, sharing, or production cutover remains a separate explicit approval.

## Cross-Season Reproducibility

The pipeline must stay re-runnable: a new season's pseudonymised intake goes in, a published dashboard comes out, applying the same versioned rules. Three layers, because only the first carries forward:

| Layer | Lives in | Carry-forward |
|---|---|---|
| **Rules** (case/time-loss definitions, cohort/season-window logic, IOC bucket mappings, diagnosis inference precedence, exposure grain handling, severity bands, exclusion criteria) | Versioned migrations/views (`analysis.*_vN`) | Re-runs unchanged on later seasons |
| **Row-level adjudications** (date corrections, duplicate exclusions, individual ambiguity rulings) | `audit.adjudications`, keyed to source rows | Season-specific; reapplied by the pipeline, never baked into code, never carried blindly |
| **Per-team source mappings** (column/codebook translation) | Versioned per team | Revalidate through the profiling gate whenever that club's export changes |

Binding consequences:

- **A rule that exists only in a dev-only preview file (e.g. `tools/sql/dashboard_v3_preview.sql`) is not part of the pipeline and will not apply to Year 2.** Promote it to a versioned view through a migration, or it does not count and will be re-derived from scratch next season.
- Any change that alters a derived value, classification, cohort, denominator, or published figure must be recorded in `docs/PIPELINE_RULE_CHANGELOG.md` with date, rule version, what changed, why, carry-forward status, and adjudication reference. **Record it when the change is accepted, not retrospectively at season end.**
- The audit deliverable is **source to final**, not per-version: for every source row, its final published state and every decision that moved it, with reasons. Intermediate draft versions are working steps, not standalone review artifacts.

## Privacy and Data Safety

- URC is the data controller, UCD the data processor. Governance, ethics, and DPA approval covering hosted Supabase storage of pseudonymised player-level data is confirmed and recorded (Abdel, 9 July 2026). Loading pseudonymised data into the approved live Supabase target is permitted.
- Treat player names, dates of birth, IDs, and medical/injury records as sensitive. **Do not place direct identifiers in Git, logs, screenshots, fixtures, dashboard URLs, or reports.**
- Store pseudonym mappings separately with restricted access. Analysis tables use stable pseudonymous IDs.
- **Keep the re-identification codebook out of this repository and every system it touches:** not in Supabase, Git, Vercel, logs, fixtures, screenshots, or exports.
- The team-to-league-alias map is protected metadata and lives only in Git-ignored `data/intake/team_alias_map.json`. **Never hardcode name-to-alias pairs in code, docs, or anything committed to Git.**
- **Amendment (approved Abdel, 19 July 2026):** the league-comparison tab displays each club's real codebook alias (`Team A` to `Team Z`) as its comparison label, reaching the UI only through a display-time join (`TEAM_DISPLAY_ALIAS_JSON` in Git-ignored `.env.local` / deployment env). `Club NN` remains the fallback when the env var is absent.
- Treat exact placeholder strings `Team A` through `Team Z` as protected alias strings in the **data and export layers**: redact them from database `source_values` and from anything committed to Git (including `content/reporting/*.json`), and query for alias-pattern hits after live loads before release closeout. Per the amendment this ban no longer applies to the rendered comparison UI; the automated leak check is scoped to DB values, committed files, and exports.
- **On the record:** while team pages are passwordless, anyone with the URL can walk the named team dashboards, match metrics to aliased comparison rows, and reconstruct the full alias-to-team codebook. The restoration gate therefore protects the codebook itself, not only team privacy. The passwordless URL must remain private to Abdel until that gate closes. See `docs/ACCESS_RESTORATION_GATE.md`.
- Do not copy source data into this repository until intended storage, encryption, access controls, backup, retention, and deletion are confirmed.
- **Confirm the target database and environment before any write or migration. Never assume a local connection is non-production.**

## Web and Deployment Contracts

- Keep public dashboard chart copy concise: titles, values, and controls without generic instructional sublines. Do not surface internal adjudication, approval, draft-rule, or reporting-contract commentary inside chart panels. Keep necessary methodological caveats in the methodology or limitations surfaces unless Abdel explicitly requests otherwise.
- When Abdel asks to see provisional local dashboard data before adjudication, implement the reversible private preview promptly and keep methodological or approval commentary out of the visible chart UI. Scientific adjudication remains a release requirement, not a blocker to his private review.
- **Do not access or manage Vercel** through the Vercel CLI, browser automation, plugins, connectors, or APIs for this project. Use only this repository's configured environment variables; deployments remain GitHub push-triggered.
- Build V2 in a new private GitHub repository and a temporary Vercel preview project. Leave the current repository and live site unchanged until cutover. At cutover, connect the existing Vercel project `urc-scriipt-ucd` to the V2 repository so `https://urc-scriipt-ucd.vercel.app` stays the production URL; retain the previous deployment as rollback.
- Preserve the current site's recognizable URC/UCD dark navy and cyan design, hero media, navigation/routes, team grid, and dashboard skeleton. Improve only evidenced defects, responsiveness, accessibility, performance, and information clarity.
- **Temporary pre-production review state (approved Abdel, 14 July 2026):** every team marked `live` may expose only its approved aggregate dashboard directly, without a password or team session. This is for Abdel's private review and is **not** approval for public production access.
- The temporary review build must not contain password forms, password/session API routes, password secrets, or misleading unlock/logout controls. Git history retains the reviewed protected-access implementation for later restoration.
- **Before the V2 URL is shared with teams or the public, or before production cutover, complete `docs/ACCESS_RESTORATION_GATE.md`.** Treat every legacy password as public.
- No upload or admin interface. Preview deployments must not run data imports, cleaning jobs, migrations, or destructive writes against the hosted database.
- **Do not suppress small aggregate counts by default.** Exact `0`, `1`, and other small counts are retained and may be shown unless Abdel explicitly approves a later disclosure rule.

## Local Commands

- Install: `npm install`. Website: `npm run dev`. Build check: `npm run build`.
- **DB access:** parse `.env.local` yourself (never `source` it, never print values). Use `SUPABASE_DB_URL_POOLER`; the direct host times out, and pipeline child processes need `SUPABASE_DB_URL` set to the pooler value. Read-only queries: `node pipeline/sql_query.mjs <sql-file>` (file-path argument; inline SQL hits ENAMETOOLONG). Writes: `node pipeline/sql_exec.mjs`, which does **not** self-register migrations; insert the tracking row manually after applying one.
- **Pipeline CLI:** `npm run pipeline -- <subcommand>` or `python3 -m pipeline <subcommand>`. Canonical sequence in `docs/PIPELINE_RUNBOOK.md`. Support commands: `adjudicate-duplicate-exclusion`, `reapply-adjudications`, `verify-analysis-parity`, `reconcile-curated`, `trace-row`, `retire-releases`, `export-team-dashboards`, `self-check` (`npm run pipeline:check`). The retired `build-team-dashboard` and `build-munster-dashboard` routes intentionally refuse to run.
- All of `data/` is Git-ignored. `content/reporting/*.json` is an emergency/parity export and public payload, **not an application input**: no internal `source_files`, `pipeline_evidence`, hashes, or audit paths. `lib/reporting.ts` queries the reporting views server-side via the least-privilege `web_reader` role (`WEB_READER_DB_URL`). Live team pages are dynamic and currently need no password; a missing credential, database error, or missing approved bundle fails closed to the unavailable shell.
- Database writes/migrations run only against the explicitly approved live Supabase/Postgres target. Confirm the exact project/connection first.
- **No hosted Supabase, GitHub, or Vercel action is part of the local spine unless Abdel explicitly approves that exact external target and action.**

## Standing Watch-Outs

- The served 2024-25 release is V5 with the inclusive 1 September 2024 to 30 June 2025 cohort. Historical July and August curated exposure rows remain immutable; V5 re-admits only rows whose sole historical blocker was `outside_official_analysis_window` and whose native period overlaps V5, while preserving every other exclusion. The 1 to 19 September semantic non-URC-match rule applies only to the newly opened pre-URC band. Coverage counters come from the shared effective cohort snapshots, not an inherited predecessor payload. Do not mutate curated rows, rebuild exposure, or generalise the rule outside its recorded scope. The retired V4 tuple remains the reporting rollback path. See `docs/evidence/analysis_window_2024-25_v5.json`.
- `reporting.team_metric_aggregates` and `reporting.latest_team_metric_aggregates` are the legacy headline path; new releases deliberately do not populate them. **Do not "fix" that.**
- Leinster, Munster, Connacht, and Ulster report exposure weekly. Confirm the grain from each current intake and pass `--reporting-grain weekly` explicitly; the frozen analysis views derive weekly handling from `curated.exposure.grain`. `reporting.teams.weekly_reporter` is a documented placeholder and does not drive the metrics, so do not edit a frozen migration or add team-name inference to change it.
- Teams released before the Phase 3.5 cohort amendment have `record_versions` predating current rule versions but exact release parity. **Do not reprocess them without a new recorded adjudication.**
- The `web_reader` role is created NOLOGIN by migration; LOGIN and password were set out-of-band. To rotate: write the new password to a chmod-600 scratch SQL file, apply, delete the file, update `.env.local`. Never echo it.
- **Python: `Path("")` is truthy.** A release-export bug came from `Path(x or "") or default` (fixed in `0e27bf1`). Do not reintroduce that pattern.

## Decisions Still Required

Canonical schemas, code lists, and case/time-loss/severity/exposure definitions are frozen in the `_v1` views and `curated.code_lists` (10 July 2026). Still open:

- Union access model (union-scoped passwords and approved union aggregates). Placement is decided: unions live on the standalone `/unions` page, not the main dashboard grid.
- Keep or remove the synthetic demo team tile in the 17-tile grid.
- `/about` route: retain as unlinked compatibility route, redirect to `/about-us`, or remove.
- Small-cell disclosure rule. Small counts are currently NOT suppressed; any suppression needs Abdel's explicit approval.
- Device/vendor-specific exposure validity rules for teams whose intake requires them (weekly reporters keep their native grain).
