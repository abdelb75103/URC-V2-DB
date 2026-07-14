import { cookies } from 'next/headers';
import { notFound } from 'next/navigation';
import { getTeamById } from '@/config/teams';
import { getTeamDashboard } from '@/lib/reporting';
import { TEAM_SESSION_COOKIE } from '@/lib/team-session';
import { LockedShell } from '@/components/locked-shell';
import { TeamDashboard } from '@/components/dashboard/team-dashboard';

// Protected dashboards must never be prerendered or shared through ISR.
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

  const cookieStore = await cookies();
  const sessionToken = cookieStore.get(TEAM_SESSION_COOKIE)?.value;
  let dashboard;
  try {
    dashboard = await getTeamDashboard(team.id, sessionToken);
  } catch {
    dashboard = undefined;
  }
  if (!dashboard) {
    return (
      <LockedShell
        title={`${team.name} Dashboard`}
        subtitle="URC injury & exposure surveillance"
        crest={team.crest}
        accent={team.accent}
        reason="Enter the shared team password to view this disclosure-controlled dashboard."
        actionHref={`/unlock?teamId=${encodeURIComponent(team.id)}`}
        actionLabel="Unlock dashboard"
      />
    );
  }

  return <TeamDashboard dashboard={dashboard} crest={team.crest} teamName={team.name} />;
}
