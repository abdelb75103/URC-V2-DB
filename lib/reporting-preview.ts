import "server-only";
import { readFile } from "node:fs/promises";
import { z } from "zod";
import type { DashboardSupplement } from "@/lib/reporting-types";

const settingSchema = z.enum(["all", "match", "training", "unknown"]);

const injuryProfileSchema = z.object({
  dimension: z.literal("diagnosis"),
  code: z.string(),
  label: z.string(),
  setting: settingSchema,
  time_loss_injuries: z.number().int().nonnegative(),
  days_lost: z.number().nonnegative(),
  exposure_hours: z.number().nonnegative().nullable(),
  incidence_per_1000h: z.number().nonnegative().nullable(),
  burden_per_1000h: z.number().nonnegative().nullable(),
  mean_severity_days: z.number().nonnegative().nullable(),
});

const classificationProfileSchema = injuryProfileSchema.extend({
  dimension: z.enum(["body_location", "injury_type"]),
});

const inferenceCoverageCountsSchema = z.object({
  source_reported: z.number().int().nonnegative(),
  mapped: z.number().int().nonnegative(),
  inferred: z.number().int().nonnegative(),
  adjudicated: z.number().int().nonnegative(),
  remaining_unknown: z.number().int().nonnegative(),
  unknown_before_v3: z.number().int().nonnegative(),
  classified: z.number().int().nonnegative(),
  total: z.number().int().nonnegative(),
});

const supplementSchema = z.object({
  status: z.literal("draft_not_for_release"),
  season: z.string(),
  team_key: z.string(),
  rule_version: z.literal("urc-diagnosis-inference-v3-draft.9"),
  cohort_rule: z.literal("season_bound_2024-07-01_2025-06-30_no_exposure_window"),
  generated_at: z.string(),
  consequence_summary: z.object({
    recorded_injuries: z.number().int().nonnegative(),
    positive_day_cases: z.number().int().nonnegative(),
    zero_day_cases: z.number().int().nonnegative(),
    duration_unknown_or_censored: z.number().int().nonnegative(),
    source_reported_time_loss: z.number().int().nonnegative(),
    source_reported_time_loss_without_positive_days: z.number().int().nonnegative(),
    source_reported_medical_attention: z.number().int().nonnegative(),
    source_class_unknown: z.number().int().nonnegative(),
  }),
  descriptive_consequence_summary: z.object({
    recorded_injuries: z.number().int().nonnegative(),
    time_loss_injuries: z.number().int().nonnegative(),
    medical_attention_only: z.number().int().nonnegative(),
    consequence_unknown: z.number().int().nonnegative(),
    undated_injuries: z.number().int().nonnegative(),
    outside_season_date_injuries: z.number().int().nonnegative(),
    rate_ineligible_time_loss_injuries: z.number().int().nonnegative(),
  }),
  rate_setting_metrics: z.array(z.object({
    setting: settingSchema,
    label: z.string(),
    time_loss_injuries: z.number().int().nonnegative(),
    days_lost: z.number().nonnegative(),
    exposure_hours: z.number().nonnegative().nullable(),
    incidence_per_1000h: z.number().nonnegative().nullable(),
    burden_per_1000h: z.number().nonnegative().nullable(),
    mean_severity_days: z.number().nonnegative().nullable(),
  })),
  severity_distribution: z.array(z.object({
    key: z.string(),
    label: z.string(),
    recorded_injuries: z.number().int().nonnegative(),
    time_loss_injuries: z.number().int().nonnegative(),
    days_lost: z.number().nonnegative(),
  })),
  match_scope_summary: z.object({
    positive_day_match_cases: z.number().int().nonnegative(),
    confirmed_urc_match_cases: z.number().int().nonnegative(),
    retained_generic_match_cases: z.number().int().nonnegative(),
  }),
  monthly_by_setting: z.array(z.object({
    month: z.string(),
    setting: settingSchema,
    recorded_injuries: z.number().int().nonnegative(),
    time_loss_injuries: z.number().int().nonnegative(),
    rate_time_loss_injuries: z.number().int().nonnegative(),
    exposure_hours: z.number().nonnegative().nullable(),
    incidence_per_1000h: z.number().nonnegative().nullable(),
  })),
  contact_distribution: z.array(z.object({
    key: z.string(),
    label: z.string(),
    setting: z.enum(["all", "match", "training"]),
    recorded_injuries: z.number().int().nonnegative(),
    time_loss_injuries: z.number().int().nonnegative(),
  })),
  body_locations: z.array(classificationProfileSchema),
  injury_types: z.array(classificationProfileSchema),
  common_injuries: z.array(injuryProfileSchema),
  diagnosis_coverage: z.object({
    classified_time_loss_injuries: z.number().int().nonnegative(),
    eligible_time_loss_injuries: z.number().int().nonnegative(),
  }),
  inference_coverage: z.object({
    cohort: z.literal("attributed_descriptive_cases"),
    body_location: inferenceCoverageCountsSchema,
    tissue_pathology: inferenceCoverageCountsSchema,
    diagnosis: inferenceCoverageCountsSchema,
    contact_context: inferenceCoverageCountsSchema,
  }),
});

const previewFileSchema = z.object({
  status: z.literal("draft_not_for_release"),
  supplements: z.array(supplementSchema),
});

/**
 * Local review only. The approved database projection remains the sole source
 * in production; setting DASHBOARD_V3_PREVIEW_FILE opts a dev server into an
 * aggregate supplement generated by the read-only V3 audit query.
 */
export async function getDashboardSupplement(
  teamKey: string
): Promise<DashboardSupplement | undefined> {
  const file = process.env.DASHBOARD_V3_PREVIEW_FILE;
  if (!file || process.env.NODE_ENV === "production") return undefined;

  const parsed = previewFileSchema.parse(JSON.parse(await readFile(file, "utf8")));
  return parsed.supplements.find((row) => row.team_key === teamKey);
}
