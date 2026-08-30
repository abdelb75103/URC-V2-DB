select jsonb_build_object(
  'season', '2024-25',
  'team_count', (
    select count(*)
    from reporting.latest_team_dashboard_v6
    where season = '2024-25'
  ),
  'league_count', (
    select count(*)
    from reporting.latest_league_dashboard_v6
    where season = '2024-25'
  ),
  'team_payloads', (
    select jsonb_agg(
      jsonb_build_object(
        'team_key', team_key,
        'payload_sha256', reporting.canonical_jsonb_sha256_v1(
          to_jsonb(team_payload) - 'team_key'
        )
      )
      order by team_key
    )
    from reporting.latest_team_dashboard_v6 team_payload
    where season = '2024-25'
  ),
  'league_payload_sha256', (
    select reporting.canonical_jsonb_sha256_v1(to_jsonb(league_payload))
    from reporting.latest_league_dashboard_v6 league_payload
    where season = '2024-25'
  )
);
