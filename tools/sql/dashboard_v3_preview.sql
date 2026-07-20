-- Read-only V3 candidate aggregates for local dashboard review.
--
-- This query never changes database state. It is deliberately pinned to the
-- same immutable V2 league member builds as the approved dashboard. Diagnosis
-- rules are conservative and evidence based. Existing curated values always
-- win; exact Orchard/OSIICS mappings are considered next; then explicit text
-- may name a diagnosis. Named candidates are reconciled at display-bucket
-- granularity, so multiple knee-ligament subtypes remain one diagnosis. Rows
-- without a named diagnosis fall back only to the compound of their already-
-- standardised body and IOC tissue/pathology buckets. Cross-bucket conflicts
-- remain Unknown and are emitted as adjudication candidates. Ambiguous
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
    sr.source_values,
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
), eligible_descriptive as (
  select *
  from pinned
  where eligibility_status not in ('excluded_from_analysis', 'excluded_duplicate_adjudicated')
    and problem_type = 'injury'
    and (received_in_team_status is null or received_in_team_status not in ('other_team', 'club'))
    and (urc_match_scope is null or urc_match_scope <> 'non_urc_marker')
    and source_match_type <> 'italian elite championship'
), outside_season_dates as (
  select team_key as scope_key, count(*)::int as outside_season_date_injuries
  from eligible_descriptive
  where date_injured is not null
    and date_injured not between date '2024-07-01' and date '2025-06-30'
  group by team_key
  union all
  select 'urc', count(*)::int
  from eligible_descriptive
  where date_injured is not null
    and date_injured not between date '2024-07-01' and date '2025-06-30'
), descriptive as (
  -- Draft.9 preview cohort: retain season-attributed undated injuries, but
  -- exclude dated records outside the fixed season sanity bound.
  select *
  from eligible_descriptive
  where date_injured is null
    or date_injured between date '2024-07-01' and date '2025-06-30'
), scoped_descriptive as (
  select d.team_key as scope_key, d.* from descriptive d
  union all
  select 'urc' as scope_key, d.* from descriptive d
), reliable_concussion_text as (
  -- Inventory-led allowlist. `Games Missed` is deliberately absent: its only
  -- SRC hit means competition context, not sport-related concussion.
  select d.scope_key, d.id, e.key as evidence_field,
    lower(trim(coalesce(e.value, ''))) as evidence_value
  from scoped_descriptive d
  cross join lateral jsonb_each_text(d.source_values) e
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
), concussion_evidence_rows as (
  select d.scope_key, d.id, 'mapped'::text as evidence_class,
    'Orchard Code'::text as evidence_field
  from scoped_descriptive d
  where d.orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')
  union all
  select t.scope_key, t.id, 'inferred', t.evidence_field
  from reliable_concussion_text t
), concussion_evidence_summary as (
  select scope_key, id,
    bool_or(evidence_class = 'mapped') as has_exact_code,
    bool_or(evidence_class = 'inferred') as has_positive_text,
    array_agg(distinct evidence_field order by evidence_field) as evidence_fields
  from concussion_evidence_rows
  group by scope_key, id
), descriptive_with_concussion as (
  select d.*,
    coalesce(c.has_exact_code, false) as concussion_has_exact_code,
    coalesce(c.has_positive_text, false) as concussion_has_positive_text,
    c.id is not null as has_concussion_evidence,
    coalesce(c.evidence_fields, array[]::text[]) as concussion_evidence_fields
  from scoped_descriptive d
  left join concussion_evidence_summary c
    on c.scope_key = d.scope_key and c.id = d.id
), cohort as (
  -- Deliberately bypass the frozen exposure-windowed V2 view. Draft.9 rates
  -- use every eligible injury inside the fixed season bound plus undated
  -- season-attributed injuries, so numerator and denominator share one rule.
  select
    d.id as injury_id,
    d.curated_build_id,
    d.team_key,
    d.season,
    d.date_injured,
    d.days_injured,
    coalesce(d.days_injured, 0) as days_lost,
    coalesce(d.days_injured, 0) > 0 as is_time_loss,
    case d.activity_context
      when 'urc_match' then 'match'
      when 'match' then 'match'
      when 'training' then 'training'
      else 'unknown'
    end as setting_code,
    coalesce(d.severity_category, 'unknown_or_censored') as severity_code,
    d.activity_context,
    d.contact_context,
    d.field_origins,
    d.source_class,
    d.source_match_type,
    d.orchard_code,
    d.description_evidence,
    d.tissue_evidence,
    d.body_evidence,
    d.contact_source,
    d.mechanism_evidence,
    d.onset_evidence,
    d.clinical_evidence,
    d.legacy_evidence
  from descriptive d
), scoped_cohort as (
  select c.team_key as scope_key, c.* from cohort c
  union all
  select 'urc' as scope_key, c.* from cohort c
), body_candidates as (
  -- Precedence 1 is enforced later: a non-Unknown curated value is immutable.
  -- Precedence 2: a strict Orchard/OSIICS first-character body-area code.
  select d.scope_key, d.id, x.bucket, 'orchard_code'::text as evidence_source
  from descriptive_with_concussion d
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
  from descriptive_with_concussion d
  cross join lateral (values
    ('head', d.has_concussion_evidence or d.clinical_evidence ~ '(head injury|facial|skull|jaw)'),
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
    ('hip_groin', d.clinical_evidence ~ '(\mhip\M|\mgroin\M|inguinal|\madductor\M)'),
    ('thigh', d.clinical_evidence ~ '(\mthigh\M|hamstring|biceps femoris|semitend|semimembran|quadriceps|rectus femoris|\mvastus\M)'),
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
      when coalesce(bs.candidate_count, 0) = 1 and bs.has_code_evidence then 'mapped'
      when coalesce(bs.candidate_count, 0) = 1 then 'inferred'
      else 'remaining_unknown'
    end as body_location_origin_group,
    case when coalesce(d.body_location, 'unknown') = 'unknown' and coalesce(bs.candidate_count, 0) = 1
      then case
        when bs.has_code_evidence then 'mapped_from_strict_orchard_body_code'
        else 'inferred_v3:explicit_anatomical_text' end
      else d.field_origins ->> 'body_location' end as effective_body_location_origin,
    coalesce(bs.candidate_count, 0) as body_candidate_count,
    coalesce(bs.candidates, array[]::text[]) as body_candidates
  from descriptive_with_concussion d
  left join body_candidate_summary bs on bs.scope_key = d.scope_key and bs.id = d.id
), tissue_candidates as (
  -- Exact observed HN concussion codes outrank the otherwise ambiguous generic
  -- second-character N mapping. They are deterministic mappings, not inference.
  select d.scope_key, d.id, 'brain_spinal_cord_injury'::text as bucket,
    'exact_orchard_concussion_code'::text as evidence_source
  from body_stage d
  where coalesce(d.injury_type, 'unknown') = 'unknown'
    and d.concussion_has_exact_code
  union all
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
    and not d.concussion_has_exact_code
    and d.orchard_code ~ '^[HNSUERWPCDLOGTKQAFZX][MTFJNHKOGAUD]'
    and substring(d.orchard_code from 2 for 1) = x.code_character
  union all
  -- Explicit pathology terms are mutually exclusive at this layer; broad
  -- rules exclude their named subtypes and residual conflicts go to review.
  select d.scope_key, d.id, x.bucket, 'explicit_text'::text
  from body_stage d
  cross join lateral (values
    ('brain_spinal_cord_injury', d.has_concussion_evidence or d.clinical_evidence ~ 'spinal cord injury'),
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
    bool_or(evidence_source in ('orchard_code', 'exact_orchard_concussion_code')) as has_code_evidence,
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
      when coalesce(ts.candidate_count, 0) = 1 and ts.has_code_evidence then 'mapped'
      when coalesce(ts.candidate_count, 0) = 1 then 'inferred'
      else 'remaining_unknown'
    end as tissue_pathology_origin_group,
    case when coalesce(d.injury_type, 'unknown') = 'unknown' and coalesce(ts.candidate_count, 0) = 1
      then case
        when ts.has_code_evidence then 'mapped_from_strict_orchard_pathology_code'
        else 'inferred_v3:explicit_pathology_text' end
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
), diagnosis_bucket_rule_cases as (
  select * from (values
    ('00000000-0000-0000-0000-000000000001'::uuid, 'acl', 'knee', 'acl injury', 'knee_ligament', 1),
    ('00000000-0000-0000-0000-000000000002'::uuid, 'mcl', 'knee', 'mcl injury', 'knee_ligament', 1),
    ('00000000-0000-0000-0000-000000000003'::uuid, 'pcl', 'knee', 'pcl injury', 'knee_ligament', 1),
    ('00000000-0000-0000-0000-000000000004'::uuid, 'lcl', 'knee', 'lcl injury', 'knee_ligament', 1),
    ('00000000-0000-0000-0000-000000000005'::uuid, 'cruciate', 'knee', 'cruciate injury', 'knee_ligament', 1),
    ('00000000-0000-0000-0000-000000000006'::uuid, 'collateral', 'knee', 'collateral injury', 'knee_ligament', 1),
    ('00000000-0000-0000-0000-000000000007'::uuid, 'within_bucket_acl_pcl', 'knee', 'acl and pcl injury', 'knee_ligament', 2),
    ('00000000-0000-0000-0000-000000000008'::uuid, 'cross_bucket_knee_fracture', 'knee', 'acl fracture', null, 2)
  ) v(id, case_name, effective_body_location, clinical_evidence, expected_bucket, expected_subtype_count)
), diagnosis_rule_inputs as (
  select d.scope_key, d.id, false as is_synthetic, null::text as case_name,
    d.has_concussion_evidence, d.effective_body_location, d.clinical_evidence,
    d.effective_injury_type, d.description_evidence,
    null::text as expected_bucket, null::int as expected_subtype_count
  from contact_stage d
  union all
  select '__synthetic__', c.id, true, c.case_name,
    false, c.effective_body_location, c.clinical_evidence,
    'unknown', c.clinical_evidence,
    c.expected_bucket, c.expected_subtype_count
  from diagnosis_bucket_rule_cases c
), all_diagnosis_candidates as (
  -- Named-diagnosis precedence: named region-specific patterns, then named
  -- structures, then general pathology profiles. General rules explicitly
  -- exclude named patterns; any remaining multi-match is not resolved here.
  select d.scope_key, d.id, d.is_synthetic, d.case_name,
    d.expected_bucket, d.expected_subtype_count,
    x.priority, x.diagnosis_code, x.diagnosis_subtype, x.profile_code
  from diagnosis_rule_inputs d
  cross join lateral (values
    (1, 'concussion', 'concussion', 'head__brain_spinal_cord_injury', d.has_concussion_evidence and d.effective_body_location = 'head'),
    (2, 'ac_joint_sprain', 'ac_joint_sprain', 'shoulder__joint_sprain', d.effective_body_location = 'shoulder'
      and d.clinical_evidence ~ '(acromioclavicular|\mac joint\M|\ma/c joint\M)'
      and d.clinical_evidence ~ '(sprain|separation|disloc)'),
    (3, 'syndesmosis_injury', 'syndesmosis_injury', 'ankle__joint_sprain', d.effective_body_location = 'ankle'
      and d.clinical_evidence ~ '(syndesmo|high ankle sprain)' and d.clinical_evidence !~ 'fractur'),
    (4, 'lisfranc_injury', 'lisfranc_injury', 'foot__joint_sprain', d.effective_body_location = 'foot' and d.clinical_evidence ~ '\mlisfranc\M'),
    (5, 'knee_ligament', 'acl', 'knee__joint_sprain', d.effective_body_location = 'knee' and d.clinical_evidence ~ '(\macl\M|anterior cruciate)'),
    (6, 'knee_ligament', 'mcl', 'knee__joint_sprain', d.effective_body_location = 'knee' and d.clinical_evidence ~ '(\mmcl\M|medial collateral)'),
    (7, 'knee_ligament', 'pcl', 'knee__joint_sprain', d.effective_body_location = 'knee' and d.clinical_evidence ~ '(\mpcl\M|posterior cruciate)'),
    (8, 'knee_ligament', 'lcl', 'knee__joint_sprain', d.effective_body_location = 'knee' and d.clinical_evidence ~ '(\mlcl\M|lateral collateral)'),
    (9, 'meniscal_injury', 'meniscal_injury', 'knee__cartilage_injury', d.effective_body_location = 'knee' and d.clinical_evidence ~ 'menisc'),
    (10, 'knee_ligament', 'unspecified', 'knee__joint_sprain', d.effective_body_location = 'knee'
      and d.clinical_evidence ~ '(knee ligament|\mcruciate\M|\mcollateral\M)'
      and d.clinical_evidence !~ '(\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|anterior cruciate|posterior cruciate|medial collateral|lateral collateral)'),
    (11, 'ankle_ligament_sprain', 'ankle_ligament_sprain', 'ankle__joint_sprain', d.effective_body_location = 'ankle'
      and d.clinical_evidence ~ '(sprain|ligament)'
      and d.clinical_evidence !~ '(syndesmo|high ankle sprain)'),
    (12, 'hamstring_strain', 'hamstring_strain', 'thigh__muscle_injury', d.effective_body_location = 'thigh'
      and d.clinical_evidence ~ '(hamstring|biceps femoris|semitend|semimembran)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (13, 'calf_muscle', 'calf_muscle', 'lower_leg__muscle_injury', d.effective_body_location = 'lower_leg'
      and d.clinical_evidence ~ '(\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (14, 'quadriceps_muscle', 'quadriceps_muscle', 'thigh__muscle_injury', d.effective_body_location = 'thigh'
      and d.clinical_evidence ~ '(quadriceps|rectus femoris|\mvastus\M)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (15, 'adductor_groin', 'adductor_groin', 'hip_groin__muscle_injury', d.effective_body_location in ('thigh', 'hip_groin')
      and d.clinical_evidence ~ '(\madductor\M|\mgroin\M)'
      and (d.effective_injury_type = 'muscle_injury' or d.description_evidence ~ '(strain|tear|ruptur)')),
    (16, 'achilles_tendon', 'achilles_tendon', 'lower_leg__tendinopathy', d.effective_body_location = 'lower_leg' and d.clinical_evidence ~ '\machilles\M'),
    (17, 'patellar_tendon', 'patellar_tendon', 'knee__tendinopathy', d.effective_body_location = 'knee' and d.clinical_evidence ~ 'patellar tendon'),
    (18, 'shoulder_labral', 'shoulder_labral', 'shoulder__cartilage_injury', d.effective_body_location = 'shoulder' and d.clinical_evidence ~ '(labral|labrum)'),
    (19, 'shoulder_instability', 'shoulder_instability', 'shoulder__joint_sprain', d.effective_body_location = 'shoulder' and d.clinical_evidence ~ '(disloc|sublux|instability)'
      and d.clinical_evidence !~ '(acromioclavicular|\mac joint\M|\ma/c joint\M|labral|labrum)'),
    (20, 'fracture', 'fracture', concat(d.effective_body_location, '__fracture'), d.clinical_evidence ~ '(fractur|broken bone)' and d.clinical_evidence !~ '\mlisfranc\M'),
    (21, 'contusion_haematoma', 'contusion_haematoma', concat(d.effective_body_location, '__contusion_superficial'), d.clinical_evidence ~ '(\mcontusion\M|haematoma|hematoma|dead leg)'
      and d.clinical_evidence !~ '(concuss(ion|ed)?|brain injury)'),
    (22, 'tendon_injury', 'tendon_injury', concat(d.effective_body_location, '__tendinopathy'), d.clinical_evidence ~ '(\mtendon\M|tendinopathy|tendinosis)'
      and d.clinical_evidence !~ '(concuss|brain injury|acromioclavicular|\mac joint\M|\ma/c joint\M|syndesmo|high ankle sprain|lisfranc|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|cruciate|collateral|menisc|hamstring|biceps femoris|semitend|semimembran|\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\mvastus\M|\madductor\M|\mgroin\M|achilles|patellar tendon|labral|labrum|disloc|sublux|instability|fractur|broken bone|\mcontusion\M|haematoma|hematoma|dead leg)')
  ) x(priority, diagnosis_code, diagnosis_subtype, profile_code, matches)
  where x.matches
), diagnosis_candidates as (
  select scope_key, id, priority, diagnosis_code, diagnosis_subtype, profile_code
  from all_diagnosis_candidates
  where not is_synthetic
), diagnosis_candidate_summary as (
  select scope_key, id, count(distinct diagnosis_code)::int as candidate_count,
    min(diagnosis_code) as sole_candidate,
    array_agg(distinct diagnosis_code order by diagnosis_code) as candidates,
    count(distinct diagnosis_subtype)::int as subtype_candidate_count,
    min(diagnosis_subtype) as sole_subtype,
    array_agg(distinct diagnosis_subtype order by diagnosis_subtype) as subtype_candidates
  from diagnosis_candidates
  group by scope_key, id
), legacy_diagnosis_candidates as (
  -- Draft.3 patterns are a fallback only. Count every matching pattern before
  -- selecting anything so ordered CASE precedence cannot hide ambiguity.
  select d.scope_key, d.id, x.diagnosis_code, x.diagnosis_subtype, x.profile_code
  from contact_stage d
  cross join lateral (values
    -- Legacy fallback remains negation-aware. Without these guards, a row such
    -- as "head impact (not concussion)" would bypass reliable_concussion_text
    -- and be incorrectly classified here.
    ('concussion', 'concussion', 'head__brain_spinal_cord_injury', d.legacy_evidence ~ '(concuss|brain injury)'
      and d.legacy_evidence !~ '(no|not|negative( for)?|passed|clear(ed)?|ruled out|without|did not).{0,32}(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
      and d.legacy_evidence !~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M).{0,32}(negative|passed|clear(ed)?|ruled out|not diagnosed)'),
    ('knee_ligament', 'acl', 'knee__joint_sprain', d.body_location = 'knee' and d.legacy_evidence ~ '(\macl\M|anterior cruciate)'),
    ('knee_ligament', 'mcl', 'knee__joint_sprain', d.body_location = 'knee' and d.legacy_evidence ~ '(\mmcl\M|medial collateral)'),
    ('knee_ligament', 'pcl', 'knee__joint_sprain', d.body_location = 'knee' and d.legacy_evidence ~ '(\mpcl\M|posterior cruciate)'),
    ('knee_ligament', 'lcl', 'knee__joint_sprain', d.body_location = 'knee' and d.legacy_evidence ~ '(\mlcl\M|lateral collateral)'),
    ('knee_ligament', 'unspecified', 'knee__joint_sprain', d.body_location = 'knee'
      and d.legacy_evidence ~ '(\mcruciate\M|\mcollateral\M|knee ligament)'
      and d.legacy_evidence !~ '(\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|anterior cruciate|posterior cruciate|medial collateral|lateral collateral)'),
    ('ankle_ligament_sprain', 'ankle_ligament_sprain', 'ankle__joint_sprain', d.body_location = 'ankle' and d.legacy_evidence ~ '(sprain|ligament)'),
    ('hamstring_strain', 'hamstring_strain', 'thigh__muscle_injury', d.legacy_evidence ~ '(hamstring|biceps femoris|semitend|semimembran)'),
    ('contusion_haematoma', 'contusion_haematoma', concat(coalesce(d.body_location, 'unknown'), '__contusion_superficial'), d.legacy_evidence ~ '(contusion|haematoma|hematoma|dead leg)'),
    ('calf_muscle', 'calf_muscle', 'lower_leg__muscle_injury', d.legacy_evidence ~ '(calf|gastrocnemius|soleus)'),
    ('quadriceps_muscle', 'quadriceps_muscle', 'thigh__muscle_injury', d.legacy_evidence ~ '(quadriceps|rectus femoris|vastus )'),
    ('adductor_groin', 'adductor_groin', 'hip_groin__muscle_injury', d.legacy_evidence ~ '(adductor|groin)'),
    ('shoulder_instability', 'shoulder_instability', 'shoulder__joint_sprain', d.body_location = 'shoulder' and d.legacy_evidence ~ '(disloc|sublux|instability)'),
    ('fracture', 'fracture', concat(coalesce(d.body_location, 'unknown'), '__fracture'), d.legacy_evidence ~ '(fracture|broken bone)'),
    ('tendon_injury', 'tendon_injury', concat(coalesce(d.body_location, 'unknown'), '__tendinopathy'), d.legacy_evidence ~ '(tendon|tendin)')
  ) x(diagnosis_code, diagnosis_subtype, profile_code, matches)
  where x.matches
), legacy_diagnosis_candidate_summary as (
  select scope_key, id, count(distinct diagnosis_code)::int as candidate_count,
    min(diagnosis_code) as sole_candidate,
    array_agg(distinct diagnosis_code order by diagnosis_code) as candidates,
    count(distinct diagnosis_subtype)::int as subtype_candidate_count,
    min(diagnosis_subtype) as sole_subtype,
    array_agg(distinct diagnosis_subtype order by diagnosis_subtype) as subtype_candidates
  from legacy_diagnosis_candidates
  group by scope_key, id
), origin_strength as (
  select * from (values
    ('inferred', 1), ('mapped', 2), ('source_reported', 3), ('adjudicated', 4)
  ) v(origin_class, strength)
), compound_origin_pairs as (
  select a.origin_class as body_origin, b.origin_class as tissue_origin,
    case when a.strength <= b.strength then a.origin_class else b.origin_class end as resolved_origin
  from origin_strength a
  cross join origin_strength b
), compound_origin_expected_cases as (
  select * from (values
    ('inferred', 'inferred', 'inferred'),
    ('inferred', 'mapped', 'inferred'),
    ('inferred', 'source_reported', 'inferred'),
    ('inferred', 'adjudicated', 'inferred'),
    ('mapped', 'inferred', 'inferred'),
    ('mapped', 'mapped', 'mapped'),
    ('mapped', 'source_reported', 'mapped'),
    ('mapped', 'adjudicated', 'mapped'),
    ('source_reported', 'inferred', 'inferred'),
    ('source_reported', 'mapped', 'mapped'),
    ('source_reported', 'source_reported', 'source_reported'),
    ('source_reported', 'adjudicated', 'source_reported'),
    ('adjudicated', 'inferred', 'inferred'),
    ('adjudicated', 'mapped', 'mapped'),
    ('adjudicated', 'source_reported', 'source_reported'),
    ('adjudicated', 'adjudicated', 'adjudicated')
  ) v(body_origin, tissue_origin, expected_origin)
), diagnosis_stage as (
  select d.*,
    op.resolved_origin as compound_origin_group,
    case when coalesce(ds.candidate_count, 0) = 1 then ds.sole_candidate end as candidate_diagnosis_code,
    coalesce(ds.candidate_count, 0) as diagnosis_candidate_count,
    coalesce(ds.candidates, array[]::text[]) as diagnosis_candidates,
    coalesce(ds.subtype_candidate_count, 0) as diagnosis_subtype_candidate_count,
    case
      when coalesce(ds.subtype_candidate_count, 0) = 1 then ds.sole_subtype
      when coalesce(ds.candidate_count, 0) = 1 then 'multiple'
    end as candidate_diagnosis_subtype,
    coalesce(ds.subtype_candidates, array[]::text[]) as diagnosis_subtype_candidates,
    case when coalesce(ls.candidate_count, 0) = 1 then ls.sole_candidate end as legacy_diagnosis_code,
    coalesce(ls.candidate_count, 0) as legacy_diagnosis_candidate_count,
    coalesce(ls.candidates, array[]::text[]) as legacy_diagnosis_candidates,
    coalesce(ls.subtype_candidate_count, 0) as legacy_diagnosis_subtype_candidate_count,
    case
      when coalesce(ls.subtype_candidate_count, 0) = 1 then ls.sole_subtype
      when coalesce(ls.candidate_count, 0) = 1 then 'multiple'
    end as legacy_diagnosis_subtype,
    coalesce(ls.subtype_candidates, array[]::text[]) as legacy_diagnosis_subtype_candidates,
    array(
      select distinct candidate
      from unnest(coalesce(ds.candidates, array[]::text[]) || coalesce(ls.candidates, array[]::text[])) candidate
      order by candidate
    ) as diagnosis_ambiguity_candidates
  from contact_stage d
  left join diagnosis_candidate_summary ds on ds.scope_key = d.scope_key and ds.id = d.id
  left join legacy_diagnosis_candidate_summary ls on ls.scope_key = d.scope_key and ls.id = d.id
  left join compound_origin_pairs op
    on op.body_origin = d.body_location_origin_group
   and op.tissue_origin = d.tissue_pathology_origin_group
), classified_descriptive as (
  select d.*,
    case
      when diagnosis_candidate_count = 1 then candidate_diagnosis_code
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1 then legacy_diagnosis_code
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 0
        and effective_body_location <> 'unknown' and effective_injury_type <> 'unknown'
        then concat('compound__', effective_body_location, '__', effective_injury_type)
    end as diagnosis_code,
    case
      when diagnosis_candidate_count = 1 then diagnosis_subtype_candidates
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1
        then legacy_diagnosis_subtype_candidates
      else array[]::text[]
    end as diagnosis_subtypes,
    case
      when diagnosis_candidate_count = 1 then candidate_diagnosis_subtype
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1 then legacy_diagnosis_subtype
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 0
        and effective_body_location <> 'unknown' and effective_injury_type <> 'unknown'
        then 'compound_body_tissue'
    end as diagnosis_subtype,
    case
      when diagnosis_candidate_count = 1
        or (diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1) then 'tier_1_named'
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 0
        and effective_body_location <> 'unknown' and effective_injury_type <> 'unknown' then 'tier_2_compound'
      when diagnosis_candidate_count > 1
        or (diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count > 1) then 'cross_bucket_conflict'
      else 'insufficient_compound_evidence'
    end as diagnosis_tier,
    case
      when diagnosis_candidate_count = 1
        and candidate_diagnosis_code = 'concussion'
        and concussion_has_exact_code
        then 'mapped'
      when diagnosis_candidate_count = 1
        or (diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1)
        then 'inferred'
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 0
        and effective_body_location <> 'unknown' and effective_injury_type <> 'unknown'
        then compound_origin_group
      else 'remaining_unknown'
    end as diagnosis_origin_group,
    case
      when diagnosis_candidate_count = 1
        and candidate_diagnosis_code = 'concussion'
        and concussion_has_exact_code
        then 'mapped_from_exact_orchard_concussion_code'
      when diagnosis_candidate_count = 1 then 'inferred_v3:explicit_named_diagnosis_pattern'
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 1 then 'inferred_v3:unique_legacy_fallback_pattern'
      when diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count = 0
        and effective_body_location <> 'unknown' and effective_injury_type <> 'unknown'
        then case compound_origin_group
          when 'inferred'
            then 'inferred_v3:compound_body_tissue_weaker_input'
          when 'mapped'
            then 'mapped_from_compound_body_tissue_weaker_input'
          when 'source_reported'
            then 'source_reported'
          else 'manual_adjudication:compound_body_tissue_inputs'
        end
    end as diagnosis_origin
  from diagnosis_stage d
), diagnosis_display_taxonomy as (
  -- Abdel-approved display-taxonomy decision (20 Jul 2026): the IOC 2020
  -- joint_sprain tissue category is the parent for knee/ankle ligament-sprain
  -- families. This map changes only display code/subtype. Evidence rules,
  -- diagnosis tier, diagnosis origin string, and origin class are unchanged.
  select * from (values
    ('knee_ligament', 'compound__knee__joint_sprain', null::text),
    ('compound__knee__joint_sprain', 'compound__knee__joint_sprain', 'unspecified'),
    ('ankle_ligament_sprain', 'compound__ankle__joint_sprain', 'ankle_lateral_ligament'),
    ('syndesmosis_injury', 'compound__ankle__joint_sprain', 'syndesmosis'),
    ('compound__ankle__joint_sprain', 'compound__ankle__joint_sprain', 'unspecified')
  ) v(source_diagnosis_code, display_diagnosis_code, display_subtype)
), synthetic_display_taxonomy_cases as (
  select * from (values
    ('named_acl', 'knee_ligament', array['acl']::text[], 'acl', 'mapped',
      'compound__knee__joint_sprain', array['acl']::text[], 'acl', 'mapped'),
    ('generic_knee_sprain', 'compound__knee__joint_sprain', array[]::text[], 'compound_body_tissue', 'inferred',
      'compound__knee__joint_sprain', array['unspecified']::text[], 'unspecified', 'inferred'),
    ('knee_cartilage', 'compound__knee__cartilage_injury', array[]::text[], 'compound_body_tissue', 'mapped',
      'compound__knee__cartilage_injury', array[]::text[], 'compound_body_tissue', 'mapped'),
    ('meniscal', 'meniscal_injury', array['meniscal_injury']::text[], 'meniscal_injury', 'inferred',
      'meniscal_injury', array['meniscal_injury']::text[], 'meniscal_injury', 'inferred'),
    ('knee_nerve', 'compound__knee__peripheral_nerve_injury', array[]::text[], 'compound_body_tissue', 'mapped',
      'compound__knee__peripheral_nerve_injury', array[]::text[], 'compound_body_tissue', 'mapped'),
    ('shoulder_instability', 'shoulder_instability', array['shoulder_instability']::text[], 'shoulder_instability', 'inferred',
      'shoulder_instability', array['shoulder_instability']::text[], 'shoulder_instability', 'inferred'),
    ('ac_joint', 'ac_joint_sprain', array['ac_joint_sprain']::text[], 'ac_joint_sprain', 'inferred',
      'ac_joint_sprain', array['ac_joint_sprain']::text[], 'ac_joint_sprain', 'inferred'),
    ('lisfranc', 'lisfranc_injury', array['lisfranc_injury']::text[], 'lisfranc_injury', 'inferred',
      'lisfranc_injury', array['lisfranc_injury']::text[], 'lisfranc_injury', 'inferred'),
    ('hamstring', 'hamstring_strain', array['hamstring_strain']::text[], 'hamstring_strain', 'inferred',
      'hamstring_strain', array['hamstring_strain']::text[], 'hamstring_strain', 'inferred'),
    ('quadriceps', 'quadriceps_muscle', array['quadriceps_muscle']::text[], 'quadriceps_muscle', 'inferred',
      'quadriceps_muscle', array['quadriceps_muscle']::text[], 'quadriceps_muscle', 'inferred')
  ) v(case_name, source_diagnosis_code, source_subtypes, source_subtype, source_origin_class,
    expected_diagnosis_code, expected_subtypes, expected_subtype, expected_origin_class)
), display_classified_descriptive as (
  select d.*,
    coalesce(m.display_diagnosis_code, d.diagnosis_code) as display_diagnosis_code,
    case when m.display_subtype is not null then array[m.display_subtype]::text[]
      else d.diagnosis_subtypes end as display_diagnosis_subtypes,
    coalesce(m.display_subtype, d.diagnosis_subtype) as display_diagnosis_subtype,
    d.diagnosis_origin_group as display_diagnosis_origin_group
  from classified_descriptive d
  left join diagnosis_display_taxonomy m
    on m.source_diagnosis_code = d.diagnosis_code
), classified_cohort as (
  select c.*, d.effective_body_location, d.effective_body_location_origin,
    d.body_location_origin_group,
    d.effective_injury_type, d.effective_injury_type_origin,
    d.tissue_pathology_origin_group,
    d.effective_contact_context, d.effective_contact_context_origin,
    d.diagnosis_code as evidence_diagnosis_code,
    d.display_diagnosis_code as diagnosis_code,
    d.display_diagnosis_subtype as diagnosis_subtype,
    d.display_diagnosis_subtypes as diagnosis_subtypes,
    d.diagnosis_tier, d.diagnosis_origin,
    d.display_diagnosis_origin_group as diagnosis_origin_group,
    d.diagnosis_candidate_count, d.diagnosis_subtype_candidate_count,
    d.legacy_diagnosis_candidate_count, d.legacy_diagnosis_subtype_candidate_count,
    d.concussion_has_exact_code, d.concussion_has_positive_text
  from scoped_cohort c
  join display_classified_descriptive d on d.scope_key = c.scope_key and d.id = c.injury_id
), scopes as (
  select team_key as scope_key from analysis.league_member_releases_v2 where season = '2024-25'
  union all select 'urc'
), bounded_exposure as (
  select
    e.team_key,
    round(coalesce(sum(e.minutes_clean), 0) / 60, 1) as total_hours
  from curated.exposure e
  join analysis.league_member_releases_v2 m
    on m.curated_build_id = e.curated_build_id
   and m.team_key = e.team_key and m.season = e.season
  where e.season = '2024-25'
    and e.eligibility_status = 'included_pending_protocol'
    and coalesce(e.session_date, e.week_start_date)
      between date '2024-07-01' and date '2025-06-30'
  group by e.team_key
), bounded_match_exposure as (
  select teams.team_key, count(*)::numeric * 20.0 as match_hours
  from curated.fixtures f
  cross join lateral (values (f.home_team_key), (f.away_team_key)) teams(team_key)
  where f.season = '2024-25'
    and f.match_date between date '2024-07-01' and date '2025-06-30'
  group by teams.team_key
), team_denominators as (
  select
    s.scope_key,
    coalesce(e.total_hours, 0)::numeric as total_hours,
    round(coalesce(m.match_hours, 0), 1) as match_hours,
    round(coalesce(e.total_hours, 0) - coalesce(m.match_hours, 0), 1) as training_hours
  from scopes s
  left join bounded_exposure e on e.team_key = s.scope_key
  left join bounded_match_exposure m on m.team_key = s.scope_key
  where s.scope_key <> 'urc'
), denominators as (
  select * from team_denominators
  union all
  select 'urc', round(sum(total_hours), 1), round(sum(match_hours), 1), round(sum(training_hours), 1)
  from team_denominators
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
    and f.match_date between date '2024-07-01' and date '2025-06-30'
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
    d.scope_key,
    count(*)::int as recorded_injuries,
    count(*) filter (where d.date_injured is null)::int as undated_injuries,
    coalesce(o.outside_season_date_injuries, 0)::int as outside_season_date_injuries,
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
  from scoped_descriptive d
  left join outside_season_dates o on o.scope_key = d.scope_key
  group by d.scope_key, o.outside_season_date_injuries
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
), classification_profile_rows as (
  select
    c.scope_key,
    'body_location'::text as dimension,
    st.setting_code,
    c.effective_body_location as code,
    coalesce(cl.label, 'Unknown') as label,
    c.days_lost
  from classified_cohort c
  cross join settings st
  left join curated.code_lists cl
    on cl.list_name = 'body_location' and cl.code = c.effective_body_location
  where c.is_time_loss
    and (st.setting_code = 'all' or c.setting_code = st.setting_code)
  union all
  select
    c.scope_key,
    'injury_type',
    st.setting_code,
    c.effective_injury_type,
    coalesce(cl.label, 'Unknown'),
    c.days_lost
  from classified_cohort c
  cross join settings st
  left join curated.code_lists cl
    on cl.list_name = 'injury_type' and cl.code = c.effective_injury_type
  where c.is_time_loss
    and (st.setting_code = 'all' or c.setting_code = st.setting_code)
), classification_profiles as (
  select
    scope_key,
    dimension,
    setting_code,
    code,
    label,
    count(*)::int as time_loss_injuries,
    sum(days_lost)::numeric as days_lost
  from classification_profile_rows
  group by scope_key, dimension, setting_code, code, label
), diagnosis_labels as (
  -- Knee/ankle ligament-sprain families use the IOC joint_sprain parent label.
  -- Clinically distinct shoulder instability, AC-joint and Lisfranc entities,
  -- plus named muscle diagnoses, remain separate display diagnoses.
  select * from (values
    ('concussion', 'Concussion', 1),
    ('ac_joint_sprain', 'AC joint sprain / separation', 2),
    ('lisfranc_injury', 'Lisfranc injury', 4),
    ('compound__knee__joint_sprain', 'Knee · Joint sprain', 5),
    ('meniscal_injury', 'Meniscal injury', 6),
    ('compound__ankle__joint_sprain', 'Ankle · Joint sprain', 7),
    ('hamstring_strain', 'Hamstring strain', 8),
    ('calf_muscle', 'Calf muscle injury', 9),
    ('quadriceps_muscle', 'Quadriceps muscle injury', 10),
    ('adductor_groin', 'Adductor / groin injury', 11),
    ('achilles_tendon', 'Achilles tendon injury', 12),
    ('patellar_tendon', 'Patellar tendon injury', 13),
    ('shoulder_labral', 'Shoulder labral injury', 14),
    ('shoulder_instability', 'Shoulder instability', 15),
    ('fracture', 'Fracture', 16),
    ('contusion_haematoma', 'Contusion / haematoma', 17),
    ('tendon_injury', 'Tendon injury', 18),
    ('unknown', 'Unknown diagnosis', 99)
  ) v(diagnosis_code, label, sort_order)
), diagnosis_profile_rows as (
  select d.*, st.setting_code as profile_setting_code,
    coalesce(d.diagnosis_code, 'unknown') as profile_code,
    case
      when l.label is not null then l.label
      when d.diagnosis_tier = 'tier_2_compound'
        then concat(coalesce(bl.label, d.effective_body_location), ' · ',
          coalesce(tl.label, d.effective_injury_type))
    end as profile_label,
    case when l.sort_order is not null then l.sort_order
      when d.diagnosis_tier = 'tier_2_compound' then 90 end as sort_order
  from classified_cohort d
  left join diagnosis_labels l on l.diagnosis_code = coalesce(d.diagnosis_code, 'unknown')
  left join curated.code_lists bl
    on bl.list_name = 'body_location' and bl.code = d.effective_body_location
  left join curated.code_lists tl
    on tl.list_name = 'injury_type' and tl.code = d.effective_injury_type
  cross join settings st
  where d.is_time_loss
    and (st.setting_code = 'all' or d.setting_code = st.setting_code)
), diagnosis_profile_aggregates as (
  select
    d.scope_key,
    d.profile_setting_code as setting_code,
    d.profile_code as diagnosis_code,
    d.profile_label as label,
    count(*)::int as time_loss_injuries,
    sum(d.days_lost)::numeric as days_lost
  from diagnosis_profile_rows d
  group by d.scope_key, d.profile_setting_code, d.profile_code, d.profile_label, d.sort_order
), diagnosis_profiles as (
  select * from diagnosis_profile_aggregates
  union all
  select s.scope_key, st.setting_code, 'unknown', 'Unknown diagnosis', 0::int, 0::numeric
  from (select distinct scope_key from classified_cohort) s
  cross join settings st
  where not exists (
    select 1 from diagnosis_profile_aggregates p
    where p.scope_key = s.scope_key
      and p.setting_code = st.setting_code
      and p.diagnosis_code = 'unknown'
  )
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
      'source_reported', count(*) filter (where diagnosis_origin_group = 'source_reported'),
      'mapped', count(*) filter (where diagnosis_origin_group = 'mapped'),
      'inferred', count(*) filter (where diagnosis_origin_group = 'inferred'),
      'adjudicated', count(*) filter (where diagnosis_origin_group = 'adjudicated'),
      'remaining_unknown', count(*) filter (where diagnosis_origin_group = 'remaining_unknown'),
      'unknown_before_v3', count(*) filter (where legacy_diagnosis_subtype_candidate_count <> 1),
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
  select id::text, scope_key, 'body_location',
    to_jsonb(array[body_location, 'head']::text[]),
    'concussion versus curated body',
    'Reliable concussion evidence conflicts with immutable curated body location.',
    null::int, null::int, body_location
  from classified_descriptive
  where scope_key <> 'urc'
    and has_concussion_evidence
    and coalesce(body_location, 'unknown') not in ('unknown', 'head')
  union all
  select id::text, scope_key, 'tissue_pathology', to_jsonb(tissue_candidates),
    concat('signals ', array_to_string(tissue_candidates, '/')),
    'Conflicting IOC tissue/pathology signals; source code and text do not resolve uniquely.',
    null::int, null::int, 'unknown'
  from classified_descriptive where scope_key <> 'urc' and tissue_candidate_count > 1
  union all
  select id::text, scope_key, 'tissue_pathology',
    to_jsonb(array[injury_type, 'brain_spinal_cord_injury']::text[]),
    'concussion versus curated tissue',
    'Reliable concussion evidence conflicts with immutable curated tissue/pathology.',
    null::int, null::int, injury_type
  from classified_descriptive
  where scope_key <> 'urc'
    and has_concussion_evidence
    and coalesce(injury_type, 'unknown') not in ('unknown', 'brain_spinal_cord_injury')
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
    and (diagnosis_candidate_count > 1
      or (diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count > 1))
), concussion_rule_cases as (
  select * from (values
    ('description_positive', 'Description', 'acute concussion', true),
    ('mechanism_cross_column', 'Mechanism Notes', 'removed for HIA', true),
    ('rtp_cross_column', 'Return to Play Notes', 'SRC protocol commenced', true),
    ('negated_concussion', 'Description', 'no concussion diagnosed', false),
    ('hia_negative', 'Mechanism Notes', 'HIA negative', false),
    ('hia_passed', 'Mechanism Notes', 'HIA passed', false),
    ('not_concussed', 'Description', 'player not concussed', false),
    ('not_diagnosed', 'Injury Tissue Type/s', 'head impact not diagnosed as concussion', false),
    ('legitimate_no_history', 'Description', 'concussion with no concerning history', true)
  ) v(case_name, evidence_field, evidence_value, expected_positive)
), concussion_rule_results as (
  select *,
    (
      (
        evidence_field in (
          'Description', 'Injury Tissue Type/s', 'Body Part',
          'Mechanism of Injury', 'Mechanism Notes', 'Treatment/Rehab',
          'Injury Immediate Action', 'Injury Status', 'Medical System'
        )
        or lower(evidence_field) ~ '(hia|concussion|head injury assessment|return.?to.?play|(^|[^a-z])rtp([^a-z]|$)|diagnos)'
      )
      and lower(evidence_value) ~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
      and lower(evidence_value) !~ '(no|not|negative( for)?|passed|clear(ed)?|ruled out|without|did not).{0,32}(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
      and lower(evidence_value) !~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M).{0,32}(negative|passed|clear(ed)?|ruled out|not diagnosed)'
    ) as actual_positive
  from concussion_rule_cases
), legacy_concussion_rule_cases as (
  select * from (values
    ('legacy_positive', 'acute concussion', true),
    ('legacy_negated', 'no concussion diagnosed', false),
    ('legacy_hia_negative', 'HIA negative after head impact', false),
    ('legacy_not_diagnosed', 'head impact not diagnosed as concussion', false),
    ('legacy_clearance', 'concussion ruled out and player cleared', false)
  ) v(case_name, evidence_value, expected_positive)
), legacy_concussion_rule_results as (
  select *,
    (
      lower(evidence_value) ~ '(concuss|brain injury)'
      and lower(evidence_value) !~ '(no|not|negative( for)?|passed|clear(ed)?|ruled out|without|did not).{0,32}(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
      and lower(evidence_value) !~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M).{0,32}(negative|passed|clear(ed)?|ruled out|not diagnosed)'
    ) as actual_positive
  from legacy_concussion_rule_cases
), synthetic_diagnosis_results as (
  select c.case_name,
    case when count(distinct a.diagnosis_code) = 1
      then min(a.diagnosis_code) end as actual_bucket,
    count(distinct a.diagnosis_subtype)::int as actual_subtype_count,
    c.expected_bucket,
    c.expected_subtype_count
  from diagnosis_bucket_rule_cases c
  left join all_diagnosis_candidates a
    on a.is_synthetic and a.id = c.id
  group by c.case_name, c.expected_bucket, c.expected_subtype_count
), synthetic_compound_origin_results as (
  select e.body_origin, e.tissue_origin,
    p.resolved_origin as actual_origin, e.expected_origin
  from compound_origin_expected_cases e
  join compound_origin_pairs p
    on p.body_origin = e.body_origin and p.tissue_origin = e.tissue_origin
), synthetic_display_taxonomy_results as (
  select c.case_name,
    coalesce(m.display_diagnosis_code, c.source_diagnosis_code) as actual_diagnosis_code,
    case when m.display_subtype is not null then array[m.display_subtype]::text[]
      else c.source_subtypes end as actual_subtypes,
    coalesce(m.display_subtype, c.source_subtype) as actual_subtype,
    c.source_origin_class as actual_origin_class,
    c.expected_diagnosis_code, c.expected_subtypes, c.expected_subtype,
    c.expected_origin_class
  from synthetic_display_taxonomy_cases c
  left join diagnosis_display_taxonomy m
    on m.source_diagnosis_code = c.source_diagnosis_code
), diagnosis_assignment_checks as (
  select scope_key,
    count(*) filter (where diagnosis_code is not null)::int as diagnosis_bucket_rows,
    count(*) filter (where diagnosis_code is null)::int as diagnosis_unknown_rows,
    count(*)::int as descriptive_cohort_rows,
    (count(*) - count(distinct id))::int as duplicate_injury_rows
  from classified_descriptive
  group by scope_key
), profile_assignment_checks as (
  select c.scope_key, st.setting_code,
    count(*) filter (where c.is_time_loss
      and (st.setting_code = 'all' or c.setting_code = st.setting_code))::int as classified_time_loss_rows,
    coalesce((select sum(p.time_loss_injuries)::int from diagnosis_profiles p
      where p.scope_key = c.scope_key and p.setting_code = st.setting_code), 0)::int as profile_rows
  from classified_cohort c
  cross join settings st
  group by c.scope_key, st.setting_code
), legacy_multi_match_refusal_checks as (
  select scope_key,
    count(*)::int as expected_legacy_multi_match_refusals
  from classified_descriptive
  where scope_key <> 'urc'
    and legacy_diagnosis_candidate_count > 1
    and diagnosis_candidate_count = 0
  group by scope_key
), concussion_scope_counts as (
  select d.scope_key,
    count(*) filter (where d.has_concussion_evidence)::int as evidence_rows,
    count(*) filter (where d.diagnosis_code = 'concussion')::int as classified_diagnosis_rows,
    count(*) filter (where d.diagnosis_code = 'concussion' and d.diagnosis_origin_group = 'mapped')::int as mapped_diagnosis_rows,
    count(*) filter (where d.diagnosis_code = 'concussion' and d.diagnosis_origin_group = 'inferred')::int as inferred_diagnosis_rows,
    (select count(*)::int from classified_cohort c
      where c.scope_key = d.scope_key and c.is_time_loss and c.diagnosis_code = 'concussion') as time_loss_rows
  from classified_descriptive d
  group by d.scope_key
), diagnosis_provenance as (
  select
    c.scope_key as team_scope,
    st.setting_code as setting,
    coalesce(c.diagnosis_code, 'unknown') as diagnosis_code,
    c.diagnosis_origin_group as origin_class,
    count(*)::int as time_loss_injuries
  from classified_cohort c
  cross join settings st
  where c.scope_key <> 'urc'
    and c.is_time_loss
    and (st.setting_code = 'all' or c.setting_code = st.setting_code)
  group by c.scope_key, st.setting_code,
    coalesce(c.diagnosis_code, 'unknown'), c.diagnosis_origin_group
), joint_sprain_subtype_provenance as (
  select
    c.scope_key as team_scope,
    st.setting_code as setting,
    case c.diagnosis_code
      when 'compound__knee__joint_sprain' then 'knee'
      else 'ankle'
    end as joint_location,
    subtype.diagnosis_subtype,
    c.diagnosis_origin_group as origin_class,
    count(*)::int as time_loss_injuries,
    sum(c.days_lost)::numeric as days_lost
  from classified_cohort c
  cross join settings st
  cross join lateral unnest(
    case when cardinality(c.diagnosis_subtypes) > 0
      then c.diagnosis_subtypes else array['unspecified']::text[] end
  ) subtype(diagnosis_subtype)
  where c.scope_key <> 'urc'
    and c.is_time_loss
    and c.diagnosis_code in (
      'compound__knee__joint_sprain', 'compound__ankle__joint_sprain'
    )
    and (st.setting_code = 'all' or c.setting_code = st.setting_code)
  group by c.scope_key, st.setting_code, c.diagnosis_code,
    subtype.diagnosis_subtype, c.diagnosis_origin_group
), draft7_unknown_decomposition as (
  select
    st.setting_code as setting,
    count(*)::int as draft7_unknown_time_loss_rows,
    count(*) filter (where c.effective_body_location <> 'unknown')::int as has_standardised_body,
    count(*) filter (where c.effective_injury_type <> 'unknown')::int as has_standardised_tissue,
    count(*) filter (where c.orchard_code <> '')::int as has_orchard_osiics_code,
    count(*) filter (where c.description_evidence <> '')::int as has_description,
    count(*) filter (where c.diagnosis_tier = 'tier_2_compound')::int as recoverable_by_tier2,
    count(*) filter (where c.diagnosis_tier = 'tier_1_named'
      and c.evidence_diagnosis_code = 'knee_ligament'
      and (c.diagnosis_subtype_candidate_count > 1
        or (c.diagnosis_candidate_count = 0
          and c.legacy_diagnosis_subtype_candidate_count > 1))
    )::int as recovered_by_knee_rollup,
    count(*) filter (where c.diagnosis_tier = 'cross_bucket_conflict')::int as cross_bucket_conflict,
    count(*) filter (where c.diagnosis_code is null)::int as remaining_unknown_after_draft9,
    count(*) filter (where c.effective_body_location = 'unknown'
      and c.effective_injury_type = 'unknown'
      and c.orchard_code = '' and c.description_evidence = '')::int as genuinely_evidence_less_all_four
  from classified_cohort c
  cross join settings st
  where c.scope_key = 'urc'
    and c.is_time_loss
    and (st.setting_code = 'all' or c.setting_code = st.setting_code)
    and not (
      c.diagnosis_subtype_candidate_count = 1
      or (c.diagnosis_candidate_count = 0
        and c.legacy_diagnosis_subtype_candidate_count = 1)
    )
  group by st.setting_code
), draft7_unknown_evidence_crosstab as (
  select
    st.setting_code as setting,
    (c.effective_body_location <> 'unknown') as has_standardised_body,
    (c.effective_injury_type <> 'unknown') as has_standardised_tissue,
    (c.orchard_code <> '') as has_orchard_osiics_code,
    (c.description_evidence <> '') as has_description,
    c.diagnosis_tier,
    count(*)::int as time_loss_injuries
  from classified_cohort c
  cross join settings st
  where c.scope_key = 'urc'
    and c.is_time_loss
    and (st.setting_code = 'all' or c.setting_code = st.setting_code)
    and not (
      c.diagnosis_subtype_candidate_count = 1
      or (c.diagnosis_candidate_count = 0
        and c.legacy_diagnosis_subtype_candidate_count = 1)
    )
  group by st.setting_code,
    (c.effective_body_location <> 'unknown'),
    (c.effective_injury_type <> 'unknown'),
    (c.orchard_code <> ''), (c.description_evidence <> ''), c.diagnosis_tier
), concussion_evidence_counts as (
  select
    c.scope_key as team_scope,
    count(*) filter (
      where c.diagnosis_code = 'concussion' and c.concussion_has_exact_code
    )::int as exact_code_rows,
    count(*) filter (
      where c.diagnosis_code = 'concussion' and c.concussion_has_positive_text
    )::int as text_pattern_rows
  from classified_cohort c
  where c.scope_key <> 'urc'
  group by c.scope_key
), validation_checks as (
  select jsonb_build_object(
    'synthetic_concussion_case_failures', (
      select count(*)::int from concussion_rule_results where actual_positive <> expected_positive
    ),
    'legacy_concussion_case_failures', (
      select count(*)::int from legacy_concussion_rule_results where actual_positive <> expected_positive
    ),
    'synthetic_diagnosis_bucket_case_failures', (
      select count(*)::int from synthetic_diagnosis_results
      where actual_bucket is distinct from expected_bucket
        or actual_subtype_count <> expected_subtype_count
    ),
    'synthetic_compound_origin_case_failures', (
      select count(*)::int from synthetic_compound_origin_results
      where actual_origin <> expected_origin
    ),
    'synthetic_display_taxonomy_case_failures', (
      select count(*)::int from synthetic_display_taxonomy_results
      where actual_diagnosis_code is distinct from expected_diagnosis_code
        or actual_subtypes is distinct from expected_subtypes
        or actual_subtype is distinct from expected_subtype
        or actual_origin_class is distinct from expected_origin_class
    ),
    'display_taxonomy_origin_class_changes', (
      select count(*)::int from display_classified_descriptive
      where diagnosis_origin_group is distinct from display_diagnosis_origin_group
    ),
    'profile_map_duplicate_source_codes', (
      select count(*)::int from (
        select diagnosis_code from diagnosis_labels group by diagnosis_code having count(*) <> 1
      ) x
    ),
    'acl_routes_to_joint_sprain_parent', (
      select count(*) = 2 from diagnosis_labels
      where (diagnosis_code = 'compound__knee__joint_sprain' and label = 'Knee · Joint sprain')
         or (diagnosis_code = 'compound__ankle__joint_sprain' and label = 'Ankle · Joint sprain')
    ),
    'legacy_knee_ligament_display_labels', (
      select count(*)::int from diagnosis_labels
      where diagnosis_code = 'knee_ligament' or label = 'Knee ligament injury'
    ),
    'within_bucket_multi_match_refusals', (
      select count(*)::int from classified_descriptive
      where diagnosis_subtype_candidate_count > 1
        and diagnosis_candidate_count = 1 and diagnosis_code is null
    ),
    'cross_bucket_conflicts_classified', (
      select count(*)::int from classified_descriptive
      where (diagnosis_candidate_count > 1
          or (diagnosis_candidate_count = 0 and legacy_diagnosis_candidate_count > 1))
        and diagnosis_code is not null
    ),
    'compound_missing_input_failures', (
      select count(*)::int from classified_descriptive
      where diagnosis_tier = 'tier_2_compound'
        and (effective_body_location = 'unknown' or effective_injury_type = 'unknown')
    ),
    'unknown_with_complete_compound_inputs', (
      select count(*)::int from classified_descriptive
      where diagnosis_code is null and diagnosis_tier <> 'cross_bucket_conflict'
        and effective_body_location <> 'unknown' and effective_injury_type <> 'unknown'
    ),
    'meniscus_routes_to_cartilage', (
      select count(*) = 1 from diagnosis_labels
      where diagnosis_code = 'meniscal_injury' and label = 'Meniscal injury'
    ),
    'diagnosis_assignments', (
      select jsonb_agg(to_jsonb(d) order by d.scope_key) from diagnosis_assignment_checks d
    ),
    'time_loss_profile_assignments', (
      select jsonb_agg(to_jsonb(p) order by p.scope_key) from profile_assignment_checks p
    ),
    'legacy_multi_match_refusal_checks', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.scope_key), '[]'::jsonb)
      from legacy_multi_match_refusal_checks r
    ),
    'concussion_counts', (
      select jsonb_agg(to_jsonb(c) order by c.scope_key) from concussion_scope_counts c
    )
  ) as checks
), supplements as (
  select jsonb_build_object(
    'status', 'draft_not_for_release',
    'season', '2024-25',
    'team_key', s.scope_key,
    'rule_version', 'urc-diagnosis-inference-v3-draft.9',
    'cohort_rule', 'season_bound_2024-07-01_2025-06-30_no_exposure_window',
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
    'body_locations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dimension', p.dimension,
        'code', p.code,
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
        p.time_loss_injuries desc, p.code)
      from classification_profiles p
      join denominators d on d.scope_key = p.scope_key
      where p.scope_key = s.scope_key and p.dimension = 'body_location'
    ), '[]'::jsonb),
    'injury_types', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dimension', p.dimension,
        'code', p.code,
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
        p.time_loss_injuries desc, p.code)
      from classification_profiles p
      join denominators d on d.scope_key = p.scope_key
      where p.scope_key = s.scope_key and p.dimension = 'injury_type'
    ), '[]'::jsonb),
    'common_injuries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dimension', 'diagnosis',
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
  'cohort_rule', 'season_bound_2024-07-01_2025-06-30_no_exposure_window',
  'supplements', jsonb_agg(supplement order by supplement ->> 'team_key'),
  'report_support', jsonb_build_object(
    'diagnosis_provenance', (
      select coalesce(jsonb_agg(to_jsonb(p)
        order by p.setting, p.diagnosis_code, p.team_scope, p.origin_class), '[]'::jsonb)
      from diagnosis_provenance p
    ),
    'concussion_evidence_counts', (
      select coalesce(jsonb_agg(to_jsonb(c) order by c.team_scope), '[]'::jsonb)
      from concussion_evidence_counts c
    ),
    'joint_sprain_subtype_provenance', (
      select coalesce(jsonb_agg(to_jsonb(k)
        order by k.joint_location, k.setting, k.diagnosis_subtype,
          k.team_scope, k.origin_class), '[]'::jsonb)
      from joint_sprain_subtype_provenance k
    ),
    'draft7_unknown_decomposition', (
      select coalesce(jsonb_agg(to_jsonb(u) order by u.setting), '[]'::jsonb)
      from draft7_unknown_decomposition u
    ),
    'draft7_unknown_evidence_crosstab', (
      select coalesce(jsonb_agg(to_jsonb(u)
        order by u.setting, u.has_standardised_body, u.has_standardised_tissue,
          u.has_orchard_osiics_code, u.has_description, u.diagnosis_tier), '[]'::jsonb)
      from draft7_unknown_evidence_crosstab u
    )
  ),
  'origin_class_counts', (
    select coalesce(jsonb_agg(to_jsonb(o) order by o.scope_key, o.field, o.origin, o.origin_class), '[]'::jsonb)
    from origin_class_counts o
  ),
  'validation_checks', (select checks from validation_checks),
  'adjudication_candidates', (
    select coalesce(jsonb_agg(to_jsonb(a) order by a.team_key, a.id, a.field), '[]'::jsonb)
    from adjudication_candidates a
  )
) as dashboard_v3_preview
from supplements;
