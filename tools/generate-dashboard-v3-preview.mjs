#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";
import {
  assertPrivatePreviewOutputPath,
  validateDraft9ClassificationProfiles,
  validateDraft9DiagnosisBuckets,
  validateDraft9RuleChecks,
  validateDraft9SeasonBoundCohort,
  validateOriginClassCounts,
  validateLegacyMultiMatchRefusal,
} from "./dashboard-v3-validation.mjs";

const outputFlag = process.argv.indexOf("--output");
if (outputFlag === -1 || !process.argv[outputFlag + 1]) {
  throw new Error("usage: node tools/generate-dashboard-v3-preview.mjs --output <file.json>");
}

const queryPath = new URL("./sql/dashboard_v3_preview.sql", import.meta.url);
const query = await readFile(queryPath, "utf8");
const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const outputPath = resolve(process.argv[outputFlag + 1]);
const reconciliationFlag = process.argv.indexOf("--reconciliation-output");
const reconciliationOutputPath = reconciliationFlag === -1
  ? undefined
  : resolve(process.argv[reconciliationFlag + 1] ?? "");
if (reconciliationFlag !== -1 && !process.argv[reconciliationFlag + 1]) {
  throw new Error("--reconciliation-output requires a file path");
}
function outputPathFor(flag, fallback) {
  const index = process.argv.indexOf(flag);
  if (index === -1) return resolve(fallback);
  if (!process.argv[index + 1]) throw new Error(`${flag} requires a file path`);
  return resolve(process.argv[index + 1]);
}
const adjudicationJsonPath = outputPathFor(
  "--adjudication-json-output", "data/reporting/inference_adjudication_candidates_2024-25.json"
);
const adjudicationMarkdownPath = outputPathFor(
  "--adjudication-md-output", "data/reporting/inference_adjudication_candidates_2024-25.md"
);
for (const [path, flag] of [
  [outputPath, "--output"],
  [reconciliationOutputPath, "--reconciliation-output"],
  [adjudicationJsonPath, "--adjudication-json-output"],
  [adjudicationMarkdownPath, "--adjudication-md-output"],
]) {
  if (path) await assertPrivatePreviewOutputPath(path, projectRoot, flag);
}

const connectionString = process.env.DATABASE_URL || process.env.SUPABASE_DB_URL;
if (!connectionString) throw new Error("DATABASE_URL or SUPABASE_DB_URL is required");
const client = new pg.Client({ connectionString });

