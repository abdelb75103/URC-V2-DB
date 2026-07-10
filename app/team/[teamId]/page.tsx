import { notFound } from 'next/navigation';
import { getTeamById, teams } from '@/config/teams';
import { getTeamDashboard } from '@/lib/reporting';
import { LockedShell } from '@/components/locked-shell';
import { TeamDashboard } from '@/components/dashboard/team-dashboard';

// Dashboards change only at approved releases: prerender every team page at
// deploy, then revalidate hourly. If a revalidation cannot reach the
// database, getTeamDashboard throws and Next keeps serving the last good
// cached render.
export const revalidate = 3600;

export function generateStaticParams() {
  return teams.map((team) => ({ teamId: team.id }));
}

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

  // Fail closed: a live-flagged team with no approved release in the
  // database (or no reader credential in this environment) renders the
  // locked shell rather than erroring or exposing anything.
  const dashboard = await getTeamDashboard(team.id);
  if (!dashboard) {
    return (
      <LockedShell
        title={`${team.name} Dashboard`}
        subtitle="URC injury & exposure surveillance"
        crest={team.crest}
        accent={team.accent}
      />
    );
  }

  return <TeamDashboard dashboard={dashboard} crest={team.crest} teamName={team.name} />;
}
