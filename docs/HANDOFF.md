# Handoff: what this project is and where truth lives

Written 2026-07-24. Audience: a cold reader who needs to be productive in ten
minutes. `AGENTS.md` is the binding contract; this is the orientation map.

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
        10 steps, every row-level edit,  (4 inclusion-stage row removals live
        inference, and adjudication      here, giving 759 excluded overall)
        |
INCLUSION  what analysis consumes        data/2024-25/inclusion/
        2,301 rows x 28 columns          urc_injury_included_dataset_2024-25.csv
```

Files are the intake, the database is the truth (after the pending
restatement), rendered artifacts are exports. The master and inclusion layers
visibly disagree on inferred cells by design: source preserved, inference
labelled, both recorded in the ledger.

## The four tools

- `python3 tools/render.py {extract|render|compare|mark-excluded}`: master
  data table to formatted workbook and back; cell-for-cell compare.
- `python3 tools/replay.py [--write-methodology]`: baseline plus ledger to
  the inclusion CSV. Must reproduce SHA-256
  `e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb`
  byte-for-byte; any conflict stops the line for review.
- `python3 tools/intake.py --team <key> --season <s> --file <csv>`: new
  season intake, append-only; `--validate-against-baseline` reconciles a
  team's file against the v5 baseline without writing.
- `python3 tools/checks.py --season <s>`: standing comparability suite;
  structural problems FAIL, observations FLAG.

Tests: `python3 -m unittest discover -s tests -p 'test_*.py'`.

## The change loop

Author one decision record (row, field, old to new, reason) in the ledger,
run replay, read the printed diff summary and flags, stop for Abdel's manual
review. That review is the gate. Never hand-edit the workbook, the inclusion
CSV, or any generated artifact.

## The story of the data, generated

`docs/METHODOLOGY.md` is generated from the ledger by
`tools/replay.py --write-methodology` and tells the complete source to master
to inclusion story. `docs/PIPELINE_RULE_CHANGELOG.md` records every accepted
rule change with carry-forward status. Open items ride in the ledger's
`open_items` (currently source rows 1735 and 210).

## The database and website

Supabase Postgres serves the currently approved 2024-25 releases through
`reporting.latest_team_dashboard_v2` / `latest_league_dashboard_v2`; the
website is read-only and fails closed. The restatement of the DB from the
v5 baseline plus ledger, and the deletion cleanup of superseded local
artifacts, are gated phases of `docs/CLEANUP_RESTRUCTURE_PLAN_2026-07-24.md`
awaiting Abdel's explicit go (Phases 4 and 5). Every live database write
needs the exact hosted target approved; see `AGENTS.md`.

## Privacy in one paragraph

Player data is pseudonymised before it reaches this repo; all of `data/` and
`outputs/` are Git-ignored. The club-alias codebook is protected: alias
strings (`Team A` through `Team Z`) never enter Git, the DB, or exports; the
alias map lives only in Git-ignored `data/intake/team_alias_map.json` and
encrypted UCD storage. Team pages are temporarily passwordless for Abdel's
private review only; the password boundary must be restored before any
sharing or cutover (executable gate in `AGENTS.md`).

## Year 2 in one paragraph

Versioned rules carry forward; row adjudications never do. A new team file
enters through `tools/intake.py` (append-only into the new season's master),
gets its own Standardization Record, its own season-scoped ledger, and the
same checks suite. The 2024-25 lineage stays frozen as the comparison anchor.
