# URC SCRIIPT V2 Foundation

Status: accepted foundation, updated 14 July 2026

## Goal

Rebuild the 2024-25 and 2025-26 URC injury and exposure workflow as a reproducible, database-backed research system. Munster is the pilot. Once its workflow is reviewed and frozen, the same version will be applied to the other 15 teams and then reused for Year 2.

The system must produce academically defensible cleaned datasets, analysis, dashboards, reports, and methodology evidence. A result is not complete unless it can be traced to the source file, source row, pipeline run, transformation rule, and analytical query that produced it.

## Accepted Decisions

- Supabase Postgres is the data system of record.
- The hosted pilot database becomes production. Schema changes and destructive tests run locally first; no separate hosted staging database is planned.
- The formal V2 audit boundary begins with a Munster intake file containing canonical columns and pseudonymous player IDs, but no row cleaning, deduplication, value inference, or exclusions. The intake manifest must state who prepared it, when, the mapping/codebook version, and the original submission checksum and secure UCD locator where available. Carry original sheet/row locators into the intake when available and reconcile row counts. Do not claim that upstream canonicalisation or pseudonymisation is reproducible unless its script and reconciliation evidence are retained in encrypted UCD storage.
- Supabase stores the complete pseudonymised lineage: ingested rows, stage state, transformations, exclusions, corrections, adjudications, curated records, analysis views, and releases.
- Original identity mappings remain in encrypted UCD-managed storage. The re-identification codebook never enters Supabase, GitHub, Vercel, logs, test fixtures, or reports.
- The website exposes approved aggregate data only. It never returns player-level records or identifiers.
- The web application is read-only. Python commands perform ingestion, cleaning, adjudication, analysis generation, and publishing.
- Temporary pre-production review state, approved by Abdel on 14 July 2026: every `live` team dashboard is directly accessible without a password so Abdel can review the V2 website. The site still exposes approved aggregates only and has no Supabase Auth or admin interface.
- Before the V2 URL is shared with teams or the public, or before production cutover, restore shared team passwords as server-side hashes plus signed, expiring, HttpOnly, team-scoped sessions and rate-limited unlock attempts.
- The executable restoration baseline is commit `2cbfb6e`; `AGENTS.md` § "Web and Deployment Contracts" lists the exact files, secrets/WAF controls, tests, and browser acceptance checks required before sharing or cutover.
- The primary analysis window is the earliest official URC fixture through the URC final, inclusive. The same league-wide dates apply to every team. Preseason is excluded; late reporting is recorded as missing coverage rather than changing a team's study window.
- The existing website remains live and unchanged during the V2 build.
- The URC/UCD governance, ethics, and DPA approval covering hosted Supabase storage of pseudonymised player-level data is confirmed and recorded (Abdel, 9 July 2026). Pseudonymised data may be loaded into the approved live Supabase target; the re-identification codebook still never leaves encrypted UCD storage.

## Repository and Deployment

### Build phase

1. Develop V2 in a new private GitHub repository based on this workspace.
2. Use a temporary Vercel project for private previews.
3. Keep the current repository, `abdelb75103/URC-SCRIIPT-UCD`, and current Vercel project untouched.
4. Preview deployments may read approved data from the hosted Supabase project, but must not run imports, cleaning jobs, migrations, or destructive writes.

### Cutover

1. Freeze and back up the approved Supabase release.
2. Provision and verify the V2 Supabase read credential, new password hashes, cookie-signing key, and other required secrets in the existing Vercel project's Preview scope.
3. Verify the candidate deployment against the release snapshot.
4. Reconnect the existing Vercel project `urc-scriipt-ucd` from the old GitHub repository to the V2 repository.
5. Promote the already-verified secrets to Production scope and deploy V2 through the existing project so `https://urc-scriipt-ucd.vercel.app` remains the production URL.
6. Run production smoke and access-isolation checks.
7. Roll back to the prior Vercel deployment if any release gate fails.
8. Archive the old GitHub repository only after V2 is accepted.

Do not use a `/v2` route or run both applications inside one codebase. That would couple their dependencies, secrets, routing, and rollback for no long-term benefit.

## Trust Boundaries

```text
Encrypted UCD storage
  identifiable source files + re-identification codebook
                    |
                    | approved pseudonymised export
                    v
Local Python pipeline -> Supabase private data + audit schemas
                                  |
                                  | approved aggregate reporting views
                                  v
                       Next.js server-only reader
                         |                    |
                         v                    v
                 public URC pages     temporary direct team pages
```

