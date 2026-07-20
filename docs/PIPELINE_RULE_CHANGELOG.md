# Pipeline Rule Change Log

Every change that alters a derived value, classification, cohort, denominator, or published figure is recorded here when it is accepted — not retrospectively at season end. See `AGENTS.md` § "Cross-Season Reproducibility and Change Capture" for the binding rule.

**Carry-forward status** answers one question: *does a new season automatically inherit this?*

- `carries-forward` — a versioned rule in `analysis.*_vN` / migrations. Year 2 gets it for free.
- `season-specific` — a row-level adjudication keyed to source rows. Year 2 does **not** inherit it; equivalent issues in Year 2 need their own adjudications.
- `team-specific` — a per-club source mapping. Reused for that club until its export changes and the profiling gate re-runs.
- `not-yet-in-pipeline` — accepted in principle but still only in a dev preview file. **Will not apply to Year 2 until promoted to a versioned view.**

---

## 2026-07-20 — Accepted 14-item adjudication batch

| Field | Value |
|---|---|
| Workbook SHA-256 | `b258bd9ad13d1fa6ddb58f99fec1f6cf1dfa559cfcd01fa8787931b53b484f1d` |
| Evidence-manifest SHA-256 | `d3be9f4308f070951abc0e0f6fd2e33f4f8c670f3b514d1176dc0ebaf5cdbf7e` |
| Reviewer | Abdel Babiker |
| Row-level refs | `ID-01`, `ID-02`, `ID-03`, `DX-02`, `DX-03`, `DX-12`–`DX-18` |
| Rule refs | `IA-02`, `ACL-01` |
| Classification version | `reporting_classification_2026-07-20_v1` |
| Migration | `20260720150000`, SHA-256 `28996f175f6faa36f2b076924312bf6546d748e89b6e5b9ed8ae1066926a616c` |

**Season-specific corrections.** Cardiff `ID-01` and `ID-02` correct two return-to-availability years to 2025; Dragons `ID-03` corrects the injury year to 2025. The immutable source values remain unchanged. The corrections are stored as `audit.adjudications`, overlaid before processing, and re-derived through new `processing.record_versions` and row-level events. They do not carry into another season.

**Duplicate decisions.** All nine reviewed exposure pairs differ in the substantive source field `training_day`; they are retained as distinct records. `DX-02` and `DX-17` keep their existing rehab/RTP exclusions. No exposure denominator changes. These are audit-only season-specific decisions.

**Reporting classification (`reporting_classification_2026-07-20_v1`).** Reliable explicit concussion evidence takes reporting priority as `Concussion`; otherwise diagnosis reporting uses the already-standardised body-location × IOC tissue/pathology parent (for example, `Knee · Joint sprain`). Specific evidence such as ACL may remain available as an auditable subtype but is not required or separately counted. The original source and curated values are preserved. This classification carries forward through the versioned additive view; it does not adopt the separate draft cohort, denominator, or broader named-diagnosis rules in `tools/sql/dashboard_v3_preview.sql`.

---

## 2026-07-20 — V3 diagnosis inference layer (draft.9)

| Field | Value |
|---|---|
| Rule version | `urc-diagnosis-inference-v3-draft.9` |
| Status | `not-yet-in-pipeline` (broader dev preview only; the narrower IA-02/ACL-01 subset is promoted separately above) |
| Carry-forward | `carries-forward` **once promoted** |
| Adjudication ref | pending for the broader named-diagnosis rules |

**What changed.** Diagnosis classification reworked into two tiers. Tier 1 names a diagnosis from evidence (concussion, hamstring strain, quadriceps, calf, adductor/groin, achilles/patellar tendon, meniscal, syndesmosis, Lisfranc, AC joint, shoulder instability/labral, fracture, contusion, tendon). Tier 2 composes a compound diagnosis from the already-standardised body location × IOC tissue/pathology bucket where tier 1 does not fire. A row stays `Unknown` only when it lacks a tier-1 name *and* a complete body×tissue pair.

**Why.** Diagnosis `Unknown` was inflated by a bucketing gap, not missing data: 425 of 618 Unknown time-loss rows carried a complete standardised body×tissue pair, and only 2 rows lacked all four evidence channels (body, tissue, Orchard/OSIICS code, description). Unknown fell 618 → 210 (match 301 → 106, training 251 → 82).

**Provenance.** Compound diagnoses take the weaker of their two contributing classes; a class is never upgraded. The four-class model (`source_reported` / `mapped` / `inferred` / `adjudicated`) and the executable origin→class validation are unchanged.

