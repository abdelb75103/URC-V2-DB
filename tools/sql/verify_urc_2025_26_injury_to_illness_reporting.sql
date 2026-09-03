-- Read-only. Prove the approved live target immediately before running.
with dashboards as materialized (
  select team_key, season, to_jsonb(reader) as dashboard
  from reporting.latest_team_dashboard_v8 reader
  union all
  select null::text, season, to_jsonb(reader)
  from reporting.latest_league_dashboard_v8 reader
), expected as materialized (
  select dashboard.*, totals.*,
    (select jsonb_object_agg(item ->> 'key', item)
      from jsonb_array_elements(dashboard.dashboard -> 'headline') item) as headline
  from dashboards dashboard
  cross join lateral (
    select count(*) as recorded, count(*) filter (where is_time_loss) as time_loss,
      count(*) filter (where is_time_loss and days_lost is not null) as known_duration,
      coalesce(sum(days_lost) filter (where is_time_loss), 0) as days
    from analysis.urc_canonical_injury_rows_v1 injury
    where injury.season = dashboard.season
      and (dashboard.team_key is null or injury.team_key = dashboard.team_key)
  ) totals
  where dashboard.season = '2025-26'
), checks as (
  select 'exact_source_decisions_and_null_duration' as contract,
    (select count(*) = 24 and count(*) filter (where decision.time_loss_days is null) = 1
      and sum(decision.time_loss_days) = 92
      and bool_and(decision.final_master_row_sha256 = master.final_master_row_sha256
        and decision.final_classification = master.final_classification
        and decision.time_loss_days is not distinct from master.time_loss_days
        and master.row_values ->> 'Problem type' = 'Injury')
      from audit.urc_2025_26_injury_to_illness_decisions_v1 decision
      join lineage.injury_master_rows_v3 master using (version_id, source_row)) as passed
  union all
  select 'injury_cohort_and_every_v8_headline',
    (select count(*) = 17 and bool_and(
      (headline #>> '{recorded_injuries,value}')::numeric = recorded
      and (headline #>> '{time_loss_injuries,value}')::numeric = time_loss
      and (headline #>> '{burden_per_1000h,numerator}')::numeric = days
      and (headline #>> '{severity_mean_days,denominator}')::numeric = known_duration
      and abs((headline #>> '{incidence_per_1000h,value}')::numeric
        - time_loss * 1000 / nullif((dashboard #>> '{coverage,hours}')::numeric, 0)) < 0.000000001
    ) from expected)
    and (select recorded = 1521 and time_loss = 915 and days = 20573
      from expected where team_key is null)
  union all
  select 'injury_profile_dimensions_and_severity', not exists (
    select 1 from expected
    cross join (values ('body_location'), ('injury_type'), ('diagnosis')) kind(dimension)
    where (select sum((item ->> 'recorded_injuries')::numeric)
      from jsonb_array_elements(dashboard -> 'injury_profiles') item
      where item ->> 'dimension' = kind.dimension and item ->> 'setting' = 'all') <> recorded
      or (select sum((item ->> 'time_loss_injuries')::numeric)
        from jsonb_array_elements(dashboard -> 'injury_profiles') item
        where item ->> 'dimension' = kind.dimension and item ->> 'setting' = 'all') <> time_loss
      or (select sum((item ->> 'days_lost')::numeric)
        from jsonb_array_elements(dashboard -> 'injury_profiles') item
        where item ->> 'dimension' = kind.dimension and item ->> 'setting' = 'all') <> days
      or (select sum((item ->> 'recorded_injuries')::numeric)
        from jsonb_array_elements(dashboard -> 'severity_distribution') item
        where item ->> 'setting' = 'all') <> recorded
  )
  union all
  select 'monthly_and_setting_rows', not exists (
    select 1 from expected
    cross join lateral jsonb_array_elements(dashboard -> 'monthly') month
    cross join lateral (
      select count(*) as recorded, count(*) filter (where is_time_loss) as time_loss,
        coalesce(sum(days_lost) filter (where is_time_loss), 0) as days
      from analysis.urc_2025_26_canonical_injury_rows_v1 injury
      where (expected.team_key is null or injury.team_key = expected.team_key)
        and date_trunc('month', injury.injury_date)::date = case
          when month ->> 'month' ~ '^[0-9]{4}-[0-9]{2}$' then to_date(month ->> 'month', 'YYYY-MM')
          else to_date(month ->> 'month', 'Mon YYYY') end
    ) totals
    where (month ->> 'recorded_injuries')::numeric <> totals.recorded
      or (month ->> 'time_loss_injuries')::numeric <> totals.time_loss
      or (month ->> 'days_lost')::numeric <> totals.days
  ) and not exists (
    select 1 from expected
    cross join lateral jsonb_array_elements(dashboard -> 'setting_metrics') setting
    cross join lateral (
      select count(*) as recorded, count(*) filter (where is_time_loss) as time_loss,
        coalesce(sum(days_lost) filter (where is_time_loss), 0) as days
      from analysis.urc_2025_26_canonical_injury_rows_v1 injury
      where (expected.team_key is null or injury.team_key = expected.team_key)
        and (setting ->> 'setting' = 'all' or injury.setting_code = setting ->> 'setting')
    ) totals
    where (setting ->> 'recorded_injuries')::numeric <> totals.recorded
      or (setting ->> 'time_loss_injuries')::numeric <> totals.time_loss
      or (setting ->> 'days_lost')::numeric <> totals.days
  )
  union all
  select 'illness_profiles_and_disjoint_cohorts',
    (select count(*) = 463 and count(*) filter (where duration_known) = 225 and sum(days_lost) = 1019
      from analysis.urc_illness_profile_rows_v2 where season = '2025-26')
    and not exists (
      select 1 from analysis.urc_illness_profile_rows_v2 illness
      join analysis.urc_canonical_injury_rows_v1 injury using (season, team_key, source_row)
      where illness.season = '2025-26'
    ) and not exists (
      select 1 from expected
      cross join lateral (
        select count(*) as recorded, count(*) filter (where duration_known) as known,
          coalesce(sum(days_lost), 0) as days
        from analysis.urc_illness_profile_rows_v2 illness
        where illness.season = expected.season
          and (expected.team_key is null or illness.team_key = expected.team_key)
      ) totals
      where (dashboard #>> '{illness_summary,recorded_illnesses}')::numeric <> totals.recorded
        or (dashboard #>> '{illness_summary,known_duration_illnesses}')::numeric <> totals.known
        or (dashboard #>> '{illness_summary,days_lost}')::numeric <> totals.days
    )
  union all
  select 'v5_comparisons_use_current_v7_payloads',
    (select count(*) = 16 and bool_and(comparison.comparison = reporting.build_season_comparison_v5(
      to_jsonb(previous) - 'team_key', to_jsonb(current) - 'team_key', 'team'))
      from reporting.latest_team_season_comparison_v5 comparison
      join reporting.latest_team_dashboard_v7 previous using (team_key)
      join reporting.latest_team_dashboard_v7 current using (team_key)
      where previous.season = '2024-25' and current.season = '2025-26')
    and (select comparison.comparison = reporting.build_season_comparison_v5(
      to_jsonb(previous), to_jsonb(current), 'league')
      from reporting.latest_league_season_comparison_v5 comparison
      cross join reporting.latest_league_dashboard_v7 previous
      cross join reporting.latest_league_dashboard_v7 current
      where previous.season = '2024-25' and current.season = '2025-26')
  union all
  select 'restricted_reader_contract',
    (select target_attested from reporting.approved_dashboard_reader_target_v8)
    and not has_table_privilege('web_reader', 'audit.urc_2025_26_injury_to_illness_decisions_v1', 'select')
    and not has_table_privilege('web_reader', 'reporting.diagnosis_family_team_dashboard_payloads_v3', 'select')
    and not has_table_privilege('web_reader', 'reporting.diagnosis_family_league_dashboard_payloads_v3', 'select')
    and not has_function_privilege('web_reader', 'reporting.urc_2025_26_injury_to_illness_dashboard_v1(jsonb,text)', 'execute')
)
select contract, passed from checks order by contract;
