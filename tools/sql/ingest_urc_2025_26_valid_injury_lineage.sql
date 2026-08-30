-- Load the exact locally reviewed first-valid 2025-26 injury lineage.
-- The caller supplies one version object, master rows and inclusion rows in
-- `_pipeline_params`. Every assertion runs inside the same transaction.

do $$
declare
  version_count integer;
  master_payload_count integer;
  inclusion_payload_count integer;
  attested_payload_sha256 text;
begin
  select payload_sha256 into strict attested_payload_sha256
  from _pipeline_params_attestation;

  if attested_payload_sha256 <> '7a11596713ce730a4404039a958d8a8c10cca2092115a8fa40d951e22940e8c2' then
    raise exception '2025-26 injury load payload SHA-256 is not the accepted byte digest';
  end if;

  select count(*) filter (where value ->> 'kind' = 'version'),
         count(*) filter (where value ->> 'kind' = 'master_row'),
         count(*) filter (where value ->> 'kind' = 'inclusion_row')
  into version_count, master_payload_count, inclusion_payload_count
  from _pipeline_params;

  if version_count <> 1 or master_payload_count = 0 or inclusion_payload_count = 0 then
    raise exception 'invalid 2025-26 injury load payload shape';
  end if;

  if exists (
    select 1 from _pipeline_params where value ->> 'kind' not in (
      'version', 'master_row', 'inclusion_row'
    )
  ) then
    raise exception 'unknown 2025-26 injury load payload item';
  end if;

  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260829230000'
      and name = 'urc_2025_26_valid_injury_ingest'
      and statements = array[
        'migration_sha256=f4c5e3986e13a0b3b1a2e4dda6759f1cf476095ecb77e38554d1226936eba62b',
        'classification_rule_version=urc_2025_26_injury_classification_2026_08_29_v2',
        'scope=private_injury_lineage_only'
      ]
  ) then
    raise exception '2025-26 valid injury migration is not checksum-registered';
  end if;

  if exists (select 1 from lineage.injury_master_versions_v2 where season = '2025-26') then
    raise exception 'a valid 2025-26 injury lineage already exists';
  end if;
end;
$$;

insert into lineage.injury_master_versions_v2 (
  id,
  season,
  version_label,
  status,
  classification_rule_version,
  migration_version,
  migration_sha256,
  master_csv_sha256,
  master_workbook_sha256,
  inclusion_csv_sha256,
  classification_evidence_sha256,
  manifest_sha256,
  source_bundle_sha256,
  master_json_sha256,
  inclusion_json_sha256,
  load_payload_sha256,
  master_row_count,
  included_row_count,
  excluded_row_count,
  dashboard_injury_row_count,
  team_count,
  source_manifest,
  classification_contract,
  summary
)
select
  (value ->> 'id')::uuid,
  value ->> 'season',
  value ->> 'version_label',
  'valid_ingested',
  value ->> 'classification_rule_version',
  value ->> 'migration_version',
  value ->> 'migration_sha256',
  value ->> 'master_csv_sha256',
  value ->> 'master_workbook_sha256',
  value ->> 'inclusion_csv_sha256',
  value ->> 'classification_evidence_sha256',
  value ->> 'manifest_sha256',
  value ->> 'source_bundle_sha256',
  value ->> 'master_json_sha256',
  value ->> 'inclusion_json_sha256',
  (select payload_sha256 from _pipeline_params_attestation),
  (value ->> 'master_row_count')::integer,
  (value ->> 'included_row_count')::integer,
  (value ->> 'excluded_row_count')::integer,
  (value ->> 'dashboard_injury_row_count')::integer,
  (value ->> 'team_count')::integer,
  value -> 'source_manifest',
  value -> 'classification_contract',
  value -> 'summary'
from _pipeline_params
where value ->> 'kind' = 'version';

