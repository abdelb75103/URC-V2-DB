import { TeamDashboard } from '@/components/dashboard/team-dashboard';
import { LockedShell } from '@/components/locked-shell';
import { StaticImages } from '@/lib/placeholder-images';
import { getLeaguePageData } from '@/lib/reporting';
import { getDashboardSupplement } from '@/lib/reporting-preview';
import type { DashboardSupplement, SeasonComparisonData, SettingMetricRow, TeamComparisonRow } from '@/lib/reporting-types';
import { resolveDashboardSeason } from '@/lib/dashboard-season';
import { buildReportModel } from '@/lib/report-model';
import { reportProtectedTerms } from '@/lib/report-privacy';
import { buildReportComparisonBenchmarks, buildReportComparisonRows } from '@/lib/report-comparison';
import { loadReportBrand } from '@/lib/report-brand';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export default async function UrcOverallPage({
  searchParams,
}: {
  searchParams: Promise<{ season?: string | string[] }>;
}) {
  const { season: seasonParameter } = await searchParams;
  const season = resolveDashboardSeason(seasonParameter);
  let dashboard;
  let comparisonDashboard;
  let comparisons: TeamComparisonRow[] = [];
  let leagueMetrics: SettingMetricRow[] = [];
  let supplement: DashboardSupplement | undefined;
  let seasonComparison: SeasonComparisonData | undefined;
  try {
    ({ dashboard, comparisonDashboard, comparisons, leagueMetrics, seasonComparison } = await getLeaguePageData(season));
  } catch {
    dashboard = undefined;
    comparisonDashboard = undefined;
    comparisons = [];
    leagueMetrics = [];
    seasonComparison = undefined;
  }
  try {
    supplement = await getDashboardSupplement('urc', season);
  } catch {
    supplement = undefined;
  }

  if (!dashboard) {
    return (
      <LockedShell
        title="URC Overall"
        crest={StaticImages.urcLogo}
        reason="The approved league dashboard could not be loaded. Please try again later."
        statusLabel="Dashboard unavailable"
      />
    );
  }

  const reportModel = buildReportModel({
    current: dashboard,
    prior: comparisonDashboard ?? null,
    expectedScope: 'league',
    expectedSeason: season,
    subjectName: dashboard.team,
    protectedTerms: reportProtectedTerms(),
    exportedAt: new Date().toISOString(),
    comparisonRows: buildReportComparisonRows({
      rows: comparisons,
      scope: 'league',
      subjectName: dashboard.team,
    }),
    comparisonBenchmarks: buildReportComparisonBenchmarks(leagueMetrics),
    seasonComparisonVisuals: seasonComparison,
    brand: await loadReportBrand(StaticImages.urcLogo, '#00B9D8'),
  });

  return (
    <TeamDashboard
      dashboard={dashboard}
      crest={StaticImages.urcLogo}
      teamName="United Rugby Championship"
      comparisons={comparisons}
      leagueMetrics={leagueMetrics}
      supplement={supplement}
      seasonComparison={seasonComparison}
      season={season}
      seasonPath="/urc"
      reportModel={reportModel}
    />
  );
}
