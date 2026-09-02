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
            'The accepted Zebre total-distance anomaly remains uncorrected and affects league-mean placeholders.'
          )
    )
    or exists (
      select 1
      from reporting.latest_team_dashboard_v8 dashboard
      where dashboard.season = '2025-26'
        and dashboard.team_key in ('benetton', 'edinburgh')
        and not (
          dashboard.coverage -> 'data_quality_warnings'
            @> jsonb_build_array(
              'The accepted Zebre total-distance anomaly remains uncorrected and affects league-mean placeholders.'
            )
        )
    )
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

select jsonb_build_object('hsr_reporting_v8', true) as verification;
