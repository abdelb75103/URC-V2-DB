-- Accepted reporting V3: a parameterised season-bound cohort.  This is an
-- additive successor to V1/V2: no frozen view or snapshot is changed.

insert into audit.reason_codes (code, description) values
  ('league_dashboard_release_v3', 'Immutable 16-team league dashboard release from the accepted season-bound V3 cohort.'),
  ('season_bound_reporting_cohort_adjudication', 'Human-approved parameterised season-bound reporting cohort rule.')
on conflict (code) do nothing;

create table audit.reporting_cohort_rule_adjudications_v3 (
  id uuid primary key default gen_random_uuid(),
  adjudication_ref text not null,
  cohort_view_version text not null,
  season text not null,
  decision jsonb not null check (jsonb_typeof(decision) = 'object'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_locator text not null,
  reviewer text not null check (reviewer = 'Abdel Babiker'),
  migration_version text not null check (migration_version = '20260720170000'),
  decided_at timestamptz not null default now(),
  unique (adjudication_ref, cohort_view_version, season)
);
alter table audit.reporting_cohort_rule_adjudications_v3 enable row level security;

create function audit.reject_reporting_cohort_rule_adjudication_v3_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'audit.reporting_cohort_rule_adjudications_v3 is immutable; insert a superseding version';
end;
$$;
revoke execute on function audit.reject_reporting_cohort_rule_adjudication_v3_mutation() from public;
create trigger reporting_cohort_rule_adjudications_v3_immutable
before update or delete on audit.reporting_cohort_rule_adjudications_v3
for each row execute function audit.reject_reporting_cohort_rule_adjudication_v3_mutation();

-- Add future seasons as rows.  The cohort is never allowed to infer a window
-- from team-specific exposure coverage.
create table analysis.reporting_season_windows_v3 (
  cohort_view_version text not null,
  season text not null,
  season_start date not null,
  season_end date not null,
  decision_ref text not null,
  primary key (cohort_view_version, season),
  check (season_start <= season_end)
);
alter table analysis.reporting_season_windows_v3 enable row level security;

create function analysis.reject_reporting_season_window_v3_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'analysis.reporting_season_windows_v3 is immutable; add a superseding cohort version';
end;
$$;
revoke execute on function analysis.reject_reporting_season_window_v3_mutation() from public;
create trigger reporting_season_windows_v3_immutable
before update or delete on analysis.reporting_season_windows_v3
for each row execute function analysis.reject_reporting_season_window_v3_mutation();

insert into analysis.reporting_season_windows_v3
  (cohort_view_version, season, season_start, season_end, decision_ref)
values
  ('season_bound_2026-07-20_v1', '2024-25', date '2024-07-01', date '2025-06-30', 'COHORT-01');

insert into audit.reporting_cohort_rule_adjudications_v3
  (adjudication_ref, cohort_view_version, season, decision, evidence_sha256,
   evidence_locator, reviewer, migration_version, decided_at)
values (
  'COHORT-01', 'season_bound_2026-07-20_v1', '2024-25',
  '{"eligible_dated_injuries":"within_registered_season_window","eligible_undated_injuries":"season_attributed","exclude":"existing_eligibility_non_injury_other_team_non_urc_and_exact_italian_elite_championship","exposure":"included_curated_exposure_and_registered_fixtures_within_same_window","team_exposure_window":"not_used"}'::jsonb,
  'ab047adb8fbad86c87d83ede156954759ffe4b0c8da074cd0ee4f584a64c79a3',
  'docs/evidence/season_bound_reporting_2024-25.json',
  'Abdel Babiker', '20260720170000', timestamptz '2026-07-19 00:00:00+00'
);

create view analysis.accepted_reporting_cohort_rules_v3
with (security_invoker = true) as
select r.cohort_view_version, r.season,
  encode(digest(convert_to(jsonb_agg(jsonb_build_object(
    'adjudication_ref', r.adjudication_ref, 'decision', r.decision,
    'evidence_sha256', r.evidence_sha256, 'evidence_locator', r.evidence_locator,
    'reviewer', r.reviewer,
    'migration_version', r.migration_version
  ) order by r.adjudication_ref)::text, 'UTF8'), 'sha256'), 'hex') as cohort_evidence_sha256
from audit.reporting_cohort_rule_adjudications_v3 r
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = r.cohort_view_version and w.season = r.season
  and w.decision_ref = r.adjudication_ref
where r.adjudication_ref = 'COHORT-01'
  and r.cohort_view_version = 'season_bound_2026-07-20_v1'
  and r.reviewer = 'Abdel Babiker'
  and r.evidence_sha256 = 'ab047adb8fbad86c87d83ede156954759ffe4b0c8da074cd0ee4f584a64c79a3'
  and r.evidence_locator = 'docs/evidence/season_bound_reporting_2024-25.json'
  and r.migration_version = '20260720170000'
  and r.decision = '{"eligible_dated_injuries":"within_registered_season_window","eligible_undated_injuries":"season_attributed","exclude":"existing_eligibility_non_injury_other_team_non_urc_and_exact_italian_elite_championship","exposure":"included_curated_exposure_and_registered_fixtures_within_same_window","team_exposure_window":"not_used"}'::jsonb
group by r.cohort_view_version, r.season
having count(*) = 1;

-- Unlike V2, this never joins an exposure-derived team coverage window.  An
-- undated row is season-attributed by i.season and is deliberately retained;
-- downstream monthly views naturally require a non-null date.
create view analysis.injury_cohort_by_build_season_bound_v3
with (security_invoker = true) as
select
  i.id as injury_id, i.curated_build_id, i.team_key, i.season, i.date_injured,
  coalesce(i.days_injured, 0) as days_lost,
  coalesce(i.days_injured, 0) > 0 as is_time_loss,
  case i.activity_context when 'urc_match' then 'match' when 'match' then 'match'
    when 'training' then 'training' else 'unknown' end as setting_code,
  coalesce(i.body_location, 'unknown') as body_location_code,
  coalesce(bl.label, 'Unknown') as body_location_label,
  coalesce(i.injury_type, 'unknown') as injury_type_code,
  coalesce(it.label, 'Unknown') as injury_type_label,
  coalesce(i.severity_category, 'unknown_or_censored') as severity_code,
  case coalesce(i.severity_category, 'unknown_or_censored')
    when 'zero_days_medical_attention_only' then 'Medical attention'
    when 'one_day' then '1 day' when 'two_to_three_days' then '2-3 days'
    when 'four_to_seven_days' then '4-7 days'
    when 'eight_to_twenty_eight_days' then '8-28 days'
    when 'greater_than_twenty_eight_days' then '>28 days'
    else 'Unknown or censored' end as severity_label,
  (i.date_injured is null) as is_undated
from curated.injuries i
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'season_bound_2026-07-20_v1' and w.season = i.season
join analysis.accepted_reporting_cohort_rules_v3 rule
  on rule.cohort_view_version = w.cohort_view_version and rule.season = w.season
join ingestion.source_rows sr on sr.id = i.source_row_id
left join curated.code_lists bl on bl.list_name = 'body_location' and bl.code = coalesce(i.body_location, 'unknown')
left join curated.code_lists it on it.list_name = 'injury_type' and it.code = coalesce(i.injury_type, 'unknown')
where i.eligibility_status not in ('excluded_from_analysis', 'excluded_duplicate_adjudicated')
  and i.problem_type = 'injury'
  and (i.received_in_team_status is null or i.received_in_team_status not in ('other_team', 'club'))
  and (i.urc_match_scope is null or i.urc_match_scope <> 'non_urc_marker')
  and lower(trim(coalesce(sr.source_values ->> 'Match Type', ''))) <> 'italian elite championship'
  and (i.date_injured is null or i.date_injured between w.season_start and w.season_end);

create view analysis.exposure_hours_by_build_season_bound_v3
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season,
  coalesce(sum(e.minutes_clean), 0) / 60 as total_hours,
    case when count(distinct e.grain) = 1 then min(e.grain) else 'mixed' end as exposure_grain
  from curated.exposure e
  join analysis.reporting_season_windows_v3 w
    on w.cohort_view_version = 'season_bound_2026-07-20_v1' and w.season = e.season
  where e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date) between w.season_start and w.season_end
  group by e.curated_build_id, e.team_key, e.season
), fixtures as (
  select f.season, teams.team_key, count(*)::integer as matches_played
  from curated.fixtures f
  join analysis.reporting_season_windows_v3 w
    on w.cohort_view_version = 'season_bound_2026-07-20_v1' and w.season = f.season
  cross join lateral (values (f.home_team_key), (f.away_team_key)) teams(team_key)
  where f.match_date between w.season_start and w.season_end
  group by f.season, teams.team_key
)
select e.curated_build_id, e.team_key, e.season, coalesce(f.matches_played, 0) as matches_played,
  coalesce(f.matches_played, 0) * 20.0 as match_hours,
  e.total_hours - coalesce(f.matches_played, 0) * 20.0 as training_hours,
  e.total_hours, e.exposure_grain,
  'season_bound_included_curated_exposure_and_registered_fixtures'::text as method_note
