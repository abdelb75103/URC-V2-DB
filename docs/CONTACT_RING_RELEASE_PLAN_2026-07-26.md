# Contact mechanism ring — additive release plan, 2026-07-26

Status: plan only. Nothing in this document has been applied. No migration
written, no database action taken.

Scope: **the contact mechanism ring only.** Per-setting severity is explicitly
out of scope (see "Deliberately excluded").

Class: **T4.** It writes a migration and promotes a live release bundle. It
needs Abdel's explicit approval of the exact hosted target for each named live
action, and one independent `sol_xhigh` review before promotion.

---

## Where things stand

The 2024-25 served release is **V5**: live release
`a5a07fca-1be6-4ead-9a6b-648a3475c205`, label `urc-2024-25-v5-45169a66a7da-a1`,
approved 26 July 2026. The changelog records a deployment blocker against it
(push reached `origin/main`, the repository-linked V2 domain returned
`DEPLOYMENT_NOT_FOUND`). That is a GitHub-to-Vercel trigger problem, not a
database or payload problem, and it is independent of this work. **Resolve it
before or after, but do not conflate it with this release.**

The dashboard UI for the ring is already built and committed (`7d01d57`). It
renders a half-ring with Contact / Non-contact / Unknown beside the match and
training bench on the overview tab. It currently reads
`supplement.contact_distribution`, so on the live site it renders nothing at
all. The only work left is getting the data into the release and repointing the
component at it.

## Why this is additive and not a rebuild

`contact_context` is already populated on `curated.injuries` for the released
build. It is a frozen pipeline derivation (`contact_context()` in
`pipeline/__main__.py`) from the inclusion CSV's `Is Contact` column, with a
recorded origin per row and a frozen three-value code list in
`curated.code_lists`. No re-clean, no reprocessing, no new adjudication.

The precedent is `20260722150000_incremental_classification_bundle_release.sql`,
which opens: "Classification-only bundle releases must not rebuild unrelated
dashboard metrics." It inherits the approved payload and `jsonb_set`s only the
changed sections. This plan follows that pattern exactly, except that it adds a
key rather than replacing one, so every existing section is inherited untouched.

## Verified live numbers (read-only, 26 July 2026)

League-wide, against `analysis.analysis_window_injury_cohort_v5` joined to
`curated.injuries`. **These are the acceptance targets.** If the new views do
not reproduce them exactly, stop.

| Setting | Contact | Non-contact | Unknown |
|---|---:|---:|---:|
| All (recorded) | 943 | 565 | 150 |
| All (time-loss) | 443 | 280 | 62 |
| Match (recorded) | 671 | 153 | 69 |
| Match (time-loss) | 327 | 85 | 25 |
| Training (recorded) | 270 | 406 | 66 |
| Training (time-loss) | 114 | 191 | 33 |
| Unknown setting (recorded) | 2 | 6 | 15 |

Unknown mechanism is 9% of recorded cases. The ring deliberately shows it.

---

## The work, in order

### 1. Migration: contact distribution views

New migration, additive only. Never edit a frozen view.

- `analysis.analysis_window_contact_distribution_v5` — team-level, grouped by
  `curated_build_id, team_key, season, setting_code, contact_context`, with
  `recorded_injuries` and `time_loss_injuries`.
- `analysis.analysis_window_league_contact_distribution_v5` — the league
  equivalent, joined through `analysis.league_member_releases_v2`, pooling raw
  counts before any derivation (league rule).

Note: `analysis_window_injury_cohort_v5` does **not** project `contact_context`.
Join `curated.injuries i on i.id = c.injury_id`. Do not add the column to the
released cohort view.

Emit an `all` setting row per team in addition to match / training / unknown, so
the payload shape matches what the component already consumes.

### 2. Migration: incremental payload views

Modelled on the classification precedent. Inherit the approved V5 payload and
`jsonb_set` a single new `contact_distribution` key into it, team and league.
Every other section must be inherited byte-identical; assert that.

Payload row shape, matching the existing `DashboardSupplement` contract so the
component needs no shape change:

```json
{ "key": "contact", "label": "Contact", "setting": "all",
  "recorded_injuries": 943, "time_loss_injuries": 443 }
```

Labels: `Contact`, `Non-contact`, `Unknown`.

### 3. Migration: new reader view version

