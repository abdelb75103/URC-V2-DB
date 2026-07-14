-- League/team dashboard V2 analytical and release contract.
--
-- Additive only: every accepted *_v1 view and reporting.latest_team_dashboard
-- remains unchanged. V2 calculations are pinned to the immutable curated_build_id
-- stored on each latest approved full team release; they never follow an
-- unreleased active build.
--
-- Denominator decision (Abdel Babiker, 14 July 2026): match exposure uses every
-- registered fixture for the season at 15 players * 80 minutes / 60 = 20
-- player-hours per team-match. Training exposure is total cleaned exposure minus
-- match exposure. For the approved 2024-25 release this deliberately means 302
-- team-fixture participations / 6,040 match player-hours, including the two
-- fixtures after the Edinburgh and Lions team-specific coverage end dates.
-- Unknown-setting injuries retain counts/days/severity but have NULL exposure,
-- incidence, and burden.

insert into audit.reason_codes (code, description) values (
  'league_dashboard_release_v2',
  'Immutable 16-team league dashboard release from build-pinned V2 analysis views, using pooled numerators and denominators.'
) on conflict (code) do nothing;

-- Build-pinned cohort: reproduces the frozen amended V1 eligibility rule without
-- the V1 active-build join, so an approved release continues to resolve exactly
-- its immutable build if a newer unreleased build later becomes active.
create view analysis.injury_cohort_by_build_v2
with (security_invoker = true) as
with exposure_window as (
  select
    e.curated_build_id,
    e.team_key,
    e.season,
    min(coalesce(e.session_date, e.week_start_date)) as coverage_start,
    max(coalesce(e.session_date, e.week_start_date))
      + case when count(distinct e.grain) = 1 and min(e.grain) = 'weekly' then 6 else 0 end
      as coverage_end
  from curated.exposure e
  where e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date) is not null
  group by e.curated_build_id, e.team_key, e.season
)
select
  i.id as injury_id,
  i.curated_build_id,
  i.team_key,
  i.season,
  i.date_injured,
  i.days_injured,
  coalesce(i.days_injured, 0) as days_lost,
  coalesce(i.days_injured, 0) > 0 as is_time_loss,
  case i.activity_context
    when 'urc_match' then 'match'
    when 'match' then 'match'
    when 'training' then 'training'
    else 'unknown'
  end as setting_code,
  coalesce(i.body_location, 'unknown') as body_location_code,
  coalesce(bl.label, 'Unknown') as body_location_label,
  coalesce(i.injury_type, 'unknown') as injury_type_code,
  coalesce(it.label, 'Unknown') as injury_type_label,
  coalesce(i.severity_category, 'unknown_or_censored') as severity_code,
  case coalesce(i.severity_category, 'unknown_or_censored')
    when 'zero_days_medical_attention_only' then 'Medical attention'
    when 'one_day' then '1 day'
    when 'two_to_three_days' then '2-3 days'
    when 'four_to_seven_days' then '4-7 days'
    when 'eight_to_twenty_eight_days' then '8-28 days'
    when 'greater_than_twenty_eight_days' then '>28 days'
    else 'Unknown or censored'
  end as severity_label,
  w.coverage_start,
  w.coverage_end
from curated.injuries i
join exposure_window w
  on w.curated_build_id = i.curated_build_id
 and w.team_key = i.team_key
 and w.season = i.season
left join curated.code_lists bl
  on bl.list_name = 'body_location' and bl.code = coalesce(i.body_location, 'unknown')
left join curated.code_lists it
  on it.list_name = 'injury_type' and it.code = coalesce(i.injury_type, 'unknown')
where i.eligibility_status not in ('excluded_from_analysis', 'excluded_duplicate_adjudicated')
  and i.problem_type = 'injury'
  and i.date_injured is not null
  and i.date_injured between w.coverage_start and w.coverage_end
  and (i.received_in_team_status is null or i.received_in_team_status not in ('other_team', 'club'))
  and (i.urc_match_scope is null or i.urc_match_scope <> 'non_urc_marker');

create view analysis.exposure_hours_by_build_v2
with (security_invoker = true) as
select
  d.curated_build_id,
  d.team_key,
  d.season,
  d.matches_played,
  d.match_hours,
  d.training_hours,
  d.total_hours,
  g.exposure_grain,
  d.method_note
from curated.team_exposure_denominators d
left join lateral (
  select case when count(distinct e.grain) = 1 then min(e.grain) else 'mixed' end as exposure_grain
  from curated.exposure e
  where e.curated_build_id = d.curated_build_id
    and e.eligibility_status = 'included_pending_protocol'
) g on true;

-- Team/build setting metrics. This is the versioned successor to
-- analysis.setting_split_v1; V1 remains frozen and rate-free.
create view analysis.setting_split_v2
with (security_invoker = true) as
with grouped as (
  select
    c.curated_build_id,
    c.team_key,
    c.season,
    c.setting_code,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_v2 c
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, c.setting_code
)
select
  g.curated_build_id,
  g.team_key,
  g.season,
  g.setting_code,
  g.time_loss_injuries,
  g.days_lost,
  case g.setting_code
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.match_hours)
    when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.training_hours)
    else null
  end as incidence_per_1000h,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(g.days_lost, e.match_hours)
    when 'training' then analysis.rate_per_1000_v1(g.days_lost, e.training_hours)
    else null
  end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_v2 e
  on e.curated_build_id = g.curated_build_id
 and e.team_key = g.team_key
 and e.season = g.season;