insert into lineage.injury_master_rows_v2 (
  version_id,
  source_row,
  team_key,
  source_group,
  source_task_id,
  source_file_name,
  source_artifact_sha256,
  source_row_number,
  source_locator,
  source_artifact_row_sha256,
  final_master_row_sha256,
  row_values,
  excluded,
  exclusion_reason,
  qualifying_source_classification,
  final_classification,
  classification_basis,
  clinical_duration_days,
  clinical_duration_basis,
  time_loss_days,
  return_date,
  return_date_basis,
  open_status,
  participation_restriction_evidence,
  unrestricted_participation_evidence,
  source_conflict,
  review_required,
  review_reasons,
  derived_fields,
  verified_urc_fixture
)
select
  (value ->> 'version_id')::uuid,
  (value ->> 'source_row')::integer,
  value ->> 'team_key',
  value ->> 'source_group',
  (value ->> 'source_task_id')::uuid,
  value ->> 'source_file_name',
  value ->> 'source_artifact_sha256',
  value ->> 'source_row_number',
  value ->> 'source_locator',
  value ->> 'source_artifact_row_sha256',
  value ->> 'final_master_row_sha256',
  value -> 'row_values',
  (value ->> 'excluded')::boolean,
  nullif(value ->> 'exclusion_reason', ''),
  nullif(value ->> 'qualifying_source_classification', ''),
  value ->> 'final_classification',
  value ->> 'classification_basis',
  nullif(value ->> 'clinical_duration_days', '')::integer,
  value ->> 'clinical_duration_basis',
  nullif(value ->> 'time_loss_days', '')::integer,
  nullif(value ->> 'return_date', '')::date,
  value ->> 'return_date_basis',
  (value ->> 'open_status')::boolean,
  (value ->> 'participation_restriction_evidence')::boolean,
  (value ->> 'unrestricted_participation_evidence')::boolean,
  (value ->> 'source_conflict')::boolean,
  (value ->> 'review_required')::boolean,
  value -> 'review_reasons',
  array(select jsonb_array_elements_text(value -> 'derived_fields')),
  (value ->> 'verified_urc_fixture')::boolean
from _pipeline_params
where value ->> 'kind' = 'master_row'
order by (value ->> 'source_row')::integer;

insert into lineage.injury_inclusion_rows_v2 (
  version_id,
  inclusion_row,
  source_row,
  team_key,
  row_values,
  row_sha256,
  dashboard_eligible,
  dashboard_eligibility_reason
)
select
  (value ->> 'version_id')::uuid,
  (value ->> 'inclusion_row')::integer,
  (value ->> 'source_row')::integer,
  value ->> 'team_key',
  value -> 'row_values',
  value ->> 'row_sha256',
  (value ->> 'dashboard_eligible')::boolean,
  value ->> 'dashboard_eligibility_reason'
from _pipeline_params
where value ->> 'kind' = 'inclusion_row'
order by (value ->> 'inclusion_row')::integer;

do $$
declare
  loaded_version lineage.injury_master_versions_v2%rowtype;
  classification_counts jsonb;
