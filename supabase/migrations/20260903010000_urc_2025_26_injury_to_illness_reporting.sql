-- Apply only after the operator proves the approved live target.
-- Scope: 24 reviewed Problem type decisions. Source and release storage stay intact.
begin;

do $$
begin
  if current_database() <> 'postgres'
    or (select target_attested from reporting.approved_dashboard_reader_target_v8) is distinct from true
    or not exists (
      select 1 from supabase_migrations.schema_migrations
      where version = '20260901021000'
        and statements[1] = 'migration_sha256=eb015ecaa8ca3db1d4992f4c4d3498ff5f5aa65aac60f16693b780104443e5d0'
    )
    or not exists (
      select 1 from lineage.injury_master_versions_v3
      where id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
        and master_csv_sha256 = '1872fae1f33c32fab6ec5b86a83a8e475f463910a72c76d4546d35bcf7228264'
    )
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1) <> 1545
    or (select count(*) from analysis.urc_illness_profile_rows_v1 where season = '2025-26') <> 439
  then
    raise exception 'Injury-to-illness reporting predecessor does not match';
  end if;
end;
$$;

-- Retain definitions for the five replaced views. Rollback keeps all decision evidence.
create table audit.urc_2025_26_injury_to_illness_rollback_v1 (
  object_name text primary key check (object_name in (
    'analysis.urc_2025_26_canonical_injury_rows_v1',
    'analysis.urc_illness_team_profiles_v1',
    'reporting.latest_team_dashboard_v7',
    'reporting.latest_league_dashboard_v7',
    'reporting.latest_dashboard_cache_token_v2'
  )),
  definition text not null
);
insert into audit.urc_2025_26_injury_to_illness_rollback_v1
select name, pg_get_viewdef(name::regclass, true)
from unnest(array[
  'analysis.urc_2025_26_canonical_injury_rows_v1',
  'analysis.urc_illness_team_profiles_v1',
  'reporting.latest_team_dashboard_v7',
  'reporting.latest_league_dashboard_v7',
  'reporting.latest_dashboard_cache_token_v2'
]) name;

create table audit.urc_2025_26_injury_to_illness_decisions_v1 (
  source_row integer primary key,
  version_id uuid not null check (version_id = '2f419706-8c36-58dd-b4cb-e92162e782b8'),
  team_key text not null,
  final_master_row_sha256 text not null,
  source_artifact_sha256 text not null,
  source_artifact_row_sha256 text not null,
  field_name text not null check (field_name = 'Problem type'),
  before_value text not null check (before_value = 'Injury'),
  after_value text not null check (after_value = 'Illness'),
  final_classification text not null,
  time_loss_days integer,
  source_label text not null,
  illness_code text not null,
  illness_label text not null,
  mapping_basis text not null check (mapping_basis in ('accepted_exact_label', 'retained_source_identity')),
  reason_code text not null check (reason_code = 'reviewed_injury_to_illness'),
  rationale text not null,
  rule_version text not null check (rule_version = 'urc_2025_26_injury_to_illness_2026_09_03_v1'),
  approved_by text not null check (approved_by = 'Abdel Babiker'),
  recorded_at timestamptz not null default now(),
  foreign key (version_id, source_row)
    references lineage.injury_master_rows_v3(version_id, source_row)
);

