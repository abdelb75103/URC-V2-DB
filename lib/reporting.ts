import "server-only";
import { Pool } from "pg";
import { z } from "zod";
import type {
  AnalyticsRow,
  Coverage,
  DashboardData,
  DistributionRow,
  HeadlineMetric,
  InjuryProfileRow,
  InjuryTypeFamilyRow,
  SeverityRow,
  SettingMetricRow,
  TeamComparisonRow,
} from "@/lib/reporting-types";

export type { DashboardData, TeamDashboardData } from "@/lib/reporting-types";

const DASHBOARD_PAYLOAD_CACHE_MILLISECONDS = 300_000;
const APPROVED_URC_PROJECT_REF = "eukkvswaxweenovqqgzr";

/** Credential-free server-side proof of the configured URC project. */
export function assertApprovedWebReaderConnectionString(connectionString: string): {
  projectRef: string;
  hostname: string;
  database: "postgres";
} {
  let url: URL;
  try {
    url = new URL(connectionString);
  } catch {
    throw new Error("web reader database URL is invalid; approved URC project proof failed");
  }
  if (!new Set(["postgres:", "postgresql:"]).has(url.protocol)) {
    throw new Error("web reader database URL is not PostgreSQL; approved URC project proof failed");
  }
  if (url.pathname.replace(/^\//, "") !== "postgres") {
    throw new Error("web reader database name is not postgres; approved URC project proof failed");
  }
  const directMatch = url.hostname.match(/^db\.([a-z0-9]{20})\.supabase\.co$/);
  const poolerMatch = url.username.match(/^web_reader\.([a-z0-9]{20})$/);
  const projectRef = directMatch?.[1] ?? poolerMatch?.[1];
  const approvedEndpoint = directMatch !== null
    ? url.username === "web_reader"
    : poolerMatch !== null && url.hostname.endsWith(".pooler.supabase.com");
  if (!approvedEndpoint || projectRef !== APPROVED_URC_PROJECT_REF) {
    throw new Error("web reader database URL does not resolve to the approved URC project");
  }
  return { projectRef, hostname: url.hostname, database: "postgres" };
}

type DashboardPayloadCacheEntry = {
  releaseToken: string;
  expiresAt: number;
  value: Promise<unknown>;
};

// A strict, process-local cache avoids stale-while-revalidate semantics. Every
// request first reads the current approved release token from PostgreSQL. A
// promotion or rollback changes that token immediately, while a token-query
// failure throws and preserves the application's fail-closed behaviour.
const dashboardPayloadCache = new Map<string, DashboardPayloadCacheEntry>();

// The view emits jsonb_build_object rows, so optional numeric fields can be
// explicit JSON nulls; nullish() accepts both shapes and stripNulls()
// normalizes them back to absent keys (the committed-JSON convention the
// dashboard components were written against).
const headlineMetricSchema = z.object({
  key: z.string(),
  label: z.string(),
  value: z.number().nullish(),
  unit: z.string(),
  numerator: z.number().nullish(),
  denominator: z.number().nullish(),
  formula: z.string(),
});

const analyticsRowSchema = z.object({
  key: z.string().nullish(),
  label: z.string().nullish(),
  month: z.string().nullish(),
  exposure_hours: z.number().nullish(),
  distance_km: z.number().nullish(),
  time_loss_injuries: z.number(),
  recorded_injuries: z.number().nullish(),
  days_lost: z.number(),
  overall_incidence_per_1000h: z.number().nullish(),
  incidence_per_1000h: z.number().nullish(),
  burden_per_1000h: z.number().nullish(),
  mean_severity_days: z.number().nullish(),
});

const settingMetricSchema = z.object({
  setting: z.enum(["all", "match", "training", "unknown"]),
  label: z.string(),
  recorded_injuries: z.number().nullish(),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
  exposure_hours: z.number().nullish(),
  overall_incidence_per_1000h: z.number().nullish(),
  incidence_per_1000h: z.number().nullish(),
  burden_per_1000h: z.number().nullish(),
  mean_severity_days: z.number().nullish(),
});

const injuryProfileSchema = z.object({
  dimension: z.enum(["body_location", "injury_type", "injury_profile", "diagnosis"]),
  code: z.string(),
  label: z.string(),
  setting: z.enum(["all", "match", "training", "unknown"]),
  recorded_injuries: z.number().optional(),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
  exposure_hours: z.number().nullish(),
  incidence_per_1000h: z.number().nullish(),
  burden_per_1000h: z.number().nullish(),
  mean_severity_days: z.number().nullish(),
});

const injuryTypeSubtypeSchema = injuryProfileSchema.extend({
  dimension: z.literal('injury_type'),
});

const injuryTypeFamilySchema = injuryProfileSchema.omit({ dimension: true }).extend({
  dimension: z.literal('injury_type_family'),
  mapping_version: z.literal('injury_type_family_2026-07-21_v1'),
  subtypes: z.array(injuryTypeSubtypeSchema),
}).superRefine((family, context) => {
  family.subtypes.forEach((subtype, index) => {
    if (subtype.setting !== family.setting) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['subtypes', index, 'setting'],
        message: 'Subtype setting must match its injury type family setting',
      });
    }
  });
});

const severityRowSchema = z.object({
  key: z.string(),
  label: z.string(),
  setting: z.enum(["all", "match", "training"]).optional(),
  recorded_injuries: z.number(),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
});

