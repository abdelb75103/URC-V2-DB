import { TeamDashboard } from '@/components/dashboard/team-dashboard';
import { LockedShell } from '@/components/locked-shell';
import { StaticImages } from '@/lib/placeholder-images';
import { getLeaguePageData } from '@/lib/reporting';
import { getDashboardSupplement, getExposureReviewPreview } from '@/lib/reporting-preview';
import type { DashboardSupplement, ExposureReviewPreview, SettingMetricRow, TeamComparisonRow } from '@/lib/reporting-types';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export default async function UrcOverallPage() {
  let dashboard;
  let comparisons: TeamComparisonRow[] = [];
  let leagueMetrics: SettingMetricRow[] = [];
  let supplement: DashboardSupplement | undefined;
  let exposurePreview: ExposureReviewPreview | undefined;
  try {
    ({ dashboard, comparisons, leagueMetrics } = await getLeaguePageData());
  } catch {
    dashboard = undefined;
    comparisons = [];
    leagueMetrics = [];
  }
  try {
    supplement = await getDashboardSupplement('urc');
  } catch {
    supplement = undefined;
  }
  try {
    exposurePreview = await getExposureReviewPreview();
  } catch {
    exposurePreview = undefined;
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
      comparisons={comparisons}
      leagueMetrics={leagueMetrics}
      supplement={supplement}
      exposurePreview={exposurePreview}
    />
  );
}
