import { realpath } from "node:fs/promises";
import { basename, dirname, isAbsolute, relative, resolve } from "node:path";

function isWithin(candidate, parent) {
  const pathFromParent = relative(parent, candidate);
  return pathFromParent === ""
    || (!pathFromParent.startsWith("..") && !isAbsolute(pathFromParent));
}

async function resolveThroughExistingAncestor(path) {
  let ancestor = resolve(path);
  const missingSegments = [];
  while (true) {
    try {
      return resolve(await realpath(ancestor), ...missingSegments.reverse());
    } catch (error) {
      if (error?.code !== "ENOENT" && error?.code !== "ENOTDIR") throw error;
      const parent = dirname(ancestor);
      if (parent === ancestor) throw error;
      missingSegments.push(basename(ancestor));
      ancestor = parent;
    }
  }
}

export async function assertPrivatePreviewOutputPath(path, projectRoot, flag) {
  const candidate = resolve(path);
  const resolvedCandidate = await resolveThroughExistingAncestor(candidate);
  for (const lexicalPublicRoot of [resolve(projectRoot, "content"), resolve(projectRoot, "public")]) {
    const resolvedPublicRoot = await resolveThroughExistingAncestor(lexicalPublicRoot);
    if (isWithin(candidate, lexicalPublicRoot) || isWithin(resolvedCandidate, resolvedPublicRoot)) {
      throw new Error(`${flag} must not write under public payload directory ${lexicalPublicRoot}`);
    }
  }
}

export function expectedOriginClass(origin) {
  if (origin.startsWith("manual_adjudication:")) return "adjudicated";
  if (origin === "source_reported" || origin === "approved_mapping:source_reported") {
    return "source_reported";
  }
  if (origin.startsWith("inferred") || origin.includes("protocol_defined_inference")) {
    return "inferred";
  }
  if (origin.startsWith("mapped_from_")) return "mapped";
  return undefined;
}

export function validateOriginClassCounts(originClassCounts, unclassifiedOrigins = []) {
  const unclassifiedKeys = new Set(unclassifiedOrigins.map((row) =>
    `${row.scope_key}:${row.field}:${row.origin}`));
  for (const row of originClassCounts) {
    if (row.origin_class === "remaining_unknown") continue;
    const expected = expectedOriginClass(row.origin);
    if (expected && row.origin_class !== expected) {
      throw new Error(`${row.scope_key}: ${row.field} origin ${row.origin} must be ${expected}, not ${row.origin_class}`);
    }
    if (!expected) {
      const key = `${row.scope_key}:${row.field}:${row.origin}`;
      if (row.origin_class !== "inferred") {
        throw new Error(`${row.scope_key}: unclassified ${row.field} origin ${row.origin} must conservatively be inferred`);
      }
      if (!unclassifiedKeys.has(key)) {
        throw new Error(`${row.scope_key}: unclassified ${row.field} origin ${row.origin} is not visible in unclassified_origins`);
      }
    }
  }
  for (const row of unclassifiedOrigins) {
    if (expectedOriginClass(row.origin)) {
      throw new Error(`${row.scope_key}: recognized ${row.field} origin ${row.origin} must not be listed as unclassified`);
    }
  }
}

