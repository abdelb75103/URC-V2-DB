import { TeamDashboard } from '@/components/dashboard/team-dashboard';
import { LockedShell } from '@/components/locked-shell';
import { StaticImages } from '@/lib/placeholder-images';
import { getLeagueDashboard } from '@/lib/reporting';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export default async function UrcOverallPage() {
  let dashboard;
  try {
    dashboard = await getLeagueDashboard();
  } catch {
    dashboard = undefined;
  }

  if (!dashboard) {
    return (
      <LockedShell
        title="URC Overall"
        subtitle="League-wide injury and exposure surveillance"
        crest={StaticImages.urcLogo}
        reason="The approved league dashboard could not be loaded. Please try again later."
        statusLabel="Dashboard unavailable"
      />
    );
  }

  return (
    <TeamDashboard
      dashboard={dashboard}
      crest={StaticImages.urcLogo}
      teamName="United Rugby Championship"
    />
  );
}