function validatePreview(payload) {
  const cohortRule = "season_bound_2024-07-01_2025-06-30_no_exposure_window";
  const coverageFields = ["body_location", "tissue_pathology", "diagnosis", "contact_context"];
  for (const row of payload.supplements ?? []) {
    validateDraft9SeasonBoundCohort(row);
    validateDraft9DiagnosisBuckets(row);
    validateDraft9ClassificationProfiles(row);
    if (row.rule_version !== "urc-diagnosis-inference-v3-draft.9"
      || row.cohort_rule !== cohortRule) {
      throw new Error(`${row.team_key}: unexpected draft.9 rule metadata`);
    }
    const descriptive = row.descriptive_consequence_summary;
    const partition = descriptive.time_loss_injuries
      + descriptive.medical_attention_only
      + descriptive.consequence_unknown;
    if (partition !== descriptive.recorded_injuries) {
      throw new Error(`${row.team_key}: descriptive consequence classes do not partition recorded injuries`);
    }

    const rateTimeLossUnion = row.consequence_summary.positive_day_cases
      + row.consequence_summary.source_reported_time_loss_without_positive_days;
    if (descriptive.rate_ineligible_time_loss_injuries < 0
      || rateTimeLossUnion + descriptive.rate_ineligible_time_loss_injuries
      !== descriptive.time_loss_injuries) {
      throw new Error(`${row.team_key}: descriptive and rate time-loss cohorts do not reconcile`);
    }

    const overallRate = row.rate_setting_metrics.find((item) => item.setting === "all");
    const matchRate = row.rate_setting_metrics.find((item) => item.setting === "match");
    if (!overallRate || !matchRate) {
      throw new Error(`${row.team_key}: missing rate setting metrics`);
    }
    if (overallRate.time_loss_injuries !== row.consequence_summary.positive_day_cases) {
      throw new Error(`${row.team_key}: overall rate metric does not match positive-day cohort`);
    }

    const severityTotal = row.severity_distribution
      .reduce((sum, item) => sum + item.recorded_injuries, 0);
    if (severityTotal !== row.consequence_summary.recorded_injuries) {
      throw new Error(`${row.team_key}: severity bands do not partition the rate cohort`);
    }

    const matchScope = row.match_scope_summary;
    if (matchScope.confirmed_urc_match_cases + matchScope.retained_generic_match_cases
      !== matchScope.positive_day_match_cases
      || matchScope.positive_day_match_cases !== matchRate.time_loss_injuries) {
      throw new Error(`${row.team_key}: match scope classes do not partition positive-day match cases`);
    }

    const contactTotal = row.contact_distribution
      .filter((item) => item.setting === "all")
      .reduce((sum, item) => sum + item.time_loss_injuries, 0);
    if (contactTotal !== row.consequence_summary.positive_day_cases) {
      throw new Error(`${row.team_key}: contact distribution does not partition positive-day cases`);
    }
    const contactRecordedTotal = row.contact_distribution
      .filter((item) => item.setting === "all")
      .reduce((sum, item) => sum + item.recorded_injuries, 0);
    if (contactRecordedTotal !== row.consequence_summary.recorded_injuries) {
      throw new Error(`${row.team_key}: contact distribution does not partition the rate cohort`);
    }

    const diagnosedTotal = row.common_injuries
      .filter((item) => item.setting === "all")
      .reduce((sum, item) => sum + item.time_loss_injuries, 0);
    if (diagnosedTotal !== row.diagnosis_coverage.eligible_time_loss_injuries) {
      throw new Error(`${row.team_key}: diagnosis buckets including Unknown do not partition eligible time-loss cases`);
    }
    const unknownDiagnosis = row.common_injuries.find(
      (item) => item.setting === "all" && item.code === "unknown"
    );
    if (!unknownDiagnosis || unknownDiagnosis.label !== "Unknown diagnosis"
      || unknownDiagnosis.dimension !== "diagnosis"
      || unknownDiagnosis.time_loss_injuries
        !== row.diagnosis_coverage.eligible_time_loss_injuries
          - row.diagnosis_coverage.classified_time_loss_injuries) {
      throw new Error(`${row.team_key}: visible Unknown diagnosis bucket does not reconcile`);
    }

    if (row.inference_coverage.cohort !== "attributed_descriptive_cases") {
      throw new Error(`${row.team_key}: inference coverage uses an unexpected cohort`);
    }
    for (const field of coverageFields) {
      const coverage = row.inference_coverage[field];
      const partition = coverage.source_reported + coverage.mapped + coverage.inferred
        + coverage.adjudicated + coverage.remaining_unknown;
      if (partition !== coverage.total) {
        throw new Error(`${row.team_key}: ${field} origins do not partition the descriptive cohort`);
      }
      if (coverage.classified !== coverage.source_reported + coverage.mapped
        + coverage.inferred + coverage.adjudicated
        || coverage.classified + coverage.remaining_unknown !== coverage.total) {
        throw new Error(`${row.team_key}: ${field} classified/Unknown counts do not partition exactly`);
      }
    }

    for (const month of row.monthly_by_setting.filter((item) => item.setting === "match")) {
      const expected = month.exposure_hours > 0
        ? month.rate_time_loss_injuries / month.exposure_hours * 1000
        : null;
      if (expected === null ? month.incidence_per_1000h !== null : Math.abs(expected - month.incidence_per_1000h) > 1e-9) {
        throw new Error(`${row.team_key} ${month.month}: monthly match incidence formula mismatch`);
      }
    }

    const allMonths = row.monthly_by_setting.filter((item) => item.setting === "all");
    const monthlyRecorded = allMonths.reduce((sum, item) => sum + item.recorded_injuries, 0);
    const monthlyRateCases = allMonths.reduce((sum, item) => sum + item.rate_time_loss_injuries, 0);
    if (monthlyRecorded + row.descriptive_consequence_summary.undated_injuries
      !== row.descriptive_consequence_summary.recorded_injuries
      || monthlyRateCases > overallRate.time_loss_injuries) {
      throw new Error(`${row.team_key}: undated injuries are not excluded only from monthly series`);
    }

    const matchMonths = row.monthly_by_setting.filter((item) => item.setting === "match");
    const monthlyMatchHours = matchMonths.reduce((sum, item) => sum + (item.exposure_hours ?? 0), 0);
    if (Math.abs(monthlyMatchHours - (matchRate.exposure_hours ?? 0)) > 1e-9) {
      throw new Error(`${row.team_key}: monthly bounded match exposure does not reconcile to setting metrics`);
    }
  }
  const league = (payload.supplements ?? []).find((row) => row.team_key === "urc");
  if (!league) throw new Error("league inference coverage is missing");
  for (const field of coverageFields) {
    const coverage = league.inference_coverage[field];
    if (coverage.remaining_unknown > coverage.unknown_before_v3) {
      throw new Error(`urc: ${field} inference does not improve league completeness`);
    }
  }
}