const distributionRowSchema = z.object({
  key: z.string(),
  label: z.string(),
  setting: z.enum(["all", "match", "training", "unknown"]),
  recorded_injuries: z.number(),
  time_loss_injuries: z.number(),
});

const coverageSchema = z
  .object({
    exposure_rows: z.number(),
    exposed_players: z.number(),
    weeks: z.number(),
    exposure_periods: z.number().nullish(),
    exposure_grain: z.string().nullish(),
    match_hours: z.number().nullish(),
    training_hours: z.number().nullish(),
    teams_included: z.number().nullish(),
    coverage_windows: z
      .array(
        z.object({
          start: z.string(),
          end: z.string(),
          teams: z.number().nullish(),
        })
      )
      .nullish(),
    hours: z.number(),
    distance_km: z.number(),
    included_exposure_status: z.string(),
    scope_status_counts: z.record(z.string(), z.number()).nullish(),
    injury_cohort_filters: z
      .record(z.string(), z.union([z.boolean(), z.record(z.string(), z.number())]))
      .nullish(),
  })
  .passthrough();

const comparisonSourceRowSchema = z.object({
  team_key: z.string(),
  team: z.string(),
  coverage: coverageSchema,
  headline: z.array(headlineMetricSchema).min(1),
  setting_metrics: z.array(settingMetricSchema),
});

const leagueMetricsSourceSchema = z.object({
  coverage: coverageSchema,
  headline: z.array(headlineMetricSchema).min(1),
  setting_metrics: z.array(settingMetricSchema),
});

const dashboardRowSchema = z.object({
  team: z.string(),
  season: z.string(),
  generated_at: z.union([z.string(), z.date()]),
  analysis_window: z.object({
    start: z.string(),
    end: z.string(),
    basis: z.string(),
  }),
  method: z.array(z.string()),
  coverage: coverageSchema,
  headline: z.array(headlineMetricSchema).min(1),
  setting_split: z.array(analyticsRowSchema),
  setting_metrics: z.array(settingMetricSchema),
  monthly: z.array(analyticsRowSchema),
  body_locations: z.array(analyticsRowSchema),
  injury_types: z.array(analyticsRowSchema),
  injury_profiles: z.array(injuryProfileSchema),
  injury_type_families: z.array(injuryTypeFamilySchema),
  severity_distribution: z.array(severityRowSchema),
  // Optional: releases published before the 2026-07-26 contact-ring change do
  // not carry this key, and the v3 reader views do not project it.
  contact_distribution: z.array(distributionRowSchema).nullish(),
  prior_season: z.object({
    season: z.string(),
    status: z.string(),
    note: z.string(),
  }),
  limitations: z.array(z.string()),
});

