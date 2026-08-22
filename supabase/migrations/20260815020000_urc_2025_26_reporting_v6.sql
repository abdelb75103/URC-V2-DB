-- Additive Year 2 computational reporting successor.  This path reads only
-- active curated rows and becomes visible only for a complete sixteen-team build.

create view analysis.accepted_analysis_window_cohort_rules_v6
with (security_invoker = true) as
select r.cohort_view_version, r.season,
  encode(digest(convert_to(jsonb_agg(jsonb_build_object(
    'adjudication_ref',r.adjudication_ref,'decision',r.decision,
    'evidence_sha256',r.evidence_sha256,'evidence_locator',r.evidence_locator,
    'reviewer',r.reviewer,'migration_version',r.migration_version
  ) order by r.adjudication_ref)::text,'UTF8'),'sha256'),'hex') as cohort_evidence_sha256
from audit.reporting_cohort_rule_adjudications_v3 r
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version=r.cohort_view_version and w.season=r.season
 and w.decision_ref=r.adjudication_ref
 and w.season_start=date '2025-09-01' and w.season_end=date '2026-06-30'
where r.adjudication_ref='ANALYSIS-WINDOW-2025-26-01'
  and r.cohort_view_version='analysis_window_2025-26_2026-08-15_v1'
  and r.season='2025-26' and r.reviewer='Abdel Babiker'
  and r.evidence_sha256='e8d82b7d5b89c32576b806bb33778601030538ba8fb56fc1a68febc5f56d3fd2'
  and r.evidence_locator='docs/evidence/urc_2025_26_reporting_contract.json'
  and r.migration_version='20260815010000'
group by r.cohort_view_version,r.season having count(*)=1;

-- Year 2 accepts the already-reviewed catalogue and conservative inference
-- algorithm, but deliberately does not inherit the prior season's row-level
-- adjudication chain.  This evidence identity is therefore derived only from
-- immutable repository catalogue/rule bytes and their declared scope.
create view analysis.accepted_year2_reporting_classification_rules_v6
with (security_invoker = true) as
with expected_mapping(source_code,mapped_body_location_code,mapped_injury_type_code) as (
  values
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
  ('QBC','lower_leg','bursitis'),
  ('QRA','ankle','tendon_rupture'),('QRA','lower_leg','tendon_rupture'),
  ('QVVP','lower_leg','vascular_trauma'),('SL1','shoulder','joint_sprain'),
  ('SL2','shoulder','joint_sprain'),
  ('SQP','shoulder','synovitis_capsulitis'),('WC1','wrist','cartilage_injury')
), expected_multi(
  source_code,mapped_body_location_code,diagnosis_code,diagnosis_label,
  candidate_injury_types,analysis_primary_type_code
) as (
  values ('NPM','neck','multi__neck__muscle_injury__tendinopathy',
    'Neck · Muscle/tendon injury','muscle_injury;tendinopathy','nonspecific')
), catalogue_gate as (
  select
    not exists (
      (select * from expected_mapping except all select * from analysis.osiics_exact_ioc_mapping_v1)
      union all
      (select * from analysis.osiics_exact_ioc_mapping_v1 except all select * from expected_mapping)
    ) as mapping_exact,
    not exists (
      (select * from expected_multi except all select * from analysis.osiics_multi_type_diagnosis_v1)
      union all
      (select * from analysis.osiics_multi_type_diagnosis_v1 except all select * from expected_multi)
    ) as multi_exact
)
select
  'reporting_classification_2026-07-22_v2'::text as classification_view_version,
  encode(digest(convert_to(jsonb_build_object(
    'application_scope','catalogue_and_conservative_inference_only',
    'rule_evidence_locator','docs/evidence/urc_2025_26_classification_rule.json',
    'rule_evidence_sha256','e898320fc5fa8cdfbf4fde4382d1ade62c87fe2dbef820ecf72b557bfb07cd5f',
    'mapping_catalogue_projection_sha256','79767a9fc4212309c8fa01749ddf47541a251e467897268a9c8edeb4265553ff',
    'mapping_catalogue_row_count',52,
    'multi_type_catalogue_projection_sha256','d7aa844af7a4e6a53072f90e129da5357dfd4523aef415ecf84fd447702db55a',
    'multi_type_catalogue_row_count',1,
    'year1_row_adjudications','not_carried_forward'
  )::text,'UTF8'),'sha256'),'hex') as classification_evidence_sha256
from catalogue_gate where mapping_exact and multi_exact;

-- This relation admits only the one complete public fixture schedule whose
-- accepted prepared CSV bytes are bound to every official-response provenance
-- row.  A partial load, duplicate/altered provenance, or a checksum mismatch
-- returns no rows and therefore cannot contribute team hours or a V6 release.
create view analysis.accepted_urc_fixtures_v6
with (security_invoker = true) as
with matched as (
  select fixture.season, fixture.stage, fixture.round, fixture.match_date,
    fixture.date_status, fixture.home_team_key, fixture.away_team_key,
    fixture.source_row_number, fixture.source_file_sha256 as prepared_file_sha256,
    provenance.upstream_match_id, provenance.source_locator,
    provenance.source_request_sha256, provenance.upstream_response_sha256,
    provenance.retrieved_at
  from curated.fixtures fixture
  join curated.fixture_provenance_v1 provenance
    on provenance.season = fixture.season
   and provenance.source_row_number = fixture.source_row_number
   and provenance.prepared_file_sha256=fixture.source_file_sha256
  join analysis.fixture_preparation_evidence_v1 evidence
    on evidence.season = fixture.season
   and fixture.source_file_sha256 = evidence.prepared_file_sha256
   and provenance.source_request_sha256 = evidence.source_request_sha256
   and provenance.upstream_response_sha256 = evidence.upstream_response_sha256
   and provenance.retrieved_at = evidence.retrieved_at
   and provenance.source_locator ~ evidence.source_locator_pattern
  where fixture.season = '2025-26'
), completeness as (
  select
    (select count(*) from curated.fixtures where season = '2025-26') as fixture_count,
    (select count(*) from curated.fixture_provenance_v1 where season = '2025-26') as provenance_count,
    count(*) as joined_count,
    count(distinct source_row_number) as joined_source_row_count,
    count(distinct prepared_file_sha256) as prepared_hash_count,
    count(distinct upstream_response_sha256) as upstream_response_hash_count,
    count(*) filter (where stage = 'Regular season') as regular_fixture_count,
    count(*) filter (where stage = 'Quarter-final') as quarter_final_count,
    count(*) filter (where stage = 'Semi-final') as semi_final_count,
    count(*) filter (where stage = 'Final') as final_count
  from matched
), team_regular_coverage as (
  select team_key, count(*) as regular_match_count
  from (
    select home_team_key as team_key from matched where stage = 'Regular season'
    union all
    select away_team_key as team_key from matched where stage = 'Regular season'
  ) appearances
  group by team_key
), schedule_complete as (
  select not exists (
    select 1
    from reporting.teams roster
    left join team_regular_coverage coverage on coverage.team_key = roster.team_key
    where coalesce(coverage.regular_match_count, 0) <> 18
  ) as all_teams_have_eighteen_regular_matches
)
select matched.*
from matched
cross join completeness
cross join schedule_complete
where fixture_count = 151
  and provenance_count = 151
  and joined_count = 151
  and joined_source_row_count = 151
  and prepared_hash_count = 1
  and upstream_response_hash_count = 1
  and regular_fixture_count = 144
  and quarter_final_count = 4
  and semi_final_count = 2
  and final_count = 1
  and all_teams_have_eighteen_regular_matches;

