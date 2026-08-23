-- Register the eight reviewed Year 2 migrations only after their additive
-- objects and least-privilege boundary exist. A conflicting historical row is
-- never overwritten: the final verification fails closed instead.

do $$
begin
  if to_regclass('analysis.accepted_release_contracts_v1') is null
    or to_regclass('curated.fixture_provenance_v1') is null
    or to_regclass('analysis.analysis_window_injury_cohort_v6') is null
    or to_regclass('analysis.analysis_window_team_exposure_v6') is null
    or to_regclass('analysis.analysis_window_team_exposure_completeness_v6') is null
    or to_regclass('analysis.accepted_urc_2025_26_incomplete_exposure_reporting_evidence_v6') is null
    or to_regclass('analysis.accepted_urc_2025_26_injury_eligibility_bridge_evidence_v6') is null
    or to_regclass('analysis.league_team_dashboard_release_candidates_analysis_window_v6') is null
    or to_regclass('analysis.league_dashboard_release_candidate_snapshot_v6_20260823') is null
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
    or not (select relrowsecurity from pg_class
            where oid = 'analysis.league_dashboard_release_candidate_snapshot_v6_20260823'::regclass)
    or has_table_privilege('web_reader', 'reporting.team_release_payloads_v6', 'select')
    or has_table_privilege('web_reader', 'reporting.league_release_payloads_v6', 'select')
    or has_table_privilege('web_reader',
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260823', 'select')
  then
    raise exception 'URC 2025-26 V6 private release storage is not least-privilege';
  end if;

  if (
    select count(*)
    from reporting.team_key_aliases alias
    join reporting.teams team on team.team_key = alias.team_key and team.active
    where (alias.alias, alias.team_key, alias.excluded) in (
      ('Benetton Rugby', 'benetton', false),
      ('Connacht Rugby', 'connacht', false),
      ('Leinster Rugby', 'leinster', false),
      ('Munster Rugby', 'munster', false),
      ('Ulster Rugby', 'ulster', false)
    )
  ) <> 5 then
    raise exception 'URC 2025-26 official fixture aliases are absent, inactive, or conflict with canonical team keys';
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
    array['migration_sha256=013973d8abefc004d80ae11aafa5028da47f563c99d55248fb87b9edd0ef41b7']
  ),
  (
    '20260822010000',
    'urc_2025_26_fixture_team_aliases',
    array['migration_sha256=d3409ef9ab0546c46690deb21173eddfb1e3d2fde357a3df16f949029c61865f']
  ),
  (
    '20260822020000',
    'urc_2025_26_incomplete_exposure_reporting_v6',
    array['migration_sha256=2e7d81e2a543e754bbb1f3eb63f750f0a177591a5ec742e7560effa58159c0b8']
  ),
  (
    '20260822030000',
    'urc_2025_26_injury_eligibility_bridge',
    array['migration_sha256=4960c284ab6a5257a7f8c64ef83a45c4aaed7c906b6b1843e8536516dbc95e03']
  ),
  (
    '20260822220611',
    'urc_2025_26_v6_candidate_view_optimisation',
    array['migration_sha256=5e5c734a0d4b14337a6cf0a12f5891fbdd9b4ef7ea71fadc97c1a1d85a4cd8d6']
  ),
  (
    '20260823120000',
    'urc_2025_26_v6_league_candidate_fast_path',
    array['migration_sha256=b7414b9ade8dd6eb5bc225e3fd25aab6bf6711147afdbe7511a451e6b7555dfc']
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
        array['migration_sha256=013973d8abefc004d80ae11aafa5028da47f563c99d55248fb87b9edd0ef41b7']),
      ('20260822010000', 'urc_2025_26_fixture_team_aliases',
        array['migration_sha256=d3409ef9ab0546c46690deb21173eddfb1e3d2fde357a3df16f949029c61865f']),
      ('20260822020000', 'urc_2025_26_incomplete_exposure_reporting_v6',
        array['migration_sha256=2e7d81e2a543e754bbb1f3eb63f750f0a177591a5ec742e7560effa58159c0b8']),
      ('20260822030000', 'urc_2025_26_injury_eligibility_bridge',
        array['migration_sha256=4960c284ab6a5257a7f8c64ef83a45c4aaed7c906b6b1843e8536516dbc95e03']),
      ('20260822220611', 'urc_2025_26_v6_candidate_view_optimisation',
        array['migration_sha256=5e5c734a0d4b14337a6cf0a12f5891fbdd9b4ef7ea71fadc97c1a1d85a4cd8d6']),
      ('20260823120000', 'urc_2025_26_v6_league_candidate_fast_path',
        array['migration_sha256=b7414b9ade8dd6eb5bc225e3fd25aab6bf6711147afdbe7511a451e6b7555dfc'])
    )
  ) <> 8 then
    raise exception 'URC 2025-26 V6 migration registration is absent or checksum-mismatched';
  end if;
end;
$$;
