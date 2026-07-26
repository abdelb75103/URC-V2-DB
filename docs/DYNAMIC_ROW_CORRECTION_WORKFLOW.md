# Dynamic Row Correction Workflow

Status: implemented locally and under production-readiness verification, recorded 26 July 2026. The additive migration and its registration must be confirmed as `applied-and-verified` in `docs/PIPELINE_RULE_CHANGELOG.md` before the first live correction.

## Purpose and boundary

Use this workflow to correct one field on an existing injury source row and let versioned SQL re-derive every dependent team and pooled league value. Never edit aggregate counts, incidence, burden, days lost, denominators, dashboard JSON, `ingestion.source_rows`, curated rows, frozen views, or historical migrations directly.

The existing V2 release storage stays frozen. A correction or rollback never inserts into `reporting.league_release_context_v2`, `reporting.league_release_payloads_v2`, or `reporting.team_dashboard_payloads_v2`. It writes only to the additive append-only `reporting.correction_release_context_v1` or `reporting.correction_rollback_context_v1`, plus `reporting.correction_league_payloads_v1` and `reporting.correction_team_payloads_v1`.

The correction-aware seam is also additive:

- `reporting.dashboard_bundle_context_v1` unifies frozen V2, correction, and rollback context.
- `reporting.dashboard_bundle_league_payloads_v1` and `reporting.dashboard_bundle_team_payloads_v1` unify frozen V2 payloads with correction payloads.
- `reporting.latest_approved_dashboard_bundle_v4` selects the current complete approved bundle from either storage family.
- The website reads the allowlisted `reporting.latest_team_dashboard_v5` and `reporting.latest_league_dashboard_v5` projections.

The unified bundle views and the internal `latest_approved_dashboard_bundle_v4` selector are private implementation surfaces. They are ungranted to `web_reader` and are reached under owner execution only through the security-definer V5 allowlist. `web_reader` receives `SELECT` only on `latest_team_dashboard_v5` and `latest_league_dashboard_v5`, so release, correction, build, and audit fields cannot leak through direct access to the unified sources.

Until a reviewed correction or rollback successor is approved, the V5 readers project the currently served V5 V2 bundle without changing its context, payloads, hashes, or metrics.

The exact installation target is the existing approved hosted Supabase/Postgres database reached through `SUPABASE_DB_URL_POOLER`, parsed from `/Users/abdelbabiker/Desktop/URC-V2-DB/.env.local` without sourcing or printing it. The additive migration is `supabase/migrations/20260726200000_dynamic_row_correction_pipeline.sql`; `tools/sql/register_dynamic_row_correction_pipeline_migration.sql` records that exact migration after application. Do not substitute a local Supabase target.

Baseline capture, baseline verification, proposal, and release preflight are read-only. Apply, promotion, and rollback are live writes. Proposal, preflight, baseline, and evidence files must stay Git-ignored and outside `content/reporting/`. They are private operator evidence, not website inputs.

Metric formulas remain SQL-only. Python resolves inputs, verifies evidence and hashes, and orchestrates the reviewed database functions. The additive SQL dependency graph calculates the preview and immutable draft.

`contact_distribution` is part of the V5 reader contract. Unaffected team payloads preserve it byte-for-byte. When an eligibility correction changes the effective injury cohort, the affected team's contact/non-contact/unknown counts and the pooled league distribution are recomputed from that same effective cohort in versioned SQL. Other typed corrections preserve the predecessor distribution when its inputs do not change.

## Short operator workflow

The human sequence is: request the exact row change, inspect the read-only proposal and impact preview, approve the apply, then separately approve the incremental release. The commands below preserve those two review gates.

### 1. Capture and verify the served predecessor

```bash
python3 -m pipeline capture-served-baseline --season <season> \
  --output <git-ignored-baseline.json>
python3 -m pipeline verify-served-baseline --season <season> \
  --baseline-file <git-ignored-baseline.json>
```

The baseline binds the correction-aware approved bundle identity, canonical bundle assembled through the unified payload views, served V5 team and league projections, all 16 team payload hashes, and the league payload hash. For the installation closeout, the selected release is still the existing V2-backed 2024-25 V5 bundle, so its identity, payloads, hashes, `contact_distribution`, and every served V5 metric must remain exact. No correction or draft may be active.

### 2. Create a read-only proposal and downstream preview

```bash
python3 -m pipeline correction-propose --season <season> \
  --source-row-id <stable-source-row-uuid> \
  --field-name <eligibility|days_injured|body_location_code|injury_type_code|diagnosis_code> \
  --expected-value '<json-value>' --new-value '<json-value>' \
  --reason '<evidence-backed-rationale>' --evidence-file <evidence-file> \
  --operator <operator> --rule-version <rule-version> \
  --output <git-ignored-proposal.json>
```

For a compensating decision, also pass `--supersedes-correction-id <correction-uuid>`.

The proposal has no reviewer or approval field. It resolves the exact existing row, checks its expected current effective value, and binds the source-row hash, effective-row fingerprint, typed old and new values, reason, evidence hash, operator, rule version, code and dependency provenance, current and proposed correction-set hashes, predecessor bundle, proposal hash, and SQL-generated downstream preview. A missing row, unsupported value, stale expected value, changed source fingerprint, or changed correction set fails closed.

Abdel reviews the concise before-and-after row, team and pooled league impact, changed dashboard paths, candidate hashes, and unchanged-team proof. A one-team metric change may alter only that team candidate and the pooled league candidate. The other 15 team payload hashes must match the predecessor byte-for-byte. A legitimate correction can also have no dashboard impact.

