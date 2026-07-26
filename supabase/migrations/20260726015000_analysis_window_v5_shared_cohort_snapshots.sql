-- Shared build-pinned V5 scientific cohorts.
--
-- These snapshots evaluate the accepted injury and exposure cohorts once.
-- The successor aggregate views preserve their original definitions and
-- consume only these shared rows, so every dashboard section reuses the same
-- build-pinned cohort without repeated lineage or semantic joins.

set transaction isolation level repeatable read;

create materialized view analysis.analysis_window_injury_cohort_v5_snapshot as
select *
from analysis.analysis_window_injury_cohort_v5
with no data;

create index analysis_window_injury_cohort_v5_snapshot_team
  on analysis.analysis_window_injury_cohort_v5_snapshot
  (season, team_key, curated_build_id);
create index analysis_window_injury_cohort_v5_snapshot_injury
  on analysis.analysis_window_injury_cohort_v5_snapshot (injury_id);

create materialized view analysis.analysis_window_reporting_classification_v5_snapshot as
select c.*
from analysis.lineage_reporting_classification_v1 c
join analysis.analysis_window_injury_cohort_v5_snapshot v5
  on v5.injury_id = c.injury_id
 and v5.curated_build_id = c.curated_build_id
 and v5.team_key = c.team_key
 and v5.season = c.season
with no data;

create index analysis_window_reporting_classification_v5_snapshot_team
  on analysis.analysis_window_reporting_classification_v5_snapshot
  (season, team_key, curated_build_id);
create index analysis_window_reporting_classification_v5_snapshot_injury
  on analysis.analysis_window_reporting_classification_v5_snapshot (injury_id);

create materialized view analysis.analysis_window_effective_exposure_cohort_v5_snapshot as
select *
from analysis.analysis_window_effective_exposure_cohort_v5
with no data;

create index analysis_window_effective_exposure_cohort_v5_snapshot_team
  on analysis.analysis_window_effective_exposure_cohort_v5_snapshot
  (season, team_key, curated_build_id, effective_eligibility_status);
create unique index analysis_window_effective_exposure_cohort_v5_snapshot_row
  on analysis.analysis_window_effective_exposure_cohort_v5_snapshot
  (exposure_id);

create or replace view analysis.exposure_hours_by_build_analysis_window_v5
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season,
    coalesce(sum(e.minutes_clean), 0) / 60 as total_hours,
    case when count(distinct e.reporting_grain) = 1
      then min(e.reporting_grain) else 'mixed' end as exposure_grain
  from analysis.analysis_window_effective_exposure_cohort_v5_snapshot e
  where e.effective_eligibility_status = 'included_pending_protocol'
  group by e.curated_build_id, e.team_key, e.season
), fixtures as (
  select f.season, teams.team_key, count(*)::integer as matches_played
  from curated.fixtures f
  join analysis.reporting_season_windows_v3 w
    on w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
   and w.season = f.season
  join analysis.accepted_analysis_window_cohort_rules_v5 accepted
    on accepted.cohort_view_version = w.cohort_view_version
   and accepted.season = w.season
  cross join lateral (values (f.home_team_key), (f.away_team_key))
    teams(team_key)
  where f.match_date between w.season_start and w.season_end
  group by f.season, teams.team_key
)
select e.curated_build_id, e.team_key, e.season,
  coalesce(f.matches_played, 0) as matches_played,
  coalesce(f.matches_played, 0) * 20.0 as match_hours,
  e.total_hours - coalesce(f.matches_played, 0) * 20.0 as training_hours,
  e.total_hours,
  e.exposure_grain,
  'analysis_window_v5_effective_exposure_and_registered_fixtures'::text
    as method_note
from exposure e
left join fixtures f using (team_key, season);

create or replace view analysis.analysis_window_team_summary_v5
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days
from analysis.analysis_window_injury_cohort_v5_snapshot c
group by c.curated_build_id, c.team_key, c.season;

