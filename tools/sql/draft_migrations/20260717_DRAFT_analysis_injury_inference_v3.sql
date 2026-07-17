-- DRAFT ONLY — NOT A MIGRATION — DO NOT APPLY.
-- Proposed rule version: urc-diagnosis-inference-v3-draft.5
-- This file is intentionally outside supabase/migrations and transaction-guarded.
-- Promotion requires the checklist in README.md and an exact rule-parity review.

begin;

do $draft_guard$
begin
  raise exception 'DRAFT ONLY: recorded adjudication and explicit hosted-target approval are required';
end
$draft_guard$;

-- Proposed immutable rule catalogue. Patterns are evidence selectors, not
-- clinical facts; a row is inferred only when its candidate set has one value.
create view analysis.injury_inference_rules_v3
with (security_invoker = true) as
select *
from (values
  -- domain, priority, code, evidence field, include regex, exclude regex,
  -- required IOC body bucket, required IOC tissue/pathology bucket, rationale
  ('body_location', 10, 'head', 'clinical', '\m(concuss(ion|ed)?|brain injury|head injury|facial|skull|jaw)\M', null, null, null, 'Explicit head/brain anatomy'),
  ('body_location', 20, 'shoulder', 'clinical', '(\mshoulder\M|acromioclavicular|\mac joint\M|\ma/c joint\M|\mclavicle\M|scapul)', null, null, null, 'Explicit shoulder-region anatomy'),
  ('body_location', 30, 'thigh', 'clinical', '(\mthigh\M|hamstring|biceps femoris|semitend|semimembran|quadriceps|rectus femoris|\mvastus\M|\madductor\M)', null, null, null, 'Explicit thigh muscle anatomy'),
  ('body_location', 40, 'knee', 'clinical', '(\mknee\M|patell|menisc|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|cruciate)', null, null, null, 'Explicit knee anatomy'),
  ('body_location', 50, 'lower_leg', 'clinical', '(\mlower leg\M|\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M|achilles|\mshin\M)', null, null, null, 'Explicit lower-leg anatomy'),
  ('body_location', 60, 'ankle', 'clinical', '(\mankle\M|syndesmo|high ankle sprain)', null, null, null, 'Explicit ankle anatomy'),
  ('body_location', 70, 'foot', 'clinical', '(\mfoot\M|\mtoe\M|metatars|lisfranc|calcane|plantar)', null, null, null, 'Explicit foot anatomy'),

  ('tissue_pathology', 10, 'brain_spinal_cord_injury', 'clinical', '(concuss(ion|ed)?|brain injury|spinal cord injury)', null, null, null, 'Explicit neural injury'),
  ('tissue_pathology', 20, 'tendon_rupture', 'clinical', '(tendon|achilles).{0,18}(ruptur|complete tear)|(ruptur|complete tear).{0,18}(tendon|achilles)', null, null, null, 'Explicit tendon rupture'),
  ('tissue_pathology', 30, 'bone_stress_injury', 'clinical', '(stress fracture|bone stress|stress reaction|shin splints)', null, null, null, 'Explicit bone-stress pathology'),
  ('tissue_pathology', 40, 'bone_contusion', 'clinical', '(bone contusion|bony contusion|bone bruise)', null, null, null, 'Explicit bone contusion'),
  ('tissue_pathology', 50, 'fracture', 'clinical', '(fractur|broken bone)', '(stress fracture|bone stress|stress reaction)', null, null, 'Traumatic fracture only'),
  ('tissue_pathology', 60, 'cartilage_injury', 'clinical', '(osteochondral|\mcartilage\M|labral|labrum|menisc)', null, null, null, 'Explicit cartilage/labral/meniscal evidence'),
  ('tissue_pathology', 70, 'joint_sprain', 'clinical', '(\msprain(ed)?\M|\mligament\M|disloc|sublux|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|syndesmo|lisfranc)', null, null, null, 'Explicit joint/ligament injury'),
  ('tissue_pathology', 80, 'muscle_injury', 'clinical', '(muscle (strain|tear|rupture|injury)|\mstrain(ed)?\M|hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M)', '(muscle contusion|muscle haematoma|intramuscular haematoma)', null, null, 'Explicit muscle injury excluding contusion'),

  ('diagnosis', 1, 'concussion', 'clinical', '(concuss(ion|ed)?|brain injury)', null, null, null, 'Named diagnosis'),
  ('diagnosis', 2, 'ac_joint_sprain', 'clinical', '(acromioclavicular|\mac joint\M|\ma/c joint\M).*(sprain|separation|disloc)|(sprain|separation|disloc).*(acromioclavicular|\mac joint\M|\ma/c joint\M)', null, 'shoulder', null, 'Named region-specific diagnosis'),
  ('diagnosis', 3, 'syndesmosis_injury', 'clinical', '(syndesmo|high ankle sprain)', 'fractur', 'ankle', null, 'Named region-specific diagnosis'),
  ('diagnosis', 4, 'lisfranc_injury', 'clinical', '\mlisfranc\M', null, 'foot', null, 'Named region-specific diagnosis'),
  ('diagnosis', 5, 'acl_injury', 'clinical', '(\macl\M|anterior cruciate)', null, 'knee', null, 'Named structure'),
  ('diagnosis', 6, 'mcl_injury', 'clinical', '(\mmcl\M|medial collateral)', null, 'knee', null, 'Named structure'),
  ('diagnosis', 7, 'pcl_lcl_injury', 'clinical', '(\mpcl\M|\mlcl\M|posterior cruciate|lateral collateral)', null, 'knee', null, 'Named structure'),
  ('diagnosis', 8, 'meniscal_injury', 'clinical', 'menisc', null, 'knee', null, 'Named structure'),
  ('diagnosis', 15, 'achilles_tendon', 'clinical', '\machilles\M', null, 'lower_leg', null, 'Named tendon'),
  ('diagnosis', 16, 'patellar_tendon', 'clinical', 'patellar tendon', null, 'knee', null, 'Named tendon'),
  ('diagnosis', 17, 'shoulder_labral', 'clinical', '(labral|labrum)', null, 'shoulder', 'cartilage_injury', 'Named structure'),
  ('diagnosis', 19, 'fracture', 'clinical', '(fractur|broken bone)', '\mlisfranc\M', null, 'fracture', 'General pathology after named diagnoses'),
  ('diagnosis', 20, 'contusion_haematoma', 'clinical', '(\mcontusion\M|haematoma|hematoma|dead leg)', '(concuss(ion|ed)?|brain injury)', null, null, 'General pathology after named diagnoses'),

  ('contact_context', 10, 'contact', 'mechanism', '(\mtackl(e|ed|ing)\M|collision with (a |another |opposition )?player|contact with (a |another |opposition )?player|\mruck\M|\mmaul\M|\mscrum\M)', null, null, null, 'Explicit contact mechanism'),
  ('contact_context', 20, 'non_contact', 'mechanism', '(non[- ]contact|without contact|change of direction|overuse|overload)', null, null, null, 'Explicit non-contact mechanism')
) r(domain, priority, code, evidence_field, include_pattern, exclude_pattern,
    required_body_location, required_tissue_pathology, rationale);

