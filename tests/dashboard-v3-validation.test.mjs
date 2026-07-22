import assert from "node:assert/strict";
import { mkdir, symlink } from "node:fs/promises";
import test from "node:test";
import { resolve } from "node:path";
import {
  assertPrivatePreviewOutputPath,
  expectedOriginClass,
  validateDraft9ClassificationProfiles,
  validateDraft9DiagnosisBuckets,
  validateDraft9RuleChecks,
  validateDraft9SeasonBoundCohort,
  validateDraft9SettingDistributions,
  validateOriginClassCounts,
  validateLegacyMultiMatchRefusal,
} from "../tools/dashboard-v3-validation.mjs";

const projectRoot = resolve(new URL("../", import.meta.url).pathname);

test("preview outputs refuse public payload directories", async () => {
  await assert.rejects(
    assertPrivatePreviewOutputPath(resolve(projectRoot, "content/reporting/preview.json"), projectRoot, "--output"),
    /must not write under public payload directory/
  );
  await assert.rejects(
    assertPrivatePreviewOutputPath(resolve(projectRoot, "public/reconciliation.json"), projectRoot, "--reconciliation-output"),
    /must not write under public payload directory/
  );
  await assert.doesNotReject(
    assertPrivatePreviewOutputPath(resolve(projectRoot, "data/reporting/preview.json"), projectRoot, "--output")
  );
});

test("draft.9 rule checks enforce the IOC joint-sprain display fold and existing invariants", () => {
  const valid = {
    synthetic_concussion_case_failures: 0,
    legacy_concussion_case_failures: 0,
    profile_map_duplicate_source_codes: 0,
    acl_routes_to_joint_sprain_parent: true,
    legacy_knee_ligament_display_labels: 0,
    synthetic_display_taxonomy_case_failures: 0,
    display_taxonomy_origin_class_changes: 0,
    meniscus_routes_to_cartilage: true,
    synthetic_diagnosis_bucket_case_failures: 0,
    synthetic_compound_origin_case_failures: 0,
    within_bucket_multi_match_refusals: 0,
    cross_bucket_conflicts_classified: 0,
    compound_missing_input_failures: 0,
    unknown_with_complete_compound_inputs: 0,
    diagnosis_assignments: [{
      scope_key: "urc",
      diagnosis_bucket_rows: 900,
      diagnosis_unknown_rows: 1298,
      descriptive_cohort_rows: 2198,
      duplicate_injury_rows: 0,
    }],
    time_loss_profile_assignments: ["all", "match", "training"].map((setting_code) => ({
      scope_key: "urc",
      setting_code,
      classified_time_loss_rows: 350,
      profile_rows: 350,
    })),
  };
  assert.doesNotThrow(() => validateDraft9RuleChecks(valid));
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, synthetic_concussion_case_failures: 1 }),
    /synthetic concussion rule cases failed/
  );
  assert.throws(
    () => validateDraft9RuleChecks({
      ...valid,
      diagnosis_assignments: [{ ...valid.diagnosis_assignments[0], duplicate_injury_rows: 1 }],
    }),
    /appears more than once/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, acl_routes_to_joint_sprain_parent: false }),
    /joint-sprain parent label/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, synthetic_display_taxonomy_case_failures: 1 }),
    /display-taxonomy cases failed/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, display_taxonomy_origin_class_changes: 1 }),
    /changed provenance class/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, legacy_concussion_case_failures: 1 }),
    /fallback negation cases failed/
  );
  assert.throws(
    () => validateDraft9RuleChecks({
      ...valid,
      time_loss_profile_assignments: valid.time_loss_profile_assignments.slice(0, 2),
    }),
    /profile checks are missing training/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, synthetic_diagnosis_bucket_case_failures: 1 }),
    /synthetic diagnosis display-bucket cases failed/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, synthetic_compound_origin_case_failures: 1 }),
    /synthetic compound provenance cases failed/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, within_bucket_multi_match_refusals: 1 }),
    /within-bucket diagnosis multi-match was refused/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, cross_bucket_conflicts_classified: 1 }),
    /cross-bucket diagnosis conflict was classified/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, compound_missing_input_failures: 1 }),
    /tier-2 compound diagnosis is missing/
  );
  assert.throws(
    () => validateDraft9RuleChecks({ ...valid, unknown_with_complete_compound_inputs: 1 }),
    /complete body\+tissue evidence remained Unknown/
  );
});

