-- Accepted 20 July 2026 adjudications only: source-field correction evidence,
-- concussion-priority reporting, body x IOC tissue/pathology parent reporting,
-- and immutable dashboard-bundle successors. The V1 cohort and denominators
-- remain unchanged.

insert into audit.reason_codes (code, description) values
  ('source_field_adjudicated_correction', 'Human-approved correction overlaid on an immutable source field before deterministic re-derivation.'),
  ('duplicate_review_retain_distinct', 'Human-reviewed exposure pair retained because a substantive source field differs.'),
  ('reporting_classification_adjudication', 'Human-approved reporting classification rule bound to exact evidence.')
on conflict (code) do update set description = excluded.description;

create table audit.rule_adjudications (
  id uuid primary key default gen_random_uuid(),
  adjudication_ref text not null,
  rule_version text not null,
  decision jsonb not null check (jsonb_typeof(decision) = 'object'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  workbook_sha256 text not null check (workbook_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_manifest_sha256 text not null check (evidence_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  reviewer text not null,
  workbook_snapshot_locator text not null,
  migration_version text not null check (migration_version = '20260720150000'),
  migration_sha256 text not null check (migration_sha256 ~ '^[0-9a-f]{64}$'),
  rationale text not null,
  decided_at timestamptz not null default now(),
  unique (adjudication_ref, rule_version)
);

alter table audit.rule_adjudications enable row level security;

create function audit.reject_rule_adjudication_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'audit.rule_adjudications is immutable; insert a superseding version';
end;
$$;

revoke execute on function audit.reject_rule_adjudication_mutation() from public;

create trigger rule_adjudications_immutable
before update or delete on audit.rule_adjudications
for each row execute function audit.reject_rule_adjudication_mutation();

alter table reporting.league_release_context_v2
  add column classification_view_version text not null default 'v2'
    check (classification_view_version in ('v2', 'reporting_classification_2026-07-20_v1')),
  add column classification_evidence_sha256 text
    check (classification_evidence_sha256 is null or classification_evidence_sha256 ~ '^[0-9a-f]{64}$');

alter table reporting.league_release_context_v2
  add constraint league_release_context_v2_classification_evidence check (
    (classification_view_version = 'v2' and classification_evidence_sha256 is null)
    or
    (classification_view_version = 'reporting_classification_2026-07-20_v1'
      and classification_evidence_sha256 is not null)
  );

create view analysis.accepted_reporting_classification_rules_v3
with (security_invoker = true) as
select
  r.rule_version as classification_view_version,
  encode(digest(convert_to(jsonb_agg(jsonb_build_object(
    'adjudication_ref', r.adjudication_ref,
    'decision', r.decision,
    'evidence_sha256', r.evidence_sha256,
    'workbook_sha256', r.workbook_sha256,
    'evidence_manifest_sha256', r.evidence_manifest_sha256,
    'reviewer', r.reviewer,
    'workbook_snapshot_locator', r.workbook_snapshot_locator,
    'migration_version', r.migration_version,
    'migration_sha256', r.migration_sha256,
    'rationale', r.rationale
  ) order by r.adjudication_ref)::text, 'UTF8'), 'sha256'), 'hex')
    as classification_evidence_sha256
from audit.rule_adjudications r
where r.rule_version = 'reporting_classification_2026-07-20_v1'
  and r.adjudication_ref in ('IA-02', 'ACL-01')
  and r.reviewer = 'Abdel Babiker'
  and r.workbook_sha256 = 'b258bd9ad13d1fa6ddb58f99fec1f6cf1dfa559cfcd01fa8787931b53b484f1d'
  and r.evidence_manifest_sha256 = 'd3be9f4308f070951abc0e0f6fd2e33f4f8c670f3b514d1176dc0ebaf5cdbf7e'
  and (
    (r.adjudication_ref = 'IA-02'
      and r.evidence_sha256 = '4fce823f04bc3530bd58c63062879828455cb1faddd3af73a611cebbf8370181'
      and r.decision = '{"concussion_priority":true,"classification":"Concussion / head / brain_spinal_cord_injury","preserve_source_and_curated_values":true}'::jsonb)
    or
    (r.adjudication_ref = 'ACL-01'
      and r.evidence_sha256 = '217e9c08acf9320cc41b06187947789586ddb54dc2aeeabde76fe714dcd58e77'
      and r.decision = '{"reporting_parent":"body_location_x_tissue_pathology","example":"Knee · Joint sprain","specific_subtype_optional":true,"preserve_specific_evidence":true}'::jsonb)
  )
group by r.rule_version
having count(*) = 2
   and count(distinct r.workbook_sha256) = 1
   and count(distinct r.evidence_manifest_sha256) = 1;

create view analysis.injury_reporting_classification_v3
with (security_invoker = true) as
with evidence as (
  select
    c.*,
    sr.source_values,
    upper(trim(coalesce(
      nullif(sr.source_values ->> 'Orchard Code', ''),
      case when i.problem_type = 'injury' then sr.source_values ->> 'Illness Code' end,
      ''
    ))) as orchard_code,
    exists (
      select 1
      from jsonb_each_text(sr.source_values) e
      where (
          e.key in (
            'Description', 'Injury Tissue Type/s', 'Body Part',
            'Mechanism of Injury', 'Mechanism Notes', 'Treatment/Rehab',
            'Injury Immediate Action', 'Injury Status', 'Medical System'
          )
          or lower(e.key) ~ '(hia|concussion|head injury assessment|return.?to.?play|(^|[^a-z])rtp([^a-z]|$)|diagnos)'
        )
        and lower(trim(coalesce(e.value, ''))) ~
          '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
        and lower(trim(coalesce(e.value, ''))) !~
          '(no|not|negative( for)?|passed|clear(ed)?|ruled out|without|did not).{0,32}(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
        and lower(trim(coalesce(e.value, ''))) !~
          '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M).{0,32}(negative|passed|clear(ed)?|ruled out|not diagnosed)'
    ) as has_positive_concussion_text
  from analysis.injury_cohort_by_build_v2 c
  join curated.injuries i on i.id = c.injury_id
  join ingestion.source_rows sr on sr.id = i.source_row_id
), classified as (
  select
    e.*,
    (e.orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')
      or e.has_positive_concussion_text) as has_reliable_concussion_evidence
  from evidence e
)
select
  c.injury_id, c.curated_build_id, c.team_key, c.season, c.setting_code,
  c.is_time_loss, c.days_lost,
  case when c.has_reliable_concussion_evidence
    then 'concussion'
    when c.body_location_code = 'unknown' or c.injury_type_code = 'unknown'
    then 'unknown'
    else concat('compound__', c.body_location_code, '__', c.injury_type_code)
  end as diagnosis_code,
  case when c.has_reliable_concussion_evidence
    then 'Concussion'
    when c.body_location_code = 'unknown' or c.injury_type_code = 'unknown'
    then 'Unknown diagnosis'
    else concat(c.body_location_label, ' · ', c.injury_type_label)
  end as diagnosis_label,
  case when c.has_reliable_concussion_evidence
    then 'concussion'
    else null
  end as diagnosis_subtype,
  case when c.has_reliable_concussion_evidence
      and c.orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')
    then 'mapped_from_exact_orchard_concussion_code'
    when c.has_reliable_concussion_evidence
    then 'adjudicated_concussion_priority_from_explicit_text'
    else 'adjudicated_body_tissue_parent'
  end as diagnosis_origin,
  c.has_reliable_concussion_evidence
from classified c
cross join analysis.accepted_reporting_classification_rules_v3 accepted;

create view analysis.diagnosis_profiles_v3
with (security_invoker = true) as
with expanded as (
  select c.*, s.setting_code as profile_setting
  from analysis.injury_reporting_classification_v3 c
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = c.curated_build_id
   and m.team_key = c.team_key and m.season = c.season
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
), grouped as (
  select curated_build_id, team_key, season, diagnosis_code, diagnosis_label,
         profile_setting as setting_code,
         count(*) as time_loss_injuries, sum(days_lost) as days_lost
  from expanded
  group by curated_build_id, team_key, season, diagnosis_code, diagnosis_label, profile_setting
)
select
  g.curated_build_id, g.team_key, g.season,
  'diagnosis'::text as dimension, g.diagnosis_code as code,
  g.diagnosis_label as label, g.setting_code,
  g.time_loss_injuries, g.days_lost,
  case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours
    when 'training' then e.training_hours else null end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours
      when 'training' then e.training_hours else null end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours
      when 'training' then e.training_hours else null end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_v2 e
  on e.curated_build_id = g.curated_build_id
 and e.team_key = g.team_key and e.season = g.season;

create view analysis.league_diagnosis_profiles_v3
with (security_invoker = true) as
with expanded as (
  select c.*, s.setting_code as profile_setting
  from analysis.injury_reporting_classification_v3 c
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = c.curated_build_id
   and m.team_key = c.team_key and m.season = c.season
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
), grouped as (
  select season, diagnosis_code, diagnosis_label, profile_setting as setting_code,
         count(*) as time_loss_injuries, sum(days_lost) as days_lost
  from expanded
  group by season, diagnosis_code, diagnosis_label, profile_setting
), exposure as (
  select e.season, sum(e.total_hours) as total_hours, sum(e.match_hours) as match_hours,
         sum(e.training_hours) as training_hours
  from analysis.exposure_hours_by_build_v2 e
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = e.curated_build_id and m.team_key = e.team_key and m.season = e.season
  group by e.season
)
select
  g.season, 'diagnosis'::text as dimension, g.diagnosis_code as code,
  g.diagnosis_label as label, g.setting_code,
  g.time_loss_injuries, g.days_lost,
  case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours
    when 'training' then e.training_hours else null end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours
      when 'training' then e.training_hours else null end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code when 'all' then e.total_hours when 'match' then e.match_hours
      when 'training' then e.training_hours else null end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g join exposure e using (season);

create view analysis.team_dashboard_payload_adjudicated_v3
with (security_invoker = true) as
select
  base.team_key, base.season, base.team_release_id, base.curated_build_id,
  rules.classification_view_version, rules.classification_evidence_sha256,
  jsonb_set(base.dashboard, '{injury_profiles}',
    coalesce(base.dashboard -> 'injury_profiles', '[]'::jsonb) || coalesce(profile.docs, '[]'::jsonb))
    as dashboard
from analysis.team_dashboard_payload_v2 base
cross join analysis.accepted_reporting_classification_rules_v3 rules
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'dimension', v.dimension, 'code', v.code, 'label', v.label,
    'setting', v.setting_code, 'time_loss_injuries', v.time_loss_injuries,
    'days_lost', v.days_lost, 'exposure_hours', v.exposure_hours,
    'incidence_per_1000h', v.incidence_per_1000h,
    'burden_per_1000h', v.burden_per_1000h,
    'mean_severity_days', v.mean_severity_days
  ) order by v.setting_code, v.time_loss_injuries desc, v.days_lost desc, v.code) as docs
  from analysis.diagnosis_profiles_v3 v
  where v.curated_build_id = base.curated_build_id
    and v.team_key = base.team_key and v.season = base.season
) profile on true;