const v6HeadlineCountSchema = z.object({
  key: z.enum(["recorded_injuries", "time_loss_injuries", "severity_median_days"]),
  label: z.string(), value: z.number().nullable(), unit: z.string(), formula: z.string(),
}).strict();
const v6HeadlineRateSchema = z.object({
  key: z.enum(["incidence_per_1000h", "severity_mean_days", "burden_per_1000h"]),
  label: z.string(), value: z.number().nullable(), unit: z.string(),
  numerator: z.number().nullable(), denominator: z.number().nullable(), formula: z.string(),
}).strict();
const v6HeadlineBaseSchema = z.tuple([
  v6HeadlineCountSchema.extend({
    key: z.literal("recorded_injuries"),
    formula: z.literal("count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)"),
  }).strict(),
  v6HeadlineCountSchema.extend({
    key: z.literal("time_loss_injuries"),
    formula: z.literal("count(eligible injury rows where days lost > 0)"),
  }).strict(),
  v6HeadlineRateSchema.extend({
    key: z.literal("incidence_per_1000h"),
    formula: z.literal("pooled time-loss injuries / pooled exposure hours * 1000"),
  }).strict(),
  v6HeadlineRateSchema.extend({
    key: z.literal("severity_mean_days"),
    formula: z.literal("pooled days lost / pooled time-loss injuries"),
  }).strict(),
  v6HeadlineCountSchema.extend({
    key: z.literal("severity_median_days"),
    formula: z.literal("median(days lost) across pooled time-loss injuries"),
  }).strict(),
  v6HeadlineRateSchema.extend({
    key: z.literal("burden_per_1000h"),
    formula: z.literal("pooled days lost / pooled exposure hours * 1000"),
  }).strict(),
]);
const v6OverallIncidenceHeadlineSchema = v6HeadlineRateSchema.extend({
  key: z.literal("overall_incidence_per_1000h"),
  formula: z.literal("pooled recorded injuries / pooled exposure hours * 1000"),
}).strict();
const v6HeadlineSchema = z.union([
  v6HeadlineBaseSchema,
  z.tuple([
    ...v6HeadlineBaseSchema.items,
    v6OverallIncidenceHeadlineSchema,
  ]),
]);
const v6MonthlyRowSchema = z.object({
  month: z.string(), exposure_hours: z.number().nullable(), distance_km: z.number().nullable(),
  recorded_injuries: z.number().int().nonnegative().optional(),
  time_loss_injuries: z.number(), days_lost: z.number(),
  overall_incidence_per_1000h: z.number().nullable().optional(),
  incidence_per_1000h: z.number().nullable(), burden_per_1000h: z.number().nullable(),
}).strict();
const v6CategoryRowSchema = z.object({
  key: z.string(), label: z.string(), time_loss_injuries: z.number(), days_lost: z.number(),
  exposure_hours: z.number().nullable(), incidence_per_1000h: z.number().nullable(),
  burden_per_1000h: z.number().nullable(), mean_severity_days: z.number().nullable(),
}).strict();
const v6SettingSplitRowSchema = z.object({
  key: z.enum(["all", "match", "training", "unknown"]),
  label: z.string(), time_loss_injuries: z.number(), days_lost: z.number(),
  exposure_hours: z.number().nullable(),
}).strict();
const v6SettingMetricSchema = z.object({
  setting: z.enum(["all", "match", "training", "unknown"]),
  label: z.string(),
  recorded_injuries: z.number().nullable().optional(),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
  exposure_hours: z.number().nullable(),
  overall_incidence_per_1000h: z.number().nullable().optional(),
  incidence_per_1000h: z.number().nullable(),
  burden_per_1000h: z.number().nullable(),
  mean_severity_days: z.number().nullable(),
}).strict();
const v6InjuryProfileSchema = z.object({
  dimension: z.enum(["body_location", "injury_type", "injury_profile", "diagnosis"]),
  code: z.string(),
  label: z.string(),
  setting: z.enum(["all", "match", "training", "unknown"]),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
  exposure_hours: z.number().nullable(),
  incidence_per_1000h: z.number().nullable(),
  burden_per_1000h: z.number().nullable(),
  mean_severity_days: z.number().nullable(),
}).strict();
const v6InjuryTypeSubtypeSchema = v6InjuryProfileSchema.extend({
  dimension: z.literal("injury_type"),
}).strict();
const v6InjuryProfilesSchema = z.array(v6InjuryProfileSchema).superRefine((profiles, context) => {
  if (profiles.length > 0 && !profiles.some((profile) => profile.dimension === "diagnosis")) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "V6 injury profiles require the accepted diagnosis dimension",
    });
  }
});
const v6InjuryTypeFamilySchema = z.object({
  dimension: z.literal("injury_type_family"),
  code: z.string(),
  label: z.string(),
  setting: z.enum(["all", "match", "training", "unknown"]),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
  exposure_hours: z.number().nullable(),
  incidence_per_1000h: z.number().nullable(),
  burden_per_1000h: z.number().nullable(),
  mean_severity_days: z.number().nullable(),
  mapping_version: z.literal("injury_type_family_2026-07-21_v1"),
  subtypes: z.array(v6InjuryTypeSubtypeSchema).min(1),
}).strict().superRefine((family, context) => {
  family.subtypes.forEach((subtype, index) => {
    if (subtype.setting !== family.setting) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["subtypes", index, "setting"],
        message: "Subtype setting must match its injury type family setting",
      });
    }
  });
});
const v6SeverityRowSchema = severityRowSchema.strict();
const v6ContactRowSchema = (
  setting: "all" | "match" | "training" | "unknown",
  key: "contact" | "non_contact" | "unknown",
  label: "Contact" | "Non-contact" | "Unknown",
) => z.object({
  key: z.literal(key),
  label: z.literal(label),
  setting: z.literal(setting),
  recorded_injuries: z.number(),
  time_loss_injuries: z.number(),
}).strict();
const v6ContactDistributionSchema = z.tuple([
  v6ContactRowSchema("all", "contact", "Contact"),
  v6ContactRowSchema("all", "non_contact", "Non-contact"),
  v6ContactRowSchema("all", "unknown", "Unknown"),
  v6ContactRowSchema("match", "contact", "Contact"),
  v6ContactRowSchema("match", "non_contact", "Non-contact"),
  v6ContactRowSchema("match", "unknown", "Unknown"),
  v6ContactRowSchema("training", "contact", "Contact"),
  v6ContactRowSchema("training", "non_contact", "Non-contact"),
  v6ContactRowSchema("training", "unknown", "Unknown"),
  v6ContactRowSchema("unknown", "contact", "Contact"),
  v6ContactRowSchema("unknown", "non_contact", "Non-contact"),
  v6ContactRowSchema("unknown", "unknown", "Unknown"),
]);

const v6CoverageCommonShape = {
  exposure_rows: z.number(),
  exposed_players: z.number(),
  weeks: z.number(),
  match_hours: z.number().nullable(),
  training_hours: z.number().nullable(),
  hours: z.number().nullable(),
  distance_km: z.number().nullable(),
  included_exposure_status: z.string(),
  analysis_window_start: z.string(),
  analysis_window_end: z.string(),
};
const v6TeamCoverageSchema = z.object({
  ...v6CoverageCommonShape,
  exposure_grain: z.string(),
}).strict();
const v6LeagueCoverageSchema = z.object({
  ...v6CoverageCommonShape,
  teams_included: z.literal(16),
}).strict();

