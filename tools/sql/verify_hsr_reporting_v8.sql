-- Read-only post-migration proof for the checksum-bound HSR V8 successor.
do $$
begin
  if (select count(*) from analysis.hsr_team_season_metadata_v1) <> 32
    or (select count(*) from analysis.hsr_team_season_metadata_v1
      where season = '2024-25' and source_available) <> 16
    or (select count(*) from analysis.hsr_team_season_metadata_v1
      where season = '2025-26' and source_available) <> 14
    or (select count(*) from analysis.hsr_ingestion_batches_v1
      where parameter_payload_sha256 =
        '821a3b15eddfdb444a564ffa709410fdc3062b6f3cb49bf4740dabd625735149') <> 1
    or (select count(*) from analysis.hsr_source_observation_events_v1) <> 166207
    or exists (
      select 1
      from analysis.hsr_source_observation_events_v1 event
      left join ingestion.source_rows source on source.id = event.source_row_id
      left join analysis.hsr_active_curated_exposure_rows_v1 active
        on active.curated_exposure_id = event.curated_exposure_id
       and active.source_row_id = event.source_row_id
      where source.id is null or active.curated_exposure_id is null
        or (event.source_status = 'actual' and event.hsr_distance_m is null)
        or (event.source_status = 'unknown' and event.hsr_distance_m is not null)
    )
    or exists (
      select 1
      from reporting.latest_team_dashboard_v8 dashboard
      cross join lateral jsonb_array_elements(dashboard.monthly) month
      where coalesce(month ->> 'hsr_source_status', '') like '%unknown%'
        and coalesce((month ->> 'is_imputed')::boolean, false) = false
        and month -> 'hsr_distance_km' is distinct from 'null'::jsonb
    )
    or exists (
      select 1
      from reporting.latest_team_dashboard_v8 dashboard
      cross join lateral jsonb_array_elements(dashboard.monthly) month
      where coalesce((month ->> 'is_imputed')::boolean, false)
        and (
          month -> 'actual_hsr_distance_km' is distinct from 'null'::jsonb
          or month -> 'hsr_distance_km' = 'null'::jsonb
          or month -> 'hsr_percentage' = 'null'::jsonb
          or month ->> 'imputation_method'
            <> 'season_month_pooled_valid_hsr_percentage_v1'
        )
    )
    or exists (
      select 1
      from reporting.latest_team_dashboard_v8 dashboard
      cross join lateral jsonb_array_elements(dashboard.monthly) month
      where (month ->> 'hsr_percentage')::numeric < 0
        or (month ->> 'hsr_percentage')::numeric > 100
    )
    or not exists (
      select 1
      from reporting.latest_team_dashboard_v8 dashboard
      where dashboard.season = '2025-26' and dashboard.team_key = 'zebre'
        and dashboard.coverage -> 'data_quality_warnings'
          @> jsonb_build_array(
            'The Zebre source total-distance anomaly was corrected in the accepted exposure release. HSR uses those corrected distances.'
          )
    )
    or exists (
      select 1
      from reporting.latest_team_dashboard_v8 dashboard
      where dashboard.season = '2025-26'
        and (dashboard.coverage ->> 'is_imputed')::boolean
        and not (
          dashboard.coverage -> 'data_quality_warnings'
            @> jsonb_build_array(
              'The Zebre source total-distance anomaly was corrected in the accepted exposure release. HSR uses those corrected distances.'
            )
        )
    )
    or (
      select count(*)
      from reporting.latest_team_dashboard_v8 dashboard
      where dashboard.season = '2025-26'
        and dashboard.team_key in ('benetton', 'edinburgh')
        and dashboard.coverage -> 'hsr_distance_km' = 'null'::jsonb
        and dashboard.coverage -> 'hsr_percentage' = 'null'::jsonb
        and not (dashboard.coverage ->> 'is_imputed')::boolean
        and (dashboard.coverage ->> 'valid_paired_row_count')::bigint = 0
    ) <> 2
    or exists (
      select 1
      from reporting.latest_team_dashboard_v8 dashboard
      where jsonb_array_length(dashboard.hsr_team_comparison) <> 16
    )
    or exists (
      select 1
      from reporting.latest_league_dashboard_v8 dashboard
      where jsonb_array_length(dashboard.hsr_team_comparison) <> 16
    )
    or not (select target_attested from reporting.approved_dashboard_reader_target_v8)
  then
    raise exception 'HSR V8 reporting contract failed';
  end if;
