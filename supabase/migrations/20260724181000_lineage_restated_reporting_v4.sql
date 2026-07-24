-- Restated reporting binds the reviewed 2024-25 master and ordered ledger to
-- an additive full-dashboard release path. Frozen reporting views remain
-- unchanged.

insert into audit.reason_codes (code, description) values
  (
    'league_dashboard_release_v4',
    'immutable 16-team league dashboard release from the restated 2024-25 master-plus-ledger lineage'
  )
on conflict (code) do nothing;

alter table audit.reporting_cohort_rule_adjudications_v3
  drop constraint reporting_cohort_rule_adjudications_v3_migration_version_check,
  add constraint reporting_cohort_rule_adjudications_v3_migration_version_check check (
    migration_version in ('20260720170000', '20260724181000')
  );

insert into analysis.reporting_season_windows_v3
  (cohort_view_version, season, season_start, season_end, decision_ref)
values
  (
    'lineage_2024-25_2026-07-24_v1', '2024-25',
    date '2024-07-01', date '2025-06-30', 'LINEAGE-01'
  );

insert into audit.reporting_cohort_rule_adjudications_v3
  (adjudication_ref, cohort_view_version, season, decision, evidence_sha256,
   evidence_locator, reviewer, migration_version, decided_at)
values (
  'LINEAGE-01', 'lineage_2024-25_2026-07-24_v1', '2024-25',
  '{
    "classification_rule":"accepted reporting_classification_2026-07-22_v2 logic applied to the restated cohort with final canonical values overriding source values",
    "days_lost_rule":"coalesce(parsed Days Injured, 0); unparsed or blank is censored",
    "exposure_rule":"unchanged analysis.exposure_hours_by_build_season_bound_v3",
    "inclusion_rule":"master rows with blank Exclusion Reason and no ledger removal entry",
    "ioc_bucket_source":"curated.injuries codes via the verified lineage.master_source_bridge",
    "problem_type_filter":"final Problem type equals Injury",
    "setting_rule":"final Occasion category Match to match, Training to training, else unknown",
    "time_loss_rule":"final Days Injured parsed as integer greater than zero",
    "undated_rule":"season_attributed; excluded only from monthly series",
    "value_authority":"lineage master rows plus ordered ledger final values",
    "window_rule":"dated injuries must fall inside the registered season window"
  }'::jsonb,
  '8ccba2bba66442fa141c100132f7e31762ae371871b6450e2b7146034ddd5f93',
  'docs/evidence/lineage_cohort_2024-25.json',
  'Abdel Babiker', '20260724181000',
  timestamptz '2026-07-24 00:00:00+00'
);

create view analysis.accepted_lineage_cohort_rules_v1
with (security_invoker = true) as
select r.cohort_view_version, r.season,
  encode(digest(convert_to(jsonb_agg(jsonb_build_object(
    'adjudication_ref', r.adjudication_ref, 'decision', r.decision,
    'evidence_sha256', r.evidence_sha256, 'evidence_locator', r.evidence_locator,
    'reviewer', r.reviewer,
    'migration_version', r.migration_version
  ) order by r.adjudication_ref)::text, 'UTF8'), 'sha256'), 'hex') as cohort_evidence_sha256
from audit.reporting_cohort_rule_adjudications_v3 r
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = r.cohort_view_version and w.season = r.season
  and w.decision_ref = r.adjudication_ref
where r.adjudication_ref = 'LINEAGE-01'
  and r.cohort_view_version = 'lineage_2024-25_2026-07-24_v1'
  and r.reviewer = 'Abdel Babiker'
  and r.evidence_sha256 = '8ccba2bba66442fa141c100132f7e31762ae371871b6450e2b7146034ddd5f93'
  and r.evidence_locator = 'docs/evidence/lineage_cohort_2024-25.json'
  and r.migration_version = '20260724181000'
  and r.decision = '{
    "classification_rule":"accepted reporting_classification_2026-07-22_v2 logic applied to the restated cohort with final canonical values overriding source values",
    "days_lost_rule":"coalesce(parsed Days Injured, 0); unparsed or blank is censored",
    "exposure_rule":"unchanged analysis.exposure_hours_by_build_season_bound_v3",
    "inclusion_rule":"master rows with blank Exclusion Reason and no ledger removal entry",
    "ioc_bucket_source":"curated.injuries codes via the verified lineage.master_source_bridge",
    "problem_type_filter":"final Problem type equals Injury",
    "setting_rule":"final Occasion category Match to match, Training to training, else unknown",
    "time_loss_rule":"final Days Injured parsed as integer greater than zero",
    "undated_rule":"season_attributed; excluded only from monthly series",
    "value_authority":"lineage master rows plus ordered ledger final values",
    "window_rule":"dated injuries must fall inside the registered season window"
  }'::jsonb
group by r.cohort_view_version, r.season
having count(*) = 1;

-- The loader proves old-value guards before data enters lineage. Reporting
-- therefore applies only the final ordered override per field.
create view analysis.lineage_included_rows_v1
with (security_invoker = true) as
select m.season, m.source_row, m.team,
  m.row_values || coalesce(overrides.final_overrides, '{}'::jsonb) as final_values
