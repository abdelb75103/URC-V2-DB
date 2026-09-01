begin;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901020000'
      and name = 'urc_diagnosis_family_reader_execution_boundary'
      and statements[1] = 'migration_sha256=f9d0cdce9b30e1bbe12dc6caacb2b37d60d1107833063281a158f0a1cc00b4b2'
  )
    or to_regclass('reporting.diagnosis_family_team_dashboard_payloads_v2') is not null
    or to_regclass('reporting.diagnosis_family_league_dashboard_payloads_v2') is not null
    or (select count(*) from reporting.diagnosis_family_team_dashboards_v1) <> 32
    or (select count(*) from reporting.diagnosis_family_league_dashboards_v1) <> 2
  then
    raise exception 'Diagnosis-family materialized-reader precondition failed';
  end if;
end;
$$;

create materialized view reporting.diagnosis_family_team_dashboard_payloads_v2 as
select team_key, season, dashboard
from reporting.diagnosis_family_team_dashboards_v1;

create unique index diagnosis_family_team_dashboard_payloads_v2_key
on reporting.diagnosis_family_team_dashboard_payloads_v2 (team_key, season);

create materialized view reporting.diagnosis_family_league_dashboard_payloads_v2 as
select season, dashboard
from reporting.diagnosis_family_league_dashboards_v1;

create unique index diagnosis_family_league_dashboard_payloads_v2_key
on reporting.diagnosis_family_league_dashboard_payloads_v2 (season);

revoke all on reporting.diagnosis_family_team_dashboard_payloads_v2,
  reporting.diagnosis_family_league_dashboard_payloads_v2
from public, anon, authenticated, web_reader;

create or replace view reporting.latest_team_dashboard_v7
with (security_invoker = false, security_barrier = true) as
select team_key, dashboard ->> 'team' as team, season,
  (dashboard ->> 'generated_at')::timestamptz as generated_at,
  dashboard -> 'analysis_window' as analysis_window,
  dashboard -> 'method' as method, dashboard -> 'coverage' as coverage,
  dashboard -> 'headline' as headline,
  dashboard -> 'setting_split' as setting_split,
  dashboard -> 'setting_metrics' as setting_metrics,
  dashboard -> 'monthly' as monthly,
  dashboard -> 'body_locations' as body_locations,
  dashboard -> 'injury_types' as injury_types,
  dashboard -> 'injury_profiles' as injury_profiles,
  dashboard -> 'diagnosis_families' as diagnosis_families,
  dashboard -> 'illness_profiles' as illness_profiles,
  dashboard -> 'illness_summary' as illness_summary,
  dashboard -> 'injury_type_families' as injury_type_families,
  dashboard -> 'severity_distribution' as severity_distribution,
  dashboard -> 'contact_distribution' as contact_distribution,
  dashboard -> 'prior_season' as prior_season,
  dashboard -> 'limitations' as limitations,
  dashboard -> 'preliminary_monthly_rates' as preliminary_monthly_rates
from reporting.diagnosis_family_team_dashboard_payloads_v2;

create or replace view reporting.latest_league_dashboard_v7
with (security_invoker = false, security_barrier = true) as
select dashboard ->> 'team' as team, season,
  (dashboard ->> 'generated_at')::timestamptz as generated_at,
  dashboard -> 'analysis_window' as analysis_window,
  dashboard -> 'method' as method, dashboard -> 'coverage' as coverage,
  dashboard -> 'headline' as headline,
  dashboard -> 'setting_split' as setting_split,
  dashboard -> 'setting_metrics' as setting_metrics,
  dashboard -> 'monthly' as monthly,
  dashboard -> 'body_locations' as body_locations,
  dashboard -> 'injury_types' as injury_types,
  dashboard -> 'injury_profiles' as injury_profiles,
  dashboard -> 'diagnosis_families' as diagnosis_families,
  dashboard -> 'illness_profiles' as illness_profiles,
  dashboard -> 'illness_summary' as illness_summary,
  dashboard -> 'injury_type_families' as injury_type_families,
  dashboard -> 'severity_distribution' as severity_distribution,
  dashboard -> 'contact_distribution' as contact_distribution,
  dashboard -> 'prior_season' as prior_season,
  dashboard -> 'limitations' as limitations,
  dashboard -> 'preliminary_monthly_rates' as preliminary_monthly_rates
from reporting.diagnosis_family_league_dashboard_payloads_v2;

revoke all on reporting.latest_team_dashboard_v7,
  reporting.latest_league_dashboard_v7
from public, anon, authenticated;
grant select on reporting.latest_team_dashboard_v7,
  reporting.latest_league_dashboard_v7
to web_reader;

do $$
begin
  if (select count(*) from reporting.diagnosis_family_team_dashboard_payloads_v2) <> 32
    or (select count(*) from reporting.diagnosis_family_league_dashboard_payloads_v2) <> 2
    or exists (
      select 1
      from reporting.diagnosis_family_team_dashboard_payloads_v2 snapshot
      join reporting.diagnosis_family_team_dashboards_v1 source
        using (team_key, season)
      where snapshot.dashboard <> source.dashboard
    )
    or exists (
      select 1
      from reporting.diagnosis_family_league_dashboard_payloads_v2 snapshot
      join reporting.diagnosis_family_league_dashboards_v1 source using (season)
      where snapshot.dashboard <> source.dashboard
    )
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_team_dashboard_payloads_v2', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_league_dashboard_payloads_v2', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_dashboard_v7', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_dashboard_v7', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_team_season_comparison_v5', 'select'
    )
    or not has_table_privilege(
      'web_reader', 'reporting.latest_league_season_comparison_v5', 'select'
    )
  then
    raise exception 'Diagnosis-family materialized-reader boundary is invalid';
  end if;
end;
$$;

commit;

