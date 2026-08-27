# Pipeline Rule Change Log

Every change that alters a derived value, classification, cohort, denominator, or published figure is recorded here when it is accepted — not retrospectively at season end. See `AGENTS.md` § "Cross-Season Reproducibility and Change Capture" for the binding rule.

**Carry-forward status** answers one question: *does a new season automatically inherit this?*

- `carries-forward` — a versioned rule in `analysis.*_vN` / migrations. Year 2 gets it for free.
- `season-specific` — a row-level adjudication keyed to source rows. Year 2 does **not** inherit it; equivalent issues in Year 2 need their own adjudications.
- `team-specific` — a per-club source mapping. Reused for that club until its export changes and the profiling gate re-runs.
- `not-yet-in-pipeline` — accepted in principle but still only in a dev preview file. **Will not apply to Year 2 until promoted to a versioned view.**

---

## 2026-08-26: 2024-25 final injury classification and monthly timeline successor

| Field | Value |
|---|---|
| Status | `implementation-ready`: governed evidence, the single additive SQL successor, local replay and shared dashboard changes pass their local gates. Live execution is recorded separately after promotion. |
| Rule version | `reporting_classification_2024-25_2026-08-27_v1` |
| Carry-forward | Classification decisions are `season-specific`. Whole-hour exposure presentation and the recorded-injury timeline series use shared components and therefore carry across season tabs. |
| Evidence | Classification evidence `docs/evidence/urc_2024-25_classification_monthly_successor_2026-08-26.json`, SHA-256 `0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833`; diagnosis evidence `docs/evidence/urc_2024-25_specific_diagnosis_evidence.json`, SHA-256 `5855127dc199df1918cb906250809ad00b6f2d8ea03904a7ceee5d587996a753` |
| Migration | `supabase/migrations/20260826100000_urc_2024_25_classification_monthly_successor.sql`, SHA-256 `1b2d6a150949f3e879148eb934c2cfebf2d90e9408445891541da2868a23f802` |

**Classification and duration.** The correction-aware successor separates final classification from duration. Source-reported and adjudicated Time Loss cases remain Time Loss when duration is null, count in incidence, and remain internally open or ongoing without invented days. Medical Attention and zero-day cases are closed on Date Injured and contribute only to recorded counts. Remaining unclassified cases also contribute only to recorded counts. Severity, mean, median and burden use known-duration Time Loss cases.

**Adjudication and lineage.** The 32 human decisions reconcile to 15 Time Loss, 1 Medical Attention and 16 unclassified outcomes. Their source facts remain 29 blank values and 3 `FALSE` values; `FALSE` is retained as a source value, not treated as a scientific class. Canonical identity is the exact 2024-25 immutable master hash plus stable master source row and its deterministic 28-field row-value hash. Workbook sheet and row locators are secondary provenance only. The adjudication baseline remains hash-bound, while the current authoritative review workbook hash is `4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73`. The evidence binds the exact approved Dragons predecessor, retained live-aligned fixture and active correction-set hash.

**Local reconciliation.** The retained live-aligned Dragons fixture reconciles 1,662 recorded injuries, 787 known-duration Time Loss injuries and 17,575 observed days. The successor preserves the accepted one-day TL corrections at source rows 1120 and 1121. The adjudicated row set contains 15 null-duration Time Loss outcomes; together with 111 source-reported null-duration Time Loss cases, the final classification produces 913 Time Loss injuries without changing recorded totals or observed days. Monthly Date Injured totals are 1,656 recorded and 912 Time Loss injuries, with 6 undated recorded cases and 1 undated Time Loss case retained in season totals. All 16 teams reconcile to league. Analysis window, coverage, prior season, monthly exposure and monthly distance remain byte-identical.

**Diagnosis and presentation.** Reviewed specific-diagnosis groups replace the derived location and injury-type compound for diagnosis views. The evidence contains 1,660 injury mappings; 392 illnesses are excluded, two eligible injuries fall back to internal `unknown`, and front-facing diagnosis lists hide `unknown`. Overview and timeline show Injuries with TL injuries, and Overall incidence with TL incidence. Match and Training overview filters use their own released total and TL values. Other incidence views remain TL incidence. Shared exposure-hour labels round to whole hours while stored values and rates retain full precision.

---

## 2026-08-23: Year 2 V6 league candidate sealed snapshot

| Field | Value |
|---|---|
| Status | `applied-and-promoted`: the exact additive migration is registered and the complete 16-team V6 bundle is approved on the live URC database. |
| Rule version | `urc_2025_26_v6_league_candidate_fast_path` |
| Carry-forward | `season-specific`: the sealed snapshot is valid only for the exact current 2025-26 sixteen-member release/build set. |
| Migration | `20260823120000_urc_2025_26_v6_league_candidate_fast_path.sql` |

**Execution only.** The migration selects the exact sixteen immutable, approved team release payloads, verifies their stored canonical hashes and release tuple, and reconstructs the established league aggregates in eleven bounded temporary stages under one repeatable-read transaction. Global exposure counts and median severity remain direct analytical reads. It then uses the existing base and enriched JSON expressions and ordering to assemble one canonical candidate and stores those exact JSONB bytes in a private, immutable snapshot. The existing candidate view reads the snapshot only while a deterministic hash of all sixteen current team release and curated-build identities still matches the sealed member set. A member or active-build change returns no league candidate until a separately reviewed versioned successor is installed.

**Live attestation.** Migration SHA-256 `ad8ed2146569c81020f2d8425a84d053045a1bf727f767949eff0cee97f715eb` is registered on project `eukkvswaxweenovqqgzr`, database `postgres`. The transactional apply completed in 5.6 seconds. Post-apply proof found exactly one sealed row and one candidate, matching sixteen current release/build identities and the canonical payload hash; row-level security is enabled and `web_reader` has no direct snapshot access. Two predecessor implementations exceeded their statement timeout and rolled back fully before this accepted version, leaving no partial object or registration.

**Release.** `urc-2025-26-v6-1287c2a447f5-a1` was promoted with reviewer `Abdel Babiker`. The league payload SHA-256 is `165fa8ac3cd59de726d66f9af1da9115bb0ff2518717ff76b7a7849adb551a02`; the complete bundle SHA-256 is `1287c2a447f5ae1da74a24cf09c30a2d419585415233a1b136ad6f7135130191`; the 16-team parity export-set SHA-256 is `d8d44587070013c9f8833b1da6b6d9ce9def3a0318c993b10a30ec9ea77a5ea5`. Post-promotion proof found exactly one approved V6 bundle, one league reader and sixteen distinct team readers with the expected hashes, an attested reader target and no open pipeline runs.

**No reporting rule change.** Candidate columns, payload bytes, formulas, classification and cohort evidence, release validation triggers, immutable bundle storage and public readers are unchanged. The snapshot has row-level security, no public or web-reader grant, and rejects update or delete. The migration does not reference a 2024-25 relation and applies no imputation.

---

## 2026-08-22: Year 2 V6 candidate view query optimisation

