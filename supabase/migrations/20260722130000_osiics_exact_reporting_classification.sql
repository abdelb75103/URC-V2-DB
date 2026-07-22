-- Additive successor reporting classification approved 22 July 2026.
-- Original source and curated values remain immutable. Exact OSIICS/OSICS
-- mappings and unique explicit body/type text are exposed only as effective
-- reporting values with provenance. Conflicts and ambiguous types remain
-- Unknown.

alter table audit.rule_adjudications
  drop constraint rule_adjudications_migration_version_check,
  add constraint rule_adjudications_migration_version_check check (
    migration_version in ('20260720150000', '20260722130000')
  );

create view analysis.osiics_exact_ioc_mapping_v1
with (security_invoker = true) as
select * from (values
  ('AL1','ankle','joint_sprain'),('AL2','ankle','joint_sprain'),
  ('ALA','ankle','joint_sprain'),('ALJ','ankle','joint_sprain'),
  ('ALM','ankle','joint_sprain'),('ALR','ankle','joint_sprain'),
  ('ALS','ankle','joint_sprain'),('AQA','ankle','synovitis_capsulitis'),
  ('AQP','ankle','synovitis_capsulitis'),('CC1','chest','cartilage_injury'),
  ('CLS','chest','joint_sprain'),('CLX','chest','joint_sprain'),
  ('DL1','thoracic_spine','joint_sprain'),('EC1','elbow','cartilage_injury'),
  ('ELA','elbow','joint_sprain'),('ELM','elbow','joint_sprain'),
  ('ER1','elbow','tendon_rupture'),('FIN','foot','abrasion'),
  ('FL1','foot','joint_sprain'),('FLJ','foot','joint_sprain'),
  ('FPL','foot','joint_sprain'),('FQ2','foot','synovitis_capsulitis'),
  ('FRP','foot','tendon_rupture'),('JTKT','knee','physis_injury'),
  ('KC1','knee','cartilage_injury'),('KC2','knee','cartilage_injury'),
  ('KC8','knee','cartilage_injury'),('KCD','knee','cartilage_injury'),
  ('KCP','knee','cartilage_injury'),('KCU','knee','cartilage_injury'),
  ('KL2','knee','joint_sprain'),('KL3','knee','joint_sprain'),
  ('KL5','knee','joint_sprain'),('KLM','knee','joint_sprain'),
  ('KLV','knee','joint_sprain'),('KQS','knee','synovitis_capsulitis'),
  ('KV1','knee','contusion_superficial'),
  ('LC1','lumbosacral','cartilage_injury'),
  ('LC3','lumbosacral','cartilage_injury'),
  ('LCP','lumbosacral','cartilage_injury'),
  ('LLF','lumbosacral','joint_sprain'),('NC1','neck','cartilage_injury'),
  ('NL1','neck','joint_sprain'),('NLW','neck','joint_sprain'),
  ('QVVP','lower_leg','vascular_trauma'),('SL1','shoulder','joint_sprain'),
  ('SL2','shoulder','joint_sprain'),
  ('SQP','shoulder','synovitis_capsulitis'),('WC1','wrist','cartilage_injury')
) v(source_code, mapped_body_location_code, mapped_injury_type_code);

comment on view analysis.osiics_exact_ioc_mapping_v1 is
  'Exact reviewed OSIICS 15 / OSICS 10 / OSICS 9 source-code mappings bound to docs/evidence/osiics_exact_mapping_2024-25.json.';

create view analysis.osiics_multi_type_diagnosis_v1
with (security_invoker = true) as
select * from (values
  ('NPM','neck','multi__neck__muscle_injury__tendinopathy',
   'Neck · Muscle/tendon injury','muscle_injury;tendinopathy','nonspecific')
) v(source_code, mapped_body_location_code, diagnosis_code,
    diagnosis_label, candidate_injury_types, analysis_primary_type_code);

