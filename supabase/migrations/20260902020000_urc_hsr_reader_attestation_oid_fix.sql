-- Bind attestation privilege targets at migration time so the web reader
-- never resolves private analysis names through its restricted schema access.

create or replace view reporting.approved_dashboard_reader_target_v8
with (security_invoker = false, security_barrier = true) as
select target.target_attested
  and 'reporting.latest_team_dashboard_v8'::regclass is not null
  and 'reporting.latest_league_dashboard_v8'::regclass is not null
  and (select count(*) from analysis.hsr_team_season_metadata_v1) = 32
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_team_season_metadata_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_ingestion_batches_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_source_observation_events_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_active_curated_exposure_rows_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_active_source_observations_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_dashboard_exposure_rows_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_dashboard_monthly_actual_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_dashboard_monthly_display_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_dashboard_team_display_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_dashboard_league_monthly_display_v1'::regclass, 'select'
  )
  and not has_table_privilege(
    'web_reader', 'analysis.hsr_dashboard_league_display_v1'::regclass, 'select'
  )
  and not has_function_privilege(
    'web_reader', 'analysis.reject_hsr_reporting_mutation_v1()'::regprocedure, 'execute'
  )
  and has_table_privilege(
    'web_reader', 'reporting.latest_team_dashboard_v8'::regclass, 'select'
  )
  and has_table_privilege(
    'web_reader', 'reporting.latest_league_dashboard_v8'::regclass, 'select'
  )
  as target_attested
from reporting.approved_dashboard_reader_target_v7 target;