| Field | Value |
|---|---|
| Status | `implemented-not-executed`: additive migration and focused SQL-contract tests only. No database query, migration or release ran. |
| Rule version | `urc_2025_26_v6_candidate_view_optimisation` |
| Carry-forward | `season-specific` implementation for the existing 2025-26 V6 candidate views. |
| Migration | `20260822220611_urc_2025_26_v6_candidate_view_optimisation.sql` |

**Execution only.** The enriched team payload now filters its four repeated V6 aggregate sources to one base team row, then evaluates each source once through a `MATERIALIZED` CTE. The league payload applies the same pattern once per selected season. The downstream team and league candidate relations keep their existing names and column contracts.

**No reporting rule change.** The view replacements retain `security_invoker`, every output column, JSON key, value expression and ordering from the predecessor definitions. They do not change source data, classification, cohort membership, exposure completeness, denominators, fixture rules, payload semantics or any 2024-25 relation.

---

## 2026-08-22: Curated exposure scope projection compatibility

| Field | Value |
|---|---|
| Status | `implemented-not-executed`: the code and focused tests are ready for the failed Year 2 curated-build retry. This entry records no database build, release, or published change. |
| Rule version | `curated_build_2026-08-22_v2` |
| Carry-forward | `carries-forward` at the curated-build boundary, but only for the six named input statuses. Any other nonblank status fails the build. |
| Decision provenance | Transactional Year 2 build failure against the existing `curated.exposure.scope_status` constraint, 22 August 2026. |
| Code | `pipeline/__main__.py`; contract tests in `tests/test_curated_exposure_scope_projection.py`. |

**Projection.** The curated layer retains `in_scope_explicit`, `scope_unknown_included`, and `out_of_scope_explicit`. It maps the processed intake statuses `excluded`, `outside_protocol_window`, and `within_protocol_window_scope_unknown` to `scope_unknown_included`. Null and blank status values remain null. The build rejects every other nonblank value before it writes a curated row.

**Boundary.** This compatibility projection changes only `curated.exposure.scope_status`. The build copies source and record-version lineage, exposure eligibility, exclusion reasons, dates, minutes, distance, and grain as before. It does not add exposure, make an excluded row eligible, impute a value, or alter the signed intake package.

---

## 2026-08-22: 2025-26 injury eligibility bridge

| Field | Value |
|---|---|
| Status | `applied-not-promoted`: the exact additive migration is registered on the approved live URC database. The protected input successor remains unsigned and ingest-blocked, so no Year 2 intake or release has been promoted. |
| Rule version | `urc_2025_26_injury_eligibility_bridge_v1` |
| Carry-forward | `season-specific`: it applies only to the registered 2025-26 V6 tuple. A later season requires a separately reviewed bridge. |
| Evidence | `docs/evidence/urc_2025_26_injury_eligibility_bridge.json`, SHA-256 `a47d89700b22fdc3c9aa91203aed5227fbf76a2e4e7eab7dd8f18f9e13092ea1` |
| Migration | `20260822030000_urc_2025_26_injury_eligibility_bridge.sql`, bound through the V6 release contract and combined checksum registration. |

**Rule.** A blank source injury date may be `season_attributed_undated` only when the checksum-bound 2025-26 adapted successor says so. The processing state retains `date_injured = null`, records the controlled date-basis field and audit reason code, includes the row in non-monthly totals, and keeps it out of monthly series. It never fabricates a date. Nonblank unparseable dates and parseable dates outside 1 September 2025 to 30 June 2026 remain `review_required` and excluded from the reporting cohort.

**Exclusions and duplicates.** A non-placeholder explicit source exclusion produces a checksum-bound analysis-audit exclusion using the seeded `explicit_source_exclusion` code. Unknown identities and insufficient signatures cannot form an injury duplicate candidate. Candidate duplicate signatures remain `included_pending_protocol` and audit-visible. V12 has zero duplicate-copy exclusions.

**Cohort guard.** The V6 injury cohort continues to accept dated eligible injuries in the registered window. For a null date it now requires the latest immutable processing state to carry `injury_date_basis = season_attributed_undated` and `included_pending_protocol`. This is a Year 2 V6 view replacement only. Every 2024-25 processing path, view, release, payload and reader remains unchanged.

## 2026-08-22: 2025-26 incomplete-exposure V6 successor

| Field | Value |
|---|---|
| Status | `applied-live`: the exact additive migration is registered on the approved live URC database. No source row or Year 2 release was written, and the frozen 2024-25 release remained checksum-equivalent after application. |
| Rule version | `urc_2025_26_incomplete_exposure_reporting_v6` |
| Carry-forward | `season-specific`: it applies only to the registered 2025-26 V6 tuple. A later season requires its own evidence-bound successor. |
| Evidence | `docs/evidence/urc_2025_26_incomplete_exposure_reporting_v6.json`, SHA-256 `b6fae7ce7e4609000337c29d7965e99809da3733b126522a1faabf600fdcc23c` |
| Migration | `20260822020000_urc_2025_26_incomplete_exposure_reporting_v6.sql`, bound through the V6 release contract and combined checksum registration. |

**Rule.** Every active 2025-26 build produces a V6 candidate. A team denominator is available only when included source-backed exposure hours meet that team's accepted fixture-derived match hours. Otherwise coverage hours, training hours, distance, incidence, burden and their exposure denominators are JSON `null`; injury counts, severity and fixture-derived match hours remain visible. No exposure is imputed.

**Monthly and league behaviour.** A team-month without source-backed included exposure has null exposure and rate values. League exposure values and rates are null unless all 16 team denominators are available, and a league monthly rate also requires source-backed exposure for all 16 teams in that month. Submitted exposure may still be incomplete where a denominator is available, which is stated in the public status and limitations.

**Compatibility.** The V6 public payload keys, formulas, candidate view names, private storage, reader grants and release tuple stay unchanged. Grain uses the sole curated value even when included rows are absent, otherwise public `unknown`. The 2024-25 view families, tuples, payloads and releases are untouched.

---

## 2026-08-15: 2025-26 reporting and fixture-provenance contract

| Field | Value |
|---|---|
| Status | `prepared-not-applied-source-blocked`: additive local artefacts and tests only. The exact approved live database is the only permitted execution target; no database row, release, payload, or 2024-25 object has changed. |
| Rule version | Analysis `v6`; classification `reporting_classification_2026-07-22_v2`; cohort `analysis_window_2025-26_2026-08-15_v1`. |
| Carry-forward | `season-specific` window and release identity. The V6 computational successor remains evidence-gated and must not fall back to a V5 candidate. |
| Evidence | `docs/evidence/urc_2025_26_reporting_contract.json`, SHA-256 `e8d82b7d5b89c32576b806bb33778601030538ba8fb56fc1a68febc5f56d3fd2`; fixture preparation evidence is separately checksum-bound. |
| Migrations | `20260815010000_urc_2025_26_reporting_contract.sql`, `20260815020000_urc_2025_26_reporting_v6.sql`, and `20260815030000_urc_2025_26_team_release_v6.sql`, all not applied and registered only through the exact checksum gate. |