from lineage.master_rows m
left join lateral (
  select jsonb_object_agg(last_entry.field, coalesce(last_entry.new_value, ''))
    as final_overrides
  from (
    select distinct on (e.field) e.field, e.new_value
    from lineage.ledger_entries e
    where e.season = m.season
      and e.source_row = m.source_row
      and not e.is_removal
    order by e.field, e.step_order desc, e.entry_index desc
  ) last_entry
) overrides on true
where not m.excluded
  and not exists (
    select 1
    from lineage.ledger_entries removal
    where removal.season = m.season
      and removal.source_row = m.source_row
      and removal.is_removal
  );

create view analysis.lineage_injury_cohort_v1
with (security_invoker = true) as
select
  i.id as injury_id, b.curated_build_id, b.team_key, r.season,
  b.source_row_id, r.source_row, parsed.date_injured,
  coalesce(parsed.parsed_days, 0)::numeric as days_lost,
  coalesce(parsed.parsed_days, 0) > 0 as is_time_loss,
  case trim(r.final_values ->> 'Occasion category')
    when 'Match' then 'match'
    when 'Training' then 'training'
    else 'unknown'
  end as setting_code,
  coalesce(i.body_location, 'unknown') as body_location_code,
  coalesce(bl.label, 'Unknown') as body_location_label,
  coalesce(i.injury_type, 'unknown') as injury_type_code,
  coalesce(it.label, 'Unknown') as injury_type_label,
  case
    when parsed.parsed_days is null then 'unknown_or_censored'
    when parsed.parsed_days = 0 then 'zero_days_medical_attention_only'
    when parsed.parsed_days = 1 then 'one_day'
    when parsed.parsed_days between 2 and 3 then 'two_to_three_days'
    when parsed.parsed_days between 4 and 7 then 'four_to_seven_days'
    when parsed.parsed_days between 8 and 28 then 'eight_to_twenty_eight_days'
    when parsed.parsed_days > 28 then 'greater_than_twenty_eight_days'
    else 'unknown_or_censored'
  end as severity_code,
  case
    when parsed.parsed_days is null then 'Unknown or censored'
    when parsed.parsed_days = 0 then 'Medical attention'
    when parsed.parsed_days = 1 then '1 day'
    when parsed.parsed_days between 2 and 3 then '2-3 days'
    when parsed.parsed_days between 4 and 7 then '4-7 days'
    when parsed.parsed_days between 8 and 28 then '8-28 days'
    when parsed.parsed_days > 28 then '>28 days'
    else 'Unknown or censored'
  end as severity_label,
  parsed.date_injured is null as is_undated
from analysis.lineage_included_rows_v1 r
join lineage.master_source_bridge b using (season, source_row)
join curated.injuries i on i.id = b.injury_id
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'lineage_2024-25_2026-07-24_v1'
 and w.season = r.season
join analysis.accepted_lineage_cohort_rules_v1 rule
  on rule.cohort_view_version = w.cohort_view_version
 and rule.season = w.season
left join curated.code_lists bl
  on bl.list_name = 'body_location'
 and bl.code = coalesce(i.body_location, 'unknown')
left join curated.code_lists it
  on it.list_name = 'injury_type'
 and it.code = coalesce(i.injury_type, 'unknown')
cross join lateral (
  select
    case
      when trim(r.final_values ->> 'Date Injured') ~ '^\d{2}/\d{2}/\d{4}$'
        then to_date(trim(r.final_values ->> 'Date Injured'), 'DD/MM/YYYY')
      else null
    end as date_injured,
    case
      when trim(r.final_values ->> 'Days Injured') ~ '^\d+(\.0+)?$'
        then trim(r.final_values ->> 'Days Injured')::numeric
      else null
    end as parsed_days
) parsed
where trim(r.final_values ->> 'Problem type') = 'Injury'
  and (
    parsed.date_injured is null
    or parsed.date_injured between w.season_start and w.season_end
  );

