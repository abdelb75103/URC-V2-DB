begin;

-- Additive successor for the diagnosis driver. It preserves every existing
-- comparison section and replaces the single leading diagnosis with the top
-- three diagnosis families for Overall, Match and Training in each season.

do $$
begin
  if (select count(*)
      from reporting.approved_dashboard_reader_target_v4
      where target_attested) <> 1
    or not exists (
      select 1
      from supabase_migrations.schema_migrations
      where version = '20260831150000'
        and name = 'season_comparison_presentation_v2'
        and statements = array[
          'migration_sha256=85722743687a87ce76d0d927687a2113b9e27b11b9ada8da0da3741e474384c3',
          'rule_version=season_comparison_reporting_2026_08_31_v2',
          'change=governed_hamstring_display_alias_and_remove_severe_browser_projection'
        ]
    )
  then
    raise exception 'Approved season comparison V2 predecessor is not attested';
  end if;
end;
$$;

create function reporting.season_comparison_diagnosis_family_v3(
  diagnosis_code text,
  diagnosis_label text
)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case
    when lower(btrim(diagnosis_label)) in (
      'hamstring injury',
      'hamstring muscle injury',
      'hamstring strain or tear',
      'hamstring strain/tear',
      'grade 3 hamstring strain'
    ) then 'Hamstring Injury'
    when lower(btrim(diagnosis_code)) in (
      'acute_concussion',
      'concussion'
    )
      or lower(btrim(diagnosis_code)) like 'concussion\_%' escape '\'
      or lower(btrim(diagnosis_code)) like 'dx\_concussion\_%' escape '\'
      then 'Concussion'
    else diagnosis_label
  end;
$$;

create function reporting.season_comparison_top_diagnoses_v3(
  dashboard jsonb,
  setting_name text
)
returns jsonb
language sql
immutable
strict
set search_path = pg_catalog, pg_temp
as $$
  with eligible as (
    select reporting.season_comparison_diagnosis_family_v3(
        item ->> 'code', item ->> 'label'
      ) as diagnosis,
      (item ->> 'time_loss_injuries')::numeric as time_loss_injuries,
      (item ->> 'incidence_per_1000h')::numeric as incidence_per_1000h,
      (item ->> 'burden_per_1000h')::numeric as burden_per_1000h
    from jsonb_array_elements(dashboard -> 'injury_profiles') item
    where item ->> 'dimension' = 'diagnosis'
      and item ->> 'setting' = setting_name
      and (item ->> 'time_loss_injuries')::numeric > 0
      and lower(item ->> 'code') !~ '(^|__)unknown(_|__|$)'
      and lower(item ->> 'code') not in (
        'other_unclassified', 'unmapped_review'
      )
      and lower(item ->> 'label')
        !~ '(^|[[:space:]·/])unknown($|[[:space:]/])'
  ), families as (
    select diagnosis,
      sum(time_loss_injuries) as time_loss_injuries,
      sum(incidence_per_1000h) as incidence_per_1000h,
      sum(burden_per_1000h) as burden_per_1000h
    from eligible
    group by diagnosis
  ), ranked as (
    select row_number() over (
        order by time_loss_injuries desc,
          burden_per_1000h desc nulls last,
          diagnosis
      ) as rank,
      diagnosis,
      time_loss_injuries,
      incidence_per_1000h,
      burden_per_1000h
    from families
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank', rank,
    'diagnosis', diagnosis,
    'time_loss_injuries', time_loss_injuries,
    'incidence_per_1000h', incidence_per_1000h,
    'burden_per_1000h', burden_per_1000h
  ) order by rank), '[]'::jsonb)
  from ranked
  where rank <= 3;
$$;

create function reporting.build_season_comparison_v3(
  previous_dashboard jsonb,
  current_dashboard jsonb,
  comparison_scope text
)
returns jsonb
language plpgsql
stable
strict
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  comparison jsonb;
  diagnoses jsonb;
begin
  comparison := reporting.season_comparison_presentation_v2(
    reporting.build_season_comparison_v1(
      previous_dashboard,
      current_dashboard,
      comparison_scope
    )
  );

  with settings(ordinal, setting, label) as (
    values
      (1, 'all', 'Overall'),
      (2, 'match', 'Match'),
      (3, 'training', 'Training')
  )
  select jsonb_agg(jsonb_build_object(
    'setting', setting,
    'label', label,
    'previous', reporting.season_comparison_top_diagnoses_v3(
      previous_dashboard, setting
    ),
    'current', reporting.season_comparison_top_diagnoses_v3(
      current_dashboard, setting
    )
  ) order by ordinal)
  into diagnoses
  from settings;

  return jsonb_set(
    jsonb_set(
      comparison,
      '{rule_version}',
      to_jsonb('season_comparison_reporting_2026_08_31_v3'::text),
      false
    ),
    '{diagnoses}',
    diagnoses,
    false
  );
