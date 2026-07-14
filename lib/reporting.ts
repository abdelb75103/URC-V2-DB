import "server-only";
import { Pool } from "pg";
import { z } from "zod";
import type {
  AnalyticsRow,
  Coverage,
  DashboardData,
  HeadlineMetric,
  InjuryProfileRow,
  SeverityRow,
  SettingMetricRow,
} from "@/lib/reporting-types";

export type { DashboardData, TeamDashboardData } from "@/lib/reporting-types";

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
  incidence_per_1000h: z.number().nullish(),
  burden_per_1000h: z.number().nullish(),
  mean_severity_days: z.number().nullish(),
});

const settingMetricSchema = z.object({
  setting: z.enum(["all", "match", "training", "unknown"]),
  label: z.string(),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
  exposure_hours: z.number().nullish(),
  incidence_per_1000h: z.number().nullish(),
  burden_per_1000h: z.number().nullish(),
  mean_severity_days: z.number().nullish(),
});

const injuryProfileSchema = z.object({
  dimension: z.enum(["body_location", "injury_type", "injury_profile"]),
  code: z.string(),
  label: z.string(),
  setting: z.enum(["all", "match", "training", "unknown"]),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
  exposure_hours: z.number().nullish(),
  incidence_per_1000h: z.number().nullish(),
  burden_per_1000h: z.number().nullish(),
  mean_severity_days: z.number().nullish(),
});

const severityRowSchema = z.object({
  key: z.string(),
  label: z.string(),
  recorded_injuries: z.number(),
  time_loss_injuries: z.number(),
  days_lost: z.number(),
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
  severity_distribution: z.array(severityRowSchema),
  prior_season: z.object({
    season: z.string(),
    status: z.string(),
    note: z.string(),
  }),
  limitations: z.array(z.string()),
});

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

/**
 * Reads the latest approved release for a team from
 * reporting.latest_team_dashboard_v2 and validates it into DashboardData.
 * The v2 consumer view exposes only the whitelisted fields from the immutable
 * team snapshot stored with the approved 16-team dashboard bundle.
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

  const result = await pool.query(
    `select team, season, generated_at, analysis_window, method, coverage,
            headline, setting_split, setting_metrics, monthly, body_locations,
            injury_types, injury_profiles, severity_distribution, prior_season,
            limitations
     from reporting.latest_team_dashboard_v2
     where team_key = $1 and season = $2`,
    [teamId, season]
  );
  if (result.rows.length === 0) return undefined;
  if (result.rows.length > 1) {
    throw new Error(`expected one dashboard row for team ${teamId}, got ${result.rows.length}`);
  }

  const row = dashboardRowSchema.parse(result.rows[0]);

  // Rebuilt field-by-field: only the published dashboard payload crosses
  // this boundary (never release ids, build ids, or future view columns).
  return normalizeDashboardRow(row, "team");
}

export async function getLeagueDashboard(
  season = "2024-25"
): Promise<DashboardData | undefined> {
  const pool = webReaderPool();
  if (!pool) return undefined;

  const result = await pool.query(
    `select team, season, generated_at, analysis_window, method, coverage,
            headline, setting_split, setting_metrics, monthly, body_locations,
            injury_types, injury_profiles, severity_distribution, prior_season,
            limitations
     from reporting.latest_league_dashboard_v2
     where season = $1`,
    [season]
  );
  if (result.rows.length === 0) return undefined;
  if (result.rows.length > 1) {
    throw new Error(`expected one league dashboard row for season ${season}, got ${result.rows.length}`);
  }

  return normalizeDashboardRow(dashboardRowSchema.parse(result.rows[0]), "league");
}

function normalizeDashboardRow(
  row: z.infer<typeof dashboardRowSchema>,
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
    coverage: stripNulls(row.coverage) as Coverage,
    headline: row.headline.map(({ value, ...rest }) => ({
      ...(stripNulls(rest) as Omit<HeadlineMetric, "value">),
      value: value ?? null,
    })),
    setting_split: row.setting_split.map(stripNulls) as AnalyticsRow[],
    setting_metrics: row.setting_metrics.map((item) => ({
      ...stripNulls(item),
      exposure_hours: item.exposure_hours ?? null,
      incidence_per_1000h: item.incidence_per_1000h ?? null,
      burden_per_1000h: item.burden_per_1000h ?? null,
      mean_severity_days: item.mean_severity_days ?? null,
    })) as SettingMetricRow[],
    monthly: row.monthly.map(stripNulls) as AnalyticsRow[],
    body_locations: row.body_locations.map(stripNulls) as AnalyticsRow[],
    injury_types: row.injury_types.map(stripNulls) as AnalyticsRow[],
    injury_profiles: row.injury_profiles.map((item) => ({
      ...stripNulls(item),
      exposure_hours: item.exposure_hours ?? null,
      incidence_per_1000h: item.incidence_per_1000h ?? null,
      burden_per_1000h: item.burden_per_1000h ?? null,
      mean_severity_days: item.mean_severity_days ?? null,
    })) as InjuryProfileRow[],
    severity_distribution: row.severity_distribution.map(stripNulls) as SeverityRow[],
    prior_season: row.prior_season,
    limitations: row.limitations,
  };
}
