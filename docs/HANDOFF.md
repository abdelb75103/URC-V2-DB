# Handoff: what this project is and where truth lives

Written 2026-07-24; operational reader and correction status updated
2026-07-29. Audience: a cold reader who needs to be productive in ten minutes.
`AGENTS.md` is the binding contract; this is the orientation map.

## What this is

A reproducible injury-surveillance pipeline for the United Rugby Championship
(URC), run by UCD. Sixteen clubs supply heterogeneous injury and exposure
exports for season 2024-25. The pipeline standardizes them, applies recorded
human review decisions, and publishes team and league dashboards (incidence,
burden, severity, contact) on a website backed by Supabase Postgres.

## Where truth lives (three layers)

```
per-team supplied standardized CSVs      data/intake/2024-25/<team>/
        |  (documented, not re-executed, for 2024-25:
        |   Standardization Records, data/2024-25/intake/standardization_records/)
        v
MASTER  every source row, append-only    data/2024-25/master/
        3,060 rows, 755 marked excluded  master_2024-25_v5.json (the v5 baseline)
        with reasons; formatted workbook urc_injury_master_workbook_2024-25.xlsx
        is a generated render            (hashes: baseline_record.json)
        |
DECISION LEDGER, ordered and replayable  data/2024-25/decisions/ledger.json
        12 steps, every row-level edit,  (8 master exclusions restored and
        inference, and adjudication      4 inclusion removals: 751 excluded)
        |
INCLUSION  what analysis consumes        data/2024-25/inclusion/
        2,309 rows x 28 columns          urc_injury_included_dataset_2024-25.csv
```

Files are the intake, the database is the truth, rendered artifacts are
exports. The master and inclusion layers
visibly disagree on inferred cells by design: source preserved, inference
labelled, both recorded in the ledger.

## The four tools

- `python3 tools/render.py {extract|render|compare|mark-excluded}`: master
  data table to formatted workbook and back; cell-for-cell compare.
- `python3 tools/replay.py [--write-methodology]`: baseline plus ledger to
  the inclusion CSV. Must reproduce SHA-256
  `7203b83954becb1c2232ff7e7efa73eac1da41d7533afce865fa325041d74d71`
  byte-for-byte; any conflict stops the line for review.
- `python3 tools/intake.py --team <key> --season <s> --file <csv>`: new
  season intake, append-only; `--validate-against-baseline` reconciles a
  team's file against the v5 baseline without touching the master (it
  writes only a validation report).
- `python3 tools/checks.py --season <s>`: standing comparability suite;
  structural problems FAIL, observations FLAG.

Tests: `python3 -m unittest discover -s tests -p 'test_*.py'`.

## The change loop

Author one decision record (row, field, old to new, reason) in the ledger,
run replay, read the printed diff summary and flags, stop for Abdel's manual
review. That review is the gate. Never hand-edit the workbook, the inclusion
CSV, or any generated artifact.

That one command plus one review covers the data layer, and stops there by
design. Reaching the website is a separate, separately approved path: lineage
load, `release-league` preflight, Abdel's recorded yes, promotion, then
`export-team-dashboards`. Every live database write and every promotion needs
his approval of the exact hosted target, so nothing crosses that line on one
command (plan acceptance criterion 4, as amended 2026-07-25).

## The story of the data, generated

`docs/METHODOLOGY.md` is generated from the ledger by
`tools/replay.py --write-methodology` and tells the complete source to master
to inclusion story. `docs/PIPELINE_RULE_CHANGELOG.md` records every accepted
rule change with carry-forward status. Open items ride in the ledger's
`open_items` (currently source rows 1735 and 210).

## The database and website

Supabase Postgres serves the approved 2024-25 release through
`reporting.latest_team_dashboard_v5` / `latest_league_dashboard_v5`; the
website is read-only and fails closed. The current bundle is
`urc-2024-25-correction-r1122-20260729-a1`, bundle SHA-256
`34fc4dbafb87c2ec0047c6e955ae448b20f0430ded1b0eecaf9187e76d175067`.
Frozen V2 payload storage remains intact;
the V5 readers can select either that approved predecessor or an append-only
correction/rollback successor through the unified bundle seam. The dynamic
row-correction operator path is `docs/DYNAMIC_ROW_CORRECTION_WORKFLOW.md`.
Its first real use is complete: the 29 July fixture and illness decisions are
recorded in the file-backed ledger, and the eight resulting eligibility
restorations are active in the live correction chain.
The Phase 5 deletion cleanup is done too, so
`docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md` is complete and is now the plan
of record rather than a task list. Released figures and the reasons behind
the release path are in `docs/PIPELINE_RULE_CHANGELOG.md`. After any
accepted `release-league` promotion, run
`python3 -m pipeline export-team-dashboards --season <season>` or the 16
committed per-team parity exports under `content/reporting/` go stale. Every
live database write needs the exact hosted target approved; see `AGENTS.md`.

## Privacy in one paragraph

Player data is pseudonymised before it reaches this repo; all of `data/` and
`outputs/` are Git-ignored. The club-alias codebook is protected: the
single-letter club placeholder aliases never enter Git, the DB, or exports
(exact strings and scope in `AGENTS.md`); the alias map lives only in
Git-ignored `data/intake/team_alias_map.json`. Team pages are temporarily
passwordless for Abdel's private review only; the password boundary must be
restored before any sharing or cutover (executable gate in `AGENTS.md`).

## Year 2 in one paragraph

Versioned rules carry forward; row adjudications never do. A new team file
enters through `tools/intake.py` (append-only into the new season's master),
gets its own Standardization Record, its own season-scoped ledger, and the
same checks suite. The 2024-25 lineage stays frozen as the comparison anchor.