end;
$$;

create view reporting.latest_team_season_comparison_v3
with (security_invoker = false, security_barrier = true) as
select previous.team_key,
  reporting.build_season_comparison_v3(
    to_jsonb(previous) - 'team_key',
    to_jsonb(current) - 'team_key',
    'team'
  ) as comparison
from reporting.latest_team_dashboard_v6 previous
join reporting.latest_team_dashboard_v6 current
  on current.team_key = previous.team_key
 and current.season = '2025-26'
where previous.season = '2024-25';

create view reporting.latest_league_season_comparison_v3
with (security_invoker = false, security_barrier = true) as
select reporting.build_season_comparison_v3(
    to_jsonb(previous),
    to_jsonb(current),
    'league'
  ) as comparison
from reporting.latest_league_dashboard_v6 previous
cross join reporting.latest_league_dashboard_v6 current
where previous.season = '2024-25'
  and current.season = '2025-26';

create view reporting.approved_dashboard_reader_target_v5
with (security_invoker = false, security_barrier = true) as
select target_attested
  and to_regclass('reporting.latest_team_season_comparison_v3') is not null
  and to_regclass('reporting.latest_league_season_comparison_v3') is not null
  as target_attested
from reporting.approved_dashboard_reader_target_v4;

do $$
begin
  if (select count(*) from reporting.latest_team_season_comparison_v3) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v3) <> 1
    or exists (
      select 1
      from reporting.latest_team_season_comparison_v3 current
      join reporting.latest_team_season_comparison_v2 predecessor using (team_key)
      where current.comparison ->> 'rule_version'
          <> 'season_comparison_reporting_2026_08_31_v3'
        or current.comparison - 'rule_version' - 'diagnoses'
          <> predecessor.comparison - 'rule_version' - 'diagnoses'
    )
    or exists (
      select 1
      from reporting.latest_league_season_comparison_v3 current
      cross join reporting.latest_league_season_comparison_v2 predecessor
      where current.comparison ->> 'rule_version'
          <> 'season_comparison_reporting_2026_08_31_v3'
        or current.comparison - 'rule_version' - 'diagnoses'
          <> predecessor.comparison - 'rule_version' - 'diagnoses'
    )
    or exists (
      select 1
      from (
        select comparison from reporting.latest_team_season_comparison_v3
        union all
        select comparison from reporting.latest_league_season_comparison_v3
      ) comparisons
      cross join lateral jsonb_array_elements(
        comparisons.comparison -> 'diagnoses'
      ) setting
      where jsonb_typeof(setting -> 'previous') <> 'array'
        or jsonb_typeof(setting -> 'current') <> 'array'
        or jsonb_array_length(setting -> 'previous') > 3
        or jsonb_array_length(setting -> 'current') > 3
    )
    or exists (
      select 1
      from (
        select comparison from reporting.latest_team_season_comparison_v3
        union all
        select comparison from reporting.latest_league_season_comparison_v3
      ) comparisons
      cross join lateral jsonb_array_elements(
        comparisons.comparison -> 'diagnoses'
      ) setting
      cross join lateral jsonb_array_elements(
        (setting -> 'previous') || (setting -> 'current')
      ) diagnosis
      where (diagnosis ->> 'rank')::integer not between 1 and 3
        or lower(diagnosis ->> 'diagnosis')
          ~ '(^|[[:space:]·/])unknown($|[[:space:]/])'
    )
    or (select count(*)
        from reporting.approved_dashboard_reader_target_v5
        where target_attested) <> 1
  then
    raise exception 'Season comparison diagnosis top-three V3 contract is invalid';
  end if;
end;
$$;

revoke all on reporting.latest_team_season_comparison_v3,
  reporting.latest_league_season_comparison_v3,
  reporting.approved_dashboard_reader_target_v5
from public, anon, authenticated, web_reader;

revoke all on function reporting.season_comparison_diagnosis_family_v3(
  text, text
) from public, anon, authenticated, web_reader;
revoke all on function reporting.season_comparison_top_diagnoses_v3(
  jsonb, text
) from public, anon, authenticated, web_reader;
revoke all on function reporting.build_season_comparison_v3(
  jsonb, jsonb, text
) from public, anon, authenticated, web_reader;

revoke select on reporting.latest_team_season_comparison_v2,
  reporting.latest_league_season_comparison_v2,
  reporting.approved_dashboard_reader_target_v4
from web_reader;
revoke execute on function reporting.season_comparison_presentation_v2(jsonb)
from web_reader;

grant select on reporting.latest_team_season_comparison_v3,
  reporting.latest_league_season_comparison_v3,
  reporting.approved_dashboard_reader_target_v5
to web_reader;

grant execute on function reporting.build_season_comparison_v3(
  jsonb, jsonb, text
) to web_reader;

commit;