with approved(source_row, team_key, row_sha256, classification, days) as (values
  (401, 'dragons', 'f7dd842b050de42672b9e85df0709d8bd245b7e3bb597017f9c2830c7ccf79e2', 'Time Loss', 2),
  (446, 'dragons', '9e07f517b3c51a97054242fe81a7eb9efee71cc2b114bd24818559796b25610b', 'Time Loss', 6),
  (464, 'dragons', '2e60af71a9d0133dc668eb03411ece80361685196bd0e8a14f0cc7985aed7650', 'Time Loss', 3),
  (468, 'dragons', '534bd552bb327d21e2bbb07c4f2f7d51d267554af8f323d69a7bafc2eb519277', 'Time Loss', 5),
  (481, 'dragons', '3fd3e07ecebdea29dd9996f6753002f70694c75f9136d688f82bfd8157f3f528', 'Time Loss', 3),
  (494, 'dragons', 'ff133a2a5b7af4ff34a96976d4de98a8a74b368a0d083e2cdb82dd19f05e5e56', 'Time Loss', 11),
  (509, 'dragons', '323748d9a43d57e85fa8966a243f7b58ad7c14b1608d235cff4be6eb9d6c2936', 'Time Loss', 7),
  (510, 'dragons', '081f336f4e6fb685d092ea0c2eaaff647eb9d83e9b46680ad82ce641fabcf1cf', 'Time Loss', 5),
  (514, 'dragons', 'd4c258fe7e1ef52bb1775047af24c299a5c3b34226d45b797c8131eecb02f0ba', 'Time Loss', 6),
  (515, 'dragons', '9820380bee867d4ea134536f8b1753824591f29c1cd2147f6e57d3b78176edc5', 'Time Loss', 2),
  (555, 'dragons', 'a89289e1f9356fe635df648ca0b83839c382f6059dc620f7f87d0b542a385a37', 'Time Loss', 2),
  (556, 'dragons', 'cdb6e59e1f6e4f055928b2550997b6f6cecf5a997725f2759a9373672a489256', 'Time Loss', 2),
  (949, 'glasgow', '8e4d47764c1ff43c13b27d5b5d622242d28776a36fa11892fa2c1582a4a1d346', 'Medical Attention', null),
  (1608, 'ospreys', '5d86f0f5f5e83af8500d3287bba8bec2aeda982a279038d678f79c9807e01d94', 'Time Loss', 4),
  (1610, 'ospreys', 'fe987a9380404daf672318d99622b7930cfcf589b332efae88c4b4d645837733', 'Time Loss', 2),
  (1611, 'ospreys', 'ce9a27452e6baeb423af0fd903934976ac9771f1604cd14528436a2c5c348a7c', 'Time Loss', 3),
  (1622, 'ospreys', '62752b86f540224e04098ab8e1b3ece1fc7a8ca4841df4f7e1d83d774d3bed7c', 'Time Loss', 4),
  (1631, 'ospreys', 'b878ac643b1a138741fb56ff6dd3a334bda0264613f599c7889bf01ad87a9906', 'Time Loss', 3),
  (1633, 'ospreys', '646d32326ac030201a4e3dc05fd1b5bd206ff609f210df90b5311317b4d9c0c2', 'Time Loss', 4),
  (1645, 'ospreys', '4e933a52dab6772ff1ce92608dddf8eb363b9f6a40767dee37fda6def41e283a', 'Time Loss', 7),
  (1646, 'ospreys', '96da96e582272ad7e0e0f6f39fe9f480545802ec84cbc0d3d51a96228edfe102', 'Time Loss', 3),
  (1662, 'ospreys', 'e84a91ebf81b12b8e43f399fe5c4b140617b260ff3bc2fe61797b93399bc7f89', 'Time Loss', 2),
  (1666, 'ospreys', '1de05634861513ba2026ce1a56ded6f894914e4072049cea380b02bc61b84cfa', 'Time Loss', 2),
  (1696, 'ospreys', '12d25840cdef29a601874b2ee94ab152ce2663d9b0b0c84757c8f306305985b1', 'Time Loss', 4)
)
insert into audit.urc_2025_26_injury_to_illness_decisions_v1
select master.source_row, master.version_id, master.team_key,
  master.final_master_row_sha256, master.source_artifact_sha256,
  master.source_artifact_row_sha256,
  'Problem type', 'Injury', 'Illness', master.final_classification,
  master.time_loss_days, label.source_label,
  coalesce(profile.illness_code, 'illness_identity_' ||
    encode(extensions.digest(label.source_label, 'sha256'), 'hex')),
  coalesce(profile.illness_label, label.source_label),
  case when profile.illness_code is null then 'retained_source_identity'
    else 'accepted_exact_label' end,
  'reviewed_injury_to_illness',
  'Approved source-row correction using retained Illness tissue evidence; classification and duration are unchanged.',
  'urc_2025_26_injury_to_illness_2026_09_03_v1', 'Abdel Babiker', now()
