begin;

-- Additive correction for the released acute_concussion_* variants omitted by
-- the V3 presentation-family matcher. All other comparison values are retained.

do $$
begin
  if (select count(*)
      from reporting.approved_dashboard_reader_target_v5
      where target_attested) <> 1
    or not exists (
      select 1
      from supabase_migrations.schema_migrations
      where version = '20260831160000'
        and name = 'season_comparison_diagnosis_top_three_v3'
        and statements = array[
          'migration_sha256=4803835b90a840e321414f0965daf8958bf9b100db4fecfd7a8342c90b4902ea',
          'rule_version=season_comparison_reporting_2026_08_31_v3',
          'change=ranked_top_three_diagnosis_families_by_setting_and_season'
        ]
    )
  then
    raise exception 'Approved season comparison V3 predecessor is not attested';
  end if;
end;
$$;

create function reporting.season_comparison_diagnosis_family_v4(
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
    when lower(btrim(diagnosis_code)) = 'concussion'
      or lower(btrim(diagnosis_code)) ~ '^concussion_'
      or lower(btrim(diagnosis_code)) ~ '^acute_concussion(?:_|$)'
      or lower(btrim(diagnosis_code)) ~ '^dx_concussion_'
      then 'Concussion'
    else diagnosis_label
  end;
$$;

create function reporting.season_comparison_top_diagnoses_v4(
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
    select reporting.season_comparison_diagnosis_family_v4(
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

create function reporting.build_season_comparison_v4(
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
  comparison := reporting.build_season_comparison_v3(
    previous_dashboard,
    current_dashboard,
    comparison_scope
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
    'previous', reporting.season_comparison_top_diagnoses_v4(
      previous_dashboard, setting
    ),
    'current', reporting.season_comparison_top_diagnoses_v4(
      current_dashboard, setting
    )
  ) order by ordinal)
  into diagnoses
  from settings;

  return jsonb_set(
    jsonb_set(
      comparison,
      '{rule_version}',
      to_jsonb('season_comparison_reporting_2026_08_31_v4'::text),
      false
    ),
    '{diagnoses}',
    diagnoses,
    false
  );
end;
$$;

create view reporting.latest_team_season_comparison_v4
with (security_invoker = false, security_barrier = true) as
select previous.team_key,
  reporting.build_season_comparison_v4(
    to_jsonb(previous) - 'team_key',
    to_jsonb(current) - 'team_key',
    'team'
  ) as comparison
from reporting.latest_team_dashboard_v6 previous
join reporting.latest_team_dashboard_v6 current
  on current.team_key = previous.team_key
 and current.season = '2025-26'
where previous.season = '2024-25';

create view reporting.latest_league_season_comparison_v4
with (security_invoker = false, security_barrier = true) as
select reporting.build_season_comparison_v4(
    to_jsonb(previous),
    to_jsonb(current),
    'league'
  ) as comparison
from reporting.latest_league_dashboard_v6 previous
cross join reporting.latest_league_dashboard_v6 current
where previous.season = '2024-25'
  and current.season = '2025-26';

create view reporting.approved_dashboard_reader_target_v6
with (security_invoker = false, security_barrier = true) as
select target_attested
  and to_regclass('reporting.latest_team_season_comparison_v4') is not null
  and to_regclass('reporting.latest_league_season_comparison_v4') is not null
  as target_attested
from reporting.approved_dashboard_reader_target_v5;

do $$
begin
  if reporting.season_comparison_diagnosis_family_v4(
      'acute_concussion_with_visual_symptoms',
      'Acute Concussion with visual symptoms'
    ) <> 'Concussion'
    or (select count(*) from reporting.latest_team_season_comparison_v4) <> 16
    or (select count(*) from reporting.latest_league_season_comparison_v4) <> 1
    or exists (
      select 1
      from reporting.latest_team_season_comparison_v4 current
      join reporting.latest_team_season_comparison_v3 predecessor using (team_key)
      where current.comparison ->> 'rule_version'
          <> 'season_comparison_reporting_2026_08_31_v4'
        or current.comparison - 'rule_version' - 'diagnoses'
          <> predecessor.comparison - 'rule_version' - 'diagnoses'
    )
    or exists (
      select 1
      from reporting.latest_league_season_comparison_v4 current
      cross join reporting.latest_league_season_comparison_v3 predecessor
      where current.comparison ->> 'rule_version'
          <> 'season_comparison_reporting_2026_08_31_v4'
        or current.comparison - 'rule_version' - 'diagnoses'
          <> predecessor.comparison - 'rule_version' - 'diagnoses'
    )
    or (select count(*)
        from reporting.approved_dashboard_reader_target_v6
        where target_attested) <> 1
  then
    raise exception 'Season comparison concussion-family V4 contract is invalid';
  end if;
end;
$$;

revoke all on reporting.latest_team_season_comparison_v4,
  reporting.latest_league_season_comparison_v4,
  reporting.approved_dashboard_reader_target_v6
from public, anon, authenticated, web_reader;

revoke all on function reporting.season_comparison_diagnosis_family_v4(
  text, text
) from public, anon, authenticated, web_reader;
revoke all on function reporting.season_comparison_top_diagnoses_v4(
  jsonb, text
) from public, anon, authenticated, web_reader;
revoke all on function reporting.build_season_comparison_v4(
  jsonb, jsonb, text
) from public, anon, authenticated, web_reader;

revoke select on reporting.latest_team_season_comparison_v3,
  reporting.latest_league_season_comparison_v3,
  reporting.approved_dashboard_reader_target_v5
from web_reader;
revoke execute on function reporting.build_season_comparison_v3(
  jsonb, jsonb, text
) from web_reader;
revoke execute on function reporting.build_season_comparison_v1(
  jsonb, jsonb, text
) from web_reader;

grant select on reporting.latest_team_season_comparison_v4,
  reporting.latest_league_season_comparison_v4,
  reporting.approved_dashboard_reader_target_v6
to web_reader;

grant execute on function reporting.build_season_comparison_v4(
  jsonb, jsonb, text
) to web_reader;

commit;