- Pseudonymised data remains personal data because the external codebook permits re-identification.
- Stable opaque player IDs support longitudinal linkage. Human-readable labels such as `Athlete 001` are display labels, not primary keys.
- Treat the team-name to league-alias mapping as protected research metadata. Team-scoped views must not reveal league aliases.
- The Vercel application receives only a least-privilege read credential for aggregate reporting views. It does not receive a database owner or unrestricted service credential.
- The browser never connects directly to Supabase.
- Database schemas containing player-level rows and audit evidence are not exposed through the Supabase Data API.

## Data Architecture

Use four logical layers; exact table names will be finalized with the Munster schema.

1. **Ingestion:** source-file manifest, checksum, sheet/table, source row number, stable raw record ID, team, season, schema version, codebook version, and untouched source values.
2. **Processing:** typed values and ordered record versions produced by the accepted cleaning rules.
3. **Audit:** pipeline runs, step runs, record events, exclusions, flags, adjudications, parameters, code version, counts, and dataset hashes.
4. **Reporting:** curated injury/exposure records, versioned analytical views, aggregate release tables, and export manifests.

The cleaned worksheet is an export from a versioned curated view. It is never edited as an independent master dataset.

## Audit Contract

Every run records:

- Run ID, team, season, start/end time, operator, code commit, dependency lock, input checksum, parameters, status, and output checksum.
- Ordered step ID, rule name/version, input/output counts overall and by relevant strata, and input/output dataset hashes.
- For each changed, inferred, excluded, restored, corrected, or flagged record: stable raw record ID, source row, field, previous value, resulting value, action, controlled reason code, evidence fields, and review status.
- Manual adjudications with decision, rationale, reviewer, timestamp, and the rule/run that consumes the decision.
- Release ID connecting every dashboard/report metric to its cohort definition, numerator, denominator, analytical query/view version, and pipeline run.

Rows are never physically deleted. Exclusions change analytical eligibility and remain queryable. Unchanged rows are recoverable from ordered stage membership and hashes; the audit does not create redundant no-change events.

Pipeline runs recorded before 10 July 2026 predate provenance capture: their code commit, dependency lock, and operator fields are null (not backfilled), while their rule versions remain recorded per step.

## Cleaning and Inference Policy

All added or changed values belong to one class:

1. **Deterministic derivation:** reproducible calculation from named source fields.
2. **Protocol-defined inference:** explicit rule with named evidence fields and a review requirement where ambiguity remains.
3. **Manual adjudication:** recorded human decision consumed by the pipeline.

Source values are immutable. Derived or inferred values never overwrite them. Missing values do not become zero. Free-text or AI-based clinical inference cannot silently enter the analysis dataset.

Before cleaning Munster, freeze the case definition, time-loss definition, recurrence handling, severity categories, competition/training scope, exposure denominators, censoring, missing-data rules, validity thresholds, and controlled reason codes.

Exposure reporting granularity is not uniform across teams. Leinster, Munster, Connacht, and Ulster report exposure weekly. Confirm the grain from each current intake and record it explicitly rather than inferring it from the team name; other teams must likewise be profiled from their own file evidence. Analysis views preserve the native grain and aggregate comparably rather than treating weekly rows as session rows.

## Operational Pipeline

The current commands, evidence chain, approval gates, and row/metric tracing procedure are maintained in `docs/PIPELINE_RUNBOOK.md`. SQL migrations define the database; the `pipeline` package is the supported processing interface; and the website is a read-only reporting consumer. Do not duplicate cleaning formulas in the website, spreadsheet exports, local review tools, or one-off scripts.

## Website Architecture

- Next.js App Router on Vercel.
- Server-render approved league and live-team aggregates from reporting views. During the temporary private review, live team dashboards require no password.
- No upload, cleaning, editing, adjudication, or admin screens.
- No team JSON or passwords in `public/` or Git history.
- League and team pages show data coverage and release/version context with the metrics.
- Before public production, restore one signed session cookie containing the authorized team scope and expiry; verify a slow team password hash, rate-limit unlock requests, and protect preview deployments. Treat every legacy password as public and generate new high-entropy V2 passwords.
- Exact small aggregate counts are currently retained. Any future suppression or combination rule requires governance approval and a versioned release rule.

## Design Direction: Preserve and Refine