function validateAdjudicationCandidates(candidates) {
  const allowedFields = new Set(["body_location", "tissue_pathology", "diagnosis", "contact_context"]);
  const seen = new Set();
  for (const row of candidates) {
    if (!row.id || !row.team_key || !allowedFields.has(row.field)
      || !Array.isArray(row.candidate_values) || row.candidate_values.length < 2) {
      throw new Error("invalid inference adjudication candidate");
    }
    if (row.evidence_fragment.trim().split(/\s+/).filter(Boolean).length > 6) {
      throw new Error(`${row.id}: adjudication evidence fragment exceeds six words`);
    }
    const key = `${row.id}:${row.team_key}:${row.field}`;
    if (seen.has(key)) throw new Error(`${key}: duplicate adjudication candidate`);
    seen.add(key);
  }
}

function validateReconciliation(payload, reconciliation, previewOriginClassCounts) {
  if (reconciliation.rule_version !== payload.supplements[0]?.rule_version) {
    throw new Error("preview and reconciliation rule versions differ");
  }
  validateOriginClassCounts(
    reconciliation.curated_origin_class_counts ?? [],
    reconciliation.unclassified_origins ?? []
  );
  validateOriginClassCounts(previewOriginClassCounts, reconciliation.unclassified_origins ?? []);
  const supplements = new Map(payload.supplements.map((row) => [row.team_key, row]));
  const beforeKeys = {
    body_location: "body_location_unknown_before_v3",
    tissue_pathology: "tissue_pathology_unknown_before_v3",
    diagnosis: "diagnosis_unknown_before_v3",
    contact_context: "contact_context_unknown_before_v3",
  };
  const originKeys = {
    body_location: {
      source_reported: "body_location_source_reported_before_v3",
      mapped: "body_location_mapped_before_v3",
      inferred: "body_location_inferred_before_v3",
      adjudicated: "body_location_adjudicated_before_v3",
    },
    tissue_pathology: {
      source_reported: "tissue_pathology_source_reported_before_v3",
      mapped: "tissue_pathology_mapped_before_v3",
      inferred: "tissue_pathology_inferred_before_v3",
      adjudicated: "tissue_pathology_adjudicated_before_v3",
    },
    contact_context: {
      source_reported: "contact_context_source_reported_before_v3",
      mapped: "contact_context_mapped_before_v3",
      inferred: "contact_context_inferred_before_v3",
      adjudicated: "contact_context_adjudicated_before_v3",
    },
  };
  for (const team of reconciliation.teams ?? []) {
    const supplement = supplements.get(team.team_key);
    if (!supplement) throw new Error(`${team.team_key}: reconciliation has no preview supplement`);
    if (team.inference_partition_total !== team.attributed_descriptive_cases) {
      throw new Error(`${team.team_key}: reconciliation inference cohort differs from descriptive cohort`);
    }
    for (const [field, beforeKey] of Object.entries(beforeKeys)) {
      const coverage = supplement.inference_coverage[field];
      if (coverage.total !== team.inference_partition_total
        || coverage.unknown_before_v3 !== team[beforeKey]) {
        throw new Error(`${team.team_key}: ${field} preview/reconciliation counts differ`);
      }
      const originRows = previewOriginClassCounts.filter(
        (row) => row.scope_key === team.team_key && row.field === field
      );
      const originTotal = originRows.reduce((sum, row) => sum + Number(row.count), 0);
      if (originTotal !== coverage.total) {
        throw new Error(`${team.team_key}: ${field} origin-string counts do not match preview total`);
      }
      for (const originClass of ["source_reported", "mapped", "inferred", "adjudicated", "remaining_unknown"]) {
        const counted = originRows
          .filter((row) => row.origin_class === originClass)
          .reduce((sum, row) => sum + Number(row.count), 0);
        if (counted !== coverage[originClass]) {
          throw new Error(`${team.team_key}: ${field} ${originClass} origin-string counts do not match preview coverage`);
        }
      }
      const fieldOriginKeys = originKeys[field];
      if (fieldOriginKeys) {
        for (const originClass of ["source_reported", "adjudicated"]) {
          if (coverage[originClass] !== team[fieldOriginKeys[originClass]]) {
            throw new Error(`${team.team_key}: ${field} ${originClass} preview/reconciliation counts differ`);
          }
        }
        const resolvedUnknowns = coverage.unknown_before_v3 - coverage.remaining_unknown;
        const beforeMapped = team[fieldOriginKeys.mapped];
        const beforeInferred = team[fieldOriginKeys.inferred];
        if (coverage.mapped < beforeMapped || coverage.inferred < beforeInferred
          || coverage.mapped + coverage.inferred !== beforeMapped + beforeInferred + resolvedUnknowns) {
          throw new Error(`${team.team_key}: ${field} mapped/inferred resolutions do not reconcile`);
        }
      }
    }
    team.inference_coverage = supplement.inference_coverage;
  }
}

