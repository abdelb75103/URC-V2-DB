begin;

-- This additive reader derives the two-season comparison only from the current
-- approved dashboard readers. It does not change either immutable season
-- payload, cohort, classification or denominator.

create function reporting.season_comparison_exposure_qualification_v1(
  dashboard jsonb
)
returns jsonb
language plpgsql
immutable
strict
set search_path = pg_catalog, reporting
as $$
declare
  exposure_hours numeric := (dashboard #>> '{coverage,hours}')::numeric;
  exposure_status text := lower(coalesce(
    dashboard #>> '{coverage,included_exposure_status}', ''
  ));
  status text;
  qualification text;
begin
  if exposure_hours is null or exposure_hours <= 0 then
    status := 'unavailable';
    qualification := 'Rate unavailable because the approved exposure denominator is unavailable.';
  elsif exposure_status like '%estimate%' then
    status := 'estimated';
    qualification := 'Rates use a released estimated exposure denominator rather than fully source-backed exposure.';
  elsif exposure_status like '%incomplete%' then
    status := 'incomplete';
    qualification := 'Released source-backed exposure may be incomplete.';
  else
    status := 'available';
    qualification := null;
  end if;

  return jsonb_build_object(
    'exposure_hours', exposure_hours,
    'status', status,
    'qualification', qualification
  );
end;
$$;

create function reporting.season_comparison_severe_value_v1(
  dashboard jsonb
)
returns jsonb
language plpgsql
immutable
strict
set search_path = pg_catalog, reporting
as $$
declare
  total_time_loss numeric;
  known_duration_time_loss numeric;
  known_band_time_loss numeric;
  severe_numerator numeric;
  exposure_hours numeric := (dashboard #>> '{coverage,hours}')::numeric;
  exposure_status text := lower(coalesce(
    dashboard #>> '{coverage,included_exposure_status}', ''
  ));
  has_setting_rows boolean;
  rate_status text;
  exposure_qualification text;
  duration_qualification text :=
    'Unknown and, where present, right-censored durations are excluded from the severe numerator.';
  rate numeric;
  lower_rate numeric;
  upper_rate numeric;
  confidence_interval jsonb;
begin
  select (item ->> 'value')::numeric
  into total_time_loss
  from jsonb_array_elements(coalesce(dashboard -> 'headline', '[]'::jsonb)) item
  where item ->> 'key' = 'time_loss_injuries'
  limit 1;

  select (item ->> 'denominator')::numeric
  into known_duration_time_loss
  from jsonb_array_elements(coalesce(dashboard -> 'headline', '[]'::jsonb)) item
  where item ->> 'key' = 'severity_mean_days'
  limit 1;

  select exists (
    select 1
    from jsonb_array_elements(coalesce(
      dashboard -> 'severity_distribution', '[]'::jsonb
    )) item
    where item ? 'setting'
  ) into has_setting_rows;

  select (item ->> 'time_loss_injuries')::numeric
  into severe_numerator
  from jsonb_array_elements(coalesce(
    dashboard -> 'severity_distribution', '[]'::jsonb
  )) item
  where item ->> 'key' = 'greater_than_twenty_eight_days'
    and (not has_setting_rows or item ->> 'setting' = 'all')
  limit 1;

  select coalesce(sum((item ->> 'time_loss_injuries')::numeric), 0)
  into known_band_time_loss
  from jsonb_array_elements(coalesce(
    dashboard -> 'severity_distribution', '[]'::jsonb
  )) item
  where item ->> 'key' in (
      'one_day',
      'two_to_three_days',
      'four_to_seven_days',
      'eight_to_twenty_eight_days',
      'greater_than_twenty_eight_days'
    )
    and (not has_setting_rows or item ->> 'setting' = 'all');

  -- Some team payloads omit empty severity bands. An absent severe row means
  -- zero only when the remaining known-duration bands reconcile exactly to the
  -- released mean-severity denominator.
  if severe_numerator is null
    and known_duration_time_loss is not null
    and known_band_time_loss = known_duration_time_loss then
    severe_numerator := 0;
  end if;

  if severe_numerator is null then
    rate_status := 'unavailable_severe_band';
    exposure_qualification :=
      'The approved severe-duration band is unavailable for this season.';
  elsif exposure_hours is null or exposure_hours <= 0 then
    rate_status := 'unavailable_exposure';
    exposure_qualification :=
      'Rate unavailable because the approved exposure denominator is unavailable.';
  elsif exposure_status like '%estimate%' then
    rate_status := 'qualified_estimated_exposure';
    exposure_qualification :=
      'Rate uses a released estimated exposure denominator rather than fully source-backed exposure.';
  elsif exposure_status like '%incomplete%' then
    rate_status := 'qualified_incomplete_exposure';
    exposure_qualification := 'Released source-backed exposure may be incomplete.';
  else
    rate_status := 'available';
    exposure_qualification := null;
  end if;

  if severe_numerator is not null and exposure_hours is not null
    and exposure_hours > 0 then
    rate := severe_numerator * 1000 / exposure_hours;
    if severe_numerator = 0 then
      lower_rate := 0;
      upper_rate := -ln(0.025) * 1000 / exposure_hours;
    else
      lower_rate := severe_numerator * power(
        1 - 1 / (9 * severe_numerator)
          - 1.959963984540054 / (3 * sqrt(severe_numerator)),
        3
      ) * 1000 / exposure_hours;
      upper_rate := (severe_numerator + 1) * power(
        1 - 1 / (9 * (severe_numerator + 1))
          + 1.959963984540054 / (3 * sqrt(severe_numerator + 1)),
        3
      ) * 1000 / exposure_hours;
    end if;
    confidence_interval := jsonb_build_object(
      'lower', greatest(0, lower_rate),
      'upper', upper_rate,
      'method',
        'Byar approximate 95% Poisson confidence interval with exact zero-event upper limit'
    );
  end if;

  return jsonb_build_object(
    'incidence_per_1000h', rate,
    'confidence_interval', confidence_interval,
    'numerator', severe_numerator,
    'exposure_hours', exposure_hours,
    'known_duration_time_loss_injuries', known_duration_time_loss,
    'total_time_loss_injuries', total_time_loss,
    'known_duration_coverage_percent', case
      when total_time_loss > 0 and known_duration_time_loss is not null
        then known_duration_time_loss * 100 / total_time_loss
      else null
    end,
    'excluded_unknown_or_censored_time_loss_injuries', case
      when total_time_loss is not null and known_duration_time_loss is not null
        then greatest(total_time_loss - known_duration_time_loss, 0)
      else null
    end,
    'rate_status', rate_status,
    'qualification', concat_ws(' ', exposure_qualification, case
      when severe_numerator is not null then duration_qualification
      else null
    end)
  );
end;
$$;

create function reporting.build_season_comparison_v1(
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
  kpis jsonb;
  impact jsonb;
  monthly jsonb;
  diagnoses jsonb;
begin
  if comparison_scope not in ('team', 'league') then
    raise exception 'season comparison scope must be team or league';
  end if;
  if previous_dashboard ->> 'season' <> '2024-25'
    or current_dashboard ->> 'season' <> '2025-26' then
    raise exception 'season comparison requires 2024-25 then 2025-26';
  end if;

  with metric_specs(ordinal, key, label, headline_key, unit) as (
    values
      (1, 'time_loss_incidence', 'TL injury incidence',
        'incidence_per_1000h', 'TL injuries per 1,000 player-hours'),
      (2, 'mean_severity', 'Mean severity',
        'severity_mean_days', 'days lost per injury'),
      (3, 'injury_burden', 'Injury burden',
        'burden_per_1000h', 'days lost per 1,000 player-hours'),
      (4, 'time_loss_injuries', 'Time-loss injuries',
        'time_loss_injuries', 'TL injuries')
  ), metric_values as (
    select specs.*,
      (select (item ->> 'value')::numeric
       from jsonb_array_elements(previous_dashboard -> 'headline') item
       where item ->> 'key' = specs.headline_key limit 1) as previous_value,
      (select (item ->> 'value')::numeric
       from jsonb_array_elements(current_dashboard -> 'headline') item
       where item ->> 'key' = specs.headline_key limit 1) as current_value
    from metric_specs specs
  )
  select jsonb_agg(jsonb_build_object(
    'key', key,
    'label', label,
    'previous', jsonb_build_object('value', previous_value, 'unit', unit),
    'current', jsonb_build_object('value', current_value, 'unit', unit),
    'outcome_improvement_percent', case
      when previous_value is null or previous_value = 0 or current_value is null
        then null
      else 100 * (previous_value - current_value) / previous_value
    end
  ) order by ordinal)
  into kpis
  from metric_values;

  with settings(ordinal, setting, label) as (
    values
      (1, 'all', 'Overall'),
      (2, 'match', 'Match'),
      (3, 'training', 'Training')
  )
  select jsonb_agg(jsonb_build_object(
    'setting', setting,
    'label', label,
    'previous', coalesce((
      select jsonb_build_object(
        'time_loss_incidence_per_1000h',
          (item ->> 'incidence_per_1000h')::numeric,
        'mean_severity_days', (item ->> 'mean_severity_days')::numeric,
        'burden_per_1000h', (item ->> 'burden_per_1000h')::numeric,
        'time_loss_injuries', (item ->> 'time_loss_injuries')::numeric,
        'exposure_hours', (item ->> 'exposure_hours')::numeric
      )
      from jsonb_array_elements(previous_dashboard -> 'setting_metrics') item
      where item ->> 'setting' = settings.setting
      limit 1
    ), case when settings.setting = 'all' then jsonb_build_object(
      'time_loss_incidence_per_1000h', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(previous_dashboard -> 'headline') item
        where item ->> 'key' = 'incidence_per_1000h'
        limit 1
      ),
      'mean_severity_days', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(previous_dashboard -> 'headline') item
        where item ->> 'key' = 'severity_mean_days'
        limit 1
      ),
      'burden_per_1000h', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(previous_dashboard -> 'headline') item
        where item ->> 'key' = 'burden_per_1000h'
        limit 1
      ),
      'time_loss_injuries', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(previous_dashboard -> 'headline') item
        where item ->> 'key' = 'time_loss_injuries'
        limit 1
      ),
      'exposure_hours', (previous_dashboard #>> '{coverage,hours}')::numeric
    ) else jsonb_build_object(
      'time_loss_incidence_per_1000h', null,
      'mean_severity_days', null,
      'burden_per_1000h', null,
      'time_loss_injuries', null,
      'exposure_hours', null
    ) end),
    'current', coalesce((
      select jsonb_build_object(
        'time_loss_incidence_per_1000h',
          (item ->> 'incidence_per_1000h')::numeric,
        'mean_severity_days', (item ->> 'mean_severity_days')::numeric,
        'burden_per_1000h', (item ->> 'burden_per_1000h')::numeric,
        'time_loss_injuries', (item ->> 'time_loss_injuries')::numeric,
        'exposure_hours', (item ->> 'exposure_hours')::numeric
      )
      from jsonb_array_elements(current_dashboard -> 'setting_metrics') item
      where item ->> 'setting' = settings.setting
      limit 1
    ), case when settings.setting = 'all' then jsonb_build_object(
      'time_loss_incidence_per_1000h', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(current_dashboard -> 'headline') item
        where item ->> 'key' = 'incidence_per_1000h'
        limit 1
      ),
      'mean_severity_days', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(current_dashboard -> 'headline') item
        where item ->> 'key' = 'severity_mean_days'
        limit 1
      ),
      'burden_per_1000h', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(current_dashboard -> 'headline') item
        where item ->> 'key' = 'burden_per_1000h'
        limit 1
      ),
      'time_loss_injuries', (
        select (item ->> 'value')::numeric
        from jsonb_array_elements(current_dashboard -> 'headline') item
        where item ->> 'key' = 'time_loss_injuries'
        limit 1
      ),
      'exposure_hours', (current_dashboard #>> '{coverage,hours}')::numeric
    ) else jsonb_build_object(
      'time_loss_incidence_per_1000h', null,
      'mean_severity_days', null,
      'burden_per_1000h', null,
      'time_loss_injuries', null,
      'exposure_hours', null
    ) end)
  ) order by ordinal)
  into impact
  from settings;

  with months(ordinal, month_number, month_key, label) as (
    values
      (1, 9, '2024-09', 'Sep'),
      (2, 10, '2024-10', 'Oct'),
      (3, 11, '2024-11', 'Nov'),
      (4, 12, '2024-12', 'Dec'),
      (5, 1, '2025-01', 'Jan'),
      (6, 2, '2025-02', 'Feb'),
      (7, 3, '2025-03', 'Mar'),
      (8, 4, '2025-04', 'Apr'),
      (9, 5, '2025-05', 'May'),
      (10, 6, '2025-06', 'Jun')
  )
  select jsonb_agg(jsonb_build_object(
    'month_key', month_key,
    'label', label,
    'previous_time_loss_injuries', coalesce((
      select (item ->> 'time_loss_injuries')::numeric
      from jsonb_array_elements(previous_dashboard -> 'monthly') item
      where case
        when item ->> 'month' ~ '^\d{4}-\d{2}'
          then substring(item ->> 'month' from 6 for 2)::integer
        else extract(month from to_date(item ->> 'month', 'Mon YYYY'))::integer
      end = months.month_number
      limit 1
    ), 0),
    'current_time_loss_injuries', coalesce((
      select (item ->> 'time_loss_injuries')::numeric
      from jsonb_array_elements(current_dashboard -> 'monthly') item
      where case
        when item ->> 'month' ~ '^\d{4}-\d{2}'
          then substring(item ->> 'month' from 6 for 2)::integer
        else extract(month from to_date(item ->> 'month', 'Mon YYYY'))::integer
      end = months.month_number
      limit 1
    ), 0)
  ) order by ordinal)
  into monthly
  from months;

  with settings(ordinal, setting, label) as (
    values
      (1, 'all', 'Overall'),
      (2, 'match', 'Match'),
      (3, 'training', 'Training')
  )
  select jsonb_agg(jsonb_build_object(
    'setting', setting,
    'label', label,
    'previous', (
      select jsonb_build_object(
        'diagnosis', item ->> 'label',
        'time_loss_injuries', (item ->> 'time_loss_injuries')::numeric,
        'incidence_per_1000h', (item ->> 'incidence_per_1000h')::numeric,
        'burden_per_1000h', (item ->> 'burden_per_1000h')::numeric
      )
      from jsonb_array_elements(previous_dashboard -> 'injury_profiles') item
      where item ->> 'dimension' = 'diagnosis'
        and item ->> 'setting' = settings.setting
        and (item ->> 'time_loss_injuries')::numeric > 0
        and lower(item ->> 'code') !~ '(^|__)unknown(_|__|$)'
        and lower(item ->> 'code') not in (
          'other_unclassified', 'unmapped_review'
        )
        and lower(item ->> 'label')
          !~ '(^|[[:space:]·/])unknown($|[[:space:]/])'
      order by (item ->> 'time_loss_injuries')::numeric desc,
        (item ->> 'burden_per_1000h')::numeric desc nulls last,
        item ->> 'label', item ->> 'code'
      limit 1
    ),
    'current', (
      select jsonb_build_object(
        'diagnosis', item ->> 'label',
        'time_loss_injuries', (item ->> 'time_loss_injuries')::numeric,
        'incidence_per_1000h', (item ->> 'incidence_per_1000h')::numeric,
        'burden_per_1000h', (item ->> 'burden_per_1000h')::numeric
      )
      from jsonb_array_elements(current_dashboard -> 'injury_profiles') item
      where item ->> 'dimension' = 'diagnosis'
        and item ->> 'setting' = settings.setting
        and (item ->> 'time_loss_injuries')::numeric > 0
        and lower(item ->> 'code') !~ '(^|__)unknown(_|__|$)'
        and lower(item ->> 'code') not in (
          'other_unclassified', 'unmapped_review'
        )
        and lower(item ->> 'label')
          !~ '(^|[[:space:]·/])unknown($|[[:space:]/])'
      order by (item ->> 'time_loss_injuries')::numeric desc,
        (item ->> 'burden_per_1000h')::numeric desc nulls last,
        item ->> 'label', item ->> 'code'
      limit 1
    )
  ) order by ordinal)
  into diagnoses
  from settings;

  return jsonb_build_object(
    'rule_version', 'season_comparison_reporting_2026_08_31_v1',
    'scope', comparison_scope,
    'previous_season', '2024-25',
    'current_season', '2025-26',
    'kpis', kpis,
    'impact', impact,
    'monthly', monthly,
    'diagnoses', diagnoses,
    'exposure', jsonb_build_object(
      'previous', reporting.season_comparison_exposure_qualification_v1(
        previous_dashboard
      ),
      'current', reporting.season_comparison_exposure_qualification_v1(
        current_dashboard
      )
    ),
    'severe', jsonb_build_object(
      'label', 'Severe injury incidence (>28 days)',
      'unit', 'TL injuries per 1,000 player-hours',
      'previous', reporting.season_comparison_severe_value_v1(
        previous_dashboard
      ),
      'current', reporting.season_comparison_severe_value_v1(
        current_dashboard
      )
    )
  );