-- These are source builds, not accepted releases.  Keeping this relation
-- release-free is what permits the first V6 team release to be created.
create or replace view analysis.analysis_window_active_builds_v6
with (security_invoker = true) as
select build.team_key,build.season,build.id as curated_build_id,
  build.created_at as generated_at
from curated.builds build join reporting.teams roster on roster.team_key=build.team_key
where build.season='2025-26' and build.status='active'
  and (select count(*) from curated.builds where season='2025-26' and status='active')=16
  and (select count(distinct team_key) from curated.builds where season='2025-26' and status='active')=16
  and (select count(*) from reporting.teams)=16
  and exists (select 1 from analysis.accepted_urc_fixtures_v6);

-- The accepted 2026-07-22 catalogue carries forward as a rule, not as the
-- 2024-25 row ledger.  A non-Unknown curated controlled value always wins;
-- otherwise only an exact OSIICS code or one unique explicit body/type signal
-- may classify a Year 2 injury. Ambiguous, conflicting, and weak evidence
-- remains Unknown.
create view analysis.analysis_window_reporting_classification_v6
with (security_invoker = true) as
with source_evidence as (
  select injury.id as injury_id, member.curated_build_id, member.team_key, member.season,
    injury.source_row_id, injury.date_injured,
    injury.days_injured as observed_days_injured,
    coalesce(injury.days_injured, 0)::numeric as days_lost,
    coalesce(injury.days_injured, 0) > 0 as is_time_loss,
    case injury.activity_context when 'match' then 'match' when 'urc_match' then 'match'
      when 'training' then 'training' else 'unknown' end as setting_code,
    coalesce(injury.body_location, 'unknown') as body_location_code,
    coalesce(injury.injury_type, 'unknown') as injury_type_code,
    upper(trim(coalesce(
      nullif(source.source_values ->> 'Orchard Code', ''),
      case when injury.problem_type = 'injury' then source.source_values ->> 'Illness Code' end,
      ''
    ))) as orchard_code,
    lower(trim(concat_ws(' ',
      source.source_values ->> 'Description',
      source.source_values ->> 'Injury Tissue Type/s',
      source.source_values ->> 'Body Part'
    ))) as clinical_evidence,
    lower(trim(coalesce(source.source_values ->> 'Injury Tissue Type/s', ''))) as source_tissue_evidence,
    exists (
      select 1 from jsonb_each_text(source.source_values) item
      where (
        item.key in ('Description', 'Injury Tissue Type/s', 'Body Part', 'Mechanism of Injury',
          'Mechanism Notes', 'Treatment/Rehab', 'Injury Immediate Action', 'Injury Status', 'Medical System')
        or lower(item.key) ~ '(hia|concussion|head injury assessment|return.?to.?play|(^|[^a-z])rtp([^a-z]|$)|diagnos)'
      ) and lower(trim(coalesce(item.value, ''))) ~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
        and lower(trim(coalesce(item.value, ''))) !~ '(no|not|negative( for)?|passed|clear(ed)?|ruled out|without|did not).{0,32}(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'
        and lower(trim(coalesce(item.value, ''))) !~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M).{0,32}(negative|passed|clear(ed)?|ruled out|not diagnosed)'
    ) as has_positive_concussion_text,
    injury.date_injured is null as is_undated, season_window.cohort_view_version
  from analysis.analysis_window_active_builds_v6 member
  join curated.injuries injury on injury.curated_build_id = member.curated_build_id
   and injury.team_key = member.team_key and injury.season = member.season
  join ingestion.source_rows source on source.id = injury.source_row_id
  join analysis.reporting_season_windows_v3 season_window
    on season_window.cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
   and season_window.season = member.season
  join analysis.accepted_analysis_window_cohort_rules_v6 cohort_rules
    on cohort_rules.cohort_view_version = season_window.cohort_view_version
   and cohort_rules.season = season_window.season
  cross join analysis.accepted_year2_reporting_classification_rules_v6 classification_rules
  where classification_rules.classification_view_version = 'reporting_classification_2026-07-22_v2'
    and injury.problem_type = 'injury'
    and injury.eligibility_status = 'included_pending_protocol'
    and (injury.date_injured between season_window.season_start and season_window.season_end or injury.date_injured is null)
), initial_diagnosis as (
  select source_evidence.*,
    case when orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')
          or has_positive_concussion_text then 'concussion'
      when body_location_code = 'unknown' or injury_type_code = 'unknown' then 'unknown'
      else concat('compound__', body_location_code, '__', injury_type_code) end as predecessor_diagnosis_code
  from source_evidence
), body_candidates as (
  select evidence.injury_id, mapping.mapped_body_location_code as body_code, 'exact_osiics'::text as origin
  from initial_diagnosis evidence join analysis.osiics_exact_ioc_mapping_v1 mapping on mapping.source_code = evidence.orchard_code
  where evidence.predecessor_diagnosis_code = 'unknown'
  union all
  select evidence.injury_id, candidate.body_code, 'strict_osiics_prefix'
  from initial_diagnosis evidence cross join lateral (values
    ('H','head'),('N','neck'),('S','shoulder'),('U','upper_arm'),('E','elbow'),('R','forearm'),('W','wrist'),('P','hand'),
    ('C','chest'),('D','thoracic_spine'),('L','lumbosacral'),('O','abdomen'),('G','hip_groin'),('T','thigh'),('K','knee'),
    ('Q','lower_leg'),('A','ankle'),('F','foot'),('Z','unspecified'),('X','multiple')
  ) candidate(prefix, body_code)
  where evidence.predecessor_diagnosis_code = 'unknown'
    and evidence.orchard_code ~ '^[HNSUERWPCDLOGTKQAFZX][A-Z]' and left(evidence.orchard_code, 1) = candidate.prefix
  union all
  select evidence.injury_id, candidate.body_code, 'explicit_text'
  from initial_diagnosis evidence cross join lateral (values
    ('head', evidence.clinical_evidence ~ '(head injury|facial|skull|jaw|concuss)'),
    ('neck', evidence.clinical_evidence ~ '\m(neck|cervical)\M'),
    ('shoulder', evidence.clinical_evidence ~ '(\mshoulder\M|acromioclavicular|\mac joint\M|\ma/c joint\M|\mclavicle\M|scapul)'),
    ('upper_arm', evidence.clinical_evidence ~ '(\mupper arm\M|humerus|humeral)'), ('elbow', evidence.clinical_evidence ~ '\melbow\M'),
    ('forearm', evidence.clinical_evidence ~ '\mforearm\M'), ('wrist', evidence.clinical_evidence ~ '(\mwrist\M|carpal|scaphoid)'),
    ('hand', evidence.clinical_evidence ~ '(\mhand\M|\mfinger\M|\mthumb\M|metacarp)'),
    ('chest', evidence.clinical_evidence ~ '(\mchest\M|\mrib(s)?\M|sternum|sternal|pectoral)'),
    ('thoracic_spine', evidence.clinical_evidence ~ '(thoracic spine|costovertebral)'),
    ('lumbosacral', evidence.clinical_evidence ~ '(lumbar|lumbosacral|\msacrum\M|\msacral\M|\mcoccyx\M|\mbuttock\M)'),
    ('abdomen', evidence.clinical_evidence ~ '(\mabdomen\M|abdominal)'),
    ('hip_groin', evidence.clinical_evidence ~ '(\mhip\M|\mgroin\M|inguinal|\madductor\M)'),
    ('thigh', evidence.clinical_evidence ~ '(\mthigh\M|hamstring|biceps femoris|semitend|semimembran|quadriceps|rectus femoris|\mvastus\M)'),
    ('knee', evidence.clinical_evidence ~ '(\mknee\M|patell|menisc|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|cruciate)'),
    ('lower_leg', evidence.clinical_evidence ~ '(\mlower leg\M|\mcalf\M|gastrocnemius|\mgastroc\M|\msoleus\M|achilles|\mshin\M)'),
    ('ankle', evidence.clinical_evidence ~ '(\mankle\M|syndesmo|high ankle sprain)'),
    ('foot', evidence.clinical_evidence ~ '(\mfoot\M|\mtoe\M|metatars|lisfranc|calcane|plantar)')
  ) candidate(body_code, matches)
  where evidence.predecessor_diagnosis_code = 'unknown' and candidate.matches
  union all
  select evidence.injury_id, multi.mapped_body_location_code, 'adjudicated_multi_type_osiics'
  from initial_diagnosis evidence join analysis.osiics_multi_type_diagnosis_v1 multi on multi.source_code = evidence.orchard_code
  where evidence.predecessor_diagnosis_code = 'unknown'
), body_summary as (
  select injury_id, count(distinct body_code)::int as candidate_count, min(body_code) as sole_candidate,
    bool_or(origin in ('exact_osiics', 'strict_osiics_prefix')) as has_code_origin
  from body_candidates group by injury_id
), body_resolved as (
  select evidence.*,
    case when evidence.body_location_code <> 'unknown' then evidence.body_location_code
      when coalesce(summary.candidate_count, 0) = 1 then summary.sole_candidate else 'unknown' end as effective_body_location_code,
    case when evidence.body_location_code <> 'unknown' then 'predecessor_curated'
      when coalesce(summary.candidate_count, 0) = 1 and summary.has_code_origin then 'mapped_from_osiics_body'
      when coalesce(summary.candidate_count, 0) = 1 then 'inferred_from_explicit_body_text' else 'remaining_unknown' end as body_location_origin,
    coalesce(summary.candidate_count, 0) as body_evidence_candidate_count, summary.sole_candidate as sole_body_evidence_candidate
  from initial_diagnosis evidence left join body_summary summary using (injury_id)
), type_candidates as (
  select evidence.injury_id, mapping.mapped_injury_type_code as type_code, 'exact_osiics'::text as origin
  from body_resolved evidence join analysis.osiics_exact_ioc_mapping_v1 mapping on mapping.source_code = evidence.orchard_code
  where evidence.predecessor_diagnosis_code = 'unknown' and evidence.injury_type_code = 'unknown'
    and mapping.mapped_body_location_code = evidence.effective_body_location_code
  union all
  select evidence.injury_id, candidate.type_code, 'explicit_text'
  from body_resolved evidence cross join lateral (values
    ('brain_spinal_cord_injury', evidence.clinical_evidence ~ '(concuss(ion|ed)?|brain injury|spinal cord injury)'),
    ('tendon_rupture', evidence.clinical_evidence ~ '(tendon|achilles).{0,18}(ruptur|complete tear)|(ruptur|complete tear).{0,18}(tendon|achilles)'),
    ('bone_stress_injury', evidence.clinical_evidence ~ '(stress fracture|bone stress|stress reaction|shin splints)'),
    ('bone_contusion', evidence.clinical_evidence ~ '(bone contusion|bony contusion|bone bruise)'),
    ('fracture', evidence.clinical_evidence ~ '(fractur|broken bone)' and evidence.clinical_evidence !~ '(stress fracture|bone stress|stress reaction)'),
    ('peripheral_nerve_injury', evidence.clinical_evidence ~ '(\mnerve\M|brachial plexus|burner/stinger|\mstinger\M)'),
    ('cartilage_injury', evidence.clinical_evidence ~ '(osteochondral|\mcartilage\M|labral|labrum|menisc)'),
    ('arthritis', evidence.clinical_evidence ~ '(osteoarthritis|\marthritis\M)'),
    ('tendinopathy', evidence.clinical_evidence ~ '(tendinopathy|tendinosis|tendon injury|tendon strain|plantar fasci)' and evidence.clinical_evidence !~ '(ruptur|complete tear)'),
    ('bursitis', evidence.clinical_evidence ~ '\mbursitis\M'),
    ('synovitis_capsulitis', evidence.clinical_evidence ~ '(\msynovitis\M|\mcapsulitis\M|\mimpingement\M)' and evidence.clinical_evidence !~ '\mbursitis\M'),
    ('chronic_instability', evidence.clinical_evidence ~ '(chronic instability|recurrent instability)'),
    ('joint_sprain', evidence.clinical_evidence ~ '(\msprain(ed)?\M|\mligament\M|disloc|sublux|\macl\M|\mpcl\M|\mmcl\M|\mlcl\M|syndesmo|lisfranc)'),
    ('muscle_contusion', evidence.clinical_evidence ~ '(muscle contusion|muscle haematoma|intramuscular haematoma)'),
    ('laceration', evidence.clinical_evidence ~ '\mlacerat(ion|ed)\M'), ('abrasion', evidence.clinical_evidence ~ '\mabrasion\M'),
    ('contusion_superficial', evidence.clinical_evidence ~ '(\mcontusion\M|haematoma|hematoma|\mbruis(e|ed|ing)\M|dead leg)' and evidence.clinical_evidence !~ '(muscle contusion|muscle haematoma|intramuscular haematoma|bone contusion|bony contusion|bone bruise)'),
    ('muscle_injury', (evidence.source_tissue_evidence ~ '(^|[,;/])\s*muscle(s| injury)?\s*($|[,;/])'
      or evidence.clinical_evidence ~ '(muscle (strain|tear|rupture|injury)|((hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M).{0,24}(strain|tear|ruptur|injur))|((strain|tear|ruptur|injur).{0,24}(hamstring|gastrocnemius|\mgastroc\M|\msoleus\M|quadriceps|rectus femoris|\madductor\M)))')
      and evidence.clinical_evidence !~ '(muscle contusion|muscle haematoma|intramuscular haematoma)' and evidence.orchard_code <> 'QPS')
  ) candidate(type_code, matches)
  where evidence.predecessor_diagnosis_code = 'unknown' and evidence.injury_type_code = 'unknown' and candidate.matches
    and (evidence.body_evidence_candidate_count = 0 or (evidence.body_evidence_candidate_count = 1 and evidence.sole_body_evidence_candidate = evidence.effective_body_location_code))
), type_summary as (
  select injury_id, count(distinct type_code)::int as candidate_count, min(type_code) as sole_candidate,
    bool_or(origin = 'exact_osiics') as has_exact_code_origin
  from type_candidates group by injury_id
), resolved as (
  select body.*,
    case when body.injury_type_code <> 'unknown' then body.injury_type_code
      when multi.source_code is not null and multi.mapped_body_location_code = body.effective_body_location_code then multi.analysis_primary_type_code
      when coalesce(summary.candidate_count, 0) = 1 then summary.sole_candidate else 'unknown' end as effective_injury_type_code,
    case when body.injury_type_code <> 'unknown' then 'predecessor_curated'
      when multi.source_code is not null and multi.mapped_body_location_code = body.effective_body_location_code then 'adjudicated_multi_type_osiics_diagnosis'
      when coalesce(summary.candidate_count, 0) = 1 and summary.has_exact_code_origin then 'mapped_from_exact_osiics_code'
      when coalesce(summary.candidate_count, 0) = 1 then 'inferred_from_unique_explicit_type_text' else 'remaining_unknown' end as injury_type_origin,
    case when multi.source_code is not null and multi.mapped_body_location_code = body.effective_body_location_code
      then multi.diagnosis_code end as multi_diagnosis_code,
    case when multi.source_code is not null and multi.mapped_body_location_code = body.effective_body_location_code
      then multi.diagnosis_label end as multi_diagnosis_label,
    case when multi.source_code is not null and multi.mapped_body_location_code = body.effective_body_location_code
      then multi.candidate_injury_types end as candidate_injury_types
  from body_resolved body left join type_summary summary using (injury_id)
  left join analysis.osiics_multi_type_diagnosis_v1 multi on multi.source_code = body.orchard_code
   and body.predecessor_diagnosis_code = 'unknown' and body.injury_type_code = 'unknown'
), classified as (
  select resolved.*,
    case when resolved.predecessor_diagnosis_code <> 'unknown' then resolved.predecessor_diagnosis_code
      when resolved.multi_diagnosis_code is not null then resolved.multi_diagnosis_code
      when resolved.effective_body_location_code <> 'unknown'
       and resolved.effective_injury_type_code <> 'unknown'
        then concat('compound__', resolved.effective_body_location_code, '__', resolved.effective_injury_type_code)
      else 'unknown' end as effective_diagnosis_code,
    case when resolved.predecessor_diagnosis_code = 'concussion' then 'Concussion'
      when resolved.predecessor_diagnosis_code <> 'unknown'
        then concat(coalesce(body_label.label, 'Unknown'), ' · ', coalesce(type_label.label, 'Unknown'))
      when resolved.multi_diagnosis_label is not null then resolved.multi_diagnosis_label
      when resolved.effective_body_location_code <> 'unknown'
       and resolved.effective_injury_type_code <> 'unknown'
        then concat(coalesce(body_label.label, 'Unknown'), ' · ', coalesce(type_label.label, 'Unknown'))
      else 'Unknown diagnosis' end as effective_diagnosis_label,
    case when resolved.predecessor_diagnosis_code = 'concussion' then 'accepted_current_concussion_evidence'
      when resolved.predecessor_diagnosis_code <> 'unknown' then 'predecessor_curated'
      when resolved.multi_diagnosis_code is not null then 'adjudicated_multi_type_osiics_diagnosis'
      when resolved.effective_body_location_code <> 'unknown'
       and resolved.effective_injury_type_code <> 'unknown'
       and resolved.injury_type_origin = 'mapped_from_exact_osiics_code' then 'mapped_from_exact_osiics_code'
      when resolved.effective_body_location_code <> 'unknown'
       and resolved.effective_injury_type_code <> 'unknown' then 'inferred_from_unique_explicit_body_and_type_text'
      else 'remaining_unknown' end as diagnosis_origin
  from resolved
  left join curated.code_lists body_label
    on body_label.list_name = 'body_location' and body_label.code = resolved.effective_body_location_code
  left join curated.code_lists type_label
    on type_label.list_name = 'injury_type' and type_label.code = resolved.effective_injury_type_code
)
select classified.* from classified;