begin
  select version.* into strict loaded_version
  from lineage.injury_master_versions_v2 version
  join _pipeline_params parameter
    on parameter.value ->> 'kind' = 'version'
   and version.id = (parameter.value ->> 'id')::uuid;

  if (select count(*) from lineage.injury_master_rows_v2 where version_id = loaded_version.id)
       <> loaded_version.master_row_count
     or (select count(*) from lineage.injury_master_rows_v2 where version_id = loaded_version.id and excluded)
       <> loaded_version.excluded_row_count
     or (select count(*) from lineage.injury_inclusion_rows_v2 where version_id = loaded_version.id)
       <> loaded_version.included_row_count
     or (select count(*) from lineage.injury_inclusion_rows_v2 where version_id = loaded_version.id and dashboard_eligible)
       <> loaded_version.dashboard_injury_row_count then
    raise exception '2025-26 injury load row counts do not reconcile';
  end if;

  if (
    select array_agg(distinct team_key order by team_key)
    from lineage.injury_master_rows_v2
    where version_id = loaded_version.id
  ) <> array[
    'benetton', 'bulls', 'cardiff', 'connacht', 'dragons', 'edinburgh',
    'glasgow', 'leinster', 'lions', 'munster', 'ospreys', 'scarlets',
    'sharks', 'stormers', 'ulster', 'zebre'
  ]::text[] then
    raise exception '2025-26 injury load does not contain the exact 16-team roster';
  end if;

  if exists (
    select 1
    from lineage.injury_inclusion_rows_v2 inclusion
    join lineage.injury_master_rows_v2 master
      on master.version_id = inclusion.version_id
     and master.source_row = inclusion.source_row
    where inclusion.version_id = loaded_version.id
      and (
        master.excluded
        or inclusion.row_values <> master.row_values
        or inclusion.row_sha256 <> master.final_master_row_sha256
        or inclusion.team_key <> master.team_key
      )
  ) or exists (
    select 1
    from lineage.injury_master_rows_v2 master
    left join lineage.injury_inclusion_rows_v2 inclusion
      on inclusion.version_id = master.version_id
     and inclusion.source_row = master.source_row
    where master.version_id = loaded_version.id
      and (not master.excluded) <> (inclusion.source_row is not null)
  ) then
    raise exception '2025-26 master-to-inclusion bridge is invalid';
  end if;

  if exists (
    select 1
    from lineage.injury_master_rows_v2 master
    cross join lateral jsonb_each_text(master.row_values) value
    where master.version_id = loaded_version.id
      and value.value ~* '#(ref!|value!|name\?|num!|div/0!|n/a)'
  ) then
    raise exception '2025-26 injury load contains a literal spreadsheet error';
  end if;

  if exists (
    select 1
    from lineage.injury_master_rows_v2
    where version_id = loaded_version.id
      and (
        (final_classification = 'Medical Attention' and time_loss_days is not null)
        or (classification_basis = 'open_record_fallback' and (
          final_classification <> 'Time Loss'
          or not open_status
          or return_date is not null
          or time_loss_days is not null
        ))
        or (
          classification_basis = 'source_participation_restriction'
          and participation_restriction_evidence is distinct from true
        )
        or (
          classification_basis = 'source_unrestricted_participation'
          and participation_restriction_evidence is distinct from false
        )
        or (
          open_status
          and final_classification = 'Time Loss'
          and not unrestricted_participation_evidence
          and (
            return_date is not null
            or return_date_basis <> 'missing_open_record'
            or time_loss_days is not null
          )
        )
        or (source_conflict and not review_required)
      )
  ) then
    raise exception '2025-26 classification successor contract failed';
  end if;

  select jsonb_object_agg(final_classification, row_count)
  into classification_counts
  from (
    select master.final_classification, count(*)::integer as row_count
    from lineage.injury_inclusion_rows_v2 inclusion
    join lineage.injury_master_rows_v2 master
      on master.version_id = inclusion.version_id
     and master.source_row = inclusion.source_row
    where inclusion.version_id = loaded_version.id
      and inclusion.dashboard_eligible
    group by master.final_classification
  ) counts;
  if classification_counts <> loaded_version.summary -> 'classification_dashboard_injuries' then
    raise exception '2025-26 dashboard injury classification counts changed';
  end if;

  if not exists (
    select 1
    from lineage.baselines baseline
    where baseline.season = '2024-25'
      and baseline.baseline_identity = 'v5 baseline 2024-25'
      and baseline.baseline_record_sha256 = '6cbb6d45d6dd181b9bda3a228cf4c86d509060a75f631818726a4748115e0217'
      and baseline.master_json_sha256 = '15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63'
      and baseline.ledger_sha256 = 'b92c35cdfc86acabfcc999be2c007e084495321c637d1866b0924ad2407a37fe'
      and baseline.inclusion_csv_sha256 = 'e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb'
      and baseline.source_row_mapping_sha256 = '9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f'
  ) or (select count(*) from lineage.master_rows where season = '2024-25') <> 3060
    or (select count(*) from lineage.master_rows where season = '2024-25' and excluded) <> 755
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
