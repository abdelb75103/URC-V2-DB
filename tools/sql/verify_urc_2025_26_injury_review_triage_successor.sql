do $$
declare
  successor_id constant uuid := '2f419706-8c36-58dd-b4cb-e92162e782b8';
  predecessor_id constant uuid := 'bab7731d-975b-5d49-a34c-6acc6b0c8c94';
begin
  if (select count(*) from _pipeline_params where value ->> 'kind' = 'version') <> 1
     or (select count(*) from _pipeline_params where value ->> 'kind' = 'row_delta') <> 1975
     or exists (
       select 1 from _pipeline_params
       where value ->> 'kind' not in ('version', 'row_delta')
     ) then
    raise exception 'successor verification payload shape changed';
  end if;

  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260830140000'
      and name = 'urc_2025_26_injury_review_triage_successor'
      and statements = array[
        'migration_sha256=76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a',
        'classification_rule_version=urc_2025_26_injury_review_triage_2026_08_30_v5',
        'predecessor_version_id=bab7731d-975b-5d49-a34c-6acc6b0c8c94',
        'scope=private_injury_lineage_successor_only'
      ]
  ) or not exists (
    select 1
    from lineage.injury_master_versions_v3
    where id = successor_id
      and predecessor_version_id = predecessor_id
      and migration_sha256 = '76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a'
      and manifest_sha256 = '7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab'
      and delta_payload_sha256 = '111328427560503939a66e845d4a6e0fb8fa606f9dbf4a6f508aa0df04cab637'
      and delta_evidence_sha256 = 'f9e8d82998232a2e7e6f7325f319a685546197b4f4c3ff022f366fafa854c78a'
      and master_workbook_sha256 = '2b5e2243bfc912fac1561789e9327987d058a5543233f068f3bef9928c397670'
  ) then
    raise exception 'installed successor registration or evidence changed';
  end if;

  if exists (
    select 1
    from _pipeline_params parameter
    left join lineage.injury_master_rows_v2 predecessor
      on predecessor.version_id = predecessor_id
     and predecessor.source_row = (parameter.value ->> 'source_row')::integer
    left join lineage.injury_master_rows_v3 successor
      on successor.version_id = successor_id
     and successor.source_row = (parameter.value ->> 'source_row')::integer
    where parameter.value ->> 'kind' = 'row_delta'
      and (
        to_jsonb(predecessor) - 'version_id' <> parameter.value -> 'predecessor'
        or to_jsonb(successor) - 'version_id' <> parameter.value -> 'successor'
      )
  ) or exists (
    select 1
    from lineage.injury_master_rows_v3 successor
    join lineage.injury_master_rows_v2 predecessor
      on predecessor.version_id = predecessor_id
     and predecessor.source_row = successor.source_row
    left join _pipeline_params delta
      on delta.value ->> 'kind' = 'row_delta'
     and (delta.value ->> 'source_row')::integer = successor.source_row
    where successor.version_id = successor_id
      and delta.value is null
      and to_jsonb(successor) - 'version_id' <> to_jsonb(predecessor) - 'version_id'
  ) then
    raise exception 'live successor differs from the exact accepted delta';
  end if;

  if (select count(*) from lineage.injury_master_rows_v3
      where version_id = successor_id) <> 2993
     or (select count(*) from lineage.injury_inclusion_rows_v3
         where version_id = successor_id) <> 1923
     or (select count(*)
         from lineage.injury_master_rows_v3 successor
         join lineage.injury_master_rows_v2 predecessor
           on predecessor.version_id = predecessor_id
          and predecessor.source_row = successor.source_row
         where successor.version_id = successor_id
           and successor.row_values <> predecessor.row_values) <> 438
     or (select count(*)
         from lineage.injury_master_rows_v3 successor
         join lineage.injury_master_rows_v2 predecessor
           on predecessor.version_id = predecessor_id
          and predecessor.source_row = successor.source_row
         where successor.version_id = successor_id
           and successor.final_classification <> predecessor.final_classification) <> 162
     or (select count(*)
         from lineage.injury_master_rows_v3 successor
         join lineage.injury_master_rows_v2 predecessor
           on predecessor.version_id = predecessor_id
          and predecessor.source_row = successor.source_row
         where successor.version_id = successor_id
           and successor.clinical_duration_days is distinct from predecessor.clinical_duration_days) <> 71
     or (select count(*)
         from lineage.injury_inclusion_rows_v3 successor
         join lineage.injury_inclusion_rows_v2 predecessor
           on predecessor.version_id = predecessor_id
          and predecessor.source_row = successor.source_row
         where successor.version_id = successor_id
           and successor.row_values <> predecessor.row_values) <> 277 then
    raise exception 'live successor delta counts changed';
  end if;

  if exists (
    select 1
    from lineage.injury_inclusion_rows_v3 successor
    full join lineage.injury_inclusion_rows_v2 predecessor
      on predecessor.version_id = predecessor_id
     and successor.version_id = successor_id
     and predecessor.source_row = successor.source_row
    where coalesce(successor.version_id, successor_id) = successor_id
      and (successor.source_row is null or predecessor.source_row is null)
  ) then
    raise exception 'live successor inclusion membership drifted';
  end if;

  if (select count(*) from lineage.master_rows where season = '2024-25') <> 3060
     or (select count(*) from lineage.master_rows
         where season = '2024-25' and excluded) <> 755
     or (
       select encode(digest(string_agg(
         source_row::text || ':' || row_values::text || ':' || excluded::text || ':' || coalesce(exclusion_reason, ''),
         E'\n' order by source_row
       ), 'sha256'), 'hex')
       from lineage.master_rows where season = '2024-25'
     ) <> 'fad2ab34a166804d723744b6f351f5ce0368e98fbfac5b7e61e2f110d592cc05' then
    raise exception 'frozen 2024-25 lineage changed';
  end if;