-- Full UI injury dimensions. Each time-loss record contributes one body,
-- one tissue/pathology, and one body+tissue profile row, at both `all` and
-- its source setting. Rates are always recomputed from the appropriate
-- denominator; category rates are never added or averaged.
create view analysis.injury_profiles_v2
with (security_invoker = true) as
with grouped as (
  select
    c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label,
    s.setting_code,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_v2 c
  cross join lateral (values
    ('body_location'::text, c.body_location_code, c.body_location_label),
    ('injury_type'::text, c.injury_type_code, c.injury_type_label),
    (
      'injury_profile'::text,
      c.body_location_code || '__' || c.injury_type_code,
      c.body_location_label || ' · ' || c.injury_type_label
    )
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
           d.dimension, d.code, d.label, s.setting_code
)
select
  g.curated_build_id,
  g.team_key,
  g.season,
  g.dimension,
  g.code,
  g.label,
  g.setting_code,
  g.time_loss_injuries,
  g.days_lost,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  case g.setting_code
    when 'all' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.total_hours)
    when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.match_hours)
    when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.training_hours)
    else null
  end as incidence_per_1000h,
  case g.setting_code
    when 'all' then analysis.rate_per_1000_v1(g.days_lost, e.total_hours)
    when 'match' then analysis.rate_per_1000_v1(g.days_lost, e.match_hours)
    when 'training' then analysis.rate_per_1000_v1(g.days_lost, e.training_hours)
    else null
  end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_v2 e
  on e.curated_build_id = g.curated_build_id
 and e.team_key = g.team_key
 and e.season = g.season;

create view analysis.body_locations_v2
with (security_invoker = true) as
with grouped as (
  select
    c.curated_build_id, c.team_key, c.season,
    c.body_location_code, c.body_location_label,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_v2 c
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
           c.body_location_code, c.body_location_label
)
select
  g.*,
  analysis.rate_per_1000_v1(g.time_loss_injuries, e.total_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost, e.total_hours) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days,
  case g.body_location_code
    when 'head' then 1 when 'neck' then 2 when 'shoulder' then 3
    when 'upper_arm' then 4 when 'elbow' then 5 when 'forearm' then 6
    when 'wrist' then 7 when 'hand' then 8 when 'chest' then 9
    when 'thoracic_spine' then 10 when 'abdomen' then 11 when 'lumbosacral' then 12
    when 'hip_groin' then 13 when 'thigh' then 14 when 'knee' then 15
    when 'lower_leg' then 16 when 'ankle' then 17 when 'foot' then 18
    when 'multiple' then 19 when 'unspecified' then 20 else 21
  end as anatomical_order
from grouped g
join analysis.exposure_hours_by_build_v2 e
  on e.curated_build_id = g.curated_build_id
 and e.team_key = g.team_key and e.season = g.season;

create view analysis.injury_types_v2
with (security_invoker = true) as
with grouped as (
  select
    c.curated_build_id, c.team_key, c.season,
    c.injury_type_code, c.injury_type_label,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_v2 c
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
           c.injury_type_code, c.injury_type_label
)
select
  g.*,
  analysis.rate_per_1000_v1(g.time_loss_injuries, e.total_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost, e.total_hours) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_v2 e
  on e.curated_build_id = g.curated_build_id
 and e.team_key = g.team_key and e.season = g.season;

-- Accepted source: an approved, complete V1 full-dashboard release for a
-- declared reporting.teams roster member. Headline-only/partial releases and
-- other analysis versions cannot enter the bundle.
create view analysis.accepted_team_release_candidates_v2
with (security_invoker = true) as
select
  rc.team_key,
  rc.season,
  rc.release_id as team_release_id,
  rc.curated_build_id,
  rc.generated_at,
  r.approved_at,
  r.created_at as release_created_at
from reporting.release_context rc
join reporting.aggregate_releases r on r.id = rc.release_id
join reporting.teams roster on roster.team_key = rc.team_key
join curated.builds b
  on b.id = rc.curated_build_id
 and b.team_key = rc.team_key
 and b.season = rc.season
where r.status = 'approved'
  and rc.analysis_view_version = 'v1'
  and (
    select count(distinct rows.section)
    from reporting.release_table_rows rows
    where rows.release_id = rc.release_id
      and rows.section in (
        'headline', 'setting_split', 'monthly', 'body_locations',
        'injury_types', 'severity_distribution'
      )
  ) = 6;

-- Exactly one latest accepted full-dashboard release per roster team/season.
create view analysis.league_member_releases_v2
with (security_invoker = true) as
select distinct on (c.team_key, c.season)
  c.team_key, c.season, c.team_release_id, c.curated_build_id, c.generated_at
from analysis.accepted_team_release_candidates_v2 c
order by c.team_key, c.season,
         c.approved_at desc nulls last, c.release_created_at desc, c.team_release_id desc;

create view analysis.league_member_gate_v2
with (security_invoker = true) as
select
  m.season,
  count(*)::integer as member_count,
  count(*) = 16
    and (select count(*) from reporting.teams) = 16
    and bool_and(e.match_hours = e.matches_played * 20.0)
    and bool_and(e.total_hours = e.match_hours + e.training_hours)
    and (
      m.season <> '2024-25'
      or (
        sum(e.matches_played) = 302
        and sum(e.match_hours) = 6040.0
      )
    ) as is_complete
from analysis.league_member_releases_v2 m
join analysis.exposure_hours_by_build_v2 e
  on e.curated_build_id = m.curated_build_id
 and e.team_key = m.team_key and e.season = m.season
