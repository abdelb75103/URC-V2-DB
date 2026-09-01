import { notFound } from 'next/navigation';
import { getTeamById } from '@/config/teams';
import { getTeamPageData } from '@/lib/reporting';
import { resolveTeamPalette } from '@/lib/team-color';
import { getDashboardSupplement } from '@/lib/reporting-preview';
import type { DashboardSupplement, SeasonComparisonData, SettingMetricRow, TeamComparisonRow } from '@/lib/reporting-types';
import { LockedShell } from '@/components/locked-shell';
import { TeamDashboard } from '@/components/dashboard/team-dashboard';
import { resolveDashboardSeason } from '@/lib/dashboard-season';
import { buildReportModel } from '@/lib/report-model';
import { reportProtectedTerms } from '@/lib/report-privacy';
import { buildReportComparisonBenchmarks, buildReportComparisonRows } from '@/lib/report-comparison';
import { loadReportBrand } from '@/lib/report-brand';

// Dashboard availability follows approved reporting releases at request time.
export const dynamic = 'force-dynamic';
export const revalidate = 0;

export default async function TeamPage({
  params,
  searchParams,
}: {
  params: Promise<{ teamId: string }>;
  searchParams: Promise<{ season?: string | string[] }>;
}) {
  const { teamId } = await params;
  const { season: seasonParameter } = await searchParams;
  const season = resolveDashboardSeason(seasonParameter);
  const team = getTeamById(teamId);
  if (!team) notFound();

  if (team.status !== 'live') {
    return (
      <LockedShell
        title={team.name}
        crest={team.crest}
        accent={team.accent}
      />
    );
  }

  let dashboard;
  let comparisonDashboard;
  let comparisons: TeamComparisonRow[] = [];
  let leagueMetrics: SettingMetricRow[] = [];
  let supplement: DashboardSupplement | undefined;
  let viewerComparisonId: string | null = null;
  let seasonComparison: SeasonComparisonData | undefined;
  try {
    ({ dashboard, comparisonDashboard, comparisons, leagueMetrics, seasonComparison, viewer_comparison_id: viewerComparisonId } =
      await getTeamPageData(team.id, season));
  } catch {
    dashboard = undefined;
    comparisonDashboard = undefined;
    comparisons = [];
    leagueMetrics = [];
    seasonComparison = undefined;
    viewerComparisonId = null;
  }
  try {
    supplement = await getDashboardSupplement(team.id, season);
  } catch {
    supplement = undefined;
  }
  if (!dashboard) {
    return (
      <LockedShell
        title={team.name}
        crest={team.crest}
        accent={team.accent}
        reason="This approved dashboard could not be loaded. Please try again later."
        statusLabel="Dashboard Unavailable"
      />
    );
  }

  const teamColor = resolveTeamPalette(team);
  const reportModel = buildReportModel({
    current: dashboard,
    prior: comparisonDashboard ?? null,
    expectedScope: 'team',
    expectedSeason: season,
    subjectName: team.name,
    protectedTerms: reportProtectedTerms(),
    exportedAt: new Date().toISOString(),
    comparisonRows: buildReportComparisonRows({
      rows: comparisons,
      scope: 'team',
      subjectName: team.name,
      viewerComparisonId,
    }),
    comparisonBenchmarks: buildReportComparisonBenchmarks(leagueMetrics),
    seasonComparisonVisuals: seasonComparison,
    brand: await loadReportBrand(team.crest, teamColor.mark),
  });

  return (
    <TeamDashboard
      dashboard={dashboard}
      crest={team.crest}
      teamName={team.name}
      comparisons={comparisons}
      leagueMetrics={leagueMetrics}
      supplement={supplement}
      seasonComparison={seasonComparison}
      viewerComparisonId={viewerComparisonId}
      teamColor={teamColor}
      season={season}
      seasonPath={`/team/${team.id}`}
      reportModel={reportModel}
    />
  );
}
