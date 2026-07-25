# Implementation plan: batched dashboard review decisions (2026-07-25)

Source of decisions: `HANDOFF_DASHBOARD_DECISIONS_2026-07-25.md` (scratchpad), plus
Abdel's added item 13 (Common Injuries slope chart). Nothing here has been executed.

**Class: T2** (presentation layer, one area, multi-file). Medium effort. No delegation
required by the router; Abdel has separately asked for a review subagent, an execution
subagent and a confirmation review, which sits on top of the router's budget.

**Scope boundary.** Every change below is presentation-only: it reads released payload
values and changes how they are drawn. No database access, no pipeline command, no
migration, no change to `content/reporting/*.json`, no new metric computed in the
browser. Sorting, ranking, axis domains, bar widths and label placement are visual
encoding of released values and stay inside that boundary (the ranked lanes already
sort released values today).

---

## 0. Findings that change the handoff

Two items were checked against the code before planning:

**0.1 Item 3a is already done.** `ImpactBubbleChart` at `HEAD` already uses
`scale="log"` on mean severity, with `logSeverityDomain` / `logSeverityTicks`
(`components/dashboard/charts.tsx:1399-1412`). There is no linear severity axis to
replace. 3a becomes a no-op; the plan carries 3b, 3c, 3d, 3e only. The reviewer should
confirm this rather than take it on trust.

**0.2 Item 4a (C1 axis treatment) cannot apply to the Injury Location diverging
panel.** `LocationSettingSplit` (`team-dashboard.tsx:1470-1553`) is a two-sided HTML
bar list, not a cartesian chart. It has no axis lines and no axis titles. C1 is a
no-op there; 4b (subline) is the only live part of item 4. Flag, do not invent an axis.

**0.3 `TOOLTIP_STYLE` (`charts.tsx:30-36`) is dead code** — defined, never referenced.
Delete it as part of item 12.

---

## 1. Cross-cutting conventions

### C1. Axis treatment (all cartesian charts in `charts.tsx`)

Affected charts: `MonthlyCasesChart`, `MatchIncidenceChart`, `SeasonTimelineChart`,
`ExposureTrendChart`, `ComparisonScatterChart`, `ImpactBubbleChart`
(`LabelledImpactScatter` is deleted by item 3, so it is out of scope).

Introduce shared constants next to `AXIS` / `GRID`:

```
const AXIS_LINE = { stroke: 'hsl(0 0% 78%)', strokeWidth: 1.5 };
```

Then, on the primary x-axis and y-axis of each chart above:
- `axisLine={AXIS_LINE}` (today most pass `axisLine={false}` or `{ stroke: GRID }`).
- Leave `tickLine={false}` as is.
- Axis titles centred on their axis: x titles use `position="insideBottom"` with a
  centred offset; y titles use `position="insideLeft"` with `textAnchor: 'middle'` and
  a dy that centres the rotated text on the axis length. Recharts does not centre a
  rotated label by default, so each y-title needs an explicit
  `style={{ textAnchor: 'middle' }}` and the chart's `left` margin widened enough that
  the title is not clipped (this is also the fix for 3d).
- The `SeasonTimelineChart` has two y-axes (`cases`, `rate`); both get the treatment.
- The grid stroke (`GRID`) is unchanged, so the axis reads as distinct from the grid.

Risk to watch: bolding the axis on the scatter charts, where `axisLine={{ stroke: GRID }}`
currently blends into the grid, changes the visual weight of the plot box. Check at
1440px and 390px.

### C2. No explanatory sublines

Delete these caption blocks and fold their content into axis or series labels:
- `charts.tsx:880-882` — scatter caption (item 2a). Dot-area encoding becomes
  unexplained; that cost is accepted in the handoff. Fold the axis meaning into the two
  axis titles, which already name their units. Keep the `<section aria-label>` sentence:
  it is the screen-reader description, not a visible subline.
- `charts.tsx:1437-1440` — impact captions (item 3e). The "logarithmic scale" wording
  is already in the y-axis title. The second sentence, about profiles dropped for
  non-positive mean severity, is **not** decoration: it is the only place the chart
  admits it is hiding rows. Recommendation: keep that one line, delete the first.
  Flagged for Abdel; C2's target was generic instructional text, not a disclosure of
  omitted data.