---

## 2026-07-20 — IOC joint-sprain parent reporting

| Field | Value |
|---|---|
| Rule version | `reporting_classification_2026-07-20_v1` |
| Status | accepted in the additive reporting-classification view |
| Carry-forward | `carries-forward` |
| Decision | `ACL-01`, Abdel, 20 July 2026 |

**What changed.** Diagnosis reporting now uses the already-standardised body-location × IOC tissue/pathology parent, so an ACL-evidenced row reports under `Knee · Joint sprain`. Specific structure evidence remains in the immutable source and can be queried for audit, but the released aggregate neither requires nor separately counts an ACL subtype.

**Why.** In IOC 2020 — and in this project's frozen `docs/IOC_TAXONOMY_BUCKETS.csv`, where bucket `joint_sprain` includes ligament-like source categories — joint sprain is the reporting parent. This avoids requiring a more specific clinical fact than the source supports.

**Scope limit.** The broader draft.9 named-diagnosis rules (including AC joint, Lisfranc, syndesmosis, muscle-group, and other named entities) remain preview-only and are not promoted by ACL-01.

---

## 2026-07-19 — Thigh muscle split retained (hamstring vs quadriceps)

| Field | Value |
|---|---|
| Status | `not-yet-in-pipeline` (promotion in progress) |
| Carry-forward | `carries-forward` **once promoted** |
| Decision | Abdel, 19 July 2026 |

Thigh muscle injuries are named as `Hamstring strain` (posterior) or `Quadriceps muscle injury` (anterior) where evidence supports it, rather than collapsed into a single thigh-muscle bucket. Injuries without evidence of which muscle group remain the generic `Thigh · Muscle injury` compound — they are not assigned to either. Distinguishing posterior and anterior thigh injury is epidemiologically meaningful (different mechanisms and prevention).

---

## 2026-07-19 — Preview cohort: season sanity bound, exposure-window restriction lifted

| Field | Value |
|---|---|
| Cohort rule | `season_bound_2024-07-01_2025-06-30_no_exposure_window` |
| Status | `implemented-in-pipeline` by migration `20260720170000`; immutable live bundle promotion recorded separately |
| Carry-forward | `carries-forward`, with an explicitly registered season window per season |
| Decision | Abdel, 19 July 2026 |

**What changed.** Injuries dated inside the season sanity bound (2024-07-01 – 2025-06-30) are included even when outside a team's own exposure coverage window; exposure denominators are bounded by the same season window so numerator and denominator share one window. Undated but season-attributed injuries are included in counts and breakdowns, labelled, and excluded from monthly series.

**Why.** The frozen `_v1` cohort restricted injuries to each team's exposure coverage window, which discarded in-season injuries from teams with partial exposure reporting. Binding both sides to one explicit season window keeps rates coherent while recovering those cases.

**Year-2 note.** The window is a parameter, not a constant — Year 2 uses its own season bounds. Do not hard-code 2024-25 dates when promoting.

**Implementation.** `analysis.reporting_season_windows_v3` registers each season's bounds; `analysis.injury_cohort_by_build_season_bound_v3` and its bounded exposure/dashboard successors recompute all team and league payload sections. The release context records the cohort version and a cohort-evidence hash transitively bound to the checksum and locator of `docs/evidence/season_bound_reporting_2024-25.json`. Frozen V1/V2 views and prior immutable releases remain unchanged.

---

## 2026-07-19 — Comparison labels show real codebook aliases

| Field | Value |
|---|---|
| Status | in production code (display layer only) |
| Carry-forward | `carries-forward` (display behaviour; no effect on any computed figure) |
| Decision | Abdel, 19 July 2026 |

League-comparison rows render each club's real codebook alias, joined at display time from `TEAM_DISPLAY_ALIAS_JSON` (Git-ignored env, sourced from the protected alias map), falling back to `Club NN` when unset. No name→alias pair enters Git, the database, or exports. Affects no metric. See `AGENTS.md` § "Privacy and Data Safety" for the linkage consequence and the pre-share gate this creates.

---

## Pending entries

Recorded here when accepted:

- **Remaining data-quality adjudications outside the accepted 14-item batch** — exposure year-slips and other pending proposals. Expected `season-specific`; not approved by the 20 July workbook.
- **`italian elite championship` marker / `injury_processing_2026-07-07_v2` rule identity** — blocks reprocessing until adjudicated. Expected `carries-forward`.