**Window and retention.** The initial published cohort is the inclusive period 1 September 2025 to 30 June 2026. July and August 2025 source rows remain retained with their normal lineage, but are not members of this reporting cohort.

**Fixture provenance.** Every registered 2025-26 fixture must carry an upstream official match identifier, public source locator, request and response SHA-256 values, and retrieval time in the append-only `curated.fixture_provenance_v1` relation. `analysis.fixture_preparation_evidence_v1` requires the committed official GraphQL endpoint, exact request and response checksums, prepared CSV checksum, source-locator pattern, retrieval time, and fixture-preparation evidence checksum. The accepted fixture relation requires all 151 matching rows, the full stage and 18-match-per-team structure, and one matching prepared/source checksum family. This supplements, rather than alters, the frozen `curated.fixtures` rows.

**Computational and promotion boundary.** The V6 successor creates an accepted-fixture gate, a reporting-window injury cohort, a carried-forward catalogue-only classification relation, exposure/hour and monthly/league summaries, observed body-location, injury-type, diagnosis and combined injury-profile cells, complete all/match/training/unknown setting and contact grids, immutable team payload storage, and an atomic 16-team reader/token boundary. Missing profile cells are absent rather than fabricated zero observations; shared readers already treat them as absent/zero where displayed. Classification carries the accepted OSIICS catalogue and conservative exact/unique inference rule forward, including positive concussion evidence, exact compound diagnoses and the reviewed NPM multi-type diagnosis, but never a 2024-25 row ledger or row adjudication. `analysis.accepted_release_contracts_v1` permits only the exact Year 2 tuple and requires the accepted fixture, cohort, monthly and league-summary relations plus the build-derived team, immutable team-bundle and league candidate views. Candidates remain unavailable until all release, provenance and build conditions hold. Existing V2-V5 candidate paths and every 2024-25 release remain unchanged.

**Reader boundary.** The server-side dashboard reader now proves the configured URC project reference and queries only the least-privilege boolean attestation view before each reporting statement. The attestation exposes no release, migration, fixture, team, source, or player value.

---

## 2026-08-03: No-cost Disk IO demand reduction and batch correction workflow

| Field | Value |
|---|---|
| Status | `live-installed-and-verified`: all six additive batch migrations are checksum-registered on project `eukkvswaxweenovqqgzr`; the application cache and batch operator are implemented; a rollback-only live functional harness passed and retained no test rows |
| Rule/tooling version | `dynamic_row_correction_batch_2026-08-03_v8`; `dashboard_release_token_cache_2026-08-03_v1` |
| Carry-forward | `carries-forward` for operational tooling. No analytical formula, cohort, classification, denominator or published figure changed. Each future row decision remains season-specific and evidence-bound. |
| Decision provenance | Abdel Babiker, 3 August 2026, approved no-cost implementation and live closeout |
| Evidence | `docs/evidence/DISK_IO_OPTIMISATION_2026-08-03.md`; `tools/sql/diagnose_disk_io_budget.sql`; `tools/sql/verify_dynamic_row_correction_batch_v8.sql` |

**No-cost demand reduction.** Approved V5 dashboard payloads now use a strict five-minute warm-process cache. Every request first reads a hashed release token from the least-privilege `reporting.latest_dashboard_cache_token_v1` view. A promotion or rollback changes that token and invalidates the cached payload immediately. Database failures continue to fail closed, routes remain dynamic, and access control remains outside the cache.

**Batch correction boundary.** Future corrections for one team and season are proposed, reviewed, applied and released as one append-only batch, including one-item batches. Each item retains its own evidence, source fingerprint, old and new value, rationale and rule version. The affected team and pooled league payload are derived once, while the other 15 team payloads are reused byte-for-byte. The legacy V2 single-row commands now fail closed.

**Installed migration chain.** The registered migrations and SHA-256 values are: `20260803153728` (`c4e4bdde...`), `20260803161707` (`32a0cbe4...`), `20260803162112` (`35e0a365...`), `20260803162702` (`300bf887...`), `20260803163038` (`5fdfa3f8...`) and `20260803163430` (`859e1844...`). The operator uses `analysis.row_correction_preview_v5`, `audit.apply_row_correction_batch_v8` and `reporting.promote_row_correction_batch_v8`. The complete checksums are recorded in the workflow and verification SQL.

**Live verification.** A two-item same-team batch was previewed, applied and promoted inside a live outer transaction. Verification confirmed exactly one affected team and 15 byte-identical reused teams. The append-only rollback restored the predecessor exactly, the outer transaction was rolled back, and zero verification corrections, drafts, releases or batch rows were retained. Existing source, curated, audit and release history was not deleted or rewritten. No speculative index was added to an existing large relation.

---

## 2026-07-29: Edinburgh and Glasgow fixture adjudications and illness restorations

| Field | Value |
|---|---|
| Status | `live`: replayed, independently reviewed, applied through eight append-only row corrections, and promoted through the correction-aware V5 readers |
| Rule version | `edinburgh_glasgow_fixture_and_exclusion_adjudication_2026-07-29_v1`; clarity successor `urc_match_type_fixture_clarity_2026-07-29_v1` |
| Carry-forward | `season-specific`. The eight restored rows and fifteen label/reason decisions do not carry into another season. Nearest-fixture matching remains prohibited without a row-specific adjudication. |
| Decision provenance | Abdel Babiker, 29 July 2026 |
| Result | 2,309 rows × 28 columns; CSV SHA-256 `7203b83954becb1c2232ff7e7efa73eac1da41d7533afce865fa325041d74d71`; retained-row mapping SHA-256 `5409e641ad5d9b0159a94fc141899b1345149e5d3220cb734ca7a8da2c6ae470` |

**Accepted decisions.** Rows 602, 607, 672 and 673 are restored as illnesses because fixture eligibility does not apply to illness setting. Rows 603 and 1120–1122 are restored through explicit, season-specific +1-day fixture adjudications; their recorded dates are preserved and this does not create an automatic date-tolerance rule. Row 1971 retains only the other-team exclusion through Abdel's explicit adjudication. Rows 583 and 740–743 are recorded as friendlies, while rows 1182–1183 and 1191 restore the source-reported professional A-team match type and retain their other-team exclusions. Rows 605, 651, 685, 709 and 1161 remain excluded as off-fixture matches, but their misleading exact `URC` Match Type is replaced by `Other`; their explicit Match occasion is preserved. Row 1110 remains included as Training and its inconsistent Match Type is corrected from `URC` to `training`. After replay, the only exact `URC` Match Type values are the four approved +1-day rows 603 and 1120–1122.

**Scope.** The wider set of 84 potentially misleading blue labels is deliberately untouched. The append-only master remains unchanged. `tools/replay.py` now applies guarded `Exclusion Reason` decisions before inclusion selection so an accepted ledger decision can restore a master-excluded row without editing the master or generated CSV by hand. The accepted replay adds exactly source rows 602, 603, 607, 672, 673 and 1120–1122, removes none, and reports zero conflicts.

