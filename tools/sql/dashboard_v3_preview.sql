-- Read-only V3 candidate aggregates for local dashboard review.
--
-- This query never changes database state. It is deliberately pinned to the
-- same immutable V2 league member builds as the approved dashboard. Diagnosis
-- rules are conservative, mutually exclusive and evidence based. Existing
-- curated values always win; strict Orchard/OSIICS location/pathology codes are
-- considered next; then exactly one explicit text candidate may fill Unknown.
-- Conflicts remain Unknown and are emitted as adjudication candidates. Ambiguous
-- OSIICS/Orchard second-character mappings are never used as diagnoses.
with pinned as (
  select
    i.*,
    lower(trim(coalesce(
      sr.source_values ->> 'TimeLoss vs Medical Attention',
      sr.source_values ->> 'TimeLoss vs Medical Attention (Time Loss yes or no)',
      sr.source_values ->> 'TimeLoss vs Medical Attention(Yes = Time loss)',
      ''
    ))) as source_class,
    lower(trim(coalesce(sr.source_values ->> 'Match Type', ''))) as source_match_type,
    upper(trim(coalesce(
      nullif(sr.source_values ->> 'Orchard Code', ''),
      case when i.problem_type = 'injury' then sr.source_values ->> 'Illness Code' end,
      ''
    ))) as orchard_code,
    lower(trim(coalesce(sr.source_values ->> 'Description', ''))) as description_evidence,
    lower(trim(coalesce(sr.source_values ->> 'Injury Tissue Type/s', ''))) as tissue_evidence,
    lower(trim(coalesce(sr.source_values ->> 'Body Part', ''))) as body_evidence,
    lower(trim(coalesce(sr.source_values ->> 'Is Contact', ''))) as contact_source,
    lower(trim(concat_ws(' ',
      sr.source_values ->> 'Mechanism of Injury',
      sr.source_values ->> 'Mechanism Notes'
    ))) as mechanism_evidence,
    lower(trim(coalesce(sr.source_values ->> 'Nature of onset', ''))) as onset_evidence,
    lower(trim(concat_ws(' ',
      sr.source_values ->> 'Description',
      sr.source_values ->> 'Injury Tissue Type/s',
      sr.source_values ->> 'Body Part'
    ))) as clinical_evidence,
    lower(concat_ws(' ',
      sr.source_values ->> 'Description',
      sr.source_values ->> 'Orchard Code',
      sr.source_values ->> 'Injury Tissue Type/s',
      sr.source_values ->> 'Body Part'
    )) as legacy_evidence
  from curated.injuries i
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = i.curated_build_id
   and m.team_key = i.team_key and m.season = i.season
  join ingestion.source_rows sr on sr.id = i.source_row_id
  where i.season = '2024-25'
), descriptive as (
  select *
  from pinned
  where eligibility_status not in ('excluded_from_analysis', 'excluded_duplicate_adjudicated')
    and problem_type = 'injury'
    and (received_in_team_status is null or received_in_team_status not in ('other_team', 'club'))
    and (urc_match_scope is null or urc_match_scope <> 'non_urc_marker')
    and source_match_type <> 'italian elite championship'
), scoped_descriptive as (
  select d.team_key as scope_key, d.* from descriptive d
  union all
  select 'urc' as scope_key, d.* from descriptive d
), cohort as (
  select c.*, d.activity_context, d.contact_context, d.field_origins,
    d.source_class, d.source_match_type, d.orchard_code,
    d.description_evidence, d.tissue_evidence, d.body_evidence,
    d.contact_source, d.mechanism_evidence, d.onset_evidence,
    d.clinical_evidence, d.legacy_evidence
  from analysis.injury_cohort_by_build_v2 c
  join descriptive d on d.id = c.injury_id
), scoped_cohort as (
  select c.team_key as scope_key, c.* from cohort c
  union all
  select 'urc' as scope_key, c.* from cohort c
), body_candidates as (
  -- Precedence 1 is enforced later: a non-Unknown curated value is immutable.
  -- Precedence 2: a strict Orchard/OSIICS first-character body-area code.
  select d.scope_key, d.id, x.bucket, 'orchard_code'::text as evidence_source
  from scoped_descriptive d
  cross join lateral (values
    ('H', 'head'), ('N', 'neck'), ('S', 'shoulder'), ('U', 'upper_arm'),
    ('E', 'elbow'), ('R', 'forearm'), ('W', 'wrist'), ('P', 'hand'),
    ('C', 'chest'), ('D', 'thoracic_spine'), ('L', 'lumbosacral'),
    ('O', 'abdomen'), ('G', 'hip_groin'), ('T', 'thigh'), ('K', 'knee'),
    ('Q', 'lower_leg'), ('A', 'ankle'), ('F', 'foot'), ('Z', 'unspecified'),
    ('X', 'multiple')
  ) x(code_prefix, bucket)
  where coalesce(d.body_location, 'unknown') = 'unknown'
    and d.orchard_code ~ '^[HNSUERWPCDLOGTKQAFZX][A-Z]'
    and left(d.orchard_code, 1) = x.code_prefix
  union all
  -- Precedence 3: explicit anatomical terms. Patterns intentionally avoid
  -- radius/ulna/pelvis-only guesses where adjacent IOC regions may compete.
  select d.scope_key, d.id, x.bucket, 'explicit_text'::text
  from scoped_descriptive d
  cross join lateral (values
    ('head', d.clinical_evidence ~ '\m(concuss(ion|ed)?|brain injury|head injury|facial|skull|jaw)\M'),
    ('neck', d.clinical_evidence ~ '\m(neck|cervical)\M'),
    ('shoulder', d.clinical_evidence ~ '(\mshoulder\M|acromioclavicular|\mac joint\M|\ma/c joint\M|\mclavicle\M|scapul)'),
    ('upper_arm', d.clinical_evidence ~ '(\mupper arm\M|humerus|humeral)'),
    ('elbow', d.clinical_evidence ~ '\melbow\M'),
    ('forearm', d.clinical_evidence ~ '\mforearm\M'),
    ('wrist', d.clinical_evidence ~ '(\mwrist\M|carpal|scaphoid)'),
    ('hand', d.clinical_evidence ~ '(\mhand\M|\mfinger\M|\mthumb\M|metacarp)'),
    ('chest', d.clinical_evidence ~ '(\mchest\M|\mrib(s)?\M|sternum|sternal|pectoral)'),
    ('thoracic_spine', d.clinical_evidence ~ '(thoracic spine|costovertebral)'),
    ('lumbosacral', d.clinical_evidence ~ '(lumbar|lumbosacral|\msacrum\M|\msacral\M|\mcoccyx\M|\mbuttock\M)'),
    ('abdomen', d.clinical_evidence ~ '(\mabdomen\M|abdominal)'),
    ('hip_groin', d.clinical_evidence ~ '(\mhip\M|\mgroin\M|inguinal)'),
    ('thigh', d.clinical_evidence ~ '(\mthigh\M|hamstring|biceps femoris|semitend|semimembran|quadriceps|rectus femoris|\mvastus\M|\madductor\M)'),
    ('knee', d.clinical_evidence ~ '(\mknee\M|patell|menisc|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|cruciate)'),
    ('lower_leg', d.clinical_evidence ~ '(\mlower leg\M|\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M|achilles|\mshin\M)'),
    ('ankle', d.clinical_evidence ~ '(\mankle\M|syndesmo|high ankle sprain)'),
    ('foot', d.clinical_evidence ~ '(\mfoot\M|\mtoe\M|metatars|lisfranc|calcane|plantar)')
  ) x(bucket, matches)
  where coalesce(d.body_location, 'unknown') = 'unknown' and x.matches
), body_candidate_summary as (
  select scope_key, id, count(distinct bucket)::int as candidate_count,
    min(bucket) as sole_candidate,
    array_agg(distinct bucket order by bucket) as candidates,
    bool_or(evidence_source = 'orchard_code') as has_code_evidence,
    bool_or(evidence_source = 'explicit_text') as has_text_evidence
  from body_candidates
  group by scope_key, id
), body_stage as (
  select d.*,
    case
      when coalesce(d.body_location, 'unknown') <> 'unknown' then d.body_location
      when coalesce(bs.candidate_count, 0) = 1 then bs.sole_candidate
      else 'unknown'
    end as effective_body_location,
    case
      when coalesce(d.body_location, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'body_location', '') like 'manual_adjudication:%'
        then 'adjudicated'
      when coalesce(d.body_location, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'body_location', '') in ('source_reported', 'approved_mapping:source_reported')
        then 'source_reported'
      when coalesce(d.body_location, 'unknown') <> 'unknown'
        and (coalesce(d.field_origins ->> 'body_location', '') like 'inferred%'
          or coalesce(d.field_origins ->> 'body_location', '') like '%protocol_defined_inference%')
        then 'inferred'
      when coalesce(d.body_location, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'body_location', '') like 'mapped_from_%'
        then 'mapped'
      -- An unrecognized classified origin is never silently called mapped.
      when coalesce(d.body_location, 'unknown') <> 'unknown' then 'inferred'
      when coalesce(bs.candidate_count, 0) = 1 then 'inferred'
      else 'remaining_unknown'
    end as body_location_origin_group,
    case when coalesce(d.body_location, 'unknown') = 'unknown' and coalesce(bs.candidate_count, 0) = 1
      then concat('inferred_v3:', case
        when bs.has_code_evidence and bs.has_text_evidence then 'concordant_code_and_text'
        when bs.has_code_evidence then 'strict_orchard_body_code'
        else 'explicit_anatomical_text' end)
      else d.field_origins ->> 'body_location' end as effective_body_location_origin,
    coalesce(bs.candidate_count, 0) as body_candidate_count,
    coalesce(bs.candidates, array[]::text[]) as body_candidates
  from scoped_descriptive d
  left join body_candidate_summary bs on bs.scope_key = d.scope_key and bs.id = d.id
), tissue_candidates as (
  -- A strict second-character code is pathology evidence, never a diagnosis.
  select d.scope_key, d.id, x.bucket, 'orchard_code'::text as evidence_source
  from body_stage d
  cross join lateral (values
    ('M', 'muscle_injury'), ('T', 'tendinopathy'), ('F', 'fracture'),
    ('J', 'joint_sprain'), ('N', 'peripheral_nerve_injury'),
    ('H', 'contusion_superficial'), ('K', 'laceration'),
    ('O', 'internal_organ_trauma'), ('G', 'synovitis_capsulitis'),
    ('A', 'arthritis'), ('U', 'chronic_instability'), ('D', 'joint_sprain')
  ) x(code_character, bucket)
  where coalesce(d.injury_type, 'unknown') = 'unknown'
    and d.orchard_code ~ '^[HNSUERWPCDLOGTKQAFZX][MTFJNHKOGAUD]'
    and substring(d.orchard_code from 2 for 1) = x.code_character
  union all
  -- Explicit pathology terms are mutually exclusive at this layer; broad
  -- rules exclude their named subtypes and residual conflicts go to review.
  select d.scope_key, d.id, x.bucket, 'explicit_text'::text
  from body_stage d
  cross join lateral (values
    ('brain_spinal_cord_injury', d.clinical_evidence ~ '(concuss(ion|ed)?|brain injury|spinal cord injury)'),
    ('tendon_rupture', d.clinical_evidence ~ '(tendon|achilles).{0,18}(ruptur|complete tear)|(ruptur|complete tear).{0,18}(tendon|achilles)'),
    ('bone_stress_injury', d.clinical_evidence ~ '(stress fracture|bone stress|stress reaction|shin splints)'),
    ('bone_contusion', d.clinical_evidence ~ '(bone contusion|bony contusion|bone bruise)'),
    ('fracture', d.clinical_evidence ~ '(fractur|broken bone)' and d.clinical_evidence !~ '(stress fracture|bone stress|stress reaction)'),
    ('peripheral_nerve_injury', d.clinical_evidence ~ '(\mnerve\M|brachial plexus|burner/stinger|\mstinger\M)'),
    ('cartilage_injury', d.clinical_evidence ~ '(osteochondral|\mcartilage\M|labral|labrum|menisc)'),
    ('arthritis', d.clinical_evidence ~ '(osteoarthritis|\marthritis\M)'),
    ('tendinopathy', d.clinical_evidence ~ '(tendinopathy|tendinosis|tendon injury|tendon strain|plantar fasci)' and d.clinical_evidence !~ '(ruptur|complete tear)'),
    ('bursitis', d.clinical_evidence ~ '\mbursitis\M'),
    ('synovitis_capsulitis', d.clinical_evidence ~ '(\msynovitis\M|\mcapsulitis\M|\mimpingement\M)' and d.clinical_evidence !~ '\mbursitis\M'),
    ('chronic_instability', d.clinical_evidence ~ '(chronic instability|recurrent instability)'),
    ('joint_sprain', d.clinical_evidence ~ '(\msprain(ed)?\M|\mligament\M|disloc|sublux|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|syndesmo|lisfranc)'),
    ('muscle_contusion', d.clinical_evidence ~ '(muscle contusion|muscle haematoma|intramuscular haematoma)'),
    ('laceration', d.clinical_evidence ~ '\mlacerat(ion|ed)\M'),
    ('abrasion', d.clinical_evidence ~ '\mabrasion\M'),
    ('contusion_superficial', d.clinical_evidence ~ '(\mcontusion\M|haematoma|hematoma|\mbruis(e|ed|ing)\M|dead leg)' and d.clinical_evidence !~ '(muscle contusion|muscle haematoma|intramuscular haematoma|bone contusion|bony contusion|bone bruise)'),
    ('muscle_injury', d.clinical_evidence ~ '(muscle (strain|tear|rupture|injury)|\mstrain(ed)?\M|hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M)' and d.clinical_evidence !~ '(muscle contusion|muscle haematoma|intramuscular haematoma)')
  ) x(bucket, matches)
  where coalesce(d.injury_type, 'unknown') = 'unknown' and x.matches
), tissue_candidate_summary as (
  select scope_key, id, count(distinct bucket)::int as candidate_count,
    min(bucket) as sole_candidate,
    array_agg(distinct bucket order by bucket) as candidates,
    bool_or(evidence_source = 'orchard_code') as has_code_evidence,
    bool_or(evidence_source = 'explicit_text') as has_text_evidence
  from tissue_candidates
  group by scope_key, id
), tissue_stage as (
  select d.*,
    case
      when coalesce(d.injury_type, 'unknown') <> 'unknown' then d.injury_type
      when coalesce(ts.candidate_count, 0) = 1 then ts.sole_candidate
      else 'unknown'
    end as effective_injury_type,
    case
      when coalesce(d.injury_type, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'injury_type', '') like 'manual_adjudication:%'
        then 'adjudicated'
      when coalesce(d.injury_type, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'injury_type', '') in ('source_reported', 'approved_mapping:source_reported')
        then 'source_reported'
      when coalesce(d.injury_type, 'unknown') <> 'unknown'
        and (coalesce(d.field_origins ->> 'injury_type', '') like 'inferred%'
          or coalesce(d.field_origins ->> 'injury_type', '') like '%protocol_defined_inference%')
        then 'inferred'
      when coalesce(d.injury_type, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'injury_type', '') like 'mapped_from_%'
        then 'mapped'
      when coalesce(d.injury_type, 'unknown') <> 'unknown' then 'inferred'
      when coalesce(ts.candidate_count, 0) = 1 then 'inferred'
      else 'remaining_unknown'
    end as tissue_pathology_origin_group,
    case when coalesce(d.injury_type, 'unknown') = 'unknown' and coalesce(ts.candidate_count, 0) = 1
      then concat('inferred_v3:', case
        when ts.has_code_evidence and ts.has_text_evidence then 'concordant_code_and_text'
        when ts.has_code_evidence then 'strict_orchard_pathology_code'
        else 'explicit_pathology_text' end)
      else d.field_origins ->> 'injury_type' end as effective_injury_type_origin,
    coalesce(ts.candidate_count, 0) as tissue_candidate_count,
    coalesce(ts.candidates, array[]::text[]) as tissue_candidates
  from body_stage d
  left join tissue_candidate_summary ts on ts.scope_key = d.scope_key and ts.id = d.id
), contact_candidates as (
  select d.scope_key, d.id, x.contact_code
  from tissue_stage d
  cross join lateral (values
    ('contact', d.contact_source ~ '^(yes|contact)$'
      or d.mechanism_evidence ~ '(\mtackl(e|ed|ing)\M|collision with (a |another |opposition )?player|contact with (a |another |opposition )?player|\mruck\M|\mmaul\M|\mscrum\M)'),
    ('non_contact', d.contact_source ~ '^(no|non[- ]contact|non[- ]contact trauma|overuse.*|overload.*)$'
      or d.mechanism_evidence ~ '(non[- ]contact|without contact|change of direction|overuse|overload)'
      or (d.tissue_evidence = 'muscle strain/spasm' and d.onset_evidence = 'acute'))
  ) x(contact_code, matches)
  where coalesce(d.contact_context, 'unknown') = 'unknown' and x.matches
), contact_candidate_summary as (
  select scope_key, id, count(distinct contact_code)::int as candidate_count,
    min(contact_code) as sole_candidate,
    array_agg(distinct contact_code order by contact_code) as candidates
  from contact_candidates
  group by scope_key, id
), contact_stage as (
  select d.*,
    case
      when coalesce(d.contact_context, 'unknown') <> 'unknown' then d.contact_context
      when coalesce(cs.candidate_count, 0) = 1 then cs.sole_candidate
      else 'unknown'
    end as effective_contact_context,
    case
      when coalesce(d.contact_context, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'contact_context', '') like 'manual_adjudication:%'
        then 'adjudicated'
      when coalesce(d.contact_context, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'contact_context', '') in ('source_reported', 'approved_mapping:source_reported')
        then 'source_reported'
      when coalesce(d.contact_context, 'unknown') <> 'unknown'
        and (coalesce(d.field_origins ->> 'contact_context', '') like 'inferred%'
          or coalesce(d.field_origins ->> 'contact_context', '') like '%protocol_defined_inference%')
        then 'inferred'
      when coalesce(d.contact_context, 'unknown') <> 'unknown'
        and coalesce(d.field_origins ->> 'contact_context', '') like 'mapped_from_%'
        then 'mapped'
      when coalesce(d.contact_context, 'unknown') <> 'unknown' then 'inferred'
      when coalesce(cs.candidate_count, 0) = 1 then 'inferred'
      else 'remaining_unknown'
    end as contact_context_origin_group,
    case when coalesce(d.contact_context, 'unknown') = 'unknown' and coalesce(cs.candidate_count, 0) = 1
      then 'inferred_v3:explicit_contact_or_non_contact_evidence'
      else d.field_origins ->> 'contact_context' end as effective_contact_context_origin,
    coalesce(cs.candidate_count, 0) as contact_candidate_count,
    coalesce(cs.candidates, array[]::text[]) as contact_candidates
  from tissue_stage d
  left join contact_candidate_summary cs on cs.scope_key = d.scope_key and cs.id = d.id
), diagnosis_candidates as (
  -- Named-diagnosis precedence: named region-specific patterns, then named
  -- structures, then general pathology profiles. General rules explicitly
  -- exclude named patterns; any remaining multi-match is not resolved here.
  select d.scope_key, d.id, x.priority, x.code
  from contact_stage d
  cross join lateral (values
    (1, 'concussion', d.clinical_evidence ~ '(concuss(ion|ed)?|brain injury)'),
    (2, 'ac_joint_sprain', d.effective_body_location = 'shoulder'
      and d.clinical_evidence ~ '(acromioclavicular|\mac joint\M|\ma/c joint\M)'
      and d.clinical_evidence ~ '(sprain|separation|disloc)'),
    (3, 'syndesmosis_injury', d.effective_body_location = 'ankle'
      and d.clinical_evidence ~ '(syndesmo|high ankle sprain)' and d.clinical_evidence !~ 'fractur'),
    (4, 'lisfranc_injury', d.effective_body_location = 'foot' and d.clinical_evidence ~ '\mlisfranc\M'),
    (5, 'acl_injury', d.effective_body_location = 'knee' and d.clinical_evidence ~ '(\macl\M|anterior cruciate)'),
    (6, 'mcl_injury', d.effective_body_location = 'knee' and d.clinical_evidence ~ '(\mmcl\M|medial collateral)'),
    (7, 'pcl_lcl_injury', d.effective_body_location = 'knee' and d.clinical_evidence ~ '(\mpcl\M|\mlcl\M|posterior cruciate|lateral collateral)'),
    (8, 'meniscal_injury', d.effective_body_location = 'knee' and d.clinical_evidence ~ 'menisc'),
    (9, 'knee_ligament', d.effective_body_location = 'knee'
      and d.clinical_evidence ~ '(knee ligament|cruciate|collateral ligament)'
      and d.clinical_evidence !~ '(\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|anterior cruciate|posterior cruciate|medial collateral|lateral collateral)'),
    (10, 'ankle_ligament_sprain', d.effective_body_location = 'ankle'
      and d.clinical_evidence ~ '(sprain|ligament)'
      and d.clinical_evidence !~ '(syndesmo|high ankle sprain)'),
    (11, 'hamstring_strain', d.effective_body_location = 'thigh'
      and d.clinical_evidence ~ '(hamstring|biceps femoris|semitend|semimembran)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (12, 'calf_muscle', d.effective_body_location = 'lower_leg'
      and d.clinical_evidence ~ '(\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (13, 'quadriceps_muscle', d.effective_body_location = 'thigh'
      and d.clinical_evidence ~ '(quadriceps|rectus femoris|\mvastus\M)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (14, 'adductor_groin', d.effective_body_location in ('thigh', 'hip_groin')
      and d.clinical_evidence ~ '(\madductor\M|\mgroin\M)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (15, 'achilles_tendon', d.effective_body_location = 'lower_leg' and d.clinical_evidence ~ '\machilles\M'),
    (16, 'patellar_tendon', d.effective_body_location = 'knee' and d.clinical_evidence ~ 'patellar tendon'),
    (17, 'shoulder_labral', d.effective_body_location = 'shoulder' and d.clinical_evidence ~ '(labral|labrum)'),
    (18, 'shoulder_instability', d.effective_body_location = 'shoulder' and d.clinical_evidence ~ '(disloc|sublux|instability)'
      and d.clinical_evidence !~ '(acromioclavicular|\mac joint\M|\ma/c joint\M|labral|labrum)'),
    (19, 'fracture', d.clinical_evidence ~ '(fractur|broken bone)' and d.clinical_evidence !~ '\mlisfranc\M'),
    (20, 'contusion_haematoma', d.clinical_evidence ~ '(\mcontusion\M|haematoma|hematoma|dead leg)'
      and d.clinical_evidence !~ '(concuss(ion|ed)?|brain injury)'),
    (21, 'tendon_injury', d.clinical_evidence ~ '(\mtendon\M|tendinopathy|tendinosis)'
      and d.clinical_evidence !~ '(concuss|brain injury|acromioclavicular|\mac joint\M|\ma/c joint\M|syndesmo|high ankle sprain|lisfranc|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|cruciate|collateral|menisc|hamstring|biceps femoris|semitend|semimembran|\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\mvastus\M|\madductor\M|\mgroin\M|achilles|patellar tendon|labral|labrum|disloc|sublux|instability|fractur|broken bone|\mcontusion\M|haematoma|hematoma|dead leg)')
  ) x(priority, code, matches)
  where x.matches
), diagnosis_candidate_summary as (
  select scope_key, id, count(distinct code)::int as candidate_count,
    min(code) as sole_candidate,
    array_agg(distinct code order by code) as candidates
  from diagnosis_candidates
  group by scope_key, id
), legacy_diagnosis_candidates as (
  -- Draft.3 patterns are a fallback only. Count every matching pattern before
  -- selecting anything so ordered CASE precedence cannot hide ambiguity.
  select d.scope_key, d.id, x.code
  from contact_stage d
  cross join lateral (values
    ('concussion', d.legacy_evidence ~ '(concuss|brain injury)'),
    ('knee_ligament', d.body_location = 'knee' and d.legacy_evidence ~ '(acl|pcl|mcl|lcl|cruciate|collateral ligament|knee ligament)'),
    ('ankle_ligament_sprain', d.body_location = 'ankle' and d.legacy_evidence ~ '(sprain|ligament)'),
    ('hamstring_strain', d.legacy_evidence ~ '(hamstring|biceps femoris|semitend|semimembran)'),
    ('contusion_haematoma', d.legacy_evidence ~ '(contusion|haematoma|hematoma|dead leg)'),
    ('calf_muscle', d.legacy_evidence ~ '(calf|gastrocnemius|soleus)'),
    ('quadriceps_muscle', d.legacy_evidence ~ '(quadriceps|rectus femoris|vastus )'),
    ('adductor_groin', d.legacy_evidence ~ '(adductor|groin)'),
    ('shoulder_instability', d.body_location = 'shoulder' and d.legacy_evidence ~ '(disloc|sublux|instability)'),
    ('fracture', d.legacy_evidence ~ '(fracture|broken bone)'),
    ('tendon_injury', d.legacy_evidence ~ '(tendon|tendin)')
  ) x(code, matches)
  where x.matches
), legacy_diagnosis_candidate_summary as (
  select scope_key, id, count(distinct code)::int as candidate_count,
    min(code) as sole_candidate,
    array_agg(distinct code order by code) as candidates
  from legacy_diagnosis_candidates
  group by scope_key, id
), diagnosis_stage as (
  select d.*,
    case when coalesce(ds.candidate_count, 0) = 1 then ds.sole_candidate end as candidate_diagnosis_code,
    coalesce(ds.candidate_count, 0) as diagnosis_candidate_count,
    coalesce(ds.candidates, array[]::text[]) as diagnosis_candidates,
    case when coalesce(ls.candidate_count, 0) = 1 then ls.sole_candidate end as legacy_diagnosis_code,
    coalesce(ls.candidate_count, 0) as legacy_diagnosis_candidate_count,
    coalesce(ls.candidates, array[]::text[]) as legacy_diagnosis_candidates,
    array(
      select distinct candidate
      from unnest(coalesce(ds.candidates, array[]::text[]) || coalesce(ls.candidates, array[]::text[])) candidate
      order by candidate
    ) as diagnosis_ambiguity_candidates
  from contact_stage d
  left join diagnosis_candidate_summary ds on ds.scope_key = d.scope_key and ds.id = d.id
  left join legacy_diagnosis_candidate_summary ls on ls.scope_key = d.scope_key and ls.id = d.id
), classified_descriptive as (
  select d.*,
    case
      when legacy_diagnosis_candidate_count > 1 then null
      when diagnosis_candidate_count = 1 then candidate_diagnosis_code
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1 then legacy_diagnosis_code
    end as diagnosis_code,
    case
      when legacy_diagnosis_candidate_count <= 1
        and (diagnosis_candidate_count = 1 or (diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1))
        then 'inferred'
      else 'remaining_unknown'
    end as diagnosis_origin_group,
    case
      when legacy_diagnosis_candidate_count > 1 then null
      when diagnosis_candidate_count = 1 then 'inferred_v3:explicit_named_diagnosis_pattern'
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1 then 'inferred_v3:unique_legacy_fallback_pattern'
    end as diagnosis_origin
  from diagnosis_stage d
), classified_cohort as (
  select c.*, d.effective_body_location, d.effective_body_location_origin,
    d.effective_injury_type, d.effective_injury_type_origin,
    d.effective_contact_context, d.effective_contact_context_origin,
    d.diagnosis_code, d.diagnosis_origin
  from scoped_cohort c
  join classified_descriptive d on d.scope_key = c.scope_key and d.id = c.injury_id
), scopes as (
  select team_key as scope_key from analysis.league_member_releases_v2 where season = '2024-25'
  union all select 'urc'
), denominators as (
  select
    e.team_key as scope_key,
    e.total_hours,
    e.match_hours,
    e.training_hours
  from analysis.exposure_hours_by_build_v2 e
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = e.curated_build_id
   and m.team_key = e.team_key and m.season = e.season
  where e.season = '2024-25'
  union all
  select
    'urc',
    sum(e.total_hours),
    sum(e.match_hours),
    sum(e.training_hours)
  from analysis.exposure_hours_by_build_v2 e
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = e.curated_build_id
   and m.team_key = e.team_key and m.season = e.season
  where e.season = '2024-25'
), months as (
  select month_start::date
  from generate_series(date '2024-07-01', date '2025-06-01', interval '1 month') month_start
), settings as (
  select * from (values ('all', 1), ('match', 2), ('training', 3)) v(setting_code, sort_order)
), fixture_participations as (
  select f.match_date, teams.team_key, 20.0::numeric as exposure_hours
  from curated.fixtures f
  cross join lateral (values (f.home_team_key), (f.away_team_key)) teams(team_key)
  where f.season = '2024-25'
), match_month_exposure as (
  select team_key as scope_key, date_trunc('month', match_date)::date as month_start,
         sum(exposure_hours) as exposure_hours
  from fixture_participations
  group by team_key, date_trunc('month', match_date)
  union all
  select 'urc', date_trunc('month', match_date)::date, sum(exposure_hours)
  from fixture_participations
  group by date_trunc('month', match_date)
), monthly as (
  select
    s.scope_key,
    to_char(m.month_start, 'Mon YYYY') as month,
    st.setting_code,
    (select count(*)::int from scoped_descriptive d
      where d.scope_key = s.scope_key
        and date_trunc('month', d.date_injured)::date = m.month_start
        and (st.setting_code = 'all' or case d.activity_context
          when 'urc_match' then 'match' when 'match' then 'match'
          when 'training' then 'training' else 'unknown' end = st.setting_code)
    ) as recorded_injuries,
    (select count(*)::int from scoped_descriptive d
      where d.scope_key = s.scope_key
        and date_trunc('month', d.date_injured)::date = m.month_start
        and (coalesce(d.days_injured, 0) > 0 or d.source_class in ('time loss', 'yes', 'true', '1'))
        and (st.setting_code = 'all' or case d.activity_context
          when 'urc_match' then 'match' when 'match' then 'match'
          when 'training' then 'training' else 'unknown' end = st.setting_code)
    ) as time_loss_injuries,
    (select count(*)::int from scoped_cohort c
      where c.scope_key = s.scope_key
        and date_trunc('month', c.date_injured)::date = m.month_start
        and c.is_time_loss
        and (st.setting_code = 'all' or c.setting_code = st.setting_code)
    ) as rate_time_loss_injuries,
    case when st.setting_code = 'match' then coalesce(mx.exposure_hours, 0) else null end as exposure_hours
  from scopes s
  cross join months m
  cross join settings st
  left join match_month_exposure mx
    on mx.scope_key = s.scope_key and mx.month_start = m.month_start
  group by s.scope_key, m.month_start, st.setting_code, st.sort_order, mx.exposure_hours
), consequence as (
  select
    scope_key,
    count(*)::int as recorded_injuries,
    count(*) filter (where is_time_loss)::int as positive_day_cases,
    count(*) filter (where severity_code = 'zero_days_medical_attention_only')::int as zero_day_cases,
    count(*) filter (where not is_time_loss and severity_code = 'unknown_or_censored')::int as duration_unknown_or_censored,
    count(*) filter (where source_class in ('time loss', 'yes', 'true', '1'))::int as source_reported_time_loss,
    count(*) filter (where source_class in ('time loss', 'yes', 'true', '1') and not is_time_loss)::int as source_reported_time_loss_without_positive_days,
    count(*) filter (where source_class in ('medical attention', 'no', 'false', '0'))::int as source_reported_medical_attention,
    count(*) filter (where source_class = '')::int as source_class_unknown
  from scoped_cohort
  group by scope_key
), rate_settings as (
  select
    s.scope_key,
    st.setting_code,
    case st.setting_code when 'all' then 'Overall' when 'match' then 'Match' else 'Training' end as label,
    count(*) filter (
      where c.is_time_loss and (st.setting_code = 'all' or c.setting_code = st.setting_code)
    )::int as time_loss_injuries,
    coalesce(sum(c.days_lost) filter (
      where c.is_time_loss and (st.setting_code = 'all' or c.setting_code = st.setting_code)
    ), 0)::numeric as days_lost,
    case st.setting_code when 'all' then d.total_hours
      when 'match' then d.match_hours else d.training_hours end as exposure_hours
  from scopes s
  cross join settings st
  join scoped_cohort c on c.scope_key = s.scope_key
  join denominators d on d.scope_key = s.scope_key
  group by s.scope_key, st.setting_code, st.sort_order, d.total_hours, d.match_hours, d.training_hours
), severity as (
  select
    scope_key,
    severity_code as key,
    case severity_code
      when 'zero_days_medical_attention_only' then '0 days recorded'
      when 'one_day' then '1 day'
      when 'two_to_three_days' then '2–3 days'
      when 'four_to_seven_days' then '4–7 days'
      when 'eight_to_twenty_eight_days' then '8–28 days'
      when 'greater_than_twenty_eight_days' then '>28 days'
      else 'Unknown / censored'
    end as label,
    count(*)::int as recorded_injuries,
    count(*) filter (where is_time_loss)::int as time_loss_injuries,
    coalesce(sum(days_lost), 0)::numeric as days_lost
  from scoped_cohort
  group by scope_key, severity_code
), match_scope as (
  select
    scope_key,
    count(*) filter (where is_time_loss and setting_code = 'match')::int as positive_day_match_cases,
    count(*) filter (
      where is_time_loss and setting_code = 'match'
        and (activity_context = 'urc_match' or source_match_type in ('urc', 'united rugby championship'))
    )::int as confirmed_urc_match_cases,
    count(*) filter (
      where is_time_loss and setting_code = 'match'
        and not (activity_context = 'urc_match' or source_match_type in ('urc', 'united rugby championship'))
    )::int as retained_generic_match_cases
  from scoped_cohort
  group by scope_key
), descriptive_consequence as (
  select
    scope_key,
    count(*)::int as recorded_injuries,
    count(*) filter (where date_injured is null)::int as undated_injuries,
    count(*) filter (where date_injured is not null and date_injured not between date '2024-07-01' and date '2025-06-30')::int as outside_season_date_injuries,
    count(*) filter (
      where coalesce(days_injured, 0) > 0 or source_class in ('time loss', 'yes', 'true', '1')
    )::int as time_loss_injuries,
    count(*) filter (
      where not (coalesce(days_injured, 0) > 0 or source_class in ('time loss', 'yes', 'true', '1'))
        and (
          source_class in ('medical attention', 'no', 'false', '0')
          or (days_injured = 0 and is_closed is true)
        )
    )::int as medical_attention_only,
    count(*) filter (
      where not (coalesce(days_injured, 0) > 0 or source_class in ('time loss', 'yes', 'true', '1'))
        and not (
          source_class in ('medical attention', 'no', 'false', '0')
          or (days_injured = 0 and is_closed is true)
        )
    )::int as consequence_unknown
  from scoped_descriptive
  group by scope_key
), contact as (
  select
    s.scope_key,
    st.setting_code,
    c.effective_contact_context as contact_code,
    count(*) filter (where st.setting_code = 'all' or c.setting_code = st.setting_code)::int as recorded_injuries,
    count(*) filter (
      where c.is_time_loss and (st.setting_code = 'all' or c.setting_code = st.setting_code)
    )::int as time_loss_injuries
  from scopes s
  cross join settings st
  join classified_cohort c on c.scope_key = s.scope_key
  group by s.scope_key, st.setting_code, c.effective_contact_context
), diagnosis_labels as (
  select * from (values
    ('concussion', 'Concussion', 1),
    ('ac_joint_sprain', 'AC joint sprain / separation', 2),
    ('syndesmosis_injury', 'Syndesmosis injury', 3),
    ('lisfranc_injury', 'Lisfranc injury', 4),
    ('acl_injury', 'ACL injury', 5),
    ('mcl_injury', 'MCL injury', 6),
    ('pcl_lcl_injury', 'PCL / LCL injury', 7),
    ('meniscal_injury', 'Meniscal injury', 8),
    ('knee_ligament', 'Knee ligament injury', 9),
    ('ankle_ligament_sprain', 'Ankle ligament sprain', 10),
    ('hamstring_strain', 'Hamstring strain', 11),
    ('calf_muscle', 'Calf muscle injury', 12),
    ('quadriceps_muscle', 'Quadriceps muscle injury', 13),
    ('adductor_groin', 'Adductor / groin injury', 14),
    ('achilles_tendon', 'Achilles tendon injury', 15),
    ('patellar_tendon', 'Patellar tendon injury', 16),
    ('shoulder_labral', 'Shoulder labral injury', 17),
    ('shoulder_instability', 'Shoulder instability', 18),
    ('fracture', 'Fracture', 19),
    ('contusion_haematoma', 'Contusion / haematoma', 20),
    ('tendon_injury', 'Tendon injury', 21)
  ) v(code, label, sort_order)
), diagnosis_profiles as (
  select
    d.scope_key,
    st.setting_code,
    d.diagnosis_code,
    l.label,
    count(*)::int as time_loss_injuries,
    sum(d.days_lost)::numeric as days_lost
  from classified_cohort d
  join diagnosis_labels l on l.code = d.diagnosis_code
  cross join settings st
  where d.is_time_loss
    and (st.setting_code = 'all' or d.setting_code = st.setting_code)
  group by d.scope_key, st.setting_code, d.diagnosis_code, l.label, l.sort_order
), diagnosis_coverage as (
  select
    scope_key,
    count(*) filter (where is_time_loss and diagnosis_code is not null)::int as classified_time_loss_injuries,
    count(*) filter (where is_time_loss)::int as eligible_time_loss_injuries
  from classified_cohort
  group by scope_key
), inference_coverage as (
  select scope_key, jsonb_build_object(
    'cohort', 'attributed_descriptive_cases',
    'body_location', jsonb_build_object(
      'source_reported', count(*) filter (where body_location_origin_group = 'source_reported'),
      'mapped', count(*) filter (where body_location_origin_group = 'mapped'),
      'inferred', count(*) filter (where body_location_origin_group = 'inferred'),
      'adjudicated', count(*) filter (where body_location_origin_group = 'adjudicated'),
      'remaining_unknown', count(*) filter (where body_location_origin_group = 'remaining_unknown'),
      'unknown_before_v3', count(*) filter (where coalesce(body_location, 'unknown') = 'unknown'),
      'classified', count(*) filter (where effective_body_location <> 'unknown'),
      'total', count(*)
    ),
    'tissue_pathology', jsonb_build_object(
      'source_reported', count(*) filter (where tissue_pathology_origin_group = 'source_reported'),
      'mapped', count(*) filter (where tissue_pathology_origin_group = 'mapped'),
      'inferred', count(*) filter (where tissue_pathology_origin_group = 'inferred'),
      'adjudicated', count(*) filter (where tissue_pathology_origin_group = 'adjudicated'),
      'remaining_unknown', count(*) filter (where tissue_pathology_origin_group = 'remaining_unknown'),
      'unknown_before_v3', count(*) filter (where coalesce(injury_type, 'unknown') = 'unknown'),
      'classified', count(*) filter (where effective_injury_type <> 'unknown'),
      'total', count(*)
    ),
    'diagnosis', jsonb_build_object(
      'source_reported', 0,
      'mapped', 0,
      'inferred', count(*) filter (where diagnosis_origin_group = 'inferred'),
      'adjudicated', 0,
      'remaining_unknown', count(*) filter (where diagnosis_origin_group = 'remaining_unknown'),
      'unknown_before_v3', count(*) filter (where legacy_diagnosis_candidate_count <> 1),
      'classified', count(*) filter (where diagnosis_code is not null),
      'total', count(*)
    ),
    'contact_context', jsonb_build_object(
      'source_reported', count(*) filter (where contact_context_origin_group = 'source_reported'),
      'mapped', count(*) filter (where contact_context_origin_group = 'mapped'),
      'inferred', count(*) filter (where contact_context_origin_group = 'inferred'),
      'adjudicated', count(*) filter (where contact_context_origin_group = 'adjudicated'),
      'remaining_unknown', count(*) filter (where contact_context_origin_group = 'remaining_unknown'),
      'unknown_before_v3', count(*) filter (where coalesce(contact_context, 'unknown') = 'unknown'),
      'classified', count(*) filter (where effective_contact_context <> 'unknown'),
      'total', count(*)
    )
  ) as coverage
  from classified_descriptive
  group by scope_key
), origin_rows as (
  select scope_key, 'body_location'::text as field,
    coalesce(nullif(effective_body_location_origin, ''), '<missing>') as origin,
    body_location_origin_group as origin_class
  from classified_descriptive
  union all
  select scope_key, 'tissue_pathology',
    coalesce(nullif(effective_injury_type_origin, ''), '<missing>'),
    tissue_pathology_origin_group
  from classified_descriptive
  union all
  select scope_key, 'diagnosis',
    coalesce(nullif(diagnosis_origin, ''), '<missing>'),
    diagnosis_origin_group
  from classified_descriptive
  union all
  select scope_key, 'contact_context',
    coalesce(nullif(effective_contact_context_origin, ''), '<missing>'),
    contact_context_origin_group
  from classified_descriptive
), origin_class_counts as (
  select scope_key, field, origin, origin_class, count(*)::int as count
  from origin_rows
  group by scope_key, field, origin, origin_class
), adjudication_candidates as (
  select id::text as id, scope_key as team_key, 'body_location'::text as field,
    to_jsonb(body_candidates) as candidate_values,
    concat('signals ', array_to_string(body_candidates, '/')) as evidence_fragment,
    'Conflicting IOC body-location signals; no precedence is clinically safe.'::text as why_ambiguous,
    null::int as legacy_pattern_match_count,
    null::int as draft_pattern_match_count,
    'unknown'::text as resulting_value
  from classified_descriptive where scope_key <> 'urc' and body_candidate_count > 1
  union all
  select id::text, scope_key, 'tissue_pathology', to_jsonb(tissue_candidates),
    concat('signals ', array_to_string(tissue_candidates, '/')),
    'Conflicting IOC tissue/pathology signals; source code and text do not resolve uniquely.',
    null::int, null::int, 'unknown'
  from classified_descriptive where scope_key <> 'urc' and tissue_candidate_count > 1
  union all
  select id::text, scope_key, 'contact_context', to_jsonb(contact_candidates),
    concat('signals ', array_to_string(contact_candidates, '/')),
    'Both contact and non-contact signals are present.',
    null::int, null::int, 'unknown'
  from classified_descriptive where scope_key <> 'urc' and contact_candidate_count > 1
  union all
  select id::text, scope_key, 'diagnosis', to_jsonb(diagnosis_ambiguity_candidates),
    concat('signals ', array_to_string(diagnosis_ambiguity_candidates, '/')),
    'Multiple current or legacy named diagnosis patterns match; none is selected.',
    legacy_diagnosis_candidate_count,
    diagnosis_candidate_count,
    coalesce(diagnosis_code, 'unknown')
  from classified_descriptive
  where scope_key <> 'urc'
    and (diagnosis_candidate_count > 1 or legacy_diagnosis_candidate_count > 1)
), supplements as (
  select jsonb_build_object(
    'status', 'draft_not_for_release',
    'season', '2024-25',
    'team_key', s.scope_key,
    'rule_version', 'urc-diagnosis-inference-v3-draft.5',
    'generated_at', to_char(statement_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'consequence_summary', to_jsonb(c) - 'scope_key',
    'descriptive_consequence_summary', (to_jsonb(ds) - 'scope_key') || jsonb_build_object(
      'rate_ineligible_time_loss_injuries', ds.time_loss_injuries
        - (c.positive_day_cases + c.source_reported_time_loss_without_positive_days)
    ),
    'rate_setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', r.setting_code,
        'label', r.label,
        'time_loss_injuries', r.time_loss_injuries,
        'days_lost', r.days_lost,
        'exposure_hours', r.exposure_hours,
        'incidence_per_1000h', r.time_loss_injuries / nullif(r.exposure_hours, 0) * 1000,
        'burden_per_1000h', r.days_lost / nullif(r.exposure_hours, 0) * 1000,
        'mean_severity_days', r.days_lost / nullif(r.time_loss_injuries, 0)
      ) order by case r.setting_code when 'all' then 1 when 'match' then 2 else 3 end)
      from rate_settings r where r.scope_key = s.scope_key
    ), '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(to_jsonb(v) - 'scope_key' order by case v.key
        when 'zero_days_medical_attention_only' then 1 when 'one_day' then 2
        when 'two_to_three_days' then 3 when 'four_to_seven_days' then 4
        when 'eight_to_twenty_eight_days' then 5 when 'greater_than_twenty_eight_days' then 6 else 7 end)
      from severity v where v.scope_key = s.scope_key
    ), '[]'::jsonb),
    'match_scope_summary', to_jsonb(ms) - 'scope_key',
    'monthly_by_setting', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', m.month,
        'setting', m.setting_code,
        'recorded_injuries', m.recorded_injuries,
        'time_loss_injuries', m.time_loss_injuries,
        'rate_time_loss_injuries', m.rate_time_loss_injuries,
        'exposure_hours', m.exposure_hours,
        'incidence_per_1000h', case when m.exposure_hours > 0
          then m.rate_time_loss_injuries::numeric / m.exposure_hours * 1000 else null end
      ) order by to_date(m.month, 'Mon YYYY'),
        case m.setting_code when 'all' then 1 when 'match' then 2 else 3 end)
      from monthly m where m.scope_key = s.scope_key
    ), '[]'::jsonb),
    'contact_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.contact_code,
        'label', case x.contact_code when 'contact' then 'Contact'
          when 'non_contact' then 'Non-contact' else 'Unknown' end,
        'setting', x.setting_code,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries
      ) order by case x.setting_code when 'all' then 1 when 'match' then 2 else 3 end,
        case x.contact_code when 'contact' then 1 when 'non_contact' then 2 else 3 end)
      from contact x
      where x.scope_key = s.scope_key
        and (x.recorded_injuries > 0 or x.time_loss_injuries > 0)
    ), '[]'::jsonb),
    'common_injuries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dimension', 'injury_profile',
        'code', p.diagnosis_code,
        'label', p.label,
        'setting', p.setting_code,
        'time_loss_injuries', p.time_loss_injuries,
        'days_lost', p.days_lost,
        'exposure_hours', case p.setting_code when 'all' then d.total_hours
          when 'match' then d.match_hours when 'training' then d.training_hours else null end,
        'incidence_per_1000h', case p.setting_code when 'all' then p.time_loss_injuries / nullif(d.total_hours, 0) * 1000
          when 'match' then p.time_loss_injuries / nullif(d.match_hours, 0) * 1000
          when 'training' then p.time_loss_injuries / nullif(d.training_hours, 0) * 1000 else null end,
        'burden_per_1000h', case p.setting_code when 'all' then p.days_lost / nullif(d.total_hours, 0) * 1000
          when 'match' then p.days_lost / nullif(d.match_hours, 0) * 1000
          when 'training' then p.days_lost / nullif(d.training_hours, 0) * 1000 else null end,
        'mean_severity_days', p.days_lost / nullif(p.time_loss_injuries, 0)
      ) order by case p.setting_code when 'all' then 1 when 'match' then 2 else 3 end,
        p.time_loss_injuries desc, p.diagnosis_code)
      from diagnosis_profiles p
      join denominators d on d.scope_key = p.scope_key
      where p.scope_key = s.scope_key
    ), '[]'::jsonb),
    'diagnosis_coverage', to_jsonb(dc) - 'scope_key',
    'inference_coverage', ic.coverage
  ) as supplement
  from scopes s
  join consequence c on c.scope_key = s.scope_key
  join descriptive_consequence ds on ds.scope_key = s.scope_key
  join diagnosis_coverage dc on dc.scope_key = s.scope_key
  join inference_coverage ic on ic.scope_key = s.scope_key
  join match_scope ms on ms.scope_key = s.scope_key
)
select jsonb_build_object(
  'status', 'draft_not_for_release',
  'supplements', jsonb_agg(supplement order by supplement ->> 'team_key'),
  'origin_class_counts', (
    select coalesce(jsonb_agg(to_jsonb(o) order by o.scope_key, o.field, o.origin, o.origin_class), '[]'::jsonb)
    from origin_class_counts o
  ),
  'adjudication_candidates', (
    select coalesce(jsonb_agg(to_jsonb(a) order by a.team_key, a.id, a.field), '[]'::jsonb)
    from adjudication_candidates a
  )
) as dashboard_v3_preview
from supplements;
