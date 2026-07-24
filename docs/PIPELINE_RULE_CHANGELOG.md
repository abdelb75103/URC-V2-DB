# Pipeline Rule Change Log

Every change that alters a derived value, classification, cohort, denominator, or published figure is recorded here when it is accepted — not retrospectively at season end. See `AGENTS.md` § "Cross-Season Reproducibility and Change Capture" for the binding rule.

**Carry-forward status** answers one question: *does a new season automatically inherit this?*

- `carries-forward` — a versioned rule in `analysis.*_vN` / migrations. Year 2 gets it for free.
- `season-specific` — a row-level adjudication keyed to source rows. Year 2 does **not** inherit it; equivalent issues in Year 2 need their own adjudications.
- `team-specific` — a per-club source mapping. Reused for that club until its export changes and the profiling gate re-runs.
- `not-yet-in-pipeline` — accepted in principle but still only in a dev preview file. **Will not apply to Year 2 until promoted to a versioned view.**

---

## 2026-07-24: Provenance correction, successor v3/v4 workbook serialization

No derived value, classification, cohort, denominator, or published figure changed. Recorded here because a provenance claim in an accepted audit record was wrong and outputs are not under version control.

The Sharks squad-normalization QA record (`outputs/urc_final_human_review_2024-25/urc_injury_sharks_squad_normalization_qa_2024-25_v2.json`) claims the v4 successor workbook was produced by a native Microsoft Excel save. It was not: the native save failed (preserved as `..._v3.failed_excel_ui_attempt.xlsx`) and v3/v4 were rebuilt by openpyxl re-serialization of the verified live values. Side effects (sharedStrings dropped, four built-in numFmt declarations trimmed, Review Queue empty formatted range truncated) are benign. Frozen vs v4 shows exactly 180 value diffs, all accounted for by existing audit records; the Excel open-verification of v4 remains valid. Full statement: `outputs/urc_final_human_review_2024-25/PROVENANCE_ADDENDUM_SHARKS_V3_V4_2026-07-24.md` (per `docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md` Phase 0).

---

## 2026-07-24: Bulls and Cardiff Unknown injury adjudications

| Field | Value |
|---|---|
| Rule version | `bulls_cardiff_unknown_adjudication_2026-07-24_v1` |
| Status | accepted and applied to the local 2024-25 included injury CSV only |
| Carry-forward | `season-specific`; these are human-reviewed row decisions, not a general diagnosis-to-Time-Loss rule |
| Decision provenance | Abdel Babiker, 24 July 2026 |
| Decision ledger | `outputs/urc_final_human_review_2024-25/urc_injury_bulls_cardiff_unknown_adjudication_decision_2026-07-24.json` |
| Resulting CSV | 2,301 rows × 28 columns, SHA-256 `e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb` |

**Accepted decisions.** After reviewing the recorded diagnoses, CSV rows 74, 76, 88, 92, 98, 100, 104, 115, 116, 135, and 137 were adjudicated from Unknown to Time Loss. CSV rows 35, 99, 111, 134, 140, and 142 remain Unknown because their evidence was not considered sufficient for a defensible Time Loss decision.

**Methodological limit.** Diagnoses such as concussion, ACL injury, hamstring strain, patellar dislocation, and other substantial injuries can strongly support a row-level human decision, but diagnosis alone does not universally prove lost training or match availability. These values are therefore recorded as `adjudicated`, with the diagnosis and description retained as evidence. They do not silently create a reusable diagnosis-based classification rule.

**Manual-edit reconciliation.** Abdel's pre-existing edits were reconciled against the prior accepted CSV state and added to the row-level audit. CSV row 138 changed from Unknown to Time Loss after concussion review. CSV row 1264 copied its existing Fit For Selection Date, `21/10/2024`, into Confirmed Return Date and recorded eight days injured. Row 1264 is source-labelled as Illness, so its Time Loss versus Medical Attention value was left Unknown rather than applying an injury-only classification rule.