from approved
join lineage.injury_master_rows_v3 master
  on master.source_row = approved.source_row
 and master.team_key = approved.team_key
 and master.version_id = '2f419706-8c36-58dd-b4cb-e92162e782b8'
 and master.final_master_row_sha256 = approved.row_sha256
 and master.final_classification = approved.classification
 and master.time_loss_days is not distinct from approved.days
join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
  on evidence.successor_version_id = master.version_id
join lineage.injury_inclusion_rows_v3 inclusion
  on inclusion.version_id = master.version_id
 and inclusion.source_row = master.source_row
 and inclusion.team_key = master.team_key
join analysis.urc_2025_26_canonical_injury_rows_v1 canonical
  on canonical.source_row = master.source_row and canonical.team_key = master.team_key
cross join lateral (
  select coalesce(nullif(btrim(master.row_values ->> 'Specific Diagnosis'), ''), 'Unknown') as source_label
) label
left join audit.urc_2025_26_illness_exact_labels_v1 profile using (source_label)
where not master.excluded
  and master.exclusion_reason is null
  and nullif(btrim(master.row_values ->> 'Exclusion Reason'), '') is null
  and master.row_values ->> 'Problem type' = 'Injury'
  and master.row_values ->> 'Injury Tissue Type/s' = 'Illness'
  and inclusion.dashboard_eligible
  and inclusion.dashboard_eligibility_reason = 'injury_record'
  and canonical.is_time_loss = (master.final_classification = 'Time Loss')
  and canonical.days_lost is not distinct from master.time_loss_days;

do $$
begin
  if (select count(*) from audit.urc_2025_26_injury_to_illness_decisions_v1) <> 24
    or (select count(*) from audit.urc_2025_26_injury_to_illness_decisions_v1
      where final_classification = 'Time Loss') <> 23
    or (select sum(time_loss_days) from audit.urc_2025_26_injury_to_illness_decisions_v1) <> 92
    or not exists (select 1 from audit.urc_2025_26_injury_to_illness_decisions_v1
      where source_row = 949 and team_key = 'glasgow'
        and final_classification = 'Medical Attention' and time_loss_days is null)
    or (select count(*) from audit.urc_2025_26_injury_to_illness_decisions_v1
      where mapping_basis = 'retained_source_identity') <> 6
    or exists (select 1 from audit.urc_2025_26_injury_to_illness_decisions_v1
      where mapping_basis = 'retained_source_identity' and source_label not in (
        'Asthma/allergy/hay fever/respiratory',
        'Other skin infection not specifically mentioned', 'Migraine'
      ))
  then
    raise exception 'The exact 24 approved source rows or retained duration values did not match';
  end if;
end;
$$;

alter table audit.urc_2025_26_injury_to_illness_decisions_v1 enable row level security;
alter table audit.urc_2025_26_injury_to_illness_rollback_v1 enable row level security;
create trigger injury_to_illness_decisions_v1_immutable before update or delete
on audit.urc_2025_26_injury_to_illness_decisions_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
create trigger injury_to_illness_rollback_v1_immutable before update or delete
on audit.urc_2025_26_injury_to_illness_rollback_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
revoke all on audit.urc_2025_26_injury_to_illness_decisions_v1,
  audit.urc_2025_26_injury_to_illness_rollback_v1
from public, anon, authenticated, web_reader;