from exposure e left join fixtures f on f.team_key = e.team_key and f.season = e.season;

create view analysis.season_bound_team_summary_v3
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season, count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost) filter (where c.is_time_loss) as median_severity_days
from analysis.injury_cohort_by_build_season_bound_v3 c
group by c.curated_build_id, c.team_key, c.season;

create view analysis.season_bound_setting_split_v3
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, c.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_season_bound_v3 c where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, c.setting_code
)
select g.*, case g.setting_code when 'match' then e.match_hours when 'training' then e.training_hours else null end as exposure_hours,
  case g.setting_code when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.match_hours) when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.training_hours) else null end as incidence_per_1000h,
  case g.setting_code when 'match' then analysis.rate_per_1000_v1(g.days_lost, e.match_hours) when 'training' then analysis.rate_per_1000_v1(g.days_lost, e.training_hours) else null end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g join analysis.exposure_hours_by_build_season_bound_v3 e using (curated_build_id, team_key, season);

create view analysis.season_bound_injury_profiles_v3
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.injury_cohort_by_build_season_bound_v3 c
  cross join lateral (values
    ('body_location'::text, c.body_location_code, c.body_location_label),
    ('injury_type'::text, c.injury_type_code, c.injury_type_label),
    ('injury_profile'::text, c.body_location_code || '__' || c.injury_type_code, c.body_location_label || ' · ' || c.injury_type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, d.dimension, d.code, d.label, s.setting_code
)
select g.*, case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours when 'training' then e.training_hours else null end as exposure_hours,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.total_hours) when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.match_hours) when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries, e.training_hours) else null end as incidence_per_1000h,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.days_lost, e.total_hours) when 'match' then analysis.rate_per_1000_v1(g.days_lost, e.match_hours) when 'training' then analysis.rate_per_1000_v1(g.days_lost, e.training_hours) else null end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g join analysis.exposure_hours_by_build_season_bound_v3 e using (curated_build_id, team_key, season);

