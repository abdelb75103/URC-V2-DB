import "server-only";
import { Pool } from "pg";
import { z } from "zod";
import { isTeamSessionAuthorized } from "@/lib/team-auth";

export type HeadlineMetric = {
  key: string;
  label: string;
  value: number | null;
  unit: string;
  numerator?: number;
  denominator?: number;
  formula: string;
};

export type Coverage = {
  exposure_rows: number;
  exposed_players: number;
  weeks: number;
  exposure_periods?: number;
  exposure_grain?: string;
  hours: number;
  distance_km: number;
  included_exposure_status: string;
  scope_status?: string;
  scope_status_counts?: Record<string, number>;
  injury_cohort_filters?: Record<string, boolean | Record<string, number>>;
};

export type AnalyticsRow = {
  label?: string;
  month?: string;
  exposure_hours?: number;
  distance_km?: number;
  time_loss_injuries: number;
  recorded_injuries?: number;
  days_lost: number;
  incidence_per_1000h?: number | null;
  burden_per_1000h?: number | null;
  mean_severity_days?: number | null;
};

export type SeverityRow = {
  key: string;
  label: string;
  recorded_injuries: number;
  time_loss_injuries: number;
  days_lost: number;
};

export type TeamDashboardData = {
  generated_at: string;
  team: string;
  season: string;
  analysis_window: {
    start: string;
    end: string;
    basis: string;
  };
  method: string[];
  coverage: Coverage;
  headline: HeadlineMetric[];
  setting_split: AnalyticsRow[];
  monthly: AnalyticsRow[];
  body_locations: AnalyticsRow[];
  injury_types: AnalyticsRow[];
  severity_distribution: SeverityRow[];
  prior_season: {
    season: string;
    status: string;
    note: string;
  };
  limitations: string[];
};

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
  monthly: z.array(analyticsRowSchema),
  body_locations: z.array(analyticsRowSchema),
  injury_types: z.array(analyticsRowSchema),
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
 * reporting.latest_team_dashboard (the web_reader role's only readable
 * relation) and validates it into TeamDashboardData.
 *
 * Fail-closed contract:
 * - Missing/invalid/wrong-team session, no reader credential, or no approved
 *   release -> undefined (the dynamic page renders the locked shell).
 * - Database or payload errors throw; the dynamic page catches them and fails
 *   closed without caching or rendering a dashboard payload.
 */
export async function getTeamDashboard(
  teamId: string,
  sessionToken: string | undefined,
  season = "2024-25"
): Promise<TeamDashboardData | undefined> {
  // This check deliberately sits at the database boundary: callers cannot
  // read a team dashboard with a missing, invalid, or differently scoped session.
  if (!isTeamSessionAuthorized(teamId, sessionToken)) return undefined;

  const pool = webReaderPool();
  if (!pool) return undefined;

  // This check deliberately sits at the database boundary: callers cannot
  // read a team dashboard with a missing, invalid, or differently scoped session.
  if (!isTeamSessionAuthorized(teamId, sessionToken)) return undefined;

  const result = await pool.query(
    `select team, season, generated_at, analysis_window, method, coverage,
            headline, setting_split, monthly, body_locations, injury_types,
            severity_distribution, prior_season, limitations
     from reporting.latest_team_dashboard
     where team_key = $1 and season = $2`,
    [teamId, season]
  );
  if (result.rows.length === 0) return undefined;
  if (result.rows.length > 1) {
    throw new Error(`expected one dashboard row for team ${teamId}, got ${result.rows.length}`);
  }

  const row = dashboardRowSchema.parse(result.rows[0]);
  const generatedAt =
    row.generated_at instanceof Date
      ? row.generated_at.toISOString().replace(/\.\d{3}Z$/, "Z")
      : row.generated_at;

  // Rebuilt field-by-field: only the published dashboard payload crosses
  // this boundary (never release ids, build ids, or future view columns).
  return {
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
    monthly: row.monthly.map(stripNulls) as AnalyticsRow[],
    body_locations: row.body_locations.map(stripNulls) as AnalyticsRow[],
    injury_types: row.injury_types.map(stripNulls) as AnalyticsRow[],
    severity_distribution: row.severity_distribution.map(stripNulls) as SeverityRow[],
    prior_season: row.prior_season,
    limitations: row.limitations,
  };
}