-- Proposed row-level seam. The accepted migration must expand the complete
-- draft.5 body/tissue catalogue from dashboard_v3_preview.sql here, retain the
-- strict Orchard first/second-character candidates, and checksum-prove parity.
-- Existing curated values are exposed separately and never overwritten.
create view analysis.injury_inference_by_build_v3
with (security_invoker = true) as
with evidence as (
  select i.id as injury_id, i.curated_build_id, i.team_key, i.season,
    i.body_location as source_body_location,
    i.injury_type as source_tissue_pathology,
    i.contact_context as source_contact_context,
    i.field_origins,
    upper(trim(coalesce(sr.source_values ->> 'Orchard Code', ''))) as orchard_code,
    lower(trim(concat_ws(' ', sr.source_values ->> 'Description',
      sr.source_values ->> 'Injury Tissue Type/s', sr.source_values ->> 'Body Part'))) as clinical_evidence,
    lower(trim(concat_ws(' ', sr.source_values ->> 'Mechanism of Injury',
      sr.source_values ->> 'Mechanism Notes'))) as mechanism_evidence
  from curated.injuries i
  join ingestion.source_rows sr on sr.id = i.source_row_id
  where i.problem_type = 'injury'
), text_candidates as (
  select e.injury_id, r.domain, r.code
  from evidence e
  join analysis.injury_inference_rules_v3 r
    on (case r.evidence_field when 'mechanism' then e.mechanism_evidence else e.clinical_evidence end) ~ r.include_pattern
   and (r.exclude_pattern is null or (case r.evidence_field when 'mechanism' then e.mechanism_evidence else e.clinical_evidence end) !~ r.exclude_pattern)
), candidate_summary as (
  select injury_id, domain, count(distinct code)::int as candidate_count,
    min(code) as sole_candidate, array_agg(distinct code order by code) as candidates
  from text_candidates
  group by injury_id, domain
)
select e.*,
  case when coalesce(e.source_body_location, 'unknown') <> 'unknown' then e.source_body_location
    when b.candidate_count = 1 then b.sole_candidate else 'unknown' end as effective_body_location,
  case when coalesce(e.source_tissue_pathology, 'unknown') <> 'unknown' then e.source_tissue_pathology
    when t.candidate_count = 1 then t.sole_candidate else 'unknown' end as effective_tissue_pathology,
  case when coalesce(e.source_contact_context, 'unknown') <> 'unknown' then e.source_contact_context
    when c.candidate_count = 1 then c.sole_candidate else 'unknown' end as effective_contact_context,
  case when d.candidate_count = 1 then d.sole_candidate end as inferred_diagnosis,
  coalesce(b.candidates, array[]::text[]) as body_location_candidates,
  coalesce(t.candidates, array[]::text[]) as tissue_pathology_candidates,
  coalesce(c.candidates, array[]::text[]) as contact_context_candidates,
  coalesce(d.candidates, array[]::text[]) as diagnosis_candidates,
  'urc-diagnosis-inference-v3-draft.5'::text as rule_version
from evidence e
left join candidate_summary b on b.injury_id = e.injury_id and b.domain = 'body_location'
left join candidate_summary t on t.injury_id = e.injury_id and t.domain = 'tissue_pathology'
left join candidate_summary c on c.injury_id = e.injury_id and c.domain = 'contact_context'
left join candidate_summary d on d.injury_id = e.injury_id and d.domain = 'diagnosis';

-- Proposed additive cohort seam; frozen V1/V2 views remain untouched.
create view analysis.injury_cohort_by_build_v3
with (security_invoker = true) as
select c.*, i.source_body_location, i.effective_body_location,
  i.source_tissue_pathology, i.effective_tissue_pathology,
  i.source_contact_context, i.effective_contact_context,
  i.inferred_diagnosis, i.rule_version
from analysis.injury_cohort_by_build_v2 c
join analysis.injury_inference_by_build_v3 i on i.injury_id = c.injury_id;

rollback;