**Execution and provenance.** The batch preserves all 2,301 rows, all 28 columns, retained-row order, and the source-row mapping. The audit records exact old and new values, source workbook row, diagnosis evidence, action, reason, rule version, and `adjudicated` origin. The Unknown Injury cohort fell from 44 in Abdel's manually edited input to 33. No Excel workbook, database object, migration, analysis view, release, dashboard, or website was changed.

---

## 2026-07-24: Unknown injury classification and return-date evidence

| Field | Value |
|---|---|
| Rule versions | `unknown_injury_fit_for_selection_2026-07-24_v1`; `unknown_injury_inference_2026-07-24_v1` |
| Status | accepted and applied to the local 2024-25 included injury CSV only |
| Carry-forward | `not-yet-in-pipeline`; later seasons require an approved versioned implementation or equivalent evidence review |
| Decision provenance | Abdel Babiker, 24 July 2026 |
| Adjudication ledger | `outputs/urc_final_human_review_2024-25/urc_injury_unknown_inference_adjudication_2026-07-24.json` |
| Row-level audits | `urc_injury_unknown_fit_resolution_audit_2026-07-24.csv`; `urc_injury_unknown_inference_audit_2026-07-24.csv` |
| Resulting CSV | 2,301 rows × 28 columns, SHA-256 `52fac7178b26a3adc7d83aaffe16f2099920a48dd2040fe8c26d1581702d395b` |

**Accepted return-date rule.** When `Confirmed Return Date` is blank and a valid `Fit For Selection Date` is present, the fit date is accepted as the confirmed return date. With a valid injury date, elapsed calendar days exclude the injury day. A positive duration implies `Time Loss`; a same-day return implies `Medical Attention`. Without an injury date, the return date may be populated but duration and classification remain unresolved. This resolved source row 359 as 397 days and Time Loss, and source row 505 as zero days and Medical Attention. Source row 210 received a confirmed return date but remains Unknown because its injury date is absent.

**Accepted inference rules.** A positive source `Games Missed` value establishes lost match availability and therefore implies `Time Loss`. This classified source row 209 as inferred Time Loss. Source `Required Surgery = Yes` also implies `Time Loss`; this classified source rows 185, 198, 202, 382, 468, 492, 498, 502, 512, 539, and 1764. These classification rules do not create a duration when defensible injury and return dates are unavailable. Audit rows label these values as `inferred` and retain the exact source evidence.

**Accepted row-level correction.** At source row 470, the trailing `q` in `10/02/25q` was adjudicated as an extraneous character because removing it yields the otherwise complete date `10/02/2025`. With injury date `25/01/2025`, the derived duration is 16 days and the classification is inferred Time Loss. The corrected date is labelled `adjudicated`; duration is `derived`; classification is `inferred`.

**Unresolved adjudication.** Source row 1735 remains unchanged and Unknown. Its Fit For Selection Date, `20/07/2024`, precedes its injury date, `26/07/2024`, by six days. Recorded clinical context is Ospreys, right anterior-thigh muscle injury, training, gradual non-contact onset, no recurrence, and no surgery. No date is silently corrected until a defensible adjudication is accepted.

**Executed result and boundary.** Across the two batches, the Unknown injury cohort fell from 60 to 45. Row count, 28-column schema, retained-row order, and source-row mapping were unchanged. Pre-change CSV and manifest copies, exact old/new cell values, evidence origin, value origin, scripts, tests, hashes, and QA reconciliations are retained beside the working CSV. No Excel workbook, database object, migration, analysis view, release, dashboard, or website was changed.

---

## 2026-07-24 — Source-reported time-loss injuries with missing usable duration