create view analysis.analysis_window_injury_cohort_v6
with (security_invoker = true) as
select classification.injury_id, classification.curated_build_id, classification.team_key, classification.season,
  classification.source_row_id, classification.date_injured, classification.days_lost, classification.is_time_loss,
  classification.setting_code, classification.effective_body_location_code as body_location_code,
  coalesce(body.label, 'Unknown') as body_location_label,
  classification.effective_injury_type_code as injury_type_code,
  coalesce(injury_type.label, 'Unknown') as injury_type_label,
  classification.effective_diagnosis_code as diagnosis_code,
  classification.effective_diagnosis_label as diagnosis_label,
  classification.diagnosis_origin,
  case when classification.observed_days_injured is null then 'unknown_or_censored'
    when classification.observed_days_injured = 0 then 'zero_days_medical_attention_only'
    when classification.observed_days_injured = 1 then 'one_day'
    when classification.observed_days_injured between 2 and 3 then 'two_to_three_days'
    when classification.observed_days_injured between 4 and 7 then 'four_to_seven_days'
    when classification.observed_days_injured between 8 and 28 then 'eight_to_twenty_eight_days'
    when classification.observed_days_injured > 28 then 'greater_than_twenty_eight_days'
    else 'unknown_or_censored' end as severity_code,
  classification.is_undated, classification.cohort_view_version
