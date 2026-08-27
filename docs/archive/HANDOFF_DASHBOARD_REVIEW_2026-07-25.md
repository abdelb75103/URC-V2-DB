# Handoff: dashboard redesign review — 2026-07-25

Status: archived handoff. The branch, commit, working-tree, server and decision
state below are historical and must not be used as current instructions.

**Your job:** walk Abdel through the changes below **one at a time**. Present a
change, show him old versus new, get his decision, apply it, then move to the
next. Do not batch them. Do not present the whole list at once and ask him to
pick — he explicitly asked for one decision at a time.

---

## State of the repo

- Branch `main`. Last commit `22b0d11` (the Overview redesign) is **already
  committed and pushed**.
- Everything else listed below is **uncommitted working-tree changes**. Nothing
  from "Phase 1" has been committed or pushed.
- Dev server should be running on **http://localhost:3000**. If not, `npm run dev`.
  Do not kill or restart a server that is already running (project rule).

**Verification status right now — all green:**
`npm run build` ✓ · `npm run typecheck` 0 errors · `test:dashboard-access` 22/22 ·
`test:dashboard-v3` 9/9 node + 17/17 python · `tests/team-color.test.mjs` 8/8

Re-run these after any change he asks for.

## How to show him old versus new

- **Tabs other than Overview:** both versions are on screen simultaneously. Every
  Phase 1 addition was appended *below* the original, deliberately, so he can
  compare without reverting anything.
- **The Overview tab is the exception** — it replaced the old one. A worktree of
  the previous commit already exists:
  `/private/tmp/claude-501/-Users-abdelbabiker-Desktop-URC-V2-DB/068b9a36-fee5-4c77-a919-bdbdf1daf485/scratchpad/pre-redesign`
  (at `2b4e97d`, the commit before the redesign). Run a second dev server there on
  another port (`npm run dev -- -p 3001`) to show old and new side by side.
- **Before-images** of the pre-Phase-1 tabs are in `output/playwright/tab-*.png`
  (comparison, exposure, common, location, types, impact). That directory is
  gitignored.

---

## The decisions, in the order to raise them

### 1. Overview tab — the only replace-not-add change

Old: six stacked blocks, four "highlight" cards, a bare 4-stat strip, mirrored
match/training panels, two side-by-side monthly charts, two donuts.
New: four KPI tiles with sparklines, one composed season timeline (case bars +
incidence line), body map with ranked hotspots, severity segmented arc, contact
ring, full-width match/training bench. One global Overall/Match/Training filter.

Reverting means `git revert 22b0d11` (it is pushed, so a revert commit is the
clean route, not a history rewrite).

### 2. Team Comparison — scatter panel appended

Match incidence (x) against training incidence (y), one dot per club, dot area
scaled by that club's exposure hours, league mean crosshairs. Original ranked
bars and heat map are untouched above it. Keep, remove, or keep and drop
something else?

### 3. Injury Impact — "Labelled view" appended

The original bubble chart is unchanged on top; the new panel below labels only
the top 5 by burden with real box-collision placement, marks profiles with fewer
than 3 cases as open dots, and has no quadrant lines. Both are currently shown.
Almost certainly he wants only one — ask which.

### 4. Injury Location — "Match against training by region" appended

Diverging bars, match left / training right, defaulting to counts because match
and training rates sit on different denominators. Original bars, body map and
detail rail unchanged above.

### 5. Team colour on the dashboard

The `<h1>` and the viewer's own bar/dot now carry the club's colour, resolved
through `lib/team-color.ts` (OKLCH lightness lift preserving hue; 11 of 16 club
accents fail 3:1 on the dark background). Semantic palettes — severity ramp,
contact ring, body-map heat, match/training series — are deliberately **not**
themed. Do not let that constraint get relaxed: those encode ordered,
categorical and sequential meaning, and a brand hue would corrupt them.

### 6. Ospreys and Sharks resolve to white

Both are `#000000` with a `#FFFFFF` secondary, so no chromatic identity exists in
their config. They currently get white. Legible everywhere, but identical to body
text, so they read as "untinted" rather than branded. Show him
`/team/ospreys`. Alternatives: a mid-grey (looked disabled), or a hand-picked
colour per club (breaks the deterministic rule).

