# Additive dashboard enhancement plan — 2026-07-25 (rev 2, post-review)

Status: reviewed by an independent agent, corrected, ready to execute Phase 1.

Guiding rule from Abdel (2026-07-25): **additive only.** Nothing existing is
removed. New visualisations are added as previews *below* the current ones so
both can be compared. Removals are decided later.

Rev 2 corrects four material errors found in review; they are listed at the end.

## Data reality — three payload paths, not one

The app reads three different sources and they carry different fields. Rev 1
audited only the released bundle and got this wrong.

- **Released bundle** — `reporting.latest_team_dashboard_v2/v3`, what production
  serves. Types: `TeamDashboardData`.
- **Dev-only supplement** — `DashboardSupplement` via `getDashboardSupplement`,
  the Git-ignored private-review artifact. Carries `monthly_by_setting`,
  `contact_distribution`, per-setting `severity_distribution`,
  `rate_setting_metrics`. The contact ring and per-setting severity already
  visible on the dashboard exist **only** here.
- **Exposure preview** — `ExposureReviewPreview`, carries `match_hours` monthly.

| Feature | Data | Path |
|---|---|---|
| Team colour theming | `config/teams.ts` | presentation |
| Comparison scatter | `TeamComparisonRow.match/.training.incidence_per_1000h` | released |
| Dot size by precision | `TeamComparisonRow.exposure_hours` | released |
| "You are here" | **not present** — needs a server-side addition (§1.0) | — |
| Impact scatter relabel | `InjuryProfileRow` | released |
| Body-region match/training split | `body_location` rows per setting | released |
| Stacked monthly exposure | `match_exposure_hours` — **chart already exists, grouped** | preview |
| Match-date markers | fixtures — **not in any reporting view** | PHASE 2 |
| Severity × body region | cross-tab does not exist | PHASE 2 |
| Severity × injury type | cross-tab does not exist | PHASE 2 |

---

# PHASE 1 — additive presentation work

## 1.0 Prerequisite: identify the viewing team (server-side)

`TeamComparisonRow` exposes only `comparison_id` and `team_alias`.
`normalizeTeamComparisons` in `lib/reporting.ts` deliberately strips
`internal_team_key`, so the browser cannot tell which row is the team whose page
it is. Two Phase 1 features depend on this.

Add `viewer_comparison_id: string | null` to the team page payload, computed in
`getTeamPageData` while `team_key` is still in scope, and thread it down as a
prop. **Do not** match on `exposure_hours` float equality — the exposure preview
mutates both sides of that comparison.

Privacy note, on the record: this exposes no new linkage. A viewer on the Munster
page already knows the page is Munster; marking which row is theirs reveals only
their own alias to themselves. No other club's alias mapping is disclosed. This
is consistent with the 19 July 2026 amendment.

## 1.1 Team colour identity

**Verified contrast against `--background: 205 47% 14%`:** 11 of 16 accents fail
a 3.0 ratio — connacht 2.86, leinster 2.01, munster 2.95, ulster 2.95, dragons
2.95, ospreys 1.36, scarlets 2.95, lions 2.95, sharks 1.36, stormers 2.01,
edinburgh 1.11. Only cardiff, bulls, benetton, zebre, glasgow pass.

A naive fallback to `accentSecondary` sends eight clubs to `#FFFFFF`, which is
already `--foreground` — no identity at all. So the resolver order matters:

New `lib/team-color.ts`, `resolveTeamColor({ accent, accentSecondary, backdrop, target })`:

1. If `accent` meets `target` against `backdrop`, use it.
2. Else **lift the accent's lightness in OKLCH, preserving hue and chroma**,
   until it meets `target`. Munster stays red, Leinster stays blue.
3. Else use `accentSecondary` **only if chromatic** (reject near-zero chroma).
4. Achromatic last resort.

Requirements: `backdrop` and `target` are parameters, not constants — panels are
`bg-card`, bar tracks are `bg-muted`, and a colour passing against the page can
fail against muted (benetton: 3.98 vs background, 2.63 vs muted). Text and marks
differ: the `<h1>` is large bold text (3.0 is the AA floor for it), chart marks
are non-text UI under WCAG 1.4.11 (3:1). Return
`{ primary, text, mark }` and document which is safe where.

Unit-test all 16 clubs: every result clears its target against background, card,
and muted, and steps 1-2 preserve hue.

**Apply the colour only via explicit props or inline style at named call sites.**
Never rebind the `--primary` CSS variable — that would silently recolour every
item in the do-not-touch list below.