const v6DashboardShape = {
  team: z.string(),
  season: z.literal("2025-26"),
  generated_at: z.union([z.string(), z.date()]),
  analysis_window: z.object({
    start: z.string(),
    end: z.string(),
    basis: z.string(),
  }).strict(),
  method: z.array(z.string()),
  headline: v6HeadlineSchema,
  setting_split: z.tuple([
    v6SettingSplitRowSchema.extend({ key: z.literal("all") }).strict(),
    v6SettingSplitRowSchema.extend({ key: z.literal("match") }).strict(),
    v6SettingSplitRowSchema.extend({ key: z.literal("training") }).strict(),
    v6SettingSplitRowSchema.extend({ key: z.literal("unknown") }).strict(),
  ]),
  setting_metrics: z.tuple([
    v6SettingMetricSchema.extend({ setting: z.literal("all") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("match") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("training") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("unknown") }).strict(),
  ]),
  monthly: z.array(v6MonthlyRowSchema),
  body_locations: z.array(v6CategoryRowSchema),
  injury_types: z.array(v6CategoryRowSchema),
  injury_profiles: v6InjuryProfilesSchema,
  injury_type_families: z.array(v6InjuryTypeFamilySchema),
  severity_distribution: z.array(v6SeverityRowSchema),
  contact_distribution: v6ContactDistributionSchema,
  prior_season: z.object({
    season: z.literal("2024-25"),
    status: z.literal("frozen"),
    note: z.string(),
  }).strict(),
  limitations: z.array(z.string()),
};
const v6TeamDashboardRowSchema = z.object({
  ...v6DashboardShape,
  coverage: v6TeamCoverageSchema,
}).strict();
const v6LeagueDashboardRowSchema = z.object({
  ...v6DashboardShape,
  coverage: v6LeagueCoverageSchema,
}).strict();
const v6ComparisonSourceRowSchema = z.object({
  team_key: z.string(),
  team: z.string(),
  coverage: v6TeamCoverageSchema,
  headline: v6HeadlineSchema,
  setting_metrics: z.tuple([
    v6SettingMetricSchema.extend({ setting: z.literal("all") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("match") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("training") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("unknown") }).strict(),
  ]),
}).strict();
const v6LeagueMetricsSourceSchema = z.object({
  coverage: v6LeagueCoverageSchema,
  headline: v6HeadlineSchema,
  setting_metrics: z.tuple([
    v6SettingMetricSchema.extend({ setting: z.literal("all") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("match") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("training") }).strict(),
    v6SettingMetricSchema.extend({ setting: z.literal("unknown") }).strict(),
  ]),
}).strict();

type DashboardReaderRow =
  | z.infer<typeof dashboardRowSchema>
  | z.infer<typeof v6TeamDashboardRowSchema>
  | z.infer<typeof v6LeagueDashboardRowSchema>;
type ComparisonReaderRow =
  | z.infer<typeof comparisonSourceRowSchema>
  | z.infer<typeof v6ComparisonSourceRowSchema>;
type LeagueMetricsReaderRow =
  | z.infer<typeof leagueMetricsSourceSchema>
  | z.infer<typeof v6LeagueMetricsSourceSchema>;
type ReaderCoverage =
  | z.infer<typeof coverageSchema>
  | z.infer<typeof v6TeamCoverageSchema>
  | z.infer<typeof v6LeagueCoverageSchema>;

export function parseDashboardReaderRow(
  raw: unknown,
  season: string,
  scope: "team" | "league",
): DashboardReaderRow {
  if (season !== "2025-26") return dashboardRowSchema.parse(raw);
  return (scope === "team" ? v6TeamDashboardRowSchema : v6LeagueDashboardRowSchema).parse(raw);
}

function parseComparisonReaderRow(
  raw: unknown,
  season: string,
): ComparisonReaderRow {
  return season === "2025-26"
    ? v6ComparisonSourceRowSchema.parse(raw)
    : comparisonSourceRowSchema.parse(raw);
}

function parseLeagueMetricsReaderRow(
  raw: unknown,
  season: string,
): LeagueMetricsReaderRow {
  const row = raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Record<string, unknown>
    : {};
  const metrics = {
    coverage: row.coverage,
    headline: row.headline,
    setting_metrics: row.setting_metrics,
  };
  return season === "2025-26"
    ? v6LeagueMetricsSourceSchema.parse(metrics)
    : leagueMetricsSourceSchema.parse(metrics);
}

function stripNulls<T extends Record<string, unknown>>(row: T): T {
  return Object.fromEntries(
    Object.entries(row).filter(([, v]) => v !== null && v !== undefined)
  ) as T;
}

// Lazy singleton so builds without a credential never open a pool, and dev
// hot reloads reuse one pool instead of leaking connections.
declare global {
  // eslint-disable-next-line no-var
  var __urcWebReaderPool: Pool | undefined;
}

function webReaderPool(): Pool | undefined {
  const url = process.env.WEB_READER_DB_URL;
  if (!url) return undefined;
  assertApprovedWebReaderConnectionString(url);
  if (!globalThis.__urcWebReaderPool) {
    globalThis.__urcWebReaderPool = new Pool({
      connectionString: url,
      max: 3,
      connectionTimeoutMillis: 10000,
      idleTimeoutMillis: 30000,
    });
  }
  return globalThis.__urcWebReaderPool;
}

function assertApprovedWebReaderConfiguration(): void {
  const url = process.env.WEB_READER_DB_URL;
  if (!url) throw new Error("WEB_READER_DB_URL is required for an approved dashboard query");
  assertApprovedWebReaderConnectionString(url);
}

/**
 * Bind every server-side dashboard read to both the configured project
 * reference and a database-side frozen-release attestation. The attestation
 * view exposes one boolean only, so web_reader retains no access to release,
 * migration, fixture, or source tables.
 */