**Live reconciliation.** The eight restored eligibility decisions were applied sequentially through the installed dynamic correction workflow and each was promoted as an immutable successor. The correction chain ends at release `urc-2024-25-correction-r1122-20260729-a1`, bundle SHA-256 `34fc4dbafb87c2ec0047c6e955ae448b20f0430ded1b0eecaf9187e76d175067`. A final live query verified all eight source rows have active `eligibility = true`, with no missing or mismatched row. The four illness restorations do not change dashboard metrics; the four match restorations update only their affected team and the pooled league result. Match Type clarity changes remain file-backed because Match Type is not a published dashboard input or an allowlisted dynamic-correction field.

---

## 2026-07-26: Dynamic row-correction workflow and additive implementation

| Field | Value |
|---|---|
| Status | Base capability and additive T4 hardening `live-installed-and-verified`; renewed independent `sol_xhigh` T4 acceptance passed with no P0, P1 or P2 blockers; application change merged to `main` at `8646367`; production build and 43 focused contracts passed. No sample correction was retained or promoted. |
| Rule/tooling version | `dynamic_row_correction_2026-07-26_v1` |
| Migration | Installed base: `supabase/migrations/20260726200000_dynamic_row_correction_pipeline.sql`; SHA-256 `07bbd951aedf19705ba8ea99cff30d445c6634ddfad90f84e3b9f2f38218aac5`; registered as `20260726200000` / `dynamic_row_correction_pipeline`. Installed hardening: `supabase/migrations/20260727010000_dynamic_row_correction_pipeline_hardening.sql`; SHA-256 `29dd76bb42ac7bdc10f3a6691bf538a1af4786a15408acc467a4c9beab4cd57b`; registered as `20260727010000` / `dynamic_row_correction_pipeline_hardening`. |
| Installation target | The existing approved hosted Supabase/Postgres target reached through `SUPABASE_DB_URL_POOLER`, parsed from `/Users/abdelbabiker/Desktop/URC-V2-DB/.env.local` without sourcing or printing it |
| Carry-forward | `carries-forward`: the mechanism is season-keyed and has no hard-coded 2024-25 row decisions. Year 2 uses its own season key, source-row binding, evidence and correction set. Row-level decisions never carry forward blindly. |
| Decision provenance | Abdel Babiker, 26 July 2026, implementation handoff for an audited incremental correction capability |
| Documentation | `docs/DYNAMIC_ROW_CORRECTION_WORKFLOW.md` |

**Implemented workflow.** The commands `capture-served-baseline` and `verify-served-baseline` bind the correction-aware approved bundle, its canonical payloads through the unified bundle views, and the served V5 team and league projections. `correction-propose` is read-only and has no reviewer input. It resolves one allowlisted existing row and typed field, checks the expected current effective value, and binds immutable source-row evidence, old and new values, reason, evidence hash, operator, rule version, code and dependency provenance, current and proposed correction-set hashes, predecessor bundle, proposal hash, and the versioned-SQL downstream preview.

After Abdel reviews that proposal, `correction-apply --reviewer 'Abdel Babiker'` replays the row, proposal, correction-set and candidate bindings under optimistic concurrency. It appends the immutable approval, correction set, row correction, run and processing evidence, and stores an immutable payload-bearing draft in one transaction. Approval and draft evidence are separately queryable; neither changes the reporting reader. A distinct `correction-release --preflight` reads that stored draft for review, and a separately reviewed `correction-release --preflight-file ...` promotes its exact payloads.

**Additive storage and reader successor.** Frozen V2 payload and context tables remain untouched. Correction and rollback successors use append-only `reporting.correction_release_context_v1` or `reporting.correction_rollback_context_v1`, `reporting.correction_league_payloads_v1`, and `reporting.correction_team_payloads_v1`. The additive `reporting.dashboard_bundle_context_v1`, `reporting.dashboard_bundle_league_payloads_v1`, and `reporting.dashboard_bundle_team_payloads_v1` views unify those rows with frozen V2 storage. The private `reporting.latest_approved_dashboard_bundle_v4` selector chooses the complete current bundle, and the website reads `reporting.latest_team_dashboard_v5` and `reporting.latest_league_dashboard_v5`. Until a correction or rollback is approved, the V5 path projects the currently served V5 V2 bundle exactly.

**Contact distribution.** `contact_distribution` remains part of the published reader contract. Unaffected teams preserve it byte-for-byte with the rest of their predecessor payload. An eligibility correction recomputes the affected team's contact, non-contact and unknown counts from the effective injury cohort, then pools those recomputed values into the league distribution. Diagnosis, body-location, injury-type and days-lost corrections preserve predecessor contact counts because they do not change contact membership.

**Reader privilege boundary.** The unified context/payload views and internal V4 selector are owner-executed private implementation surfaces with no grant to `web_reader`. The security-definer, security-barrier `latest_team_dashboard_v5` and `latest_league_dashboard_v5` views are the application allowlist. Historical V2, V3 and V4 aggregate-reader grants remain temporarily available for deployment rollback and expose no correction, release, build or audit fields. Retire those older grants through an additive migration only after the V5 deployment and rollback window are verified; their depended-on views remain. The website cannot directly query correction payload storage, bundle context, release/build identities, evidence, or audit fields.

**Safety and analytical boundary.** Metric formulas remain in versioned SQL, never Python or dashboard JSON. `ingestion.source_rows`, curated data, the approved 2024-25 V5 lineage, frozen views, historical migrations, `reporting.league_release_context_v2`, `reporting.league_release_payloads_v2`, and `reporting.team_dashboard_payloads_v2` remain immutable. The design permits one pending correction set per season, exact old-value guards, row and set fingerprints, explicit supersession, and retained immutable predecessors. A one-team correction must reuse the other 15 approved team payloads byte-for-byte and recompute only the affected team candidate plus the pooled league candidate. Rollback re-promotes a retained predecessor as a new immutable event; a wrong decision is corrected through a compensating correction, never deletion.

**No-impact and release-lineage behaviour.** A valid evidence correction can leave every dashboard metric unchanged. That state still appends approval and draft evidence, proves all 16 predecessor team payloads and the league bundle are unchanged, and requires explicit promotion. Promotion creates an audited immutable successor rather than leaving an approved correction outside the served correction lineage.

**Rollback and active-correction guard.** `correction-rollback` creates a new immutable successor in the additive correction payload tables containing the correction release's exact retained predecessor payloads and records reviewer, rationale, evidence and execution provenance. It does not delete, mutate or reapprove the correction or either bundle. The served-correction view follows correction and rollback release lineage. While a correction remains active, the guard blocks both approval of an ordinary V2 release and retirement of the served predecessor; the successor must reconcile that correction or use the explicit append-only rollback.

**Clinical boundary.** Diagnosis and body-location corrections use the same typed, evidence-bound overlay and may map only into the controlled IOC taxonomy. Weak or ambiguous evidence stays `Unknown`; source evidence and original values are retained.