| Field | Value |
|---|---|
| Rule version | `local_time_loss_missing_duration_decision_2026-07-24_v1` |
| Status | accepted local analytical decision; not implemented in the live pipeline, database, releases, dashboards, or website |
| Carry-forward | `not-yet-in-pipeline`; it requires a versioned analysis-view implementation before it can apply to Year 2 or any release |
| Decision provenance | Abdel Babiker, 24 July 2026 |
| Decision ledger | `outputs/urc_final_human_review_2024-25/urc_injury_analysis_release_decisions_2026-07-24.json` |
| Current dataset evidence | `outputs/urc_final_human_review_2024-25/urc_injury_included_dataset_2024-25.csv`, 2,301 rows, SHA-256 `5a01bcbca75c8902353d09557d1a3d579153fe05a9d903005eaf35399b57f0bc` |

**Accepted rule.** A retained Injury with a valid `Date Injured`, no usable `Days Injured`, no valid or defensible closure date in either the `Confirmed Return Date` or `Fit For Selection Date` channel, and an affirmative source time-loss classification (`TRUE`, `Yes`, or `Time Loss`) counts in recorded injury counts and in the time-loss incidence numerator. It contributes no observed days lost to the burden numerator, leaves the exposure denominator unchanged, and is excluded from the complete-case mean-severity calculation unless a usable duration is subsequently supplied.

**Observed scope and evidence.** The post-removal dataset has 90 rows meeting that definition: 64 source `TRUE`, 9 source `Yes`, and 17 source `Time Loss`. The equivalent pre-removal count was 91. The sole removed case was Scarlets source workbook row 1892 (`Ath_288`, 24/07/2024, `Non-Rugby`, source `Yes`, blank duration and return date), removed only from the included CSV by `included_injury_nonrugby_gym_removal_2026-07-23_v1`. Evidence is bound to the current manifest's ordered source-row mapping, the 51-column source-facing `injury_master_2024-25.csv`, the focused-cleanup audit that normalized the affirmative values, and the non-rugby/gym removal audit. Across the current included dataset, 90 of 1,013 source-reported Time Loss injuries have missing duration (8.9%). Missingness is uneven: Lions has 15 of 37 (40.5%) and Sharks 37 of 94 (39.4%). Consequently, known-duration burden totals are incomplete lower bounds; complete-case mean severity is incomplete and may be biased by missingness, rather than being assumed to be a lower bound.

**Duration semantics.** `duration_missing_closure_unknown` means that final duration and defensible closure evidence are unavailable. It is not an assertion that the injury remained open: do not assign zero days, impute duration, or call it right-censored. `right_censored_open` is permitted only when source evidence confirms that the injury remained unresolved at a pre-specified observation end date, with that date and provenance recorded. The present 28-column CSV has no duration-status field, so these are recorded local analytical semantics rather than a dataset rewrite.

**Scientific limit and implementation boundary.** The Lions, Sharks, and Stormers closure follow-up evidence identifies 64 of the 90 rows as requiring confirmation of closure/return status and true days lost. They therefore support missing-duration handling, not a presumption of open injury. Implementing the accepted numerator rule in a live release still requires a new versioned analysis view, a recorded adjudication, rerun, and re-release for affected team/seasons. Frozen views and all existing releases remain unchanged.

---

## 2026-07-22 — Evidence-bound OSIICS and explicit body/type classification

| Field | Value |
|---|---|
| Rule version | `reporting_classification_2026-07-22_v2` |
| Status | accepted; live adjudication recorded and incremental immutable bundle promotion approved |
| Carry-forward | `carries-forward` for the exact code catalogue and conservative inference rules; the 2024-25 row ledger remains season-specific evidence |
| Decision provenance | Abdel Babiker, 22 July 2026; approved use of defensible OSIICS/body/type/description evidence and the NPM neck multi-type representation |
| Adjudication ref | `OSIICS-01` |
| Evidence manifest | `docs/evidence/osiics_exact_mapping_2024-25.json`, SHA-256 `db1823f5d402c9989ef7c053dcfd4aced637eab142f7d372e6b16f22b168ed7c` |
| Migrations | Base `20260722130000_osiics_exact_reporting_classification.sql` (`f469d4a724a481535c81c3c250a56a3ae75c29a6b6936f3d9cafe27612aa3c09`); additive correction `20260722140000_osiics_source_body_pathology_mapping.sql` (`47b4b918248b3cd0222c9013f1dad886bcc3995fb4348ed06124fac8fabe7b63`); incremental bundle release `20260722150000_incremental_classification_bundle_release.sql` (`ca10f3a52ac9df912c10cc6487169607a5770759e0e037cfa66cb4e99daa45f8`) |

