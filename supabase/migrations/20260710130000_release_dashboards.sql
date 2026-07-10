-- Phase 4.1: full dashboard payload into the database. Same schema-level
-- revoke posture as ingestion/processing/audit/reporting/curated/analysis
-- (already revoked at schema level in 20260706125243_initial_local_spine.sql;
-- these are new tables/view inside the existing `reporting` schema, so no
-- further schema-level grant/revoke is needed -- matching the precedent that
-- reporting.team_metric_aggregates required no extra revoke beyond RLS).
--
-- Design: `reporting.aggregate_releases` (existing, Phase 0/1) stays the one
-- release-event anchor for BOTH the old headline-only releases (Edinburgh,
-- and any future one) and these new full-dashboard releases; a release_id
-- gets AT MOST one reporting.release_context row (the per-release method/
-- coverage/limitations context) and MANY reporting.release_table_rows rows
-- (the normalized per-section metric rows). A release with no
-- release_context row (e.g. Edinburgh's approved 'Edinburgh-2024-25-approved'
-- release, which predates this migration and stays untouched/parked) simply
-- does not appear in reporting.latest_team_dashboard -- that view only
-- assembles releases that went through this new path.
--
-- injury_cohort_filters (Adjudication 2, data/reporting/
-- analysis_parity_adjudications_2026-07-10.json): analysis.coverage_v1
-- documents that the dashboard's five cohort-exclusion reason counts cannot
-- be reproduced from curated.* alone (curated-only read rule for analysis
-- views). This block is carried into release_context from audit evidence
-- (audit.record_events rows with field_name='analysis_eligibility_status',
-- action='exclude') by the release command itself -- a plain Python/SQL
-- query, never a new analysis.*_v1 view -- and is exposed as its own typed
-- column here (not only nested inside `coverage`) so it can be queried and
-- audited independently of the coverage jsonb blob's internal shape.