- `team-dashboard.tsx:1544-1548` — `Values are ${meta.longUnit}` (item 4b). Fold into
  the two column headers, which already carry the Match / Training swatches: render
  them as `Match, {meta.longUnit}` and `Training, {meta.longUnit}`. The second clause
  for rate metrics ("match and training rates rest on different exposure denominators")
  is a methodological caveat, not an instruction. Recommendation: keep it for the rate
  metrics only. Flagged — the handoff already notes "keep it all" may have covered it.

### C3. Tooltips — see item 12.

---

## 2. Item-by-item plan

Order is chosen so shared code lands before its consumers.

### Step 1 — item 12: one shared tooltip (`charts.tsx`)

The foundation for everything else, because five tooltips already route through
`TooltipCard` (`charts.tsx:107-130`): `CasesTooltip`, `IncidenceTooltip`,
`MonthlyExposureTooltip`, `TimelineTooltip`, `ComparisonScatterTooltip`. Restyling one
component covers them all.

Restyle `TooltipCard` to the reference:
- Background `hsl(205 47% 9% / 0.92)` with `backdrop-blur-sm`, `rounded-lg`,
  `shadow-xl`, **no border**.
- Header: bold, white, category name only (drop the ` - overall` setting suffix from
  the title and move the setting into the footer, so the header reads "September" like
  the reference).
- One compact row per series. Extend the `rows` prop to
  `{ label: string; value: string; color?: string }` and render both label and value in
  that colour, value bold and `tabular-nums`. Every call site passes the series colour
  it already knows (`SETTING_COLORS.match`, `#ffc45c`, `#f59e0b`, `profileColor(code)`,
  the viewer colour).
- Units stay in the value string (they carry meaning per row and the reference's
  single-unit case does not apply here); no per-row unit repetition beyond that.
- `cohort` footer: the reference has no footer. But `n = …` is a released value and the
  only sample-size signal on hover. Recommendation: keep it as one small muted line,
  drop the sentence framing (`n = 12 time-loss cases` not `n = 12 time-loss cases.`
  plus caveats). Flagged for Abdel.
- Delete `TOOLTIP_STYLE` (0.3).

`ImpactTooltip` (`charts.tsx:1096-1130`) is a hand-positioned pinnable panel, not a
recharts tooltip. Restyle it to match (same surface, same colour rules, keep the
pin/dismiss affordance and its `role="tooltip"`/`aria-live`), do not force it through
`TooltipCard` — it has a different information shape and pinning behaviour.

The `aria-live` "tooltip" divs in `MetricBars`, `BodyMap` and `injury-type-map.tsx` are
screen-reader text, not visual tooltips. Out of scope.

Cursor band: **recommend not importing the reference's heavy opaque band.** Keep the
existing subtle cursors. Confirm with Abdel (open question Q2).

### Step 2 — item 9: body map (`components/dashboard/body-map.tsx`)

- **9b.** `locationHeatColor(value, max)`: return an untinted fill when `value <= 0`
  (e.g. `hsl(205 30% 22% / 0.35)`), before the floor lift applies. The floor lift then
  covers non-zero values only. Note this function is also used by `MetricBars` and the
  Overview "Top locations" list, so zero-valued bars there also go untinted — that is
  consistent and desirable.
- **9c.** Every region hoverable. `BodyFigure` (`body-map.tsx:143-165`) already
  enumerates the controlled `REGIONS` vocabulary (18 IOC buckets, `body-map.tsx:8-27`)
  and only the payload lookup is missing. Change `enabled={Boolean(row)}` to `true`,
  and where `row` is absent use `value = 0` with `label = code.replaceAll('_',' ')`
  (already the fallback) and the `aria-label` reading `0`. The `sr-only` live region
  must state `0` rather than "not available".
- The plotted `max` must stay driven by the rows that exist, so adding zero regions
  does not change any other region's colour.
- Confirm `REGIONS` still matches `docs/IOC_TAXONOMY_BUCKETS.csv` before relying on it
  as the vocabulary.
- Carry the caveat in the hover text wording: `0` means no cases recorded in this
  bucket. Keep it to the accessible description, not a visible subline (C2).

### Step 3 — item 1: Overview tab (`team-dashboard.tsx`)

- **1a.** Remove `<BurdenSplit …>` from the Burden `StatTile`
  (`team-dashboard.tsx:409`) and delete the now-unused `BurdenSplit` component
  (`:564-595`). Check whether `match` / `training` locals are still used elsewhere in
  `OverviewTab` before removing them (they are — `SettingBench` at `:532`).