from analysis.analysis_window_reporting_classification_v6 classification
left join curated.code_lists body on body.list_name = 'body_location' and body.code = classification.effective_body_location_code
left join curated.code_lists injury_type on injury_type.list_name = 'injury_type' and injury_type.code = classification.effective_injury_type_code;

create view analysis.analysis_window_team_exposure_v6
with (security_invoker = true) as
select member.curated_build_id,member.team_key,member.season,exposure.player_uid,
  exposure.grain as reporting_grain,
  coalesce(exposure.session_date,exposure.week_start_date) as period_start,
  coalesce(exposure.session_date,exposure.week_start_date)+case when exposure.grain='weekly' then 6 else 0 end as period_end,
  exposure.minutes_clean,exposure.distance_m_clean,season_window.cohort_view_version
from analysis.analysis_window_active_builds_v6 member
join curated.exposure exposure on exposure.curated_build_id=member.curated_build_id
 and exposure.team_key=member.team_key and exposure.season=member.season
join analysis.reporting_season_windows_v3 season_window on season_window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and season_window.season=member.season
join analysis.accepted_analysis_window_cohort_rules_v6 accepted on accepted.cohort_view_version=season_window.cohort_view_version and accepted.season=season_window.season
where exposure.eligibility_status='included_pending_protocol'
  and coalesce(exposure.session_date,exposure.week_start_date) is not null
  and coalesce(exposure.session_date,exposure.week_start_date)<=season_window.season_end
  and coalesce(exposure.session_date,exposure.week_start_date)+case when exposure.grain='weekly' then 6 else 0 end>=season_window.season_start;

create view analysis.analysis_window_team_hours_v6
with (security_invoker = true) as
with exposure as (
  select curated_build_id,team_key,season,coalesce(sum(minutes_clean),0)/60 as total_hours,
    coalesce(sum(distance_m_clean),0)/1000 as distance_km,
    case when count(distinct reporting_grain)=1 then min(reporting_grain) else 'mixed' end as exposure_grain
  from analysis.analysis_window_team_exposure_v6 group by curated_build_id,team_key,season
), fixtures as (
  select member.team_key,member.season,count(*)*20.0 as match_hours
  from analysis.analysis_window_active_builds_v6 member
  join analysis.accepted_urc_fixtures_v6 fixture on fixture.season=member.season and (fixture.home_team_key=member.team_key or fixture.away_team_key=member.team_key)
  join analysis.reporting_season_windows_v3 season_window on season_window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and season_window.season=fixture.season
  where fixture.match_date between season_window.season_start and season_window.season_end
  group by member.team_key,member.season
)
select exposure.curated_build_id,exposure.team_key,exposure.season,exposure.total_hours,
  coalesce(fixtures.match_hours,0) as match_hours,
  exposure.total_hours-coalesce(fixtures.match_hours,0) as training_hours,
  exposure.distance_km,exposure.exposure_grain
