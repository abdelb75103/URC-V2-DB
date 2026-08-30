-- Load the exact accepted 2025-26 adjudication successor.
-- The transaction clones the immutable v2 predecessor, substitutes only the
-- checksum-bound row deltas, and leaves reporting, exposure and releases alone.

do $$
declare
  attested_payload_sha256 text;
  version_count integer;
  delta_count integer;
begin
  select payload_sha256 into strict attested_payload_sha256
  from _pipeline_params_attestation;

  if attested_payload_sha256 <> '111328427560503939a66e845d4a6e0fb8fa606f9dbf4a6f508aa0df04cab637' then
    raise exception '2025-26 injury successor payload SHA-256 is not the accepted byte digest';
  end if;

  select count(*) filter (where value ->> 'kind' = 'version'),
         count(*) filter (where value ->> 'kind' = 'row_delta')
  into version_count, delta_count
  from _pipeline_params;

  if version_count <> 1 or delta_count <> 1975
     or (select count(distinct (value ->> 'source_row')::integer)
         from _pipeline_params where value ->> 'kind' = 'row_delta') <> 1975 then
    raise exception 'invalid 2025-26 injury successor payload shape';
  end if;

  if exists (
    select 1 from _pipeline_params
    where value ->> 'kind' not in ('version', 'row_delta')
  ) then
    raise exception 'unknown 2025-26 injury successor payload item';
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
  ) then
    raise exception '2025-26 injury successor migration is not checksum-registered';
  end if;

  if not exists (
    select 1
    from lineage.injury_master_versions_v2
    where id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
      and season = '2025-26'
      and version_label = 'urc-injury-2025-26-valid-20260830-a2'
      and status = 'valid_ingested'
      and classification_rule_version = 'urc_2025_26_injury_classification_2026_08_29_v2'
      and migration_version = '20260829230000'
      and migration_sha256 = 'f4c5e3986e13a0b3b1a2e4dda6759f1cf476095ecb77e38554d1226936eba62b'
      and master_csv_sha256 = 'c8c9839445ac2af1d6e68f85c23c50bac784273387f6f1c7411a4deb62b329bd'
      and master_workbook_sha256 = '15be3edbe9617f6627e421e6cad470320aa5c5c9e5aed48c92a8225b3c24d643'
      and inclusion_csv_sha256 = '857240ebf02880ce82e0c58b8907e28f9a58446d6a703abc6179c9ecef238394'
      and classification_evidence_sha256 = 'b074d8cdc21b42c4659a622f20e611545513bc55b7c5e795d0405f1de507ff51'
      and manifest_sha256 = '9fc869cff5732becb20db3b7ec2bbd71a619096aaa32895ff0ac726fbf9395c7'
      and source_bundle_sha256 = '6625218eaed1ebb918e02f5d43e162360786ce62ed8020f9f9f0b4e3eeaf9d28'
      and load_payload_sha256 = '7a11596713ce730a4404039a958d8a8c10cca2092115a8fa40d951e22940e8c2'
      and master_row_count = 2993
      and included_row_count = 1923
      and excluded_row_count = 1070
      and dashboard_injury_row_count = 1484
      and team_count = 16
  ) then
    raise exception 'installed 2025-26 injury predecessor changed';
  end if;

  if (select count(*) from lineage.injury_master_rows_v2
      where version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94') <> 2993
     or (select count(*) from lineage.injury_inclusion_rows_v2
         where version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94') <> 1923 then
    raise exception 'installed 2025-26 injury predecessor row counts changed';
  end if;

  if exists (
    select 1
    from _pipeline_params parameter
    left join lineage.injury_master_rows_v2 predecessor
      on predecessor.version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
     and predecessor.source_row = (parameter.value ->> 'source_row')::integer
    where parameter.value ->> 'kind' = 'row_delta'
      and (
        predecessor.source_row is null
        or to_jsonb(predecessor) - 'version_id' <> parameter.value -> 'predecessor'
      )
  ) then
    raise exception '2025-26 injury successor predecessor state does not match live';
  end if;

  if exists (
    select 1 from lineage.injury_master_versions_v3
    where season = '2025-26'
       or id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
       or predecessor_version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
  ) then
    raise exception 'accepted 2025-26 injury successor already exists';
  end if;
end;
$$;

insert into lineage.injury_master_versions_v3 (
  id,
  predecessor_version_id,
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
  delta_payload_sha256,
  delta_evidence_sha256,
  master_row_count,
  included_row_count,
  excluded_row_count,
  dashboard_injury_row_count,
  team_count,
  affected_row_count,
  changed_master_row_count,
  changed_classification_row_count,
  changed_duration_row_count,
  classification_contract,
  summary
)
select
  (value ->> 'id')::uuid,
  (value ->> 'predecessor_version_id')::uuid,
  value ->> 'season',
  value ->> 'version_label',
  'valid_ingested_successor',
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
  value ->> 'delta_evidence_sha256',
  (value ->> 'master_row_count')::integer,
  (value ->> 'included_row_count')::integer,
  (value ->> 'excluded_row_count')::integer,
  (value ->> 'dashboard_injury_row_count')::integer,
  (value ->> 'team_count')::integer,
  (value ->> 'affected_row_count')::integer,
  (value ->> 'changed_master_row_count')::integer,
  (value ->> 'changed_classification_row_count')::integer,
  (value ->> 'changed_duration_row_count')::integer,
  value -> 'classification_contract',
  value -> 'summary'
from _pipeline_params
where value ->> 'kind' = 'version';

insert into lineage.injury_master_rows_v3
select (jsonb_populate_record(
  null::lineage.injury_master_rows_v3,
  (
    case
      when delta.value is null then to_jsonb(predecessor) - 'version_id'
      else delta.value -> 'successor'
    end
  ) || jsonb_build_object('version_id', '2f419706-8c36-58dd-b4cb-e92162e782b8')
)).*
from lineage.injury_master_rows_v2 predecessor
left join _pipeline_params delta
  on delta.value ->> 'kind' = 'row_delta'
 and (delta.value ->> 'source_row')::integer = predecessor.source_row
where predecessor.version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
order by predecessor.source_row;

insert into lineage.injury_inclusion_rows_v3 (
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
  '2f419706-8c36-58dd-b4cb-e92162e782b8',
  predecessor.inclusion_row,
  predecessor.source_row,
  successor.team_key,
  successor.row_values,
  successor.final_master_row_sha256,
  predecessor.dashboard_eligible,
  predecessor.dashboard_eligibility_reason
from lineage.injury_inclusion_rows_v2 predecessor
join lineage.injury_master_rows_v3 successor
  on successor.version_id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
 and successor.source_row = predecessor.source_row
where predecessor.version_id = 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
order by predecessor.inclusion_row;

do $$
declare
  loaded_version lineage.injury_master_versions_v3%rowtype;
  all_classification_counts jsonb;
  dashboard_classification_counts jsonb;
begin
  select * into strict loaded_version
  from lineage.injury_master_versions_v3
  where id = '2f419706-8c36-58dd-b4cb-e92162e782b8';

  if loaded_version.predecessor_version_id <> 'bab7731d-975b-5d49-a34c-6acc6b0c8c94'
     or loaded_version.delta_payload_sha256 <> '111328427560503939a66e845d4a6e0fb8fa606f9dbf4a6f508aa0df04cab637'
     or loaded_version.delta_evidence_sha256 <> 'f9e8d82998232a2e7e6f7325f319a685546197b4f4c3ff022f366fafa854c78a'
     or loaded_version.manifest_sha256 <> '7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab'
     or loaded_version.master_workbook_sha256 <> '2b5e2243bfc912fac1561789e9327987d058a5543233f068f3bef9928c397670'
     or loaded_version.affected_row_count <> 1975
     or loaded_version.changed_master_row_count <> 438
     or loaded_version.changed_classification_row_count <> 162
     or loaded_version.changed_duration_row_count <> 71 then
    raise exception '2025-26 injury successor version evidence changed';
  end if;

  if (select count(*) from lineage.injury_master_rows_v3
      where version_id = loaded_version.id) <> 2993
     or (select count(*) from lineage.injury_master_rows_v3
         where version_id = loaded_version.id and excluded) <> 1070
     or (select count(*) from lineage.injury_inclusion_rows_v3
         where version_id = loaded_version.id) <> 1923
     or (select count(*) from lineage.injury_inclusion_rows_v3
         where version_id = loaded_version.id and dashboard_eligible) <> 1484 then
    raise exception '2025-26 injury successor row counts do not reconcile';
  end if;

  if (
    select array_agg(distinct team_key order by team_key)
    from lineage.injury_master_rows_v3
    where version_id = loaded_version.id
  ) <> array[
    'benetton', 'bulls', 'cardiff', 'connacht', 'dragons', 'edinburgh',
    'glasgow', 'leinster', 'lions', 'munster', 'ospreys', 'scarlets',
    'sharks', 'stormers', 'ulster', 'zebre'
  ]::text[] then
    raise exception '2025-26 injury successor does not contain the exact 16-team roster';
  end if;

  if exists (
    select 1
    from _pipeline_params parameter
    join lineage.injury_master_rows_v3 successor
      on successor.version_id = loaded_version.id
     and successor.source_row = (parameter.value ->> 'source_row')::integer
    where parameter.value ->> 'kind' = 'row_delta'
      and to_jsonb(successor) - 'version_id' <> parameter.value -> 'successor'
  ) or (
    select count(*)
    from lineage.injury_master_rows_v3 successor
    join lineage.injury_master_rows_v2 predecessor
      on predecessor.version_id = loaded_version.predecessor_version_id
     and predecessor.source_row = successor.source_row
    left join _pipeline_params delta
      on delta.value ->> 'kind' = 'row_delta'
     and (delta.value ->> 'source_row')::integer = successor.source_row
    where successor.version_id = loaded_version.id
      and delta.value is null
      and to_jsonb(successor) - 'version_id' <> to_jsonb(predecessor) - 'version_id'
  ) <> 0 then
    raise exception '2025-26 injury successor differs outside the accepted delta';
  end if;

  if exists (
    select 1
    from lineage.injury_inclusion_rows_v3 inclusion
    join lineage.injury_master_rows_v3 master
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
    from lineage.injury_master_rows_v3 master
    left join lineage.injury_inclusion_rows_v3 inclusion
      on inclusion.version_id = master.version_id
     and inclusion.source_row = master.source_row
    where master.version_id = loaded_version.id
      and (not master.excluded) <> (inclusion.source_row is not null)
  ) then
    raise exception '2025-26 injury successor inclusion bridge is invalid';
  end if;

  if exists (
    select 1
    from lineage.injury_master_rows_v3 master
    cross join lateral jsonb_each_text(master.row_values) value
    where master.version_id = loaded_version.id
      and value.value ~* '#(ref!|value!|name\?|num!|div/0!|n/a)'
  ) then
    raise exception '2025-26 injury successor contains a literal spreadsheet error';
  end if;

  if exists (
    select 1
    from lineage.injury_master_rows_v3
    where version_id = loaded_version.id
      and (
        review_required
        or (final_classification = 'Medical Attention' and time_loss_days is not null)
        or (
          classification_basis = 'open_record_fallback'
          and (
            final_classification <> 'Time Loss'
            or not open_status
            or return_date is not null
            or time_loss_days is not null
          )
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
      )
  ) then
    raise exception '2025-26 injury successor classification contract failed';
  end if;

  select jsonb_object_agg(final_classification, row_count)
  into all_classification_counts
  from (
    select master.final_classification, count(*)::integer row_count
    from lineage.injury_inclusion_rows_v3 inclusion
    join lineage.injury_master_rows_v3 master
      on master.version_id = inclusion.version_id
     and master.source_row = inclusion.source_row
    where inclusion.version_id = loaded_version.id
    group by master.final_classification
  ) counts;

  select jsonb_object_agg(final_classification, row_count)
  into dashboard_classification_counts
  from (
    select master.final_classification, count(*)::integer row_count
    from lineage.injury_inclusion_rows_v3 inclusion
    join lineage.injury_master_rows_v3 master
      on master.version_id = inclusion.version_id
     and master.source_row = inclusion.source_row
    where inclusion.version_id = loaded_version.id
      and inclusion.dashboard_eligible
    group by master.final_classification
  ) counts;

  if all_classification_counts <> '{"Medical Attention":840,"Time Loss":1083}'::jsonb
     or dashboard_classification_counts <> '{"Medical Attention":607,"Time Loss":877}'::jsonb
     or (select count(*) from lineage.injury_master_rows_v3
         where version_id = loaded_version.id and source_conflict) <> 350 then
    raise exception '2025-26 injury successor classification counts changed';
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