- **1c.** Season timeline starts at September. Filter `monthlyRows` before it reaches
  `SeasonTimelineChart` (`:432`) by dropping leading months earlier than September of
  the season's first year, using the existing `sortByMonth` ordering — that is, slice
  from the first September rather than hard-coding month names against a parsed date.
  Add the note: one short line under the panel heading stating that cases recorded
  before September are counted in the headline totals but not plotted. This is a
  disclosure of omitted data, so it survives C2. **Do not** change the KPI sparklines
  (`:395-416`), which must keep reconciling against the tiles.
  **Q1 (open):** does this apply only here, or to every monthly chart site-wide,
  including the `/urc` exposure chart? Do not decide this in execution.
- **1d.** Units break and leak, `SettingBench` (`:644-656`). The value column is
  `7rem` and `{fmt(value)}<span className="ml-1 …">{meta.shortUnit}</span>` wraps
  inside `days/1,000 h`. Fix: wrap the unit in `whitespace-nowrap`, widen the column
  (`sm:grid-cols-[5.5rem_minmax(0,1fr)_9rem]`), and put the unit on its own line under
  the value rather than trailing it, so a long unit cannot push the value out of the
  card. Verify all four metric modes at 1440px and 390px — Burden has the longest unit,
  Incidence (`/1,000 h`) is the next risk.
- **1b (illnesses)** is out of this batch. Blocked: frozen case definition, needs `_v2`
  views, adjudication, rerun and re-release. Nothing to do here.

### Step 4 — item 2: Team Comparison scatter (`charts.tsx:788-885`)

- **2a.** Delete the caption (C2).
- **2b.** Give the two league-mean `ReferenceLine`s different colours. Recommend
  `SETTING_COLORS.match` for the vertical (match mean) and `SETTING_COLORS.training`
  for the horizontal (training mean), so each mean line matches the axis it belongs to
  and the site's existing match/training encoding. Keep the dashed stroke.
- **2c.** Reposition the labels. `insideTopRight` on the vertical line collides with
  the plot; `insideBottomLeft` on the horizontal jams against the y-axis. Recommend
  moving both outside the plot area: the match-mean label above the plot at the line's
  x (`position="top"`), the training-mean label at the right edge
  (`position="right"`), each in its own line colour, `fontSize` 10. Increase the chart
  `top` and `right` margins to make room.
- **2d/2e.** C1.

### Step 5 — item 3: Injury Impact

- Delete `LabelledImpactScatter` (`charts.tsx:947-1090`) and its supporting
  `LabelledImpactTooltip`, `LabelledImpactDot`, `LABEL_BOX`, `severityFloor`,
  `SMALL_SAMPLE_CASES` and the `LabelledImpactRow` type, once nothing else references
  them. Delete the "Labelled view" `Panel` and the import in `team-dashboard.tsx`
  (`:30`, `:1733-1736`).
- **3a.** No-op, see 0.1.
- **3b.** Port the box-collision label placement into `ImpactBubbleChart`. The original
  labels via `<LabelList dataKey="displayLabel" position="top">` on the top four by
  burden (`charts.tsx:1355-1363`, `:1419`). Port the placement loop from the deleted
  panel (`:974-1011`) and its `renderLabel` content function (`:1020-1028`), adjusting
  the pixel box: `ImpactBubbleChart` is `h-[430px] min-w-[680px]` with margins
  `{ top: 30, right: 30, bottom: 34, left: 18 }`, so `LABEL_BOX` must be recomputed for
  that geometry and kept next to the container class with a comment tying the two
  together (they will silently drift otherwise). Keep the top-4 label set.
- **3c.** C1. **3d.** Clipped y-axis title — fixed by C1's widened left margin plus a
  larger `YAxis width`; verify the full string "Mean severity, days (logarithmic
  scale)" renders at both widths, and shorten to "Mean severity, days (log scale)" if
  it still clips at 390px. **3e.** C2, with the exception noted in §1.
- **Do not** add quadrant or median reference lines.

### Step 6 — item 11: HSR percentage label (`charts.tsx:732-739`)

Today the HSR share renders `position="insideBottom"` in white inside the blue
remainder segment, immediately above the orange HSR sliver, so it reads as the blue
series.