-- One evidence-bound decision set drives both cohort boundaries.
create or replace view analysis.urc_2025_26_canonical_injury_rows_v1
with (security_invoker = true) as
select injury.team_key, injury.source_row, injury.injury_date,
  injury.is_time_loss, injury.days_lost, injury.setting_code,
  injury.contact_context,
  injury.reporting_body_location_code as body_location_code,
  injury.reporting_body_location_label as body_location_label,
  injury.reporting_injury_type_code as injury_type_code,
  injury.reporting_injury_type_label as injury_type_label,
  injury.reporting_diagnosis_code as diagnosis_code,
  injury.diagnosis_label, injury.severity_code
from analysis.urc_2025_26_reporting_key_rows_v3 injury
join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence on true
join lineage.injury_master_rows_v3 master
  on master.version_id = evidence.successor_version_id
 and master.source_row = injury.source_row
where lower(btrim(master.row_values ->> 'Problem type')) = 'injury'
  and not exists (
    select 1 from audit.urc_2025_26_injury_to_illness_decisions_v1 decision
    where decision.version_id = master.version_id
      and decision.source_row = master.source_row
      and decision.final_master_row_sha256 = master.final_master_row_sha256
  );

create view analysis.urc_illness_profile_rows_v2
with (security_invoker = true) as
select * from analysis.urc_illness_profile_rows_v1
union all
select '2025-26', team_key, source_row, illness_code, illness_label,
  time_loss_days is not null, time_loss_days
from audit.urc_2025_26_injury_to_illness_decisions_v1;
revoke all on analysis.urc_illness_profile_rows_v2
from public, anon, authenticated, web_reader;

-- Reuse the existing illness aggregate, changing only its row input.
do $$
declare previous text;
begin
  select definition into previous
  from audit.urc_2025_26_injury_to_illness_rollback_v1
  where object_name = 'analysis.urc_illness_team_profiles_v1';
  if strpos(previous, 'analysis.urc_illness_profile_rows_v1') = 0 then
    raise exception 'Illness aggregate source binding changed';
  end if;
  execute 'create or replace view analysis.urc_illness_team_profiles_v1 as ' ||
    replace(previous, 'urc_illness_profile_rows_v1', 'urc_illness_profile_rows_v2');
end;
$$;
refresh materialized view analysis.urc_diagnosis_family_rows_v1;

-- ponytail: copy the accepted calculator, with only the existing month formats recognised.
do $$
declare previous text;
begin
  previous := pg_get_functiondef('reporting.urc_canonical_injury_sections_json_v1(text,text)'::regprocedure);
  if encode(extensions.digest(previous, 'sha256'), 'hex')
      <> '224dcd2c499d03fb670ed221a5d934cac67aa2a5d23f579e75c0e41f51f9b198'
  then
    raise exception 'Canonical injury calculator differs from the reviewed definition';
  end if;
  execute replace(replace(previous,
    'reporting.urc_canonical_injury_sections_json_v1',
    'reporting.urc_canonical_injury_sections_json_v2'),
    $old$to_date(month ->> 'month', 'Mon YYYY')$old$,
    $new$case when month ->> 'month' ~ '^[0-9]{4}-[0-9]{2}$'
      then to_date(month ->> 'month', 'YYYY-MM')
      else to_date(month ->> 'month', 'Mon YYYY') end$new$);
end;
$$;
revoke all on function reporting.urc_canonical_injury_sections_json_v2(text, text)
from public, anon, authenticated, web_reader;

