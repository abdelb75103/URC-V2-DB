# URC SCRIIPT V2 Foundation

Status: accepted foundation, 6 July 2026

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
- Public users see approved URC league-wide outputs. Each team receives one shared password for its own dashboard. V2 has no Supabase Auth or admin interface.
- Shared passwords are stored as server-side hashes in Vercel secrets. Successful unlocks create signed, expiring, HttpOnly, team-scoped cookies.
- The primary analysis window is the earliest official URC fixture through the URC final, inclusive. The same league-wide dates apply to every team. Preseason is excluded; late reporting is recorded as missing coverage rather than changing a team's study window.
- The existing website remains live and unchanged during the V2 build.
- No player-level data, including pseudonymised data, enters hosted Supabase until the applicable URC/UCD governance, ethics, DPA, region, retention, and backup approval is recorded. Structural inspection and data-dictionary work may proceed inside approved UCD storage.

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
                 public URC pages     password-gated team pages
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

## Cleaning and Inference Policy

All added or changed values belong to one class:

1. **Deterministic derivation:** reproducible calculation from named source fields.
2. **Protocol-defined inference:** explicit rule with named evidence fields and a review requirement where ambiguity remains.
3. **Manual adjudication:** recorded human decision consumed by the pipeline.

Source values are immutable. Derived or inferred values never overwrite them. Missing values do not become zero. Free-text or AI-based clinical inference cannot silently enter the analysis dataset.

Before cleaning Munster, freeze the case definition, time-loss definition, recurrence handling, severity categories, competition/training scope, exposure denominators, censoring, missing-data rules, validity thresholds, and controlled reason codes.

Exposure reporting granularity is not uniform across teams. Team aliases I, J, K, and L reported exposure weekly; all other team aliases reported exposure per session. Analysis views must preserve this native grain and aggregate comparably rather than treating weekly rows as session rows.

## Minimal Modules and Commands

Keep the implementation small and concentrated behind four command interfaces:

```text
pipeline ingest      register and load an untouched pseudonymised input
pipeline run         execute a named, versioned cleaning pipeline
pipeline adjudicate  import and validate recorded manual decisions
pipeline release     build frozen analytical views and exports
```

SQL migrations define the database. Python contains transformation logic and small runnable checks. Do not duplicate cleaning formulas in the website or spreadsheet exports. Keep only scripts used by an accepted run.

## Website Architecture

- Next.js App Router on Vercel.
- Server-render approved league aggregates and password-gated team aggregates from reporting views.
- No upload, cleaning, editing, adjudication, or admin screens.
- No team JSON or passwords in `public/` or Git history.
- A team-scoped session can request only its allow-listed aggregate reporting views.
- Unknown, expired, or mismatched sessions fail closed.
- League and team pages show data coverage and release/version context with the metrics.
- Use one signed session cookie containing the authorized scope and expiry; do not encode authorization in cookie names. Store and rotate the signing key through Vercel secrets.
- Unlock requests must name one team, verify a slow password hash with constant-time comparison, and be rate-limited per team and source at the Vercel edge or equivalent. Record security events without player or injury data.
- Treat every password committed to the legacy repository as public. Generate and distribute new high-entropy team passwords for V2; V2 must never accept a legacy password.
- Protect every temporary Vercel preview deployment so its URL is not an unauthenticated side door.
- Apply an approved disclosure-control rule to small or rare aggregate cells before release. The threshold and suppression/combination method require governance approval and must be versioned with the release.

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

The current site also contains union dashboards for IRFU, WRU, SARU, FIR, and SRU. Union dashboards are not yet accepted into V2's access model. Before reporting/session implementation, explicitly either approve union-scoped aggregate views and shared passwords with cross-team governance approval, or approve removal of those routes from V2.

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

After acceptance, freeze the schema, rules, reason codes, tests, and pipeline version before processing the remaining teams.

## Next Step

When the Munster file arrives, inspect its structure without changing it, calculate its checksum, complete its intake provenance manifest, identify the canonical injury/exposure fields, and draft the data dictionary and validation contract. Do not upload player-level data to hosted Supabase until governance approval is recorded. Do not clean rows until the scientific protocol and the first ordered cleaning steps are approved.

## Remaining Scope Decisions

- Include union dashboards with union-scoped aggregate access, or explicitly remove the five union routes.
- Keep the synthetic demo team in the recognizable 17-tile grid, or remove it with approval.
- Retain `/about` as an unlinked compatibility route, redirect it to `/about-us`, or remove it after checking external links.
- Approve the aggregate small-cell disclosure threshold and release-review process.