create view analysis.league_dashboard_payload_adjudicated_v3
with (security_invoker = true) as
select
  base.season, rules.classification_view_version, rules.classification_evidence_sha256,
  jsonb_set(base.dashboard, '{injury_profiles}',
    coalesce(base.dashboard -> 'injury_profiles', '[]'::jsonb) || coalesce(profile.docs, '[]'::jsonb))
    as dashboard
from analysis.league_dashboard_payload_v2 base
cross join analysis.accepted_reporting_classification_rules_v3 rules
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'dimension', v.dimension, 'code', v.code, 'label', v.label,
    'setting', v.setting_code, 'time_loss_injuries', v.time_loss_injuries,
    'days_lost', v.days_lost, 'exposure_hours', v.exposure_hours,
    'incidence_per_1000h', v.incidence_per_1000h,
    'burden_per_1000h', v.burden_per_1000h,
    'mean_severity_days', v.mean_severity_days
  ) order by v.setting_code, v.time_loss_injuries desc, v.days_lost desc, v.code) as docs
  from analysis.league_diagnosis_profiles_v3 v where v.season = base.season
) profile on true;

create view analysis.team_dashboard_release_candidates_v3
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id,
       'v2'::text as classification_view_version,
       null::text as classification_evidence_sha256, dashboard