export function validateLegacyMultiMatchRefusal(candidates, reconciliation, checks) {
  if (!Array.isArray(checks?.legacy_multi_match_refusal_checks)) {
    throw new Error("draft.9 legacy multi-match refusal checks are missing");
  }
  const reconciliationTeams = new Map((reconciliation?.teams ?? [])
    .map((team) => [team.team_key, team]));
  const expectedByScope = new Map(checks.legacy_multi_match_refusal_checks
    .map((row) => [row.scope_key, Number(row.expected_legacy_multi_match_refusals)]));
  const actualByScope = new Map();
  for (const row of candidates) {
    if (row.field !== "diagnosis"
      || (row.legacy_pattern_match_count ?? 0) <= 1
      || (row.draft_pattern_match_count ?? 0) !== 0) continue;
    if (row.resulting_value !== "unknown") {
      throw new Error(`${row.id}: multi-match legacy diagnosis fallback did not remain Unknown`);
    }
    actualByScope.set(row.team_key, (actualByScope.get(row.team_key) ?? 0) + 1);
  }
  for (const [scopeKey, expected] of expectedByScope) {
    const reconciliationTeam = reconciliationTeams.get(scopeKey);
    if (!reconciliationTeam) {
      throw new Error(`${scopeKey}: legacy multi-match checks have no reconciliation scope`);
    }
    if (Number(reconciliationTeam.diagnosis_legacy_multi_match_observed_before_draft6) < expected) {
      throw new Error(`${scopeKey}: reconciliation undercounts preview legacy multi-match refusals`);
    }
    if ((actualByScope.get(scopeKey) ?? 0) !== expected) {
      throw new Error(`${scopeKey}: unresolved legacy multi-match diagnoses are not fully ledgered`);
    }
  }
  for (const [scopeKey, actual] of actualByScope) {
    if ((expectedByScope.get(scopeKey) ?? 0) !== actual) {
      throw new Error(`${scopeKey}: unexpected legacy multi-match diagnosis ledger rows`);
    }
  }
}

export function validateDraft9RuleChecks(checks) {
  if (!checks || checks.synthetic_concussion_case_failures !== 0) {
    throw new Error("draft.9 synthetic concussion rule cases failed");
  }
  if (checks.legacy_concussion_case_failures !== 0) {
    throw new Error("draft.9 legacy concussion fallback negation cases failed");
  }
  if (checks.profile_map_duplicate_source_codes !== 0) {
    throw new Error("draft.9 diagnosis code maps to more than one display label");
  }
  if (checks.acl_routes_to_joint_sprain_parent !== true) {
    throw new Error("draft.9 knee/ankle joint-sprain parent label is invalid");
  }
  if (checks.legacy_knee_ligament_display_labels !== 0) {
    throw new Error("draft.9 retained a legacy Knee ligament injury display label");
  }
  if (checks.synthetic_display_taxonomy_case_failures !== 0) {
    throw new Error("draft.9 synthetic display-taxonomy cases failed");
  }
  if (checks.display_taxonomy_origin_class_changes !== 0) {
    throw new Error("draft.9 joint-sprain display relabelling changed provenance class");
  }
  if (checks.meniscus_routes_to_cartilage !== true) {
    throw new Error("draft.9 meniscal diagnosis label is invalid");
  }
  for (const [field, message] of [
    ["synthetic_diagnosis_bucket_case_failures", "synthetic diagnosis display-bucket cases failed"],
    ["synthetic_compound_origin_case_failures", "synthetic compound provenance cases failed"],
    ["within_bucket_multi_match_refusals", "within-bucket diagnosis multi-match was refused"],
    ["cross_bucket_conflicts_classified", "cross-bucket diagnosis conflict was classified"],
    ["compound_missing_input_failures", "tier-2 compound diagnosis is missing a standardised input"],
    ["unknown_with_complete_compound_inputs", "complete body+tissue evidence remained Unknown"],
  ]) {
    if (checks[field] !== 0) {
      throw new Error(`draft.9 ${message}`);
    }
  }
  for (const row of checks.diagnosis_assignments ?? []) {
    if (row.diagnosis_bucket_rows + row.diagnosis_unknown_rows !== row.descriptive_cohort_rows) {
      throw new Error(`${row.scope_key}: diagnosis buckets plus Unknown do not reconcile`);
    }
    if (row.duplicate_injury_rows !== 0) {
      throw new Error(`${row.scope_key}: an injury appears more than once in diagnosis assignment`);
    }
  }
  const expectedProfileSettings = new Set(["all", "match", "training"]);
  const settingsByScope = new Map();
  for (const row of checks.time_loss_profile_assignments ?? []) {
    if (!expectedProfileSettings.has(row.setting_code)) {
      throw new Error(`${row.scope_key}: unexpected profile setting ${row.setting_code}`);
    }
    if (row.classified_time_loss_rows !== row.profile_rows) {
      throw new Error(`${row.scope_key}: ${row.setting_code} diagnosis buckets including Unknown do not partition time-loss rows`);
    }
    const settings = settingsByScope.get(row.scope_key) ?? new Set();
    settings.add(row.setting_code);
    settingsByScope.set(row.scope_key, settings);
  }
  for (const [scopeKey, settings] of settingsByScope) {
    for (const setting of expectedProfileSettings) {
      if (!settings.has(setting)) {
        throw new Error(`${scopeKey}: profile checks are missing ${setting}`);
      }
    }
  }
  for (const row of checks.diagnosis_assignments ?? []) {
    if (!settingsByScope.has(row.scope_key)) {
      throw new Error(`${row.scope_key}: profile checks are missing for scope`);
    }
  }
}