create table reporting.release_context (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null unique references reporting.aggregate_releases(id),
  team_key text not null references reporting.teams(team_key),
  season text not null,
  -- Frozen at release time (never re-joined against reporting.teams at read
  -- time) so a later rename of reporting.teams.display_name can never
  -- retroactively change what an already-approved release reports.
  team_display_name text not null,
  curated_build_id uuid not null references curated.builds(id),
  analysis_view_version text not null default 'v1',
  generated_at timestamptz not null,
  analysis_window_start date not null,
  analysis_window_end date not null,
  analysis_window_basis text not null,
  method jsonb not null default '[]'::jsonb,
  coverage jsonb not null default '{}'::jsonb,
  injury_cohort_filters jsonb not null default '{}'::jsonb,
  prior_season jsonb not null default '{}'::jsonb,
  limitations jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

comment on table reporting.release_context is
  'Phase 4: one row per full-dashboard release (release_id unique). Carries '
  'the non-tabular dashboard context (analysis window, method lines, '
  'coverage block, injury_cohort_filters, prior_season, limitations) that '
  'reporting.release_table_rows does not. team_display_name is frozen at '
  'release time, not re-derived from reporting.teams at read time.';

create table reporting.release_table_rows (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references reporting.aggregate_releases(id),
  team_key text not null references reporting.teams(team_key),
  season text not null,
  section text not null check (section in (
    'headline', 'setting_split', 'monthly', 'body_locations', 'injury_types', 'severity_distribution'
  )),
  -- Stable identity within (release_id, section): the metric key for
  -- headline, the severity band key for severity_distribution, the
  -- ISO month (YYYY-MM-01) for monthly, a slug of the group label for
  -- setting_split/body_locations/injury_types.
  row_key text not null,
  ordinal integer not null,
  label text,
  month text,
  value numeric,
  numerator numeric,
  denominator numeric,
  unit text,
  formula text,
  exposure_hours numeric,
  distance_km numeric,
  time_loss_injuries numeric,
  recorded_injuries numeric,
  days_lost numeric,
  incidence_per_1000h numeric,
  burden_per_1000h numeric,
  mean_severity_days numeric,
  created_at timestamptz not null default now(),
  unique (release_id, section, row_key)
);

comment on table reporting.release_table_rows is
  'Phase 4: normalized snapshot of every dashboard section row for a full-'
  'dashboard release. One release_table_rows row per rendered array item '
  '(AnalyticsRow / HeadlineMetric / SeverityRow in lib/reporting.ts); '
  'body_locations/injury_types store only the top-10-ranked rows actually '
  'published (the full ranked distribution stays queryable via '
  'analysis.body_locations_v1 / analysis.injury_types_v1 directly, per '
  'those views'' own documented separation of concerns).';

create index release_table_rows_team_season_section
  on reporting.release_table_rows (team_key, season, section, ordinal);

alter table reporting.release_context enable row level security;
alter table reporting.release_table_rows enable row level security;

-- reporting.latest_team_dashboard: latest APPROVED full-dashboard release
-- per team_key/season, assembled into the TeamDashboardData shape
-- lib/reporting.ts / the website consumes. Only releases with a
-- release_context row participate (see design note above); Edinburgh's
-- pre-Phase-4 release has none, so it is correctly absent here until its
-- own re-release is explicitly approved. security_invoker mirrors every
-- other view in this schema (reporting.latest_team_metric_aggregates,
-- public.dashboard_team_metrics, every analysis.*_v1 view). Does not read,
-- alter, or depend on reporting.latest_team_metric_aggregates /
-- reporting.team_metric_aggregates in any way -- that view and its
-- underlying table are untouched by this migration and keep working
-- exactly as before for any release that still populates them.
create view reporting.latest_team_dashboard
with (security_invoker = true) as
with latest_release as (
  select distinct on (rc.team_key, rc.season)
    rc.release_id, rc.team_key, rc.season
  from reporting.release_context rc
  join reporting.aggregate_releases r on r.id = rc.release_id
  where r.status = 'approved'
  order by rc.team_key, rc.season, r.approved_at desc nulls last, r.created_at desc, r.id desc
),
section_docs as (
  select
    t.release_id,
    t.section,
    jsonb_agg(
      case t.section
        when 'headline' then jsonb_strip_nulls(jsonb_build_object(
          'key', t.row_key, 'label', t.label, 'value', t.value, 'unit', t.unit,
          'numerator', t.numerator, 'denominator', t.denominator, 'formula', t.formula
        ))
        when 'setting_split' then jsonb_build_object(
          'label', t.label, 'time_loss_injuries', t.time_loss_injuries,
          'days_lost', t.days_lost, 'mean_severity_days', t.mean_severity_days
        )
        when 'monthly' then jsonb_build_object(
          'month', t.month, 'exposure_hours', t.exposure_hours, 'distance_km', t.distance_km,
          'time_loss_injuries', t.time_loss_injuries, 'days_lost', t.days_lost,
          'incidence_per_1000h', t.incidence_per_1000h, 'burden_per_1000h', t.burden_per_1000h
        )
        when 'severity_distribution' then jsonb_build_object(
          'key', t.row_key, 'label', t.label, 'recorded_injuries', t.recorded_injuries,
          'time_loss_injuries', t.time_loss_injuries, 'days_lost', t.days_lost
        )
        else jsonb_build_object(
          'label', t.label, 'time_loss_injuries', t.time_loss_injuries, 'days_lost', t.days_lost,
          'incidence_per_1000h', t.incidence_per_1000h, 'burden_per_1000h', t.burden_per_1000h,
          'mean_severity_days', t.mean_severity_days
        )
      end
      order by t.ordinal
    ) as docs
  from reporting.release_table_rows t
  join latest_release lr
    on lr.release_id = t.release_id
  group by t.release_id, t.section
)
select
  lr.team_key,
  rc.team_display_name as team,
  lr.season,
  rc.generated_at,
  jsonb_build_object(
    'start', rc.analysis_window_start,
    'end', rc.analysis_window_end,
    'basis', rc.analysis_window_basis
  ) as analysis_window,
  rc.method,
  rc.coverage,
  coalesce(hl.docs, '[]'::jsonb) as headline,
  coalesce(ss.docs, '[]'::jsonb) as setting_split,
  coalesce(mo.docs, '[]'::jsonb) as monthly,
  coalesce(bl.docs, '[]'::jsonb) as body_locations,
  coalesce(it.docs, '[]'::jsonb) as injury_types,
  coalesce(sd.docs, '[]'::jsonb) as severity_distribution,
  rc.prior_season,
  rc.limitations,
  rc.release_id,
  rc.curated_build_id
from latest_release lr
join reporting.release_context rc on rc.release_id = lr.release_id
left join section_docs hl on hl.release_id = lr.release_id and hl.section = 'headline'
left join section_docs ss on ss.release_id = lr.release_id and ss.section = 'setting_split'
left join section_docs mo on mo.release_id = lr.release_id and mo.section = 'monthly'
left join section_docs bl on bl.release_id = lr.release_id and bl.section = 'body_locations'
left join section_docs it on it.release_id = lr.release_id and it.section = 'injury_types'
left join section_docs sd on sd.release_id = lr.release_id and sd.section = 'severity_distribution';

comment on view reporting.latest_team_dashboard is
  'Phase 4: latest approved full-dashboard release per team_key/season, '
  'assembled into the TeamDashboardData shape (lib/reporting.ts). Read-only '
  'consumer view for Phase 5''s web_reader role (not yet granted here).';

-- Dimension correction: the club's proper public name is 'Glasgow Warriors'
-- (already the name used throughout the approved, committed glasgow dashboard
-- text: team, analysis_window.basis, prior_season.note). The seed in
-- 20260709120100_reporting_teams_dimension.sql abbreviated it to 'Glasgow';
-- correcting it here keeps every published sentence byte-identical at the
-- Phase 4 re-release (the diff gate treats ANY team-name drift as blocking).
-- The website grid label comes from config/teams.ts and is unaffected.
update reporting.teams
set display_name = 'Glasgow Warriors'
where team_key = 'glasgow' and display_name = 'Glasgow';

-- Controlled reason code for the Phase 4 full-dashboard release run
-- (distinct from the existing 'aggregate_release' code, which described the
-- old headline-only 'read-only website smoke path').
insert into audit.reason_codes (code, description) values
  (
    'full_dashboard_release',
    'Full DB-backed dashboard snapshot released from analysis.*_v1 views '
    'into reporting.release_table_rows/release_context (Phase 4): every '
    'section (headline, setting_split, monthly, body_locations, '
    'injury_types, severity_distribution) plus release_context in one '
    'transaction, gated on a fresh (non-stale) active curated build, '
    'required migrations, a clean protected-alias scan, and a non-dirty '
    'code_version.'
  )
on conflict (code) do nothing;