async function approvedWebReaderQuery(
  pool: Pool,
  sql: string,
  values: any[] = [],
) {
  assertApprovedWebReaderConfiguration();
  const client = await pool.connect();
  let transactionOpen = false;
  try {
    await client.query("begin transaction read only");
    transactionOpen = true;
    const attestation = await client.query(
      `select target_attested
       from reporting.approved_dashboard_reader_target_v2`,
    );
    if (
      attestation.rows.length !== 1
      || attestation.rows[0]?.target_attested !== true
    ) {
      throw new Error("web reader database identity does not match the approved URC project");
    }
    assertApprovedWebReaderConfiguration();
    const result = await client.query<any, any[]>(sql, values);
    await client.query("commit");
    transactionOpen = false;
    return result;
  } catch (error) {
    if (transactionOpen) {
      await client.query("rollback").catch(() => undefined);
    }
    throw error;
  } finally {
    client.release();
  }
}

async function approvedDashboardReleaseToken(
  pool: Pool,
  season: string
): Promise<string | null> {
  const result = await approvedWebReaderQuery(pool,
    `select cache_token
     from reporting.latest_dashboard_cache_token_v2
     where season = $1`,
    [season]
  );
  if (result.rows.length === 0) return null;
  if (result.rows.length !== 1 || typeof result.rows[0]?.cache_token !== "string") {
    throw new Error("expected one approved dashboard cache token");
  }
  return result.rows[0].cache_token;
}

async function loadStrictlyCachedDashboardPayload<T>(
  key: string,
  releaseToken: string,
  loader: () => Promise<T>
): Promise<T> {
  const now = Date.now();
  const cached = dashboardPayloadCache.get(key);
  if (
    cached &&
    cached.releaseToken === releaseToken &&
    cached.expiresAt > now
  ) {
    return cached.value as Promise<T>;
  }

  const value = loader();
  dashboardPayloadCache.set(key, {
    releaseToken,
    expiresAt: now + DASHBOARD_PAYLOAD_CACHE_MILLISECONDS,
    value,
  });
  try {
    return await value;
  } catch (error) {
    const current = dashboardPayloadCache.get(key);
    if (current?.value === value) dashboardPayloadCache.delete(key);
    throw error;
  }
}

function teamDisplayAliases(): Record<string, string> {
  const raw = process.env.TEAM_DISPLAY_ALIAS_JSON;
  if (!raw) return {};

  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    return Object.fromEntries(
      Object.entries(parsed).filter(
        ([key, alias]) => /^[a-z0-9-]+$/.test(key)
          && typeof alias === "string"
          && /^Team [A-Z]$/.test(alias)
      )
    ) as Record<string, string>;
  } catch {
    // Next's local dotenv parser can remove the inner JSON quotes when the
    // value was entered unwrapped. Accept that narrow dev-only shape so an
    // already-running review server does not expose fallback club labels.
    if (process.env.NODE_ENV !== "production" && raw.startsWith("{") && raw.endsWith("}")) {
      const entries = raw.slice(1, -1).split(",").map((pair) => pair.split(":"));
      if (entries.length && entries.every(([key, alias]) =>
        /^[a-z0-9-]+$/.test(key ?? "") && /^Team [A-Z]$/.test(alias ?? "")
      )) {
        return Object.fromEntries(entries) as Record<string, string>;
      }
    }
    return {};
  }
}

/**
 * Reads the latest approved release for a team from
 * reporting.latest_team_dashboard_v6 and validates it into DashboardData.
 * The V6 successor keeps the V5 allowlisted immutable projection for Year 1
 * and adds the season-bound Year 2 release payload without widening the
 * frozen release-table contract.
 *
 * Fail-closed contract:
 * - No reader credential or no approved release -> undefined (the dynamic
 *   page renders the unavailable shell).
 * - Database or payload errors throw; the dynamic page catches them and fails
 *   closed without caching or rendering a dashboard payload.
 */
export async function getTeamDashboard(
  teamId: string,
  season = "2024-25"
): Promise<DashboardData | undefined> {
  const pool = webReaderPool();
  if (!pool) return undefined;

  const result = await approvedWebReaderQuery(pool,
    `select team, season, generated_at, analysis_window, method, coverage,
            headline, setting_split, setting_metrics, monthly, body_locations,
            injury_types, injury_profiles, injury_type_families, severity_distribution,
            contact_distribution, prior_season,
            limitations
     from reporting.latest_team_dashboard_v6
     where team_key = $1 and season = $2`,
    [teamId, season]
  );
  if (result.rows.length === 0) return undefined;
  if (result.rows.length > 1) {
    throw new Error(`expected one dashboard row for team ${teamId}, got ${result.rows.length}`);
  }

  const row = parseDashboardReaderRow(result.rows[0], season, "team");

  // Rebuilt field-by-field: only the published dashboard payload crosses
  // this boundary (never release ids, build ids, or future view columns).
  return normalizeDashboardRow(row, "team");
}

export async function getLeagueDashboard(
  season = "2024-25"
): Promise<DashboardData | undefined> {
  const pool = webReaderPool();
  if (!pool) return undefined;

  const result = await approvedWebReaderQuery(pool,
    `select team, season, generated_at, analysis_window, method, coverage,
            headline, setting_split, setting_metrics, monthly, body_locations,
            injury_types, injury_profiles, injury_type_families, severity_distribution,
            contact_distribution, prior_season,
            limitations
     from reporting.latest_league_dashboard_v6
     where season = $1`,
    [season]
  );
  if (result.rows.length === 0) return undefined;
  if (result.rows.length > 1) {
    throw new Error(`expected one league dashboard row for season ${season}, got ${result.rows.length}`);
  }

  return normalizeDashboardRow(parseDashboardReaderRow(result.rows[0], season, "league"), "league");
}