export function validateDraft9SeasonBoundCohort(row) {
  const expectedRule = "season_bound_2024-07-01_2025-06-30_no_exposure_window";
  if (row.rule_version !== "urc-diagnosis-inference-v3-draft.9"
    || row.cohort_rule !== expectedRule) {
    throw new Error(`${row.team_key}: unexpected draft.9 season-bound cohort metadata`);
  }
  const overall = row.rate_setting_metrics.find((item) => item.setting === "all");
  if (!overall) throw new Error(`${row.team_key}: missing overall bounded rate metric`);
  for (const metric of row.rate_setting_metrics) {
    if (metric.exposure_hours !== null
      && Math.abs(metric.exposure_hours * 10 - Math.round(metric.exposure_hours * 10)) > 1e-9) {
      throw new Error(`${row.team_key}: bounded exposure is not rounded to one decimal`);
    }
  }
  const allMonths = row.monthly_by_setting.filter((item) => item.setting === "all");
  const monthlyRecorded = allMonths.reduce((sum, item) => sum + item.recorded_injuries, 0);
  const monthlyRateCases = allMonths.reduce((sum, item) => sum + item.rate_time_loss_injuries, 0);
  if (monthlyRecorded + row.descriptive_consequence_summary.undated_injuries
      !== row.descriptive_consequence_summary.recorded_injuries
    || monthlyRateCases > overall.time_loss_injuries) {
    throw new Error(`${row.team_key}: undated injuries are not included in counts and excluded from monthly series`);
  }
}

export function validateDraft9DiagnosisBuckets(row) {
  const overallRows = row.common_injuries.filter((item) => item.setting === "all");
  if (overallRows.some((item) => item.dimension !== "diagnosis" || !item.label)) {
    throw new Error(`${row.team_key}: common injuries are not labelled diagnosis buckets`);
  }
  const total = overallRows.reduce((sum, item) => sum + item.time_loss_injuries, 0);
  const unknown = overallRows.find((item) => item.code === "unknown");
  if (overallRows.some((item) => item.label === "Knee ligament injury"
      || item.code === "knee_ligament")) {
    throw new Error(`${row.team_key}: legacy Knee ligament injury display bucket remains`);
  }
  if (total !== row.diagnosis_coverage.eligible_time_loss_injuries
    || !unknown
    || unknown.label !== "Unknown diagnosis"
    || unknown.time_loss_injuries !== row.diagnosis_coverage.eligible_time_loss_injuries
      - row.diagnosis_coverage.classified_time_loss_injuries) {
    throw new Error(`${row.team_key}: diagnosis buckets including visible Unknown do not partition time-loss cases`);
  }
}

export function validateDraft9ClassificationProfiles(row) {
  for (const [field, dimension] of [["body_locations", "body_location"], ["injury_types", "injury_type"]]) {
    const rows = row[field] ?? [];
    if (rows.some((item) => item.dimension !== dimension || !item.label)) {
      throw new Error(`${row.team_key}: ${field} contains an invalid classification profile`);
    }
    const overall = rows
      .filter((item) => item.setting === "all")
      .reduce((sum, item) => sum + item.time_loss_injuries, 0);
    if (overall !== row.consequence_summary.positive_day_cases) {
      throw new Error(`${row.team_key}: ${field} does not partition the season-bound time-loss cohort`);
    }
  }
}