end;
$$;

create view reporting.latest_team_season_comparison_v1
with (security_invoker = false, security_barrier = true) as
select previous.team_key,
  reporting.build_season_comparison_v1(
    to_jsonb(previous) - 'team_key',
    to_jsonb(current) - 'team_key',
    'team'
  ) as comparison
from reporting.latest_team_dashboard_v6 previous
join reporting.latest_team_dashboard_v6 current
  on current.team_key = previous.team_key
 and current.season = '2025-26'
where previous.season = '2024-25';

create view reporting.latest_league_season_comparison_v1
with (security_invoker = false, security_barrier = true) as
select reporting.build_season_comparison_v1(
    to_jsonb(previous),
    to_jsonb(current),
    'league'
  ) as comparison
from reporting.latest_league_dashboard_v6 previous
cross join reporting.latest_league_dashboard_v6 current
where previous.season = '2024-25'
  and current.season = '2025-26';

create view reporting.approved_dashboard_reader_target_v3
with (security_invoker = false, security_barrier = true) as
select target_attested
  and to_regclass('reporting.latest_team_season_comparison_v1') is not null
  and to_regclass('reporting.latest_league_season_comparison_v1') is not null
  as target_attested
from reporting.approved_dashboard_reader_target_v2;

revoke all on reporting.latest_team_season_comparison_v1,
  reporting.latest_league_season_comparison_v1,
  reporting.approved_dashboard_reader_target_v3
from public, anon, authenticated, web_reader;

revoke all on function reporting.season_comparison_exposure_qualification_v1(
  jsonb
) from public, anon, authenticated, web_reader;
revoke all on function reporting.season_comparison_severe_value_v1(
  jsonb
) from public, anon, authenticated, web_reader;
revoke all on function reporting.build_season_comparison_v1(
  jsonb, jsonb, text
) from public, anon, authenticated, web_reader;

grant select on reporting.latest_team_season_comparison_v1,
  reporting.latest_league_season_comparison_v1,
  reporting.approved_dashboard_reader_target_v3
to web_reader;

-- The views call this pure JSON transformer at query time. Grant only the
-- top-level security-definer builder; its trusted search path and lack of data
-- access keep the two subordinate helpers private from web_reader.
grant execute on function reporting.build_season_comparison_v1(
  jsonb, jsonb, text
) to web_reader;

commit;
