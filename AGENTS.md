# URC Injury Surveillance Database Pipeline

## Project Overview

This repository rebuilds the URC injury and exposure-data workflow as a database-backed, reproducible research pipeline. It will support cleaned season datasets, analysis, dashboards, league and club reports, and a defensible methodology section. The legacy workflow relied on spreadsheets, manual pastes, and hard-coded outputs; use it for context only, not as the source of truth.

The Munster pilot is complete and the workflow is frozen (10 July 2026): the `curated` schema, `analysis.*_v1` view definitions, controlled reason codes, release gates, and dashboard-JSON diff whitelist. Six approved 2024-25 releases exist (Connacht, Edinburgh, Glasgow, Leinster, Munster, Ulster). The current phase is: (a) roll the same frozen path out to the remaining ten teams, one at a time with per-team sign-off, as intake files arrive; and (b) the Vercel cutover, which is Abdel's explicit manual call because Edinburgh's public numbers change at that deploy. Reuse the Year 1 workflow for Year 2 so cross-season comparisons are based on consistent definitions and processing. The accepted foundation and the freeze record are in `docs/V2_FOUNDATION.md` (§ "DB-Backed Reporting and the V1 Freeze"). Any rule change requires a new versioned migration (e.g. `_v2` views), a recorded adjudication of why, and a rerun plus re-release for every affected team/season — never an edit in place.

## Source Archive

- Reference-only legacy archive: `/Users/abdelbabiker/Desktop/URC` (145 files across 16 team folders).
- It contains heterogeneous raw injury and GPS/exposure exports, team mapping codebooks, standardised workbooks, cleaning reports, a cleaned injury master, prior surveillance reports, and microsite material.
- When Abdel asks to compare to V1, use the project-root workbook `/Users/abdelbabiker/Desktop/URC-V2-DB/V1 - FOR COMPARIOSN ONLY Injury & Exposure Data Master Sheet - Analysis.xlsx` only as a comparison reference. Do not ingest it, clean it, release it, or treat it as a pipeline source. Use PDFs only as narrative context unless he explicitly asks for report-level baselines.
- Never edit files in the legacy archive. Record archive originals' SHA-256 checksums and secure locators as intake provenance in UCD-managed storage; the pipeline ingests only the supplied pseudonymised intake files.
- The archive mainly concerns 2024-25 data, while historical reports include 2022-23. During team profiling, record each team's actual reporting window and coverage first. Do not treat a team-specific coverage window as the final comparable window. After all teams are profiled, choose the largest defensible comparable window and record late/missing coverage rather than silently changing denominators.
- Team inputs differ in schemas, units, daily versus weekly exposure, duration formats, and high-speed-running thresholds. Do not treat a populated standard column as proof that values are comparable.

## Target Data Flow

This is a lakehouse (medallion) layout on Supabase Postgres, live since 10 July 2026:

`immutable intake files -> ingestion (source_files, source_rows) -> processing (record_versions) -> curated (builds, injuries, exposure, fixtures, code_lists, team_exposure_denominators) -> analysis.*_v1 views -> reporting releases (aggregate_releases, release_context, release_table_rows) -> reporting.latest_team_dashboard -> website`

The cross-cutting `audit` schema (`pipeline_runs`, `step_runs`, `record_events`, `adjudications`, `reason_codes`) is written at every step; nothing moves between layers without a recorded run.

