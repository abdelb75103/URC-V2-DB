# URC Injury Surveillance Database Pipeline

## Project Overview

This repository rebuilds the URC injury and exposure-data workflow as a database-backed, reproducible research pipeline. It will support cleaned season datasets, analysis, dashboards, league and club reports, and a defensible methodology section. The legacy workflow relied on spreadsheets, manual pastes, and hard-coded outputs; use it for context only, not as the source of truth.

Munster is the pilot. Freeze its accepted workflow and schema, then apply that same version to the other 15 teams. Reuse the Year 1 workflow for Year 2 so cross-season comparisons are based on consistent definitions and processing. The accepted foundation is in `docs/V2_FOUNDATION.md`.

## Source Archive

- Reference-only legacy archive: `/Users/abdelbabiker/Desktop/URC` (145 files across 16 team folders).
- It contains heterogeneous raw injury and GPS/exposure exports, team mapping codebooks, standardised workbooks, cleaning reports, a cleaned injury master, prior surveillance reports, and microsite material.
- When Abdel asks to compare to V1, use the project-root workbook `/Users/abdelbabiker/Desktop/URC-V2-DB/V1 - FOR COMPARIOSN ONLY Injury & Exposure Data Master Sheet - Analysis.xlsx` only as a comparison reference. Do not ingest it, clean it, release it, or treat it as a pipeline source. Use PDFs only as narrative context unless he explicitly asks for report-level baselines.
- Never edit files in the legacy archive. Record archive originals' SHA-256 checksums and secure locators as intake provenance in UCD-managed storage; the pipeline ingests only the supplied pseudonymised intake files.
- The archive mainly concerns 2024-25 data, while historical reports include 2022-23. During team profiling, record each team's actual reporting window and coverage first. Do not treat a team-specific coverage window as the final comparable window. After all teams are profiled, choose the largest defensible comparable window and record late/missing coverage rather than silently changing denominators.
- Team inputs differ in schemas, units, daily versus weekly exposure, duration formats, and high-speed-running thresholds. Do not treat a populated standard column as proof that values are comparable.

## Target Data Flow

`immutable raw files -> ingestion manifest -> raw database records -> standardised staging records -> validated analysis records/views -> dashboard and reports`

- The database and versioned analysis views are the analytical source of truth.
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

## Pilot and Rollout

For Munster, complete and review this vertical slice before batch processing:

1. Register immutable source files and provenance.
2. Map raw fields to the canonical schema without losing source values.
3. Run validation, cleaning, exclusions, and adjudication with row-level audit events.
4. Load validated records and create analysis views.
5. Reproduce agreed injury/exposure metrics and a small report/dashboard slice.
6. Reconcile sampled records and aggregates to source evidence.
7. Generate the cleaning log and methodology inputs from recorded runs.
8. Freeze the schema, rules, reason codes, tests, and pipeline version before applying it to the remaining teams.

Any later rule change must be versioned, justified, rerun for every affected team/season, and reflected in the methodology.

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

- Canonical injury and exposure schemas and approved code lists.
- Final case, time-loss, severity, censoring, competition, and exposure definitions.
- Device/vendor-specific validity rules and the treatment of weekly reporters.
- Union dashboard placement is decided: unions are listed on the standalone `/unions` page and are not shown in the main dashboard grid. The union access model (union-scoped passwords and approved union aggregates) is still to be decided.

## Local Commands

- All of `data/` (pseudonymised intake, protected alias map, raw generated reporting exports) is Git-ignored. Reporting is DB-backed since 10 July 2026: `lib/reporting.ts` queries `reporting.latest_team_dashboard` server-side via the least-privilege `web_reader` role (`WEB_READER_DB_URL` in Git-ignored `.env.local`, and in Vercel env at cutover); team pages revalidate hourly and fail closed to the locked shell. `pipeline release` snapshots approved analysis-view aggregates into the release tables and exports `content/reporting/*.json` as an emergency artifact and parity record — the app no longer imports it, and a fresh clone still builds without `data/` or a DB credential (all team pages render the locked shell). `content/reporting/*.json` remains a public payload: no internal `source_files`, `pipeline_evidence`, hashes, or audit paths. Do not suppress small aggregate counts unless Abdel explicitly adds that rule later.
- Install dependencies: `npm install`
- Run the website: `npm run dev`
- Build check: `npm run build`
- Database writes/migrations: run only against the explicitly approved live Supabase/Postgres target; confirm the exact project/connection before running.
- Pipeline CLI: `npm run pipeline -- ingest|run|release`

No hosted Supabase, GitHub, or Vercel action is part of the local spine unless Abdel explicitly approves that exact external target/action.

## Run Closeout

At the end of every URC V2 work run, after the summary and verification, state:

- `Next`: the immediate next step for the pipeline, database, website, or governance path.
- `Manual`: what Abdel must provide or approve, such as Munster intake files, governance/DPA approval, live Supabase credentials/target, or an external GitHub/Vercel/Supabase action. Say `Manual: none` if nothing is needed.
- `Can do`: what the agent can do next, and the exact blocker to remove if any, such as "I can run the migration after approval of the live `SUPABASE_DB_URL`/Supabase project" or "I can create the private repo after approval of the target account/name".
