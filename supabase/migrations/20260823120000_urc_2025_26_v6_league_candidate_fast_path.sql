-- Materialise the accepted V6 constituent relations in bounded statements,
-- assemble the established league JSON once, then seal those exact JSONB
-- bytes. The snapshot remains valid only while the same sixteen approved team
-- release/build identities are current. Member drift returns zero candidates.

do $$
begin
  if current_setting('transaction_isolation') <> 'repeatable read' then
    raise exception 'V6 league candidate snapshot requires repeatable-read isolation';
  end if;
end;
$$;

create table analysis.league_dashboard_release_candidate_snapshot_v6_20260823 (
  snapshot_version text primary key check (snapshot_version = '20260823120000'),
  season text not null check (season = '2025-26'),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (
    classification_view_version = 'reporting_classification_2026-07-22_v2'
  ),
  classification_evidence_sha256 text not null check (
    classification_evidence_sha256 ~ '^[0-9a-f]{64}$'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
  ),
  cohort_evidence_sha256 text not null check (
    cohort_evidence_sha256 ~ '^[0-9a-f]{64}$'
  ),
  member_count integer not null check (member_count = 16),
  member_set_sha256 text not null check (member_set_sha256 ~ '^[0-9a-f]{64}$'),
  dashboard jsonb not null check (jsonb_typeof(dashboard) = 'object'),
  payload_sha256 text not null check (
    payload_sha256 ~ '^[0-9a-f]{64}$'
    and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
  ),
  created_at timestamptz not null default now(),
  unique (season, analysis_version, classification_view_version, cohort_view_version)
);

alter table analysis.league_dashboard_release_candidate_snapshot_v6_20260823
  enable row level security;
revoke all on analysis.league_dashboard_release_candidate_snapshot_v6_20260823
  from public, anon, authenticated, web_reader;

create function reporting.prevent_v6_league_candidate_snapshot_mutation_20260823()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'V6 league candidate snapshot is immutable';
end;
$$;

revoke execute on function
  reporting.prevent_v6_league_candidate_snapshot_mutation_20260823()
  from public, anon, authenticated, web_reader;

create trigger league_dashboard_release_candidate_snapshot_v6_20260823_immutable
before update or delete
on analysis.league_dashboard_release_candidate_snapshot_v6_20260823
for each row execute function
  reporting.prevent_v6_league_candidate_snapshot_mutation_20260823();

create temporary table _v6_current_members on commit drop as
select member.team_key, member.season, member.team_release_id,
  member.curated_build_id
from analysis.league_member_releases_v6 member
where member.season = '2025-26';
analyze _v6_current_members;

create temporary table _v6_league_summary on commit drop as
select summary.*
from analysis.analysis_window_league_summary_v6 summary
where summary.season = '2025-26';
analyze _v6_league_summary;

create temporary table _v6_league_monthly on commit drop as
select monthly.*
from analysis.analysis_window_league_monthly_v6 monthly
where monthly.season = '2025-26';
analyze _v6_league_monthly;

create temporary table _v6_team_hours on commit drop as
select hours.*
from analysis.analysis_window_team_hours_v6 hours
where hours.season = '2025-26';
analyze _v6_team_hours;

create temporary table _v6_exposure_stats on commit drop as
select count(*) as exposure_rows,
  count(distinct nullif(exposure.player_uid, 'Unknown')) as exposed_players,
  count(distinct date_trunc('week', exposure.period_start)) as weeks
from analysis.analysis_window_team_exposure_v6 exposure;
analyze _v6_exposure_stats;

create temporary table _v6_active_build_stats on commit drop as
select max(member.generated_at) as generated_at
from analysis.analysis_window_active_builds_v6 member;
analyze _v6_active_build_stats;

create temporary table _v6_release_evidence on commit drop as
select summary.season, rules.classification_view_version,
  rules.classification_evidence_sha256, cohort.cohort_view_version,
  cohort.cohort_evidence_sha256, season_window.season_start,
  season_window.season_end
from _v6_league_summary summary
join analysis.reporting_season_windows_v3 season_window
  on season_window.cohort_view_version =
    'analysis_window_2025-26_2026-08-15_v1'
 and season_window.season = summary.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort
  on cohort.cohort_view_version = season_window.cohort_view_version
 and cohort.season = season_window.season