comment on view analysis.osiics_multi_type_diagnosis_v1 is
  'Reviewed multi-type OSIICS diagnoses: candidate types are retained verbatim and one nonspecific primary type prevents double-counting.';

create view analysis.accepted_reporting_classification_rules_v4
with (security_invoker = true) as
select
  r.rule_version as classification_view_version,
  encode(digest(convert_to(jsonb_build_object(
    'predecessor_classification_evidence_sha256', predecessor.classification_evidence_sha256,
    'adjudication_ref', r.adjudication_ref,
    'decision', r.decision,
    'evidence_sha256', r.evidence_sha256,
    'workbook_sha256', r.workbook_sha256,
    'evidence_manifest_sha256', r.evidence_manifest_sha256,
    'reviewer', r.reviewer,
    'migration_version', r.migration_version,
    'migration_sha256', r.migration_sha256,
    'rationale', r.rationale
  )::text, 'UTF8'), 'sha256'), 'hex') as classification_evidence_sha256
from analysis.accepted_reporting_classification_rules_v3 predecessor
join audit.rule_adjudications r
  on r.rule_version = 'reporting_classification_2026-07-22_v2'
 and r.adjudication_ref = 'OSIICS-01'
where r.reviewer = 'Abdel Babiker'
  and r.evidence_sha256 = 'ff0e31d1fb8f92c4a0084fc9d7dd86d9371941a2cd2aeb3b993cadbb66ea7310'
  and r.workbook_sha256 = '8bfeab660942f9ff7a25ebeb42544c231d611365fb9ee36cec27233bc82157c5'
  and r.evidence_manifest_sha256 = '821596f5ea5a227b231451873b434fb6b59b01397eda64cb0c081037dfe5774c'
  and r.migration_version = '20260722130000'
  and r.decision = '{
    "mapping_catalogue_sha256":"81604d6cec0356967ccbd263b277f9d75cb19c7d085a9d15dc47d5b70cf5ae6c",
    "multi_type_catalogue_sha256":"04ec0e97424b9c2128e555c475d0ab9c70b8c2d016c864909bc532ba73fbe0e7",
    "exact_code_candidate_count":108,
    "explicit_text_candidate_count":12,
    "multi_type_diagnosis_candidate_count":1,
    "unknown_before":245,
    "unknown_after":124,
    "preserve_original_values":true,
    "conflicts_remain_unknown":true
  }'::jsonb;