### 3. Apply Abdel's reviewed decision

```bash
python3 -m pipeline correction-apply \
  --proposal-file <git-ignored-proposal.json> \
  --reviewer 'Abdel Babiker'
```

Use `--evidence-file <evidence-file>` only when the original evidence path recorded in the proposal is no longer available.

This live write first replays the proposal and all optimistic-concurrency guards. It then appends the immutable correction set, row correction, audit run and processing version, and stores an immutable payload-bearing draft in one transaction. Original source and curated values remain unchanged. Approval, the processing draft, and later release promotion remain distinct audit states even though the apply transaction creates the first two atomically.

Only one pending correction set is allowed per season. A no-impact apply is reported distinctly, stores a draft whose bundle equals its predecessor, and still requires explicit promotion so the reviewed correction enters the immutable release lineage.

### 4. Inspect the stored immutable draft

```bash
python3 -m pipeline correction-release \
  --proposal-file <git-ignored-proposal.json> --preflight \
  --output <git-ignored-preflight.json>
```

This step is read-only. It reads the exact stored draft rather than recalculating a mutable candidate, and binds its proposal, correction-set, predecessor and bundle hashes. For a metric-changing correction it proves 15 predecessor team payloads are reused exactly. For a no-impact correction it proves all 16 team payloads and the league bundle are unchanged. In both cases promotion remains required.

### 5. Promote the reviewed draft

```bash
python3 -m pipeline correction-release \
  --preflight-file <git-ignored-preflight.json> \
  --reviewer 'Abdel Babiker' \
  --release-label <unique-correction-release-label> \
  --rollback-release-label <unique-closeout-failure-rollback-label> \
  --rollback-reviewer 'Abdel Babiker' \
  --rollback-reason '<reason if parity export closeout fails>' \
  --rollback-evidence-file <rollback-evidence-file> \
  --rollback-operator <operator>
```

Promotion is a separate live write. It creates a new immutable 16-team correction bundle in `reporting.correction_league_payloads_v1` and `reporting.correction_team_payloads_v1`, copies the 15 unaffected team payloads byte-for-byte through the unified predecessor views, inserts the affected team and pooled league candidates, and retires rather than deletes the predecessor. It does not write to frozen V2 context or payload tables. A no-impact release creates the required audited successor while reusing all 16 team payloads.

The command verifies the promoted release identity and exact reviewed bundle through `reporting.latest_approved_dashboard_bundle_v4` while refreshing the 16 parity exports. The V5 team and league readers then select the additive correction payloads, including the preserved or recomputed `contact_distribution`. If that closeout fails after database promotion, it invokes the supplied append-only rollback immediately and re-raises the failure.

### 6. Verify the result

Before promotion, `verify-served-baseline` must still match the captured predecessor exactly. After a deliberate correction promotion, the old baseline is expected to differ. Verify the promoted release against the preflight's exact bundle and hashes, confirm its predecessor remains retained, and capture a fresh served baseline for future work.

## Rollback and correction of a correction

Never delete or reapprove a historical correction or release. To cease serving a promoted correction:

```bash
python3 -m pipeline correction-rollback \
  --release-label <correction-release-label> \
  --rollback-release-label <unique-rollback-successor-label> \
  --reviewer 'Abdel Babiker' --reason '<rollback-rationale>' \
  --evidence-file <rollback-evidence-file> --operator <operator>
```

Rollback creates a new immutable successor in the additive correction payload tables containing the correction release's exact retained predecessor payloads. It records the target release, reviewer, rationale, evidence hash and execution provenance, then refreshes parity exports from the newly served V5 successor. The correction, its draft, its release, all prior payloads, and all frozen V2 context and payload rows remain immutable and queryable.

If the decision itself was wrong, create a compensating proposal using `--supersedes-correction-id`, then apply and promote it through the same gates. The served correction-set view follows release and rollback lineage, so a rolled-back correction does not silently become active again.

## Correction types and carry-forward

- `eligibility`: pass JSON boolean `true` or `false` to include or exclude an existing injury through an auditable effective-value overlay, never deletion.
- `days_injured`: pass a JSON number or `null`. Preserve `null` as missing and never replace missing duration with zero.
- `diagnosis_code`, `body_location_code`, and `injury_type_code`: pass an exact JSON string for a registered controlled value. Retain source evidence and accept only controlled IOC classifications. Ambiguous evidence remains `Unknown`.

An absent source row is not a correction. Add it through a separately checksummed intake amendment.

The mechanism is season-keyed and supports later seasons without hard-coded 2024-25 row assumptions. Shared versioned rules may carry forward, but each correction remains bound to that season's source row, evidence, current correction-set hash and approved rule version.

## Non-negotiable safety checks

- Confirm the exact approved hosted target before installation, apply, promotion or rollback.
- Preserve the pre-installation V5 baseline exactly. No verification correction, pending draft or sample release may remain after installation tests.
- Keep source and curated rows immutable. Corrections, drafts, release contexts, rollback contexts and additive correction payloads are append-only. Never route a dynamic bundle through the frozen V2 context or payload tables.
- Keep normal release paths from dropping active corrections. The active-correction guard blocks both ordinary V2 approval and ordinary predecessor retirement until a correction-aware successor or append-only rollback reconciles that season.
- Stop on stale row evidence, a changed proposal or draft, a candidate mismatch, an unchanged-team hash mismatch, or a served-baseline difference.
- Repair installed behaviour through an additive successor migration or compensating correction. Never rewrite or delete history.