create or replace view analysis.analysis_window_setting_split_v5
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, c.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.analysis_window_injury_cohort_v5_snapshot c
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, c.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create or replace view analysis.analysis_window_injury_profiles_v5
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.analysis_window_injury_cohort_v5_snapshot c
  cross join lateral (values
    ('body_location'::text, c.body_location_code, c.body_location_label),
    ('injury_type'::text, c.injury_type_code, c.injury_type_label),
    ('injury_profile'::text,
      c.body_location_code || '__' || c.injury_type_code,
      c.body_location_label || ' · ' || c.injury_type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create or replace view analysis.analysis_window_effective_injury_profiles_v5
with (security_invoker = true) as
with labelled as (
  select c.*,
    coalesce(bl.label,
      initcap(replace(c.effective_body_location_code, '_', ' '))) as body_label,
    coalesce(it.label,
      initcap(replace(c.effective_injury_type_code, '_', ' '))) as type_label
  from analysis.analysis_window_reporting_classification_v5_snapshot c
  left join curated.code_lists bl
    on bl.list_name = 'body_location'
   and bl.code = c.effective_body_location_code
  left join curated.code_lists it
    on it.list_name = 'injury_type'
   and it.code = c.effective_injury_type_code
), grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from labelled c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  cross join lateral (values
    ('body_location'::text, c.effective_body_location_code, c.body_label),
    ('injury_type'::text, c.effective_injury_type_code, c.type_label),
    ('injury_profile'::text,
      c.effective_body_location_code || '__' || c.effective_injury_type_code,
      c.body_label || ' · ' || c.type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create or replace view analysis.analysis_window_diagnosis_profiles_v5
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code as code, c.diagnosis_label as label,
    s.setting_code, count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.analysis_window_reporting_classification_v5_snapshot c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code, c.diagnosis_label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create or replace view analysis.analysis_window_monthly_v5
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season,
    date_trunc('month', e.effective_period_start)::date as month_start,
    sum(e.minutes_clean) / 60 as exposure_hours,
    sum(e.distance_m_clean) / 1000 as distance_km
  from analysis.analysis_window_effective_exposure_cohort_v5_snapshot e
  where e.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
    and e.effective_eligibility_status = 'included_pending_protocol'
  group by e.curated_build_id, e.team_key, e.season,
    date_trunc('month', e.effective_period_start)
), injuries as (
  select curated_build_id, team_key, season,
    date_trunc('month', date_injured)::date as month_start,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from analysis.analysis_window_injury_cohort_v5_snapshot
  where cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
    and date_injured is not null
  group by curated_build_id, team_key, season, date_trunc('month', date_injured)
), months as (
  select curated_build_id, team_key, season, month_start from exposure
  union
  select curated_build_id, team_key, season, month_start from injuries
)
select m.curated_build_id, m.team_key, m.season, m.month_start,
  to_char(m.month_start, 'Mon YYYY') as month_label,
  coalesce(e.exposure_hours, 0) as exposure_hours,
  coalesce(e.distance_km, 0) as distance_km,
  coalesce(i.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(i.days_lost, 0) as days_lost,
  analysis.rate_per_1000_v1(coalesce(i.time_loss_injuries, 0),
    coalesce(e.exposure_hours, 0)) as incidence_per_1000h,
  analysis.rate_per_1000_v1(coalesce(i.days_lost, 0),
    coalesce(e.exposure_hours, 0)) as burden_per_1000h
from months m
left join exposure e using (curated_build_id, team_key, season, month_start)
left join injuries i using (curated_build_id, team_key, season, month_start);

create or replace view analysis.analysis_window_severity_distribution_v5
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  case c.severity_code
    when 'zero_days_medical_attention_only' then 0
    when 'one_day' then 1
    when 'two_to_three_days' then 2
    when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4
    when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.analysis_window_injury_cohort_v5_snapshot c
group by c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label;

create or replace view analysis.analysis_window_league_summary_v5
with (security_invoker = true) as
with cohort as (
  select c.*
  from analysis.analysis_window_injury_cohort_v5_snapshot c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
), exposure as (
  select e.season,
    sum(e.total_hours) as exposure_hours,
    sum(e.match_hours) as match_exposure_hours,
    sum(e.training_hours) as training_exposure_hours
  from analysis.exposure_hours_by_build_analysis_window_v5 e
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by e.season
)
select c.season,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days,
  e.exposure_hours,
  e.match_exposure_hours,
  e.training_exposure_hours
from cohort c
join exposure e using (season)
group by c.season, e.exposure_hours,
  e.match_exposure_hours, e.training_exposure_hours;

create or replace view analysis.analysis_window_league_setting_split_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_setting_split_v5 x
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by x.season, x.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create or replace view analysis.analysis_window_league_injury_profiles_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_injury_profiles_v5 x
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create or replace view analysis.analysis_window_league_effective_injury_profiles_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_effective_injury_profiles_v5 x
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create or replace view analysis.analysis_window_league_diagnosis_profiles_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_diagnosis_profiles_v5 x
  group by x.season, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create or replace view analysis.analysis_window_league_monthly_v5
with (security_invoker = true) as
select x.season, x.month_start, x.month_label,
  sum(x.exposure_hours) as exposure_hours,
  sum(x.distance_km) as distance_km,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  analysis.rate_per_1000_v1(sum(x.time_loss_injuries), sum(x.exposure_hours))
    as incidence_per_1000h,
  analysis.rate_per_1000_v1(sum(x.days_lost), sum(x.exposure_hours))
    as burden_per_1000h
from analysis.analysis_window_monthly_v5 x
join analysis.league_member_releases_v2 m
  using (curated_build_id, team_key, season)
group by x.season, x.month_start, x.month_label;

create or replace view analysis.analysis_window_league_severity_distribution_v5
with (security_invoker = true) as
select x.season, x.severity_code, x.severity_label,
  sum(x.recorded_injuries) as recorded_injuries,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  min(x.band_order) as band_order
from analysis.analysis_window_severity_distribution_v5 x
join analysis.league_member_releases_v2 m
  using (curated_build_id, team_key, season)
group by x.season, x.severity_code, x.severity_label;

comment on materialized view analysis.analysis_window_injury_cohort_v5_snapshot is
  'Build-pinned V5 injury cohort shared by every successor aggregate.';
comment on materialized view analysis.analysis_window_reporting_classification_v5_snapshot is
  'Build-pinned accepted classification for the shared V5 injury cohort.';
comment on materialized view analysis.analysis_window_effective_exposure_cohort_v5_snapshot is
  'Build-pinned V5 effective exposure cohort shared by every successor aggregate.';
