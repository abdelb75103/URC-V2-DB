with dashboards as materialized (
  select
    'team'::text as scope,
    team_key,
    season,
    headline,
    diagnosis_families,
    illness_profiles,
    illness_summary
  from reporting.latest_team_dashboard_v7
  where team_key = 'benetton'
    and season in ('2024-25', '2025-26')
  union all
  select
    'league',
    null,
    season,
    headline,
    diagnosis_families,
    illness_profiles,
    illness_summary
  from reporting.latest_league_dashboard_v7
  where season in ('2024-25', '2025-26')
)
select jsonb_build_object(
  'rows', count(*),
  'scopes', jsonb_object_agg(
    scope || ':' || season,
    jsonb_build_object(
      'recorded_injuries', (
        select item
        from jsonb_array_elements(headline) item
        where item ->> 'key' = 'recorded_injuries'
      ),
      'diagnosis_family_count', jsonb_array_length(diagnosis_families),
      'illness_profile_count', jsonb_array_length(illness_profiles),
      'illness_summary', illness_summary,
      'internal_unknown_illness_profiles', (
        select count(*)
        from jsonb_array_elements(illness_profiles) item
        where lower(item ->> 'code') = 'unknown'
           or lower(item ->> 'label') like 'unknown%'
      )
    )
  )
) as dashboard_verification
from dashboards;