end;
$$;

select jsonb_build_object(
  'captured_at', now(),
  'migration_registration', (
    select to_jsonb(registration)
    from supabase_migrations.schema_migrations registration
    where registration.version = '20260830140000'
  ),
  'successor', (
    select jsonb_build_object(
      'version_id', version.id,
      'predecessor_version_id', version.predecessor_version_id,
      'version_label', version.version_label,
      'rule_version', version.classification_rule_version,
      'migration_sha256', version.migration_sha256,
      'manifest_sha256', version.manifest_sha256,
      'delta_payload_sha256', version.delta_payload_sha256,
      'delta_evidence_sha256', version.delta_evidence_sha256,
      'master_workbook_sha256', version.master_workbook_sha256,
      'master_rows', version.master_row_count,
      'included_rows', version.included_row_count,
      'excluded_rows', version.excluded_row_count,
      'dashboard_injury_rows', version.dashboard_injury_row_count,
      'affected_rows', version.affected_row_count,
      'changed_master_rows', version.changed_master_row_count,
      'changed_classification_rows', version.changed_classification_row_count,
      'changed_duration_rows', version.changed_duration_row_count,
      'changed_inclusion_rows', (
        select count(*)
        from lineage.injury_inclusion_rows_v3 successor
        join lineage.injury_inclusion_rows_v2 predecessor
          on predecessor.version_id = version.predecessor_version_id
         and predecessor.source_row = successor.source_row
        where successor.version_id = version.id
          and successor.row_values <> predecessor.row_values
      ),
      'review_required', (
        select count(*) from lineage.injury_master_rows_v3
        where version_id = version.id and review_required
      ),
      'source_conflicts', (
        select count(*) from lineage.injury_master_rows_v3
        where version_id = version.id and source_conflict
      ),
      'all_classifications', (
        select jsonb_object_agg(final_classification, row_count)
        from (
          select master.final_classification, count(*) row_count
          from lineage.injury_inclusion_rows_v3 inclusion
          join lineage.injury_master_rows_v3 master
            on master.version_id = inclusion.version_id
           and master.source_row = inclusion.source_row
          where inclusion.version_id = version.id
          group by master.final_classification
        ) counts
      ),
      'dashboard_classifications', (
        select jsonb_object_agg(final_classification, row_count)
        from (
          select master.final_classification, count(*) row_count
          from lineage.injury_inclusion_rows_v3 inclusion
          join lineage.injury_master_rows_v3 master
            on master.version_id = inclusion.version_id
           and master.source_row = inclusion.source_row
          where inclusion.version_id = version.id and inclusion.dashboard_eligible
          group by master.final_classification
        ) counts
      )
    )
    from lineage.injury_master_versions_v3 version
    where version.id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
  ),
  'security', jsonb_build_object(
    'rls_enabled', (
      select bool_and(class.relrowsecurity)
      from pg_class class
      join pg_namespace namespace on namespace.oid = class.relnamespace
      where namespace.nspname = 'lineage'
        and class.relname in (
          'injury_classification_rules_v3',
          'injury_master_versions_v3',
          'injury_master_rows_v3',
          'injury_inclusion_rows_v3'
        )
    ),
    'web_reader_select', (
      select bool_or(has_table_privilege(
        'web_reader', format('%I.%I', namespace.nspname, class.relname), 'select'
      ))
      from pg_class class
      join pg_namespace namespace on namespace.oid = class.relnamespace
      where namespace.nspname = 'lineage'
        and class.relname in (
          'injury_classification_rules_v3',
          'injury_master_versions_v3',
          'injury_master_rows_v3',
          'injury_inclusion_rows_v3'
        )
    ),
    'immutability_triggers_enabled', (
      select count(*)
      from pg_trigger
      where tgrelid in (
        'lineage.injury_classification_rules_v3'::regclass,
        'lineage.injury_master_versions_v3'::regclass,
        'lineage.injury_master_rows_v3'::regclass,
        'lineage.injury_inclusion_rows_v3'::regclass
      ) and not tgisinternal and tgenabled <> 'D'
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
