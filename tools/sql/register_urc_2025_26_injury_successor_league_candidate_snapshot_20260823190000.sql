-- Register only the sealed injury-semantics successor league candidate after
-- proving its exact current member binding, payload hash and private posture.

do $$
begin
  if exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260823170000'
  ) or to_regclass(
    'analysis.league_dashboard_release_candidate_snapshot_v6_20260823_injury_successor'
  ) is not null then
    raise exception 'Obsolete migration 20260823170000 or its snapshot is present';
  end if;

  if to_regclass(
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260823190000'
    ) is null
    or to_regclass(
      'analysis.league_dashboard_release_candidates_analysis_window_v6'
    ) is null
  then
    raise exception 'URC 2025-26 injury successor league snapshot objects are incomplete';
  end if;

  if (
    select count(*)
    from analysis.league_dashboard_release_candidate_snapshot_v6_20260823190000 snapshot
    join analysis.league_dashboard_release_candidates_analysis_window_v6 candidate
      on candidate.season = snapshot.season
     and candidate.analysis_version = snapshot.analysis_version
     and candidate.classification_view_version = snapshot.classification_view_version
     and candidate.cohort_view_version = snapshot.cohort_view_version
     and candidate.dashboard = snapshot.dashboard
    cross join analysis.accepted_urc_2025_26_injury_problem_type_successor_v1 evidence
    where snapshot.snapshot_version = '20260823190000'
      and snapshot.season = '2025-26'
      and snapshot.member_count = 16
      and (
        select (item ->> 'value')::bigint
        from jsonb_array_elements(snapshot.dashboard -> 'headline') item
        where item ->> 'key' = 'recorded_injuries'
      ) = 7514
      and snapshot.payload_sha256 =
        reporting.canonical_jsonb_sha256_v1(snapshot.dashboard)
      and snapshot.dashboard -> 'limitations' @>
        jsonb_build_array(evidence.release_limitation)
  ) <> 1 then
    raise exception 'URC 2025-26 injury successor league snapshot is absent or mismatched';
  end if;

  if not (
      select relrowsecurity
      from pg_catalog.pg_class
      where oid =
        'analysis.league_dashboard_release_candidate_snapshot_v6_20260823190000'::regclass
    )
    or has_table_privilege(
      'web_reader',
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260823190000',
      'select'
    )
  then
    raise exception 'URC 2025-26 injury successor league snapshot is not least-privilege';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260823190000',
  'urc_2025_26_injury_successor_league_candidate_snapshot',
  array['migration_sha256=5937b563c37914e3fe5e138308cb76c07c85cdc67cb6bfe58b00976100c5a60c']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260823190000'
      and migration.name =
        'urc_2025_26_injury_successor_league_candidate_snapshot'
      and migration.statements = array[
        'migration_sha256=5937b563c37914e3fe5e138308cb76c07c85cdc67cb6bfe58b00976100c5a60c'
      ]
  ) then
    raise exception 'URC 2025-26 injury successor league snapshot registration is absent or checksum-mismatched';
  end if;
end;
$$;
