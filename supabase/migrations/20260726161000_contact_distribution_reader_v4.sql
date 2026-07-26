-- Additive reader version exposing the contact_distribution payload section.
--
-- reporting.latest_team_dashboard_v2 / latest_league_dashboard_v2 project an
-- explicit allowlist of payload keys, so a new top-level key is invisible to
-- web_reader until a new reader version projects it. v3 selects source.* from
-- v2 and therefore never carries dashboard_payload, so v4 re-joins the payload
-- relations to reach the raw JSON.
--
-- Nothing frozen is edited: v2 and v3 stay exactly as released.
--
-- The re-join is one-to-one by construction:
--   * reporting.latest_approved_dashboard_bundle_v2 yields at most one approved
--     release per season (its correlated `limit 1` selector).
--   * reporting.team_dashboard_payloads_v2 has primary key
--     (bundle_release_id, team_key).
--   * reporting.league_release_payloads_v2 has primary key (release_id).
-- Verified read-only on 2026-07-26: 16 team rows in and 16 out, 1 league row in
-- and 1 out, zero missing, extra, or duplicated (team_key, season) pairs.

create view reporting.latest_team_dashboard_v4
with (security_invoker = false, security_barrier = true) as
select
  source.*,
  payload.dashboard_payload -> 'contact_distribution' as contact_distribution
from reporting.latest_team_dashboard_v3 source
join reporting.latest_approved_dashboard_bundle_v2 b
  on b.season = source.season
join reporting.team_dashboard_payloads_v2 payload
  on payload.bundle_release_id = b.release_id
 and payload.team_key = source.team_key;

create view reporting.latest_league_dashboard_v4
with (security_invoker = false, security_barrier = true) as
select
  source.*,
  payload.dashboard_payload -> 'contact_distribution' as contact_distribution
from reporting.latest_league_dashboard_v3 source
join reporting.latest_approved_dashboard_bundle_v2 b
  on b.season = source.season
join reporting.league_release_payloads_v2 payload
  on payload.release_id = b.release_id;

grant select on reporting.latest_team_dashboard_v4 to web_reader;
grant select on reporting.latest_league_dashboard_v4 to web_reader;

comment on view reporting.latest_team_dashboard_v4 is
  'V3 immutable team dashboard projection plus the approved contact_distribution payload section. No release, bundle, or build identifier crosses the web_reader boundary.';
comment on view reporting.latest_league_dashboard_v4 is
  'V3 immutable league dashboard projection plus the approved contact_distribution payload section. No release, bundle, or build identifier crosses the web_reader boundary.';