**Apply to:** the dashboard `<h1>`; the team's own bar in comparison rankings and
the exposure 16-club list; the team's dot in the new scatter; the *single-series*
exposure bar at `charts.tsx:725` only.

**Never apply to** — these encode meaning, not identity:

- Severity ramp (`SEVERITY_BAND_COLORS`) — ordered scale.
- Contact ring (`CONTACT_RING_COLORS`) — categorical.
- Body-map heat ramp (`locationHeatColor`) — sequential.
- `SETTING_COLORS` match/training — consistent across tabs.
- `PROFILE_COLORS` / `profileColor()` — `charts.tsx:44-59`.
- `INJURY_FAMILY_COLORS` — `injury-type-dossier.tsx:10-21`.
- `REFERENCE_INJURY_COLORS` / `commonInjuryColorMap` — `team-dashboard.tsx:64-115`.
- `deltaTone` emerald/amber/red — `team-dashboard.tsx:928-932`. Diverging and semantic.
- The two-series exposure bars at `charts.tsx:721-722`.

**League page:** `app/urc/page.tsx` renders the same component and `config/teams.ts`
has no `urc` entry. The resolver must have a defined league fallback (keep
`--primary`), not be called with `undefined`.

## 1.2 Team Comparison — append scatter

Keep the ranked bars and heatmap table untouched. **Append** a panel: match
incidence (x) against training incidence (y), one dot per club, all values read
directly from released `TeamComparisonRow`.

- **Dot area scales with `exposure_hours`** (a released field). Clubs range 2,467
  to 6,988 player-hours, so a rate from half the exposure is materially less
  precise. Encoding precision in the mark is better than a caveat sentence that
  fights an equal-sized-dot picture. No statistic is computed.
- Viewing club: resolved team colour, emphasised, labelled with its real name.
  All others keep `Team A`–`Team Z`.
- League mean crosshairs from released `leagueMetrics` — a released value, drawn
  as reference lines. (It is already printed elsewhere on this tab, so drawing it
  raises no new question.)
- Short note: dot size reflects exposure; larger dots are more precisely
  estimated. Do not print a computed spread ratio.

## 1.3 Injury Impact — append relabelled scatter, no quadrants

Keep the existing bubble chart. **Append** a panel with the same data, fixing the
label collision: label only the top 5 by burden, everything else an unlabelled
dot with hover. Points with fewer than 3 cases are visually distinguished, not
only flagged on hover.

**The four-quadrant risk matrix is dropped from Phase 1.** Two reasons, and I
think both are right:

- *Governance.* A browser-computed median that sorts every profile into a named
  category ("high frequency, high severity") is a classification rule the browser
  owns, and a medical lead will quote that label in a meeting. Suppressing the
  numeral makes it worse, not compliant: it creates an untraceable threshold,
  against "each published metric must be traceable to a pipeline run, analysis
  view, cohort definition, numerator, and denominator." The real line is not
  printed-vs-drawn, it is whether the browser owns a rule that changes what a
  reader concludes about a record. Quadrant membership does.
- *Statistics.* `ImpactTab` already slices to the **top 12 by burden**, so a
  median over that set is a median of an already-truncated tail — labelling a
  corner "low frequency, low severity" when every point is among the club's
  highest-burden problems is actively misleading. With n≈10 and many rows at 1-2
  cases, one case moving flips points across the split. Neither IOC 2020 /
  STROBE-SIIS nor Fuller 2007 endorses quadrant risk matrices; they come from
  occupational risk management. And incidence × severity = burden, already the
  bubble area, so the matrix shows one number three times.

If quadrants are still wanted, the threshold belongs in a versioned view —
Phase 2.

> **Amended 2026-07-26 (Abdel Babiker).** Quadrants were subsequently accepted as
> a display-only annotation, and the Injury Impact tab was folded into Common
> Injuries. The statistical objection above is answered by taking the median over
> **every plottable profile in the selected setting and grouping**, not over the
> top-12-by-burden slice that is drawn. The governance point is not overturned:
> the labels are comparative ("Longer absences · More frequent"), quadrant
> membership is stored nowhere and carries no released status, and promoting any
> quoted threshold to a versioned view remains Phase 2. Recorded in
> `docs/PIPELINE_RULE_CHANGELOG.md`, 2026-07-26.

## 1.4 Injury Location — append depth

Keep everything. **Append** a match vs training split per body region as a
diverging bar (match left, training right), reading released per-setting
`body_location` rows. **Default the metric to counts**: match and training
incidence sit on different denominators and match rates typically dwarf training
rates, which makes a shared-axis rate comparison misleading at a glance.

Defect fix, permitted: the existing heat ramp's low end renders near-invisible
brown on the dark background (Ankle, Chest, Elbow unreadable). Raise the ramp's
lightness floor.

