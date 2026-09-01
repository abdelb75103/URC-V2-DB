begin;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901010000'
      and name = 'urc_diagnosis_family_reporting_successor'
      and statements[1] = 'migration_sha256=b2d6af31bad2a49d26be8fe135c304fdc5a9c55a888f56cd26a5e32249cc903d'
  )
    or to_regclass('reporting.diagnosis_family_team_dashboards_v1') is null
    or to_regclass('reporting.diagnosis_family_league_dashboards_v1') is null
    or to_regclass('reporting.latest_team_dashboard_v7') is null
    or to_regclass('reporting.latest_league_dashboard_v7') is null
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_team_dashboards_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_league_dashboards_v1', 'select'
    )
  then
    raise exception 'Diagnosis-family reader execution-boundary precondition failed';
  end if;
end;
$$;

alter view reporting.diagnosis_family_team_dashboards_v1
  set (security_invoker = false);
alter view reporting.diagnosis_family_league_dashboards_v1
  set (security_invoker = false);

revoke all on reporting.diagnosis_family_team_dashboards_v1,
  reporting.diagnosis_family_league_dashboards_v1
from public, anon, authenticated, web_reader;

do $$
begin
  if not exists (
    select 1
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'reporting'
      and relation.relname = 'diagnosis_family_team_dashboards_v1'
      and coalesce(relation.reloptions, '{}'::text[])
        @> array['security_invoker=false']
  )
    or not exists (
      select 1
      from pg_class relation
      join pg_namespace namespace on namespace.oid = relation.relnamespace
      where namespace.nspname = 'reporting'
        and relation.relname = 'diagnosis_family_league_dashboards_v1'
        and coalesce(relation.reloptions, '{}'::text[])
          @> array['security_invoker=false']
    )
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_team_dashboards_v1', 'select'
    )
    or has_table_privilege(
      'web_reader', 'reporting.diagnosis_family_league_dashboards_v1', 'select'
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
    raise exception 'Diagnosis-family reader execution boundary is invalid';
  end if;
end;
$$;

commit;
