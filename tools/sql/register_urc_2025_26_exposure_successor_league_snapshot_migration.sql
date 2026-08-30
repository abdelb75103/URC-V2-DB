-- Register only the sealed Year 2 exposure-successor league snapshot.

do $$
begin
  if to_regclass(
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260830'
    ) is null
    or (
      select count(*)
      from analysis.league_dashboard_release_candidate_snapshot_v6_20260830
      where snapshot_version = '20260830160000'
        and member_count = 16
        and dashboard #>> '{coverage,hours}' = '87854.0133391047619046'
        and dashboard #>> '{coverage,included_exposure_status}' =
          'includes_temporary_league_mean_estimates_for_two_teams'
        and dashboard #> '{coverage,distance_km}' = 'null'::jsonb
        and dashboard #>> '{coverage,exposure_rows}' = '62481'
        and dashboard #>> '{coverage,exposed_players}' = '490'
        and dashboard #>> '{coverage,weeks}' = '44'
        and jsonb_array_length(dashboard -> 'limitations') = 3
        and not exists (
          select 1
          from jsonb_array_elements(dashboard -> 'monthly') month
          where month -> 'exposure_hours' is distinct from 'null'::jsonb
            or month -> 'distance_km' is distinct from 'null'::jsonb
            or month -> 'incidence_per_1000h' is distinct from 'null'::jsonb
            or month -> 'burden_per_1000h' is distinct from 'null'::jsonb
        )
        and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
    ) <> 1
    or (select count(*) from analysis.league_dashboard_release_candidates_analysis_window_v6
        where season = '2025-26') <> 1
    or not (
      select relrowsecurity
      from pg_class
      where oid =
        'analysis.league_dashboard_release_candidate_snapshot_v6_20260830'::regclass
    )
    or exists (
      select 1
      from information_schema.role_table_grants
      where table_schema = 'analysis'
        and table_name =
          'league_dashboard_release_candidate_snapshot_v6_20260830'
        and grantee in ('PUBLIC', 'anon', 'authenticated', 'web_reader')
    )
    or not exists (
      select 1
      from pg_trigger
      where tgrelid =
        'analysis.league_dashboard_release_candidate_snapshot_v6_20260830'::regclass
        and tgname =
          'league_dashboard_release_candidate_snapshot_v6_20260830_immutable'
        and tgenabled <> 'D'
        and not tgisinternal
    )
    or (
      select array_agg(column_name::text order by ordinal_position)
      from information_schema.columns
      where table_schema = 'analysis'
        and table_name =
          'league_dashboard_release_candidates_analysis_window_v6'
    ) is distinct from array[
      'season', 'analysis_version', 'classification_view_version',
      'classification_evidence_sha256', 'cohort_view_version',
      'cohort_evidence_sha256', 'dashboard'
    ]::text[]
    or not (
      select coalesce(reloptions, '{}'::text[]) @> array['security_invoker=true']
      from pg_class
      where oid =
        'analysis.league_dashboard_release_candidates_analysis_window_v6'::regclass
    )
  then
    raise exception 'Year 2 exposure-successor league snapshot is incomplete';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830160000',
  'urc_2025_26_v6_exposure_successor_league_snapshot',
  array['migration_sha256=d3fd1527679807156c7676500b283534fe0fab5a30b4f678a40fa2b9283e8415']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260830160000'
      and name = 'urc_2025_26_v6_exposure_successor_league_snapshot'
      and statements = array[
        'migration_sha256=d3fd1527679807156c7676500b283534fe0fab5a30b4f678a40fa2b9283e8415'
      ]
  ) then
    raise exception 'Year 2 exposure-successor league snapshot registration is invalid';
  end if;
end;
$$;
