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
        and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
    ) <> 1
    or (select count(*) from analysis.league_dashboard_release_candidates_analysis_window_v6
        where season = '2025-26') <> 1
  then
    raise exception 'Year 2 exposure-successor league snapshot is incomplete';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830160000',
  'urc_2025_26_v6_exposure_successor_league_snapshot',
  array['migration_sha256=41dbf5f4245e549cf7fbfeb67290d77cd3bd053e5038db042341ed94075d20ad']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260830160000'
      and name = 'urc_2025_26_v6_exposure_successor_league_snapshot'
      and statements = array[
        'migration_sha256=41dbf5f4245e549cf7fbfeb67290d77cd3bd053e5038db042341ed94075d20ad'
      ]
  ) then
    raise exception 'Year 2 exposure-successor league snapshot registration is invalid';
  end if;
end;
$$;
