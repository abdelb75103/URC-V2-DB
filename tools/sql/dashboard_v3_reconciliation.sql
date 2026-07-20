-- Read-only cohort reconciliation. Counts are intentionally split instead of
-- forcing unlike V1/V2 definitions to agree.
with builds as (
  select * from analysis.league_member_releases_v2 where season = '2024-25'
), pinned as (
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
    lower(trim(concat_ws(' ',
      sr.source_values ->> 'Description',
      sr.source_values ->> 'Injury Tissue Type/s',
      sr.source_values ->> 'Body Part'
    ))) as narrow_clinical_evidence,
    lower(concat_ws(' ',
      sr.source_values ->> 'Description',
      sr.source_values ->> 'Orchard Code',
      sr.source_values ->> 'Injury Tissue Type/s',
      sr.source_values ->> 'Body Part'
    )) as legacy_evidence
  from curated.injuries i
  join builds b
    on b.curated_build_id = i.curated_build_id
   and b.team_key = i.team_key and b.season = i.season
  join ingestion.source_rows sr on sr.id = i.source_row_id
), eligible_injury_records as (
  select *
  from pinned
  where eligibility_status not in ('excluded_from_analysis', 'excluded_duplicate_adjudicated')
    and problem_type = 'injury'
), attributed_unbounded as (
  select *
  from eligible_injury_records
  where (received_in_team_status is null or received_in_team_status not in ('other_team', 'club'))
    and (urc_match_scope is null or urc_match_scope <> 'non_urc_marker')
    and source_match_type <> 'italian elite championship'
), attributed_descriptive as (
  select *
  from attributed_unbounded
  where date_injured is null
    or date_injured between date '2024-07-01' and date '2025-06-30'
), legacy_diagnosis_candidates as (
  select d.id, x.code, x.diagnosis_subtype, x.profile_code
  from attributed_descriptive d
  cross join lateral (values
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
  ) x(code, diagnosis_subtype, profile_code, matches)
  where x.matches
), legacy_diagnosis_candidate_summary as (
  select id, count(distinct code)::int as candidate_count,
    count(distinct diagnosis_subtype)::int as subtype_candidate_count
  from legacy_diagnosis_candidates
  group by id
), attributed_with_legacy as (
  select d.*, coalesce(l.candidate_count, 0) as legacy_diagnosis_candidate_count,
    coalesce(l.subtype_candidate_count, 0) as legacy_diagnosis_subtype_candidate_count
  from attributed_descriptive d
  left join legacy_diagnosis_candidate_summary l on l.id = d.id
), rate_cohort as (
  select id as injury_id
  from attributed_descriptive
), teams as (
  select team_key from builds union all select 'urc'
), scoped_records as (
  select team_key as scope_key, p.* from pinned p
  union all select 'urc', p.* from pinned p
), scoped_eligible as (
  select team_key as scope_key, p.* from eligible_injury_records p
  union all select 'urc', p.* from eligible_injury_records p
), scoped_attributed as (
  select team_key as scope_key, p.* from attributed_with_legacy p
  union all select 'urc', p.* from attributed_with_legacy p
), scoped_attributed_unbounded as (
  select team_key as scope_key, p.* from attributed_unbounded p
  union all select 'urc', p.* from attributed_unbounded p
), scoped_rate as (
  select p.team_key as scope_key, p.*
  from attributed_descriptive p join rate_cohort r on r.injury_id = p.id
  union all
  select 'urc', p.*
  from attributed_descriptive p join rate_cohort r on r.injury_id = p.id
), origin_rows as (
  select scope_key, 'body_location'::text as field,
    coalesce(nullif(field_origins ->> 'body_location', ''), '<missing>') as origin,
    coalesce(body_location, 'unknown') <> 'unknown' as has_classified_value
  from scoped_attributed
  union all
  select scope_key, 'tissue_pathology',
    coalesce(nullif(field_origins ->> 'injury_type', ''), '<missing>'),
    coalesce(injury_type, 'unknown') <> 'unknown'
  from scoped_attributed
  union all
  select scope_key, 'contact_context',
    coalesce(nullif(field_origins ->> 'contact_context', ''), '<missing>'),
    coalesce(contact_context, 'unknown') <> 'unknown'
  from scoped_attributed
), origin_classes as (
  select *,
    case
      when not has_classified_value then 'remaining_unknown'
      when origin like 'manual_adjudication:%' then 'adjudicated'
      when origin in ('source_reported', 'approved_mapping:source_reported') then 'source_reported'
      when origin like 'inferred%' or origin like '%protocol_defined_inference%' then 'inferred'
      when origin like 'mapped_from_%' then 'mapped'
      else 'inferred'
    end as origin_class,
    has_classified_value
      and origin not like 'manual_adjudication:%'
      and origin not in ('source_reported', 'approved_mapping:source_reported')
      and origin not like 'inferred%'
      and origin not like '%protocol_defined_inference%'
      and origin not like 'mapped_from_%' as is_unclassified
  from origin_rows
), origin_class_counts as (
  select scope_key, field, origin, origin_class, is_unclassified, count(*)::int as count
  from origin_classes
  group by scope_key, field, origin, origin_class, is_unclassified
)
select jsonb_build_object(
  'status', 'draft_not_for_release',
  'season', '2024-25',
  'rule_version', 'urc-diagnosis-inference-v3-draft.9',
  'cohort_rule', 'season_bound_2024-07-01_2025-06-30_no_exposure_window',
  'definitions', jsonb_build_object(
    'pinned_records', 'All injury-table rows on the 16 immutable approved V2 member builds.',
    'eligible_injury_records', 'Pinned rows explicitly classified as injury after controlled duplicate/exclusion decisions; dates and attribution are not required.',
    'attributed_descriptive_cases', 'Eligible attributed injury records dated inside 2024-07-01..2025-06-30 or season-attributed with no injury date.',
    'exposure_aligned_rate_cases', 'Draft.9 season-bound attributed cases, including undated cases; no team exposure-window restriction is applied.',
    'diagnosis_unknown_exception', 'Unknown requires a missing standardised body or tissue input, except that cross-display-bucket named-diagnosis conflicts remain Unknown for adjudication.',
    'knee_ankle_ligament_families_display_under_ioc_joint_sprain_parent', 'Adjudicated display-taxonomy decision approved by Abdel on 20 Jul 2026 and grounded in the IOC 2020 joint_sprain tissue parent: knee named ligaments plus generic knee sprains display as Knee · Joint sprain; ankle lateral-ligament, syndesmosis, and generic ankle sprains display as Ankle · Joint sprain. Ligament specificity remains in diagnosis_subtype and each row retains its pre-display origin class.',
    'joint_sprain_scope_exceptions', 'Shoulder instability, AC joint sprain / separation, and Lisfranc injury remain distinct named diagnoses. Other joint-sprain compounds and named muscle diagnoses are unchanged.'
  ),
  'curated_origin_class_counts', (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'scope_key', o.scope_key,
        'field', o.field,
        'origin', o.origin,
        'origin_class', o.origin_class,
        'count', o.count
      ) order by o.scope_key, o.field, o.origin, o.origin_class
    ), '[]'::jsonb)
    from origin_class_counts o
  ),
  'unclassified_origins', (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'scope_key', o.scope_key,
        'field', o.field,
        'origin', o.origin,
        'count', o.count,
        'conservative_class', 'inferred'
      ) order by o.scope_key, o.field, o.origin
    ), '[]'::jsonb)
    from origin_class_counts o
    where o.is_unclassified
  ),
  'teams', jsonb_agg(jsonb_build_object(
    'team_key', t.team_key,
    'pinned_records', (select count(*) from scoped_records r where r.scope_key = t.team_key),
    'eligible_injury_records', (select count(*) from scoped_eligible r where r.scope_key = t.team_key),
    'attributed_descriptive_cases', (select count(*) from scoped_attributed r where r.scope_key = t.team_key),
    'exposure_aligned_rate_cases', (select count(*) from scoped_rate r where r.scope_key = t.team_key),
    'external_team_or_club_records', (select count(*) from scoped_eligible r where r.scope_key = t.team_key and r.received_in_team_status in ('other_team', 'club')),
    'explicit_non_urc_records', (select count(*) from scoped_eligible r where r.scope_key = t.team_key
      and (r.urc_match_scope = 'non_urc_marker' or r.source_match_type = 'italian elite championship')),
    'missing_injury_date', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and r.date_injured is null),
    'outside_exposure_window', (select count(*) from scoped_attributed_unbounded r where r.scope_key = t.team_key
      and r.date_injured is not null and r.date_injured not between date '2024-07-01' and date '2025-06-30'),
    'time_loss_outside_rate_cohort', (select count(*) from scoped_attributed_unbounded r where r.scope_key = t.team_key
      and (coalesce(r.days_injured, 0) > 0 or r.source_class in ('time loss', 'yes', 'true', '1'))
      and not exists (select 1 from rate_cohort c where c.injury_id = r.id)),
    'positive_day_cases_descriptive', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and coalesce(r.days_injured, 0) > 0),
    'source_reported_time_loss_descriptive', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and r.source_class in ('time loss', 'yes', 'true', '1')),
    'time_loss_union_descriptive', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and (coalesce(r.days_injured, 0) > 0 or r.source_class in ('time loss', 'yes', 'true', '1'))),
    'medical_attention_only_descriptive', (select count(*) from scoped_attributed r where r.scope_key = t.team_key
      and not (coalesce(r.days_injured, 0) > 0 or r.source_class in ('time loss', 'yes', 'true', '1'))
      and (r.source_class in ('medical attention', 'no', 'false', '0') or (r.days_injured = 0 and r.is_closed is true))),
    'consequence_unknown_after_inference', (select count(*) from scoped_attributed r where r.scope_key = t.team_key
      and not (coalesce(r.days_injured, 0) > 0 or r.source_class in ('time loss', 'yes', 'true', '1'))
      and not (r.source_class in ('medical attention', 'no', 'false', '0') or (r.days_injured = 0 and r.is_closed is true))),
    'source_reported_medical_attention_descriptive', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and r.source_class in ('medical attention', 'no', 'false', '0')),
    'source_consequence_unknown_descriptive', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and r.source_class = ''),
    'inference_partition_total', (select count(*) from scoped_attributed r where r.scope_key = t.team_key),
    'body_location_source_reported_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'body_location' and o.origin_class = 'source_reported'),
    'body_location_mapped_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'body_location' and o.origin_class = 'mapped'),
    'body_location_inferred_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'body_location' and o.origin_class = 'inferred'),
    'body_location_adjudicated_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'body_location' and o.origin_class = 'adjudicated'),
    'body_location_unknown_before_v3', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and coalesce(r.body_location, 'unknown') = 'unknown'),
    'tissue_pathology_source_reported_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'tissue_pathology' and o.origin_class = 'source_reported'),
    'tissue_pathology_mapped_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'tissue_pathology' and o.origin_class = 'mapped'),
    'tissue_pathology_inferred_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'tissue_pathology' and o.origin_class = 'inferred'),
    'tissue_pathology_adjudicated_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'tissue_pathology' and o.origin_class = 'adjudicated'),
    'tissue_pathology_unknown_before_v3', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and coalesce(r.injury_type, 'unknown') = 'unknown'),
    'contact_context_source_reported_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'contact_context' and o.origin_class = 'source_reported'),
    'contact_context_mapped_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'contact_context' and o.origin_class = 'mapped'),
    'contact_context_inferred_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'contact_context' and o.origin_class = 'inferred'),
    'contact_context_adjudicated_before_v3', (select count(*) from origin_classes o where o.scope_key = t.team_key and o.field = 'contact_context' and o.origin_class = 'adjudicated'),
    'contact_context_unknown_before_v3', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and coalesce(r.contact_context, 'unknown') = 'unknown'),
    'exact_concussion_code_rows', (select count(*) from scoped_attributed r where r.scope_key = t.team_key
      and r.orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')),
    'exact_concussion_code_rows_without_narrow_text', (select count(*) from scoped_attributed r where r.scope_key = t.team_key
      and r.orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')
      and r.narrow_clinical_evidence !~ '(concuss(ion|ed)?|head injury assessment|brain injury|\mhia\M|\msrc\M)'),
    'concussion_curated_body_conflicts', (select count(*) from scoped_attributed r where r.scope_key = t.team_key
      and r.orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')
      and coalesce(r.body_location, 'unknown') not in ('unknown', 'head')),
    'concussion_curated_tissue_conflicts', (select count(*) from scoped_attributed r where r.scope_key = t.team_key
      and r.orchard_code in ('HN1', 'HN2', 'HNC1', 'HNC2', 'HNCA', 'HNCD', 'HNCH', 'HNCN', 'HNCO', 'HNCX')
      and coalesce(r.injury_type, 'unknown') not in ('unknown', 'brain_spinal_cord_injury')),
    'diagnosis_unknown_before_v3', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and r.legacy_diagnosis_subtype_candidate_count <> 1),
    'diagnosis_legacy_multi_match_observed_before_draft6', (select count(*) from scoped_attributed r where r.scope_key = t.team_key and r.legacy_diagnosis_subtype_candidate_count > 1)
  ) order by t.team_key)
) as reconciliation
from teams t;
