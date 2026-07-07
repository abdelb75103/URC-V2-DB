import { notFound } from 'next/navigation';
import { getTeamById, teams } from '@/config/teams';
import { getTeamDashboard } from '@/lib/reporting';
import { LockedShell } from '@/components/locked-shell';
import { TeamDashboard } from '@/components/dashboard/team-dashboard';

export const dynamic = 'force-static';

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

  const dashboard = getTeamDashboard(team.id);
  if (!dashboard) notFound();

  return <TeamDashboard dashboard={dashboard} crest={team.crest} teamName={team.name} />;
}
