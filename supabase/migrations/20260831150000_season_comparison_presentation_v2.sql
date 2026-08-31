begin;

-- Presentation-only successor. It keeps every approved comparison value,
-- aligns the two hamstring labels used by the season source taxonomies, and
-- removes the retired severe-incidence section from the browser contract.

do $$
begin
  if (select count(*)
      from reporting.approved_dashboard_reader_target_v3
      where target_attested) <> 1
    or not exists (
      select 1
      from supabase_migrations.schema_migrations
      where version = '20260831140000'
        and name = 'season_comparison_reporting_v1'
        and statements = array[
          'migration_sha256=77b1e1cb6bc19eb53e264742d2e950431f327960744f36588b2352ad46bfa60b',
          'rule_version=season_comparison_reporting_2026_08_31_v1',
          'season_pair=2024-25_to_2025-26'
        ]
    )
  then
    raise exception 'Approved season comparison V1 predecessor is not attested';
  end if;
end;
$$;

create function reporting.season_comparison_presentation_v2(
  comparison jsonb
)
returns jsonb
language sql
immutable
strict
security definer
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_set(
    jsonb_set(
      comparison - 'severe',
      '{rule_version}',
      to_jsonb('season_comparison_reporting_2026_08_31_v2'::text),
      false
    ),
    '{diagnoses}',
    coalesce((
      select jsonb_agg(
        jsonb_set(
          jsonb_set(
            diagnosis,
            '{previous,diagnosis}',
            coalesce(to_jsonb(case
              when lower(btrim(diagnosis #>> '{previous,diagnosis}')) in (
                'hamstring injury',
                'hamstring muscle injury',
                'hamstring strain or tear'
              ) then 'Hamstring Injury'
              else diagnosis #>> '{previous,diagnosis}'
            end), 'null'::jsonb),
            false
          ),
          '{current,diagnosis}',
          coalesce(to_jsonb(case
            when lower(btrim(diagnosis #>> '{current,diagnosis}')) in (
              'hamstring injury',
              'hamstring muscle injury',
              'hamstring strain or tear'
            ) then 'Hamstring Injury'
            else diagnosis #>> '{current,diagnosis}'
          end), 'null'::jsonb),
          false
        ) order by ordinal
      )
      from jsonb_array_elements(
        coalesce(comparison -> 'diagnoses', '[]'::jsonb)
      ) with ordinality as rows(diagnosis, ordinal)
    ), '[]'::jsonb),
    false
  );
$$;

create view reporting.latest_team_season_comparison_v2
with (security_invoker = false, security_barrier = true) as
select team_key,
  reporting.season_comparison_presentation_v2(comparison) as comparison
from reporting.latest_team_season_comparison_v1;

create view reporting.latest_league_season_comparison_v2
with (security_invoker = false, security_barrier = true) as
select reporting.season_comparison_presentation_v2(comparison) as comparison
from reporting.latest_league_season_comparison_v1;

create view reporting.approved_dashboard_reader_target_v4
with (security_invoker = false, security_barrier = true) as
select target_attested
  and to_regclass('reporting.latest_team_season_comparison_v2') is not null
  and to_regclass('reporting.latest_league_season_comparison_v2') is not null
  as target_attested
from reporting.approved_dashboard_reader_target_v3;

do $$
begin
  if (select count(*) from reporting.latest_team_season_comparison_v2) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v2) <> 1
    or exists (
      select 1
      from reporting.latest_team_season_comparison_v2
      where comparison ->> 'rule_version'
          <> 'season_comparison_reporting_2026_08_31_v2'
        or comparison ? 'severe'
    )
    or exists (
      select 1
      from reporting.latest_league_season_comparison_v2
      where comparison ->> 'rule_version'
          <> 'season_comparison_reporting_2026_08_31_v2'
        or comparison ? 'severe'
    )
    or exists (
      select 1
      from reporting.latest_team_season_comparison_v2 team_comparison
      cross join lateral jsonb_array_elements(
        team_comparison.comparison -> 'diagnoses'
      ) diagnosis
      where lower(coalesce(diagnosis #>> '{previous,diagnosis}', '')) in (
          'hamstring muscle injury', 'hamstring strain or tear'
        )
        or lower(coalesce(diagnosis #>> '{current,diagnosis}', '')) in (
          'hamstring muscle injury', 'hamstring strain or tear'
        )
    )
    or exists (
      select 1
      from reporting.latest_team_season_comparison_v2 current
      join reporting.latest_team_season_comparison_v1 predecessor using (team_key)
      where current.comparison - 'rule_version' - 'diagnoses'
        <> predecessor.comparison - 'rule_version' - 'diagnoses' - 'severe'
    )
    or exists (
      select 1
      from reporting.latest_league_season_comparison_v2 current
      cross join reporting.latest_league_season_comparison_v1 predecessor
      where current.comparison - 'rule_version' - 'diagnoses'
        <> predecessor.comparison - 'rule_version' - 'diagnoses' - 'severe'
    )
    or (select count(*)
        from reporting.approved_dashboard_reader_target_v4
        where target_attested) <> 1
  then
    raise exception 'Season comparison presentation V2 contract is invalid';
  end if;
end;
$$;

revoke all on reporting.latest_team_season_comparison_v2,
  reporting.latest_league_season_comparison_v2,
  reporting.approved_dashboard_reader_target_v4
from public, anon, authenticated, web_reader;

revoke all on function reporting.season_comparison_presentation_v2(jsonb)
from public, anon, authenticated, web_reader;

revoke select on reporting.latest_team_season_comparison_v1,
  reporting.latest_league_season_comparison_v1,
  reporting.approved_dashboard_reader_target_v3
from web_reader;

grant select on reporting.latest_team_season_comparison_v2,
  reporting.latest_league_season_comparison_v2,
  reporting.approved_dashboard_reader_target_v4
to web_reader;

grant execute on function reporting.season_comparison_presentation_v2(jsonb)
to web_reader;

commit;