**What changes.** In the accepted 2024-25 league cohort, 111 Unknown diagnoses have an exact reviewed OSIICS/OSICS pathology mapping and 9 more have one unique explicit body area plus one unique controlled tissue/pathology type. One NPM case is reported as `Neck · Muscle/tendon injury`: its candidate types are retained as `muscle_injury;tendinopathy`, while its single analytical injury type is `nonspecific` so it contributes exactly once. The resulting bound expectation is 121 newly informative diagnoses and 245 → 124 underlying Unknown diagnoses. QRA preserves the supplied canonical body (`Ankle` or `Lower leg`) while applying the official Achilles tendon-rupture pathology; QBC maps to lower-leg bursitis.

**Scientific limits.** Existing non-Unknown values win. Code/body conflicts, multiple candidate types, broken or nonspecific codes, and weak descriptions remain unresolved. QPS remains Unknown because “soleus trigger points/spasm” does not establish structural muscle injury. Original source and curated values are immutable; the successor view exposes effective values and provenance only.

**Publication behaviour.** The successor recomputes only diagnosis, body-location, injury-type, and combined injury-profile aggregates from the effective reporting values. The incremental release candidate copies the approved bundle and replaces only `body_locations`, `injury_types`, and `injury_profiles`; headline, exposure, monthly, setting, severity, coverage, method, limitations, and all other keys remain exactly inherited. The remaining Unknown categories are retained for completeness/audit but filtered from every front-facing dashboard category view. Promotion is an immutable 16-team league bundle; its approved predecessor remains available for rollback.

---

## 2026-07-21 — Injury-type family anatomy roll-up

| Field | Value |
|---|---|
| Rule version | `injury_type_family_2026-07-21_v1` |
| Status | accepted additive reporting reader |
| Carry-forward | `carries-forward` |
| Decision provenance | Abdel Babiker, 21 July 2026; approved the recommended family model and the methodology record in the Injury Types design/review session |
| Migration | `20260721120000_injury_type_family_reader_v3.sql`, SHA-256 `763516def079dffe7bb66b5f5d092143900fa35e97781d8d035b15e9c70177e6` |

**What changed.** The approved IOC injury-type rows are rolled into major display families for the Injury Types anatomy explorer: Muscle; Tendon; Ligament / sprain; Joint & capsule; Bone; Cartilage; Nervous system; Skin & superficial tissue; Internal organ; Vascular; and Other / unclassified. The mapping covers all 26 controlled injury-type codes. Each family retains its contributing controlled subtypes, and family counts and days lost are pooled before incidence, burden, and mean severity are derived. Types not present in an approved dashboard payload do not produce an interactive family total.

**Why.** The dashboard needs a clinically legible anatomical overview rather than 26 competing fine-grained regions. The major-family layer matches the approved user interaction while preserving the exact subtype evidence and avoiding unsupported clinical inference. The transparent silhouette is a presentation layer only; the versioned SQL mapping remains the single analytical definition consumed by team and league readers.

**Scope and lineage.** The additive `reporting.latest_team_dashboard_v3` and `reporting.latest_league_dashboard_v3` readers extend the immutable approved V2 payloads; frozen V1/V2 views and release data remain unchanged. Rates reuse `analysis.rate_per_1000_v1`. This rule carries forward to later seasons while their controlled injury types remain on the same canonical code list; any code-list or family-mapping change requires a new versioned mapping and a new recorded decision.

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