create function reporting.urc_2025_26_injury_to_illness_dashboard_v1(
  predecessor jsonb, target_team text default null
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, analysis, reporting, pg_temp as $$
  with calculated as materialized (
    select reporting.urc_canonical_injury_sections_json_v2('2025-26', target_team) as sections,
      reporting.diagnosis_family_rows_json_v1('2025-26', target_team) as families
  )
  select predecessor || (sections - array['method', 'headline', 'monthly'])
    || jsonb_build_object(
      'headline', (
        select jsonb_agg(old.item || (fresh.item - array['key','label','unit','formula']) order by old.ordinality)
        from jsonb_array_elements(predecessor -> 'headline') with ordinality old(item, ordinality)
        join jsonb_array_elements(sections -> 'headline') fresh(item)
          on fresh.item ->> 'key' = old.item ->> 'key'
      ),
      'monthly', (
        select jsonb_agg(fresh.item || jsonb_build_object(
          'overall_incidence_per_1000h', case
            when old.item ->> 'overall_incidence_per_1000h' is null then null
            else fresh.item -> 'overall_incidence_per_1000h' end,
          'incidence_per_1000h', case
            when old.item ->> 'incidence_per_1000h' is null then null
            else fresh.item -> 'incidence_per_1000h' end,
          'burden_per_1000h', case
            when old.item ->> 'burden_per_1000h' is null then null
            else fresh.item -> 'burden_per_1000h' end
        ) order by old.ordinality)
        from jsonb_array_elements(predecessor -> 'monthly') with ordinality old(item, ordinality)
        join jsonb_array_elements(sections -> 'monthly') fresh(item)
          on fresh.item ->> 'month' = old.item ->> 'month'
      ),
      'injury_profiles', reporting.replace_diagnosis_profiles_v1(
        sections -> 'injury_profiles', families
      ),
      'diagnosis_families', families,
      'illness_profiles', reporting.illness_profile_rows_json_v1('2025-26', target_team),
      'illness_summary', reporting.illness_summary_json_v1('2025-26', target_team),
      'severity_distribution', reporting.urc_2025_26_setting_severity_json_v1(target_team),
      'preliminary_monthly_rates', case when target_team is null
        then reporting.urc_2025_26_preliminary_monthly_rates_json_v1()
        else predecessor -> 'preliminary_monthly_rates' end
    )
  from calculated;
$$;
revoke all on function reporting.urc_2025_26_injury_to_illness_dashboard_v1(jsonb, text)
from public, anon, authenticated, web_reader;

-- The previous 32 team and two league snapshots remain unchanged and recoverable.
create materialized view reporting.diagnosis_family_team_dashboard_payloads_v3 as
select team_key, season,
  case when season = '2025-26' and team_key in ('dragons', 'ospreys', 'glasgow')
    then reporting.urc_2025_26_injury_to_illness_dashboard_v1(dashboard, team_key)
    else dashboard end as dashboard
from reporting.diagnosis_family_team_dashboard_payloads_v2;
create unique index diagnosis_family_team_dashboard_payloads_v3_key
on reporting.diagnosis_family_team_dashboard_payloads_v3(team_key, season);

create materialized view reporting.diagnosis_family_league_dashboard_payloads_v3 as
select season, case when season = '2025-26'
  then reporting.urc_2025_26_injury_to_illness_dashboard_v1(dashboard)
  else dashboard end as dashboard
from reporting.diagnosis_family_league_dashboard_payloads_v2;
create unique index diagnosis_family_league_dashboard_payloads_v3_key
on reporting.diagnosis_family_league_dashboard_payloads_v3(season);
revoke all on reporting.diagnosis_family_team_dashboard_payloads_v3,
  reporting.diagnosis_family_league_dashboard_payloads_v3
from public, anon, authenticated, web_reader;

-- Replace the reader input only. Existing columns, options and grants remain intact.
do $$
declare item record; source_name text; successor_name text;
begin
  for item in select * from audit.urc_2025_26_injury_to_illness_rollback_v1
    where object_name in ('reporting.latest_team_dashboard_v7', 'reporting.latest_league_dashboard_v7')
  loop
    source_name := case when item.object_name = 'reporting.latest_team_dashboard_v7'
      then 'reporting.diagnosis_family_team_dashboard_payloads_v2'
      else 'reporting.diagnosis_family_league_dashboard_payloads_v2' end;
    successor_name := replace(source_name, '_v2', '_v3');
    if strpos(item.definition, source_name) = 0 then
      raise exception 'Dashboard predecessor snapshot binding changed';
    end if;
    execute 'create or replace view ' || item.object_name || ' as ' ||
      replace(item.definition, split_part(source_name, '.', 2),
        split_part(successor_name, '.', 2));
  end loop;
end;
$$;

create or replace view reporting.latest_dashboard_cache_token_v2
with (security_invoker = false, security_barrier = true) as
select season, cache_token from reporting.latest_dashboard_cache_token_v1
where season <> '2025-26'
union all
select bundle.season, encode(extensions.digest(convert_to(
  bundle.release_id::text || ':' || payload.payload_sha256 ||
    ':urc_2025_26_injury_to_illness_2026_09_03_v1',
  'UTF8'), 'sha256'), 'hex')
from reporting.latest_approved_league_bundle_v6 bundle
join reporting.league_release_payloads_v6 payload on payload.release_id = bundle.release_id;

do $$
declare changed_sections text[] := array[
  'headline','monthly','body_locations','injury_types','injury_profiles',
  'injury_type_families','setting_split','setting_metrics','contact_distribution',
  'severity_distribution','diagnosis_families','illness_profiles','illness_summary',
  'preliminary_monthly_rates'
];
begin
  if (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1) <> 1521
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1 where is_time_loss) <> 915
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1 where not is_time_loss) <> 606
    or (select sum(days_lost) from analysis.urc_2025_26_canonical_injury_rows_v1 where is_time_loss) <> 20573
    or (select count(*) from analysis.urc_illness_profile_rows_v2 where season = '2025-26') <> 463
    or (select count(*) from analysis.urc_illness_profile_rows_v2 where season = '2025-26' and duration_known) <> 225
    or (select sum(days_lost) from analysis.urc_illness_profile_rows_v2 where season = '2025-26') <> 1019
    or exists (
      select 1 from analysis.urc_illness_profile_rows_v2 illness
      join analysis.urc_canonical_injury_rows_v1 injury using (season, team_key, source_row)
      where illness.season = '2025-26'
    )
    or (select count(*) from reporting.diagnosis_family_team_dashboard_payloads_v3) <> 32
    or (select count(*) from reporting.diagnosis_family_league_dashboard_payloads_v3) <> 2
    or exists (
      select 1 from reporting.diagnosis_family_team_dashboard_payloads_v3 successor
      join reporting.diagnosis_family_team_dashboard_payloads_v2 predecessor using (team_key, season)
      where successor.dashboard - changed_sections <> predecessor.dashboard - changed_sections
        or ((successor.season <> '2025-26' or successor.team_key not in ('dragons','ospreys','glasgow'))
          and successor.dashboard <> predecessor.dashboard)
    )
    or exists (
      select 1 from reporting.diagnosis_family_league_dashboard_payloads_v3 successor
      join reporting.diagnosis_family_league_dashboard_payloads_v2 predecessor using (season)
      where successor.dashboard - changed_sections <> predecessor.dashboard - changed_sections
        or (successor.season <> '2025-26' and successor.dashboard <> predecessor.dashboard)
    )
    or has_table_privilege('web_reader', 'audit.urc_2025_26_injury_to_illness_decisions_v1', 'select')
    or has_table_privilege('web_reader', 'analysis.urc_illness_profile_rows_v2', 'select')
    or has_table_privilege('web_reader', 'reporting.diagnosis_family_team_dashboard_payloads_v3', 'select')
    or has_table_privilege('web_reader', 'reporting.diagnosis_family_league_dashboard_payloads_v3', 'select')
    or has_function_privilege('web_reader', 'reporting.urc_2025_26_injury_to_illness_dashboard_v1(jsonb,text)', 'execute')
  then
    raise exception 'Injury-to-illness cohort, payload preservation or reader boundary failed';
  end if;
end;
$$;

commit;
