# Exposure Cleaning Protocol

Status: companion for the frozen shared/core V1 exposure rules, 10 July 2026. Accepted team-specific rules and analysis-window handling remain versioned in the pipeline and audit evidence.

## Core Rule

Retain every source row in staging. Cleaning sets `cleaning_action`, `scope_status`, cleaned values, and exclusion reasons; it does not delete source rows.

## Scope

Exclude a row from the primary exposure denominator only when an explicit source field states the exposure is outside the URC squad cohort, including academy, international/national-team, rehab, RTP/return-to-play, or another named non-cohort context.

If competition/session/context fields are blank, missing, or ambiguous, retain the row as `scope_unknown_included` and report the missing-context count.

## Exposure Grain

- Leinster, Munster, Connacht, and Ulster are the four known weekly exposure reporters. This is retained operational evidence, not permission to infer grain from a team name: reconfirm it from each current file/profile and record the evidence.
- The operator must classify each intake explicitly as `weekly` or `session` with the required `--reporting-grain` argument to `prepare-exposure`, `clean-exposure`, and `process-exposure`.
- Never infer exposure grain from a team name, protected team alias, file path, or prior-team default.
- `prepare-exposure` records the declared grain in every prepared row, the QC file, and the intake manifest. `clean-exposure` verifies that declaration, applies the selected rule set to every row, and records the grain in the cleaned output and cleaning evidence. `process-exposure` refuses a cleaned file whose row grain does not exactly match the explicit argument and records the selected grain in the audit run parameters.
- For weekly exposure, treat the source date as `week_start_date`. For session exposure, treat it as `session_date`.
- Do not apply per-session duration/distance limits to weekly reporters.

## Match and Training Denominators

- Approved 2024-25 fixture source (registered intake copies):
  - `data/intake/2024-25/fixtures/urc_fixtures_2024_25.downloaded.csv`, SHA-256 `f8be83637d1b065c0876b0efbba2746f31d7a1c94343b34f990beb79196548f2` (as downloaded from the original source, `Injury & Exposure Data Master Sheet - Analysis - Fixtures.csv`).
  - `data/intake/2024-25/fixtures/urc_fixtures_2024_25.corrected.csv`, SHA-256 `9608ff7e932cf76743eeb6de7d3bce6f5746ab1dfa4cec80a01f001ec2e9c39c` (corrected working copy used by the pipeline).
- Preserve knockout-stage `round` as blank when the source leaves it blank; do not fabricate QF/SF/final round labels.
- Calculate fixture match exposure as 20 player-hours per team per match.
- Calculate training exposure for every team as `total_hours - match_hours`.
- Record the total-hours source, fixture source checksum, corrected fixture file checksum, and team-level match/training output checksum in QC.

## Hard Exclusions

Global exclusions:

- Exact duplicate copy after the first retained row.
- Missing player label, usable date, minutes, or distance.
- Negative minutes or distance.
- Minutes = 0 and distance = 0.
- Explicit out-of-scope context.

Weekly-team exclusions:

- Minutes < 5.
- Minutes > 1,100.
- Distance > 40,000 m.

Per-session exclusions:

- Minutes < 5.
- Distance < 200 m.
- Minutes > 220.
- Distance > 20,000 m.
- Distance/minute > 1,000 m/min.

## Low-Coverage Fields

Do not drop low-coverage columns from staging. Record coverage and exclude low-coverage fields from headline metrics unless the analysis plan approves them.
