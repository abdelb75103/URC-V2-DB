import { notFound } from 'next/navigation';
import { getTeamById } from '@/config/teams';
import { getTeamPageData } from '@/lib/reporting';
import { resolveTeamPalette } from '@/lib/team-color';
import { getDashboardSupplement } from '@/lib/reporting-preview';
import type { DashboardSupplement, SettingMetricRow, TeamComparisonRow } from '@/lib/reporting-types';
import { LockedShell } from '@/components/locked-shell';
import { TeamDashboard } from '@/components/dashboard/team-dashboard';
import { resolveDashboardSeason } from '@/lib/dashboard-season';

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
        title={`${team.name} Dashboard`}
        subtitle="URC injury & exposure surveillance"
        crest={team.crest}
        accent={team.accent}
      />
    );
  }

  let dashboard;
  let comparisons: TeamComparisonRow[] = [];
  let leagueMetrics: SettingMetricRow[] = [];
  let supplement: DashboardSupplement | undefined;
  let viewerComparisonId: string | null = null;
  try {
    ({ dashboard, comparisons, leagueMetrics, viewer_comparison_id: viewerComparisonId } =
      await getTeamPageData(team.id, season));
  } catch {
    dashboard = undefined;
    comparisons = [];
    leagueMetrics = [];
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
        title={`${team.name} Dashboard`}
        subtitle="URC injury & exposure surveillance"
        crest={team.crest}
        accent={team.accent}
        reason="This approved dashboard could not be loaded. Please try again later."
        statusLabel="Dashboard unavailable"
      />
    );
  }

  return (
    <TeamDashboard
      dashboard={dashboard}
      crest={team.crest}
      teamName={team.name}
      comparisons={comparisons}
      leagueMetrics={leagueMetrics}
      supplement={supplement}
      viewerComparisonId={viewerComparisonId}
      teamColor={resolveTeamPalette(team)}
      season={season}
      seasonPath={`/team/${team.id}`}
    />
  );
}
