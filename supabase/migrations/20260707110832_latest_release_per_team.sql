create or replace view reporting.latest_team_metric_aggregates
with (security_invoker = true) as
with latest_releases as (
  select distinct on (m.team, m.season, m.scope)
    m.release_id,
    m.team,
    m.season,
    m.scope
  from reporting.team_metric_aggregates m
  join reporting.aggregate_releases r on r.id = m.release_id
  where r.status = 'approved'
  order by m.team, m.season, m.scope, r.approved_at desc, r.created_at desc, r.id desc
)
select m.*
from reporting.team_metric_aggregates m
join latest_releases latest
  on latest.release_id = m.release_id
 and latest.team = m.team
 and latest.season = m.season
 and latest.scope = m.scope;