group by m.season;

create view analysis.league_headline_v2
with (security_invoker = true) as
with cohort as (
  select c.*
  from analysis.injury_cohort_by_build_v2 c
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = c.curated_build_id
   and m.team_key = c.team_key and m.season = c.season
), injury_agg as (
  select
    season,
    count(*) as recorded_injuries,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost,
    avg(days_lost) filter (where is_time_loss) as mean_severity_days,
    percentile_cont(0.5) within group (order by days_lost) filter (where is_time_loss) as median_severity_days
  from cohort
  group by season
), exposure_agg as (
  select
    e.season,
    sum(e.total_hours) as exposure_hours,
    sum(e.match_hours) as match_exposure_hours,
    sum(e.training_hours) as training_exposure_hours,
    sum(e.matches_played) as team_fixture_participations
  from analysis.exposure_hours_by_build_v2 e
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = e.curated_build_id
   and m.team_key = e.team_key and m.season = e.season
  group by e.season
)
select
  i.season,
  g.member_count,
  i.recorded_injuries,
  i.time_loss_injuries,
  i.days_lost,
  e.exposure_hours,
  e.match_exposure_hours,
  e.training_exposure_hours,
  e.team_fixture_participations,
  analysis.rate_per_1000_v1(i.time_loss_injuries, e.exposure_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(i.days_lost, e.exposure_hours) as burden_per_1000h,
  i.mean_severity_days,
  i.median_severity_days
from injury_agg i
join exposure_agg e using (season)
join analysis.league_member_gate_v2 g using (season)
where g.is_complete;

create view analysis.league_setting_split_v2
with (security_invoker = true) as
with grouped as (
  select
    s.season,
    s.setting_code,
    sum(s.time_loss_injuries) as time_loss_injuries,
    sum(s.days_lost) as days_lost
  from analysis.setting_split_v2 s
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = s.curated_build_id
   and m.team_key = s.team_key and m.season = s.season
  join analysis.league_member_gate_v2 gate on gate.season = s.season and gate.is_complete
  group by s.season, s.setting_code
)
select
  g.season,
  g.setting_code,
  g.time_loss_injuries,
  g.days_lost,
  case g.setting_code
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries, h.match_exposure_hours)
    when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries, h.training_exposure_hours)
    else null
  end as incidence_per_1000h,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(g.days_lost, h.match_exposure_hours)
    when 'training' then analysis.rate_per_1000_v1(g.days_lost, h.training_exposure_hours)
    else null
  end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g
join analysis.league_headline_v2 h using (season);

create view analysis.league_body_locations_v2
with (security_invoker = true) as
with grouped as (
  select
    c.season,
    c.body_location_code,
    c.body_location_label,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_v2 c
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = c.curated_build_id
   and m.team_key = c.team_key and m.season = c.season
  join analysis.league_member_gate_v2 gate on gate.season = c.season and gate.is_complete
  where c.is_time_loss
  group by c.season, c.body_location_code, c.body_location_label
)
select
  g.*,
  analysis.rate_per_1000_v1(g.time_loss_injuries, h.exposure_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost, h.exposure_hours) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days,
  case g.body_location_code
    when 'head' then 1 when 'neck' then 2 when 'shoulder' then 3
    when 'upper_arm' then 4 when 'elbow' then 5 when 'forearm' then 6
    when 'wrist' then 7 when 'hand' then 8 when 'chest' then 9
    when 'thoracic_spine' then 10 when 'abdomen' then 11 when 'lumbosacral' then 12
    when 'hip_groin' then 13 when 'thigh' then 14 when 'knee' then 15
    when 'lower_leg' then 16 when 'ankle' then 17 when 'foot' then 18
    when 'multiple' then 19 when 'unspecified' then 20 else 21
  end as anatomical_order
from grouped g
join analysis.league_headline_v2 h using (season);

create view analysis.league_injury_types_v2
with (security_invoker = true) as
with grouped as (
  select
    c.season,
    c.injury_type_code,
    c.injury_type_label,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_v2 c
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = c.curated_build_id
   and m.team_key = c.team_key and m.season = c.season
  join analysis.league_member_gate_v2 gate on gate.season = c.season and gate.is_complete
  where c.is_time_loss
  group by c.season, c.injury_type_code, c.injury_type_label
)
select
  g.*,
  analysis.rate_per_1000_v1(g.time_loss_injuries, h.exposure_hours) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost, h.exposure_hours) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g
join analysis.league_headline_v2 h using (season);

create view analysis.league_injury_profiles_v2
with (security_invoker = true) as
with grouped as (
  select
    p.season, p.dimension, p.code, p.label, p.setting_code,
    sum(p.time_loss_injuries) as time_loss_injuries,
    sum(p.days_lost) as days_lost
  from analysis.injury_profiles_v2 p
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = p.curated_build_id
   and m.team_key = p.team_key and m.season = p.season
  join analysis.league_member_gate_v2 gate on gate.season = p.season and gate.is_complete
  group by p.season, p.dimension, p.code, p.label, p.setting_code
)
select
  g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  case g.setting_code
    when 'all' then analysis.rate_per_1000_v1(g.time_loss_injuries, h.exposure_hours)
    when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries, h.match_exposure_hours)
    when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries, h.training_exposure_hours)
    else null
  end as incidence_per_1000h,
  case g.setting_code
    when 'all' then analysis.rate_per_1000_v1(g.days_lost, h.exposure_hours)
    when 'match' then analysis.rate_per_1000_v1(g.days_lost, h.match_exposure_hours)
    when 'training' then analysis.rate_per_1000_v1(g.days_lost, h.training_exposure_hours)
    else null
  end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g