/**
 * Reads the approved per-team projections needed for the league comparison and
 * exposure tabs. No rates are recomputed here: each row is copied from the same
 * correction-aware immutable team payload used by the team dashboard.
 */
export async function getTeamComparisons(
  season = "2024-25"
): Promise<TeamComparisonRow[]> {
  const pool = webReaderPool();
  if (!pool) return [];

  const result = await approvedWebReaderQuery(pool,
    `select team_key, team, coverage, headline, setting_metrics
     from reporting.latest_team_dashboard_v6
     where season = $1
     order by team_key`,
    [season]
  );

  return normalizeTeamComparisons(result.rows, season);
}

function normalizeTeamComparisons(rawRows: unknown[], season = "2024-25"): TeamComparisonRow[] {
  return normalizeTeamComparisonsWithKeys(rawRows, season).rows;
}

/**
 * Same normalization, but also returns the internal-key to comparison_id map so
 * a caller that still holds the viewing team's key can mark that team's own row.
 * The map never crosses the server-component boundary; only the single
 * comparison_id belonging to the page's own team does.
 */
function normalizeTeamComparisonsWithKeys(rawRows: unknown[], season = "2024-25"): {
  rows: TeamComparisonRow[];
  comparisonIdByTeamKey: Map<string, string>;
} {
  const internalRows = rawRows.map((raw) => {
    const row = parseComparisonReaderRow(raw, season);
    const metric = (setting: SettingMetricRow["setting"]) => {
      const value = row.setting_metrics.find((item) => item.setting === setting);
      if (!value) return null;
      return {
        ...stripNulls(value),
        recorded_injuries: value.recorded_injuries ?? null,
        exposure_hours: value.exposure_hours ?? null,
        overall_incidence_per_1000h: value.overall_incidence_per_1000h ?? null,
        incidence_per_1000h: value.incidence_per_1000h ?? null,
        burden_per_1000h: value.burden_per_1000h ?? null,
        mean_severity_days: value.mean_severity_days ?? null,
      } as SettingMetricRow;
    };

    return {
      internal_team_key: row.team_key,
      included_exposure_status: row.coverage.included_exposure_status,
      exposure_hours: row.coverage.hours,
      distance_km: row.coverage.distance_km,
      match_hours: row.coverage.match_hours ?? null,
      training_hours: row.coverage.training_hours ?? null,
      all: overallSettingMetric(row.headline, row.coverage),
      match: metric("match"),
      training: metric("training"),
    };
  });

  // TEAM_DISPLAY_ALIAS_JSON may carry the real codebook alias under Abdel's
  // 19 Jul 2026 amendment; Club NN remains the no-environment fallback.
  // They are assigned only after real identifiers have served their server-side
  // validation/tie-break purpose. Neither the real team key nor name crosses
  // the server-component boundary into the browser payload. While team pages are
  // passwordless, exact shared metrics still allow alias-to-team linkage by walking
  // those pages; restoring team-scoped passwords closes that vector, leaving only
  // each authorised team able to identify itself.
  const aliases = teamDisplayAliases();
  const comparisonIdByTeamKey = new Map<string, string>();
  const rows = internalRows
    .sort((a, b) => compareNullableNumbersDescending(a.exposure_hours, b.exposure_hours)
      || a.internal_team_key.localeCompare(b.internal_team_key))
    .map(({ internal_team_key, ...row }, index) => {
      const comparisonRow = {
        ...row,
        comparison_id: `comparison-${String(index + 1).padStart(2, "0")}`,
        team_alias: aliases[internal_team_key] ?? `Club ${String(index + 1).padStart(2, "0")}`,
      };
      comparisonIdByTeamKey.set(internal_team_key, comparisonRow.comparison_id);
      return comparisonRow;
    });
  return { rows, comparisonIdByTeamKey };
}

function compareNullableNumbersDescending(left: number | null, right: number | null) {
  if (left === null) return right === null ? 0 : 1;
  if (right === null) return -1;
  return right - left;
}

export type TeamPageData = {
  dashboard: DashboardData | undefined;
  comparisons: TeamComparisonRow[];
  leagueMetrics: SettingMetricRow[];
  /**
   * The comparison_id of the team whose page this is, matched on the internal
   * team key while it is still in scope. A viewer already knows which club's
   * page they opened, so marking their own row discloses no other club's alias.
   */
  viewer_comparison_id: string | null;
};

/**
 * Loads every production payload needed by a team page in one PostgreSQL
 * statement. PostgreSQL gives a statement one MVCC snapshot, so a request
 * cannot mix an old dashboard bundle with comparisons from its successor.
 */