Reading: hybrid public microsite and protected analytics dashboard, redesign-preserve mode, trust-first elite-rugby tone.

Existing motifs:

- Floodlit rugby: dark navy surfaces, live-action hero footage, high-contrast cyan field-line energy.
- Continental competition: team crests and the league-to-team hierarchy.
- Clinical evidence: precise incidence, severity, burden, and exposure comparisons.

Concepts considered:

- **Floodlit evidence:** preserve the current dark/cyan sporting identity and make the data presentation more disciplined.
- **Clinical command centre:** a lighter institutional redesign; rejected because it would feel like a different website.
- **Continental mosaic:** elevate the team-grid motif; rejected because marketing spectacle would compete with repeated dashboard use.

Selected concept: **Floodlit evidence**. It preserves recognition while moving the craft into typography, spacing, responsiveness, accessibility, and information hierarchy.

Signature point of view: every team metric is presented with the approved URC benchmark and the data-coverage context needed to interpret it.

Design dials:

- Public microsite: variance 3/10, motion 2/10, density 5/10.
- Dashboards: variance 2/10, motion 2/10, density 7/10.
- Theme: dark-only, matching the current brand treatment.

Preserve:

- URC/UCD identity, dark navy and cyan palette, logos, hero video, team crests, recognizable landing-page grid, primary navigation labels and routes, dashboard tab structure, and league/team hierarchy.

Improve selectively:

- Typography and spacing consistency, chart labeling, comparison context, mobile layouts, keyboard/focus behavior, loading/empty/error states, contrast, touch targets, media loading, and broken or misleading fallbacks.
- Remove implementation debt that affects correctness: hard-coded datasets, public team files, committed passwords, duplicated middleware, ignored TypeScript/ESLint failures, and values silently defaulted to zero.

Do not change routes, navigation labels, logos, legal/consent copy, or the recognizable visual language without explicit approval. Validate changes at 390, 1280, and 1440 pixels before release.

The current site also contains union dashboards for IRFU, WRU, SARU, FIR, and SRU. Decided 9 July 2026: unions are listed on the standalone `/unions` page and removed from the main dashboard grid. Union-scoped aggregate views and shared passwords are not yet accepted into V2's access model; approve them (with cross-team governance sign-off) before any union dashboard goes live.

## Munster Pilot Acceptance Gate

Munster is complete only when:

1. The untouched input is registered and can be reproduced from its checksum and source locator.
2. Every cleaning step passes its runnable check and produces reconciled counts.
3. Every affected row has an auditable reason and before/after evidence.
4. A sampled source-to-curated reconciliation passes.
5. Curated injury and exposure exports reproduce exactly from the database.
6. Agreed incidence, severity, burden, and coverage outputs reproduce from versioned views.
7. The team and league dashboard slice reads only the frozen aggregate release.
8. The methodology log can be generated from run evidence without relying on memory.
9. Security checks confirm that player-level data and password material cannot be retrieved from public routes or the repository.
10. Desktop and mobile browser verification passes.
11. A restore rehearsal proves the database can be rebuilt from migrations, retained pseudonymised inputs, adjudication evidence, and an approved backup. If the chosen Supabase plan lacks point-in-time recovery, retain encrypted logical backups in UCD-managed storage.

After acceptance, freeze the schema, rules, reason codes, tests, and pipeline version before processing another team or season; later changes use additive versioned successors.

## DB-Backed Reporting and the V1 Freeze (10 July 2026)

The full lakehouse path is live and is the single source of truth for every published number: `ingestion` → `processing` (+ `audit`) → `curated` (typed builds) → versioned analysis views → reviewed per-team release snapshots → immutable 16-team league bundle → `reporting.latest_team_dashboard_v2` / `reporting.latest_league_dashboard_v2` (the website consumer views).