from exposure left join fixtures using(team_key,season)
where exposure.total_hours>=coalesce(fixtures.match_hours,0);

create view analysis.analysis_window_team_summary_v6
with (security_invoker = true) as
select member.curated_build_id,member.team_key,member.season,
  count(cohort.injury_id) as recorded_injuries,
  count(cohort.injury_id) filter(where cohort.is_time_loss) as time_loss_injuries,
  coalesce(sum(cohort.days_lost) filter(where cohort.is_time_loss),0) as days_lost,
  avg(cohort.days_lost) filter(where cohort.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by cohort.days_lost)
    filter(where cohort.is_time_loss) as median_severity_days
from analysis.analysis_window_active_builds_v6 member
left join analysis.analysis_window_injury_cohort_v6 cohort using(curated_build_id,team_key,season)
group by member.curated_build_id,member.team_key,member.season;

create view analysis.analysis_window_monthly_v6
with (security_invoker = true) as
with exposure as (
 select curated_build_id,team_key,season,date_trunc('month',period_start)::date as month_start,
   sum(minutes_clean)/60 as exposure_hours,sum(distance_m_clean)/1000 as distance_km
 from analysis.analysis_window_team_exposure_v6 group by curated_build_id,team_key,season,date_trunc('month',period_start)
), injuries as (
 select curated_build_id,team_key,season,date_trunc('month',date_injured)::date as month_start,
   count(*) filter(where is_time_loss) as time_loss_injuries,coalesce(sum(days_lost) filter(where is_time_loss),0) as days_lost
 from analysis.analysis_window_injury_cohort_v6
 where cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and date_injured is not null
 group by curated_build_id,team_key,season,date_trunc('month',date_injured)
), months as (select curated_build_id,team_key,season,month_start from exposure union select curated_build_id,team_key,season,month_start from injuries)
select months.curated_build_id,months.team_key,months.season,months.month_start,to_char(months.month_start,'Mon YYYY') as month_label,
 coalesce(exposure.exposure_hours,0) as exposure_hours,coalesce(exposure.distance_km,0) as distance_km,
 coalesce(injuries.time_loss_injuries,0) as time_loss_injuries,coalesce(injuries.days_lost,0) as days_lost,
 analysis.rate_per_1000_v1(coalesce(injuries.time_loss_injuries,0),coalesce(exposure.exposure_hours,0)) as incidence_per_1000h,
 analysis.rate_per_1000_v1(coalesce(injuries.days_lost,0),coalesce(exposure.exposure_hours,0)) as burden_per_1000h
from months left join exposure using(curated_build_id,team_key,season,month_start) left join injuries using(curated_build_id,team_key,season,month_start);

create view analysis.analysis_window_league_monthly_v6
with (security_invoker = true) as
select season,month_start,month_label,sum(exposure_hours) as exposure_hours,sum(distance_km) as distance_km,
 sum(time_loss_injuries) as time_loss_injuries,sum(days_lost) as days_lost,
 analysis.rate_per_1000_v1(sum(time_loss_injuries),sum(exposure_hours)) as incidence_per_1000h,
 analysis.rate_per_1000_v1(sum(days_lost),sum(exposure_hours)) as burden_per_1000h
from analysis.analysis_window_monthly_v6 group by season,month_start,month_label;

create view analysis.analysis_window_league_summary_v6
with (security_invoker = true) as
select summary.season,sum(summary.recorded_injuries) as recorded_injuries,
 sum(summary.time_loss_injuries) as time_loss_injuries,sum(summary.days_lost) as days_lost,
  sum(summary.days_lost)/nullif(sum(summary.time_loss_injuries),0) as mean_severity_days,
  (select percentile_cont(0.5) within group (order by cohort.days_lost)
   from analysis.analysis_window_injury_cohort_v6 cohort
   where cohort.season=summary.season and cohort.is_time_loss) as median_severity_days,
  sum(hours.total_hours) as exposure_hours,sum(hours.match_hours) as match_exposure_hours,sum(hours.training_hours) as training_exposure_hours
from analysis.analysis_window_team_summary_v6 summary join analysis.analysis_window_team_hours_v6 hours using(curated_build_id,team_key,season)
group by summary.season;

create view analysis.team_dashboard_payload_analysis_window_v6
with (security_invoker = true) as
select member.team_key,member.season,null::uuid as team_release_id,member.curated_build_id,
 rules.classification_view_version,rules.classification_evidence_sha256,
 cohort.cohort_view_version,cohort.cohort_evidence_sha256,
 jsonb_build_object('generated_at',member.generated_at,'team',roster.display_name,'season',member.season,
  'analysis_window',jsonb_build_object('start',season_window.season_start,'end',season_window.season_end,'basis','Registered Year 2 reporting window.'),
  'method',jsonb_build_array('Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.','Burden = pooled days lost / pooled exposure hours × 1,000.','Season-attributed undated injuries are included in totals but excluded from monthly series.','Curated IOC categories are carried forward; unsupported mappings remain Unknown.'),
  'coverage',jsonb_build_object('hours',hours.total_hours,'match_hours',hours.match_hours,'training_hours',hours.training_hours,'distance_km',hours.distance_km,'exposure_grain',hours.exposure_grain,'exposure_rows',(select count(*) from analysis.analysis_window_team_exposure_v6 exposure where exposure.curated_build_id=member.curated_build_id),'exposed_players',(select count(distinct nullif(exposure.player_uid,'Unknown')) from analysis.analysis_window_team_exposure_v6 exposure where exposure.curated_build_id=member.curated_build_id),'weeks',(select count(distinct date_trunc('week',exposure.period_start)) from analysis.analysis_window_team_exposure_v6 exposure where exposure.curated_build_id=member.curated_build_id),'included_exposure_status','included_pending_protocol','analysis_window_start',season_window.season_start,'analysis_window_end',season_window.season_end),
  'headline',jsonb_build_array(jsonb_build_object('key','recorded_injuries','label','Recorded injuries','value',summary.recorded_injuries,'unit','injuries','formula','count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'),jsonb_build_object('key','time_loss_injuries','label','Time-loss injuries','value',summary.time_loss_injuries,'unit','injuries','formula','count(eligible injury rows where days lost > 0)'),jsonb_build_object('key','incidence_per_1000h','label','Incidence','value',analysis.rate_per_1000_v1(summary.time_loss_injuries,hours.total_hours),'unit','per 1,000 player-hours','numerator',summary.time_loss_injuries,'denominator',hours.total_hours,'formula','pooled time-loss injuries / pooled exposure hours * 1000'),jsonb_build_object('key','severity_mean_days','label','Mean severity','value',summary.mean_severity_days,'unit','days lost per injury','numerator',summary.days_lost,'denominator',summary.time_loss_injuries,'formula','pooled days lost / pooled time-loss injuries'),jsonb_build_object('key','severity_median_days','label','Median severity','value',summary.median_severity_days,'unit','days lost per injury','formula','median(days lost) across pooled time-loss injuries'),jsonb_build_object('key','burden_per_1000h','label','Burden','value',analysis.rate_per_1000_v1(summary.days_lost,hours.total_hours),'unit','days lost per 1,000 player-hours','numerator',summary.days_lost,'denominator',hours.total_hours,'formula','pooled days lost / pooled exposure hours * 1000')),
  'monthly',coalesce((select jsonb_agg(jsonb_build_object('month',monthly.month_label,'exposure_hours',monthly.exposure_hours,'distance_km',monthly.distance_km,'time_loss_injuries',monthly.time_loss_injuries,'days_lost',monthly.days_lost,'incidence_per_1000h',monthly.incidence_per_1000h,'burden_per_1000h',monthly.burden_per_1000h) order by monthly.month_start) from analysis.analysis_window_monthly_v6 monthly where monthly.curated_build_id=member.curated_build_id and monthly.team_key=member.team_key and monthly.season=member.season),'[]'::jsonb),
  'body_locations','[]'::jsonb,'injury_types','[]'::jsonb,'injury_profiles','[]'::jsonb,'injury_type_families','[]'::jsonb,'severity_distribution','[]'::jsonb,'setting_split','[]'::jsonb,'setting_metrics','[]'::jsonb,'contact_distribution','[]'::jsonb,'prior_season',jsonb_build_object('season','2024-25','status','frozen','note','Prior season remains frozen and is not recomputed by V6.'),'limitations',jsonb_build_array('Candidate is unavailable until all sixteen active member builds are present.')) as dashboard