join analysis.league_headline_v2 h using (season);

create view analysis.league_monthly_v2
with (security_invoker = true) as
with exposure_month as (
  select
    e.season,
    date_trunc('month', coalesce(e.session_date, e.week_start_date))::date as month_start,
    sum(e.minutes_clean) / 60 as exposure_hours,
    sum(e.distance_m_clean) / 1000 as distance_km
  from curated.exposure e
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = e.curated_build_id
   and m.team_key = e.team_key and m.season = e.season
  join analysis.league_member_gate_v2 gate on gate.season = e.season and gate.is_complete
  where e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date) is not null
  group by e.season, date_trunc('month', coalesce(e.session_date, e.week_start_date))
), injury_month as (
  select
    c.season,
    date_trunc('month', c.date_injured)::date as month_start,
    count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_v2 c
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = c.curated_build_id
   and m.team_key = c.team_key and m.season = c.season
  join analysis.league_member_gate_v2 gate on gate.season = c.season and gate.is_complete
  where c.is_time_loss
  group by c.season, date_trunc('month', c.date_injured)
), months as (
  select season, month_start from exposure_month
  union
  select season, month_start from injury_month
)
select
  m.season,
  m.month_start,
  to_char(m.month_start, 'Mon YYYY') as month_label,
  coalesce(e.exposure_hours, 0) as exposure_hours,
  coalesce(e.distance_km, 0) as distance_km,
  coalesce(i.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(i.days_lost, 0) as days_lost,
  analysis.rate_per_1000_v1(coalesce(i.time_loss_injuries, 0), coalesce(e.exposure_hours, 0)) as incidence_per_1000h,
  analysis.rate_per_1000_v1(coalesce(i.days_lost, 0), coalesce(e.exposure_hours, 0)) as burden_per_1000h
from months m
left join exposure_month e using (season, month_start)
left join injury_month i using (season, month_start);

create view analysis.league_severity_distribution_v2
with (security_invoker = true) as
select
  c.season,
  c.severity_code,
  c.severity_label,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  case c.severity_code
    when 'zero_days_medical_attention_only' then 0 when 'one_day' then 1
    when 'two_to_three_days' then 2 when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4 when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.injury_cohort_by_build_v2 c
join analysis.league_member_releases_v2 m
  on m.curated_build_id = c.curated_build_id
 and m.team_key = c.team_key and m.season = c.season
join analysis.league_member_gate_v2 gate on gate.season = c.season and gate.is_complete
group by c.season, c.severity_code, c.severity_label;

create view analysis.league_coverage_v2
with (security_invoker = true) as
with member_exposure as (
  select
    e.team_key, e.season, e.curated_build_id,
    count(*) as exposure_rows,
    count(distinct nullif(e.player_uid, '')) as exposed_players,
    count(distinct case when e.grain = 'weekly' then e.week_start_date end) as weeks,
    count(distinct coalesce(e.session_date, e.week_start_date)) as exposure_periods,
    sum(e.minutes_clean) / 60 as exposure_hours,
    sum(e.distance_m_clean) / 1000 as distance_km,
    min(coalesce(e.session_date, e.week_start_date)) as coverage_start,
    max(coalesce(e.session_date, e.week_start_date))
      + case when count(distinct e.grain) = 1 and min(e.grain) = 'weekly' then 6 else 0 end
      as coverage_end,
    case when count(distinct e.grain) = 1 then min(e.grain) else 'mixed' end as exposure_grain
  from curated.exposure e
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = e.curated_build_id
   and m.team_key = e.team_key and m.season = e.season
  where e.eligibility_status = 'included_pending_protocol'
  group by e.team_key, e.season, e.curated_build_id
), grain_counts as (
  select season, jsonb_object_agg(exposure_grain, n) as exposure_grain_counts
  from (
    select season, exposure_grain, count(*) as n
    from member_exposure group by season, exposure_grain
  ) q
  group by season
), window_counts as (
  select
    season,
    jsonb_agg(jsonb_build_object(
      'start', coverage_start,
      'end', coverage_end,
      'teams', teams
    ) order by coverage_start, coverage_end) as coverage_windows
  from (
    select season, coverage_start, coverage_end, count(*) as teams
    from member_exposure
    group by season, coverage_start, coverage_end
  ) q
  group by season
)
select
  e.season,
  count(*)::integer as member_count,
  count(distinct (e.coverage_start, e.coverage_end))::integer as distinct_coverage_windows,
  min(e.coverage_start) as earliest_coverage_start,
  max(e.coverage_start) as latest_coverage_start,
  min(e.coverage_end) as earliest_coverage_end,
  max(e.coverage_end) as latest_coverage_end,
  sum(e.exposure_rows) as exposure_rows,
  sum(e.exposed_players) as exposed_players,
  sum(e.weeks) as weeks,
  sum(e.exposure_periods) as exposure_periods,
  sum(e.exposure_hours) as exposure_hours,
  sum(e.distance_km) as distance_km,
  g.exposure_grain_counts,
  w.coverage_windows,
  20.0::numeric as player_hours_per_team_fixture,
  'all_registered_season_fixtures_15_players_x_80_minutes_div_60'::text as match_exposure_decision
from member_exposure e
join analysis.league_member_gate_v2 gate on gate.season = e.season and gate.is_complete
join grain_counts g on g.season = e.season
join window_counts w on w.season = e.season
group by e.season, g.exposure_grain_counts, w.coverage_windows;

-- Exactly 16 team payload candidates, each bound to the latest accepted team
-- release and its immutable curated build. These rows are inputs to the bundle
-- release transaction; the public reporting view never reads them dynamically.
create view analysis.team_dashboard_payload_v2
with (security_invoker = true) as
select
  m.team_key,
  m.season,
  m.team_release_id,
  m.curated_build_id,
  jsonb_build_object(
    'generated_at', d.generated_at,
    'team', d.team,
    'season', d.season,
    'analysis_window', d.analysis_window,
    'method', d.method,
    'coverage', d.coverage || jsonb_build_object(
      'hours', x.total_hours,
      'match_hours', x.match_hours,
      'training_hours', x.training_hours
    ),
    'headline', d.headline,
    'setting_split', d.setting_split,
    'setting_metrics', coalesce(s.docs, '[]'::jsonb),
    'monthly', d.monthly,
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', d.severity_distribution,
    'prior_season', d.prior_season,
    'limitations', d.limitations
  ) as dashboard
from analysis.league_member_releases_v2 m
join analysis.league_member_gate_v2 gate on gate.season = m.season and gate.is_complete
join reporting.latest_team_dashboard d
  on d.release_id = m.team_release_id
 and d.team_key = m.team_key and d.season = m.season
join analysis.exposure_hours_by_build_v2 x
  on x.curated_build_id = m.curated_build_id
 and x.team_key = m.team_key and x.season = m.season
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'setting', v.setting_code,
    'label', case v.setting_code
      when 'match' then 'Match' when 'training' then 'Training' else 'Unknown'
    end,
    'time_loss_injuries', v.time_loss_injuries,
    'days_lost', v.days_lost,
    'exposure_hours', v.exposure_hours,
    'incidence_per_1000h', v.incidence_per_1000h,
    'burden_per_1000h', v.burden_per_1000h,
    'mean_severity_days', v.mean_severity_days
  ) order by case v.setting_code when 'match' then 1 when 'training' then 2 else 3 end) as docs
  from analysis.setting_split_v2 v
  where v.curated_build_id = m.curated_build_id
    and v.team_key = m.team_key and v.season = m.season
) s on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'key', v.body_location_code,
    'label', v.body_location_label,
    'time_loss_injuries', v.time_loss_injuries,
    'days_lost', v.days_lost,
    'incidence_per_1000h', v.incidence_per_1000h,
    'burden_per_1000h', v.burden_per_1000h,
    'mean_severity_days', v.mean_severity_days
  ) order by v.anatomical_order, v.body_location_code) as docs
  from analysis.body_locations_v2 v
  where v.curated_build_id = m.curated_build_id
    and v.team_key = m.team_key and v.season = m.season
) body on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'key', v.injury_type_code,
    'label', v.injury_type_label,
    'time_loss_injuries', v.time_loss_injuries,
    'days_lost', v.days_lost,
    'incidence_per_1000h', v.incidence_per_1000h,
    'burden_per_1000h', v.burden_per_1000h,
    'mean_severity_days', v.mean_severity_days
  ) order by v.time_loss_injuries desc, v.days_lost desc, v.injury_type_code) as docs
  from analysis.injury_types_v2 v
  where v.curated_build_id = m.curated_build_id
    and v.team_key = m.team_key and v.season = m.season
) types on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'dimension', v.dimension,
    'code', v.code,
    'label', v.label,
    'setting', v.setting_code,
    'time_loss_injuries', v.time_loss_injuries,
    'days_lost', v.days_lost,
    'exposure_hours', v.exposure_hours,
    'incidence_per_1000h', v.incidence_per_1000h,
    'burden_per_1000h', v.burden_per_1000h,
    'mean_severity_days', v.mean_severity_days
  ) order by v.dimension, v.setting_code, v.time_loss_injuries desc, v.days_lost desc, v.code) as docs
  from analysis.injury_profiles_v2 v
  where v.curated_build_id = m.curated_build_id
    and v.team_key = m.team_key and v.season = m.season
) profiles on true;