### 7. Real team name instead of the alias

In Team Comparison the viewer's row now reads "Munster" rather than "Team J", and
in the heat map that row is pulled to the top and named. All other clubs keep
`Team A`–`Team Z`.

**Raise the privacy point explicitly.** This reveals one alias mapping to whoever
is on that page. The viewer already knows which team's page they are on, so it
discloses only their own alias to themselves and no other club's — but it makes
the linkage explicit rather than inferable, and `AGENTS.md` treats the alias map
as protected metadata. Worth him confirming knowingly.

### 8. One decimal place everywhere

All ranked lists show 1dp (his decision today). Ranked bars are now drawn from
the **rounded** value, so two rows both showing `3.1` render identical bars
instead of visibly different ones. Trade-off: a row ranked above another can now
look level with it.

### 9. Body-map heat ramp floor raised

Defect fix. Low-end regions (Ankle, Chest, Elbow) were near-invisible brown on
the dark background and now render. Applies to the existing panel, not a new one.

### 10. Exposure — stacked bars and viewer highlight

The existing grouped match/training monthly bars became stacked. **Only visible
on `/urc`** — team pages do not load the exposure preview that supplies the
per-setting split, so on team pages this change is inert until Phase 2. The
16-club list also gained the viewer's name and colour.

### 11. Common Injuries — untouched, optional addition

**Nothing was changed on this tab.** Verified: zero diff hunks inside
`CommonInjuriesTab` (team-dashboard.tsx lines 723-837) in either the pushed
commit or the working tree. Its colour map was on the do-not-touch list.

Raise it last, as an optional extra rather than a decision about existing work.
The standing critique: twenty saturated colour-filled cards in four columns, where
a solid red "Concussion" card reads as an alarm rather than a statistic, and the
real insight (concussion tops count, knee sprain tops burden) has to be
reconstructed by eye across four columns.

Proposed addition if he wants it: a **slope chart** showing how the top injuries
re-rank across count, incidence, burden and severity — the crossing lines are the
finding, and it is the one visual grammar not yet used anywhere on the dashboard.
Purely additive, needs no new data (`InjuryProfileRow` already carries all four
metrics per injury), no pipeline or database work.

---

## Still outstanding after the above

**Cleanup he has not approved** (do not delete without an explicit yes):
- `output/_table.mjs` — throwaway script left in the repo.
- 5 duplicate screenshots in `output/playwright/` from a failed capture loop.
- Two scratch worktrees: `.../scratchpad/head-baseline` and `.../scratchpad/pre-redesign`.
  **Keep `pre-redesign` until decision 1 is settled** — it is how you show him the
  old Overview.

**Commit and push:** he chose "neither yet". Ask again once decisions are made.

**Phase 2 — blocked, needs separate approval.** Recorded in
`docs/archive/OVERVIEW_TABS_ADDITIVE_PLAN_2026-07-25.md`. Each needs a versioned
migration, a recorded adjudication, a rerun and a re-release for all 16 teams,
retiring bundle `urc-2024-25-v4-6f04bd64d2a6-a2`. Every DB action needs his
explicit approval of the exact hosted target.
1. Fixture dates in the reporting payload (match-date markers).
2. Severity × body-location cross-tab.
3. Severity × injury-type cross-tab.
4. Poisson confidence intervals on incidence (Fuller et al. 2007).
5. Risk-matrix thresholds in a view, if quadrants are ever wanted.
6. Per-setting monthly exposure in the released bundle (unblocks decision 10).

---

## Rules that bind you

Read `AGENTS.md` before touching anything. The ones most likely to trip you here:

- **No metric may be computed in presentation code.** Dot positions, bar widths,
  axis domains and label placement are visual encoding and are fine. A printed
  statistic the browser derived is not. This is why the Injury Impact quadrant
  matrix was dropped: a browser-computed median that sorts profiles into named
  risk categories is a classification rule the browser would own, untraceable to
  any pipeline run.
- **No database access** for any of this work.
- The web app is read-only; releases go through the Python pipeline.
- Do not restart a running dev server.
- An approved release is not a deployment. Access-control restoration and
  production cutover remain separate, explicitly manual steps.