Recommended fix: **reorder the stack so HSR is the top segment** (`distance_remainder_km`
first, `hsr_distance_km` second with the rounded top radius), and move the label to
`position="top"` in `#f59e0b`. The percentage then sits above the whole bar on the dark
card background: unambiguous, legible when the sliver is thin, and legible on short bars
(Jun, Jul). Cost: the visual reading order of the stack changes, and the total-distance
bar no longer "starts" with HSR.

Fallback if Abdel wants the stack order preserved: keep HSR at the bottom and draw the
label at the segment's top edge with a negative dy and an orange fill plus a dark
`paintOrder="stroke"` halo for contrast against the blue. This is more fragile on thin
slivers, which is why it is the fallback.

Either way: raise the chart's `top` margin, and keep `formatHsrPercentage`'s existing
"blank when zero" behaviour.

Note the accepted limitation from item 10: this panel only carries the per-setting /
HSR split on `/urc`. Verify there.

### Step 7 — item 13 (new): Common Injuries rank-slope panel

**Additive only.** The four-column grid (`CommonInjuryRankings`, `team-dashboard.tsx:838-859`)
and every card in it is untouched. The slope panel is appended **below** it inside
`CommonInjuriesTab` so both can be compared before anything is deleted.

*What it shows.* One line per injury, four x positions (Count, Incidence, Burden,
Severity — `METRICS` order), y = that injury's rank in that metric, rank 1 at the top.
Crossing lines are the payload: concussion topping Count while knee sprain tops Burden
becomes one read instead of four column comparisons.

*Data.* `InjuryProfileRow` already carries all four metrics per injury. No new data, no
computed metric — rank is an ordering of released values, the same ordering the four
lanes already perform.

*Which injuries.* The union of each metric's top five, i.e. exactly the set of cards
visible on screen. In practice 8–12 lines for a typical club. This set is already
computed inside `commonInjuryColorMap` (`:765-778`) as `visibleCodes`; extract that
selection into a shared helper so the panel and the lanes cannot drift.