- **Releases.** `pipeline release` reads the `analysis.*_v1` views directly, snapshots all six dashboard sections, and gates on: required migrations tracked, exactly one active and non-stale curated build, adjudicated duplicate exclusions reflected in that build, section-vs-headline reconciliation, a clean protected-alias scan, and a non-dirty code version. Before a team/season's first release, `release --preflight` runs those checks read-only and renders the exact public candidate under Git-ignored `data/reporting`; the actual first release requires the reviewed candidate and named reviewer through `--preflight-file`/`--preflight-reviewer` and permits only `generated_at` to change. A re-release requires `--previous-dashboard-file`; the CLI caches, parses, and hashes the previous artifact before its first database query, requires its contents to exactly match the latest accepted full release (currently approved, or a successfully retired predecessor), applies the frozen historical whitelist against both the current candidate and serialized draft, and records the predecessor identity plus checksum in the release audit parameters. The write path uses the existing statuses as a two-transaction state machine: insert snapshot plus `started` audit evidence as invisible `draft`; serialize and verify that draft directly; then lock the team release boundary, recheck the expected predecessor, atomically promote the exact draft to `approved` while retiring superseded approved full releases, reconstruct its complete public JSON through `reporting.latest_team_dashboard` pinned to that release id, compare it with the verified draft candidate, and only then finalize the audit run as `succeeded` in the same transaction. Any failed draft or promotion is best-effort retired and marked failed, and retries use a new immutable label; if local artifact export fails after promotion, cleanup restores the exact prior approved predecessor when one existed and no newer successor displaced it. Sixteen approved 2024-25 releases exist, one per URC team; superseded releases remain retired, not deleted. Per-release evidence (labels, curated build ids, view version, code version, operator, row counts, first-release reviewer/checksum where applicable, and predecessor identity/checksum for re-releases) and the Phase 6 end-to-end reconciliation live in Git-ignored `data/reporting/phase6_acceptance_evidence_2026-07-10.json`.
- **Edinburgh restatement.** Edinburgh was re-released under the current frozen rules with Abdel's explicit approval of the number change (recorded injuries 140→115, time-loss 92→75, days lost 1,867→1,663, incidence 13.7→11.2, burden 278.4→248.0; denominator unchanged). The exclusion attribution is recorded in the release's `injury_cohort_filters` and the diff record retained with the release evidence.
- **Bundle and website.** A per-team `pipeline release` preserves the reviewed member snapshot but does not change the site until `pipeline release-league` promotes a reviewed immutable 16-team bundle. Classification-only successors use versioned incremental candidates: the approved payload is copied and only `body_locations`, `injury_types`, and `injury_profiles` are replaced from the accepted classification views; unrelated metrics are neither recalculated nor overwritten. The successor is still a new immutable release and the predecessor is retained for rollback. `lib/reporting.ts` queries `reporting.latest_team_dashboard_v2` and `reporting.latest_league_dashboard_v2` server-side through the `web_reader` role; those views expose only whitelisted fields from the latest approved complete bundle. Team pages are dynamic and, during the temporary private review approved on 14 July 2026, every team marked `live` is directly accessible without a password. A missing credential, database error, or missing approved bundle fails closed to the unavailable shell. `content/reporting/*.json` remains an emergency artifact and parity record, but the app does not import it. The `web_reader` credential lives only in Git-ignored `.env.local` and the review deployment environment.
- **Frozen as of migrations `20260710130000` and `20260710150000`:** the `analysis.*_v1` view definitions, the `curated` schema, the controlled reason codes, the release gates, and the dashboard-JSON diff whitelist. The first-release preflight is an operational pipeline safety gate only; it does not change the frozen curated schema, `_v1` metric definitions, cohort, or release payload. Any analytical rule change still requires a new versioned migration (e.g. `_v2` views), a recorded adjudication of why, and a rerun plus re-release for every affected team/season — never an edit in place.
- **Rollout.** All 16 teams completed the 2024-25 path and are marked `live` for the private passwordless review. Every new team/season follows `docs/PIPELINE_RUNBOOK.md`: local profile and injury/exposure preparation; separate checksum-matched registrations and processing runs; once-per-season fixture loading; curated build; reconciliation/parity; reviewed team release; and reviewed immutable league-bundle release. A database release, bundle promotion, route status, access-control change, deployment, sharing, and production cutover remain distinct approval boundaries.

## Next Step

Review the passwordless private V2 site across all 16 approved team dashboards. Before the URL is shared or production cutover begins, execute the protected-access restoration gate in `AGENTS.md`, configure the least-privilege `web_reader` credential, and smoke-test the dynamic team routes at desktop and mobile widths.

## Remaining Scope Decisions

- Union placement is decided (standalone `/unions` page, off the main grid); the union access model (union-scoped passwords and approved union aggregates) remains open.
- Keep the synthetic demo team in the recognizable 17-tile grid, or remove it with approval.
- Retain `/about` as an unlinked compatibility route, redirect it to `/about-us`, or remove it after checking external links.
- Approve the aggregate small-cell disclosure threshold and release-review process.
