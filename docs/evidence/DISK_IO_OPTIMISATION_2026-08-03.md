# Disk IO optimisation decision, 3 August 2026

## Decision

Use no-cost demand reduction. Cache approved dashboard page payloads for five minutes, batch future same-team row corrections into one derivation and release, retain all audit/source history, and add no speculative indexes to existing large relations.

## Evidence reviewed

- The Supabase project is on Free/Nano. Disk IO was healthy during inspection, but the prior daily graph reached 46%. At 16:02:44 UTC the database was 568,519,827 bytes, above the 500 MB Free quota.
- The reproducible SQL snapshot reported 99.9841% database cache hits, 97.9967% table cache hits, 99.9701% index cache hits, and zero temporary files or bytes.
- The database performance advisor reported no errors or warnings. Its informational foreign-key suggestions did not demonstrate a slow production query.
- The snapshot contained 4,899 league-page and 1,476 team-page payload-query calls in `pg_stat_statements`. Those statements recorded 4,352,807 shared-block hits, 55 shared-block reads and zero temporary blocks in total. PostgreSQL returned `null` for the database statistics-reset timestamp, so these counts must be treated as an unbounded point-in-time accumulation rather than a dated interval.
- Dynamic correction previews and applies took tens of seconds because they recompute an affected team and the pooled league. Eight sequential corrections therefore repeated the same expensive release work eight times.
- The largest relations are immutable source, processing, curated exposure, effective snapshot and audit history. They are required lineage, not disposable cache data.

The association between the high daily IO period and release/correction activity is an inference from timestamps and workload shape because the Free plan does not retain sufficient hourly history for a definitive attribution.

The exact read-only diagnostic is `tools/sql/diagnose_disk_io_budget.sql`, SHA-256 `3e6f505a7921521108e1128df6aa928731111b34439075cd238a291fbd8e5928`. It was run inside a read-only transaction against project `eukkvswaxweenovqqgzr` on 3 August 2026. The command output is retained in the Codex task record; it contains aggregate database statistics only and no source-row or player data.

## Implemented controls

1. `lib/reporting.ts` caches only approved V5 page payloads for 300 seconds in the warm server process. Every request first reads a SHA-256 release token through the least-privilege reader. Promotion or rollback changes the token immediately, database errors still fail closed, routes remain dynamic, and access decisions stay outside the cache.
2. The live-installed chain beginning with `20260803153728_dynamic_row_correction_batch_v3.sql` adds an append-only same-team batch overlay. One batch derives one affected-team payload and one pooled league payload while reusing the other 15 team payloads exactly. The final operator entry points are preview V5, apply V8 and promotion V8.
3. Existing audit, source, curated and snapshot rows are retained. No cleanup or deletion is part of this optimisation.
4. No new index is added to an existing relation without a measured query plan showing that it is needed. Primary-key and uniqueness indexes on the new small batch-control tables are required for integrity and exact lookup.

The six migration files in the batch chain were installed and registered by exact SHA-256 on the approved project. A live rollback-only harness previewed, applied and promoted a two-item batch, verified one affected team plus 15 byte-identical reused teams, restored the exact predecessor release, and retained zero test rows. The final read-only verification query is `tools/sql/verify_dynamic_row_correction_batch_v8.sql`. It confirmed zero pending correction sets, 16 team reader rows, one league reader row, the intended least-privilege boundary, and the unchanged approved bundle `urc-2024-25-correction-r1122-20260729-a1`, SHA-256 `34fc4dbafb87c2ec0047c6e955ae448b20f0430ded1b0eecaf9187e76d175067`.

## Recheck trigger

Revisit indexing only if a production query appears in the slow-query evidence with a repeatable plan showing a large avoidable scan, or if cache hit ratios, IO waits or temporary IO deteriorate. Revisit the five-minute cache window if the approved release propagation delay becomes operationally unacceptable.