-- One dynamic, deterministic document per complete season. The release command
-- snapshots this exact JSON; it never reconstructs formulas in Python/TypeScript.
create view analysis.league_dashboard_payload_v2
with (security_invoker = true) as
select
  h.season,
  jsonb_build_object(
    'generated_at', (
      select max(m.generated_at)
      from analysis.league_member_releases_v2 m
      where m.season = h.season
    ),
    'team', 'URC Overall',
    'season', h.season,
    'analysis_window', jsonb_build_object(
      'start', c.earliest_coverage_start,
      'end', c.latest_coverage_end,
      'basis', 'Pooled across 16 approved team-specific coverage windows; exact windows are retained in coverage.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Mean severity = pooled days lost / pooled time-loss injuries.',
      'Match exposure = all registered fixtures × 15 players × 80 minutes / 60 per team.',
      'Training exposure = total cleaned exposure minus match exposure.',
      'IOC-aligned body-location and tissue/pathology categories use the accepted V2 mappings.'
    ),
    'coverage', jsonb_build_object(
      'exposure_rows', c.exposure_rows,
      'exposed_players', c.exposed_players,
      'weeks', c.weeks,
      'exposure_periods', c.exposure_periods,
      'exposure_grain', 'mixed',
      'hours', h.exposure_hours,
      'match_hours', h.match_exposure_hours,
      'training_hours', h.training_exposure_hours,
      'distance_km', c.distance_km,
      'teams_included', c.member_count,
      'coverage_windows', c.coverage_windows,
      'included_exposure_status', 'included'
    ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', h.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in each team coverage window)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', h.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', h.incidence_per_1000h, 'unit', 'per 1,000 player-hours',
        'numerator', h.time_loss_injuries, 'denominator', h.exposure_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', h.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', h.days_lost, 'denominator', h.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', h.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', h.burden_per_1000h, 'unit', 'days lost per 1,000 player-hours',
        'numerator', h.days_lost, 'denominator', h.exposure_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', s.setting_code, 'label', initcap(s.setting_code),
        'time_loss_injuries', s.time_loss_injuries, 'days_lost', s.days_lost,
        'exposure_hours', s.exposure_hours,
        'incidence_per_1000h', s.incidence_per_1000h,
        'burden_per_1000h', s.burden_per_1000h,
        'mean_severity_days', s.mean_severity_days
      ) order by case s.setting_code when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.league_setting_split_v2 s where s.season = h.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', s.setting_code, 'label', initcap(s.setting_code),
        'time_loss_injuries', s.time_loss_injuries, 'days_lost', s.days_lost,
        'exposure_hours', s.exposure_hours,
        'incidence_per_1000h', s.incidence_per_1000h,
        'burden_per_1000h', s.burden_per_1000h,
        'mean_severity_days', s.mean_severity_days
      ) order by case s.setting_code when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.league_setting_split_v2 s where s.season = h.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', m.month_label, 'exposure_hours', m.exposure_hours,
        'distance_km', m.distance_km, 'time_loss_injuries', m.time_loss_injuries,
        'days_lost', m.days_lost, 'incidence_per_1000h', m.incidence_per_1000h,
        'burden_per_1000h', m.burden_per_1000h
      ) order by m.month_start)
      from analysis.league_monthly_v2 m where m.season = h.season
    ), '[]'::jsonb),
    'body_locations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', b.body_location_code, 'label', b.body_location_label,
        'time_loss_injuries', b.time_loss_injuries, 'days_lost', b.days_lost,
        'incidence_per_1000h', b.incidence_per_1000h,
        'burden_per_1000h', b.burden_per_1000h,
        'mean_severity_days', b.mean_severity_days
      ) order by b.anatomical_order, b.body_location_code)
      from analysis.league_body_locations_v2 b where b.season = h.season
    ), '[]'::jsonb),
    'injury_types', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', t.injury_type_code, 'label', t.injury_type_label,
        'time_loss_injuries', t.time_loss_injuries, 'days_lost', t.days_lost,
        'incidence_per_1000h', t.incidence_per_1000h,
        'burden_per_1000h', t.burden_per_1000h,
        'mean_severity_days', t.mean_severity_days
      ) order by t.time_loss_injuries desc, t.days_lost desc, t.injury_type_code)
      from analysis.league_injury_types_v2 t where t.season = h.season
    ), '[]'::jsonb),
    'injury_profiles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dimension', p.dimension, 'code', p.code, 'label', p.label,
        'setting', p.setting_code, 'time_loss_injuries', p.time_loss_injuries,
        'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
        'incidence_per_1000h', p.incidence_per_1000h,
        'burden_per_1000h', p.burden_per_1000h,
        'mean_severity_days', p.mean_severity_days
      ) order by p.dimension, p.setting_code, p.time_loss_injuries desc, p.days_lost desc, p.code)
      from analysis.league_injury_profiles_v2 p where p.season = h.season
    ), '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', s.severity_code, 'label', s.severity_label,
        'recorded_injuries', s.recorded_injuries,
        'time_loss_injuries', s.time_loss_injuries, 'days_lost', s.days_lost
      ) order by s.band_order)
      from analysis.league_severity_distribution_v2 s where s.season = h.season
    ), '[]'::jsonb),
    'prior_season', jsonb_build_object(
      'season', '2023-24', 'status', 'pending',
      'note', 'No prior-season league injury and exposure denominator pair has passed the V2 workflow.'
    ),
    'limitations', jsonb_build_array(
      'Team coverage is not uniform; the pooled estimate retains each approved team-specific window.',
      'Unknown-setting injuries are included in overall metrics but have no match/training rate.',
      'Exact diagnoses are not inferred; injury profiles combine controlled IOC body and tissue/pathology categories.'
    )
  ) as dashboard
