select
  current_database() as database_name,
  current_user as database_role,
  approved.release_id,
  release.release_label,
  context.classification_view_version,
  (select (item ->> 'value')::bigint
   from jsonb_array_elements(payload.dashboard_payload -> 'headline') item
   where item ->> 'key' = 'recorded_injuries') as recorded_injuries,
  (select (item ->> 'value')::bigint
   from jsonb_array_elements(payload.dashboard_payload -> 'headline') item
   where item ->> 'key' = 'time_loss_injuries') as time_loss_injuries,
  (select (item ->> 'numerator')::numeric
   from jsonb_array_elements(payload.dashboard_payload -> 'headline') item
   where item ->> 'key' = 'severity_mean_days') as days_lost,
  exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260827170000'
  ) as setting_profile_successor_registered,
  exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260827171000'
  ) as assertion_lifecycle_registered
from reporting.latest_approved_dashboard_bundle_v4 approved
join reporting.aggregate_releases release on release.id = approved.release_id
join reporting.league_release_context_v2 context on context.release_id = approved.release_id
join reporting.dashboard_bundle_league_payloads_v1 payload
  on payload.release_id = approved.release_id
where approved.season = '2024-25';
