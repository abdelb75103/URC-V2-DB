export const DASHBOARD_TABS = [
  { value: 'overview', label: 'Overview' },
  { value: 'comparison', label: 'Team Comparison' },
  { value: 'common', label: 'Common Injuries' },
  { value: 'location', label: 'Injury Location' },
  { value: 'types', label: 'Injury Types' },
  { value: 'exposure', label: 'Exposure' },
  { value: 'season-comparison', label: 'Season Comparison' },
  { value: 'reports', label: 'Reports' },
] as const;

export type DashboardTab = (typeof DASHBOARD_TABS)[number]['value'];

export const DEFAULT_DASHBOARD_TAB: DashboardTab = 'overview';

export function resolveDashboardTab(value: string | null | undefined): DashboardTab {
  return DASHBOARD_TABS.some((tab) => tab.value === value)
    ? value as DashboardTab
    : DEFAULT_DASHBOARD_TAB;
}