from analysis.league_headline_v2 h
join analysis.league_coverage_v2 c using (season);

-- One approved bundle snapshots the league payload and all 16 team V2
-- payloads together. Hashes are generated by PostgreSQL from canonical jsonb
-- text; callers cannot supply a decorative checksum.
create table reporting.league_release_context_v2 (
  release_id uuid primary key references reporting.aggregate_releases(id),
  season text not null,
  analysis_version text not null check (analysis_version = 'v2') default 'v2',
  generated_at timestamptz not null,
  expected_member_count integer not null check (expected_member_count = 16) default 16,
  match_exposure_decision text not null check (
    match_exposure_decision = 'all_registered_season_fixtures_15_players_x_80_minutes_div_60'
  ),
  decision_reviewer text not null check (decision_reviewer = 'Abdel Babiker'),
  decision_recorded_at date not null check (decision_recorded_at = date '2026-07-14'),
  created_at timestamptz not null default now()
);

create table reporting.league_release_members_v2 (
  release_id uuid not null references reporting.league_release_context_v2(release_id),
  team_key text not null references reporting.teams(team_key),
  team_release_id uuid not null references reporting.aggregate_releases(id),
  curated_build_id uuid not null references curated.builds(id),
  primary key (release_id, team_key),
  unique (release_id, team_release_id),
  unique (release_id, curated_build_id)
);

