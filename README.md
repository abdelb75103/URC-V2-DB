# URC Injury Surveillance Pipeline

This repository turns an approved pseudonymised, standardised team/season intake into reproducible injury-surveillance releases and the read-only URC dashboards.

The current operational path is:

```text
pseudonymised intake + approved profile/manifest
  -> ingestion.source_files / ingestion.source_rows
  -> processing.record_versions + audit.record_events
  -> curated builds, injuries, exposure, fixtures, and denominators
  -> versioned analysis views
  -> immutable reviewed team and league release snapshots
  -> reporting.latest_*_dashboard_v2
  -> server-rendered website
```

Start with [docs/PIPELINE_RUNBOOK.md](docs/PIPELINE_RUNBOOK.md). It is the canonical map of commands, evidence, approval boundaries, and row/metric traceability.

## Repository map

| Path | Purpose |
|---|---|
| `pipeline/` | The only supported data-processing command line. |
| `supabase/migrations/` | Versioned schemas, controlled rules, analysis views, and release gates. Existing migrations are immutable. |
| `docs/PIPELINE_RUNBOOK.md` | Current source-to-output operating path and audit contract. |
| `docs/TEAM_INTAKE_PROFILING_GATE.md` | Required local, read-only gate for every new team/season. |
| `docs/PIPELINE_RULE_CHANGELOG.md` | Accepted rule changes and whether they carry forward. |
| `docs/V2_FOUNDATION.md` | Architecture, governance, and accepted foundation. |
| `docs/archive/` | Completed plans retained for historical context; not operating instructions. |
| `tools/` | Review utilities and explicitly non-production experiments. |
| `tests/` | Pipeline, migration, release, and website contract checks. |
| `app/`, `components/`, `lib/`, `config/` | Read-only Next.js website. |
| `content/reporting/` | Public emergency/parity exports. The website reads approved database views, not these files. |
| `data/`, `output/`, `outputs/` | Git-ignored local inputs, evidence, review artifacts, and generated output. Never treat these directories as source code. |

## Safe local checks

These do not write to the hosted database:

```bash
npm run pipeline:check
npm run typecheck
npm run build
python3 -m unittest discover -s tests -p 'test_*.py'
```

All migrations, ingests, processing, curated builds, adjudications, and releases target the live hosted database and require separate approval for the exact action and target. Do not run a write command merely to test the pipeline.
