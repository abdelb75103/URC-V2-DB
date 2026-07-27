# Handoff: what this project is and where truth lives

Written 2026-07-24; operational reader and correction status updated
2026-07-27. Audience: a cold reader who needs to be productive in ten minutes.
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
        10 steps, every row-level edit,  (4 inclusion-stage row removals live
        inference, and adjudication      here, giving 759 excluded overall)
        |
INCLUSION  what analysis consumes        data/2024-25/inclusion/
        2,301 rows x 28 columns          urc_injury_included_dataset_2024-25.csv
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
  `e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb`
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
`urc-2024-25-v5-4ae722941285-a1`. Frozen V2 payload storage remains intact;
the V5 readers can select either that approved predecessor or an append-only
correction/rollback successor through the unified bundle seam. The dynamic
row-correction operator path is `docs/DYNAMIC_ROW_CORRECTION_WORKFLOW.md`.
No real correction is active, and its first use remains gated by a recorded
reconciliation rule for the master, decision ledger and inclusion CSV.
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