create view analysis.season_bound_monthly_v3
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season, date_trunc('month', coalesce(e.session_date, e.week_start_date))::date as month_start,
    sum(e.minutes_clean) / 60 as exposure_hours, sum(e.distance_m_clean) / 1000 as distance_km
  from curated.exposure e join analysis.reporting_season_windows_v3 w on w.cohort_view_version = 'season_bound_2026-07-20_v1' and w.season = e.season
  where e.eligibility_status = 'included_pending_protocol' and coalesce(e.session_date, e.week_start_date) between w.season_start and w.season_end
  group by e.curated_build_id, e.team_key, e.season, date_trunc('month', coalesce(e.session_date, e.week_start_date))
), injuries as (
  select curated_build_id, team_key, season, date_trunc('month', date_injured)::date as month_start,
    count(*) filter (where is_time_loss) as time_loss_injuries, coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from analysis.injury_cohort_by_build_season_bound_v3 where date_injured is not null
  group by curated_build_id, team_key, season, date_trunc('month', date_injured)
), months as (select curated_build_id, team_key, season, month_start from exposure union select curated_build_id, team_key, season, month_start from injuries)
select m.curated_build_id, m.team_key, m.season, m.month_start, to_char(m.month_start, 'Mon YYYY') as month_label,
  coalesce(e.exposure_hours, 0) as exposure_hours, coalesce(e.distance_km, 0) as distance_km,
  coalesce(i.time_loss_injuries, 0) as time_loss_injuries, coalesce(i.days_lost, 0) as days_lost,
  analysis.rate_per_1000_v1(coalesce(i.time_loss_injuries, 0), coalesce(e.exposure_hours, 0)) as incidence_per_1000h,
  analysis.rate_per_1000_v1(coalesce(i.days_lost, 0), coalesce(e.exposure_hours, 0)) as burden_per_1000h
from months m left join exposure e using (curated_build_id, team_key, season, month_start)
left join injuries i using (curated_build_id, team_key, season, month_start);

create view analysis.season_bound_severity_distribution_v3
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season, c.severity_code, c.severity_label,
  count(*) as recorded_injuries, count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  case c.severity_code when 'zero_days_medical_attention_only' then 0 when 'one_day' then 1 when 'two_to_three_days' then 2 when 'four_to_seven_days' then 3 when 'eight_to_twenty_eight_days' then 4 when 'greater_than_twenty_eight_days' then 5 else 6 end as band_order
from analysis.injury_cohort_by_build_season_bound_v3 c
group by c.curated_build_id, c.team_key, c.season, c.severity_code, c.severity_label;

create view analysis.season_bound_reporting_classification_v3
with (security_invoker = true) as
with evidence as (
  select c.*, exists (
    select 1 from ingestion.source_rows sr cross join lateral jsonb_each_text(sr.source_values) e
    where sr.id = i.source_row_id
      and (e.key in ('Description', 'Injury Tissue Type/s', 'Body Part', 'Mechanism of Injury', 'Mechanism Notes', 'Treatment/Rehab', 'Injury Immediate Action', 'Injury Status', 'Medical System') or lower(e.key) ~ '(hia|concussion|head injury assessment|return.?to.?play|(^|[^a-z])rtp([^a-z]|$)|diagnos)')
      and lower(trim(coalesce(e.value, ''))) ~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
      and lower(trim(coalesce(e.value, ''))) !~ '(no|not|negative( for)?|passed|clear(ed)?|ruled out|without|did not).{0,32}(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
      and lower(trim(coalesce(e.value, ''))) !~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M).{0,32}(negative|passed|clear(ed)?|ruled out|not diagnosed)'
  ) as has_positive_concussion_text,
  upper(trim(coalesce(nullif(sr.source_values ->> 'Orchard Code', ''), case when i.problem_type = 'injury' then sr.source_values ->> 'Illness Code' end, ''))) as orchard_code
  from analysis.injury_cohort_by_build_season_bound_v3 c join curated.injuries i on i.id = c.injury_id join ingestion.source_rows sr on sr.id = i.source_row_id
)
select injury_id, curated_build_id, team_key, season, setting_code, is_time_loss, days_lost,
  case when orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX') or has_positive_concussion_text then 'concussion' when body_location_code = 'unknown' or injury_type_code = 'unknown' then 'unknown' else concat('compound__', body_location_code, '__', injury_type_code) end as diagnosis_code,
  case when orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX') or has_positive_concussion_text then 'Concussion' when body_location_code = 'unknown' or injury_type_code = 'unknown' then 'Unknown diagnosis' else concat(body_location_label, ' · ', injury_type_label) end as diagnosis_label