cross join analysis.accepted_year2_reporting_classification_rules_v6 rules
cross join analysis.accepted_urc_2025_26_incomplete_exposure_reporting_evidence_v6 evidence
where rules.classification_view_version =
    'reporting_classification_2026-07-22_v2'
  and evidence.evidence_sha256 =
    'b6fae7ce7e4609000337c29d7965e99809da3733b126522a1faabf600fdcc23c';
analyze _v6_release_evidence;

create temporary table _v6_league_profiles on commit drop as
select profile.*
from analysis.analysis_window_league_profiles_v6 profile
where profile.season = '2025-26';
analyze _v6_league_profiles;

create temporary table _v6_league_severity on commit drop as
select severity.*
from analysis.analysis_window_league_severity_v6 severity
where severity.season = '2025-26';
analyze _v6_league_severity;

create temporary table _v6_league_setting_metrics on commit drop as
select setting.*
from analysis.analysis_window_league_setting_metrics_v6 setting
where setting.season = '2025-26';
analyze _v6_league_setting_metrics;

create temporary table _v6_league_contact_distribution on commit drop as
select contact.*
from analysis.analysis_window_league_contact_distribution_v6 contact
where contact.season = '2025-26';
analyze _v6_league_contact_distribution;

do $$
begin
  if (select count(*) from _v6_current_members) <> 16
    or (select count(distinct team_key) from _v6_current_members) <> 16
    or (select count(distinct team_release_id) from _v6_current_members) <> 16
    or (select count(distinct curated_build_id) from _v6_current_members) <> 16
  then
    raise exception 'V6 staged member set must contain sixteen distinct release/build identities';
  end if;

  if (select count(*) from _v6_league_summary) <> 1
    or not exists (
      select 1 from _v6_league_summary
      where recorded_injuries = 335 and time_loss_injuries = 107
        and days_lost = 1950
    )
  then
    raise exception 'V6 staged league summary is incomplete or differs from approved members';
  end if;

  if (select count(*) from _v6_league_monthly) <> 10
    or (select count(distinct month_start) from _v6_league_monthly) <> 10
    or (select min(month_start) from _v6_league_monthly) <> date '2025-09-01'
    or (select max(month_start) from _v6_league_monthly) <> date '2026-06-01'
  then
    raise exception 'V6 staged league monthly domain must contain Sep 2025 through Jun 2026';
  end if;

  if (select count(*) from _v6_team_hours) <> 16
    or (select count(distinct team_key) from _v6_team_hours) <> 16
    or (select count(distinct curated_build_id) from _v6_team_hours) <> 16
    or (select count(total_hours) from _v6_team_hours) <> 8
  then
    raise exception 'V6 staged team hours differ from the sixteen approved team candidates';
  end if;

  if (select count(*) from _v6_exposure_stats) <> 1
    or not exists (
      select 1 from _v6_exposure_stats where exposure_rows = 56769
    )
    or (select count(*) from _v6_active_build_stats) <> 1
    or (select generated_at from _v6_active_build_stats) is null
    or (select count(*) from _v6_release_evidence) <> 1
  then
    raise exception 'V6 staged coverage, build or release evidence is incomplete';
  end if;

  if (select count(*) from _v6_league_profiles) <> 213
    or (
      select count(*) from (
        select setting_code, dimension, code, label
        from _v6_league_profiles
        group by setting_code, dimension, code, label
        having count(*) <> 1
      ) duplicate_profiles
    ) <> 0
  then
    raise exception 'V6 staged league profiles are incomplete or duplicate-keyed';
  end if;

  if (select count(*) from _v6_league_severity) <> 7
    or (select count(distinct severity_code) from _v6_league_severity) <> 7
  then
    raise exception 'V6 staged league severity grid must contain seven unique cells';
  end if;

  if (select count(*) from _v6_league_setting_metrics) <> 4
    or (select array_agg(setting_code order by setting_code)
        from _v6_league_setting_metrics)
      is distinct from array['all', 'match', 'training', 'unknown']::text[]
  then
    raise exception 'V6 staged league setting grid must contain four exact cells';
  end if;

  if (select count(*) from _v6_league_contact_distribution) <> 12
    or (
      select count(*) from (
        select setting_code, contact_context
        from _v6_league_contact_distribution
        group by setting_code, contact_context
        having count(*) <> 1
      ) duplicate_contacts
    ) <> 0
    or (select count(distinct setting_code)
        from _v6_league_contact_distribution) <> 4
    or (select count(distinct contact_context)
        from _v6_league_contact_distribution) <> 3
  then
    raise exception 'V6 staged league contact grid must contain twelve exact cells';
  end if;