**This is the step most likely to be missed.** `reporting.latest_team_dashboard_v2`
enumerates payload keys as explicit columns and is a frozen 14 July migration. A
new payload key is invisible to the web reader until a new reader version
projects it.

Create `reporting.latest_team_dashboard_v4` and
`reporting.latest_league_dashboard_v4` as `source.*` from the v3 views plus
`dashboard_payload -> 'contact_distribution'`. Grant select to `web_reader`.
Follow the v3 pattern in `20260721120000_injury_type_family_reader_v3.sql`.

### 4. Pipeline: whitelist the new export key

`classify_dashboard_json_diff()` in `pipeline/__main__.py` **blocks any
unexplained `extra_in_new` top-level key**, so the parity export diff will fail
on `contact_distribution` until it is whitelisted. Add an entry with a reason
string naming this plan. Do not widen the whitelist beyond that one path.

### 5. Release

Per the routine v5 spine now in the runbook (four commands): refresh v5
snapshots, snapshot the approved predecessor, produce one definitive preflight,
promote the reviewed file. Promotion regenerates the 17 parity exports
automatically; **do not** run a separate `export-team-dashboards`.

Start with `--plan`, which touches no database:

```bash
python3 -m pipeline release-league --season 2024-25 \
  --analysis-version v5 \
  --classification-view-version reporting_classification_2026-07-22_v2 \
  --cohort-view-version analysis_window_2024-25_2026-07-25_v1 \
  --plan
```

`release-league` refuses a dirty tree. Commit first.

### 6. Web layer

- `lib/reporting-types.ts`: add optional `contact_distribution` to
  `DashboardData`.
- `lib/reporting.ts`: add the column to **all four** select lists (team page,
  league page, and the two combined queries at lines ~246, ~273, ~403, ~465),
  point them at the v4 reader views, and add the row schema to the zod
  validator.
- `components/dashboard/team-dashboard.tsx` (~line 382): read
  `dashboard.contact_distribution ?? supplement?.contact_distribution`. Keep the
  supplement fallback so local preview review still works. Everything else in
  the component stays as committed.

### 7. Record it

`docs/PIPELINE_RULE_CHANGELOG.md`: date, rule version, what changed, why,
carry-forward status, adjudication reference. Record it when accepted, not at
season end. Carry-forward is **yes**: this is a rule-layer view, so it re-runs
unchanged on Year 2.

---

## Acceptance checks

1. New views reproduce the verified numbers table above exactly.
2. Preflight shows every inherited section byte-identical to the approved V5
   payload; the only diff is the added key.
3. Parity export diff classifies exactly one new path, `contact_distribution`,
   as whitelisted, and nothing else.
4. Ring renders on the live team pages, overall and under the match and training
   filters, with Unknown visible.
5. League page ring reconciles to pooled raw counts, not averaged team rates.
6. `python3 -m unittest discover -s tests -p 'test_*.py'` stays green (231 tests
   at time of writing), `npm run pipeline:check` passes, `npm run build` passes.

## Deliberately excluded

**Per-setting severity.** It looks like the same job and is not. Severity already
ships as a published section, and `team-dashboard.tsx` falls back to summing
every `severity_distribution` row to derive recorded cases, so adding match and
training rows would double or triple count that figure. It needs the component
filtering to `setting === 'all'` in the same change, plus a decision about
whether the existing rows keep their implicit overall meaning. Separate plan.

**The Vercel deployment blocker.** Independent problem, tracked in the changelog.

**Removing `RingBreakdown`.** Now unused after the ring moved to `SeverityArc`.
Left in `charts.tsx` on purpose as a generic primitive. Delete it only if you
want the cleanup, and never as a side effect of this work.

## Decided: Unknown stays

**Abdel, 26 July 2026: the Unknown slice stays.** The ring's total is therefore
all cases, not classified cases only, and the views must emit `unknown` rows.

Every other breakdown on the site hides front-facing unknowns via
`withoutFrontFacingUnknown`. This divergence is intentional: for a mechanism
field, the unknown share (9% of recorded cases) is a real coverage statement
rather than noise, and hiding it would silently inflate the contact and
non-contact percentages. Do not "harmonise" this with the other breakdowns, and
do not route the contact rows through `withoutFrontFacingUnknown`.
