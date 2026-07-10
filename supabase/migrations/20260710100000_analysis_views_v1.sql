-- Phase 3.1: versioned analysis views. New `analysis` schema, same revoke
-- posture as ingestion/processing/audit/reporting/curated (schema-level
-- revoke from anon/authenticated; there is no direct anon/authenticated
-- access path to begin with, this just matches the existing pattern).
-- Every view is created `with (security_invoker = true)`, matching
-- public.dashboard_team_metrics / reporting.latest_team_metric_aggregates.
--
-- Read-only contract (plan Phase 3 rule): every view here reads ONLY
-- curated.* plus reporting.teams for team metadata. No view in this
-- migration reads audit.*, processing.*, or ingestion.* directly. A
-- formula (incidence/burden rate) is defined exactly once, as the SQL
-- function analysis.rate_per_1000_v1, and every view that needs a rate
-- calls that function rather than re-deriving it. Rounding-for-display
-- (Python's `rounded()`, round-half-to-even to 1 decimal) is deliberately
-- NOT done in SQL: these views return raw numeric values, and
-- verify-analysis-parity applies the pipeline's own `rounded()` helper
-- before comparing to committed dashboard JSON, so display rounding can
-- never silently diverge between the two code paths.
--
-- Versioning contract: every view is suffixed _v1 and frozen once
-- accepted. Any later rule change is a new _v2 view plus a rerun of every
-- downstream consumer; this migration never edits a _v1 view definition
-- after freeze.
--
-- Derivation source: pipeline/__main__.py build_team_dashboard() is the
-- current definition of every published dashboard number (as of rule
-- versions injury_processing_2026-07-07_v1 / exposure_processing_2026-07-07_v1).
-- Every view below cites the exact Python logic it reproduces.
--
-- COHORT DEFINITION AND ITS TWO KNOWN GAPS (verified read-only, 10 July
-- 2026): build_team_dashboard() applies five cohort-exclusion reasons over
-- the standardised CSV before computing "recorded_injuries"
-- (received_or_injured_in_other_team, explicit_non_urc_match_type,
-- non_injury_problem_type, injury_date_missing_or_outside_exposure_coverage,
-- adjudicated_duplicate -- see injury_cohort_exclusion_reasons() in
-- pipeline/__main__.py). analysis.injury_cohort_v1 freezes the three of
-- those that are fully expressible from curated columns:
--   (a) not database-excluded: eligibility_status not in
--       ('excluded_from_analysis', 'excluded_duplicate_adjudicated');
--       review_required rows stay in the cohort, exactly as the dashboards
--       treated their un-adjudicated flagged rows (their outside-window
--       flags are re-applied by filter (c) anyway);
--   (b) problem_type = 'injury' (the dashboard's non_injury_problem_type
--       exclusion: a filled Problem type of Illness or Unknown is out);
--   (c) date_injured inside the team's exposure coverage window, derived
--       from curated.exposure included rows: min..max of
--       coalesce(session_date, week_start_date), with +6 days on the end
--       for single-grain weekly teams (the dashboard's weekly
--       coverage_end rule in build_team_dashboard()).
-- The remaining two dashboard filters CANNOT be derived from curated data
-- and are deliberate, documented gaps (not silently approximated):
--   (1) received_or_injured_in_other_team: the source column's values are
--       protected 'Team A'-'Team Z' league aliases, redacted in
--       ingestion.source_rows.source_values to a single indistinct marker
--       by the Phase 0.1 privacy fix, so own-team vs other-team is no
--       longer distinguishable anywhere in the DB (verified: the four
--       Irish teams' source column is entirely blank, so the filter is a
--       no-op for them; edinburgh has redacted values and is affected;
--       glasgow's exclusion outcomes were folded into eligibility_status
--       via its analysis-audit-file reapplication before the redaction,
--       so filter (a) already captures them). Closing this gap requires a
--       new derived, non-protected classification captured at
--       process-intake time (e.g. received_in_team_status:
--       own_team/other_team/club/missing) -- a curated schema extension
--       that needs explicit orchestrator approval; never a protected
--       alias value in curated/analysis schemas.
--   (2) explicit_non_urc_match_type: the dashboard's marker-list scan of
--       the raw Match Type string (academy/club/cup/friendly/...). The
--       raw string is preserved in ingestion.source_rows.source_values
--       (public competition names, not protected) but is not carried
--       into curated.injuries, and curated activity_context is NOT
--       equivalent (it classifies generic match/game values as 'match',
--       which the dashboard retains). Closing this gap needs a curated
--       column (raw match_type or a derived urc_scope_status), same
--       approval path as (1). glasgow is again already captured via (a).
-- Where these two gaps make a view differ from a committed dashboard,
-- verify-analysis-parity surfaces the DIFF for orchestrator adjudication
-- (bug vs documented improvement), per docs/DB_BACKED_REPORTING_PLAN.md
-- Phase 3.2. Expected from the pre-gate read-only preview: connacht,
-- leinster, munster, ulster and glasgow reproduce their dashboards'
-- cohort exactly; edinburgh differs by exactly the rows its dashboard
-- excluded under (1) and (2).
--
-- Second known gap, same shape: reporting.teams.weekly_reporter is a
-- deliberate placeholder (hardcoded false for every team; see
-- 20260709120100_reporting_teams_dimension.sql) because the only
-- documented weekly-reporter evidence identifies teams by protected
-- league alias, and joining that into a public-name-keyed table is
-- exactly what must never happen. Verified live 10 July 2026:
-- curated.exposure.grain is actually 'weekly' for connacht, leinster,
-- munster, ulster and 'session' for edinburgh, glasgow -- i.e. FOUR of
-- the six live teams are weekly reporters, not zero. That grain value is
-- safe to read directly (it reflects which exposure file format was
-- ingested, never an alias), so analysis.exposure_hours_v1 derives its
-- weekly-reporter behaviour from curated.exposure.grain empirically,
-- while still reading and exposing reporting.teams.weekly_reporter
-- verbatim for cross-checking against a future non-alias-joining process
-- that might populate it correctly.

create schema if not exists analysis;

revoke all on schema analysis from anon, authenticated;

-- The one place the incidence/burden rate formula is defined (plan rule:
-- "a formula appears in exactly one view"; extended here to "exactly one
-- routine", since the same rate calculation is needed by
-- headline_metrics_v1, monthly_v1, body_locations_v1, and
-- injury_types_v1 at different levels of aggregation). Mirrors
-- pipeline/__main__.py rate_per_1000(): count / hours * 1000, or NULL
-- when hours <= 0.
create function analysis.rate_per_1000_v1(count_value numeric, hours_value numeric)
returns numeric
language sql
immutable
as $$
  select case when hours_value > 0 then count_value / hours_value * 1000 else null end;
$$;

revoke execute on function analysis.rate_per_1000_v1(numeric, numeric) from public;

comment on function analysis.rate_per_1000_v1(numeric, numeric) is
  'Sole definition of the incidence/burden rate formula (count / hours * 1000). '
  'Mirrors pipeline/__main__.py rate_per_1000(). Frozen at _v1; do not edit after freeze.';

-- analysis.injury_cohort_v1
-- Provenance: IOC 2020 consensus / STROBE-SIIS case-eligibility definition
-- (bjsm.bmj.com/content/54/7/372); Fuller et al. 2007 rugby union
-- consensus for match/training/unknown activity classification.
-- Reproduces: build_team_dashboard()'s `injury_rows` list -- the
-- eligible cohort behind the "recorded_injuries" and "time_loss_injuries"
-- headline numbers, and every downstream section (setting_split,
-- monthly, body_locations, injury_types, severity_distribution) that
-- groups over it. Applies the three curated-expressible frozen filters
-- (not database-excluded; problem_type = 'injury'; date_injured inside
-- the exposure coverage window incl. the +6-day weekly-end rule); the
-- received/injured-in-team and explicit-non-URC-match-type filters are
-- documented gaps -- see the schema header comment.
-- The exposure coverage window is derived here and ONLY here (one
-- formula, one view); coverage_start/coverage_end are exposed as columns
-- so downstream consumers reuse rather than re-derive them.
create view analysis.injury_cohort_v1
with (security_invoker = true) as
with exposure_window as (
  select
    e.team_key,
    e.season,
    min(coalesce(e.session_date, e.week_start_date)) as coverage_start,
    max(coalesce(e.session_date, e.week_start_date))
      + case when count(distinct e.grain) = 1 and min(e.grain) = 'weekly' then 6 else 0 end
      as coverage_end
  from curated.exposure e
  join curated.builds b on b.id = e.curated_build_id and b.status = 'active'
  where e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date) is not null
  group by e.team_key, e.season
)
select
  i.id as injury_id,
  i.team_key,
  i.season,
  i.source_row_id,
  i.record_version_id,
  i.curated_build_id,
  i.player_uid,
  i.injury_uid,
  i.date_injured,
  i.days_injured,
  coalesce(i.days_injured, 0) as days_lost,
  coalesce(i.days_injured, 0) > 0 as is_time_loss,
  i.is_closed,
  i.activity_context,
  case i.activity_context
    when 'urc_match' then 'match'
    when 'match' then 'match'
    when 'training' then 'training'
    else 'unknown'
  end as setting_label,
  i.contact_context,
  i.recurrence_status,
  coalesce(i.severity_category, 'unknown_or_censored') as severity_category,
  coalesce(sc.label, 'Unknown') as severity_label,
  coalesce(i.body_location, 'unknown') as body_location,
  coalesce(bl.label, 'Unknown') as body_location_label,
  coalesce(i.injury_type, 'unknown') as injury_type,
  coalesce(it.label, 'Unknown') as injury_type_label,
  i.problem_type,
  i.eligibility_status,
  w.coverage_start,
  w.coverage_end