end;
$$;

with member_set as (
  select season, count(*)::integer as member_count,
    reporting.canonical_jsonb_sha256_v1(
      jsonb_agg(jsonb_build_object(
        'team_key', team_key,
        'team_release_id', team_release_id::text,
        'curated_build_id', curated_build_id::text
      ) order by team_key)
    ) as member_set_sha256
  from _v6_current_members
  group by season
), base as (
  select summary.season, evidence.classification_view_version,
    evidence.classification_evidence_sha256, evidence.cohort_view_version,
    evidence.cohort_evidence_sha256,
    jsonb_build_object(
      'generated_at', active.generated_at,
      'team', 'URC Overall',
      'season', summary.season,
      'analysis_window', jsonb_build_object(
        'start', evidence.season_start,
        'end', evidence.season_end,
        'basis', 'Registered Year 2 reporting window.'
      ),
      'method', jsonb_build_array(
        'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
        'Burden = pooled days lost / pooled exposure hours × 1,000.',
        'Season-attributed undated injuries are included in totals but excluded from monthly series.'
      ),
      'coverage', jsonb_build_object(
        'hours', summary.exposure_hours,
        'match_hours', summary.match_exposure_hours,
        'training_hours', summary.training_exposure_hours,
        'teams_included', 16,
        'distance_km', case when summary.exposure_hours is null
          then null::numeric else (
            select sum(hours.distance_km)
            from _v6_team_hours hours
            where hours.season = summary.season
          ) end,
        'exposure_rows', exposure.exposure_rows,
        'exposed_players', exposure.exposed_players,
        'weeks', exposure.weeks,
        'included_exposure_status', case when summary.exposure_hours is null
          then 'source_backed_denominators_incomplete_no_imputation'
          else 'source_backed_exposure_submitted_may_be_incomplete' end,
        'analysis_window_start', evidence.season_start,
        'analysis_window_end', evidence.season_end
      ),
      'headline', jsonb_build_array(
        jsonb_build_object('key', 'recorded_injuries', 'label', 'Recorded injuries',
          'value', summary.recorded_injuries, 'unit', 'injuries',
          'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'),
        jsonb_build_object('key', 'time_loss_injuries', 'label', 'Time-loss injuries',
          'value', summary.time_loss_injuries, 'unit', 'injuries',
          'formula', 'count(eligible injury rows where days lost > 0)'),
        jsonb_build_object('key', 'incidence_per_1000h', 'label', 'Incidence',
          'value', analysis.rate_per_1000_v1(summary.time_loss_injuries, summary.exposure_hours),
          'unit', 'per 1,000 player-hours', 'numerator', summary.time_loss_injuries,
          'denominator', summary.exposure_hours,
          'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'),
        jsonb_build_object('key', 'severity_mean_days', 'label', 'Mean severity',
          'value', summary.mean_severity_days, 'unit', 'days lost per injury',
          'numerator', summary.days_lost, 'denominator', summary.time_loss_injuries,
          'formula', 'pooled days lost / pooled time-loss injuries'),
        jsonb_build_object('key', 'severity_median_days', 'label', 'Median severity',
          'value', summary.median_severity_days, 'unit', 'days lost per injury',
          'formula', 'median(days lost) across pooled time-loss injuries'),
        jsonb_build_object('key', 'burden_per_1000h', 'label', 'Burden',
          'value', analysis.rate_per_1000_v1(summary.days_lost, summary.exposure_hours),
          'unit', 'days lost per 1,000 player-hours', 'numerator', summary.days_lost,
          'denominator', summary.exposure_hours,
          'formula', 'pooled days lost / pooled exposure hours * 1000')
      ),
      'monthly', coalesce((
        select jsonb_agg(jsonb_build_object(
          'month', monthly.month_label,
          'exposure_hours', monthly.exposure_hours,
          'distance_km', monthly.distance_km,
          'time_loss_injuries', monthly.time_loss_injuries,
          'days_lost', monthly.days_lost,
          'incidence_per_1000h', monthly.incidence_per_1000h,
          'burden_per_1000h', monthly.burden_per_1000h
        ) order by monthly.month_start)
        from _v6_league_monthly monthly
        where monthly.season = summary.season
      ), '[]'::jsonb),
      'body_locations', '[]'::jsonb,
      'injury_types', '[]'::jsonb,
      'injury_profiles', '[]'::jsonb,
      'injury_type_families', '[]'::jsonb,
      'severity_distribution', '[]'::jsonb,
      'setting_split', '[]'::jsonb,
      'setting_metrics', '[]'::jsonb,
      'contact_distribution', '[]'::jsonb,
      'prior_season', jsonb_build_object(
        'season', '2024-25', 'status', 'frozen',
        'note', 'Prior season remains frozen and is not recomputed by V6.'
      ),
      'limitations', case when summary.exposure_hours is null then jsonb_build_array(
        'At least one source-backed team denominator is unavailable. League exposure hours, distance, incidence and burden are null. No imputation was applied.'
      ) else jsonb_build_array(
        'Submitted team exposure may be incomplete. Reported exposure values use source-backed rows only and no imputation was applied.'
      ) end
    ) as dashboard
  from _v6_league_summary summary
  join _v6_release_evidence evidence using (season)
  cross join _v6_active_build_stats active
  cross join _v6_exposure_stats exposure
), candidate as (
  select base.season, 'v6'::text as analysis_version,
    base.classification_view_version, base.classification_evidence_sha256,
    base.cohort_view_version, base.cohort_evidence_sha256,
    base.dashboard || sections.dashboard_sections || sections.family_section
      as dashboard
  from base
  cross join lateral (
    select jsonb_build_object(
      'body_locations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', code, 'label', label,
          'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
          'exposure_hours', exposure_hours,
          'incidence_per_1000h', incidence_per_1000h,
          'burden_per_1000h', burden_per_1000h,
          'mean_severity_days', mean_severity_days
        ) order by code)
        from _v6_league_profiles
        where season = base.season
          and dimension = 'body_location' and setting_code = 'all'
      ), '[]'::jsonb),
      'injury_types', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', code, 'label', label,
          'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
          'exposure_hours', exposure_hours,
          'incidence_per_1000h', incidence_per_1000h,
          'burden_per_1000h', burden_per_1000h,
          'mean_severity_days', mean_severity_days
        ) order by time_loss_injuries desc, code)
        from _v6_league_profiles
        where season = base.season
          and dimension = 'injury_type' and setting_code = 'all'
      ), '[]'::jsonb),
      'injury_profiles', coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', dimension, 'code', code, 'label', label,
          'setting', setting_code, 'time_loss_injuries', time_loss_injuries,
          'days_lost', days_lost, 'exposure_hours', exposure_hours,
          'incidence_per_1000h', incidence_per_1000h,
          'burden_per_1000h', burden_per_1000h,
          'mean_severity_days', mean_severity_days
        ) order by dimension, setting_code, code)
        from _v6_league_profiles
        where season = base.season
      ), '[]'::jsonb),
      'severity_distribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', severity_code,
          'label', initcap(replace(severity_code, '_', ' ')),
          'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries,
          'days_lost', days_lost
        ) order by severity_code)
        from _v6_league_severity
        where season = base.season
      ), '[]'::jsonb),
      'setting_metrics', coalesce((
        select jsonb_agg(jsonb_build_object(
          'setting', setting_code, 'label', initcap(setting_code),
          'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
          'exposure_hours', exposure_hours,
          'incidence_per_1000h', analysis.rate_per_1000_v1(time_loss_injuries, exposure_hours),
          'burden_per_1000h', analysis.rate_per_1000_v1(days_lost, exposure_hours),
          'mean_severity_days', days_lost / nullif(time_loss_injuries, 0)
        ) order by setting_code)
        from _v6_league_setting_metrics
        where season = base.season
      ), '[]'::jsonb),
      'setting_split', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', setting_code, 'label', initcap(setting_code),
          'time_loss_injuries', time_loss_injuries, 'days_lost', days_lost,
          'exposure_hours', exposure_hours
        ) order by setting_code)
        from _v6_league_setting_metrics
        where season = base.season
      ), '[]'::jsonb),
      'contact_distribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', contact_context, 'label', contact_label,
          'setting', setting_code, 'recorded_injuries', recorded_injuries,
          'time_loss_injuries', time_loss_injuries
        ) order by
          array_position(array['all', 'match', 'training', 'unknown'], setting_code),
          array_position(array['contact', 'non_contact', 'unknown'], contact_context)
        )
        from _v6_league_contact_distribution
        where season = base.season
      ), '[]'::jsonb)
    ) as dashboard_sections,
    jsonb_build_object(
      'injury_type_families', analysis.injury_type_families_from_payload_v1(
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'dimension', dimension, 'code', code, 'label', label,
            'setting', setting_code, 'time_loss_injuries', time_loss_injuries,
            'days_lost', days_lost, 'exposure_hours', exposure_hours,
            'incidence_per_1000h', incidence_per_1000h,
            'burden_per_1000h', burden_per_1000h,
            'mean_severity_days', mean_severity_days
          ) order by dimension, setting_code, code)
          from _v6_league_profiles
          where season = base.season
        ), '[]'::jsonb)
      )
    ) as family_section
  ) sections
)
insert into analysis.league_dashboard_release_candidate_snapshot_v6_20260823 (
  snapshot_version, season, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  member_count, member_set_sha256, dashboard, payload_sha256
)
select '20260823120000', candidate.season, candidate.analysis_version,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version, candidate.cohort_evidence_sha256,
  members.member_count, members.member_set_sha256, candidate.dashboard,
  reporting.canonical_jsonb_sha256_v1(candidate.dashboard)