from analysis.team_dashboard_payload_v2
union all
select team_key, season, team_release_id, curated_build_id,
       classification_view_version, classification_evidence_sha256, dashboard
from analysis.team_dashboard_payload_adjudicated_v3;

create view analysis.league_dashboard_release_candidates_v3
with (security_invoker = true) as
select season, 'v2'::text as classification_view_version,
       null::text as classification_evidence_sha256, dashboard
from analysis.league_dashboard_payload_v2
union all
select season, classification_view_version, classification_evidence_sha256, dashboard
from analysis.league_dashboard_payload_adjudicated_v3;

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
begin
  if not exists (
    select 1
    from reporting.league_release_context_v2 context
    join analysis.league_dashboard_release_candidates_v3 candidate
      on candidate.season = context.season
     and candidate.classification_view_version = context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.dashboard = new.dashboard_payload
    where context.release_id = new.release_id
  ) then
    raise exception 'league dashboard snapshot must equal its version-bound analytical candidate';
  end if;
  return new;
end;
$$;

create or replace function reporting.validate_team_dashboard_v2_candidates()
returns trigger language plpgsql as $$
begin
  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v3 candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.classification_view_version = context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its version-bound analytical candidate';
  end if;
  return null;
end;
$$;

revoke execute on function reporting.validate_league_dashboard_v2_candidate() from public;
revoke execute on function reporting.validate_team_dashboard_v2_candidates() from public;

comment on view analysis.injury_reporting_classification_v3 is
  'Accepted IA-02/ACL-01 reporting classification on the unchanged build-pinned V2 injury cohort.';
