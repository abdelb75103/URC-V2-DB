-- Phase 1.1: run provenance. code_version and dependency_lock_hash already
-- exist on audit.pipeline_runs (added by the initial spine migration,
-- unfilled for all 61 historical runs); this adds the missing operator
-- column so every future run can also record who executed it.

alter table audit.pipeline_runs add column operator text;