create view analysis.season_bound_reporting_classification_v4
with (security_invoker = true) as
with evidence as (
  select
    c.*,
    predecessor.diagnosis_code as predecessor_diagnosis_code,
    predecessor.diagnosis_label as predecessor_diagnosis_label,
    upper(trim(coalesce(
      nullif(sr.source_values ->> 'Orchard Code', ''),
      case when i.problem_type = 'injury' then sr.source_values ->> 'Illness Code' end,
      ''
    ))) as orchard_code,
    lower(trim(concat_ws(' ',
      sr.source_values ->> 'Description',
      sr.source_values ->> 'Injury Tissue Type/s',
      sr.source_values ->> 'Body Part'
    ))) as clinical_evidence,
    lower(trim(coalesce(sr.source_values ->> 'Injury Tissue Type/s', ''))) as source_tissue_evidence
  from analysis.injury_cohort_by_build_season_bound_v3 c
  join analysis.season_bound_reporting_classification_v3 predecessor
    using (injury_id, curated_build_id, team_key, season, setting_code, is_time_loss, days_lost)
  join curated.injuries i on i.id = c.injury_id
  join ingestion.source_rows sr on sr.id = i.source_row_id
  cross join analysis.accepted_reporting_classification_rules_v4 accepted
), body_candidates as (
  select e.injury_id, m.mapped_body_location_code as body_code, 'exact_osiics'::text as origin
  from evidence e
  join analysis.osiics_exact_ioc_mapping_v1 m on m.source_code = e.orchard_code
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
    ('shoulder', e.clinical_evidence ~ '(\mshoulder\M|acromioclavicular|\mac joint\M|\ma/c joint\M|\mclavicle\M|scapul)'),
    ('upper_arm', e.clinical_evidence ~ '(\mupper arm\M|humerus|humeral)'),
    ('elbow', e.clinical_evidence ~ '\melbow\M'),
    ('forearm', e.clinical_evidence ~ '\mforearm\M'),
    ('wrist', e.clinical_evidence ~ '(\mwrist\M|carpal|scaphoid)'),
    ('hand', e.clinical_evidence ~ '(\mhand\M|\mfinger\M|\mthumb\M|metacarp)'),
    ('chest', e.clinical_evidence ~ '(\mchest\M|\mrib(s)?\M|sternum|sternal|pectoral)'),
    ('thoracic_spine', e.clinical_evidence ~ '(thoracic spine|costovertebral)'),
    ('lumbosacral', e.clinical_evidence ~ '(lumbar|lumbosacral|\msacrum\M|\msacral\M|\mcoccyx\M|\mbuttock\M)'),
    ('abdomen', e.clinical_evidence ~ '(\mabdomen\M|abdominal)'),
    ('hip_groin', e.clinical_evidence ~ '(\mhip\M|\mgroin\M|inguinal|\madductor\M)'),
    ('thigh', e.clinical_evidence ~ '(\mthigh\M|hamstring|biceps femoris|semitend|semimembran|quadriceps|rectus femoris|\mvastus\M)'),
    ('knee', e.clinical_evidence ~ '(\mknee\M|patell|menisc|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|cruciate)'),
    ('lower_leg', e.clinical_evidence ~ '(\mlower leg\M|\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M|achilles|\mshin\M)'),
    ('ankle', e.clinical_evidence ~ '(\mankle\M|syndesmo|high ankle sprain)'),
    ('foot', e.clinical_evidence ~ '(\mfoot\M|\mtoe\M|metatars|lisfranc|calcane|plantar)')
  ) x(body_code, matches)
  where e.predecessor_diagnosis_code = 'unknown' and x.matches
  union all
  select e.injury_id, m.mapped_body_location_code, 'adjudicated_multi_type_osiics'
  from evidence e
  join analysis.osiics_multi_type_diagnosis_v1 m on m.source_code = e.orchard_code
  where e.predecessor_diagnosis_code = 'unknown'
), body_summary as (
  select injury_id, count(distinct body_code)::int as candidate_count,
    min(body_code) as sole_candidate,
    bool_or(origin in ('exact_osiics','strict_osiics_prefix')) as has_code_origin
  from body_candidates group by injury_id
), body_resolved as (
  select e.*,
    case when e.body_location_code <> 'unknown' then e.body_location_code
      when coalesce(b.candidate_count, 0) = 1 then b.sole_candidate
      else 'unknown' end as effective_body_location_code,
    case when e.body_location_code <> 'unknown' then 'predecessor_curated'
      when coalesce(b.candidate_count, 0) = 1 and b.has_code_origin then 'mapped_from_osiics_body'
      when coalesce(b.candidate_count, 0) = 1 then 'inferred_from_explicit_body_text'
      else 'remaining_unknown' end as body_location_origin,
    coalesce(b.candidate_count, 0) as body_evidence_candidate_count,
    b.sole_candidate as sole_body_evidence_candidate
  from evidence e left join body_summary b using (injury_id)
), type_candidates as (
  select e.injury_id, m.mapped_injury_type_code as type_code,
    'exact_osiics'::text as origin
  from body_resolved e
  join analysis.osiics_exact_ioc_mapping_v1 m on m.source_code = e.orchard_code
  where e.predecessor_diagnosis_code = 'unknown'
    and e.injury_type_code = 'unknown'
    and m.mapped_body_location_code = e.effective_body_location_code
  union all
  select e.injury_id, x.type_code, 'explicit_text'
  from body_resolved e
  cross join lateral (values
    ('brain_spinal_cord_injury', e.clinical_evidence ~ '(concuss(ion|ed)?|brain injury|spinal cord injury)'),
    ('tendon_rupture', e.clinical_evidence ~ '(tendon|achilles).{0,18}(ruptur|complete tear)|(ruptur|complete tear).{0,18}(tendon|achilles)'),
    ('bone_stress_injury', e.clinical_evidence ~ '(stress fracture|bone stress|stress reaction|shin splints)'),
    ('bone_contusion', e.clinical_evidence ~ '(bone contusion|bony contusion|bone bruise)'),
    ('fracture', e.clinical_evidence ~ '(fractur|broken bone)' and e.clinical_evidence !~ '(stress fracture|bone stress|stress reaction)'),
    ('peripheral_nerve_injury', e.clinical_evidence ~ '(\mnerve\M|brachial plexus|burner/stinger|\mstinger\M)'),
    ('cartilage_injury', e.clinical_evidence ~ '(osteochondral|\mcartilage\M|labral|labrum|menisc)'),
    ('arthritis', e.clinical_evidence ~ '(osteoarthritis|\marthritis\M)'),
    ('tendinopathy', e.clinical_evidence ~ '(tendinopathy|tendinosis|tendon injury|tendon strain|plantar fasci)' and e.clinical_evidence !~ '(ruptur|complete tear)'),
    ('bursitis', e.clinical_evidence ~ '\mbursitis\M'),
    ('synovitis_capsulitis', e.clinical_evidence ~ '(\msynovitis\M|\mcapsulitis\M|\mimpingement\M)' and e.clinical_evidence !~ '\mbursitis\M'),
    ('chronic_instability', e.clinical_evidence ~ '(chronic instability|recurrent instability)'),
    ('joint_sprain', e.clinical_evidence ~ '(\msprain(ed)?\M|\mligament\M|disloc|sublux|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|syndesmo|lisfranc)'),
    ('muscle_contusion', e.clinical_evidence ~ '(muscle contusion|muscle haematoma|intramuscular haematoma)'),
    ('laceration', e.clinical_evidence ~ '\mlacerat(ion|ed)\M'),
    ('abrasion', e.clinical_evidence ~ '\mabrasion\M'),
    ('contusion_superficial', e.clinical_evidence ~ '(\mcontusion\M|haematoma|hematoma|\mbruis(e|ed|ing)\M|dead leg)' and e.clinical_evidence !~ '(muscle contusion|muscle haematoma|intramuscular haematoma|bone contusion|bony contusion|bone bruise)'),
    ('muscle_injury', (
      e.source_tissue_evidence ~ '(^|[,;/])\s*muscle(s| injury)?\s*($|[,;/])'
      or e.clinical_evidence ~ '(muscle (strain|tear|rupture|injury)|((hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M).{0,24}(strain|tear|ruptur|injur))|((strain|tear|ruptur|injur).{0,24}(hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M)))'
    ) and e.clinical_evidence !~ '(muscle contusion|muscle haematoma|intramuscular haematoma)'
      and e.orchard_code <> 'QPS')
  ) x(type_code, matches)
  where e.predecessor_diagnosis_code = 'unknown'
    and e.injury_type_code = 'unknown' and x.matches
    and (
      e.body_evidence_candidate_count = 0
      or (e.body_evidence_candidate_count = 1
        and e.sole_body_evidence_candidate = e.effective_body_location_code)
    )
), type_summary as (
  select injury_id, count(distinct type_code)::int as candidate_count,
    min(type_code) as sole_candidate,
    bool_or(origin = 'exact_osiics') as has_exact_code_origin,
    bool_or(origin = 'explicit_text') as has_text_origin
  from type_candidates group by injury_id
), resolved as (
  select b.*,
    case when b.injury_type_code <> 'unknown' then b.injury_type_code
      when multi.source_code is not null
        and multi.mapped_body_location_code = b.effective_body_location_code
        then multi.analysis_primary_type_code
      when coalesce(t.candidate_count, 0) = 1 then t.sole_candidate
      else 'unknown' end as effective_injury_type_code,
    case when b.injury_type_code <> 'unknown' then 'predecessor_curated'
      when multi.source_code is not null
        and multi.mapped_body_location_code = b.effective_body_location_code
        then 'adjudicated_multi_type_osiics_diagnosis'
      when coalesce(t.candidate_count, 0) = 1 and t.has_exact_code_origin then 'mapped_from_exact_osiics_code'
      when coalesce(t.candidate_count, 0) = 1 then 'inferred_from_unique_explicit_type_text'
      else 'remaining_unknown' end as injury_type_origin,
    case when multi.source_code is not null
      and multi.mapped_body_location_code = b.effective_body_location_code
      then 2 else coalesce(t.candidate_count, 0) end as injury_type_candidate_count,
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
  case when r.predecessor_diagnosis_code <> 'unknown' then r.predecessor_diagnosis_code
    when r.multi_diagnosis_code is not null then r.multi_diagnosis_code
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      then concat('compound__', r.effective_body_location_code, '__', r.effective_injury_type_code)
    else 'unknown' end as diagnosis_code,
  case when r.predecessor_diagnosis_code <> 'unknown' then r.predecessor_diagnosis_label
    when r.multi_diagnosis_label is not null then r.multi_diagnosis_label
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      then concat(bl.label, ' · ', it.label)
    else 'Unknown diagnosis' end as diagnosis_label,
  r.body_location_code as original_body_location_code,
  r.injury_type_code as original_injury_type_code,
  r.effective_body_location_code,
  r.effective_injury_type_code,
  r.body_location_origin,
  r.injury_type_origin,
  case when r.predecessor_diagnosis_code <> 'unknown' then 'predecessor_reporting_classification'
    when r.multi_diagnosis_code is not null then 'adjudicated_multi_type_osiics_diagnosis'
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      and r.injury_type_origin = 'mapped_from_exact_osiics_code'
      then 'mapped_from_exact_osiics_code'
    when r.effective_body_location_code <> 'unknown'
      and r.effective_injury_type_code <> 'unknown'
      then 'inferred_from_unique_explicit_body_and_type_text'
    else 'remaining_unknown' end as diagnosis_origin,
  r.injury_type_candidate_count,
  r.candidate_injury_types
from resolved r
left join curated.code_lists bl
  on bl.list_name = 'body_location' and bl.code = r.effective_body_location_code
left join curated.code_lists it
  on it.list_name = 'injury_type' and it.code = r.effective_injury_type_code;

create view analysis.season_bound_effective_injury_profiles_v4
with (security_invoker = true) as
with labelled as (
  select c.*,
    coalesce(bl.label, initcap(replace(c.effective_body_location_code, '_', ' '))) as body_label,
    coalesce(it.label, initcap(replace(c.effective_injury_type_code, '_', ' '))) as type_label
  from analysis.season_bound_reporting_classification_v4 c
  left join curated.code_lists bl
    on bl.list_name = 'body_location' and bl.code = c.effective_body_location_code
  left join curated.code_lists it
    on it.list_name = 'injury_type' and it.code = c.effective_injury_type_code
), grouped as (
  select c.curated_build_id, c.team_key, c.season, d.dimension, d.code, d.label,
    s.setting_code, count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from labelled c
  join analysis.league_member_releases_v2 m using (curated_build_id, team_key, season)
  cross join lateral (values
    ('body_location'::text, c.effective_body_location_code, c.body_label),
    ('injury_type'::text, c.effective_injury_type_code, c.type_label),
    ('injury_profile'::text,
      c.effective_body_location_code || '__' || c.effective_injury_type_code,
      c.body_label || ' · ' || c.type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
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
join analysis.exposure_hours_by_build_season_bound_v3 e
  using (curated_build_id, team_key, season);

create view analysis.season_bound_league_effective_injury_profiles_v4
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries, sum(x.days_lost) as days_lost
  from analysis.season_bound_effective_injury_profiles_v4 x
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours else null end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours else null end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours else null end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g join analysis.season_bound_league_summary_v3 h using (season);

create view analysis.season_bound_diagnosis_profiles_v4
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, c.diagnosis_code as code,
    c.diagnosis_label as label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.season_bound_reporting_classification_v4 c
  join analysis.league_member_releases_v2 m using (curated_build_id, team_key, season)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code, c.diagnosis_label, s.setting_code
)
select g.*,
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
join analysis.exposure_hours_by_build_season_bound_v3 e
  using (curated_build_id, team_key, season);

create view analysis.season_bound_league_diagnosis_profiles_v4
with (security_invoker = true) as
with grouped as (
  select x.season, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.season_bound_diagnosis_profiles_v4 x
  group by x.season, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours else null end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours else null end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code when 'all' then h.exposure_hours when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours else null end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0) as mean_severity_days
from grouped g join analysis.season_bound_league_summary_v3 h using (season);

create view analysis.team_dashboard_payload_osiics_v4
with (security_invoker = true) as
select base.team_key, base.season, base.team_release_id, base.curated_build_id,
  rules.classification_view_version, rules.classification_evidence_sha256,
  base.cohort_view_version, base.cohort_evidence_sha256,
  jsonb_set(jsonb_set(jsonb_set(base.dashboard,
    '{body_locations}', coalesce(body.docs, '[]'::jsonb)),
    '{injury_types}', coalesce(types.docs, '[]'::jsonb)),
    '{injury_profiles}', coalesce(profiles.docs, '[]'::jsonb) ||
      coalesce(diagnosis.docs, '[]'::jsonb)) as dashboard
from analysis.team_dashboard_payload_season_bound_v3 base
cross join analysis.accepted_reporting_classification_rules_v4 rules
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
    'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.code) as docs
  from analysis.season_bound_effective_injury_profiles_v4 p
  where p.curated_build_id=base.curated_build_id and p.team_key=base.team_key
    and p.season=base.season and p.dimension='body_location' and p.setting_code='all'
) body on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
    'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.season_bound_effective_injury_profiles_v4 p
  where p.curated_build_id=base.curated_build_id and p.team_key=base.team_key
    and p.season=base.season and p.dimension='injury_type' and p.setting_code='all'
) types on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'dimension',p.dimension,'code',p.code,'label',p.label,'setting',p.setting_code,
    'time_loss_injuries',p.time_loss_injuries,'days_lost',p.days_lost,
    'exposure_hours',p.exposure_hours,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.dimension,p.setting_code,p.time_loss_injuries desc,p.days_lost desc,p.code) as docs
  from analysis.season_bound_effective_injury_profiles_v4 p
  where p.curated_build_id=base.curated_build_id and p.team_key=base.team_key
    and p.season=base.season
) profiles on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'dimension','diagnosis','code',p.code,'label',p.label,'setting',p.setting_code,
    'time_loss_injuries',p.time_loss_injuries,'days_lost',p.days_lost,
    'exposure_hours',p.exposure_hours,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.setting_code, p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.season_bound_diagnosis_profiles_v4 p
  where p.curated_build_id = base.curated_build_id
    and p.team_key = base.team_key and p.season = base.season
) diagnosis on true;

