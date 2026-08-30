-- Register only the sealed Year 2 exposure-successor team snapshot.

do $$
begin
  if to_regclass(
      'analysis.team_dashboard_release_candidate_snapshot_v6_20260830'
    ) is null
    or (
      select count(*)
      from analysis.team_dashboard_release_candidate_snapshot_v6_20260830
      where snapshot_version = '20260830155000'
        and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
    ) <> 16
    or (
      select count(*)
      from analysis.team_dashboard_release_candidates_analysis_window_v6
      where season = '2025-26'
    ) <> 16
  then
    raise exception 'Year 2 exposure-successor team snapshot is incomplete';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830155000',
  'urc_2025_26_v6_exposure_successor_team_snapshot',
  array['migration_sha256=9a5168da5d23bcb775c4e9c71fd03516e5cbc8fd55ad7c4376977d5cdbef326d']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260830155000'
      and name = 'urc_2025_26_v6_exposure_successor_team_snapshot'
      and statements = array[
        'migration_sha256=9a5168da5d23bcb775c4e9c71fd03516e5cbc8fd55ad7c4376977d5cdbef326d'
      ]
  ) then
    raise exception 'Year 2 exposure-successor team snapshot registration is invalid';
  end if;
end;
$$;