**First-use and scale boundaries.** The correction commands do not rewrite the file-backed 2024-25 master, decision ledger or inclusion CSV. Before the first real correction, record how the accepted database adjudication is reconciled into that source-to-final lineage. The current correction release and rollback contract is intentionally 16-team; a 17-team or larger season requires an additive member-count successor before correction promotion.

**Live installation and V5 invariant.** The base and additive hardening migrations and their checksum-bound registrations were applied on 27 July 2026. The hardening migration was first compiled and exercised in a 463-second rollback-only rehearsal, then applied and registered, then exercised again in installed state in 455 seconds. The installed-state transaction harness verified stale-proposal rejection, wrong registered-migration-SHA rejection, direct-approved-insert rejection, season-scoped candidate isolation, pending and served ordinary-release guards, append-only evidence, concurrent apply rejection, exact immutable drafts, one changed plus 15 reused team payloads, zero changed plus 16 reused payloads, sequential corrections, rollback preserving the earlier correction, correction after rollback, active clinical correction origin, collision-safe automatic recovery and compensating rollback. Every verification write ran under an outer rollback; correction sets, rows, drafts, correction releases, rollback releases, recovery labels and dynamic payload rows all returned to zero.

The served bundle remains release `76ac684a-dc60-4b12-ab78-0a502d284555`, label `urc-2024-25-v5-4ae722941285-a1`, with 16 teams and league payload SHA-256 `2f4bb3cbe77e1ea1608cf8442419c2d6e11333473ce73d10559532061382fa53`. The V5 team projection SHA-256 remains `640f338e52e6f8fc10fdd622a904d09222111b1360353ccc24acd23fcbd8c337`; the V5 league projection SHA-256 remains `f348a9e60020fdd76ebcc8891ba6fd606169fec284d08671211351325752dca9`. A real `web_reader` connection returned 16 team rows and one league row, each team and league contact distribution retained 12 cells, and all four private unified relations rejected access. The live protected-alias scan returned zero hits. The successor closes the earlier independent review's season-isolation, rollback-label collision, active clinical-origin and installed-SHA binding findings without altering V1 definitions. Live rollback-only verification and checksum registration are complete. A renewed fresh-context `sol_xhigh` T4 review accepted the finished implementation with no P0, P1 or P2 blockers.
---

## 2026-07-26: Contact mechanism distribution added to the 2024-25 dashboards

| Field | Value |
|---|---|
| Status | `released`: additive payload section, two tracked live migrations, independent review, and an approved 16-team bundle promotion. No re-clean, no reprocessing, no new adjudication. |
| Rule version | Analysis `v5`, classification `reporting_classification_2026-07-22_v2`, cohort `analysis_window_2024-25_2026-07-25_v1`. Candidate binding moves to `20260726160000`. |
| Carry-forward | `carries-forward`. The distribution is a versioned rule-layer view over `curated.injuries.contact_context`, so a later season inherits it unchanged once that season's candidate chain is built on the same pattern. The pinned 2024-25 acceptance numbers inside the integrity function are season-specific. |
| Decision provenance | Abdel Babiker, 26 July 2026. Unknown-slice retention decided the same day. Historical plan: `docs/archive/CONTACT_RING_RELEASE_PLAN_2026-07-26.md` |
| Reviewed migrations | `20260726160000_contact_distribution_v5.sql` (`aaa92ec6...`); `20260726161000_contact_distribution_reader_v4.sql` (`423bf1c0...`) |
| Code | `tools/sql/refresh_analysis_window_v5_candidate_snapshots.sql` (`8ec0b99d...`), `tools/sql/register_contact_distribution_migrations.sql`, `pipeline/__main__.py`, `lib/reporting.ts`, `lib/reporting-types.ts`, `components/dashboard/team-dashboard.tsx` |
| Runtime records | Both migrations applied and tracked on the approved hosted target. Live release `76ac684a-dc60-4b12-ab78-0a502d284555`, label `urc-2024-25-v5-4ae722941285-a1`, approved 26 July 2026, bundle payload `4ae72294...`, parity export set `5fe9829a...`. Retired predecessor `a5a07fca-1be6-4ead-9a6b-648a3475c205` (`urc-2024-25-v5-45169a66a7da-a1`) is the rollback route. |
| Verification | Preflight reconciliation passed on all four gates. Structural diff of the approved predecessor against the promoted bundle showed exactly one change across all 17 entities: `contact_distribution` added, nothing altered or removed. League counts equal the pooled 16-team raw counts for all 12 cells. Ring confirmed rendering on team and league pages at 1440 and 390 widths, overall and under both setting filters, with the Unknown slice visible. |

**What changes.** The team and league dashboard payloads gain one additive top-level section, `contact_distribution`: recorded and time-loss injury counts by contact mechanism (`contact`, `non_contact`, `unknown`) for each activity setting (`all`, `match`, `training`, `unknown`). No existing published figure changes. `contact_context` was already populated on `curated.injuries` as a frozen pipeline derivation from the inclusion CSV's `Is Contact` column, so this exposes an existing derivation rather than creating a clinical fact.

**Verified league counts, 26 July 2026.** All settings: 943 contact / 565 non-contact / 150 unknown recorded, and 443 / 280 / 62 time-loss. Match: 671 / 153 / 69 recorded. Training: 270 / 406 / 66 recorded. Unknown setting: 2 / 6 / 15 recorded. These are pinned inside `analysis.assert_contact_distribution_v5_integrity()` and the release fails rather than adjusts if they move.

**The `all` row is not match plus training.** 23 league-wide cases carry a genuinely unknown activity setting. `all` is the sum across every setting, so the per-setting rows reconcile to `all` only when the `unknown` setting row is included. The payload therefore emits it and the web type union was widened to carry it, even though the ring's filter never selects it.

**The Unknown mechanism slice is retained, by decision.** Every other front-facing breakdown hides unknown categories through `withoutFrontFacingUnknown`. The contact ring deliberately does not. For a mechanism field the unknown share (9% of recorded cases) is a real coverage statement, and suppressing it would silently inflate the contact and non-contact percentages. The ring's denominator is therefore all cases, not classified cases. `tests/dashboard-visibility.test.mjs` previously asserted the opposite policy and was inverted to match this decision.

**Additive, not a rebuild.** New payload snapshots inherit the approved coverage-corrected V5 payload and merge exactly one key. The migration asserts `dashboard - 'contact_distribution'` is byte-identical to its predecessor for all 16 teams and the league, so no unrelated metric can move. The candidate views are repointed, never edited in place, and the frozen `analysis.*_v1`, v2 and v3 readers are untouched. League rows pool raw counts across the 16 released teams before any derivation.

**Reader versioning.** `reporting.latest_{team,league}_dashboard_v2` enumerate payload keys as an explicit column allowlist, so a new key is invisible to `web_reader` until a new reader projects it. `reporting.latest_{team,league}_dashboard_v4` add the section over the v3 projection and re-join the payload relations to reach it, because v3 does not carry `dashboard_payload`. No release, bundle, or build identifier crosses the boundary.