end;
$$;

do $$
declare hsr_month_keys text[] := array[
  'actual_hsr_distance_km', 'hsr_distance_km', 'hsr_percentage', 'is_imputed',
  'imputation_method', 'display_note', 'hsr_contributor_count', 'hsr_source_status'
];
declare hsr_coverage_keys text[] := hsr_month_keys || array[
  'source_row_count', 'valid_paired_row_count', 'actual_month_count',
  'placeholder_month_count', 'comparability_status', 'units', 'threshold_or_zone',
  'data_quality_warnings'
];
begin
  if exists (
    select 1
    from reporting.latest_team_dashboard_v8 current
    join reporting.latest_team_dashboard_v7 previous using (season, team_key)
    where to_jsonb(current) - array['coverage', 'monthly', 'limitations', 'hsr_team_comparison']
        is distinct from to_jsonb(previous) - array['coverage', 'monthly', 'limitations']
      or current.coverage - hsr_coverage_keys is distinct from previous.coverage
      or current.limitations is distinct from previous.limitations || jsonb_build_array(
        'High-speed running definitions, thresholds, units and vendor calibration differ or are unknown. Do not compare teams directly.'
      )
      or exists (
        select 1
        from jsonb_array_elements(current.monthly) with ordinality a(value, position)
        full join jsonb_array_elements(previous.monthly) with ordinality b(value, position)
          using (position)
        where a.value - hsr_month_keys is distinct from b.value
      )
  ) or exists (
    select 1
    from reporting.latest_league_dashboard_v8 current
    join reporting.latest_league_dashboard_v7 previous using (season)
    where to_jsonb(current) - array['coverage', 'monthly', 'limitations', 'hsr_team_comparison']
        is distinct from to_jsonb(previous) - array['coverage', 'monthly', 'limitations']
      or current.coverage - hsr_coverage_keys is distinct from previous.coverage
      or current.limitations is distinct from previous.limitations || jsonb_build_array(
        'High-speed running definitions, thresholds, units and vendor calibration differ or are unknown. Do not compare teams directly.'
      )
      or exists (
        select 1
        from jsonb_array_elements(current.monthly) with ordinality a(value, position)
        full join jsonb_array_elements(previous.monthly) with ordinality b(value, position)
          using (position)
        where a.value - hsr_month_keys is distinct from b.value
      )
  ) then
    raise exception 'HSR V8 changed a preserved V7 field';
  end if;

  if exists (
    with pooled as (
      select season, date_trunc('month', period_start)::date as month_start,
        100 * sum(hsr_distance_m) / nullif(sum(distance_m_clean), 0) as hsr_percentage
      from analysis.hsr_dashboard_exposure_rows_v1
      where source_status = 'actual' and distance_m_clean is not null
      group by season, date_trunc('month', period_start)::date
    )
    select 1
    from analysis.hsr_dashboard_monthly_display_v1 display
    left join pooled using (season, month_start)
    where display.is_imputed and (
      display.total_distance_m is null
      or display.actual_hsr_distance_km is not null
      or display.hsr_percentage is distinct from pooled.hsr_percentage
      or display.hsr_distance_km is distinct from
        display.total_distance_m * pooled.hsr_percentage / 100000
    )
  ) then
    raise exception 'HSR placeholder values differ from the independently pooled actual rows';
  end if;

  if exists (
    select 1 from pg_class
    where oid in (
      'analysis.hsr_team_season_metadata_v1'::regclass,
      'analysis.hsr_ingestion_batches_v1'::regclass,
      'analysis.hsr_source_observation_events_v1'::regclass
    ) and not relrowsecurity
  ) or (
    select count(*) from pg_trigger
    where tgname in (
      'hsr_team_season_metadata_v1_immutable',
      'hsr_ingestion_batches_v1_immutable',
      'hsr_source_observation_events_v1_immutable'
    ) and tgenabled in ('O', 'A')
  ) <> 3 then
    raise exception 'HSR row security or append-only triggers are not enabled';
  end if;
end;
$$;

select jsonb_build_object('hsr_reporting_v8', true) as verification;