*Ranking rule.* Competition ranking on the **rounded displayed value**:
`rank(x) = 1 + count of rows whose rankedBarValue(value, metric) is strictly greater`.
Consequences, both intended:
- The card ranked first in a column is always rank 1 in the slope chart.
- Two injuries whose labels both read `3.1` share a y position, so the chart never
  implies a gap the label denies (item 8's accepted cost, handled).
Ranking runs over the full ranked row set for the metric, not just the plotted union,
so a plotted line can sit below rank 5 — that is correct and is the point.

*Rendering.* Hand-rolled inline SVG in `charts.tsx`, exported as `RankSlopeChart`,
following the `Sparkline` precedent. Recharts has no slope primitive and forcing a
`LineChart` with a categorical x and inverted y buys nothing. Props:
`{ rows, metrics, injuryColors, settingLabel }`.
- Colour: `injuryColors` is passed in from `commonInjuryColorMap`. **`REFERENCE_INJURY_COLORS`
  and the colour map are not modified, and no team colour is applied** — they are a
  deliberate maximum-distance categorical assignment and are on the do-not-touch list.
- Left gutter carries the injury label at its Count rank; right gutter repeats it at
  its Severity rank. Dots at each of the four positions. Values at 1dp via `fmtRanked`
  shown on hover.
- Hover/focus a line: it goes full opacity, the rest drop to ~0.25, and the shared
  tooltip (step 1) shows the four values in that injury's colour.
- Axis titles per C1/C2: x is the four metric names, y is `Rank (1 = highest)`. No
  subline.
- Not enough data (fewer than two injuries, or a metric with no ranked rows): render
  the existing `EmptyState`.
- Accessibility: `role="img"` with a summarising `aria-label`, plus an `sr-only`
  ordered list giving each injury's four ranks. Every interactive line is focusable
  with a visible focus ring.
- Responsive: horizontal scroll container with a `min-w` like the other charts; at
  390px the label gutters shrink and labels truncate rather than the plot collapsing.

*Setting filter.* `CommonInjuriesTab` owns its own `SettingControl`
(`team-dashboard.tsx:730, 747`) and passes rows already filtered to the chosen setting.
The panel takes the same filtered rows, so the filter is honoured directly and **no
`ScopeChip` is needed**. State that in the panel's props doc.

*Heading.* "How rankings shift across metrics" — British English, no em dash, no
explanatory subline.

### Step 8 — item 7 follow-up (docs only)

Add a line to `docs/ACCESS_RESTORATION_GATE.md` recording that each team page now
discloses its own alias mapping directly (viewer's real name in Team Comparison and
pinned in the heat map), reinforcing that the passwordless URL stays private to Abdel
until the gate closes. No code change; item 7 itself is "keep as is".

### Items with no work

- **5, 6, 8, 10** — decided "keep as is". No code change. Do not touch `lib/team-color.ts`,
  the severity ramp, the contact ring, the body-map heat ramp hue or the match/training
  series colours.

---

## 3. Files touched

| File | Items |
|---|---|
| `components/dashboard/charts.tsx` | C1, C2, 2a–2e, 3b–3e (+deletion), 11, 12, 13 (`RankSlopeChart`) |
| `components/dashboard/team-dashboard.tsx` | 1a, 1c, 1d, 3 (call site), 4b, 13 (panel + shared top-5 helper) |
| `components/dashboard/body-map.tsx` | 9b, 9c |
| `docs/ACCESS_RESTORATION_GATE.md` | 7 follow-up |

No change to `lib/`, `app/`, `pipeline/`, `supabase/`, `content/reporting/`, or any
test fixture. If a change appears to require one, stop and re-scope.

---

## 4. Verification

Run after edits, all of them, and report actual output:

1. `npm run build`
2. `npm run typecheck`
3. `npm run test:dashboard-access` (expect 22/22)
4. `npm run test:dashboard-v3` (expect 9/9 node + 17/17 python)
5. `node --test tests/team-color.test.mjs` (expect 8/8)
6. Browser checks at **1440px** and **390px** against the already-running dev server on
   `http://localhost:3000` (**do not kill or restart it**; the port 3001 worktree is
   not needed for this batch):
   - Team page → Overview: no M/T mini-bars; timeline starts at September with its
     note; `Match vs training` in all four metric modes with no unit wrap and no
     overflow past the card.
   - Team page → Common Injuries: the four columns unchanged, the slope panel below
     them, setting filter switching both together.
   - Team page → Injury Location: body map, hover a zero region and confirm `0` and an
     untinted fill; diverging panel headers carry the units.
   - Team page → Injury Impact: single panel, labels not colliding or clipped, y-axis
     title complete.
   - Team page → Team Comparison: mean lines in two colours with readable labels.
   - `/urc` → Exposure → Distance: HSR percentage above the orange segment, in orange.
   - Tooltips on every chart on both pages.

Nothing is reported as done that has not been run. Anything that cannot be checked is
named, with the reason.

---

## 5. Open questions for Abdel

These do not block starting; steps 1–10 can proceed while they are open, but the named
step must not be finalised without an answer.

- **Q1 (blocks step 3, item 1c).** Does the September start apply only to the Overview
  season timeline, or to every monthly chart site-wide, including the `/urc` exposure
  distance chart that still renders Jul and Aug? The handoff explicitly says raise this.
- **Q2 (blocks step 1, item 12).** Import the reference's heavy opaque grey hover
  cursor band, or keep the current subtle cursors? Recommendation: keep the current
  cursors.
- **Q3 (step 4/5, C2).** Two sentences are disclosures of hidden data rather than
  instructional sublines: the impact chart's "N profiles with non-positive mean
  severity are not shown", and the diverging panel's "match and training rates rest on
  different exposure denominators". Recommendation: keep both, delete everything else.
- **Q4 (step 5, item 4b).** "Keep it all" may have been meant to include
  `Values are time-loss injuries.` One-line restore if so.

Also still outstanding from the handoff, unchanged and needing an explicit yes:
cleanup of `output/_table.mjs`, the five duplicate screenshots in `output/playwright/`,
and the two scratch worktrees; and whether to commit and push once this batch is
verified.

---

## 6. Risks

- **C1 is a sweep**, not a local edit. Every cartesian chart's margins interact with its
  axis titles; widening a margin shrinks a plot. Highest risk at 390px.
- **Deleting `LabelledImpactScatter` while porting its label logic** is easy to get
  half-right. Port first, verify the original renders correctly, then delete.
- **The slope panel's rank rule must stay tied to the lanes' selection.** If the top-5
  selection is duplicated instead of shared, the panel and the cards will disagree the
  first time either sort changes.
- **`locationHeatColor` has three call sites.** The zero-untinted change affects the
  Overview top-locations list and `MetricBars` as well as the body map. Intended, but
  check all three.
- **Nothing here approves a deployment.** No push, no cutover, no access-control change.