create table reporting.league_release_payloads_v2 (
  release_id uuid primary key references reporting.league_release_context_v2(release_id),
  dashboard_payload jsonb not null check (jsonb_typeof(dashboard_payload) = 'object'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create table reporting.team_dashboard_payloads_v2 (
  bundle_release_id uuid not null references reporting.league_release_context_v2(release_id),
  team_key text not null references reporting.teams(team_key),
  team_release_id uuid not null references reporting.aggregate_releases(id),
  curated_build_id uuid not null references curated.builds(id),
  dashboard_payload jsonb not null check (jsonb_typeof(dashboard_payload) = 'object'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (bundle_release_id, team_key),
  unique (bundle_release_id, team_release_id),
  unique (bundle_release_id, curated_build_id)
);

alter table reporting.league_release_context_v2 enable row level security;
alter table reporting.league_release_members_v2 enable row level security;
alter table reporting.league_release_payloads_v2 enable row level security;
alter table reporting.team_dashboard_payloads_v2 enable row level security;

create function reporting.set_dashboard_v2_payload_hash()
returns trigger
language plpgsql
as $$
begin
  new.payload_sha256 := encode(
    digest(convert_to(new.dashboard_payload::text, 'UTF8'), 'sha256'),
    'hex'
  );
  return new;
end;
$$;

revoke execute on function reporting.set_dashboard_v2_payload_hash() from public;

create trigger league_release_payloads_v2_hash
before insert on reporting.league_release_payloads_v2
for each row execute function reporting.set_dashboard_v2_payload_hash();
create trigger team_dashboard_payloads_v2_hash
before insert on reporting.team_dashboard_payloads_v2
for each row execute function reporting.set_dashboard_v2_payload_hash();

create function reporting.validate_league_dashboard_v2_candidate()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from reporting.league_release_context_v2 context
    join analysis.league_dashboard_payload_v2 candidate
      on candidate.season = context.season
     and candidate.dashboard = new.dashboard_payload
    where context.release_id = new.release_id
  ) then
    raise exception 'league dashboard snapshot must equal the build-pinned analytical candidate';
  end if;
  return new;
end;
$$;

create function reporting.validate_team_dashboard_v2_candidates()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_payload_v2 candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.dashboard = payload.dashboard_payload
    where candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its build-pinned analytical candidate';
  end if;
  return null;
end;
$$;

revoke execute on function reporting.validate_league_dashboard_v2_candidate() from public;
revoke execute on function reporting.validate_team_dashboard_v2_candidates() from public;

create trigger league_release_payloads_v2_candidate
after insert on reporting.league_release_payloads_v2
for each row execute function reporting.validate_league_dashboard_v2_candidate();
create trigger team_dashboard_payloads_v2_candidates
after insert on reporting.team_dashboard_payloads_v2
referencing new table as new_team_dashboard_v2_payloads
for each statement execute function reporting.validate_team_dashboard_v2_candidates();

create function reporting.reject_dashboard_v2_snapshot_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is immutable; create a new dashboard bundle release', tg_table_name;
end;
$$;

revoke execute on function reporting.reject_dashboard_v2_snapshot_mutation() from public;

create trigger league_release_context_v2_immutable
before update or delete on reporting.league_release_context_v2
for each row execute function reporting.reject_dashboard_v2_snapshot_mutation();
create trigger league_release_members_v2_immutable
before update or delete on reporting.league_release_members_v2
for each row execute function reporting.reject_dashboard_v2_snapshot_mutation();
create trigger league_release_payloads_v2_immutable
before update or delete on reporting.league_release_payloads_v2
for each row execute function reporting.reject_dashboard_v2_snapshot_mutation();
create trigger team_dashboard_payloads_v2_immutable
before update or delete on reporting.team_dashboard_payloads_v2
for each row execute function reporting.reject_dashboard_v2_snapshot_mutation();

-- Private visibility gate shared by both public projections. It re-verifies
-- the exact roster, accepted V1 member releases, bundle snapshot identities,
-- and approved denominator identities before exposing a bundle.
create view reporting.latest_approved_dashboard_bundle_v2
with (security_invoker = false, security_barrier = true) as
select c.release_id, c.season
from reporting.league_release_context_v2 c
join reporting.aggregate_releases r on r.id = c.release_id and r.status = 'approved'
join reporting.league_release_payloads_v2 league_payload on league_payload.release_id = c.release_id
where (
  select count(*) from reporting.league_release_members_v2 m
  where m.release_id = c.release_id
) = 16
  and (
    select count(*) from reporting.team_dashboard_payloads_v2 p
    where p.bundle_release_id = c.release_id
  ) = 16
  and (select count(*) from reporting.teams) = 16
  and not exists (
    select 1 from reporting.teams roster
    where not exists (
      select 1 from reporting.league_release_members_v2 m
      where m.release_id = c.release_id and m.team_key = roster.team_key
    )
  )
  and not exists (
    select 1
    from reporting.league_release_members_v2 m
    where m.release_id = c.release_id
      and not exists (
        select 1 from analysis.league_member_releases_v2 current_member
        where current_member.season = c.season
          and current_member.team_key = m.team_key
          and current_member.team_release_id = m.team_release_id
          and current_member.curated_build_id = m.curated_build_id
      )
  )
  and not exists (
    select 1 from analysis.league_member_releases_v2 current_member
    where current_member.season = c.season
      and not exists (
        select 1 from reporting.league_release_members_v2 m
        where m.release_id = c.release_id
          and m.team_key = current_member.team_key
          and m.team_release_id = current_member.team_release_id
          and m.curated_build_id = current_member.curated_build_id
      )
  )
  and not exists (
    select 1
    from reporting.league_release_members_v2 m
    where m.release_id = c.release_id
      and not exists (
        select 1
        from reporting.release_context team_context
        join analysis.exposure_hours_by_build_v2 e
          on e.curated_build_id = team_context.curated_build_id
         and e.team_key = team_context.team_key and e.season = team_context.season
        where team_context.release_id = m.team_release_id
          and team_context.team_key = m.team_key
          and team_context.season = c.season
          and team_context.curated_build_id = m.curated_build_id
          and team_context.analysis_view_version = 'v1'
          and e.match_hours = e.matches_played * 20.0
          and e.total_hours = e.match_hours + e.training_hours
          and (
            select count(distinct rows.section)
            from reporting.release_table_rows rows
            where rows.release_id = team_context.release_id
              and rows.section in (
                'headline', 'setting_split', 'monthly', 'body_locations',
                'injury_types', 'severity_distribution'
              )
          ) = 6
      )
  )
  and not exists (
    select 1
    from reporting.league_release_members_v2 m
    where m.release_id = c.release_id
      and not exists (
        select 1
        from reporting.team_dashboard_payloads_v2 p
        where p.bundle_release_id = m.release_id
          and p.team_key = m.team_key
          and p.team_release_id = m.team_release_id
          and p.curated_build_id = m.curated_build_id
      )
  )
  and (
    c.season <> '2024-25'
    or (
      select sum(e.matches_played) = 302 and sum(e.match_hours) = 6040.0
      from reporting.league_release_members_v2 m
      join analysis.exposure_hours_by_build_v2 e
        on e.curated_build_id = m.curated_build_id
       and e.team_key = m.team_key and e.season = c.season
      where m.release_id = c.release_id
    )
  )
  and c.release_id = (
    select c2.release_id
    from reporting.league_release_context_v2 c2
    join reporting.aggregate_releases r2 on r2.id = c2.release_id
    where c2.season = c.season and r2.status = 'approved'
    order by r2.approved_at desc nulls last, r2.created_at desc, r2.id desc
    limit 1
  );

-- Explicit allowlists: arbitrary keys in a stored payload never cross the
-- web_reader boundary.
create view reporting.latest_league_dashboard_v2
with (security_invoker = false, security_barrier = true) as
select
  b.season,
  (p.dashboard_payload ->> 'team')::text as team,
  (p.dashboard_payload ->> 'generated_at')::timestamptz as generated_at,
  p.dashboard_payload -> 'analysis_window' as analysis_window,
  p.dashboard_payload -> 'method' as method,
  p.dashboard_payload -> 'coverage' as coverage,
  p.dashboard_payload -> 'headline' as headline,
  p.dashboard_payload -> 'setting_split' as setting_split,
  p.dashboard_payload -> 'setting_metrics' as setting_metrics,
  p.dashboard_payload -> 'monthly' as monthly,
  p.dashboard_payload -> 'body_locations' as body_locations,
  p.dashboard_payload -> 'injury_types' as injury_types,
  p.dashboard_payload -> 'injury_profiles' as injury_profiles,
  p.dashboard_payload -> 'severity_distribution' as severity_distribution,
  p.dashboard_payload -> 'prior_season' as prior_season,
  p.dashboard_payload -> 'limitations' as limitations
from reporting.latest_approved_dashboard_bundle_v2 b
join reporting.league_release_payloads_v2 p on p.release_id = b.release_id;

create view reporting.latest_team_dashboard_v2
with (security_invoker = false, security_barrier = true) as
select
  p.team_key,
  b.season,
  (p.dashboard_payload ->> 'team')::text as team,
  (p.dashboard_payload ->> 'generated_at')::timestamptz as generated_at,
  p.dashboard_payload -> 'analysis_window' as analysis_window,
  p.dashboard_payload -> 'method' as method,
  p.dashboard_payload -> 'coverage' as coverage,
  p.dashboard_payload -> 'headline' as headline,
  p.dashboard_payload -> 'setting_split' as setting_split,
  p.dashboard_payload -> 'setting_metrics' as setting_metrics,
  p.dashboard_payload -> 'monthly' as monthly,
  p.dashboard_payload -> 'body_locations' as body_locations,
  p.dashboard_payload -> 'injury_types' as injury_types,
  p.dashboard_payload -> 'injury_profiles' as injury_profiles,
  p.dashboard_payload -> 'severity_distribution' as severity_distribution,
  p.dashboard_payload -> 'prior_season' as prior_season,
  p.dashboard_payload -> 'limitations' as limitations
from reporting.latest_approved_dashboard_bundle_v2 b
join reporting.team_dashboard_payloads_v2 p on p.bundle_release_id = b.release_id;

grant select on reporting.latest_league_dashboard_v2 to web_reader;
grant select on reporting.latest_team_dashboard_v2 to web_reader;

comment on view reporting.latest_league_dashboard_v2 is
  'Whitelisted fields from the latest approved immutable, denominator-verified 16-team V2 bundle.';
comment on view reporting.latest_team_dashboard_v2 is
  'Whitelisted fields from the 16 immutable team V2 payloads snapshotted with the latest approved league bundle.';