async function loadTeamPageData(
  teamId: string,
  season = "2024-25"
): Promise<TeamPageData> {
  const pool = webReaderPool();
  if (!pool) return { dashboard: undefined, comparisons: [], leagueMetrics: [], viewer_comparison_id: null };

  const result = await approvedWebReaderQuery(pool,
    `select
       (select to_jsonb(team_row) from (
          select team, season, generated_at, analysis_window, method, coverage,
                 headline, setting_split, setting_metrics, monthly, body_locations,
                 injury_types, injury_profiles, injury_type_families, severity_distribution,
                 contact_distribution, prior_season,
                 limitations
          from reporting.latest_team_dashboard_v6
          where team_key = $1 and season = $2
        ) team_row) as dashboard,
       coalesce((
         select jsonb_agg(to_jsonb(comparison_row) order by comparison_row.team_key)
         from (
           select team_key, team, coverage, headline, setting_metrics
           from reporting.latest_team_dashboard_v6
           where season = $2
         ) comparison_row
       ), '[]'::jsonb) as comparisons,
       -- The unified successor projects only coverage, headline and
       -- setting_metrics for the league benchmark.
       (select to_jsonb(league_metrics_row) from (
          select coverage, headline, setting_metrics
          from reporting.latest_league_dashboard_v6
          where season = $2
        ) league_metrics_row) as league_metrics`,
    [teamId, season]
  );
  if (result.rows.length !== 1) throw new Error("expected one team page snapshot row");

  const snapshot = season === "2025-26"
    ? z.object({
        dashboard: v6TeamDashboardRowSchema.nullable(),
        comparisons: z.array(v6ComparisonSourceRowSchema),
        league_metrics: v6LeagueMetricsSourceSchema.nullable(),
      }).strict().parse(result.rows[0])
    : z.object({
        dashboard: dashboardRowSchema.nullable(),
        comparisons: z.array(comparisonSourceRowSchema),
        league_metrics: leagueMetricsSourceSchema.nullable(),
      }).parse(result.rows[0]);

  const { rows, comparisonIdByTeamKey } = normalizeTeamComparisonsWithKeys(snapshot.comparisons, season);

  return {
    dashboard: snapshot.dashboard
      ? normalizeDashboardRow(snapshot.dashboard, "team")
      : undefined,
    comparisons: rows,
    leagueMetrics: snapshot.league_metrics
      ? normalizeLeagueMetrics(parseLeagueMetricsReaderRow(snapshot.league_metrics, season))
      : [],
    viewer_comparison_id: comparisonIdByTeamKey.get(teamId) ?? null,
  };
}

export async function getTeamPageData(
  teamId: string,
  season = "2024-25"
): Promise<TeamPageData> {
  const pool = webReaderPool();
  if (!pool) return { dashboard: undefined, comparisons: [], leagueMetrics: [], viewer_comparison_id: null };
  const releaseToken = await approvedDashboardReleaseToken(pool, season);
  if (!releaseToken) return { dashboard: undefined, comparisons: [], leagueMetrics: [], viewer_comparison_id: null };
  return loadStrictlyCachedDashboardPayload(
    `team:${season}:${teamId}`,
    releaseToken,
    () => loadTeamPageData(teamId, season)
  );
}

export type LeaguePageData = {
  dashboard: DashboardData | undefined;
  comparisons: TeamComparisonRow[];
  leagueMetrics: SettingMetricRow[];
};

/** Same single-statement snapshot guarantee as getTeamPageData(). */
async function loadLeaguePageData(
  season = "2024-25"
): Promise<LeaguePageData> {
  const pool = webReaderPool();
  if (!pool) return { dashboard: undefined, comparisons: [], leagueMetrics: [] };

  const result = await approvedWebReaderQuery(pool,
    `select
       (select to_jsonb(league_row) from (
          select team, season, generated_at, analysis_window, method, coverage,
                 headline, setting_split, setting_metrics, monthly, body_locations,
                 injury_types, injury_profiles, injury_type_families, severity_distribution,
                 contact_distribution, prior_season,
                 limitations
          from reporting.latest_league_dashboard_v6
          where season = $1
        ) league_row) as dashboard,
       coalesce((
         select jsonb_agg(to_jsonb(comparison_row) order by comparison_row.team_key)
         from (
           select team_key, team, coverage, headline, setting_metrics
           from reporting.latest_team_dashboard_v6
           where season = $1
         ) comparison_row
       ), '[]'::jsonb) as comparisons`,
    [season]
  );
  if (result.rows.length !== 1) throw new Error("expected one league page snapshot row");

  const snapshot = season === "2025-26"
    ? z.object({
        dashboard: v6LeagueDashboardRowSchema.nullable(),
        comparisons: z.array(v6ComparisonSourceRowSchema),
      }).strict().parse(result.rows[0])
    : z.object({
        dashboard: dashboardRowSchema.nullable(),
        comparisons: z.array(comparisonSourceRowSchema),
      }).parse(result.rows[0]);

  return {
    dashboard: snapshot.dashboard
      ? normalizeDashboardRow(snapshot.dashboard, "league")
      : undefined,
    comparisons: normalizeTeamComparisons(snapshot.comparisons, season),
    leagueMetrics: snapshot.dashboard
      ? normalizeLeagueMetrics(parseLeagueMetricsReaderRow(snapshot.dashboard, season))
      : [],
  };
}

export async function getLeaguePageData(
  season = "2024-25"
): Promise<LeaguePageData> {
  const pool = webReaderPool();
  if (!pool) return { dashboard: undefined, comparisons: [], leagueMetrics: [] };
  const releaseToken = await approvedDashboardReleaseToken(pool, season);
  if (!releaseToken) return { dashboard: undefined, comparisons: [], leagueMetrics: [] };
  return loadStrictlyCachedDashboardPayload(
    `league:${season}`,
    releaseToken,
    () => loadLeaguePageData(season)
  );
}

