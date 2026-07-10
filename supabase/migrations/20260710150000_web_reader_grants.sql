-- Phase 5.1: least-privilege website reader role.
--
-- web_reader is the ONLY database identity the website ever uses. Its whole
-- surface is one view: reporting.latest_team_dashboard (approved aggregate
-- dashboards only). It gets no table grants anywhere, and no usage on
-- ingestion/processing/audit/curated/analysis, so player-level and
-- pre-release data stay unreachable even if the web tier is compromised.
--
-- The role is created NOLOGIN here so no credential ever enters Git. The
-- LOGIN attribute and password are set out-of-band against the live target
-- (recorded as an ops step in docs/V2_FOUNDATION.md, credential stored only
-- in Git-ignored .env.local and Vercel env settings).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'web_reader') then
    create role web_reader nologin;
  end if;
end $$;

-- The consumer boundary: reporting.latest_team_dashboard flips from
-- security_invoker (Phase 4's internal default, matching the analysis views)
-- to definer rights with security_barrier. Rationale: every underlying table
-- (reporting.release_context / release_table_rows / aggregate_releases /
-- teams) is RLS-enabled with no policies, which is this project's deny-all
-- posture for direct access; the view runs with its owner's rights and is
-- the one deliberate, reviewed window through that posture. It exposes only
-- latest-APPROVED-release aggregates -- exactly the payload already
-- committed to content/reporting/*.json. security_barrier stops caller
-- functions from being pushed below the view's approved/latest filter
-- (e.g. probing retired releases' rows).
alter view reporting.latest_team_dashboard
  set (security_invoker = false, security_barrier = true);

grant usage on schema reporting to web_reader;
grant select on reporting.latest_team_dashboard to web_reader;

-- Defensive runtime limits for a public-facing read path.
alter role web_reader connection limit 20;
alter role web_reader set statement_timeout = '10s';

comment on view reporting.latest_team_dashboard is
  'Phase 4/5: latest approved full-dashboard release per team_key/season, '
  'assembled into the TeamDashboardData shape (lib/reporting.ts). Definer-'
  'rights + security_barrier: the deliberate read window for the web_reader '
  'role, which has SELECT on this view and nothing else.';