- The database and versioned analysis views are the analytical source of truth. Metric definitions (incidence, severity, burden, coverage, stratifications) live once, in the frozen `analysis.*_v1` SQL views — never reimplemented in Python, the website, or exports.
- Releases are keyed by team + season; superseded releases are retired, never deleted, so year-on-year comparison and restatement history are queries, not re-cleans.
- Supabase Postgres stores all pseudonymised ingestion, processing, audit, curated, and reporting layers. The browser never connects directly to Supabase.
- This project writes straight to the live Supabase/Postgres database; there is no Docker/local Supabase workflow. The live DB connection is stored in `.env.local` as `SUPABASE_DB_URL`/`DATABASE_URL`; load it for approved pipeline commands without printing secret values. Do not run `supabase start`, `supabase migration up --local`, or `supabase db query --local`. Treat every database write, migration, ingest, processing run, adjudication, or release as live-impact work requiring explicit approval of the exact hosted target.
- The formal V2 audit boundary starts at the supplied canonical, pseudonymised intake file. Record its preparer, timestamp, mapping/codebook version, checksum, secure original-file locator/checksum where available, row reconciliation, and carried source-row locators; do not claim upstream reproducibility without its retained script/evidence.
- Dashboards and reports must query shared views or exported results from the pipeline. Do not reimplement metrics or cleaning rules in presentation code.
- Keep source-reported, deterministically derived, inferred, and manually adjudicated values distinguishable. Never overwrite the original value.
- Prefer exclusion/status fields and analysis views over deleting records.

## Audit Trail Contract

Every result must be traceable back to the source file and source row/cell.

- At ingestion, record: source file, sheet/table, original row number, stable raw record ID, file checksum, import timestamp, and source season/team.
- For every run, record: run ID, ordered step ID, timestamp, final script/version or commit, parameters, environment/dependency lock, input/output hashes, and before/after counts overall and by team.
- For every changed, excluded, restored, or flagged record, record: raw record ID, field, old value, new value where applicable, action, controlled reason code, human-readable rationale, rule/version, and reviewer/adjudication status.
- Retain excluded rows in an audit/quarantine table so a statement such as “step 3 excluded source rows 1, 7, 10, and 12 for these reasons” can be reproduced exactly.
- Ambiguous joins are review cases. Do not silently choose the nearest date, duration, or distance match when a unique key is unavailable.
- Manual corrections must enter through a recorded adjudication table/file and then be reapplied by the pipeline; never hand-edit a cleaned output.
- Each published metric must be traceable to a pipeline run, analysis view/query, cohort definition, numerator, and denominator.
- The workflow is human-in-the-loop. Do not build or require a monolithic command that runs every step for every team. Each small verified step must still record its inputs, rules/version, counts, hashes, and review/adjudication status.
- `run` may stay lightweight only as orchestration: it does not need to execute the whole team pipeline, but any script/step that changes, derives, flags, excludes, validates, or exports data must capture what ran, on which inputs, with which rules/parameters, and what changed. `release` is the promotion boundary: provisional outputs can stay local/draft, but any dashboard/reporting aggregate used as a final output must record which processed inputs, checks, and run evidence produced it.
- Keep only the final scripts actually used by the accepted pipeline. Remove superseded scratch scripts after their logic is rejected or incorporated; version control preserves history once it is established.
- The web application is read-only. Run ingestion, cleaning, adjudication, analysis generation, and releases through versioned Python commands.

## Scientific and Analytical Rules