from evidence cross join analysis.accepted_reporting_classification_rules_v3;

create view analysis.season_bound_diagnosis_profiles_v3
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, c.diagnosis_code as code,
    c.diagnosis_label as label, s.setting_code, count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.season_bound_reporting_classification_v3 c
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, c.diagnosis_code, c.diagnosis_label, s.setting_code
)
select g.*, case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours when 'training' then e.training_hours else null end as exposure_hours,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.time_loss_injuries,e.total_hours) when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries,e.match_hours) when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries,e.training_hours) else null end as incidence_per_1000h,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.days_lost,e.total_hours) when 'match' then analysis.rate_per_1000_v1(g.days_lost,e.match_hours) when 'training' then analysis.rate_per_1000_v1(g.days_lost,e.training_hours) else null end as burden_per_1000h,
  g.days_lost::numeric/nullif(g.time_loss_injuries,0) as mean_severity_days
from grouped g join analysis.exposure_hours_by_build_season_bound_v3 e using (curated_build_id, team_key, season);

create view analysis.season_bound_league_summary_v3
with (security_invoker = true) as
with cohort as (
  select c.* from analysis.injury_cohort_by_build_season_bound_v3 c
  join analysis.league_member_releases_v2 m using (curated_build_id, team_key, season)
), exposure as (
  select e.season, sum(e.total_hours) as exposure_hours, sum(e.match_hours) as match_exposure_hours,
    sum(e.training_hours) as training_exposure_hours
  from analysis.exposure_hours_by_build_season_bound_v3 e
  join analysis.league_member_releases_v2 m using (curated_build_id, team_key, season)
  group by e.season
)
select c.season, count(*) as recorded_injuries, count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss),0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost) filter (where c.is_time_loss) as median_severity_days,
  e.exposure_hours, e.match_exposure_hours, e.training_exposure_hours
from cohort c join exposure e using (season)
group by c.season,e.exposure_hours,e.match_exposure_hours,e.training_exposure_hours;

create view analysis.season_bound_league_setting_split_v3
with (security_invoker = true) as
with grouped as (
  select x.season,x.setting_code,sum(x.time_loss_injuries) as time_loss_injuries,sum(x.days_lost) as days_lost
  from analysis.season_bound_setting_split_v3 x join analysis.league_member_releases_v2 m using (curated_build_id,team_key,season)
  group by x.season,x.setting_code
)
select g.*,case g.setting_code when 'match' then h.match_exposure_hours when 'training' then h.training_exposure_hours else null end as exposure_hours,
  case g.setting_code when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.match_exposure_hours) when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.training_exposure_hours) else null end as incidence_per_1000h,
  case g.setting_code when 'match' then analysis.rate_per_1000_v1(g.days_lost,h.match_exposure_hours) when 'training' then analysis.rate_per_1000_v1(g.days_lost,h.training_exposure_hours) else null end as burden_per_1000h,
  g.days_lost::numeric/nullif(g.time_loss_injuries,0) as mean_severity_days
from grouped g join analysis.season_bound_league_summary_v3 h using(season);

create view analysis.season_bound_league_profiles_v3
with (security_invoker = true) as
with grouped as (
  select x.season,x.dimension,x.code,x.label,x.setting_code,sum(x.time_loss_injuries) as time_loss_injuries,sum(x.days_lost) as days_lost
  from analysis.season_bound_injury_profiles_v3 x join analysis.league_member_releases_v2 m using(curated_build_id,team_key,season)
  group by x.season,x.dimension,x.code,x.label,x.setting_code
)
select g.*,case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours when 'training' then h.training_exposure_hours else null end as exposure_hours,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.exposure_hours) when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.match_exposure_hours) when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.training_exposure_hours) else null end as incidence_per_1000h,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.days_lost,h.exposure_hours) when 'match' then analysis.rate_per_1000_v1(g.days_lost,h.match_exposure_hours) when 'training' then analysis.rate_per_1000_v1(g.days_lost,h.training_exposure_hours) else null end as burden_per_1000h,
  g.days_lost::numeric/nullif(g.time_loss_injuries,0) as mean_severity_days
from grouped g join analysis.season_bound_league_summary_v3 h using(season);