from analysis.analysis_window_active_builds_v6 member
join analysis.analysis_window_team_summary_v6 summary using(curated_build_id,team_key,season)
join analysis.analysis_window_team_hours_v6 hours using(curated_build_id,team_key,season)
join reporting.teams roster on roster.team_key=member.team_key
join analysis.reporting_season_windows_v3 season_window on season_window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and season_window.season=member.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort on cohort.cohort_view_version=season_window.cohort_view_version and cohort.season=season_window.season
cross join analysis.accepted_year2_reporting_classification_rules_v6 rules
where rules.classification_view_version='reporting_classification_2026-07-22_v2';

create view analysis.league_dashboard_payload_analysis_window_v6
with (security_invoker = true) as
select summary.season,rules.classification_view_version,rules.classification_evidence_sha256,cohort.cohort_view_version,cohort.cohort_evidence_sha256,
 jsonb_build_object('generated_at',(select max(generated_at) from analysis.analysis_window_active_builds_v6),'team','URC Overall','season',summary.season,
  'analysis_window',jsonb_build_object('start',season_window.season_start,'end',season_window.season_end,'basis','Registered Year 2 reporting window.'),
  'method',jsonb_build_array('Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.','Burden = pooled days lost / pooled exposure hours × 1,000.','Season-attributed undated injuries are included in totals but excluded from monthly series.'),
  'coverage',jsonb_build_object('hours',summary.exposure_hours,'match_hours',summary.match_exposure_hours,'training_hours',summary.training_exposure_hours,'teams_included',16,'distance_km',(select coalesce(sum(distance_km),0) from analysis.analysis_window_league_monthly_v6),'exposure_rows',(select count(*) from analysis.analysis_window_team_exposure_v6),'exposed_players',(select count(distinct nullif(exposure.player_uid,'Unknown')) from analysis.analysis_window_team_exposure_v6 exposure),'weeks',(select count(distinct date_trunc('week',exposure.period_start)) from analysis.analysis_window_team_exposure_v6 exposure),'included_exposure_status','included_pending_protocol','analysis_window_start',season_window.season_start,'analysis_window_end',season_window.season_end),
  'headline',jsonb_build_array(jsonb_build_object('key','recorded_injuries','label','Recorded injuries','value',summary.recorded_injuries,'unit','injuries','formula','count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'),jsonb_build_object('key','time_loss_injuries','label','Time-loss injuries','value',summary.time_loss_injuries,'unit','injuries','formula','count(eligible injury rows where days lost > 0)'),jsonb_build_object('key','incidence_per_1000h','label','Incidence','value',analysis.rate_per_1000_v1(summary.time_loss_injuries,summary.exposure_hours),'unit','per 1,000 player-hours','numerator',summary.time_loss_injuries,'denominator',summary.exposure_hours,'formula','pooled time-loss injuries / pooled exposure hours * 1000'),jsonb_build_object('key','severity_mean_days','label','Mean severity','value',summary.mean_severity_days,'unit','days lost per injury','numerator',summary.days_lost,'denominator',summary.time_loss_injuries,'formula','pooled days lost / pooled time-loss injuries'),jsonb_build_object('key','severity_median_days','label','Median severity','value',summary.median_severity_days,'unit','days lost per injury','formula','median(days lost) across pooled time-loss injuries'),jsonb_build_object('key','burden_per_1000h','label','Burden','value',analysis.rate_per_1000_v1(summary.days_lost,summary.exposure_hours),'unit','days lost per 1,000 player-hours','numerator',summary.days_lost,'denominator',summary.exposure_hours,'formula','pooled days lost / pooled exposure hours * 1000')),
  'monthly',coalesce((select jsonb_agg(jsonb_build_object('month',monthly.month_label,'exposure_hours',monthly.exposure_hours,'distance_km',monthly.distance_km,'time_loss_injuries',monthly.time_loss_injuries,'days_lost',monthly.days_lost,'incidence_per_1000h',monthly.incidence_per_1000h,'burden_per_1000h',monthly.burden_per_1000h) order by monthly.month_start) from analysis.analysis_window_league_monthly_v6 monthly where monthly.season=summary.season),'[]'::jsonb),
  'body_locations','[]'::jsonb,'injury_types','[]'::jsonb,'injury_profiles','[]'::jsonb,'injury_type_families','[]'::jsonb,'severity_distribution','[]'::jsonb,'setting_split','[]'::jsonb,'setting_metrics','[]'::jsonb,'contact_distribution','[]'::jsonb,'prior_season',jsonb_build_object('season','2024-25','status','frozen','note','Prior season remains frozen and is not recomputed by V6.'),'limitations',jsonb_build_array('Candidate is unavailable until all sixteen active member builds are present.')) as dashboard
from analysis.analysis_window_league_summary_v6 summary
join analysis.reporting_season_windows_v3 season_window on season_window.cohort_view_version='analysis_window_2025-26_2026-08-15_v1' and season_window.season=summary.season
join analysis.accepted_analysis_window_cohort_rules_v6 cohort on cohort.cohort_view_version=season_window.cohort_view_version and cohort.season=season_window.season
cross join analysis.accepted_year2_reporting_classification_rules_v6 rules
where rules.classification_view_version='reporting_classification_2026-07-22_v2';

create view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select team_key,season,team_release_id,curated_build_id,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard
from analysis.team_dashboard_payload_analysis_window_v6;

create view analysis.league_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select season,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard
from analysis.league_dashboard_payload_analysis_window_v6;

-- Curated-only display successors.  Every profile retains the total ('all')
-- alongside its actual activity setting.  Denominators therefore mean the
-- same thing for the all, match and training rows, while unknown-setting rows
-- remain descriptive rather than being assigned a false exposure denominator.
create view analysis.analysis_window_profile_rows_v6
with (security_invoker = true) as
select cohort.curated_build_id, cohort.team_key, cohort.season,
  'all'::text as setting_code, dimension, code, label, cohort.days_lost
