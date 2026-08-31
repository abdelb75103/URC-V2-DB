-- Permit the exact Welsh fixture cohort successor on the already reviewed
-- 31 August decision date while retaining every historical date contract.

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_decision_recorded_at_check,
  add constraint league_release_context_v2_decision_recorded_at_check check (
    (analysis_version = 'v2' and decision_recorded_at = date '2026-07-14') or
    (analysis_version = 'v3' and decision_recorded_at = date '2026-07-19') or
    (analysis_version = 'v4' and decision_recorded_at = date '2026-07-24') or
    (analysis_version = 'v5' and cohort_view_version =
      'analysis_window_2024-25_2026-07-25_v1'
      and decision_recorded_at = date '2026-07-25') or
    (analysis_version = 'v5' and cohort_view_version =
      'analysis_window_2024-25_2026-08-30_v2'
      and decision_recorded_at = date '2026-08-30') or
    (analysis_version = 'v6' and classification_view_version =
      'reporting_classification_2026-07-22_v2'
      and cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
      and decision_recorded_at = date '2026-08-15') or
    (analysis_version = 'v6' and classification_view_version =
      'reporting_classification_2025-26_2026-08-31_v3'
      and cohort_view_version = 'injury_lineage_2025-26_2026-08-30_v2'
      and decision_recorded_at = date '2026-08-31') or
    (analysis_version = 'v6' and classification_view_version =
      'reporting_classification_2025-26_2026-08-31_v3'
      and cohort_view_version = 'injury_lineage_2025-26_2026-08-31_v3'
      and decision_recorded_at = date '2026-08-31')
  );

do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
        'reporting.league_release_context_v2'::regclass
      and constraint_row.conname =
        'league_release_context_v2_decision_recorded_at_check'
      and pg_get_constraintdef(constraint_row.oid) like
        '%injury_lineage_2025-26_2026-08-31_v3%'
      and pg_get_constraintdef(constraint_row.oid) like '%2026-08-31%'
  ) then
    raise exception 'Welsh fixture release context date contract is absent';
  end if;
end;
$$;
