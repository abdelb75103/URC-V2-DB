-- Additive Year 2 eligibility successor. It admits a null injury date only
-- when the latest immutable processing state records the checksum-bound
-- season_attributed_undated basis. It does not alter any 2024-25 relation.

insert into audit.reason_codes (code, description) values
  ('season_attributed_undated_injury', 'A checksum-bound 2025-26 input has a blank source injury date but is explicitly attributed to the registered season. No date was fabricated.'),
  ('explicit_source_exclusion', 'A checksum-bound 2025-26 analysis audit records an explicit non-placeholder source exclusion.')
on conflict (code) do update set description = excluded.description;

create view analysis.accepted_urc_2025_26_injury_eligibility_bridge_evidence_v6
with (security_invoker = true) as
select
  'urc_2025_26_injury_eligibility_bridge_v1'::text as rule_version,
  'a47d89700b22fdc3c9aa91203aed5227fbf76a2e4e7eab7dd8f18f9e13092ea1'::text as evidence_sha256,
  '01dd17a82ab1835fd84f2c84048b9e15b4072a4f9bca3b3d3a348817a68d7241'::text as protected_successor_root_manifest_sha256,
  '5ea322d4e246510ce82075f5690ea2ac5715dace31ead35bff9db3bacc6a7abd'::text as protected_successor_file_set_sha256
where (
  select count(*)
  from audit.reason_codes
  where code in ('season_attributed_undated_injury', 'explicit_source_exclusion')
) = 2;

create or replace view analysis.analysis_window_injury_cohort_v6
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
cross join analysis.accepted_urc_2025_26_injury_eligibility_bridge_evidence_v6 bridge
left join curated.code_lists body
  on body.list_name = 'body_location' and body.code = classification.effective_body_location_code
left join curated.code_lists injury_type
  on injury_type.list_name = 'injury_type' and injury_type.code = classification.effective_injury_type_code
where classification.date_injured is not null
   or exists (
     select 1
     from processing.record_versions rv
     where rv.source_row_id = classification.source_row_id
       and rv.eligibility_status = 'included_pending_protocol'
       and rv.record_state ->> 'injury_date_basis' = 'season_attributed_undated'
       and rv.version_number = (
         select max(latest.version_number)
         from processing.record_versions latest
         where latest.source_row_id = classification.source_row_id
       )
   );