from candidate
join member_set members using (season);

do $$
begin
  if (
    select count(*)
    from analysis.league_dashboard_release_candidate_snapshot_v6_20260823
    where snapshot_version = '20260823120000'
      and member_count = 16
      and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
  ) <> 1 then
    raise exception 'V6 league candidate snapshot was not sealed exactly once';
  end if;
end;
$$;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with current_members as materialized (
  select member.team_key, member.season, member.team_release_id,
    member.curated_build_id
  from analysis.league_member_releases_v6 member
  where member.season = '2025-26'
), member_set as (
  select season, count(*)::integer as member_count,
    reporting.canonical_jsonb_sha256_v1(
      jsonb_agg(jsonb_build_object(
        'team_key', team_key,
        'team_release_id', team_release_id::text,
        'curated_build_id', curated_build_id::text
      ) order by team_key)
    ) as member_set_sha256
  from current_members
  group by season
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct team_release_id) = 16
    and count(distinct curated_build_id) = 16
)
select snapshot.season, snapshot.analysis_version,
  snapshot.classification_view_version,
  snapshot.classification_evidence_sha256,
  snapshot.cohort_view_version, snapshot.cohort_evidence_sha256,
  snapshot.dashboard
from analysis.league_dashboard_release_candidate_snapshot_v6_20260823 snapshot
join member_set members
  on members.season = snapshot.season
 and members.member_count = snapshot.member_count
 and members.member_set_sha256 = snapshot.member_set_sha256
where snapshot.snapshot_version = '20260823120000'
  and snapshot.payload_sha256 = reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.league_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;

do $$
begin
  if to_regclass(
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260823'
    ) is null
    or to_regclass(
      'analysis.league_dashboard_release_candidates_analysis_window_v6'
    ) is null
    or not (
      select relrowsecurity
      from pg_class
      where oid =
        'analysis.league_dashboard_release_candidate_snapshot_v6_20260823'::regclass
    )
    or has_table_privilege(
      'web_reader',
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260823',
      'select'
    )
  then
    raise exception 'V6 league candidate snapshot boundary is incomplete';
  end if;
end;
$$;