- Freeze a written protocol before the pilot clean: population, season window, injury case definition, time-loss definition, match/training scope, exposure denominator, severity categories, missing-data handling, recurrence rules, censoring, competition eligibility, and all exclusion thresholds.
- Treat legacy cleaning rules as hypotheses. The archive contains conflicting season endpoints and exposure filters, unverified GPS-noise thresholds, manual spreadsheet steps, and potentially unsafe closest-match reconciliation.
- Do not infer clinical categories from free text unless the protocol defines the rule and the output is labelled as inferred. Preserve the source value and confidence/review status.
- Body location and injury tissue/pathology must always be bucketed into the controlled IOC 2020 consensus categories listed in `docs/IOC_TAXONOMY_BUCKETS.csv`, or left as `Unknown` when no defensible source/code evidence exists. Orchard/OSIICS codes and source text are evidence for mapping into those buckets; they are not separate reporting buckets.
- Comparable injury-analysis columns must be standardised through the shared pipeline rules before cross-team analysis: `Occasion category` (`match`, `training`, `unknown`), `Match Type` (`URC`, `training`, `unknown`), problem type, injury status, fit-for-selection status, return date origin, severity/time-loss category, recurrence, contact context, body location, and tissue/pathology. Preserve source values and carry origin fields for derived, mapped, or inferred values.
- Per-team injury analysis source exports must keep the original standardised-file columns only. Do not append origin/status/review columns. Format `Date Injured` and `Confirmed Return Date` as `DD/MM/YYYY`; retain excluded rows, mark all excluded rows with red text in the Excel workbook, and mark only blank source cells populated by the pipeline with green text. Keep the CSV as the machine-readable companion with the same rows, columns, and values.
- Do not replace missing values with zero. Do not impute unless the protocol and analysis plan explicitly require it.
- Handle ongoing/unclosed injuries as censored observations according to the analysis plan; do not silently drop them from severity analyses.
- Record match and training exposure separately. Preserve native daily/weekly granularity; aggregate to a common level for comparison rather than fabricating daily observations from weekly totals.
- Device-derived exposure filters require documented vendor/device context, an a priori rule, removal counts, and sensitivity analysis.
- Report data completeness and team coverage alongside estimates. Low or uneven reporting can distort incidence and burden.
- Likely core outputs, subject to the frozen analysis plan: counts, incidence per 1,000 player-hours, severity, burden, prevalence, confidence intervals, and stratification by match/training, diagnosis/body area, mechanism, and team/season.

Primary methodological references:

- [IOC 2020 consensus and STROBE-SIIS](https://bjsm.bmj.com/content/54/7/372)
- [Fuller et al. 2007 rugby union consensus](https://bjsm.bmj.com/content/41/5/328)
- [World Rugby injury surveillance resources](https://www.world.rugby/the-game/player-welfare/medical/injury/surveillance)
- [2024 team-sport injury and illness surveillance framework](https://doi.org/10.1186/s40621-024-00504-6)

## Rollout (pilot complete, rules frozen)

The Munster vertical slice and the DB-backed reporting build (Phases 0–6 of `docs/DB_BACKED_REPORTING_PLAN.md`) are accepted; per-release evidence and end-to-end reconciliation live in Git-ignored `data/reporting/phase6_acceptance_evidence_2026-07-10.json`. For each remaining team, as its pseudonymised intake file arrives, run the frozen sequence one step at a time with Abdel's per-team sign-off:

1. `ingest` — register the immutable intake file with checksum and provenance.
2. `process-intake` / `process-exposure` — standardise under the frozen rules.
3. `build-curated` — apply adjudications; the release gate requires exactly one active, non-stale build.
4. Commit any implementation changes first (`release`, including preflight, refuses a dirty Git tree), then use the applicable release gate below.
5. **First release for a team/season:** run `release --team <LegacyName> --season <season> --preflight`. This executes the release gates read-only and writes the exact public-dashboard candidate to Git-ignored `data/reporting/<team_key>_dashboard_<season>_<release_hash>_preflight.json`; it never inserts a release and refuses a preflight output under `content/reporting`. Review the candidate, then run `reconcile-curated --team <LegacyName> --season <season> --dashboard-file <candidate>` and `verify-analysis-parity --team <LegacyName> --season <season> --dashboard-file <candidate>` before obtaining Abdel's explicit sign-off. Run `release --team <LegacyName> --season <season> --preflight-file <candidate> --preflight-reviewer "Abdel Babiker"`; the CLI blocks before SQL if any field except `generated_at` changed and records both reviewer and candidate checksum in audit parameters. It inserts an invisible draft with an open audit run, verifies and serializes that exact snapshot, then atomically promotes it to approved/succeeded; a failed attempt is retired/failed and an identical retry receives a new immutable label. If local artifact export fails after promotion, cleanup restores the exact prior approved predecessor when one existed. Confirm independently with `diff-dashboard-json --preflight-release --old <candidate> --new content/reporting/<team_key>_dashboard_<season>.json`; only `generated_at` may differ.
6. **Re-release for a team/season:** snapshot the team's old JSON from HEAD with `git show HEAD:content/reporting/<team_key>_dashboard_<season>.json > data/reporting/<team_key>_dashboard_<season>_previous.json`, then run `release --team <LegacyName> --season <season> --previous-dashboard-file data/reporting/<team_key>_dashboard_<season>_previous.json`. The CLI caches, parses, and hashes that snapshot before its first database query, requires its contents to exactly match the latest accepted full release, applies the historical whitelist to both the current candidate and serialized draft, and records the predecessor identity plus checksum in audit parameters; any non-whitelisted drift blocks the release. Promotion serializes on the team row, rechecks that predecessor, and atomically retires superseded approved full releases. Confirm independently with `diff-dashboard-json --old data/reporting/<team_key>_dashboard_<season>_previous.json --new content/reporting/<team_key>_dashboard_<season>.json`, which must return ALLOWED_ONLY. The whitelist covers only `generated_at`, internal-key stripping, coverage shape, and regenerated method/limitations narrative; any numeric, label, team-name, or analysis-window drift blocks the re-release unless separately adjudicated and approved.
7. Commit that team's `content/reporting/*.json` before the next team's release, then query for protected-alias pattern hits after live loads and before closeout.

An approved database release is not a public-promotion action. Remaining clubs stay inaccessible while their `config/teams.ts` status is `locked`; changing a club to `live` and deploying are separate, explicit manual approvals. Preflight does not change either boundary.

Any later rule change must be versioned (`_v2` views via a new migration), justified through a recorded adjudication, rerun for every affected team/season, and reflected in the methodology.

Standing watch-outs learned during the pilot:

- `reporting.team_metric_aggregates` and `reporting.latest_team_metric_aggregates` are the legacy headline path; new releases deliberately do not populate them. Do not "fix" that.
- Teams released before the Phase 3.5 cohort amendment have `record_versions` predating current rule versions but exact release parity — do not reprocess them without a new recorded adjudication.
- The `web_reader` role is created NOLOGIN by migration; LOGIN and password were set out-of-band. To rotate: write the new password to a chmod-600 scratch SQL file, apply, delete the file, update `.env.local` — never echo it.
- Python: `Path("")` is truthy — a release-export bug came from `Path(x or "") or default` (fixed in `0e27bf1`); do not reintroduce that pattern.

## Privacy and Data Safety

- URC is the data controller and UCD is the data processor. The URC/UCD governance, ethics, and DPA approval covering hosted Supabase storage of pseudonymised player-level data is confirmed and recorded (Abdel, 9 July 2026). Loading pseudonymised data into the approved live Supabase target is permitted.
- Treat player names, dates of birth, IDs, and medical/injury records as sensitive. Do not place direct identifiers in Git, logs, screenshots, fixtures, dashboard URLs, or reports.
- Store pseudonym mappings separately with restricted access. Analysis tables should use stable pseudonymous IDs.
- Keep the re-identification codebook only in encrypted UCD-managed storage. Never place it in Supabase, Git, Vercel, logs, fixtures, screenshots, or exports.
- Treat the team-to-league-alias map as protected metadata; team-scoped outputs must not expose league aliases.
- The alias map lives only in Git-ignored `data/intake/team_alias_map.json` (authoritative backup in encrypted UCD storage); never hardcode name-to-alias pairs in code, docs, or anything committed to Git.
- Treat exact placeholder strings such as `Team A` through `Team Z` as protected aliases too. Redact them from database `source_values`, not only from committed exports, and after live loads query for alias-pattern hits before release closeout.
- Do not copy source data into this repository until the intended storage, encryption, access controls, backup, retention, and deletion process is confirmed.
- Confirm the target database and environment before any write or migration. Never assume a local connection is non-production.

## Web and Deployment Contracts

- Build V2 in a new private GitHub repository and a temporary Vercel preview project. Leave the current repository and live site unchanged until cutover.
- At cutover, connect the existing Vercel project `urc-scriipt-ucd` to the V2 repository so `https://urc-scriipt-ucd.vercel.app` remains the production URL; retain the previous deployment as rollback.
- Preserve the current site's recognizable URC/UCD dark navy and cyan design, hero media, navigation/routes, team grid, and dashboard skeleton. Improve only evidenced defects, responsiveness, accessibility, performance, and information clarity.
- Public routes may expose only approved league aggregates. Team routes may expose only approved aggregate data for the team identified by a signed, expiring, HttpOnly team session.
- V2 deliberately uses shared team passwords, not user accounts or Supabase Auth. Store password hashes and signing secrets only in Vercel environment secrets; never commit them.
- Treat every legacy password as public and generate new high-entropy V2 passwords. Verify a named team's password with a slow hash, issue one signed scope/expiry cookie, rate-limit unlock attempts, and protect preview deployments.
- No upload or admin interface. Preview deployments must not run data imports, cleaning jobs, migrations, or destructive writes against the hosted database.
- Do not suppress small aggregate counts by default. Exact `0`, `1`, and other small counts are retained and may be shown unless Abdel explicitly approves a later disclosure rule.

## Decisions Still Required

The canonical schemas, code lists, and case/time-loss/severity/exposure definitions are decided and frozen in the `_v1` views and `curated.code_lists` (10 July 2026); they are no longer open. Still open:

- Union access model (union-scoped passwords and approved union aggregates). Placement is decided: unions live on the standalone `/unions` page, not the main dashboard grid.
- Keep or remove the synthetic demo team tile in the 17-tile grid.
- `/about` route: retain as unlinked compatibility route, redirect to `/about-us`, or remove.
- Small-cell disclosure rule — currently small counts are NOT suppressed; any suppression needs Abdel's explicit approval.
- Device/vendor-specific exposure validity rules for teams whose intake requires them (weekly reporters keep their native grain per the frozen rules).

## Local Commands

- All of `data/` (pseudonymised intake, protected alias map, raw generated reporting exports) is Git-ignored. Reporting is DB-backed since 10 July 2026: `lib/reporting.ts` queries `reporting.latest_team_dashboard` server-side via the least-privilege `web_reader` role (`WEB_READER_DB_URL` in Git-ignored `.env.local`, and in Vercel env at cutover); team pages revalidate hourly and fail closed to the locked shell. `pipeline release` snapshots approved analysis-view aggregates into the release tables and exports `content/reporting/*.json` as an emergency artifact and parity record — the app no longer imports it, and a fresh clone still builds without `data/` or a DB credential (all team pages render the locked shell). `content/reporting/*.json` remains a public payload: no internal `source_files`, `pipeline_evidence`, hashes, or audit paths. Do not suppress small aggregate counts unless Abdel explicitly adds that rule later.
- Install dependencies: `npm install`
- Run the website: `npm run dev`
- Build check: `npm run build`
- Database writes/migrations: run only against the explicitly approved live Supabase/Postgres target; confirm the exact project/connection before running.
- DB access: parse `.env.local` yourself (never `source` it, never print values). Use `SUPABASE_DB_URL_POOLER` — the direct host times out; pipeline child processes need `SUPABASE_DB_URL` set to the pooler value. Read-only queries: `node pipeline/sql_query.mjs <sql-file>` (file-path argument — inline SQL hits ENAMETOOLONG). Writes: `node pipeline/sql_exec.mjs`, which does NOT self-register migrations; insert the tracking row manually after applying one.
- Pipeline CLI: `npm run pipeline -- <subcommand>` or `python3 -m pipeline <subcommand>`. Rollout sequence: `ingest`, `process-intake`, `process-exposure`, `build-curated`, `release`, `diff-dashboard-json`. Support: `adjudicate-duplicate-exclusion`, `reapply-adjudications`, `verify-analysis-parity`, `reconcile-curated`, `trace-row`, `retire-releases`, `self-check` (`npm run pipeline:check`).

No hosted Supabase, GitHub, or Vercel action is part of the local spine unless Abdel explicitly approves that exact external target/action.
