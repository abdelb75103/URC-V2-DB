import { notFound } from 'next/navigation';
import { getTeamById } from '@/config/teams';
import { getTeamPageData } from '@/lib/reporting';
import { getDashboardSupplement } from '@/lib/reporting-preview';
import type { DashboardSupplement, SettingMetricRow, TeamComparisonRow } from '@/lib/reporting-types';
import { LockedShell } from '@/components/locked-shell';
import { TeamDashboard } from '@/components/dashboard/team-dashboard';

// Dashboard availability follows approved reporting releases at request time.
export const dynamic = 'force-dynamic';
export const revalidate = 0;

export default async function TeamPage({
  params,
}: {
  params: Promise<{ teamId: string }>;
}) {
  const { teamId } = await params;
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
  try {
    ({ dashboard, comparisons, leagueMetrics } = await getTeamPageData(team.id));
  } catch {
    dashboard = undefined;
    comparisons = [];
    leagueMetrics = [];
  }
  try {
    supplement = await getDashboardSupplement(team.id);
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
    />
  );
}
