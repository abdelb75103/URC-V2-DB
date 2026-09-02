do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260901021000'
      and name = 'urc_diagnosis_family_materialized_reader_boundary'
      and statements[1] =
        'migration_sha256=eb015ecaa8ca3db1d4992f4c4d3498ff5f5aa65aac60f16693b780104443e5d0'
  )
    or (select count(*) from analysis.hsr_ingestion_batches_v1
      where parameter_payload_sha256 =
        '821a3b15eddfdb444a564ffa709410fdc3062b6f3cb49bf4740dabd625735149') <> 1
    or (select count(*) from analysis.hsr_team_season_metadata_v1) <> 32
    or (select count(*) from analysis.hsr_source_observation_events_v1) <> 166207
    or (select count(*) from reporting.latest_team_dashboard_v8) <> 32
    or (select count(*) from reporting.latest_league_dashboard_v8) <> 2
    or not (select target_attested from reporting.approved_dashboard_reader_target_v8)
  then
    raise exception 'HSR V8 migration is not ready for checksum registration';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260902010000',
  'urc_hsr_reporting_v8',
  array[
    'migration_sha256=fae659ee69b5e455bc824793eeab6695184232c3c6cd828223a653b490c4a53b',
    'parameter_payload_sha256=821a3b15eddfdb444a564ffa709410fdc3062b6f3cb49bf4740dabd625735149',
    'rule_version=hsr_source_to_display_reporting_2026_09_02_v1',
    'predecessor=20260901021000_urc_diagnosis_family_materialized_reader_boundary',
    'zebre_2025_26_accepted_distance_mismatch_rows=976',
    'zebre_2025_26_accepted_distance_mismatch_sha256=8f056d74844db183ccfda9692cbdad4682e3592c6c8e76fb2c7e7c9021952746',
    'scope=private_row_lineage_and_reporting_v8_no_source_curated_or_release_mutation'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260902010000'
      and name = 'urc_hsr_reporting_v8'
      and statements = array[
        'migration_sha256=fae659ee69b5e455bc824793eeab6695184232c3c6cd828223a653b490c4a53b',
        'parameter_payload_sha256=821a3b15eddfdb444a564ffa709410fdc3062b6f3cb49bf4740dabd625735149',
        'rule_version=hsr_source_to_display_reporting_2026_09_02_v1',
        'predecessor=20260901021000_urc_diagnosis_family_materialized_reader_boundary',
        'zebre_2025_26_accepted_distance_mismatch_rows=976',
        'zebre_2025_26_accepted_distance_mismatch_sha256=8f056d74844db183ccfda9692cbdad4682e3592c6c8e76fb2c7e7c9021952746',
        'scope=private_row_lineage_and_reporting_v8_no_source_curated_or_release_mutation'
      ]
  )
  then
    raise exception 'HSR V8 migration checksum registration is invalid';
  end if;
end;
$$;
