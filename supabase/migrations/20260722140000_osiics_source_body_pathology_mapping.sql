-- Additive correction after the 20260722130000 transaction-level outcome gate
-- identified two explicit rows blocked by broad code-prefix/body boundaries.
-- Source and curated body values remain immutable and take precedence; QRA and
-- QBC supply exact reviewed pathology only. The full 121-row ledger and counts
-- are rebound to this migration before the classification can become accepted.

alter table audit.rule_adjudications
  drop constraint rule_adjudications_migration_version_check,
  add constraint rule_adjudications_migration_version_check check (
    migration_version in ('20260720150000', '20260722130000', '20260722140000')
  );

create or replace view analysis.osiics_exact_ioc_mapping_v1
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
  ('QBC','lower_leg','bursitis'),
  ('QRA','ankle','tendon_rupture'),('QRA','lower_leg','tendon_rupture'),
  ('QVVP','lower_leg','vascular_trauma'),('SL1','shoulder','joint_sprain'),
  ('SL2','shoulder','joint_sprain'),
  ('SQP','shoulder','synovitis_capsulitis'),('WC1','wrist','cartilage_injury')
) v(source_code, mapped_body_location_code, mapped_injury_type_code);

comment on view analysis.osiics_exact_ioc_mapping_v1 is
  'Reviewed OSIICS 15 / OSICS source-code pathology mappings. QRA preserves the supplied canonical Ankle or Lower leg body while mapping the exact Achilles tendon-rupture pathology. Bound to docs/evidence/osiics_exact_mapping_2024-25.json.';

create or replace view analysis.accepted_reporting_classification_rules_v4
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
  and r.evidence_sha256 = '1c233ca4f9c13ef61b666bda5c1f1eec004c6a4bb0cec7e90cda8a71df68c428'
  and r.workbook_sha256 = '8bfeab660942f9ff7a25ebeb42544c231d611365fb9ee36cec27233bc82157c5'
  and r.evidence_manifest_sha256 = 'db1823f5d402c9989ef7c053dcfd4aced637eab142f7d372e6b16f22b168ed7c'
  and r.migration_version = '20260722140000'
  and r.decision = '{
    "mapping_catalogue_sha256":"9b1f298883b7be0c2d64b6519b78957a04e594121c4d9463828f0e1b9a94980f",
    "multi_type_catalogue_sha256":"04ec0e97424b9c2128e555c475d0ab9c70b8c2d016c864909bc532ba73fbe0e7",
    "exact_code_candidate_count":111,
    "explicit_text_candidate_count":9,
    "multi_type_diagnosis_candidate_count":1,
    "unknown_before":245,
    "unknown_after":124,
    "preserve_original_values":true,
    "conflicts_remain_unknown":true
  }'::jsonb;

comment on view analysis.accepted_reporting_classification_rules_v4 is
  'Accepted OSIICS-01 evidence gate rebound to additive migration 20260722140000 and the exact 121-row post-decision ledger.';