**Refresh integrity.** The full acceptance suite lives in `analysis.assert_contact_distribution_v5_integrity()` rather than an inline migration block, and both the migration and the candidate-snapshot refresh script call that one definition. A refresh replaces the materialised contents, so migration-time-only assertions would have guaranteed nothing about what is actually promoted. This was raised by independent review and is the reason for the shared function.

**No diff-whitelist entry, deliberately.** The plan called for whitelisting `contact_distribution` in `classify_dashboard_json_diff()`. That premise proved wrong: `release-league` never calls that classifier, because its parity export writes from the promoted bundle and treats any bundle diff as fatal. The classifier is reached only by the per-team `release` command and `diff-dashboard-json`. Widening a frozen gate for paths that do not need it was rejected; if either path later meets the new section, blocking is the correct outcome and belongs in a recorded adjudication. `tests/test_contact_distribution_diff_whitelist.py` pins that absence.

**Deliberately excluded.** Per-setting severity. `team-dashboard.tsx` falls back to summing every `severity_distribution` row to derive recorded cases, so adding match and training rows would multiply-count that figure. It needs a component-side `setting === 'all'` filter and a decision about whether the existing rows keep their implicit overall meaning. Separate plan.
---

## 2026-07-26: Injury Impact quadrants, and the tab folded into Common Injuries

| Field | Value |
|---|---|
| Status | `presentation-only`: a display annotation over released values. No pipeline run, view, cohort, denominator, or published figure changes. |
| Rule version | None. Deliberately not a versioned rule; see carry-forward. |
| Carry-forward | `presentation-only`. Nothing is stored, so a later season inherits the annotation only because the browser recomputes it from that season's released values. If quadrant membership is ever to be quoted as a finding, the threshold must first be promoted to a versioned `analysis.*_vN` view. |
| Decision provenance | Abdel Babiker, 26 July 2026, in-session direction |
| Code | `components/dashboard/charts.tsx` (`ImpactBubbleChart`, `IMPACT_QUADRANTS`), `components/dashboard/team-dashboard.tsx` (`CommonInjuriesTab`) |

**What changes in the UI.** The standalone Injury Impact tab is removed and its bubble chart, with its Diagnosis / Location / Type grouping control, now sits inside the Common Injuries tab, replacing the "How rankings shift across metrics" slope panel. The chart gains a four-quadrant background: red where both axes are above the split, green where both are below, amber for the two mixed corners.

**How the split is computed.** The dividing lines are the **median incidence** and the **median mean severity** of every plottable profile in the currently selected setting and grouping, taken from the released per-profile rows the dashboard already reads. They are **not** the median of the twelve highest-burden profiles the chart actually draws: a median over that truncated slice would label a corner "less frequent" while every point in it is among the club's worst problems. A profile is plottable when incidence and burden are finite and mean severity is positive, matching the chart's existing log-scale filter. Fewer than four plottable profiles in the cohort and the shading does not render, because a median over three points says nothing.

**Why the labels are comparative.** The quadrants read "Longer absences · More frequent" rather than "High severity · High incidence". The split is a within-cohort median, not a clinical or released threshold, so a profile just below a line is lower than its peers, not low. Absolute wording would assert a category the pipeline has never defined.

**Standing limit.** Quadrant membership is a reading aid on this chart and carries no released status. It must not be quoted as a classification of a diagnosis, body location, or injury type, and no export, view, or payload records it. This supersedes the "no quadrants in Phase 1" position in `docs/archive/OVERVIEW_TABS_ADDITIVE_PLAN_2026-07-25.md` § 1.3 on the statistical objection only, by moving the median off the truncated slice; that section's governance point stands and is the reason for this limit.

---

## 2026-07-25: Accepted 2024-25 analysis-window v5 rule

| Field | Value |
|---|---|
| Status | `released`: accepted rule, independent review, five tracked live migrations, corrected build-pinned coverage, 28 passing live contracts, and approved 16-team bundle |
| Rule version | `analysis_window_2024-25_2026-07-25_v1` with `analysis_version` `v5` and classification `reporting_classification_2026-07-22_v2` |
| Carry-forward | `versioned-successor-ready`; after the tracked live migration is applied, the framework carries forward with a newly registered window per season. The 2024-25 dates and pre-URC semantic evidence are season-specific. |
| Decision provenance | Abdel Babiker, 25 July 2026, `ANALYSIS-WINDOW-01` |
| Immutable evidence | `docs/evidence/analysis_window_2024-25_v5.json`, SHA-256 `c9530c949c60ff4abe91753571dfed6dd9d1146f33cc466dfbbc7fdeddb8443d` |
| Reviewed migrations | Base `20260725190000` (`23970db6...`); query optimisation `20260726010000` (`eb4809f6...`); shared cohorts `20260726015000` (`62237630...`); candidate snapshots `20260726020000` (`9deca179...`); coverage correction `20260726120000` (`83d3950b...`) |
| Runtime records | All five migrations tracked. Exposure evidence `4a09c4c9...`, SQL reconciliation `cbcf5c21...`, and corrected candidate performance `6e06490f...` are committed evidence. Live release `a5a07fca-1be6-4ead-9a6b-648a3475c205`, label `urc-2024-25-v5-45169a66a7da-a1`, approved 26 July 2026. |
| Deployment | Release push `2dcbae13...` and final verification push `453f0794...` reached `origin/main`. The repository-linked V2 domain returned `DEPLOYMENT_NOT_FOUND`; the legacy production domain remained on its retained deployment. This is an external GitHub-to-Vercel trigger/configuration blocker, not a database or payload failure. |

**What changes.** The 2024-25 reporting cohort becomes the inclusive period 1 September 2024 through 30 June 2025 for both injuries and exposure. Dated injuries before 1 September are valid cleaned records but outside the v5 cohort. Six undated, season-attributed injuries remain in applicable totals and non-monthly breakdowns, while remaining outside monthly series. The v5 monthly successor must bind to the same v5 cohort identity as the headline and other cohort-derived readers, correcting the frozen lineage monthly reader's former season-bound binding.

**Exposure semantics.** The v5 row-level effective exposure cohort starts from historical eligibility and reasons. It removes `outside_official_analysis_window` only when that is the sole reason preventing inclusion and the row's native reporting period overlaps the v5 window. All other historical exclusions remain effective. Weekly rows retain their recorded start plus six-day period and are never converted to sessions. Only in the newly opened 1 to 19 September pre-URC band, clearly evidenced non-URC match, friendly, or opponent-fixture activity is excluded. Ambiguity is inclusionary. Warm-ups, top-ups, captain's runs, `Game -N` training-cycle labels, and blanks remain unless other evidence is decisive. This rule does not alter existing-window rows or generalise a league-wide URC-opponent rule.

**Lineage boundary.** This is not a re-clean. It does not rebuild or recolour the 3,060-row injury master, alter the decision ledger, regenerate the accepted 2,301-row inclusion CSV, re-clean or re-ingest exposure files, create new curated exposure builds, or run the full pipeline. Historical curated values remain immutable; v5 exposes effective eligibility through additive views. Fixture-derived match hours remain `151 × 2 × 20.0 = 6,040` and pre-season friendlies never enter match hours.