-- Stage A preserves the accepted concussion and compound-diagnosis logic,
-- but the reviewed final values take precedence over raw source evidence.
create view analysis.lineage_reporting_classification_v1
with (security_invoker = true) as
with stage_a_evidence as (
  select c.*, sr.source_values || r.final_values as effective_evidence
  from analysis.lineage_injury_cohort_v1 c
  join analysis.lineage_included_rows_v1 r
    using (season, source_row)
  join ingestion.source_rows sr on sr.id = c.source_row_id
), stage_a as (
  select e.*,
    upper(trim(coalesce(
      nullif(e.effective_evidence ->> 'Orchard Code', ''),
      e.effective_evidence ->> 'Illness Code',
      ''
    ))) as orchard_code,
    exists (
      select 1
      from jsonb_each_text(e.effective_evidence) item
      where (
        item.key in (
          'Description', 'Injury Tissue Type/s', 'Body Part',
          'Mechanism of Injury', 'Mechanism Notes', 'Treatment/Rehab',
          'Injury Immediate Action', 'Injury Status', 'Medical System'
        )
        or lower(item.key) ~
          '(hia|concussion|head injury assessment|return.?to.?play|(^|[^a-z])rtp([^a-z]|$)|diagnos)'
      )
        and lower(trim(coalesce(item.value, ''))) ~
          '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
        and lower(trim(coalesce(item.value, ''))) !~
          '(no|not|negative( for)?|passed|clear(ed)?|ruled out|without|did not).{0,32}(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
        and lower(trim(coalesce(item.value, ''))) !~
          '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M).{0,32}(negative|passed|clear(ed)?|ruled out|not diagnosed)'
    ) as has_positive_concussion_text
  from stage_a_evidence e
), predecessor as (
  select e.*,
    case
      when e.orchard_code in (
        'HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA',
        'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX'
      ) or e.has_positive_concussion_text then 'concussion'
      when e.body_location_code = 'unknown'
        or e.injury_type_code = 'unknown' then 'unknown'
      else concat(
        'compound__', e.body_location_code, '__', e.injury_type_code
      )
    end as predecessor_diagnosis_code,
    case
      when e.orchard_code in (
        'HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA',
        'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX'
      ) or e.has_positive_concussion_text then 'Concussion'
      when e.body_location_code = 'unknown'
        or e.injury_type_code = 'unknown' then 'Unknown diagnosis'
      else concat(e.body_location_label, ' · ', e.injury_type_label)
    end as predecessor_diagnosis_label
  from stage_a e
), evidence as (
  select
    p.*,
    lower(trim(concat_ws(' ',
      p.effective_evidence ->> 'Description',
      p.effective_evidence ->> 'Injury Tissue Type/s',
      p.effective_evidence ->> 'Body Part'
    ))) as clinical_evidence,
    lower(trim(coalesce(
      p.effective_evidence ->> 'Injury Tissue Type/s', ''
    ))) as source_tissue_evidence
  from predecessor p
  cross join analysis.accepted_reporting_classification_rules_v4 accepted
), body_candidates as (
  select e.injury_id, m.mapped_body_location_code as body_code,
    'exact_osiics'::text as origin
  from evidence e
  join analysis.osiics_exact_ioc_mapping_v1 m
    on m.source_code = e.orchard_code
  where e.predecessor_diagnosis_code = 'unknown'
  union all
  select e.injury_id, x.body_code, 'strict_osiics_prefix'
  from evidence e
  cross join lateral (values
    ('H','head'),('N','neck'),('S','shoulder'),('U','upper_arm'),
    ('E','elbow'),('R','forearm'),('W','wrist'),('P','hand'),
    ('C','chest'),('D','thoracic_spine'),('L','lumbosacral'),
    ('O','abdomen'),('G','hip_groin'),('T','thigh'),('K','knee'),
    ('Q','lower_leg'),('A','ankle'),('F','foot'),('Z','unspecified'),
    ('X','multiple')
  ) x(prefix, body_code)
  where e.predecessor_diagnosis_code = 'unknown'
    and e.orchard_code ~ '^[HNSUERWPCDLOGTKQAFZX][A-Z]'
    and left(e.orchard_code, 1) = x.prefix
  union all
  select e.injury_id, x.body_code, 'explicit_text'
  from evidence e
  cross join lateral (values
    ('head', e.clinical_evidence ~ '(head injury|facial|skull|jaw|concuss)'),
    ('neck', e.clinical_evidence ~ '\m(neck|cervical)\M'),
    ('shoulder', e.clinical_evidence ~
      '(\mshoulder\M|acromioclavicular|\mac joint\M|\ma/c joint\M|\mclavicle\M|scapul)'),
    ('upper_arm', e.clinical_evidence ~ '(\mupper arm\M|humerus|humeral)'),
    ('elbow', e.clinical_evidence ~ '\melbow\M'),
    ('forearm', e.clinical_evidence ~ '\mforearm\M'),
    ('wrist', e.clinical_evidence ~ '(\mwrist\M|carpal|scaphoid)'),
    ('hand', e.clinical_evidence ~
      '(\mhand\M|\mfinger\M|\mthumb\M|metacarp)'),
    ('chest', e.clinical_evidence ~
      '(\mchest\M|\mrib(s)?\M|sternum|sternal|pectoral)'),
    ('thoracic_spine', e.clinical_evidence ~
      '(thoracic spine|costovertebral)'),
    ('lumbosacral', e.clinical_evidence ~
      '(lumbar|lumbosacral|\msacrum\M|\msacral\M|\mcoccyx\M|\mbuttock\M)'),
    ('abdomen', e.clinical_evidence ~ '(\mabdomen\M|abdominal)'),
    ('hip_groin', e.clinical_evidence ~
      '(\mhip\M|\mgroin\M|inguinal|\madductor\M)'),
    ('thigh', e.clinical_evidence ~
      '(\mthigh\M|hamstring|biceps femoris|semitend|semimembran|quadriceps|rectus femoris|\mvastus\M)'),
    ('knee', e.clinical_evidence ~
      '(\mknee\M|patell|menisc|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|cruciate)'),
    ('lower_leg', e.clinical_evidence ~
      '(\mlower leg\M|\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M|achilles|\mshin\M)'),
    ('ankle', e.clinical_evidence ~
      '(\mankle\M|syndesmo|high ankle sprain)'),
    ('foot', e.clinical_evidence ~
      '(\mfoot\M|\mtoe\M|metatars|lisfranc|calcane|plantar)')
  ) x(body_code, matches)
  where e.predecessor_diagnosis_code = 'unknown' and x.matches
  union all
  select e.injury_id, m.mapped_body_location_code,
    'adjudicated_multi_type_osiics'
  from evidence e
  join analysis.osiics_multi_type_diagnosis_v1 m
    on m.source_code = e.orchard_code
  where e.predecessor_diagnosis_code = 'unknown'
), body_summary as (
  select injury_id, count(distinct body_code)::int as candidate_count,
    min(body_code) as sole_candidate,
    bool_or(origin in ('exact_osiics','strict_osiics_prefix')) as has_code_origin
  from body_candidates
  group by injury_id
), body_resolved as (
  select e.*,
    case
      when e.body_location_code <> 'unknown' then e.body_location_code
      when coalesce(b.candidate_count, 0) = 1 then b.sole_candidate
      else 'unknown'
    end as effective_body_location_code,
    case
      when e.body_location_code <> 'unknown' then 'predecessor_curated'
      when coalesce(b.candidate_count, 0) = 1 and b.has_code_origin
        then 'mapped_from_osiics_body'
      when coalesce(b.candidate_count, 0) = 1
        then 'inferred_from_explicit_body_text'
      else 'remaining_unknown'
    end as body_location_origin,
    coalesce(b.candidate_count, 0) as body_evidence_candidate_count,
    b.sole_candidate as sole_body_evidence_candidate
  from evidence e
  left join body_summary b using (injury_id)
), type_candidates as (
  select e.injury_id, m.mapped_injury_type_code as type_code,
    'exact_osiics'::text as origin
  from body_resolved e
  join analysis.osiics_exact_ioc_mapping_v1 m
    on m.source_code = e.orchard_code
  where e.predecessor_diagnosis_code = 'unknown'
    and e.injury_type_code = 'unknown'
    and m.mapped_body_location_code = e.effective_body_location_code
  union all
  select e.injury_id, x.type_code, 'explicit_text'
  from body_resolved e
  cross join lateral (values
    ('brain_spinal_cord_injury',
      e.clinical_evidence ~ '(concuss(ion|ed)?|brain injury|spinal cord injury)'),
    ('tendon_rupture',
      e.clinical_evidence ~
        '(tendon|achilles).{0,18}(ruptur|complete tear)|(ruptur|complete tear).{0,18}(tendon|achilles)'),
    ('bone_stress_injury',
      e.clinical_evidence ~
        '(stress fracture|bone stress|stress reaction|shin splints)'),
    ('bone_contusion',
      e.clinical_evidence ~ '(bone contusion|bony contusion|bone bruise)'),
    ('fracture',
      e.clinical_evidence ~ '(fractur|broken bone)'
      and e.clinical_evidence !~
        '(stress fracture|bone stress|stress reaction)'),
    ('peripheral_nerve_injury',
      e.clinical_evidence ~
        '(\mnerve\M|brachial plexus|burner/stinger|\mstinger\M)'),
    ('cartilage_injury',
      e.clinical_evidence ~ '(osteochondral|\mcartilage\M|labral|labrum|menisc)'),
    ('arthritis',
      e.clinical_evidence ~ '(osteoarthritis|\marthritis\M)'),
    ('tendinopathy',
      e.clinical_evidence ~
        '(tendinopathy|tendinosis|tendon injury|tendon strain|plantar fasci)'
      and e.clinical_evidence !~ '(ruptur|complete tear)'),
    ('bursitis', e.clinical_evidence ~ '\mbursitis\M'),
    ('synovitis_capsulitis',
      e.clinical_evidence ~
        '(\msynovitis\M|\mcapsulitis\M|\mimpingement\M)'
      and e.clinical_evidence !~ '\mbursitis\M'),
    ('chronic_instability',
      e.clinical_evidence ~ '(chronic instability|recurrent instability)'),
    ('joint_sprain',
      e.clinical_evidence ~
        '(\msprain(ed)?\M|\mligament\M|disloc|sublux|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|syndesmo|lisfranc)'),
    ('muscle_contusion',
      e.clinical_evidence ~
        '(muscle contusion|muscle haematoma|intramuscular haematoma)'),
    ('laceration', e.clinical_evidence ~ '\mlacerat(ion|ed)\M'),
    ('abrasion', e.clinical_evidence ~ '\mabrasion\M'),
    ('contusion_superficial',
      e.clinical_evidence ~
        '(\mcontusion\M|haematoma|hematoma|\mbruis(e|ed|ing)\M|dead leg)'
      and e.clinical_evidence !~
        '(muscle contusion|muscle haematoma|intramuscular haematoma|bone contusion|bony contusion|bone bruise)'),
    ('muscle_injury', (
      e.source_tissue_evidence ~
        '(^|[,;/])\s*muscle(s| injury)?\s*($|[,;/])'
      or e.clinical_evidence ~
        '(muscle (strain|tear|rupture|injury)|((hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M).{0,24}(strain|tear|ruptur|injur))|((strain|tear|ruptur|injur).{0,24}(hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M)))'
    ) and e.clinical_evidence !~
      '(muscle contusion|muscle haematoma|intramuscular haematoma)'
      and e.orchard_code <> 'QPS')
  ) x(type_code, matches)
  where e.predecessor_diagnosis_code = 'unknown'
    and e.injury_type_code = 'unknown'
    and x.matches
    and (
      e.body_evidence_candidate_count = 0
      or (
        e.body_evidence_candidate_count = 1
        and e.sole_body_evidence_candidate = e.effective_body_location_code
      )
    )
), type_summary as (
  select injury_id, count(distinct type_code)::int as candidate_count,
    min(type_code) as sole_candidate,
    bool_or(origin = 'exact_osiics') as has_exact_code_origin,
    bool_or(origin = 'explicit_text') as has_text_origin
  from type_candidates
  group by injury_id
), resolved as (
  select b.*,
    case
      when b.injury_type_code <> 'unknown' then b.injury_type_code
      when multi.source_code is not null
        and multi.mapped_body_location_code = b.effective_body_location_code
        then multi.analysis_primary_type_code
      when coalesce(t.candidate_count, 0) = 1 then t.sole_candidate
      else 'unknown'
    end as effective_injury_type_code,
    case
      when b.injury_type_code <> 'unknown' then 'predecessor_curated'
      when multi.source_code is not null
        and multi.mapped_body_location_code = b.effective_body_location_code
        then 'adjudicated_multi_type_osiics_diagnosis'
      when coalesce(t.candidate_count, 0) = 1 and t.has_exact_code_origin
        then 'mapped_from_exact_osiics_code'
      when coalesce(t.candidate_count, 0) = 1
        then 'inferred_from_unique_explicit_type_text'
      else 'remaining_unknown'
    end as injury_type_origin,
    case
      when multi.source_code is not null
        and multi.mapped_body_location_code = b.effective_body_location_code
        then 2
      else coalesce(t.candidate_count, 0)
    end as injury_type_candidate_count,
    multi.candidate_injury_types,
    multi.diagnosis_code as multi_diagnosis_code,
    multi.diagnosis_label as multi_diagnosis_label
  from body_resolved b
  left join type_summary t using (injury_id)
  left join analysis.osiics_multi_type_diagnosis_v1 multi
    on multi.source_code = b.orchard_code
   and b.predecessor_diagnosis_code = 'unknown'
   and b.injury_type_code = 'unknown'
)
select
  r.injury_id, r.curated_build_id, r.team_key, r.season, r.setting_code,
  r.is_time_loss, r.days_lost,
  case
    when r.predecessor_diagnosis_code <> 'unknown'
      then r.predecessor_diagnosis_code
    when r.multi_diagnosis_code is not null then r.multi_diagnosis_code
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      then concat(
        'compound__', r.effective_body_location_code,
        '__', r.effective_injury_type_code
      )
    else 'unknown'
  end as diagnosis_code,
  case
    when r.predecessor_diagnosis_code <> 'unknown'
      then r.predecessor_diagnosis_label
    when r.multi_diagnosis_label is not null then r.multi_diagnosis_label
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      then concat(bl.label, ' · ', it.label)
    else 'Unknown diagnosis'
  end as diagnosis_label,
  r.body_location_code as original_body_location_code,
  r.injury_type_code as original_injury_type_code,
  r.effective_body_location_code,
  r.effective_injury_type_code,
  r.body_location_origin,
  r.injury_type_origin,
  case
    when r.predecessor_diagnosis_code <> 'unknown'
      then 'predecessor_reporting_classification'
    when r.multi_diagnosis_code is not null
      then 'adjudicated_multi_type_osiics_diagnosis'
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      and r.injury_type_origin = 'mapped_from_exact_osiics_code'
      then 'mapped_from_exact_osiics_code'
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      then 'inferred_from_unique_explicit_body_and_type_text'
    else 'remaining_unknown'
  end as diagnosis_origin,
  r.injury_type_candidate_count,
  r.candidate_injury_types
