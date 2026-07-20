# DB-Backed Reporting Plan

Status: ARCHIVED — all phases (0–6) were implemented and accepted on 10 July 2026. This is historical planning context, not an operating runbook. Use `docs/PIPELINE_RUNBOOK.md` for the current source-to-release path and `docs/V2_FOUNDATION.md` § "DB-Backed Reporting and the V1 Freeze (10 July 2026)" for the accepted foundation. The "current state" below describes 9 July 2026 and is superseded.

Goal: make the database the single source of truth for every published number. Metric
definitions live once, as versioned SQL views over curated tables. The website reads
approved release data from the database, so a change in the pipeline propagates to the
dashboards without hand-editing JSON. This plan also closes the run-provenance gap
(runs do not record the code commit, environment, or operator that produced them).

Current state (verified against the live DB, 9 July 2026):

- 6 teams ingested and processed for 2024-25 (20,746 source rows, 10,306 record
  versions, 27,812 audit events, 13 adjudications).
- Dashboard metrics are computed in Python from intake CSVs; only headline metrics
  (43 rows) reach `reporting.team_metric_aggregates`. Full dashboards exist only as
  committed JSON files.
- All 59 pipeline runs have `code_version` and `dependency_lock_hash` null; there is
  no operator column.
- Hygiene: team keys are inconsistent (`glasgow` vs `Munster`); a `Smoke Test` team
  and five `-local-smoke` releases are still `approved`; protected `Team X` alias
  strings remain in `ingestion.source_rows.source_values` (4,219 rows across
  Connacht, Leinster, Munster, Ulster, Edinburgh) and in `record_state.team_alias`
  (3,253 rows, four Irish teams).

Execution rules for every phase: human-in-the-loop (one team / one step at a time, no
monolithic command); every write goes through a recorded pipeline run with counts,
hashes, reason codes, and row-level events; migrations are reviewed before they touch
the live target; each phase ends with a verification step and a rollback note.

---

## Phase 0 — Compliance and hygiene pre-work

Do this before building anything on top of the existing rows.

**0.1 Complete the protected-alias redaction (privacy fix, first).**
- New pipeline command `redact-protected-team-aliases --scope all` extending the
  existing redaction precedent: replace exact `Team A`–`Team Z` values with
  `[REDACTED_PROTECTED_METADATA]` in (a) `ingestion.source_rows.source_values` and
  (b) `processing.record_versions.record_state ->> 'team_alias'`.
- Record one pipeline run + one `audit.record_events` row per changed row
  (action `redact`, reason code `protected_metadata_redaction`). Do not delete keys;
  replace values, so row hashes/lineage stay explainable.
- Verification: the alias-pattern query returns zero hits across all schemas; add
  that query to `self-check` and to the release gate so it can never regress.
- Note: this deliberately modifies stored state. Privacy overrides immutability here;
  the audit events preserve the fact that a redaction happened.

**0.2 Team dimension table instead of rewriting history.**
- Do not mutate historical `team` strings in ingestion/audit rows. Add
  `reporting.teams` (team_key like `munster`, display_name, union_id,
  weekly_reporter boolean, active) seeded for all 16 teams, plus a mapping of every
  legacy spelling (`glasgow`, `Munster`, `Smoke Test` → excluded).
- All curated/analysis/reporting layers key on `team_key`. Website team ids already
  match this convention.

**0.3 Retire smoke artifacts.**
- Audited run setting the `Smoke Test` releases and the five `-local-smoke` releases
  to `retired` (they are currently `approved` and eligible for the latest-release
  view). Keep the rows; never delete.

Exit gate: alias scan clean; `reporting.teams` populated; only real approved releases
remain eligible.

---

## Phase 1 — Run provenance (small, do before any further runs)

**1.1 Migration `add_run_provenance`:** `alter table audit.pipeline_runs add column
operator text;` (`code_version` and `dependency_lock_hash` already exist, unfilled).

**1.2 Pipeline change:** one helper, threaded into every `pipeline_runs` insert
(ingest, process-intake, process-exposure, adjudicate, release, redact, curated/release
commands added later):
- `code_version`: `git rev-parse HEAD` plus a `-dirty` suffix when the working tree
  has uncommitted changes (refuse to run release steps dirty).