function adjudicationMarkdown(ledger) {
  const lines = [
    "# V3 inference adjudication candidates — 2024-25",
    "",
    "Draft, read-only review ledger. Values remain Unknown until a recorded adjudication approves a versioned rule; evidence fragments are capped at six words.",
    "",
    `Rule version: \`${ledger.rule_version}\`  `,
    `Candidates: ${ledger.candidate_count}`,
    "",
    "| Row id | Team key | Field | Candidate value(s) | Evidence fragment | Why ambiguous |",
    "|---|---|---|---|---|---|",
  ];
  for (const row of ledger.candidates) {
    const cells = [row.id, row.team_key, row.field, row.candidate_values.join(", "), row.evidence_fragment, row.why_ambiguous]
      .map((value) => String(value).replaceAll("|", "\\|"));
    lines.push(`| ${cells.join(" | ")} |`);
  }
  return `${lines.join("\n")}\n`;
}

await client.connect();
try {
  await client.query("begin read only");
  const result = await client.query(query);
  if (result.rows.length !== 1 || !result.rows[0].dashboard_v3_preview) {
    throw new Error("V3 preview query did not return exactly one dashboard payload");
  }

  const rawPayload = result.rows[0].dashboard_v3_preview;
  const candidates = rawPayload.adjudication_candidates ?? [];
  const {
    adjudication_candidates: _privateCandidates,
    origin_class_counts: previewOriginClassCounts = [],
    validation_checks: previewValidationChecks,
    ...aggregatePayload
  } = rawPayload;
  const payload = {
    ...aggregatePayload,
    source_query_sha256: createHash("sha256").update(query).digest("hex"),
  };
  validatePreview(payload);
  validateAdjudicationCandidates(candidates);
  validateDraft9RuleChecks(previewValidationChecks);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");

  const ledger = {
    status: "draft_awaiting_adjudication",
    season: "2024-25",
    rule_version: payload.supplements[0]?.rule_version,
    generated_at: payload.supplements[0]?.generated_at,
    candidate_count: candidates.length,
    candidates,
  };
  await mkdir(dirname(adjudicationJsonPath), { recursive: true });
  await writeFile(adjudicationJsonPath, `${JSON.stringify(ledger, null, 2)}\n`, "utf8");
  await mkdir(dirname(adjudicationMarkdownPath), { recursive: true });
  await writeFile(adjudicationMarkdownPath, adjudicationMarkdown(ledger), "utf8");

  if (reconciliationOutputPath) {
    const reconciliationQuery = await readFile(
      new URL("./sql/dashboard_v3_reconciliation.sql", import.meta.url),
      "utf8"
    );
    const reconciliationResult = await client.query(reconciliationQuery);
    if (reconciliationResult.rows.length !== 1 || !reconciliationResult.rows[0].reconciliation) {
      throw new Error("V3 reconciliation query did not return exactly one payload");
    }
    const reconciliation = {
      ...reconciliationResult.rows[0].reconciliation,
      source_query_sha256: createHash("sha256").update(reconciliationQuery).digest("hex"),
    };
    validateReconciliation(payload, reconciliation, previewOriginClassCounts);
    validateLegacyMultiMatchRefusal(candidates, reconciliation, previewValidationChecks);
    reconciliation.origin_class_counts = previewOriginClassCounts;
    reconciliation.preview_validation_checks = previewValidationChecks;
    await mkdir(dirname(reconciliationOutputPath), { recursive: true });
    await writeFile(reconciliationOutputPath, `${JSON.stringify(reconciliation, null, 2)}\n`, "utf8");
  }
  await client.query("rollback");
  process.stdout.write(`${outputPath}\n`);
  if (reconciliationOutputPath) process.stdout.write(`${reconciliationOutputPath}\n`);
  process.stdout.write(`${adjudicationJsonPath}\n${adjudicationMarkdownPath}\n`);
} catch (error) {
  try { await client.query("rollback"); } catch {}
  throw error;
} finally {
  await client.end();
}
