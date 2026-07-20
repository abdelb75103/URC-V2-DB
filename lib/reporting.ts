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
  TeamComparisonRow,
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
  dimension: z.enum(["body_location", "injury_type", "injury_profile", "diagnosis"]),
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

function teamDisplayAliases(): Record<string, string> {
  const raw = process.env.TEAM_DISPLAY_ALIAS_JSON;
  if (!raw) return {};

  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    return Object.fromEntries(
      Object.entries(parsed).filter(
        ([, alias]) => typeof alias === "string" && alias.trim().length > 0
      )
    ) as Record<string, string>;
  } catch {
    return {};
  }
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

/**
 * Reads the approved per-team projections needed for the league comparison and
 * exposure tabs. No rates are recomputed here: each row is copied from the same
 * immutable V2 team payload used by the team dashboard.
 */
export async function getTeamComparisons(
  season = "2024-25"
): Promise<TeamComparisonRow[]> {
  const pool = webReaderPool();
  if (!pool) return [];

  const result = await pool.query(
    `select team_key, team, coverage, headline, setting_metrics
     from reporting.latest_team_dashboard_v2
     where season = $1
     order by team_key`,
    [season]
  );

  return normalizeTeamComparisons(result.rows);
}

function normalizeTeamComparisons(rawRows: unknown[]): TeamComparisonRow[] {
  const internalRows = rawRows.map((raw) => {
    const row = comparisonSourceRowSchema.parse(raw);
    const metric = (setting: SettingMetricRow["setting"]) => {
      const value = row.setting_metrics.find((item) => item.setting === setting);
      if (!value) return null;
      return {
        ...stripNulls(value),
        exposure_hours: value.exposure_hours ?? null,
        incidence_per_1000h: value.incidence_per_1000h ?? null,
        burden_per_1000h: value.burden_per_1000h ?? null,
        mean_severity_days: value.mean_severity_days ?? null,
      } as SettingMetricRow;
    };

    return {
      internal_team_key: row.team_key,
      exposure_hours: row.coverage.hours,
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
  return internalRows
    .sort((a, b) => b.exposure_hours - a.exposure_hours
      || a.internal_team_key.localeCompare(b.internal_team_key))
    .map(({ internal_team_key, ...row }, index) => ({
      ...row,
      comparison_id: `comparison-${String(index + 1).padStart(2, "0")}`,
      team_alias: aliases[internal_team_key] ?? `Club ${String(index + 1).padStart(2, "0")}`,
    }));
}

export type TeamPageData = {
  dashboard: DashboardData | undefined;
  comparisons: TeamComparisonRow[];
  leagueMetrics: SettingMetricRow[];
};

/**
 * Loads every production payload needed by a team page in one PostgreSQL
 * statement. PostgreSQL gives a statement one MVCC snapshot, so a request
 * cannot mix an old dashboard bundle with comparisons from its successor.
 */
export async function getTeamPageData(
  teamId: string,
  season = "2024-25"
): Promise<TeamPageData> {
  const pool = webReaderPool();
  if (!pool) return { dashboard: undefined, comparisons: [], leagueMetrics: [] };

  const result = await pool.query(
    `select
       (select to_jsonb(team_row) from (
          select team, season, generated_at, analysis_window, method, coverage,
                 headline, setting_split, setting_metrics, monthly, body_locations,
                 injury_types, injury_profiles, severity_distribution, prior_season,
                 limitations
          from reporting.latest_team_dashboard_v2
          where team_key = $1 and season = $2
        ) team_row) as dashboard,
       coalesce((
         select jsonb_agg(to_jsonb(comparison_row) order by comparison_row.team_key)
         from (
           select team_key, team, coverage, headline, setting_metrics
           from reporting.latest_team_dashboard_v2
           where season = $2
         ) comparison_row
       ), '[]'::jsonb) as comparisons,
       (select to_jsonb(league_metrics_row) from (
          select coverage, headline, setting_metrics
          from reporting.latest_league_dashboard_v2
          where season = $2
        ) league_metrics_row) as league_metrics`,
    [teamId, season]
  );
  if (result.rows.length !== 1) throw new Error("expected one team page snapshot row");

  const snapshot = z.object({
    dashboard: dashboardRowSchema.nullable(),
    comparisons: z.array(comparisonSourceRowSchema),
    league_metrics: leagueMetricsSourceSchema.nullable(),
  }).parse(result.rows[0]);

  return {
    dashboard: snapshot.dashboard
      ? normalizeDashboardRow(snapshot.dashboard, "team")
      : undefined,
    comparisons: normalizeTeamComparisons(snapshot.comparisons),
    leagueMetrics: snapshot.league_metrics
      ? normalizeLeagueMetrics(snapshot.league_metrics)
      : [],
  };
}

export type LeaguePageData = {
  dashboard: DashboardData | undefined;
  comparisons: TeamComparisonRow[];
  leagueMetrics: SettingMetricRow[];
};

/** Same single-statement snapshot guarantee as getTeamPageData(). */
export async function getLeaguePageData(
  season = "2024-25"
): Promise<LeaguePageData> {
  const pool = webReaderPool();
  if (!pool) return { dashboard: undefined, comparisons: [], leagueMetrics: [] };

  const result = await pool.query(
    `select
       (select to_jsonb(league_row) from (
          select team, season, generated_at, analysis_window, method, coverage,
                 headline, setting_split, setting_metrics, monthly, body_locations,
                 injury_types, injury_profiles, severity_distribution, prior_season,
                 limitations
          from reporting.latest_league_dashboard_v2
          where season = $1
        ) league_row) as dashboard,
       coalesce((
         select jsonb_agg(to_jsonb(comparison_row) order by comparison_row.team_key)
         from (
           select team_key, team, coverage, headline, setting_metrics
           from reporting.latest_team_dashboard_v2
           where season = $1
         ) comparison_row
       ), '[]'::jsonb) as comparisons`,
    [season]
  );
  if (result.rows.length !== 1) throw new Error("expected one league page snapshot row");

  const snapshot = z.object({
    dashboard: dashboardRowSchema.nullable(),
    comparisons: z.array(comparisonSourceRowSchema),
  }).parse(result.rows[0]);

  return {
    dashboard: snapshot.dashboard
      ? normalizeDashboardRow(snapshot.dashboard, "league")
      : undefined,
    comparisons: normalizeTeamComparisons(snapshot.comparisons),
    leagueMetrics: snapshot.dashboard
      ? normalizeLeagueMetrics(snapshot.dashboard)
      : [],
  };
}

function overallSettingMetric(
  headline: z.infer<typeof headlineMetricSchema>[],
  coverage: z.infer<typeof coverageSchema>
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
  const result = await pool.query(
    `select setting_metrics
     from reporting.latest_league_dashboard_v2
     where season = $1`,
    [season]
  );
  if (result.rows.length !== 1) return [];
  return normalizeSettingMetrics(z.array(settingMetricSchema).parse(result.rows[0].setting_metrics));
}

function normalizeSettingMetrics(items: z.infer<typeof settingMetricSchema>[]): SettingMetricRow[] {
  return items.map((item) => ({
    ...stripNulls(item),
    exposure_hours: item.exposure_hours ?? null,
    incidence_per_1000h: item.incidence_per_1000h ?? null,
    burden_per_1000h: item.burden_per_1000h ?? null,
    mean_severity_days: item.mean_severity_days ?? null,
  })) as SettingMetricRow[];
}

function normalizeLeagueMetrics(
  source: z.infer<typeof leagueMetricsSourceSchema>
): SettingMetricRow[] {
  const overall = overallSettingMetric(source.headline, source.coverage);
  return [
    ...(overall ? [overall] : []),
    ...normalizeSettingMetrics(source.setting_metrics),
  ];
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