from curated.injuries i
join curated.builds b on b.id = i.curated_build_id and b.status = 'active'
join exposure_window w on w.team_key = i.team_key and w.season = i.season
left join curated.code_lists sc
  on sc.list_name = 'severity_category' and sc.code = coalesce(i.severity_category, 'unknown_or_censored')
left join curated.code_lists bl
  on bl.list_name = 'body_location' and bl.code = coalesce(i.body_location, 'unknown')
left join curated.code_lists it
  on it.list_name = 'injury_type' and it.code = coalesce(i.injury_type, 'unknown')
where i.eligibility_status not in ('excluded_from_analysis', 'excluded_duplicate_adjudicated')
  and i.problem_type = 'injury'
  and i.date_injured is not null
  and i.date_injured >= w.coverage_start
  and i.date_injured <= w.coverage_end;

comment on view analysis.injury_cohort_v1 is
  'Frozen injury eligibility cohort (IOC 2020 / STROBE-SIIS). Reproduces '
  'build_team_dashboard() injury_rows via the three curated-expressible '
  'filters (not excluded, problem_type=injury, inside exposure coverage '
  'window). See migration header for the received/injured-in-team and '
  'non-URC-match-type filter gaps this view cannot yet capture.';

-- analysis.exposure_hours_v1
-- Provenance: Fuller et al. 2007 rugby union consensus exposure/denominator
-- convention; docs/EXPOSURE_CLEANING_PROTOCOL.md match-hours-per-team
-- formula (PLAYER_HOURS_PER_TEAM_MATCH, already applied by
-- curated.team_exposure_denominators in Phase 2). Reproduces: the
-- dashboard's "coverage.hours" denominator and the implicit match/training
-- split used nowhere else but here. Native grain preserved: this view
-- aggregates curated.exposure rows exactly as ingested (session-level or
-- weekly-level, per team) into one team/season row; it never fabricates
-- daily observations from weekly totals (AGENTS.md exposure rule).
create view analysis.exposure_hours_v1
with (security_invoker = true) as
select
  d.team_key,
  d.season,
  d.curated_build_id,
  t.weekly_reporter as team_dimension_weekly_reporter_flag,
  g.exposure_grain,
  d.matches_played,
  d.match_hours,
  d.training_hours,
  d.total_hours,
  d.method_note