create view analysis.league_dashboard_payload_osiics_v4
with (security_invoker = true) as
select base.season, rules.classification_view_version,
  rules.classification_evidence_sha256,
  base.cohort_view_version, base.cohort_evidence_sha256,
  jsonb_set(jsonb_set(jsonb_set(base.dashboard,
    '{body_locations}', coalesce(body.docs, '[]'::jsonb)),
    '{injury_types}', coalesce(types.docs, '[]'::jsonb)),
    '{injury_profiles}', coalesce(profiles.docs, '[]'::jsonb) ||
      coalesce(diagnosis.docs, '[]'::jsonb)) as dashboard
from analysis.league_dashboard_payload_season_bound_v3 base
cross join analysis.accepted_reporting_classification_rules_v4 rules
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
    'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.code) as docs
  from analysis.season_bound_league_effective_injury_profiles_v4 p
  where p.season=base.season and p.dimension='body_location' and p.setting_code='all'
) body on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'key',p.code,'label',p.label,'time_loss_injuries',p.time_loss_injuries,
    'days_lost',p.days_lost,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.time_loss_injuries desc,p.days_lost desc,p.code) as docs
  from analysis.season_bound_league_effective_injury_profiles_v4 p
  where p.season=base.season and p.dimension='injury_type' and p.setting_code='all'
) types on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'dimension',p.dimension,'code',p.code,'label',p.label,'setting',p.setting_code,
    'time_loss_injuries',p.time_loss_injuries,'days_lost',p.days_lost,
    'exposure_hours',p.exposure_hours,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.dimension,p.setting_code,p.time_loss_injuries desc,p.days_lost desc,p.code) as docs
  from analysis.season_bound_league_effective_injury_profiles_v4 p
  where p.season=base.season
) profiles on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'dimension','diagnosis','code',p.code,'label',p.label,'setting',p.setting_code,
    'time_loss_injuries',p.time_loss_injuries,'days_lost',p.days_lost,
    'exposure_hours',p.exposure_hours,'incidence_per_1000h',p.incidence_per_1000h,
    'burden_per_1000h',p.burden_per_1000h,'mean_severity_days',p.mean_severity_days
  ) order by p.setting_code, p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.season_bound_league_diagnosis_profiles_v4 p
  where p.season = base.season
) diagnosis on true;

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_classification_view_version_check,
  add constraint league_release_context_v2_classification_view_version_check check (
    classification_view_version in (
      'v2', 'reporting_classification_2026-07-20_v1',
      'reporting_classification_2026-07-22_v2'
    )
  ),
  drop constraint league_release_context_v2_classification_evidence,
  add constraint league_release_context_v2_classification_evidence check (
    (classification_view_version = 'v2' and classification_evidence_sha256 is null)
    or
    (classification_view_version in (
      'reporting_classification_2026-07-20_v1',
      'reporting_classification_2026-07-22_v2'
    ) and classification_evidence_sha256 is not null)
  );

