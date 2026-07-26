# 2024-25 analysis window: before and after

Date: 25 July 2026  
Status: live v5 migrations applied and reconciled; promotion pending
Scope: URC 2024-25 injury and exposure reporting

## Decision

The reporting cohort will use one inclusive window for injuries and exposure:

**1 September 2024 through 30 June 2025**

This is a versioned reporting-window change. It does not re-clean injury or
exposure data. The exact release tuple is:

`v5 / reporting_classification_2026-07-22_v2 / analysis_window_2024-25_2026-07-25_v1`

## Headline comparison

| Metric | Current v4 | Approved v5 target | Change |
|---|---:|---:|---:|
| Injury reporting window | 1 Jul 2024 to 30 Jun 2025 | 1 Sep 2024 to 30 Jun 2025 | Removes July and August injuries |
| Exposure effective window | Existing cleaner and v4 cohort limits | 1 Sep 2024 to 30 Jun 2025 | Adds eligible September and late-June exposure |
| Included exposure rows | 60,389 | 64,511 | +4,122 |
| Exposure hours | 76,784.9492188 | 81,352.9194970 | +4,567.9702782 |
| Match hours | 6,040.0000000 | 6,040.0000000 | 0 |
| Training hours | 70,744.9492188 | 75,312.9194970 | +4,567.9702782 |
| Recorded injuries | 1,866 | 1,658 | -208 |
| Time-loss injuries | 925 | 785 | -140 |
| Days lost | 22,493 | 17,573 | -4,920 |
| Time-loss incidence per 1,000 h | 12.0466 | 9.6493 | -2.3973 |
| Burden per 1,000 h | 292.9350 | 216.0095 | -76.9256 |
| Undated season-attributed injuries in applicable totals | 6 | 6 | 0 |
| Injury master rows | 3,060 | 3,060 | 0 |
| Injury inclusion CSV rows | 2,301 | 2,301 | 0 |
| New exposure builds required | Not applicable | 0 | No re-clean or rebuild |
| Weekly-reporter rows moved | 0 | 0 | Connacht, Leinster, Munster and Ulster unchanged |

Dashboard display values should use the existing rounding convention. Do not sum rounded team values to recreate league totals.

## What changes

### Injuries

- Dated injuries before 1 September 2024 no longer count in the v5 analysis cohort.
- The narrower injury window removes 208 recorded injuries, 140 time-loss injuries and 4,920 days lost.
- Dragons has the largest change: 27 recorded injuries, 25 time-loss injuries and 1,599 days lost leave the analysis cohort.
- Six undated season-attributed injuries remain in totals and non-monthly breakdowns. They remain outside monthly charts.
- The v5 monthly successor must bind to `analysis_window_2024-25_2026-07-25_v1`, not the frozen monthly view's former season-bound identity. Monthly time-loss totals must reconcile to dated v5 time-loss totals.

### Exposure

- Existing curated rows stay unchanged.
- A new v5 effective cohort view re-admits rows whose only historical exclusion was the old analysis window and whose period overlaps the new window.
- Existing rehab, return-to-play, other-team, international, academy, validity and quality exclusions remain in force.
- From 1 through 19 September 2024, clearly labelled matches, friendlies, opponent fixtures and semantic equivalents are excluded because no URC fixture occurred before 20 September.
- Ambiguous labels remain included.
- Match hours remain fixture-derived at 20 player-hours per team participation.

## Pre-URC exposure exclusions

The final semantic adjudication removes these rows from the potential additions:

| Team | Rejected rows | Rejected hours |
|---|---:|---:|
| Cardiff | 164 | 180.391667 |
| Dragons | 348 | 296.138333 |
| Ospreys | 32 | 23.623333 |
| Scarlets | 169 | 183.943333 |
| Sharks | 46 | 106.937222 |
| Zebre | 56 | 74.796111 |
| **League** | **815** | **865.830000** |

These are definite non-URC match or friendly exposures in the newly opened pre-URC band. The audit evidence must retain the exact source row IDs and label-to-decision mapping.

## What does not change

- The authoritative injury master is not rebuilt or recoloured.
- The injury decision ledger is not changed.
- The injury inclusion CSV is not regenerated and retains its accepted 2,301 rows.
- Exposure files are not re-cleaned or re-ingested.
- No new curated exposure builds are created.
- Existing historical eligibility values remain intact.
- Match hours remain 6,040.
- The four weekly reporters retain their native weekly grain and move zero rows.
- The rule is not generalised to exclude match-labelled sessions league-wide across the full season.

