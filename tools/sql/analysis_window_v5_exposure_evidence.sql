-- Safe, build-pinned input for the committed V5 exposure cohort evidence.
-- Pipe stdout directly to tools/generate_analysis_window_v5_evidence.py.
select
  stable_source_row_id::text,
  curated_build_id::text,
  approved_member_build,
  team,
  reporting_grain,
  period_start::text,
  period_end::text,
  historical_eligibility_status,
  historical_exclusion_reasons,
  effective_v5_eligibility_status,
  effective_v5_exclusion_reasons,
  outside_official_analysis_window_removed,
  pre_urc_match_rule_rejected,
  pre_urc_match_evidence_class,
  pre_urc_match_evidence_value,
  exposure_hours::text,
  rule_basis_code
from analysis.analysis_window_effective_exposure_cohort_v5
where season = '2024-25'
  and approved_member_build
  and (
    outside_official_analysis_window_removed
    or pre_urc_match_rule_rejected
  )
order by period_start, team, stable_source_row_id;