**Live reconciliation.** The tracked live views and build-pinned snapshots return 64,511 included exposure rows, 81,352.919497 exposure hours, 75,312.919497 training hours, 1,658 recorded injuries, 785 time-loss injuries, and 17,573 days lost. They retain 6 undated injuries in applicable totals. The pre-URC semantic rule rejects 815 potential additions carrying 865.830 hours. Dragons is the largest injury-side change, with 27 fewer recorded injuries, 25 fewer time-loss injuries, and 1,599 fewer days lost. All 28 numeric, monthly, exclusion and classification identity contracts passed.

**Coverage payload correction and release.** The first v5 promotion correctly
changed headline metrics and exposure hours but retained v4 values for
`coverage.exposure_rows`, exposed players, exposure periods, distance and
coverage windows. Release `d5b010b0-eb83-4f5c-b619-a791239a2893` was retired,
not deleted. Additive migration `20260726120000` derives those fields once from
the shared effective exposure cohort, patches only `coverage`, proves all
non-coverage jsonb sections unchanged, and fails unless team and league hours
equal the incidence and burden denominators. The corrected approved bundle is
`a5a07fca-1be6-4ead-9a6b-648a3475c205`; its league payload SHA-256 is
`f6661135291033420d74b4b6e3787dda8e3298530c03ccc1e56052b6f74333bd`
and canonical bundle SHA-256 is
`45169a66a7da0aa507ed5521b899a990280d56d4cf90e084b9ace6e5c5835ca2`.

**Audit and rollback.** `tools/generate_analysis_window_v5_evidence.py` generates the committed injury cohort audit from the accepted inclusion CSV plus source-row mapping using deterministic evidence keys, never a player identifier. It produces 208 window-excluded injury rows, including 140 positive-day time-loss rows and 4,920 days lost. The exposure evidence is generated only after a reviewed row-view result is available: raw semantic labels are streamed as JSON to standard input and written only as a controlled evidence class plus deterministic fingerprint. Roll back reporting by re-promoting the retained v4 tuple `v4 / reporting_classification_2026-07-22_v2 / lineage_2024-25_2026-07-24_v1`; retain the additive v5 migration, adjudication, and evidence.

---

## 2026-07-24: 2024-25 lineage restatement released, and Phase 5 cleanup executed

| Field | Value |
|---|---|
| Status | promoted to the live approved bundle after Abdel's recorded yes on the full restated diff summary, 2026-07-24 |
| Rule version | `analysis_version` v4, cohort view `lineage_2024-25_2026-07-24_v1`, classification `reporting_classification_2026-07-22_v2` |
| Carry-forward | `carries-forward` for the lineage cohort and classification views; the restatement itself is season-specific |
| Adjudication reference | `LINEAGE-01`, `docs/evidence/lineage_cohort_2024-25.json` |

**Published figures changed.** The served 2024-25 dashboards are now derived from the human-review lineage (v5 master plus decision ledger) instead of the pre-restatement curated path. League headline, old V3 to new V4: recorded injuries 2,160 to 1,866; time-loss injuries 1,120 to 925; incidence 14.59 to 12.05 per 1,000 hours; burden 370.0 to 292.9 days per 1,000 hours; mean severity 25.4 to 24.3 days; median severity unchanged at 13. Exposure denominators are byte-identical for all 16 teams, so every incidence and burden change comes purely from the injury-side restatement. League recorded injuries equal the lineage cohort count, all 16 per-team counts match `analysis.lineage_injury_cohort_v1` exactly, and no team's count exceeds its count in the authoritative inclusion CSV.

**Released as one league bundle, not 16 per-team releases.** Release `urc-2024-25-v4-6f04bd64d2a6-a2`, release_id `337ec441-7713-4900-9d1d-1afe78a1a2f8`, approved 2026-07-24, `preflight_json_sha256` equal to `bundle_payload_sha256` (`6f04bd64d2a6c33d4c4069c0be33ba13b470341cd0d5e39a22b124c3e9f6f5e0`), so the promoted bundle is byte-identical to the candidate that was reviewed. League payload sha256 `da3f2721...`, `member_input_hash` `b711f7fa...`. The V3 predecessor `urc-2024-25-v3-4fa89e322b57-a1` is retired, not deleted. The reason the restatement is a single bundle release: the per-team `release` command reads the frozen `analysis.*_v1` views, so running it would have written the OLD pre-restatement numbers into new team releases. The website consumes only `reporting.latest_team_dashboard_v2` and `reporting.latest_league_dashboard_v2`, both fed by the bundle, so the bundle release is the correct and sufficient promotion boundary for this lineage.

**Performance-only migration, no rule impact.** `20260724190000_lineage_v4_candidate_fast_path.sql` adds `analysis.league_dashboard_release_candidates_lineage_v4` and `analysis.team_dashboard_release_candidates_lineage_v4` plus a V4 branch in both validation trigger functions, with V4 excluded from their legacy branches. Equivalence argument: migration `20260724181000` defines the V4 branch of the `_v6` candidate chain as a plain projection of `analysis.*_dashboard_payload_lineage_v1` tagged `'v4'`, and every other branch in that `UNION ALL` chain emits a different literal `analysis_version`, so the new views are exactly the rows `_v6` contributes for `analysis_version = 'v4'`. No metric, cohort, classification, or payload rule changed; the frozen `_v1` views and the legacy chain are untouched and non-V4 releases keep validating against `_v6`. The change was necessary because a filter on `analysis_version` does not prune the union branches, so a V4 read planned and evaluated the entire historical candidate stack and overran the target's 2-minute `statement_timeout`.

**Pipeline infrastructure, no rule impact.** `pipeline/sql_exec.mjs` now sets a transaction-local `statement_timeout` (default 900s, `PIPELINE_STATEMENT_TIMEOUT_MS`): the promotion write legitimately needs about five minutes because it re-derives the league payload and all 16 team payloads twice for its inserts and twice more in its triggers, and that re-derivation is the guarantee that the stored snapshot equals its analytical candidate. `pipeline/sql_query.mjs` gained `keepAlive` and a bounded `query_timeout` so a pooler-swallowed cancellation surfaces as an error instead of an unbounded hang. New command `pipeline export-team-dashboards --season <season>` rewrites the 16 committed per-team parity exports from the current approved bundle; it must be run after every accepted `release-league` promotion or those exports go stale. Because it is the only writer of those committed public payloads, it resolves the bundle through `reporting.latest_approved_dashboard_bundle_v2`, the same view the website reads, rather than a looser newest-approved rule, strips the internal `source_files` and `pipeline_evidence` keys, refuses to write bytes carrying a protected club-alias placeholder or a player pseudonym, and refuses to leave a per-team export the approved bundle does not account for. The 16 exports committed before this change were not merely stale but the 2026-07-10 V1 exports in a different shape (no `injury_profiles` or `setting_metrics`, a team exposure-coverage window instead of the registered season window, rounded values); they are now regenerated from the approved bundle. Precisely: regenerated values are runtime-equivalent to the stored bundle, not character-identical to its numeric text, because a Postgres `numeric` such as `2.42234971686951152000` round-trips through an IEEE double and reserializes as `2.4223497168695114`. About 9,500 numbers across the league and team exports differ in that final-digit way. That is far beyond dashboard precision and these files are not application inputs, so the difference is accepted and recorded rather than corrected; re-running the exporter is byte-stable against the committed files.