test("preview outputs refuse a symlinked parent redirected into public payloads", async () => {
  const privateFixtureRoot = resolve(projectRoot, "data/tmp");
  const redirect = resolve(privateFixtureRoot, "dashboard-v3-public-redirect-test");
  await mkdir(privateFixtureRoot, { recursive: true });
  try {
    await symlink(resolve(projectRoot, "content"), redirect, "dir");
  } catch (error) {
    if (error?.code !== "EEXIST") throw error;
  }
  await assert.rejects(
    assertPrivatePreviewOutputPath(resolve(redirect, "blocked-preview.json"), projectRoot, "--output"),
    /must not write under public payload directory/
  );
});

test("origin strings enforce semantic provenance classes", () => {
  assert.equal(expectedOriginClass("approved_mapping:source_reported"), "source_reported");
  assert.equal(expectedOriginClass("manual_adjudication:reviewed"), "adjudicated");
  assert.equal(expectedOriginClass("inferred_from_evidence"), "inferred");
  assert.equal(expectedOriginClass("approved_mapping:protocol_defined_inference"), "inferred");
  assert.equal(expectedOriginClass("mapped_from_codebook"), "mapped");

  const uncertain = {
    scope_key: "example",
    field: "contact_context",
    origin: "approved_mapping:deterministic_derivation",
    origin_class: "inferred",
    count: 3,
  };
  const unclassified = [{ ...uncertain, conservative_class: "inferred" }];
  assert.doesNotThrow(() => validateOriginClassCounts([uncertain], unclassified));
  assert.throws(
    () => validateOriginClassCounts([{ ...uncertain, origin_class: "mapped" }], unclassified),
    /must conservatively be inferred/
  );
  assert.throws(
    () => validateOriginClassCounts([uncertain], []),
    /is not visible in unclassified_origins/
  );
  assert.throws(
    () => validateOriginClassCounts([{ ...uncertain, origin: "inferred_from_evidence", origin_class: "mapped" }]),
    /must be inferred, not mapped/
  );
});

test("legacy diagnosis multi-matches must remain Unknown and be ledgered", () => {
  const refused = [{
    id: "row-1",
    team_key: "example",
    field: "diagnosis",
    legacy_pattern_match_count: 2,
    draft_pattern_match_count: 0,
    resulting_value: "unknown",
  }];

  const reconciliation = { teams: [{
    team_key: "example",
    diagnosis_legacy_multi_match_observed_before_draft6: 1,
  }] };
  const checks = { legacy_multi_match_refusal_checks: [{
    scope_key: "example",
    expected_legacy_multi_match_refusals: 1,
  }] };

  assert.doesNotThrow(() => validateLegacyMultiMatchRefusal(refused, reconciliation, checks));
  assert.throws(
    () => validateLegacyMultiMatchRefusal([{ ...refused[0], resulting_value: "concussion" }], reconciliation, checks),
    /did not remain Unknown/
  );
  assert.throws(
    () => validateLegacyMultiMatchRefusal([], reconciliation, checks),
    /not fully ledgered/
  );
  assert.doesNotThrow(
    () => validateLegacyMultiMatchRefusal([{
      ...refused[0],
      draft_pattern_match_count: 1,
      resulting_value: "head__brain_spinal_cord_injury",
    }], { teams: [{ team_key: "example", diagnosis_legacy_multi_match_observed_before_draft6: 0 }] }, {
      legacy_multi_match_refusal_checks: [],
    })
  );
});

test("draft.9 season-bound cohort includes undated counts, excludes them monthly, and rounds bounded exposure", () => {
  const row = {
    team_key: "urc",
    rule_version: "urc-diagnosis-inference-v3-draft.9",
    cohort_rule: "season_bound_2024-07-01_2025-06-30_no_exposure_window",
    descriptive_consequence_summary: { recorded_injuries: 12, undated_injuries: 2 },
    rate_setting_metrics: [
      { setting: "all", exposure_hours: 100.1, time_loss_injuries: 7 },
      { setting: "match", exposure_hours: 20.0, time_loss_injuries: 4 },
      { setting: "training", exposure_hours: 80.1, time_loss_injuries: 3 },
    ],
    monthly_by_setting: [
      { setting: "all", recorded_injuries: 10, rate_time_loss_injuries: 6 },
    ],
  };
  assert.doesNotThrow(() => validateDraft9SeasonBoundCohort(row));
  assert.throws(
    () => validateDraft9SeasonBoundCohort({ ...row, descriptive_consequence_summary: { recorded_injuries: 13, undated_injuries: 2 } }),
    /undated injuries/
  );
  assert.throws(
    () => validateDraft9SeasonBoundCohort({ ...row, rate_setting_metrics: [{ setting: "all", exposure_hours: 100.12, time_loss_injuries: 7 }] }),
    /one decimal/
  );
});

