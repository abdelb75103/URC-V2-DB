do $$
begin
  if to_regclass('lineage.injury_classification_rules_v3') is not null
     or to_regclass('lineage.injury_master_versions_v3') is not null
     or to_regclass('lineage.injury_master_rows_v3') is not null
     or to_regclass('lineage.injury_inclusion_rows_v3') is not null
     or exists (
       select 1 from supabase_migrations.schema_migrations
       where version = '20260830140000'
     ) then
    raise exception '2025-26 injury review-triage successor is not absent';
  end if;

  if not exists (
    select 1
    from lineage.injury_master_versions_v2
    where id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
      and season = '2025-26'
      and version_label = 'urc-injury-2025-26-valid-20260830-a2'
      and migration_version = '20260829230000'
      and migration_sha256 = 'f4c5e3986e13a0b3b1a2e4dda6759f1cf476095ecb77e38554d1226936eba62b'
      and manifest_sha256 = '9fc869cff5732becb20db3b7ec2bbd71a619096aaa32895ff0ac726fbf9395c7'
      and load_payload_sha256 = '7a11596713ce730a4404039a958d8a8c10cca2092115a8fa40d951e22940e8c2'
      and master_row_count = 2993
      and included_row_count = 1923
      and excluded_row_count = 1070
  ) then
    raise exception 'installed 2025-26 injury predecessor changed';
  end if;

  if (select count(*) from lineage.injury_master_rows_v2
      where version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94') <> 2993
     or (select count(*) from lineage.injury_inclusion_rows_v2
         where version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94') <> 1923
     or (select count(*) from lineage.master_rows where season = '2024-25') <> 3060
     or (select count(*) from lineage.master_rows
         where season = '2024-25' and excluded) <> 755 then
    raise exception 'protected lineage counts changed';
  end if;
end;
$$;

select jsonb_build_object(
  'captured_at', now(),
  'predecessor', (
    select jsonb_build_object(
      'version_id', version.id,
      'version_label', version.version_label,
      'migration_version', version.migration_version,
      'migration_sha256', version.migration_sha256,
      'manifest_sha256', version.manifest_sha256,
      'load_payload_sha256', version.load_payload_sha256,
      'master_rows', version.master_row_count,
      'included_rows', version.included_row_count,
      'excluded_rows', version.excluded_row_count,
      'master_rows_aggregate_sha256', (
        select encode(digest(string_agg(
          source_row::text || ':' || (to_jsonb(row_state) - 'version_id')::text,
          E'\n' order by source_row
        ), 'sha256'), 'hex')
        from lineage.injury_master_rows_v2 row_state
        where row_state.version_id = version.id
      ),
      'inclusion_rows_aggregate_sha256', (
        select encode(digest(string_agg(
          inclusion_row::text || ':' || (to_jsonb(row_state) - 'version_id')::text,
          E'\n' order by inclusion_row
        ), 'sha256'), 'hex')
        from lineage.injury_inclusion_rows_v2 row_state
        where row_state.version_id = version.id
      ),
      'immutability_triggers_enabled', (
        select count(*)
        from pg_trigger
        where tgrelid in (
          'lineage.injury_classification_rules_v2'::regclass,
          'lineage.injury_master_versions_v2'::regclass,
          'lineage.injury_master_rows_v2'::regclass,
          'lineage.injury_inclusion_rows_v2'::regclass
        ) and not tgisinternal and tgenabled <> 'D'
      )
    )
    from lineage.injury_master_versions_v2 version
    where version.id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
  ),
  'successor_absent', jsonb_build_object(
    'objects', to_regclass('lineage.injury_master_versions_v3') is null,
    'migration_registration', not exists (
      select 1 from supabase_migrations.schema_migrations
      where version = '20260830140000'
    )
  ),
  'protected_boundaries', jsonb_build_object(
    'source_files_2025_26', (
      select count(*) from ingestion.source_files where season = '2025-26'
    ),
    'source_rows_2025_26', (
      select count(*) from ingestion.source_rows row_state
      join ingestion.source_files source on source.id = row_state.source_file_id
      where source.season = '2025-26'
    ),
    'record_versions_2025_26', (
      select count(*) from processing.record_versions version
      join ingestion.source_rows row_state on row_state.id = version.source_row_id
      join ingestion.source_files source on source.id = row_state.source_file_id
      where source.season = '2025-26'
    ),
    'curated_injuries_2025_26', (
      select count(*) from curated.injuries where season = '2025-26'
    ),
    'curated_exposure_2025_26', (
      select count(*) from curated.exposure where season = '2025-26'
    ),
    'aggregate_releases_all', (select count(*) from reporting.aggregate_releases),
    'league_release_payloads_v6_all', (
      select count(*) from reporting.league_release_payloads_v6
    ),
    'team_release_payloads_v6_2025_26', (
      select count(*) from reporting.team_release_payloads_v6 where season = '2025-26'
    ),
    'team_exposure_denominators_2025_26', (
      select count(*) from curated.team_exposure_denominators where season = '2025-26'
    )
  ),
  'frozen_2024_25', jsonb_build_object(
    'master_rows', (select count(*) from lineage.master_rows where season = '2024-25'),
    'excluded_rows', (
      select count(*) from lineage.master_rows where season = '2024-25' and excluded
    ),
    'row_values_aggregate_sha256', (
      select encode(digest(string_agg(
        source_row::text || ':' || row_values::text || ':' || excluded::text || ':' || coalesce(exclusion_reason, ''),
        E'\n' order by source_row
      ), 'sha256'), 'hex')
      from lineage.master_rows where season = '2024-25'
    )
  )
) as evidence;