**Phase 5 cleanup executed.** 93 items, 354.5 MB, deleted per the manifest in `docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md`: superseded review workbooks, 25 pre-step workbook backups and two backup directories, intermediate inclusion CSV and manifest snapshots, the 21 per-step audit and QA evidence files, the bulk mining artifacts, the derived `exposure_master_2024-25.csv` (re-verified derived: its 83,131 rows equal the combined rows of the 16 per-team cleaned exposure CSVs, and `curated.exposure` holds the data live), the 8 superseded step scripts with their tests, and one duplicate bundle snapshot. The frozen 2026-07-23 workbook, the Provenance Addendum, `DEFERRED_MASTER_WORKBOOK_CHANGES_2026-07-23.md`, the Standardization Records, everything under `data/2024-25/`, and the four `tools/` verbs plus the lineage load, verification, and export modules are kept.

**Deletion recorded without mutating the ledger.** The plan proposed marking each affected ledger evidence entry `"deleted_at_phase5": true`. That would change `data/2024-25/decisions/ledger.json`, whose sha256 `b92c35cd...` is pinned in `docs/evidence/lineage_cohort_2024-25.json` (the approved cohort evidence bound into the served release), in `tools/lineage_load.py`, and in the live `lineage.baselines` row, so the approved evidence and the live provenance anchor would have become false about the file on disk. Instead `docs/evidence/phase5_deleted_ledger_evidence_2026-07-24.json` records all 30 deleted hashed references with the sha256 the ledger recorded for each, and `tools/replay.py` `verify_ledger_evidence` skips a reference only when the file is absent AND that exact path and hash are manifested. A file that still exists is byte-verified as before, and an unlisted missing file still fails the replay. The ledger stays byte-identical and keeps every path and hash as its historical record.

The manifest is built by walking all three surfaces on which the ledger pins hashes: `steps[*].evidence`, the `baseline` anchors, and `open_items[*].evidence`. `verify_ledger_evidence` originally walked only the first, and that gap is how the first version of this manifest missed one path (see the two disclosures below). It now walks all three, with `docs/PIPELINE_RULE_CHANGELOG.md` exempt by path because it gains an entry on every accepted rule change and so can never satisfy a pinned byte hash.

**Why 8 of the 9 chain scripts went.** The plan listed 9 superseded step scripts. Eight were deleted; `tools/export_included_injury_dataset.py` stays because `tools/replay.py` imports its serialization functions (the CSV writer and the export contract) and would break without it, so it is live pipeline code rather than a superseded step script. `tests/test_export_included_injury_dataset.py` stays with it.

**Plan acceptance criterion 4 amended (Abdel's decision, 2026-07-25).** No derived value, classification, cohort, denominator, or published figure changes; this records an amendment to a definition of done. The original criterion required that a small edit reach the website preview through one command plus one review. The independent `gpt-5.6-sol` acceptance review returned thumbs down on it, correctly: the routine loop is one command (`tools/replay.py`) plus one review for the data layer, and reaching the website additionally needs the lineage load, a `release-league` preflight, Abdel's recorded yes, promotion, and `export-team-dashboards`.

The criterion was not implementable as written without violating a stronger rule. A genuine single command from edit to website would perform a live database write and a release promotion without stopping, and `AGENTS.md` binds every live write and every promotion to Abdel's explicit approval of the exact hosted target. The criterion predates that boundary being settled; the gates are worth more than the convenience. Amended wording: one command plus one review through the data layer, with the website reached by the separate, separately approved release path. Carry-forward: `carries-forward` as the definition of done for this lineage and later seasons. Recorded in `docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md` criterion 4, which retains the original wording alongside the amendment. The alternative considered and declined was building a development-only local preview command; it remains available if Abdel later wants the literal property.

**Unchanged in v4.** The replay byte-match (`e8da3caf...` inclusion CSV, `9910b585...` source-row mapping), the frozen `_v1` view family, the scientific rules, the two open ledger items (source rows 1735 and 210, still awaiting adjudication), the intentionally unpopulated `reporting.team_metric_aggregates`, the historical July and August exposure exclusions, and the access-control restoration gate, which this work does not touch. The separately accepted v5 effective-cohort rule is recorded above; it does not mutate those historical rows.

---

## 2026-07-24: Release-ceremony simplification for the restated 2024-25 injury lineage

| Field | Value |
|---|---|
| Status | decided by Abdel 2026-07-24 (`docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md`, decisions locked); applies from the plan's Phase 4 restatement onward |
| Carry-forward | `carries-forward` for this lineage; the V1 preflight/whitelist ceremony remains the record for currently served releases until restatement |
| Reason | The dual-write era ended: the master, ledger, and inclusion layers are byte-replayable and independently checked, so the per-release preflight/candidate/checksum-envelope ceremony no longer adds assurance proportionate to its cost for routine updates |

**New path.** One authored decision record, one replay command (`tools/replay.py`), a printed diff summary with anomaly flags (out-of-window dates, negative durations, category drift) that flag but never block, and Abdel's recorded manual review as the gate. Releases regenerate from the v5 baseline plus ledger; superseded releases are retired, never deleted.

**Unchanged.** Scientific rules (IOC buckets, no imputation, preserve source values, pseudonymisation, privacy), the live-write approval boundary for every hosted database action, and the audit contract (every change traceable to source row, rule version, and evidence).

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

**Observed scope and evidence.** The post-removal dataset has 90 rows meeting that definition: 64 source `TRUE`, 9 source `Yes`, and 17 source `Time Loss`. The equivalent pre-removal count was 91. The sole removed case was Scarlets source workbook row 1892 (24/07/2024, `Non-Rugby`, source `Yes`, blank duration and return date; the pseudonymous athlete reference stays in the Git-ignored audit), removed only from the included CSV by `included_injury_nonrugby_gym_removal_2026-07-23_v1`. Evidence is bound to the current manifest's ordered source-row mapping, the 51-column source-facing `injury_master_2024-25.csv`, the focused-cleanup audit that normalized the affirmative values, and the non-rugby/gym removal audit. Across the current included dataset, 90 of 1,013 source-reported Time Loss injuries have missing duration (8.9%). Missingness is uneven: Lions has 15 of 37 (40.5%) and Sharks 37 of 94 (39.4%). Consequently, known-duration burden totals are incomplete lower bounds; complete-case mean severity is incomplete and may be biased by missingness, rather than being assumed to be a lower bound.

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