from analysis.analysis_window_injury_cohort_v6 cohort
cross join lateral(values
 ('body_location'::text, cohort.body_location_code, cohort.body_location_label),
 ('injury_type'::text, cohort.injury_type_code, cohort.injury_type_label),
 ('diagnosis'::text, cohort.diagnosis_code, cohort.diagnosis_label),
 ('injury_profile'::text, cohort.body_location_code || '__' || cohort.injury_type_code,
  cohort.body_location_label || ' · ' || cohort.injury_type_label)
) d(dimension, code, label)
where cohort.is_time_loss
union all
select cohort.curated_build_id, cohort.team_key, cohort.season,
  cohort.setting_code, dimension, code, label, cohort.days_lost
from analysis.analysis_window_injury_cohort_v6 cohort
cross join lateral(values
 ('body_location'::text, cohort.body_location_code, cohort.body_location_label),
 ('injury_type'::text, cohort.injury_type_code, cohort.injury_type_label),
 ('diagnosis'::text, cohort.diagnosis_code, cohort.diagnosis_label),
 ('injury_profile'::text, cohort.body_location_code || '__' || cohort.injury_type_code,
  cohort.body_location_label || ' · ' || cohort.injury_type_label)
) d(dimension, code, label)
where cohort.is_time_loss;