create view analysis.team_dashboard_release_candidates_v5
with (security_invoker = true) as
select * from analysis.team_dashboard_release_candidates_v4
union all
select team_key, season, team_release_id, curated_build_id, 'v3'::text,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_osiics_v4;

create view analysis.league_dashboard_release_candidates_v5
with (security_invoker = true) as
select * from analysis.league_dashboard_release_candidates_v4
union all
select season, 'v3'::text, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_osiics_v4;

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
begin
  if not exists (
    select 1 from reporting.league_release_context_v2 context
    join analysis.league_dashboard_release_candidates_v5 candidate
      on candidate.season=context.season and candidate.analysis_version=context.analysis_version
     and candidate.classification_view_version=context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version=context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard=new.dashboard_payload
    where context.release_id=new.release_id
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
      on context.release_id=payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v5 candidate
      on candidate.season=context.season and candidate.team_key=payload.team_key
     and candidate.team_release_id=payload.team_release_id
     and candidate.curated_build_id=payload.curated_build_id
     and candidate.analysis_version=context.analysis_version
     and candidate.classification_view_version=context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version=context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard=payload.dashboard_payload
    where candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;
  return null;
end;
$$;

comment on view analysis.season_bound_reporting_classification_v4 is
  'Accepted additive diagnosis successor: exact OSIICS/OSICS mapping and unique explicit body/type text; source and curated fields remain immutable.';