create view analysis.season_bound_league_diagnosis_profiles_v3
with (security_invoker = true) as
with grouped as (
  select x.season,x.code,x.label,x.setting_code,sum(x.time_loss_injuries) as time_loss_injuries,sum(x.days_lost) as days_lost
  from analysis.season_bound_diagnosis_profiles_v3 x join analysis.league_member_releases_v2 m using(curated_build_id,team_key,season)
  group by x.season,x.code,x.label,x.setting_code
)
select g.*,case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours when 'training' then h.training_exposure_hours else null end as exposure_hours,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.exposure_hours) when 'match' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.match_exposure_hours) when 'training' then analysis.rate_per_1000_v1(g.time_loss_injuries,h.training_exposure_hours) else null end as incidence_per_1000h,
  case g.setting_code when 'all' then analysis.rate_per_1000_v1(g.days_lost,h.exposure_hours) when 'match' then analysis.rate_per_1000_v1(g.days_lost,h.match_exposure_hours) when 'training' then analysis.rate_per_1000_v1(g.days_lost,h.training_exposure_hours) else null end as burden_per_1000h,
  g.days_lost::numeric/nullif(g.time_loss_injuries,0) as mean_severity_days
from grouped g join analysis.season_bound_league_summary_v3 h using(season);

create view analysis.season_bound_league_monthly_v3
with (security_invoker = true) as
select x.season,x.month_start,x.month_label,sum(x.exposure_hours) as exposure_hours,sum(x.distance_km) as distance_km,
  sum(x.time_loss_injuries) as time_loss_injuries,sum(x.days_lost) as days_lost,
  analysis.rate_per_1000_v1(sum(x.time_loss_injuries),sum(x.exposure_hours)) as incidence_per_1000h,
  analysis.rate_per_1000_v1(sum(x.days_lost),sum(x.exposure_hours)) as burden_per_1000h
from analysis.season_bound_monthly_v3 x join analysis.league_member_releases_v2 m using(curated_build_id,team_key,season)
group by x.season,x.month_start,x.month_label;

create view analysis.season_bound_league_severity_distribution_v3
with (security_invoker = true) as
select x.season,x.severity_code,x.severity_label,sum(x.recorded_injuries) as recorded_injuries,
  sum(x.time_loss_injuries) as time_loss_injuries,sum(x.days_lost) as days_lost,min(x.band_order) as band_order
from analysis.season_bound_severity_distribution_v3 x join analysis.league_member_releases_v2 m using(curated_build_id,team_key,season)
group by x.season,x.severity_code,x.severity_label;