from resolved r
left join curated.code_lists bl
  on bl.list_name = 'body_location'
 and bl.code = r.effective_body_location_code
left join curated.code_lists it
  on it.list_name = 'injury_type'
 and it.code = r.effective_injury_type_code;

create view analysis.lineage_team_summary_v1
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season, count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days
from analysis.lineage_injury_cohort_v1 c
group by c.curated_build_id, c.team_key, c.season;

create view analysis.lineage_setting_split_v1
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, c.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.lineage_injury_cohort_v1 c
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, c.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(
      g.time_loss_injuries, e.match_hours
    )
    when 'training' then analysis.rate_per_1000_v1(
      g.time_loss_injuries, e.training_hours
    )
    else null
  end as incidence_per_1000h,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(g.days_lost, e.match_hours)
    when 'training' then analysis.rate_per_1000_v1(
      g.days_lost, e.training_hours
    )
    else null
  end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_season_bound_v3 e
  using (curated_build_id, team_key, season);

create view analysis.lineage_injury_profiles_v1
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.lineage_injury_cohort_v1 c
  cross join lateral (values
    ('body_location'::text, c.body_location_code, c.body_location_label),
    ('injury_type'::text, c.injury_type_code, c.injury_type_label),
    (
      'injury_profile'::text,
      c.body_location_code || '__' || c.injury_type_code,
      c.body_location_label || ' · ' || c.injury_type_label
    )
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(
    g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end
  ) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_season_bound_v3 e
  using (curated_build_id, team_key, season);

create view analysis.lineage_effective_injury_profiles_v1
with (security_invoker = true) as
with labelled as (
  select c.*,
    coalesce(
      bl.label,
      initcap(replace(c.effective_body_location_code, '_', ' '))
    ) as body_label,
    coalesce(
      it.label,
      initcap(replace(c.effective_injury_type_code, '_', ' '))
    ) as type_label
  from analysis.lineage_reporting_classification_v1 c
  left join curated.code_lists bl
    on bl.list_name = 'body_location'
   and bl.code = c.effective_body_location_code
  left join curated.code_lists it
    on it.list_name = 'injury_type'
   and it.code = c.effective_injury_type_code
), grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from labelled c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  cross join lateral (values
    (
      'body_location'::text,
      c.effective_body_location_code,
      c.body_label
    ),
    (
      'injury_type'::text,
      c.effective_injury_type_code,
      c.type_label
    ),
    (
      'injury_profile'::text,
      c.effective_body_location_code || '__' ||
        c.effective_injury_type_code,
      c.body_label || ' · ' || c.type_label
    )
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(
    g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end
  ) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_season_bound_v3 e
  using (curated_build_id, team_key, season);

create view analysis.lineage_diagnosis_profiles_v1
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code as code, c.diagnosis_label as label,
    s.setting_code, count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.lineage_reporting_classification_v1 c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code, c.diagnosis_label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(
    g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end
  ) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_season_bound_v3 e
  using (curated_build_id, team_key, season);

create view analysis.lineage_monthly_v1
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season,
    date_trunc(
      'month', coalesce(e.session_date, e.week_start_date)
    )::date as month_start,
    sum(e.minutes_clean) / 60 as exposure_hours,
    sum(e.distance_m_clean) / 1000 as distance_km
  from curated.exposure e
  join analysis.reporting_season_windows_v3 w
    on w.cohort_view_version = 'season_bound_2026-07-20_v1'
   and w.season = e.season
  where e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date)
      between w.season_start and w.season_end
  group by e.curated_build_id, e.team_key, e.season,
    date_trunc('month', coalesce(e.session_date, e.week_start_date))
), injuries as (
  select curated_build_id, team_key, season,
    date_trunc('month', date_injured)::date as month_start,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from analysis.lineage_injury_cohort_v1
  where date_injured is not null
  group by curated_build_id, team_key, season,
    date_trunc('month', date_injured)
), months as (
  select curated_build_id, team_key, season, month_start from exposure
  union
  select curated_build_id, team_key, season, month_start from injuries
)
select m.curated_build_id, m.team_key, m.season, m.month_start,
  to_char(m.month_start, 'Mon YYYY') as month_label,
  coalesce(e.exposure_hours, 0) as exposure_hours,
  coalesce(e.distance_km, 0) as distance_km,
  coalesce(i.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(i.days_lost, 0) as days_lost,
  analysis.rate_per_1000_v1(
    coalesce(i.time_loss_injuries, 0), coalesce(e.exposure_hours, 0)
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    coalesce(i.days_lost, 0), coalesce(e.exposure_hours, 0)
  ) as burden_per_1000h
from months m
left join exposure e
  using (curated_build_id, team_key, season, month_start)
left join injuries i
  using (curated_build_id, team_key, season, month_start);

create view analysis.lineage_severity_distribution_v1
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  case c.severity_code
    when 'zero_days_medical_attention_only' then 0
    when 'one_day' then 1
    when 'two_to_three_days' then 2
    when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4
    when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.lineage_injury_cohort_v1 c
group by c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label;

create view analysis.lineage_league_summary_v1
with (security_invoker = true) as
with cohort as (
  select c.*
  from analysis.lineage_injury_cohort_v1 c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
), exposure as (
  select e.season, sum(e.total_hours) as exposure_hours,
    sum(e.match_hours) as match_exposure_hours,
    sum(e.training_hours) as training_exposure_hours
  from analysis.exposure_hours_by_build_season_bound_v3 e
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by e.season
)
select c.season, count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days,
  e.exposure_hours, e.match_exposure_hours, e.training_exposure_hours
from cohort c
join exposure e using (season)
group by c.season, e.exposure_hours,
  e.match_exposure_hours, e.training_exposure_hours;

create view analysis.lineage_league_setting_split_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.lineage_setting_split_v1 x
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by x.season, x.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(
      g.time_loss_injuries, h.match_exposure_hours
    )
    when 'training' then analysis.rate_per_1000_v1(
      g.time_loss_injuries, h.training_exposure_hours
    )
    else null
  end as incidence_per_1000h,
  case g.setting_code
    when 'match' then analysis.rate_per_1000_v1(
      g.days_lost, h.match_exposure_hours
    )
    when 'training' then analysis.rate_per_1000_v1(
      g.days_lost, h.training_exposure_hours
    )
    else null
  end as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.lineage_league_summary_v1 h using (season);

create view analysis.lineage_league_profiles_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.lineage_injury_profiles_v1 x
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(
    g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end
  ) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.lineage_league_summary_v1 h using (season);

create view analysis.lineage_league_effective_injury_profiles_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.lineage_effective_injury_profiles_v1 x
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(
    g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end
  ) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.lineage_league_summary_v1 h using (season);

create view analysis.lineage_league_diagnosis_profiles_v1
with (security_invoker = true) as
with grouped as (
  select x.season, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.lineage_diagnosis_profiles_v1 x
  group by x.season, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(
    g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end
  ) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.lineage_league_summary_v1 h using (season);

create view analysis.lineage_league_monthly_v1
with (security_invoker = true) as
select x.season, x.month_start, x.month_label,
  sum(x.exposure_hours) as exposure_hours,
  sum(x.distance_km) as distance_km,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  analysis.rate_per_1000_v1(
    sum(x.time_loss_injuries), sum(x.exposure_hours)
  ) as incidence_per_1000h,
  analysis.rate_per_1000_v1(
    sum(x.days_lost), sum(x.exposure_hours)
  ) as burden_per_1000h
from analysis.lineage_monthly_v1 x
join analysis.league_member_releases_v2 m
  using (curated_build_id, team_key, season)
group by x.season, x.month_start, x.month_label;

create view analysis.lineage_league_severity_distribution_v1
with (security_invoker = true) as
select x.season, x.severity_code, x.severity_label,
  sum(x.recorded_injuries) as recorded_injuries,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  min(x.band_order) as band_order
from analysis.lineage_severity_distribution_v1 x
join analysis.league_member_releases_v2 m
  using (curated_build_id, team_key, season)
group by x.season, x.severity_code, x.severity_label;

create view analysis.team_dashboard_payload_lineage_v1
with (security_invoker = true) as
with body as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from analysis.lineage_effective_injury_profiles_v1 p
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), types as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.lineage_effective_injury_profiles_v1 p
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), profile_rows as (
  select p.curated_build_id, p.team_key, p.season, p.dimension,
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from analysis.lineage_effective_injury_profiles_v1 p
  union all
  select p.curated_build_id, p.team_key, p.season, 'diagnosis',
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from analysis.lineage_diagnosis_profiles_v1 p
), profiles as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code
    ) as docs
  from profile_rows p
  group by p.curated_build_id, p.team_key, p.season
)
select m.team_key, m.season, m.team_release_id, m.curated_build_id,
  rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version, cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', m.generated_at,
    'team', d.team,
    'season', m.season,
    'analysis_window', jsonb_build_object(
      'start', w.season_start,
      'end', w.season_end,
      'basis', 'Registered season window; no team exposure-window restriction.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.',
      'Match exposure = registered fixtures in the season window × 15 players × 80 minutes / 60 per team.',
      'Training exposure = included curated exposure in the season window minus match exposure.',
      'IOC-aligned body-location and tissue/pathology categories use the accepted mappings.',
      'Injury rows and values are restated from the reviewed 2024-25 master workbook and its ordered decision ledger.'
    ),
    'coverage',
      (coalesce(d.coverage, '{}'::jsonb) - 'injury_cohort_filters')
      || jsonb_build_object(
        'hours', e.total_hours,
        'match_hours', e.match_hours,
        'training_hours', e.training_hours,
        'exposure_grain', e.exposure_grain,
        'included_exposure_status', 'included',
        'analysis_window_start', w.season_start,
        'analysis_window_end', w.season_end
      ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', s.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in registered season window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', s.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(
          s.time_loss_injuries, e.total_hours
        ),
        'unit', 'per 1,000 player-hours',
        'numerator', s.time_loss_injuries,
        'denominator', e.total_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', s.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', s.days_lost, 'denominator', s.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', s.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(s.days_lost, e.total_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', s.days_lost, 'denominator', e.total_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
          when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.lineage_setting_split_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
          when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.lineage_setting_split_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from analysis.lineage_monthly_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from analysis.lineage_severity_distribution_v1 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'prior_season', d.prior_season,
    'limitations', jsonb_build_array(
      'The registered season window, rather than team-specific exposure coverage, defines both numerator and denominator eligibility.',
      'Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.',
      'Unknown-setting injuries are included in overall metrics but have no match/training rate.',
      'Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.',
      'Superseded database-side injury cleaning is retired; the reviewed master-plus-ledger lineage is the authoritative injury record.'
    )
  ) as dashboard