- `dependency_lock_hash`: SHA-256 over Python version + `package-lock.json` hash.
- `operator`: `PIPELINE_OPERATOR` env var, falling back to the OS username.

**1.3 Historical honesty:** do not backfill. Add a one-line note to the methodology
docs: runs before this date predate provenance capture; their rule versions are still
recorded per step.

**1.4 Verification:** run one QA command against live; confirm the three fields are
populated. Self-check asserts the helper output shape.

---

## Phase 2 — Curated layer (typed tables built from the DB, not CSVs)

**2.1 Migration `curated_layer`:** new `curated` schema (RLS enabled, revoked from
`anon`/`authenticated`, same posture as the other private schemas):

- `curated.injuries` — one row per injury record: `source_row_id` FK,
  `record_version_id` FK (lineage), `team_key`, `season`, `player_uid`, `injury_uid`
  (unique), `date_injured date`, `days_injured int`, `derived_return_date date`,
  `is_closed boolean`, `activity_context`, `contact_context`, `recurrence_status`,
  `severity_category`, `body_location`, `injury_type`, `problem_type`,
  `eligibility_status`, `field_origins jsonb`, `source_locator jsonb`,
  `curated_build_id` FK.
- `curated.exposure` — one row per exposure record: `source_row_id`,
  `record_version_id`, `team_key`, `season`, `player_uid`, `grain`
  (`session`/`weekly`), `session_date`/`week_start_date`, `minutes_clean numeric`,
  `distance_m_clean numeric`, `scope_status`, `exclusion_reasons text[]`,
  `eligibility_status`, `curated_build_id`.
- `curated.team_exposure_denominators` — per team/season: match hours, training
  hours, total hours, method note, fixture-source checksums.
- `curated.fixtures` — the registered URC fixture list (date, home/away team_key,
  round) so windows and match counts are queryable.
- `curated.code_lists` — controlled categories loaded from
  `docs/IOC_TAXONOMY_BUCKETS.csv` plus the frozen enumerations for severity,
  activity, contact, recurrence, problem type. Category columns FK into it, so an
  invalid category cannot enter the curated layer.
- `curated.builds` — build id, `pipeline_run_id`, team_key, season, source record
  version numbers, row counts, output hash. Every curated row carries its build id.

**2.2 New command `build-curated --team --season`:** reads the accepted
`processing.record_versions` **from the database** (not files), projects the typed
columns, validates against code lists, inserts curated rows, records the run/step/
counts/hashes. Idempotence: a build for the same team/season/version set either
no-ops or requires an explicit `--rebuild` that supersedes the previous build
(old rows kept, marked superseded — consistent with never deleting).

**2.3 Reconciliation gate:** command comparing, per team, curated row counts and key
aggregates against (a) record_versions and (b) the currently published dashboard
JSONs. All six live teams must reconcile exactly before Phase 3 starts.

---

## Phase 3 — Versioned analysis views (metric definitions live here, once)

**3.1 Migration `analysis_views_v1`:** new `analysis` schema; every view suffixed
`_v1` and header-commented with its definition provenance (protocol reference):

- `analysis.injury_cohort_v1` — applies the frozen eligibility filters.
- `analysis.exposure_hours_v1` — match vs training hours per team/season, native
  grain preserved, weekly-reporter aggregation rule applied explicitly.
- `analysis.headline_metrics_v1` — counts, incidence /1000 h (numerator and
  denominator as columns), burden, days lost, mean severity.
- `analysis.monthly_v1`, `analysis.setting_split_v1`,
  `analysis.body_locations_v1`, `analysis.injury_types_v1`,
  `analysis.severity_distribution_v1`, `analysis.coverage_v1`.

Rules: views read only `curated.*`; a formula appears in exactly one view; any rule
change means a new `_v2` view plus rerun, never an edit of `_v1` after freeze.