create view analysis.analysis_window_profiles_v6
with (security_invoker = true) as
select profile.curated_build_id, profile.team_key, profile.season,
  profile.setting_code, profile.dimension, profile.code, profile.label,
  count(*) as time_loss_injuries, sum(profile.days_lost) as days_lost,
  case profile.setting_code
    when 'all' then hours.total_hours
    when 'match' then hours.match_hours
    when 'training' then hours.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(count(*), case profile.setting_code
    when 'all' then hours.total_hours
    when 'match' then hours.match_hours
    when 'training' then hours.training_hours
    else null
  end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(sum(profile.days_lost), case profile.setting_code
    when 'all' then hours.total_hours
    when 'match' then hours.match_hours
    when 'training' then hours.training_hours
    else null
  end) as burden_per_1000h,
  sum(profile.days_lost) / nullif(count(*), 0) as mean_severity_days
from analysis.analysis_window_profile_rows_v6 profile
join analysis.analysis_window_team_hours_v6 hours
  using(curated_build_id, team_key, season)
group by profile.curated_build_id, profile.team_key, profile.season,
  profile.setting_code, profile.dimension, profile.code, profile.label,
  hours.total_hours, hours.match_hours, hours.training_hours;

create view analysis.analysis_window_setting_metrics_v6
with (security_invoker = true) as
with observed as (
  select curated_build_id, team_key, season, 'all'::text as setting_code,
    is_time_loss, days_lost
  from analysis.analysis_window_injury_cohort_v6
  union all
  select curated_build_id, team_key, season, setting_code, is_time_loss, days_lost
  from analysis.analysis_window_injury_cohort_v6
), grouped as (
  select curated_build_id, team_key, season, setting_code,
    count(*) filter(where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter(where is_time_loss), 0) as days_lost
  from observed
  group by curated_build_id, team_key, season, setting_code
), setting_domain(setting_code) as (
  values ('all'), ('match'), ('training'), ('unknown')
)
select hours.curated_build_id, hours.team_key, hours.season,
 setting_domain.setting_code,
 coalesce(grouped.time_loss_injuries, 0)::bigint as time_loss_injuries,
 coalesce(grouped.days_lost, 0) as days_lost,
 case setting_domain.setting_code
   when 'all' then hours.total_hours
   when 'match' then hours.match_hours
   when 'training' then hours.training_hours
   else null
 end as exposure_hours
from analysis.analysis_window_team_hours_v6 hours
cross join setting_domain
left join grouped using(curated_build_id, team_key, season, setting_code);

create view analysis.analysis_window_severity_v6 with (security_invoker=true) as
select curated_build_id,team_key,season,severity_code,count(*) as recorded_injuries,
 count(*) filter(where is_time_loss) as time_loss_injuries,
 coalesce(sum(days_lost) filter(where is_time_loss),0) as days_lost
from analysis.analysis_window_injury_cohort_v6 group by curated_build_id,team_key,season,severity_code;

create view analysis.analysis_window_contact_distribution_v6
with (security_invoker = true) as
with observed as (
  select cohort.curated_build_id, cohort.team_key, cohort.season,
    cohort.setting_code, coalesce(injury.contact_context, 'unknown') as contact_context,
    count(*) as recorded_injuries,
    count(*) filter(where cohort.is_time_loss) as time_loss_injuries
  from analysis.analysis_window_injury_cohort_v6 cohort
  join curated.injuries injury on injury.id = cohort.injury_id
  group by cohort.curated_build_id, cohort.team_key, cohort.season,
    cohort.setting_code, coalesce(injury.contact_context, 'unknown')
  union all
  select cohort.curated_build_id, cohort.team_key, cohort.season,
    'all'::text, coalesce(injury.contact_context, 'unknown'),
    count(*), count(*) filter(where cohort.is_time_loss)
  from analysis.analysis_window_injury_cohort_v6 cohort
  join curated.injuries injury on injury.id = cohort.injury_id
  group by cohort.curated_build_id, cohort.team_key, cohort.season,
    coalesce(injury.contact_context, 'unknown')
), setting_domain(setting_code) as (
  values ('all'), ('match'), ('training'), ('unknown')
), contact_domain(contact_context, contact_label) as (
  values ('contact', 'Contact'), ('non_contact', 'Non-contact'), ('unknown', 'Unknown')
)
select member.curated_build_id, member.team_key, member.season,
  setting_domain.setting_code, contact_domain.contact_context,
  contact_domain.contact_label,
  coalesce(observed.recorded_injuries, 0)::bigint as recorded_injuries,
  coalesce(observed.time_loss_injuries, 0)::bigint as time_loss_injuries
from analysis.analysis_window_active_builds_v6 member
cross join setting_domain
cross join contact_domain
left join observed using(curated_build_id, team_key, season, setting_code, contact_context);

create view analysis.team_dashboard_payload_analysis_window_v6_enriched with (security_invoker=true) as
select base.team_key, base.season, base.team_release_id, base.curated_build_id,
 base.classification_view_version, base.classification_evidence_sha256,
 base.cohort_view_version, base.cohort_evidence_sha256,
 base.dashboard || jsonb_build_object(
  'body_locations',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by code) from analysis.analysis_window_profiles_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season and dimension='body_location' and setting_code='all'),'[]'::jsonb),
  'injury_types',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by time_loss_injuries desc,code) from analysis.analysis_window_profiles_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season and dimension='injury_type' and setting_code='all'),'[]'::jsonb),
  'injury_profiles',coalesce((select jsonb_agg(jsonb_build_object('dimension',dimension,'code',code,'label',label,'setting',setting_code,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by dimension,setting_code,code) from analysis.analysis_window_profiles_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'severity_distribution',coalesce((select jsonb_agg(jsonb_build_object('key',severity_code,'label',initcap(replace(severity_code,'_',' ')),'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost) order by severity_code) from analysis.analysis_window_severity_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'setting_metrics',coalesce((select jsonb_agg(jsonb_build_object('setting',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',analysis.rate_per_1000_v1(time_loss_injuries,exposure_hours),'burden_per_1000h',analysis.rate_per_1000_v1(days_lost,exposure_hours),'mean_severity_days',days_lost/nullif(time_loss_injuries,0)) order by setting_code) from analysis.analysis_window_setting_metrics_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'setting_split',coalesce((select jsonb_agg(jsonb_build_object('key',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours) order by setting_code) from analysis.analysis_window_setting_metrics_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb),
  'contact_distribution',coalesce((select jsonb_agg(jsonb_build_object('key',contact_context,'label',contact_label,'setting',setting_code,'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries) order by array_position(array['all','match','training','unknown'],setting_code),array_position(array['contact','non_contact','unknown'],contact_context)) from analysis.analysis_window_contact_distribution_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb))
 || jsonb_build_object('injury_type_families',analysis.injury_type_families_from_payload_v1(
   coalesce((select jsonb_agg(jsonb_build_object('dimension',dimension,'code',code,'label',label,'setting',setting_code,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by dimension,setting_code,code) from analysis.analysis_window_profiles_v6 where curated_build_id=base.curated_build_id and team_key=base.team_key and season=base.season),'[]'::jsonb)
 )) as dashboard
from analysis.team_dashboard_payload_analysis_window_v6 base;

create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6 with (security_invoker=true) as
select team_key,season,team_release_id,curated_build_id,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard from analysis.team_dashboard_payload_analysis_window_v6_enriched;

create view analysis.analysis_window_league_profiles_v6 with (security_invoker=true) as
with grouped as (
  select season, setting_code, dimension, code, label,
    sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost
  from analysis.analysis_window_profiles_v6
  group by season, setting_code, dimension, code, label
)
select grouped.season, grouped.setting_code, grouped.dimension, grouped.code,
  grouped.label, grouped.time_loss_injuries, grouped.days_lost,
  case grouped.setting_code
    when 'all' then summary.exposure_hours
    when 'match' then summary.match_exposure_hours
    when 'training' then summary.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(grouped.time_loss_injuries, case grouped.setting_code
    when 'all' then summary.exposure_hours
    when 'match' then summary.match_exposure_hours
    when 'training' then summary.training_exposure_hours
    else null
  end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(grouped.days_lost, case grouped.setting_code
    when 'all' then summary.exposure_hours
    when 'match' then summary.match_exposure_hours
    when 'training' then summary.training_exposure_hours
    else null
  end) as burden_per_1000h,
  grouped.days_lost / nullif(grouped.time_loss_injuries, 0) as mean_severity_days
from grouped
join analysis.analysis_window_league_summary_v6 summary using(season);

create view analysis.analysis_window_league_setting_metrics_v6 with (security_invoker=true) as
with grouped as (
  select season, setting_code, sum(time_loss_injuries) as time_loss_injuries,
    sum(days_lost) as days_lost
  from analysis.analysis_window_setting_metrics_v6
  group by season, setting_code
)
select grouped.season, grouped.setting_code, grouped.time_loss_injuries,
  grouped.days_lost,
  case grouped.setting_code
    when 'all' then summary.exposure_hours
    when 'match' then summary.match_exposure_hours
    when 'training' then summary.training_exposure_hours
    else null
  end as exposure_hours
from grouped
join analysis.analysis_window_league_summary_v6 summary using(season);

create view analysis.analysis_window_league_severity_v6 with (security_invoker=true) as
select season,severity_code,sum(recorded_injuries) as recorded_injuries,
 sum(time_loss_injuries) as time_loss_injuries,sum(days_lost) as days_lost
from analysis.analysis_window_severity_v6 group by season,severity_code;

create view analysis.analysis_window_league_contact_distribution_v6 with (security_invoker=true) as
select season, setting_code, contact_context, contact_label,
  sum(recorded_injuries) as recorded_injuries,
  sum(time_loss_injuries) as time_loss_injuries
from analysis.analysis_window_contact_distribution_v6
group by season, setting_code, contact_context, contact_label;

create view analysis.league_dashboard_payload_analysis_window_v6_enriched with (security_invoker=true) as
select base.season, base.classification_view_version,
 base.classification_evidence_sha256, base.cohort_view_version,
 base.cohort_evidence_sha256,
 base.dashboard || jsonb_build_object(
  'body_locations',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by code) from analysis.analysis_window_league_profiles_v6 where season=base.season and dimension='body_location' and setting_code='all'),'[]'::jsonb),
  'injury_types',coalesce((select jsonb_agg(jsonb_build_object('key',code,'label',label,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by time_loss_injuries desc,code) from analysis.analysis_window_league_profiles_v6 where season=base.season and dimension='injury_type' and setting_code='all'),'[]'::jsonb),
  'injury_profiles',coalesce((select jsonb_agg(jsonb_build_object('dimension',dimension,'code',code,'label',label,'setting',setting_code,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by dimension,setting_code,code) from analysis.analysis_window_league_profiles_v6 where season=base.season),'[]'::jsonb),
  'severity_distribution',coalesce((select jsonb_agg(jsonb_build_object('key',severity_code,'label',initcap(replace(severity_code,'_',' ')),'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost) order by severity_code) from analysis.analysis_window_league_severity_v6 where season=base.season),'[]'::jsonb),
  'setting_metrics',coalesce((select jsonb_agg(jsonb_build_object('setting',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',analysis.rate_per_1000_v1(time_loss_injuries,exposure_hours),'burden_per_1000h',analysis.rate_per_1000_v1(days_lost,exposure_hours),'mean_severity_days',days_lost/nullif(time_loss_injuries,0)) order by setting_code) from analysis.analysis_window_league_setting_metrics_v6 where season=base.season),'[]'::jsonb),
  'setting_split',coalesce((select jsonb_agg(jsonb_build_object('key',setting_code,'label',initcap(setting_code),'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours) order by setting_code) from analysis.analysis_window_league_setting_metrics_v6 where season=base.season),'[]'::jsonb),
  'contact_distribution',coalesce((select jsonb_agg(jsonb_build_object('key',contact_context,'label',contact_label,'setting',setting_code,'recorded_injuries',recorded_injuries,'time_loss_injuries',time_loss_injuries) order by array_position(array['all','match','training','unknown'],setting_code),array_position(array['contact','non_contact','unknown'],contact_context)) from analysis.analysis_window_league_contact_distribution_v6 where season=base.season),'[]'::jsonb))
 || jsonb_build_object('injury_type_families',analysis.injury_type_families_from_payload_v1(
   coalesce((select jsonb_agg(jsonb_build_object('dimension',dimension,'code',code,'label',label,'setting',setting_code,'time_loss_injuries',time_loss_injuries,'days_lost',days_lost,'exposure_hours',exposure_hours,'incidence_per_1000h',incidence_per_1000h,'burden_per_1000h',burden_per_1000h,'mean_severity_days',mean_severity_days) order by dimension,setting_code,code) from analysis.analysis_window_league_profiles_v6 where season=base.season),'[]'::jsonb)
 )) as dashboard
from analysis.league_dashboard_payload_analysis_window_v6 base;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6 with (security_invoker=true) as
select season,'v6'::text as analysis_version,classification_view_version,classification_evidence_sha256,cohort_view_version,cohort_evidence_sha256,dashboard from analysis.league_dashboard_payload_analysis_window_v6_enriched;