## Why excluded injuries are not red in the master

Red rows in the authoritative master represent data-cleaning or human-review exclusions. A pre-September injury is still a valid injury record. It is outside one reporting cohort, not invalid data.

The v5 process will instead create a separate cohort audit CSV or workbook. It can show the analysis-window exclusions in red without changing the meaning or replay guarantee of the master.

## Provenance and implementation record

The target is projected from read-only database queries and local source reconciliation completed on 25 July 2026. After the v5 release, update this section rather than creating a competing report.

| Record | Value |
|---|---|
| Current release tuple | `v4 / reporting_classification_2026-07-22_v2 / lineage_2024-25_2026-07-24_v1` |
| Target analysis version | `v5` |
| Target classification version | `reporting_classification_2026-07-22_v2` |
| Proposed cohort version | `analysis_window_2024-25_2026-07-25_v1` |
| Base migration | `supabase/migrations/20260725190000_analysis_window_reporting_v5.sql`, SHA-256 `23970db6b4bc38aa91f2ca0ecf41203603c6361dc1c0fc4235a55a5f2dfcccde` |
| Query optimisation migration | `supabase/migrations/20260726010000_analysis_window_v5_candidate_query_optimization.sql`, SHA-256 `eb4809f61912312375757eb545e5c237de12bbcd9fcab2892c59c9389e796ff4` |
| Shared-cohort snapshot migration | `supabase/migrations/20260726015000_analysis_window_v5_shared_cohort_snapshots.sql`, SHA-256 `622376306cda12840a684ad110b9ed21f52ec25448ef05d67f19f479a13799c0` |
| Candidate snapshot migration | `supabase/migrations/20260726020000_analysis_window_v5_release_candidate_snapshots.sql`, SHA-256 `9deca17947a98d4667302793ad0b2326e1188964b113b1c975eff0ce20b357d5` |
| Cohort adjudication reference | `ANALYSIS-WINDOW-01` |
| Immutable evidence manifest | `docs/evidence/analysis_window_2024-25_v5.json`, SHA-256 `c9530c949c60ff4abe91753571dfed6dd9d1146f33cc466dfbbc7fdeddb8443d` |
| Injury cohort audit | `docs/evidence/analysis_window_2024-25_v5_injury_cohort_audit.csv`, SHA-256 `8e76205760df2666130abec5d942a4699fc301b9fb410cb1803850a4f4edd3e3`; 208 rows, 140 positive-day time-loss rows, 4,920 days lost |
| Exposure cohort evidence | `docs/evidence/analysis_window_2024-25_v5_exposure_cohort_evidence.csv`, SHA-256 `4a09c4c9140ad54f95f5339113bd4dda735719cca4641329f09a10e1c14c2978`; 4,937 changed rows, including 815 rejected rows and 865.830 hours |
| SQL reconciliation | `docs/evidence/analysis_window_2024-25_v5_sql_reconciliation.json`, SHA-256 `cbcf5c21d6dfc437a42cfd4eb975c03fff213baa24380344e91c71817c053efb`; 28 of 28 contracts passed |
| Candidate performance | `docs/evidence/analysis_window_2024-25_v5_candidate_performance.json`, SHA-256 `0c531e9a98253d518a02d3cb05a92701d757e8cd588eb92c161338226fc6ee41`; league 9.231 ms, 16 teams 32.624 ms |
| V5 bundle release ID | Pending |
| V5 generated timestamp | Pending |
| Final live reconciliation | Exact targets confirmed: 64,511 rows; 81,352.919497 hours; 6,040 match hours; 75,312.919497 training hours; 1,658 recorded injuries; 785 time-loss injuries; 17,573 days lost; 6 undated injuries; 0 weekly-row moves |
| Deployed verification | Pending GitHub-triggered deployment and route verification |

## Post-release confirmation checklist

- Replace projected figures with exact live v5 values.
- Record the migration path and hash.
- Record the exposure cohort evidence hash after it is generated directly from the reviewed v5 row view.
- Record the v5 bundle release ID.
- Confirm all 16 team payloads reconcile with the league bundle.
- Confirm the website displays the v5 cohort and refreshed values.
- Confirm the v4 tuple remains available for rollback.