function overallSettingMetric(
  headline: z.infer<typeof headlineMetricSchema>[],
  coverage: ReaderCoverage
): SettingMetricRow | null {
  const metric = (key: string) => headline.find((item) => item.key === key);
  const timeLoss = metric("time_loss_injuries");
  const incidence = metric("incidence_per_1000h");
  const burden = metric("burden_per_1000h");
  const severity = metric("severity_mean_days");

  if (!incidence || !burden || !severity) return null;

  const timeLossInjuries = timeLoss?.value ?? incidence.numerator;
  if (timeLossInjuries == null || burden.numerator == null) return null;

  return settingMetricSchema.parse({
    setting: "all",
    label: "All settings",
    time_loss_injuries: timeLossInjuries,
    days_lost: burden.numerator,
    exposure_hours: incidence.denominator ?? coverage.hours,
    incidence_per_1000h: incidence.value,
    burden_per_1000h: burden.value,
    mean_severity_days: severity.value,
  }) as SettingMetricRow;
}

export async function getLeagueSettingMetrics(
  season = "2024-25"
): Promise<SettingMetricRow[]> {
  const pool = webReaderPool();
  if (!pool) return [];
  const result = await approvedWebReaderQuery(pool,
    `select setting_metrics
     from reporting.latest_league_dashboard_v6
     where season = $1`,
    [season]
  );
  if (result.rows.length !== 1) return [];
  const schema = season === "2025-26"
    ? z.array(v6SettingMetricSchema)
    : z.array(settingMetricSchema);
  return normalizeSettingMetrics(schema.parse(result.rows[0].setting_metrics));
}

function normalizeSettingMetrics(items: z.infer<typeof settingMetricSchema>[]): SettingMetricRow[] {
  return items.map((item) => ({
    ...stripNulls(item),
    recorded_injuries: item.recorded_injuries ?? null,
    exposure_hours: item.exposure_hours ?? null,
    overall_incidence_per_1000h: item.overall_incidence_per_1000h ?? null,
    incidence_per_1000h: item.incidence_per_1000h ?? null,
    burden_per_1000h: item.burden_per_1000h ?? null,
    mean_severity_days: item.mean_severity_days ?? null,
  })) as SettingMetricRow[];
}

function normalizeLeagueMetrics(
  source: LeagueMetricsReaderRow
): SettingMetricRow[] {
  const settings = normalizeSettingMetrics(source.setting_metrics);
  if (settings.some((row) => row.setting === "all")) return settings;
  const overall = overallSettingMetric(source.headline, source.coverage);
  return [
    ...(overall ? [overall] : []),
    ...settings,
  ];
}

function normalizeDashboardRow(
  row: DashboardReaderRow,
  scope: DashboardData["scope"]
): DashboardData {
  const generatedAt =
    row.generated_at instanceof Date
      ? row.generated_at.toISOString().replace(/\.\d{3}Z$/, "Z")
      : row.generated_at;

  return {
    scope,
    generated_at: generatedAt,
    team: row.team,
    season: row.season,
    analysis_window: row.analysis_window,
    method: row.method,
    coverage: {
      ...stripNulls(row.coverage),
      hours: row.coverage.hours ?? null,
      distance_km: row.coverage.distance_km ?? null,
    } as Coverage,
    headline: row.headline.map(({ value, ...rest }) => ({
      ...(stripNulls(rest) as Omit<HeadlineMetric, "value">),
      value: value ?? null,
    })),
    setting_split: row.setting_split.map(stripNulls) as AnalyticsRow[],
    setting_metrics: row.setting_metrics.map((item) => ({
      ...stripNulls(item),
      recorded_injuries: item.recorded_injuries ?? null,
      exposure_hours: item.exposure_hours ?? null,
      overall_incidence_per_1000h: item.overall_incidence_per_1000h ?? null,
      incidence_per_1000h: item.incidence_per_1000h ?? null,
      burden_per_1000h: item.burden_per_1000h ?? null,
      mean_severity_days: item.mean_severity_days ?? null,
    })) as SettingMetricRow[],
    monthly: row.monthly.map((item) => ({
      ...stripNulls(item),
      exposure_hours: item.exposure_hours ?? null,
      distance_km: item.distance_km ?? null,
    })) as AnalyticsRow[],
    body_locations: row.body_locations.map(stripNulls) as AnalyticsRow[],
    injury_types: row.injury_types.map(stripNulls) as AnalyticsRow[],
    injury_profiles: row.injury_profiles.map((item) => ({
      ...stripNulls(item),
      exposure_hours: item.exposure_hours ?? null,
      incidence_per_1000h: item.incidence_per_1000h ?? null,
      burden_per_1000h: item.burden_per_1000h ?? null,
      mean_severity_days: item.mean_severity_days ?? null,
    })) as InjuryProfileRow[],
    injury_type_families: row.injury_type_families.map((item) => ({
      ...stripNulls(item),
      exposure_hours: item.exposure_hours ?? null,
      incidence_per_1000h: item.incidence_per_1000h ?? null,
      burden_per_1000h: item.burden_per_1000h ?? null,
      mean_severity_days: item.mean_severity_days ?? null,
      subtypes: item.subtypes.map((subtype) => ({
        ...stripNulls(subtype),
        exposure_hours: subtype.exposure_hours ?? null,
        incidence_per_1000h: subtype.incidence_per_1000h ?? null,
        burden_per_1000h: subtype.burden_per_1000h ?? null,
        mean_severity_days: subtype.mean_severity_days ?? null,
      })),
    })) as InjuryTypeFamilyRow[],
    severity_distribution: row.severity_distribution.map(stripNulls) as SeverityRow[],
    ...(row.contact_distribution
      ? {
          contact_distribution: row.contact_distribution.map(stripNulls) as DistributionRow[],
        }
      : {}),
    prior_season: row.prior_season,
    limitations: row.limitations,
  };
}