test("severity and contact distributions uniquely reconcile all, match, and training", () => {
  const row = {
    team_key: "example",
    descriptive_consequence_summary: { recorded_injuries: 8 },
    rate_setting_metrics: [
      { setting: "all", time_loss_injuries: 5 },
      { setting: "match", time_loss_injuries: 3 },
      { setting: "training", time_loss_injuries: 2 },
    ],
    severity_distribution: [
      { setting: "all", key: "known", recorded_injuries: 6 },
      { setting: "all", key: "unknown", recorded_injuries: 2 },
      { setting: "match", key: "known", recorded_injuries: 4 },
      { setting: "training", key: "known", recorded_injuries: 4 },
    ],
    contact_distribution: [
      { setting: "all", key: "contact", recorded_injuries: 8, time_loss_injuries: 5 },
      { setting: "match", key: "contact", recorded_injuries: 4, time_loss_injuries: 3 },
      { setting: "training", key: "contact", recorded_injuries: 4, time_loss_injuries: 2 },
    ],
  };
  assert.doesNotThrow(() => validateDraft9SettingDistributions(row));
  assert.throws(
    () => validateDraft9SettingDistributions({
      ...row,
      rate_setting_metrics: row.rate_setting_metrics.filter((item) => item.setting !== "training"),
    }),
    /missing rate setting training/
  );
  assert.throws(
    () => validateDraft9SettingDistributions({
      ...row,
      severity_distribution: [...row.severity_distribution, row.severity_distribution[0]],
    }),
    /duplicate severity row all:known/
  );
  assert.throws(
    () => validateDraft9SettingDistributions({
      ...row,
      contact_distribution: row.contact_distribution.map((item) => item.setting === "training"
        ? { ...item, time_loss_injuries: 1 }
        : item),
    }),
    /training contact rows do not partition time-loss cases/
  );
  assert.throws(
    () => validateDraft9SettingDistributions({
      ...row,
      severity_distribution: row.severity_distribution.map((item) => item.setting === "match"
        ? { ...item, recorded_injuries: 3 }
        : item),
    }),
    /match severity and contact recorded-case partitions disagree/
  );
});

test("draft.9 common injuries use one knee joint-sprain parent and retain distinct diagnoses", () => {
  const row = {
    team_key: "urc",
    diagnosis_coverage: { eligible_time_loss_injuries: 10, classified_time_loss_injuries: 7 },
    common_injuries: [
      { setting: "all", dimension: "diagnosis", code: "compound__knee__joint_sprain", label: "Knee · Joint sprain", time_loss_injuries: 4 },
      { setting: "all", dimension: "diagnosis", code: "meniscal_injury", label: "Meniscal injury", time_loss_injuries: 1 },
      { setting: "all", dimension: "diagnosis", code: "compound__knee__cartilage_injury", label: "Knee · Cartilage injury", time_loss_injuries: 1 },
      { setting: "all", dimension: "diagnosis", code: "compound__knee__peripheral_nerve_injury", label: "Knee · Peripheral nerve injury", time_loss_injuries: 1 },
      { setting: "all", dimension: "diagnosis", code: "unknown", label: "Unknown diagnosis", time_loss_injuries: 3 },
      { setting: "match", dimension: "diagnosis", code: "concussion", label: "Concussion", time_loss_injuries: 4 },
    ],
  };
  assert.doesNotThrow(() => validateDraft9DiagnosisBuckets(row));
  assert.throws(
    () => validateDraft9DiagnosisBuckets({ ...row, common_injuries: row.common_injuries.filter((item) => item.code !== "unknown") }),
    /visible Unknown/
  );
});

test("draft.9 body and tissue profiles partition the same season-bound time-loss cohort", () => {
  const makeRows = (dimension) => [
    { setting: "all", dimension, code: "known", label: "Known", time_loss_injuries: 8 },
    { setting: "all", dimension, code: "unknown", label: "Unknown", time_loss_injuries: 2 },
  ];
  const row = {
    team_key: "urc",
    consequence_summary: { positive_day_cases: 10 },
    body_locations: makeRows("body_location"),
    injury_types: makeRows("injury_type"),
  };
  assert.doesNotThrow(() => validateDraft9ClassificationProfiles(row));
  assert.throws(
    () => validateDraft9ClassificationProfiles({ ...row, injury_types: row.injury_types.slice(0, 1) }),
    /does not partition/
  );
});