from curated.team_exposure_denominators d
join curated.builds b on b.id = d.curated_build_id and b.status = 'active'
join reporting.teams t on t.team_key = d.team_key
left join lateral (
  select case when count(distinct e.grain) = 1 then min(e.grain) else 'mixed' end as exposure_grain
  from curated.exposure e
  where e.curated_build_id = d.curated_build_id
    and e.eligibility_status = 'included_pending_protocol'
) g on true;

comment on view analysis.exposure_hours_v1 is
  'Match/training/total exposure hours per team/season, native grain '
  'preserved. exposure_grain is derived empirically from '
  'curated.exposure.grain (safe: reflects file format, never a protected '
  'alias); team_dimension_weekly_reporter_flag is read from '
  'reporting.teams.weekly_reporter as-is (a deliberate placeholder, '
  'currently false for every team -- see migration header) for '
  'cross-checking only, not as the operative signal.';

-- analysis.headline_metrics_v1
-- Provenance: IOC 2020 consensus incidence/burden/severity definitions.
-- Reproduces: build_team_dashboard()'s "headline" section (recorded_injuries,
-- time_loss_injuries, incidence_per_1000h, severity_mean_days,
-- severity_median_days, burden_per_1000h).
create view analysis.headline_metrics_v1
with (security_invoker = true) as
with cohort_agg as (
  select
    team_key,
    season,
    count(*) as recorded_injuries,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost_total,
    avg(days_lost) filter (where is_time_loss) as mean_severity_days,
    percentile_cont(0.5) within group (order by days_lost) filter (where is_time_loss) as median_severity_days
  from analysis.injury_cohort_v1
  group by team_key, season
)
select
  e.team_key,
  e.season,
  coalesce(c.recorded_injuries, 0) as recorded_injuries,
  coalesce(c.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(c.days_lost_total, 0) as days_lost_total,
  c.mean_severity_days,
  c.median_severity_days,
  e.total_hours as exposure_hours,
  analysis.rate_per_1000_v1(coalesce(c.time_loss_injuries, 0), e.total_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(coalesce(c.days_lost_total, 0), e.total_hours) as burden_per_1000h
from analysis.exposure_hours_v1 e
left join cohort_agg c on c.team_key = e.team_key and c.season = e.season;

comment on view analysis.headline_metrics_v1 is
  'Headline counts, incidence/1000h (numerator+denominator as columns), '
  'burden, days lost, mean+median severity. Reproduces the dashboard '
  '"headline" section. Reads analysis.injury_cohort_v1 + '
  'analysis.exposure_hours_v1; calls analysis.rate_per_1000_v1 for rates.';

-- analysis.monthly_v1
-- Provenance: STROBE-SIIS temporal reporting convention.
-- Reproduces: build_team_dashboard()'s "monthly" section -- exposure_by_month
-- (all included exposure rows, keyed by exposure date) full-outer-joined
-- with injuries_by_month (time-loss injuries only, keyed by Date Injured).
create view analysis.monthly_v1
with (security_invoker = true) as
with exposure_month as (
  select
    e.team_key,
    e.season,
    date_trunc('month', coalesce(e.session_date, e.week_start_date))::date as month_start,
    sum(e.minutes_clean) / 60 as exposure_hours,
    sum(e.distance_m_clean) / 1000 as distance_km
  from curated.exposure e
  join curated.builds b on b.id = e.curated_build_id and b.status = 'active'
  where e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date) is not null
  group by e.team_key, e.season, date_trunc('month', coalesce(e.session_date, e.week_start_date))
),
injury_month as (
  select
    c.team_key,
    c.season,
    date_trunc('month', c.date_injured)::date as month_start,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_v1 c
  where c.is_time_loss and c.date_injured is not null
  group by c.team_key, c.season, date_trunc('month', c.date_injured)
),
months as (
  select team_key, season, month_start from exposure_month
  union
  select team_key, season, month_start from injury_month
)
select
  m.team_key,
  m.season,
  m.month_start,
  to_char(m.month_start, 'Mon YYYY') as month_label,
  coalesce(x.exposure_hours, 0) as exposure_hours,
  coalesce(x.distance_km, 0) as distance_km,
  coalesce(j.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(j.days_lost, 0) as days_lost,
  analysis.rate_per_1000_v1(coalesce(j.time_loss_injuries, 0), coalesce(x.exposure_hours, 0)) as incidence_per_1000h,
  analysis.rate_per_1000_v1(coalesce(j.days_lost, 0), coalesce(x.exposure_hours, 0)) as burden_per_1000h
from months m
left join exposure_month x on x.team_key = m.team_key and x.season = m.season and x.month_start = m.month_start
left join injury_month j on j.team_key = m.team_key and j.season = m.season and j.month_start = m.month_start
order by m.team_key, m.season, m.month_start;

comment on view analysis.monthly_v1 is
  'Monthly exposure hours/distance and time-loss injury counts/rates. '
  'Reproduces the dashboard "monthly" section. month_start is the union '
  'of every month with exposure and every month with a time-loss injury, '
  'matching build_team_dashboard()''s sorted(set(exposure_by_month) | '
  'set(injuries_by_month)).';

-- analysis.setting_split_v1
-- Provenance: Fuller et al. 2007 match/training occasion classification.
-- Reproduces: build_team_dashboard()'s "setting_split" section (grouped
-- by the collapsed Occasion category label: urc_match+match -> "match",
-- training -> "training", else "unknown"; team-level exposure hours as
-- the implicit denominator, per the dashboard's documented limitation
-- that setting-specific exposure denominators are not yet approved).
create view analysis.setting_split_v1
with (security_invoker = true) as
select
  c.team_key,
  c.season,
  c.setting_label as label,
  count(*) as time_loss_injuries,
  sum(c.days_lost) as days_lost,
  (sum(c.days_lost)::numeric / nullif(count(*), 0)) as mean_severity_days
from analysis.injury_cohort_v1 c
where c.is_time_loss
group by c.team_key, c.season, c.setting_label
order by c.team_key, c.season, count(*) desc, sum(c.days_lost) desc, c.setting_label asc;

comment on view analysis.setting_split_v1 is
  'Time-loss injuries/days lost/mean severity by collapsed match-vs-training '
  'setting label. Reproduces the dashboard "setting_split" section. No '
  'incidence/burden columns: the dashboard deliberately omits them here '
  'pending setting-specific exposure denominators.';

-- analysis.body_locations_v1
-- Provenance: IOC 2020 consensus body-area categories
-- (docs/IOC_TAXONOMY_BUCKETS.csv, curated.code_lists list_name='body_location').
-- Reproduces: build_team_dashboard()'s "body_locations" section
-- (build_group_rows(time_loss_rows, "Body Part", hours, limit=10)).
-- `rank` orders groups exactly as build_group_rows sorts
-- (time_loss_injuries desc, days_lost desc, label asc); the dashboard's
-- top-10 truncation is a presentation rule applied by
-- verify-analysis-parity when rendering, not baked into this view, so the
-- full ranked distribution stays queryable.
create view analysis.body_locations_v1
with (security_invoker = true) as
with grouped as (
  select
    c.team_key,
    c.season,
    c.body_location_label as label,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_v1 c
  where c.is_time_loss
  group by c.team_key, c.season, c.body_location_label
)
select
  g.team_key,
  g.season,
  g.label,
  g.time_loss_injuries,
  g.days_lost,
  analysis.rate_per_1000_v1(g.time_loss_injuries, e.total_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost, e.total_hours) as burden_per_1000h,
  (g.days_lost::numeric / nullif(g.time_loss_injuries, 0)) as mean_severity_days,
  row_number() over (
    partition by g.team_key, g.season
    order by g.time_loss_injuries desc, g.days_lost desc, g.label asc
  ) as rank
from grouped g
join analysis.exposure_hours_v1 e on e.team_key = g.team_key and e.season = g.season
order by g.team_key, g.season, rank;

comment on view analysis.body_locations_v1 is
  'Time-loss injuries by IOC 2020 body-location label, ranked. Reproduces '
  'the dashboard "body_locations" section (top 10 by rank).';

-- analysis.injury_types_v1
-- Provenance: IOC 2020 consensus tissue/pathology categories
-- (docs/IOC_TAXONOMY_BUCKETS.csv, curated.code_lists list_name='injury_type').
-- Reproduces: build_team_dashboard()'s "injury_types" section
-- (build_group_rows(time_loss_rows, "Injury Tissue Type/s", hours, limit=10)).
create view analysis.injury_types_v1
with (security_invoker = true) as
with grouped as (
  select
    c.team_key,
    c.season,
    c.injury_type_label as label,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_v1 c
  where c.is_time_loss
  group by c.team_key, c.season, c.injury_type_label
)
select
  g.team_key,
  g.season,
  g.label,
  g.time_loss_injuries,
  g.days_lost,
  analysis.rate_per_1000_v1(g.time_loss_injuries, e.total_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost, e.total_hours) as burden_per_1000h,
  (g.days_lost::numeric / nullif(g.time_loss_injuries, 0)) as mean_severity_days,
  row_number() over (
    partition by g.team_key, g.season
    order by g.time_loss_injuries desc, g.days_lost desc, g.label asc
  ) as rank
from grouped g
join analysis.exposure_hours_v1 e on e.team_key = g.team_key and e.season = g.season
order by g.team_key, g.season, rank;

comment on view analysis.injury_types_v1 is
  'Time-loss injuries by IOC 2020 tissue/pathology label, ranked. '
  'Reproduces the dashboard "injury_types" section (top 10 by rank).';

-- analysis.severity_distribution_v1
-- Provenance: IOC 2020 consensus time-loss severity banding.
-- Reproduces: build_team_dashboard()'s "severity_distribution" section
-- (grouped over the FULL cohort, not just time-loss rows: a
-- zero_days_medical_attention_only band has recorded_injuries > 0 but
-- time_loss_injuries = 0, matching curated.injuries.severity_category,
-- which is computed by the same thresholds as severity_band() /
-- severity_category() in pipeline/__main__.py).
-- Label note: the published dashboards label the zero-days band
-- 'Medical attention' (severity_band() in pipeline/__main__.py), while
-- curated.code_lists carries the fuller controlled label
-- 'Medical attention (0 days)'. This view emits the dashboard
-- presentation label (defined in exactly this one view) so the published
-- shape is reproduced exactly; analysis.injury_cohort_v1's severity_label
-- stays the controlled code_lists label.
create view analysis.severity_distribution_v1
with (security_invoker = true) as
select
  c.team_key,
  c.season,
  c.severity_category as key,
  case c.severity_category
    when 'zero_days_medical_attention_only' then 'Medical attention'
    when 'one_day' then '1 day'
    when 'two_to_three_days' then '2-3 days'
    when 'four_to_seven_days' then '4-7 days'
    when 'eight_to_twenty_eight_days' then '8-28 days'
    when 'greater_than_twenty_eight_days' then '>28 days'
    else 'Unknown or censored'
  end as label,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  case c.severity_category
    when 'zero_days_medical_attention_only' then 0
    when 'one_day' then 1
    when 'two_to_three_days' then 2
    when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4
    when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.injury_cohort_v1 c
group by c.team_key, c.season, c.severity_category
order by c.team_key, c.season, band_order;

comment on view analysis.severity_distribution_v1 is
  'Recorded/time-loss injury counts and days lost per severity band, in '
  'the dashboard''s fixed band order. Reproduces the dashboard '
  '"severity_distribution" section.';

-- analysis.coverage_v1
-- Provenance: STROBE-SIIS completeness/coverage reporting requirement
-- (report data completeness and team coverage alongside estimates).
-- Reproduces: build_team_dashboard()'s "coverage" section, with one
-- documented exception: injury_eligibility_status_counts is a
-- curated-native breakdown (included_pending_protocol /
-- excluded_from_analysis / review_required / excluded_duplicate_adjudicated
-- counts from curated.injuries.eligibility_status), NOT the dashboard's
-- five fine-grained cohort-exclusion reason codes
-- (received_or_injured_in_other_team, explicit_non_urc_match_type,
-- non_injury_problem_type, injury_date_missing_or_outside_exposure_coverage,
-- adjudicated_duplicate). Those reason codes live only in
-- audit.record_events, which this view cannot read under the
-- curated-only read rule for analysis views (see migration header).
create view analysis.coverage_v1
with (security_invoker = true) as
with exposure_agg as (
  select
    e.team_key,
    e.season,
    count(*) as exposure_rows,
    -- nullif: build_team_dashboard() counts players with a non-empty
    -- player_uid only, so an empty-string uid must not count as a player.
    count(distinct nullif(e.player_uid, '')) as exposed_players,
    count(distinct case when e.grain = 'weekly' then e.week_start_date end) as weeks_raw,
    count(distinct coalesce(e.session_date, e.week_start_date)) as exposure_periods,
    sum(e.minutes_clean) / 60 as hours,
    sum(e.distance_m_clean) / 1000 as distance_km
  from curated.exposure e
  join curated.builds b on b.id = e.curated_build_id and b.status = 'active'
  where e.eligibility_status = 'included_pending_protocol'
  group by e.team_key, e.season
),
scope_counts as (
  select
    e.team_key,
    e.season,
    coalesce(e.scope_status, 'unknown') as scope_status,
    count(*) as n
  from curated.exposure e
  join curated.builds b on b.id = e.curated_build_id and b.status = 'active'
  where e.eligibility_status = 'included_pending_protocol'
  group by e.team_key, e.season, coalesce(e.scope_status, 'unknown')
),
scope_json as (
  select team_key, season, jsonb_object_agg(scope_status, n) as scope_status_counts
  from scope_counts
  group by team_key, season
),
injury_eligibility_counts as (
  select i.team_key, i.season, i.eligibility_status, count(*) as n
  from curated.injuries i
  join curated.builds b on b.id = i.curated_build_id and b.status = 'active'
  group by i.team_key, i.season, i.eligibility_status
),
injury_eligibility_json as (
  select team_key, season, jsonb_object_agg(eligibility_status, n) as injury_eligibility_status_counts
  from injury_eligibility_counts
  group by team_key, season
)
select
  g.team_key,
  g.season,
  g.exposure_grain,
  a.exposure_rows,
  a.exposed_players,
  case when g.exposure_grain = 'weekly' then a.weeks_raw else 0 end as weeks,
  a.exposure_periods,
  a.hours,
  a.distance_km,
  'included'::text as included_exposure_status,
  s.scope_status_counts,
  ie.injury_eligibility_status_counts
from analysis.exposure_hours_v1 g
join exposure_agg a on a.team_key = g.team_key and a.season = g.season
left join scope_json s on s.team_key = g.team_key and s.season = g.season
left join injury_eligibility_json ie on ie.team_key = g.team_key and ie.season = g.season;

comment on view analysis.coverage_v1 is
  'Exposure/injury coverage completeness per team/season. Reproduces the '
  'dashboard "coverage" section except injury_eligibility_status_counts, '
  'which is a curated-native eligibility breakdown, not the dashboard''s '
  'five audit-schema-derived cohort-exclusion reason codes (see comment '
  'above and the migration header).';
