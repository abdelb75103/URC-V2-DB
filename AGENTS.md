# URC injury surveillance pipeline

We're using this as an internal tool. You're probably used to writing enterprise code - code that tries to handle every possible edge case and has fallbacks for everything. That's not how we do things around here: our number one rule is to keep things simple. We handle ONLY the most important cases.

Maintain season parity: render each season in its own tab through shared components, with the same tables, metrics, and visuals; global UI changes apply to every season.

## Dashboard

- Visible dashboard component headings and metric labels capitalise the first letter of every word.

## Reading

- For pipeline, intake, release, or rule work, read `docs/PIPELINE_RUNBOOK.md`, `docs/TEAM_INTAKE_PROFILING_GATE.md`, and `docs/PIPELINE_RULE_CHANGELOG.md`.
- For 2024-25 human review, use only `data/2024-25/review/urc_injury_master_review_2024-25.xlsx` and read `docs/REVIEW_WORKBOOK_2024-25.md`. Workbooks under `data/2024-25/archive/review-workbooks/` are historical and must not be used for current review.
- For any sharing, cutover, or access-control change, read `docs/ACCESS_RESTORATION_GATE.md`.

## Integrity and privacy

- Simplicity preserves scientific validity, privacy, auditability, and data integrity.
- Ingest only approved pseudonymised inputs. The legacy archive is reference-only.
- Keep direct identifiers out of Git, logs, screenshots, fixtures, URLs, and reports; keep re-identification codebooks outside this repository and connected systems.
- Master source rows are append-only; record row-level judgements in the decision ledger. Generated workbooks, inclusion data, and methodology are regenerated, never hand-edited.
- Rules that change derived values, classification, cohorts, denominators, or published figures are versioned through migrations/views and recorded in the rule changelog.

## Production and release

- The web app is read-only and queries approved reporting views server-side through least-privilege access. Never connect the browser directly to Supabase or run pipeline mutations from preview or deployment code.
- Before every query, migration, or write, prove the exact approved live Supabase/Postgres target. A profile or release approval never authorises a separate database action.
- Before sharing a V2 URL with teams or the public, complete the access-restoration gate; legacy passwords are public.
- Do not access or manage Vercel through the CLI, browser automation, plugins, connectors, or APIs for this project.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