Severity mix per region is **Phase 2**.

## 1.5 Injury Types — precision fix only

The rev-1 proposal to append a per-type severity distribution is **withdrawn**:
that cross-tab does not exist, and building it would mean inventing numbers. It
moves to Phase 2.

What remains: bars are drawn from unrounded values while labels round to 1dp, so
Ligament/sprain and Nervous system both read `3.1` with visibly different bars.
Use a fixed **2dp for incidence and burden in ranked lists**, applied
consistently — not a conditional "2dp only on collision", which yields a ragged
data-dependent column. Same mismatch exists in `MetricBars`, `LocationDetail`,
and `ComparisonBarRow`; fix them together.

## 1.6 Exposure — make the existing chart stacked

A grouped match/training monthly bar chart **already exists** at
`charts.tsx:718-723`, gated on the exposure preview. Change it to stacked via
`stackId`, keeping the same gate. Fixture markers are **Phase 2**.

Add the team's own bar highlight + "You" chip to the 16-club list, using §1.0.

Note, not to build on: `training_exposure_hours` is currently derived by
subtraction in presentation code (`team-dashboard.tsx:1199`), which is exactly
the pattern AGENTS.md forbids. It is pre-existing and preview-only, so not a
Phase 1 blocker, but prefer `MonthlySettingRow` where `setting === 'training'`,
which carries the value directly.

## 1.7 Every new panel declares its setting-filter behaviour

`OverviewTab` handles this with `perSettingMonthly` / `perSettingSeverity` and
`ScopeChip`. Each new panel must record the same decision, or it will show
overall data under a match/training filter with no indication.

---

# PHASE 2 — blocked, requires separate T4 approval

Not in scope. Recorded so the requirement is not lost. Each needs a new versioned
migration, a recorded adjudication in `docs/PIPELINE_RULE_CHANGELOG.md`, a rerun,
and a re-release for every affected team/season, retiring bundle
`urc-2024-25-v4-6f04bd64d2a6-a2`. Every database action needs Abdel's explicit
approval of the exact hosted target.

1. **Fixture dates in the reporting payload** — for match-date markers.
   `curated.fixtures` exists; no reporting view reads it.
2. **Severity × body-location cross-tab** — severity mix per region.
3. **Severity × injury-type cross-tab** — severity mix per type.
4. **Poisson confidence intervals on incidence** — the correct fix for the
   cross-club precision problem, and standard practice per Fuller et al. 2007.
   For `c` cases over `E` player-hours: rate `= 1000c/E`, with exact Poisson
   limits on `c` scaled by `1000/E`.
5. **Risk-matrix thresholds**, if quadrants are wanted, computed in a view over
   an untruncated cohort.
6. **Per-setting monthly exposure in the released bundle** — currently
   preview-only, so the stacked chart cannot ship to production teams.

---

# Execution constraints

- **No database access of any kind.** No migrations, no `pipeline` writes, no
  `release`, no `sql_exec`, no `psql`. Phase 1 touches only `components/`,
  `lib/`, `config/`.
- **Additive only.** Nothing removed. The only permitted changes to existing
  elements are the three named defect fixes: §1.4 ramp floor, §1.5 precision,
  §1.6 grouped→stacked.
- **No new published figures.** Every rendered number comes from the payload.
- Do not rebind `--primary`.
- Do not commit, push, or restart a running dev server.
- Verify: `npm run build`, `npm run typecheck`, `npm run test:dashboard-access`,
  `npm run test:dashboard-v3`, plus browser checks at 1440px and 390px.

---

# Corrections made in rev 2 after independent review

1. **Audit error.** Rev 1 said per-setting monthly exposure did not exist. It does
   (`MonthlySettingRow.exposure_hours`, and `ExposureReviewPreview.match_hours`),
   and a grouped chart already ships. Scope changed from "build" to "stack".
2. **Audit error.** Rev 1 claimed a per-type severity distribution was available.
   It is not; that cross-tab does not exist. Withdrawn to Phase 2.
3. **Missing prerequisite.** Rev 1 assumed the viewing team could be identified
   client-side. `TeamComparisonRow` carries no team identity. Added §1.0.
4. **Governance and statistics.** Rev 1's quadrant matrix rationalised the
   metrics rule by hiding the numeral, and the median sat on an
   already-truncated cohort. Dropped from Phase 1.
5. **Colour resolver.** Rev 1's fallback order sent 8 of 16 clubs to white.
   Reordered to a hue-preserving lightness lift first, with backdrop and target
   parameterised and the do-not-touch list extended by four palettes.
