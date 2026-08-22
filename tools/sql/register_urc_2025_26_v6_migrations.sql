-- Register the three reviewed Year 2 migrations only after their additive
-- objects and least-privilege boundary exist. A conflicting historical row is
-- never overwritten: the final verification fails closed instead.

do $$
begin
  if to_regclass('analysis.accepted_release_contracts_v1') is null
    or to_regclass('curated.fixture_provenance_v1') is null
    or to_regclass('analysis.analysis_window_injury_cohort_v6') is null
    or to_regclass('analysis.analysis_window_team_exposure_v6') is null
    or to_regclass('analysis.league_team_dashboard_release_candidates_analysis_window_v6') is null
    or to_regclass('reporting.team_release_payloads_v6') is null
    or to_regclass('reporting.league_release_payloads_v6') is null
    or to_regclass('reporting.latest_approved_league_bundle_v6') is null
    or to_regprocedure('reporting.canonical_jsonb_sha256_v1(jsonb)') is null
  then
    raise exception 'URC 2025-26 V6 migration objects are incomplete';
  end if;

  if not (select relrowsecurity from pg_class
          where oid = 'reporting.team_release_payloads_v6'::regclass)
    or not (select relrowsecurity from pg_class
            where oid = 'reporting.league_release_payloads_v6'::regclass)
    or has_table_privilege('web_reader', 'reporting.team_release_payloads_v6', 'select')
    or has_table_privilege('web_reader', 'reporting.league_release_payloads_v6', 'select')
  then
    raise exception 'URC 2025-26 V6 private release storage is not least-privilege';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values
  (
    '20260815010000',
    'urc_2025_26_reporting_contract',
    array['migration_sha256=d150177f144d08346a0ffc5b63821a840a411be5ded07d21a9d4b3f954165cac']
  ),
  (
    '20260815020000',
    'urc_2025_26_reporting_v6',
    array['migration_sha256=48380753d7ece51221fe64f0345366e72232401247ef0397ca1f33354f710dd2']
  ),
  (
    '20260815030000',
    'urc_2025_26_team_release_v6',
    array['migration_sha256=fb2bd41bdcc519570bc9cf0b532e80c5e5ec261e923eee713a79f89f8cee0fd1']
  )
on conflict (version) do nothing;

do $$
begin
  if (
    select count(*)
    from supabase_migrations.schema_migrations migration
    where (migration.version, migration.name, migration.statements) in (
      ('20260815010000', 'urc_2025_26_reporting_contract',
        array['migration_sha256=d150177f144d08346a0ffc5b63821a840a411be5ded07d21a9d4b3f954165cac']),
      ('20260815020000', 'urc_2025_26_reporting_v6',
        array['migration_sha256=48380753d7ece51221fe64f0345366e72232401247ef0397ca1f33354f710dd2']),
      ('20260815030000', 'urc_2025_26_team_release_v6',
        array['migration_sha256=fb2bd41bdcc519570bc9cf0b532e80c5e5ec261e923eee713a79f89f8cee0fd1'])
    )
  ) <> 3 then
    raise exception 'URC 2025-26 V6 migration registration is absent or checksum-mismatched';
  end if;
end;
$$;