from analysis.league_member_releases_v2 m
join reporting.latest_team_dashboard d
  on d.release_id = m.team_release_id
 and d.team_key = m.team_key
 and d.season = m.season
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'lineage_2024-25_2026-07-24_v1'
 and w.season = m.season
join analysis.accepted_lineage_cohort_rules_v1 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
join analysis.lineage_team_summary_v1 s
  on s.curated_build_id = m.curated_build_id
 and s.team_key = m.team_key
 and s.season = m.season
join analysis.exposure_hours_by_build_season_bound_v3 e
  on e.curated_build_id = m.curated_build_id
 and e.team_key = m.team_key
 and e.season = m.season
left join body
  on body.curated_build_id = m.curated_build_id
 and body.team_key = m.team_key and body.season = m.season
left join types
  on types.curated_build_id = m.curated_build_id
 and types.team_key = m.team_key and types.season = m.season
left join profiles
  on profiles.curated_build_id = m.curated_build_id
 and profiles.team_key = m.team_key and profiles.season = m.season;

create view analysis.league_dashboard_payload_lineage_v1
with (security_invoker = true) as
with body as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from analysis.lineage_league_effective_injury_profiles_v1 p
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.season
), types as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.lineage_league_effective_injury_profiles_v1 p
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.season
), profile_rows as (
  select p.season, p.dimension, p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from analysis.lineage_league_effective_injury_profiles_v1 p
  union all
  select p.season, 'diagnosis', p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from analysis.lineage_league_diagnosis_profiles_v1 p
), profiles as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code
    ) as docs
  from profile_rows p
  group by p.season
)
select h.season, rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version, cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', (
      select max(m.generated_at)
      from analysis.league_member_releases_v2 m
      where m.season = h.season
    ),
    'team', 'URC Overall',
    'season', h.season,
    'analysis_window', jsonb_build_object(
      'start', w.season_start,
      'end', w.season_end,
      'basis', 'Registered season window; no team exposure-window restriction.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.',
      'Match exposure = registered fixtures in the season window × 15 players × 80 minutes / 60 per team.',
      'Training exposure = included curated exposure in the season window minus match exposure.',
      'IOC-aligned body-location and tissue/pathology categories use the accepted mappings.',
      'Injury rows and values are restated from the reviewed 2024-25 master workbook and its ordered decision ledger.'
    ),
    'coverage', coalesce((
      select b.dashboard -> 'coverage'
      from analysis.league_dashboard_payload_v2 b
      where b.season = h.season
    ), '{}'::jsonb) || jsonb_build_object(
      'hours', h.exposure_hours,
      'match_hours', h.match_exposure_hours,
      'training_hours', h.training_exposure_hours,
      'teams_included', (
        select count(*)
        from analysis.league_member_releases_v2 m
        where m.season = h.season
      ),
      'included_exposure_status', 'included',
      'analysis_window_start', w.season_start,
      'analysis_window_end', w.season_end
    ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', h.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in registered season window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', h.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(
          h.time_loss_injuries, h.exposure_hours
        ),
        'unit', 'per 1,000 player-hours',
        'numerator', h.time_loss_injuries,
        'denominator', h.exposure_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', h.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', h.days_lost, 'denominator', h.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', h.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(h.days_lost, h.exposure_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', h.days_lost, 'denominator', h.exposure_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
          when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.lineage_league_setting_split_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
          when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.lineage_league_setting_split_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from analysis.lineage_league_monthly_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from analysis.lineage_league_severity_distribution_v1 x
      where x.season = h.season
    ), '[]'::jsonb),
    'prior_season', jsonb_build_object(
      'season', '2023-24',
      'status', 'pending',
      'note', 'No prior-season league injury and exposure denominator pair has passed the V2 workflow.'
    ),
    'limitations', jsonb_build_array(
      'The registered season window, rather than team-specific exposure coverage, defines both numerator and denominator eligibility.',
      'Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.',
      'Unknown-setting injuries are included in overall metrics but have no match/training rate.',
      'Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.',
      'Superseded database-side injury cleaning is retired; the reviewed master-plus-ledger lineage is the authoritative injury record.'
    )
  ) as dashboard