-- The public payload shape is unchanged.  Every cohort-dependent field below
-- comes from the season-bound views; only display-independent release metadata
-- (team label, generated timestamp, prior-season placeholder) comes from the
-- immutable member release.
create view analysis.team_dashboard_payload_season_bound_v3
with (security_invoker = true) as
select m.team_key, m.season, m.team_release_id, m.curated_build_id,
  rules.classification_view_version, rules.classification_evidence_sha256,
  cohort.cohort_view_version, cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', m.generated_at, 'team', d.team, 'season', m.season,
    'analysis_window', jsonb_build_object('start', w.season_start, 'end', w.season_end, 'basis', 'Registered season window; no team exposure-window restriction.'),
    'method', jsonb_build_array('Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.', 'Burden = pooled days lost / pooled exposure hours × 1,000.', 'Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.', 'Match exposure = registered fixtures in the season window × 15 players × 80 minutes / 60 per team.', 'Training exposure = included curated exposure in the season window minus match exposure.', 'IOC-aligned body-location and tissue/pathology categories use the accepted mappings.'),
    'coverage', (coalesce(d.coverage, '{}'::jsonb) - 'injury_cohort_filters') || jsonb_build_object('hours', e.total_hours, 'match_hours', e.match_hours, 'training_hours', e.training_hours, 'exposure_grain', e.exposure_grain, 'included_exposure_status', 'included', 'analysis_window_start', w.season_start, 'analysis_window_end', w.season_end),
    'headline', jsonb_build_array(
      jsonb_build_object('key','recorded_injuries','label','Recorded injuries','value',s.recorded_injuries,'unit','injuries','formula','count(eligible injury rows in registered season window, including season-attributed undated rows)'),
      jsonb_build_object('key','time_loss_injuries','label','Time-loss injuries','value',s.time_loss_injuries,'unit','injuries','formula','count(eligible injury rows where days lost > 0)'),
      jsonb_build_object('key','incidence_per_1000h','label','Incidence','value',analysis.rate_per_1000_v1(s.time_loss_injuries,e.total_hours),'unit','per 1,000 player-hours','numerator',s.time_loss_injuries,'denominator',e.total_hours,'formula','pooled time-loss injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key','severity_mean_days','label','Mean severity','value',s.mean_severity_days,'unit','days lost per injury','numerator',s.days_lost,'denominator',s.time_loss_injuries,'formula','pooled days lost / pooled time-loss injuries'),
      jsonb_build_object('key','severity_median_days','label','Median severity','value',s.median_severity_days,'unit','days lost per injury','formula','median(days lost) across pooled time-loss injuries'),
      jsonb_build_object('key','burden_per_1000h','label','Burden','value',analysis.rate_per_1000_v1(s.days_lost,e.total_hours),'unit','days lost per 1,000 player-hours','numerator',s.days_lost,'denominator',e.total_hours,'formula','pooled days lost / pooled exposure hours * 1000')),
    'setting_split', coalesce((select jsonb_agg(jsonb_build_object('key',x.setting_code,'label',initcap(x.setting_code),'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'exposure_hours',x.exposure_hours,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by case x.setting_code when 'match' then 1 when 'training' then 2 else 3 end) from analysis.season_bound_setting_split_v3 x where x.curated_build_id=m.curated_build_id and x.team_key=m.team_key and x.season=m.season),'[]'::jsonb),
    'setting_metrics', coalesce((select jsonb_agg(jsonb_build_object('setting',x.setting_code,'label',initcap(x.setting_code),'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'exposure_hours',x.exposure_hours,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by case x.setting_code when 'match' then 1 when 'training' then 2 else 3 end) from analysis.season_bound_setting_split_v3 x where x.curated_build_id=m.curated_build_id and x.team_key=m.team_key and x.season=m.season),'[]'::jsonb),
    'monthly', coalesce((select jsonb_agg(jsonb_build_object('month',x.month_label,'exposure_hours',x.exposure_hours,'distance_km',x.distance_km,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h) order by x.month_start) from analysis.season_bound_monthly_v3 x where x.curated_build_id=m.curated_build_id and x.team_key=m.team_key and x.season=m.season),'[]'::jsonb),
    'body_locations', coalesce((select jsonb_agg(jsonb_build_object('key',x.code,'label',x.label,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by x.code) from analysis.season_bound_injury_profiles_v3 x where x.curated_build_id=m.curated_build_id and x.team_key=m.team_key and x.season=m.season and x.dimension='body_location' and x.setting_code='all'),'[]'::jsonb),
    'injury_types', coalesce((select jsonb_agg(jsonb_build_object('key',x.code,'label',x.label,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by x.time_loss_injuries desc, x.days_lost desc, x.code) from analysis.season_bound_injury_profiles_v3 x where x.curated_build_id=m.curated_build_id and x.team_key=m.team_key and x.season=m.season and x.dimension='injury_type' and x.setting_code='all'),'[]'::jsonb),
    'injury_profiles', coalesce((select jsonb_agg(jsonb_build_object('dimension',x.dimension,'code',x.code,'label',x.label,'setting',x.setting_code,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'exposure_hours',x.exposure_hours,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by x.dimension,x.setting_code,x.time_loss_injuries desc,x.days_lost desc,x.code) from (select dimension,code,label,setting_code,time_loss_injuries,days_lost,exposure_hours,incidence_per_1000h,burden_per_1000h,mean_severity_days from analysis.season_bound_injury_profiles_v3 where curated_build_id=m.curated_build_id and team_key=m.team_key and season=m.season union all select 'diagnosis'::text,code,label,setting_code,time_loss_injuries,days_lost,exposure_hours,incidence_per_1000h,burden_per_1000h,mean_severity_days from analysis.season_bound_diagnosis_profiles_v3 where curated_build_id=m.curated_build_id and team_key=m.team_key and season=m.season) x),'[]'::jsonb),
    'severity_distribution', coalesce((select jsonb_agg(jsonb_build_object('key',x.severity_code,'label',x.severity_label,'recorded_injuries',x.recorded_injuries,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost) order by x.band_order) from analysis.season_bound_severity_distribution_v3 x where x.curated_build_id=m.curated_build_id and x.team_key=m.team_key and x.season=m.season),'[]'::jsonb),
    'prior_season', d.prior_season,
    'limitations', jsonb_build_array('The registered season window, rather than team-specific exposure coverage, defines both numerator and denominator eligibility.', 'Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.', 'Unknown-setting injuries are included in overall metrics but have no match/training rate.', 'Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.')
  ) as dashboard
from analysis.league_member_releases_v2 m
join reporting.latest_team_dashboard d on d.release_id=m.team_release_id and d.team_key=m.team_key and d.season=m.season
join analysis.reporting_season_windows_v3 w on w.cohort_view_version='season_bound_2026-07-20_v1' and w.season=m.season
join analysis.accepted_reporting_cohort_rules_v3 cohort on cohort.cohort_view_version=w.cohort_view_version and cohort.season=w.season
cross join analysis.accepted_reporting_classification_rules_v3 rules
join analysis.season_bound_team_summary_v3 s on s.curated_build_id=m.curated_build_id and s.team_key=m.team_key and s.season=m.season
join analysis.exposure_hours_by_build_season_bound_v3 e on e.curated_build_id=m.curated_build_id and e.team_key=m.team_key and e.season=m.season;

create view analysis.league_dashboard_payload_season_bound_v3
with (security_invoker = true) as
select h.season, rules.classification_view_version, rules.classification_evidence_sha256,
  cohort.cohort_view_version, cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at',(select max(m.generated_at) from analysis.league_member_releases_v2 m where m.season=h.season),
    'team','URC Overall','season',h.season,
    'analysis_window',jsonb_build_object('start',w.season_start,'end',w.season_end,'basis','Registered season window; no team exposure-window restriction.'),
    'method',jsonb_build_array('Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.','Burden = pooled days lost / pooled exposure hours × 1,000.','Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.','Match exposure = registered fixtures in the season window × 15 players × 80 minutes / 60 per team.','Training exposure = included curated exposure in the season window minus match exposure.','IOC-aligned body-location and tissue/pathology categories use the accepted mappings.'),
    'coverage',coalesce((select b.dashboard -> 'coverage' from analysis.league_dashboard_payload_v2 b where b.season=h.season),'{}'::jsonb) || jsonb_build_object('hours',h.exposure_hours,'match_hours',h.match_exposure_hours,'training_hours',h.training_exposure_hours,'teams_included',(select count(*) from analysis.league_member_releases_v2 m where m.season=h.season),'included_exposure_status','included','analysis_window_start',w.season_start,'analysis_window_end',w.season_end),
    'headline',jsonb_build_array(
      jsonb_build_object('key','recorded_injuries','label','Recorded injuries','value',h.recorded_injuries,'unit','injuries','formula','count(eligible injury rows in registered season window, including season-attributed undated rows)'),
      jsonb_build_object('key','time_loss_injuries','label','Time-loss injuries','value',h.time_loss_injuries,'unit','injuries','formula','count(eligible injury rows where days lost > 0)'),
      jsonb_build_object('key','incidence_per_1000h','label','Incidence','value',analysis.rate_per_1000_v1(h.time_loss_injuries,h.exposure_hours),'unit','per 1,000 player-hours','numerator',h.time_loss_injuries,'denominator',h.exposure_hours,'formula','pooled time-loss injuries / pooled exposure hours * 1000'),
      jsonb_build_object('key','severity_mean_days','label','Mean severity','value',h.mean_severity_days,'unit','days lost per injury','numerator',h.days_lost,'denominator',h.time_loss_injuries,'formula','pooled days lost / pooled time-loss injuries'),
      jsonb_build_object('key','severity_median_days','label','Median severity','value',h.median_severity_days,'unit','days lost per injury','formula','median(days lost) across pooled time-loss injuries'),
      jsonb_build_object('key','burden_per_1000h','label','Burden','value',analysis.rate_per_1000_v1(h.days_lost,h.exposure_hours),'unit','days lost per 1,000 player-hours','numerator',h.days_lost,'denominator',h.exposure_hours,'formula','pooled days lost / pooled exposure hours * 1000')),
    'setting_split',coalesce((select jsonb_agg(jsonb_build_object('key',x.setting_code,'label',initcap(x.setting_code),'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'exposure_hours',x.exposure_hours,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by case x.setting_code when 'match' then 1 when 'training' then 2 else 3 end) from analysis.season_bound_league_setting_split_v3 x where x.season=h.season),'[]'::jsonb),
    'setting_metrics',coalesce((select jsonb_agg(jsonb_build_object('setting',x.setting_code,'label',initcap(x.setting_code),'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'exposure_hours',x.exposure_hours,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by case x.setting_code when 'match' then 1 when 'training' then 2 else 3 end) from analysis.season_bound_league_setting_split_v3 x where x.season=h.season),'[]'::jsonb),
    'monthly',coalesce((select jsonb_agg(jsonb_build_object('month',x.month_label,'exposure_hours',x.exposure_hours,'distance_km',x.distance_km,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h) order by x.month_start) from analysis.season_bound_league_monthly_v3 x where x.season=h.season),'[]'::jsonb),
    'body_locations',coalesce((select jsonb_agg(jsonb_build_object('key',x.code,'label',x.label,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by x.code) from analysis.season_bound_league_profiles_v3 x where x.season=h.season and x.dimension='body_location' and x.setting_code='all'),'[]'::jsonb),
    'injury_types',coalesce((select jsonb_agg(jsonb_build_object('key',x.code,'label',x.label,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by x.time_loss_injuries desc,x.days_lost desc,x.code) from analysis.season_bound_league_profiles_v3 x where x.season=h.season and x.dimension='injury_type' and x.setting_code='all'),'[]'::jsonb),
    'injury_profiles',coalesce((select jsonb_agg(jsonb_build_object('dimension',x.dimension,'code',x.code,'label',x.label,'setting',x.setting_code,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost,'exposure_hours',x.exposure_hours,'incidence_per_1000h',x.incidence_per_1000h,'burden_per_1000h',x.burden_per_1000h,'mean_severity_days',x.mean_severity_days) order by x.dimension,x.setting_code,x.time_loss_injuries desc,x.days_lost desc,x.code) from (select dimension,code,label,setting_code,time_loss_injuries,days_lost,exposure_hours,incidence_per_1000h,burden_per_1000h,mean_severity_days from analysis.season_bound_league_profiles_v3 where season=h.season union all select 'diagnosis'::text,code,label,setting_code,time_loss_injuries,days_lost,exposure_hours,incidence_per_1000h,burden_per_1000h,mean_severity_days from analysis.season_bound_league_diagnosis_profiles_v3 where season=h.season) x),'[]'::jsonb),
    'severity_distribution',coalesce((select jsonb_agg(jsonb_build_object('key',x.severity_code,'label',x.severity_label,'recorded_injuries',x.recorded_injuries,'time_loss_injuries',x.time_loss_injuries,'days_lost',x.days_lost) order by x.band_order) from analysis.season_bound_league_severity_distribution_v3 x where x.season=h.season),'[]'::jsonb),
    'prior_season',jsonb_build_object('season','2023-24','status','pending','note','No prior-season league injury and exposure denominator pair has passed the V2 workflow.'),
    'limitations',jsonb_build_array('The registered season window, rather than team-specific exposure coverage, defines both numerator and denominator eligibility.','Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.','Unknown-setting injuries are included in overall metrics but have no match/training rate.','Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.')
  ) as dashboard
from analysis.season_bound_league_summary_v3 h
join analysis.reporting_season_windows_v3 w on w.cohort_view_version='season_bound_2026-07-20_v1' and w.season=h.season
join analysis.accepted_reporting_cohort_rules_v3 cohort on cohort.cohort_view_version=w.cohort_view_version and cohort.season=w.season
cross join analysis.accepted_reporting_classification_rules_v3 rules;

alter table reporting.league_release_context_v2
  add column cohort_view_version text not null default 'v2'
    check (cohort_view_version in ('v2', 'season_bound_2026-07-20_v1')),
  add column cohort_evidence_sha256 text check (cohort_evidence_sha256 is null or cohort_evidence_sha256 ~ '^[0-9a-f]{64}$');
alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_analysis_version_check,
  add constraint league_release_context_v2_analysis_version_check
    check (analysis_version in ('v2', 'v3'));
alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_decision_recorded_at_check,
  add constraint league_release_context_v2_decision_recorded_at_check check (
    (analysis_version = 'v2' and decision_recorded_at = date '2026-07-14') or
    (analysis_version = 'v3' and decision_recorded_at = date '2026-07-19')
  );
alter table reporting.league_release_context_v2
  add constraint league_release_context_v2_cohort_evidence check (
    (cohort_view_version = 'v2' and cohort_evidence_sha256 is null) or
    (cohort_view_version = 'season_bound_2026-07-20_v1' and cohort_evidence_sha256 is not null)
  );

create view analysis.team_dashboard_release_candidates_v4
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id, 'v2'::text as analysis_version,
  'v2'::text as classification_view_version, null::text as classification_evidence_sha256,
  'v2'::text as cohort_view_version, null::text as cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_v2
union all
select team_key, season, team_release_id, curated_build_id, 'v2'::text,
  classification_view_version, classification_evidence_sha256, 'v2'::text, null::text, dashboard
from analysis.team_dashboard_payload_adjudicated_v3
union all
select team_key, season, team_release_id, curated_build_id, 'v3'::text,
  classification_view_version, classification_evidence_sha256, cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_season_bound_v3;

create view analysis.league_dashboard_release_candidates_v4
with (security_invoker = true) as
select season, 'v2'::text as analysis_version, 'v2'::text as classification_view_version,
  null::text as classification_evidence_sha256, 'v2'::text as cohort_view_version,
  null::text as cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_v2
union all
select season, 'v2'::text, classification_view_version, classification_evidence_sha256,
  'v2'::text, null::text, dashboard
from analysis.league_dashboard_payload_adjudicated_v3
union all
select season, 'v3'::text, classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_season_bound_v3;

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
begin
  if not exists (
    select 1 from reporting.league_release_context_v2 context
    join analysis.league_dashboard_release_candidates_v4 candidate
      on candidate.season=context.season and candidate.analysis_version=context.analysis_version
     and candidate.classification_view_version=context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version=context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard=new.dashboard_payload
    where context.release_id=new.release_id
  ) then raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate'; end if;
  return new;
end;
$$;

create or replace function reporting.validate_team_dashboard_v2_candidates()
returns trigger language plpgsql as $$
begin
  if exists (
    select 1 from new_team_dashboard_v2_payloads payload join reporting.league_release_context_v2 context on context.release_id=payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v4 candidate
      on candidate.season=context.season and candidate.team_key=payload.team_key and candidate.team_release_id=payload.team_release_id and candidate.curated_build_id=payload.curated_build_id
     and candidate.analysis_version=context.analysis_version and candidate.classification_view_version=context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version=context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard=payload.dashboard_payload
    where candidate.team_key is null
  ) then raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate'; end if;
  return null;
end;
$$;

comment on view analysis.injury_cohort_by_build_season_bound_v3 is
  'Accepted V3 cohort: registered season bounds, no team exposure-window restriction, and season-attributed undated injuries.';