**3.2 Parity harness:** command `verify-analysis-parity --team` renders the view
outputs into the dashboard JSON shape and diffs against the six committed JSONs.
Every discrepancy is either a view bug (fix) or a documented, signed-off improvement.
Acceptance = exact parity or an approved diff log.

---

## Phase 4 — Release rework: full dashboard payload into the database

**4.1 Migration `release_dashboards`:**
- `reporting.release_table_rows` — normalized: `release_id`, `team_key`, `season`,
  `section` (headline / setting_split / monthly / body_locations / injury_types /
  severity_distribution), `row_key`, `ordinal`, typed metric columns
  (value/numerator/denominator/unit plus the AnalyticsRow fields).
- `reporting.release_context` — per release: analysis window, method lines,
  coverage block, limitations, generated_at.
- `reporting.latest_team_dashboard` view (security_invoker) — assembles the latest
  approved release per team/season into the dashboard shape the website consumes.

**4.2 Rewrite `release`:** reads the `analysis.*_v1` views directly (no JSON file
input), snapshots every section into the release tables in one transaction, keeps and
strengthens the existing evidence gates (now also: curated build id + view versions +
non-dirty `code_version`), and **exports** `content/reporting/<team>_dashboard.json`
from the DB snapshot as a generated artifact — with internal keys (`source_files`,
`pipeline_evidence`) stripped at export, which also fixes the committed-JSON leak.

**4.3 Re-release the six live teams** through the new path once parity has passed;
retire the superseded releases. Published numbers must not change (parity gate).

---

## Phase 5 — Website reads the database

**5.1 Least-privilege reader role:** `web_reader` login role with `SELECT` on
`reporting.latest_team_dashboard` (and future approved league views) only; no access
to ingestion/processing/audit/curated. Connection via the Supabase **session pooler**
(Vercel is IPv4). Credential lives only in Vercel env settings.

**5.2 `lib/reporting.ts`:** replace the JSON imports with a server-only query,
Zod-validated into `TeamDashboardData`. Team pages switch from `force-static` to
incremental revalidation (dashboards change only at releases, so a modest revalidate
window plus on-deploy refresh is enough). Unknown team / no approved release fails
closed to the locked shell.

**5.3 Transition safety:** keep the exported JSON as an emergency build artifact
(not imported by the app). If the DB is unreachable at request time, serve the last
cached render, never a player-level error dump.

**5.4 Verification:** browser check of all six dashboards at 390/1280/1440 against
the DB-backed read; confirm `web_reader` cannot select from private schemas; confirm
no DB access from client bundles.

---

## Phase 6 — Acceptance, freeze, and rollout

- Sampled end-to-end reconciliation per team: source row → record version → curated
  row → analysis view → released row → rendered dashboard.
- Record methodology evidence: view versions, curated build ids, release ids, run
  provenance.
- Update AGENTS.md and `docs/V2_FOUNDATION.md`: reporting is DB-backed; the
  build-time JSON import contract is retired.
- Freeze `_v1` view definitions, curated schema, and reason codes.
- Process the remaining 10 teams through the full DB-backed path (ingest →
  process → build-curated → release), one team at a time.

---

## Order, dependencies, and approval points

| Step | Depends on | Live-DB writes | Approval needed |
|---|---|---|---|
| 0.1 alias redaction | — | yes | yes — write to live rows |
| 0.2 teams dimension | — | yes (new table) | migration approval |
| 0.3 retire smoke releases | — | yes (status flips) | yes |
| 1 run provenance | — | migration + inserts | migration approval |
| 2 curated layer | 0.2, 1 | migration + builds | migration approval |
| 3 analysis views | 2 (parity needs 0.1–0.3 done) | migration (views) | migration approval |
| 4 release rework | 3 parity passed | migration + re-releases | yes — re-release |
| 5 website reads DB | 4 | role creation | Vercel env + role approval |
| 6 freeze + rollout | 5 | per-team runs | per-team sign-off |

Main risks: parity mismatches between the Python/CSV calculations and the SQL views
(expected; the harness exists to surface them one by one), Vercel-to-Supabase
connectivity (must use the session pooler), and grant mistakes on new schemas
(mitigated by copying the existing revoke-all posture and testing as `web_reader`).