from analysis.lineage_league_summary_v1 h
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'lineage_2024-25_2026-07-24_v1'
 and w.season = h.season
join analysis.accepted_lineage_cohort_rules_v1 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
left join body using (season)
left join types using (season)
left join profiles using (season);

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_analysis_version_check,
  add constraint league_release_context_v2_analysis_version_check check (
    analysis_version in ('v2', 'v3', 'v4')
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_decision_recorded_at_check,
  add constraint league_release_context_v2_decision_recorded_at_check check (
    (analysis_version = 'v2' and decision_recorded_at = date '2026-07-14') or
    (analysis_version = 'v3' and decision_recorded_at = date '2026-07-19') or
    (analysis_version = 'v4' and decision_recorded_at = date '2026-07-24')
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_cohort_view_version_check,
  add constraint league_release_context_v2_cohort_view_version_check check (
    cohort_view_version in (
      'v2',
      'season_bound_2026-07-20_v1',
      'lineage_2024-25_2026-07-24_v1'
    )
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_cohort_evidence,
  add constraint league_release_context_v2_cohort_evidence check (
    (cohort_view_version = 'v2' and cohort_evidence_sha256 is null) or
    (
      cohort_view_version = 'season_bound_2026-07-20_v1'
      and cohort_evidence_sha256 is not null
    ) or
    (
      cohort_view_version = 'lineage_2024-25_2026-07-24_v1'
      and cohort_evidence_sha256 is not null
    )
  );

create view analysis.team_dashboard_release_candidates_v6
with (security_invoker = true) as
select * from analysis.team_dashboard_release_candidates_v5
union all
select team_key, season, team_release_id, curated_build_id, 'v4'::text,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_lineage_v1;

create view analysis.league_dashboard_release_candidates_v6
with (security_invoker = true) as
select * from analysis.league_dashboard_release_candidates_v5
union all
select season, 'v4'::text, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_lineage_v1;

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
declare
  target_classification_version text;
  target_analysis_version text;
begin
  select classification_view_version, analysis_version
    into target_classification_version, target_analysis_version
  from reporting.league_release_context_v2
  where release_id = new.release_id;

  if target_classification_version =
      'reporting_classification_2026-07-22_v2'
    and target_analysis_version = 'v3' then
    if not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_classification_incremental_20260722_v1
        candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'incremental league dashboard snapshot changed fields outside the accepted classification sections';
    end if;
  elsif not exists (
    select 1
    from reporting.league_release_context_v2 context
    join analysis.league_dashboard_release_candidates_v6 candidate
      on candidate.season = context.season
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = new.dashboard_payload
    where context.release_id = new.release_id
  ) then
    raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
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
    left join analysis.team_dashboard_classification_incremental_20260722_v1
      candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.classification_view_version =
        'reporting_classification_2026-07-22_v2'
      and context.analysis_version = 'v3'
      and candidate.team_key is null
  ) then
    raise exception 'incremental team dashboard snapshots changed fields outside the accepted classification sections';
  end if;

  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v6 candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where (
      context.classification_view_version <>
        'reporting_classification_2026-07-22_v2'
      or context.analysis_version <> 'v3'
    )
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;
  return null;
end;
$$;

comment on function reporting.validate_league_dashboard_v2_candidate() is
  'Validates full releases against v6 candidates and OSIICS classification-only V3 releases against the immutable incremental candidate.';
comment on function reporting.validate_team_dashboard_v2_candidates() is
  'Statement trigger validating v6 full or classification-only V3 team dashboard candidates without rebuilding unrelated metrics.';

revoke execute on function reporting.validate_league_dashboard_v2_candidate()
  from public;
revoke execute on function reporting.validate_team_dashboard_v2_candidates()
  from public;
