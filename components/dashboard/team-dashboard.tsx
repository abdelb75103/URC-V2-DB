'use client';

import { buildSeasonTimelineRows } from '@/lib/season-timeline';
import { currentExposureWarnings } from '@/lib/exposure-chart';
import {
  useId,
  useLayoutEffect,
  useOptimistic,
  useRef,
  useState,
  useTransition,
  type MouseEvent as ReactMouseEvent,
  type ReactNode,
} from 'react';
import dynamic from 'next/dynamic';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { ArrowLeft, X } from 'lucide-react';
import type {
  DashboardSupplement,
  DiagnosisFamilyRow,
  IllnessProfileRow,
  InjuryProfileRow,
  InjuryTypeFamilyRow,
  SettingMetricRow,
  TeamDashboardData,
  TeamComparisonRow,
} from '@/lib/reporting-types';
import { Button } from '@/components/ui/button';
import { diagnosisFamilyProfiles } from '@/lib/reporting-types';
import { Card, CardContent } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { BodyMap, locationHeatColor, type LocationMetric } from '@/components/dashboard/body-map';
import {
  InjuryTypeDossier,
  InjuryTypeRanking,
  type InjuryTypeMetric,
} from '@/components/dashboard/injury-type-dossier';
import { resolveLocationView } from '@/lib/location-view';
import { withoutFrontFacingUnknown } from '@/lib/dashboard-visibility';
import {
  commonInjuryColorMap, illnessColorMap, isKneeLigamentDiagnosis, metricValue,
  rankedCommonInjuries, rankedIllnesses, type CardColour,
} from '@/lib/report-presentation';
import { ComparisonScatterChart, type ComparisonScatterRow } from '@/components/dashboard/charts';
import {
  SETTING_COLORS,
  SEVERITY_BAND_COLORS,
  Sparkline,
  sortSeasonMonths,
  profileColor,
} from '@/components/dashboard/chart-primitives';
import type { TeamColorSet } from '@/lib/team-color';
import {
  DEFAULT_REPORT_SECTION_IDS,
  orderedReportSectionIds,
  REPORT_SECTION_LABELS,
  type ReportModel,
  type ReportSectionId,
} from '@/lib/report-model-types';
import { SUPPORTED_DASHBOARD_SEASONS, type DashboardSeason } from '@/lib/dashboard-season';
import type { SeasonComparisonData } from '@/lib/season-comparison';
import { SeasonComparison } from '@/components/dashboard/season-comparison';
import {
  DASHBOARD_TABS,
  DEFAULT_DASHBOARD_TAB,
  resolveDashboardTab,
  type DashboardTab,
} from '@/lib/dashboard-tab';

type ProfileMetric =
  | 'time_loss_injuries'
  | 'incidence_per_1000h'
  | 'burden_per_1000h'
  | 'mean_severity_days';
type Setting = InjuryProfileRow['setting'];

const METRICS: Array<{ key: ProfileMetric; label: string; shortUnit: string; longUnit: string }> = [
  { key: 'time_loss_injuries', label: 'Count', shortUnit: 'injuries', longUnit: 'injuries' },
  { key: 'incidence_per_1000h', label: 'Incidence', shortUnit: '/1,000 h', longUnit: 'injuries /1,000 h' },
  { key: 'burden_per_1000h', label: 'Burden', shortUnit: 'days/1,000 h', longUnit: 'days /1,000 h' },
  { key: 'mean_severity_days', label: 'Severity', shortUnit: 'days', longUnit: 'days' },
];

const SECTION_HEADING_CLASS = 'text-2xl font-semibold tracking-tight text-foreground sm:text-3xl';
const PANEL_HEADING_CLASS = 'text-lg font-semibold leading-snug text-foreground';

function ChartLoading({ className }: { className: string }) {
  return (
    <div role="status" className={`grid place-items-center rounded-md bg-muted/20 motion-safe:animate-pulse ${className}`}>
      <span className="sr-only">Loading chart</span>
    </div>
  );
}

const SeasonTimelineChart = dynamic(
  () => import('@/components/dashboard/charts').then((module) => module.SeasonTimelineChart),
  { ssr: false, loading: () => <ChartLoading className="h-[320px] sm:min-w-[560px]" /> },
);
const SeverityArc = dynamic(
  () => import('@/components/dashboard/charts').then((module) => module.SeverityArc),
  { ssr: false, loading: () => <ChartLoading className="h-[300px]" /> },
);
const ImpactScatterChart = dynamic(
  () => import('@/components/dashboard/charts').then((module) => module.ImpactScatterChart),
  { ssr: false, loading: () => <ChartLoading className="h-[580px]" /> },
);
const ExposureTrendChart = dynamic(
  () => import('@/components/dashboard/charts').then((module) => module.ExposureTrendChart),
  { ssr: false, loading: () => <ChartLoading className="h-[303px]" /> },
);
const ReportPreview = dynamic(
  () => import('@/components/report/report-preview').then((module) => module.ReportPreview),
  {
    ssr: false,
    loading: () => <ChartLoading className="min-h-[calc(100vh-13rem)]" />,
  },
);

type InjuryCardColor = CardColour;

const CONTACT_RING_COLORS: Record<string, string> = {
  contact: '#a78bfa',
  non_contact: '#fb923c',
  // Contact mechanism keeps its unclassified share visible (request, 2026-07-26):
  // the reader needs to know how much of the split is not evidenced.
  unknown: '#94a3b8',
};

const NUMBER_FORMATTERS = new Map<string, Intl.NumberFormat>();

function numberFormatter(maximumFractionDigits: number, minimumFractionDigits: number) {
  const key = `${minimumFractionDigits}:${maximumFractionDigits}`;
  let formatter = NUMBER_FORMATTERS.get(key);
  if (!formatter) {
    formatter = new Intl.NumberFormat('en-IE', { maximumFractionDigits, minimumFractionDigits });
    NUMBER_FORMATTERS.set(key, formatter);
  }
  return formatter;
}

function fmt(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return numberFormatter(digits, Number.isInteger(value) ? 0 : digits).format(value);
}

// Ranked lists draw bars from unrounded values, so a shared 1dp label made
// visibly different bars read as the same number. Every ranked rate shows 1dp
// (decision, 2026-07-25), and the bars are drawn from that same rounded value so
// two rows displaying 3.1 render identical bars instead of contradicting the label.
const RANKED_LIST_DIGITS: Record<ProfileMetric, number> = {
  time_loss_injuries: 0,
  incidence_per_1000h: 1,
  burden_per_1000h: 1,
  mean_severity_days: 1,
};

function fmtFixed(value: number | null | undefined, digits: number) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return numberFormatter(digits, digits).format(value);
}

function fmtRanked(value: number | null | undefined, metric: ProfileMetric) {
  const digits = RANKED_LIST_DIGITS[metric];
  return digits === 0 ? fmt(value, 0) : fmtFixed(value, digits);
}

/** The value a ranked bar is drawn from: rounded to what its label shows. */
function rankedBarValue(value: number, metric: ProfileMetric) {
  const factor = 10 ** RANKED_LIST_DIGITS[metric];
  return Math.round(value * factor) / factor;
}

function fmtHours(value: number | null | undefined) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: 0,
    minimumFractionDigits: 0,
  }).format(value);
}

function hasKnownExposure(
  row: TeamComparisonRow,
): row is TeamComparisonRow & { exposure_hours: number } {
  return typeof row.exposure_hours === 'number' && Number.isFinite(row.exposure_hours);
}

type ProfileMetricRow = InjuryProfileRow | InjuryTypeFamilyRow;

function metricMeta(metric: ProfileMetric) {
  return METRICS.find((item) => item.key === metric) ?? METRICS[0];
}

function Panel({ title, children, className = '', contentClassName = 'p-5 sm:p-6' }: {
  title?: string;
  children: ReactNode;
  className?: string;
  contentClassName?: string;
}) {
  return (
    <Card className={`min-w-0 border-border/70 bg-card/70 shadow-none ${className}`}>
      <CardContent className={contentClassName}>
        {title && (
          <div className="mb-5">
            <h3 className={`${PANEL_HEADING_CLASS} capitalize`}>{title}</h3>
          </div>
        )}
        {children}
      </CardContent>
    </Card>
  );
}

function SectionHeading({ title }: { title: string }) {
  return (
    <div className="mb-6">
      <h2 className={`${SECTION_HEADING_CLASS} capitalize`}>{title}</h2>
    </div>
  );
}

function Segmented<T extends string>({
  value,
  options,
  onChange,
  label,
  scrollable = true,
}: {
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange: (value: T) => void;
  label: string;
  scrollable?: boolean;
}) {
  return (
    <div role="group" aria-label={label} className={`inline-flex max-w-full gap-1 rounded-md border border-border bg-background/50 p-1 ${scrollable ? 'overflow-x-auto' : 'flex-wrap overflow-visible'}`}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          aria-pressed={value === option.value}
          onClick={() => onChange(option.value)}
          className="min-h-11 shrink-0 rounded px-3 text-sm font-medium text-muted-foreground transition-[background-color,color,transform] duration-150 active:scale-[0.97] aria-pressed:bg-primary aria-pressed:text-primary-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function SeasonSelector({ season, seasonPath, activeTab }: {
  season: DashboardSeason;
  seasonPath: string;
  activeTab: DashboardTab;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [optimisticSeason, setOptimisticSeason] = useOptimistic(season);
  const tabParameter = activeTab === DEFAULT_DASHBOARD_TAB ? '' : `&tab=${activeTab}`;

  const selectSeason = (event: ReactMouseEvent<HTMLAnchorElement>, option: DashboardSeason) => {
    const modifiedClick = event.metaKey || event.ctrlKey || event.shiftKey || event.altKey;
    if (modifiedClick || event.currentTarget.target === '_blank') return;

    event.preventDefault();
    if (option === optimisticSeason) return;

    const href = `${seasonPath}?season=${option}${tabParameter}`;
    startTransition(() => {
      setOptimisticSeason(option);
      router.push(href);
    });
  };

  return (
    <nav
      aria-label="Choose season"
      aria-busy={isPending}
      className="mt-3 inline-flex rounded-md border border-border bg-background/50 p-1"
    >
      {SUPPORTED_DASHBOARD_SEASONS.map((option) => (
        <Link
          key={option}
          href={`${seasonPath}?season=${option}${tabParameter}`}
          prefetch={false}
          aria-current={optimisticSeason === option ? 'page' : undefined}
          aria-busy={isPending && optimisticSeason === option}
          onClick={(event) => selectSeason(event, option)}
          className={`relative min-h-11 rounded px-3 py-2 text-sm font-medium transition-[background-color,color,transform] duration-150 active:scale-[0.97] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${optimisticSeason === option ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground'}`}
        >
          {option}
          {isPending && optimisticSeason === option && (
            <span
              aria-hidden="true"
              className="absolute inset-x-2 bottom-1 h-0.5 rounded-full bg-primary-foreground/70 motion-safe:animate-pulse"
            />
          )}
        </Link>
      ))}
      <span className="sr-only" role="status" aria-live="polite">
        {isPending ? `Loading ${optimisticSeason} season` : ''}
      </span>
    </nav>
  );
}

function MetricControl({ value, onChange, locationOnly = false }: {
  value: ProfileMetric;
  onChange: (value: ProfileMetric) => void;
  locationOnly?: boolean;
}) {
  const options = (locationOnly ? METRICS.slice(0, 3) : METRICS).map((item) => ({
    value: item.key,
    label: item.label,
  }));
  return <Segmented value={value} options={options} onChange={onChange} label="Choose metric" />;
}

function SettingControl({ value, settings, onChange }: {
  value: Setting;
  settings: Setting[];
  onChange: (value: Setting) => void;
}) {
  return (
    <div className="[&_button]:min-w-11">
      <Segmented
        value={value}
        options={settings.map((setting) => ({
          value: setting,
          label: setting === 'all' ? 'Overall' : setting[0].toUpperCase() + setting.slice(1),
        }))}
        onChange={onChange}
        label="Choose setting"
      />
    </div>
  );
}

function EmptyState({ children = 'No data is available for this view.' }: { children?: ReactNode }) {
  return <div className="grid min-h-40 place-items-center rounded-md border border-dashed border-border p-6 text-center text-sm text-muted-foreground">{children}</div>;
}

function reportingDiagnosisRows(
  profiles: InjuryProfileRow[],
  diagnosisFamilies: DiagnosisFamilyRow[] | null | undefined,
  supplement?: DashboardSupplement,
): InjuryProfileRow[] {
  if (diagnosisFamilies) return withoutFrontFacingUnknown(diagnosisFamilyProfiles(diagnosisFamilies));
  if (supplement?.common_injuries.length) return withoutFrontFacingUnknown(supplement.common_injuries);
  if (profiles.some((row) => row.dimension === 'diagnosis')) {
    return withoutFrontFacingUnknown(profiles.filter((row) => row.dimension === 'diagnosis'));
  }
  if (profiles.some((row) => row.dimension === 'injury_profile')) {
    return withoutFrontFacingUnknown(profiles.filter((row) => row.dimension === 'injury_profile'));
  }
  return withoutFrontFacingUnknown(profiles.filter((row) => row.dimension === 'injury_type'));
}

function OverviewTab({
  dashboard,
  profiles,
  supplement,
}: {
  dashboard: TeamDashboardData;
  profiles: InjuryProfileRow[];
  supplement?: DashboardSupplement;
}) {
  const [setting, setSetting] = useState<Setting>('all');
  const [showInjuries, setShowInjuries] = useState(true);
  const [showTlInjuries, setShowTlInjuries] = useState(true);
  const [showOverallIncidence, setShowOverallIncidence] = useState(true);
  const [showTlIncidence, setShowTlIncidence] = useState(true);
  const [severitySetting, setSeveritySetting] = useState<Setting>('all');
  const [contactSetting, setContactSetting] = useState<Setting>('all');
  const [locationMetric, setLocationMetric] = useState<LocationMetric>('time_loss_injuries');
  const [benchMetric, setBenchMetric] = useState<ProfileMetric>('time_loss_injuries');
  const [selectedCode, setSelectedCode] = useState<string>();
  const [hoveredCode, setHoveredCode] = useState<string>();

  const headline = Object.fromEntries(dashboard.headline.map((row) => [row.key, row.value]));
  const settingMetrics = supplement?.rate_setting_metrics ?? dashboard.setting_metrics;
  const metricFor = (target: Setting) => settingMetrics.find((row) => row.setting === target);
  const all = metricFor('all');
  const match = metricFor('match');
  const training = metricFor('training');
  const active = metricFor(setting) ?? all;

  // Body locations and setting metrics carry match/training rows on both payloads, but the
  // approved (non-supplement) payload has only overall monthly and severity breakdowns. The
  // filter is offered when any panel can honour it; panels that cannot stay on overall and
  // say so, rather than silently ignoring the control.
  const locationProfiles = profiles.filter((row) => row.dimension === 'body_location');
  const settingOptions = availableSettings([...locationProfiles, ...settingMetrics], ['all', 'match', 'training']);
  const settingFilterAvailable = settingOptions.length > 1;
  const effectiveSetting: Setting = settingFilterAvailable && settingOptions.includes(setting) ? setting : 'all';
  const perSettingMonthly = Boolean(supplement);
  const filtered = effectiveSetting !== 'all';
  const showsOverallOnlyKpiTrends = filtered && !perSettingMonthly;

  const recorded = supplement?.descriptive_consequence_summary.recorded_injuries
    ?? headline.recorded_injuries
    ?? dashboard.severity_distribution
      .filter((row) => !row.setting || row.setting === 'all')
      .reduce((sum, row) => sum + row.recorded_injuries, 0);
  const isOverall = effectiveSetting === 'all';
  const headlineValues = {
    recorded_injuries: active?.recorded_injuries ?? (isOverall ? recorded : null),
    time_loss_injuries: active?.time_loss_injuries ?? (isOverall ? headline.time_loss_injuries : null),
    overall_incidence_per_1000h: active?.overall_incidence_per_1000h ?? (isOverall ? headline.overall_incidence_per_1000h : null),
    incidence_per_1000h: active?.incidence_per_1000h ?? (isOverall ? headline.incidence_per_1000h : null),
  };

  const monthlyRows = supplement
    ? supplement.monthly_by_setting.filter((row) => row.setting === effectiveSetting)
    : dashboard.monthly.map((row) => ({
        month: row.month ?? '',
        setting: 'all' as const,
        recorded_injuries: row.recorded_injuries,
        time_loss_injuries: row.time_loss_injuries,
        rate_time_loss_injuries: row.time_loss_injuries,
        exposure_hours: row.exposure_hours ?? null,
        overall_incidence_per_1000h: row.overall_incidence_per_1000h ?? null,
        incidence_per_1000h: row.incidence_per_1000h ?? null,
      }));
  const timelineRows = buildSeasonTimelineRows(monthlyRows);
  const timelineHasOverallIncidence = timelineRows.some((row) => row.overall_incidence_per_1000h != null);
  const timelineHasTlIncidence = timelineRows.some((row) => row.incidence_per_1000h != null);
  // Charts start in September; KPI trends and headline totals keep the full set.
  const trend = sortByMonth(monthlyRows);
  const preliminaryRateTrend = dashboard.preliminary_monthly_rates ?? [];
  const usesPreliminaryRateTrend = preliminaryRateTrend.length > 1;
  const incidenceTrend = usesPreliminaryRateTrend
    ? preliminaryRateTrend.map((row) => row.incidence_per_1000h)
    : trend.map((row) => row.incidence_per_1000h ?? null);
  // The burden tile's own series. Monthly burden is a released value on the
  // approved monthly rows but is not carried per setting, so this one series is
  // always the overall season shape.
  const burdenTrend = usesPreliminaryRateTrend
    ? preliminaryRateTrend.map((row) => row.burden_per_1000h)
    : sortByMonth(
        dashboard.monthly.map((row) => ({ month: row.month ?? '', burden_per_1000h: row.burden_per_1000h ?? null }))
      ).map((row) => row.burden_per_1000h);

  const locationSettings = availableSettings(locationProfiles, ['all', 'match', 'training']);
  const locationSetting = locationSettings.includes(effectiveSetting) ? effectiveSetting : locationSettings[0] ?? 'all';
  const { rows: locationRows, barRows, activeCode, selected } = resolveLocationView({
    profiles: locationProfiles,
    setting: locationSetting,
    metric: locationMetric,
    selectedCode,
    hoveredCode,
  });
  const locationMax = Math.max(...barRows.map((row) => metricValue(row, locationMetric)), 0);

  const severityDistribution = supplement?.severity_distribution ?? dashboard.severity_distribution;
  const severitySettings = availableSettings(
    severityDistribution.filter((row): row is typeof row & { setting: Setting } => Boolean(row.setting)),
    ['all', 'match', 'training'],
  );
  const effectiveSeveritySetting = severitySettings.includes(severitySetting) ? severitySetting : severitySettings[0] ?? 'all';
  const severitySource = severitySettings.length
    ? severityDistribution.filter((row) => row.setting === effectiveSeveritySetting)
    : severityDistribution;
  const severityRows = [
    { key: 'one_to_seven', label: '1-7 Days', value: severitySource.filter((row) => ['one_day', 'two_to_three_days', 'four_to_seven_days'].includes(row.key)).reduce((sum, row) => sum + row.time_loss_injuries, 0) },
    { key: 'eight_to_twenty_eight', label: '8-28 Days', value: severitySource.find((row) => row.key === 'eight_to_twenty_eight_days')?.time_loss_injuries ?? 0 },
    { key: 'greater_than_twenty_eight', label: 'Over 28 Days', value: severitySource.find((row) => row.key === 'greater_than_twenty_eight_days')?.time_loss_injuries ?? 0 },
  ]
    .map((row) => ({ ...row, color: SEVERITY_BAND_COLORS[row.key] }));

  // Unlike the other breakdowns this one keeps its Unknown slice, so the ring
  // reads as a share of all cases rather than of the classified ones only.
  const contactOrder = ['contact', 'non_contact', 'unknown'];
  const contactDistribution = dashboard.contact_distribution ?? supplement?.contact_distribution ?? [];
  const contactSettings = availableSettings(contactDistribution, ['all', 'match', 'training']);
  const effectiveContactSetting = contactSettings.includes(contactSetting) ? contactSetting : contactSettings[0] ?? 'all';
  const contactRows = contactDistribution
    .filter((row) => row.setting === effectiveContactSetting)
    .map((row) => ({
      key: row.key,
      label: row.label,
      value: row.time_loss_injuries,
      color: CONTACT_RING_COLORS[row.key] ?? CONTACT_RING_COLORS.unknown,
    }))
    .sort((a, b) => contactOrder.indexOf(a.key) - contactOrder.indexOf(b.key));

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className={SECTION_HEADING_CLASS}>
          {dashboard.scope === 'league' ? 'League Injury Overview' : 'Team Injury Overview'}
        </h2>
        {settingFilterAvailable && (
          <SettingControl value={effectiveSetting} settings={settingOptions} onChange={setSetting} />
        )}
      </div>

      <div className="rounded-lg border border-sky-300/25 bg-sky-300/[0.07] px-3 py-2.5 text-xs leading-relaxed text-muted-foreground" role="note">
        Unless explicitly stated, injuries, injury counts, incidence and burden are based on Time Loss Injuries.
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatTile
          label="Injuries"
          value={fmt(headlineValues.time_loss_injuries, 0)}
          unit="injuries"
          companion={<PairedStat label="Overall Injuries" value={fmt(headlineValues.recorded_injuries, 0)} color={SETTING_COLORS.all} />}
        >
          <ScopeChip show={showsOverallOnlyKpiTrends} label="Overall Trend" />
          <Sparkline values={trend.map((row) => row.time_loss_injuries ?? null)} color={SETTING_COLORS.all} ariaLabel="Injuries By Month" />
        </StatTile>
        <StatTile
          label="Incidence"
          value={fmt(headlineValues.incidence_per_1000h)}
          unit="injuries /1,000 h"
          companion={<PairedStat label="Overall Incidence" value={fmt(headlineValues.overall_incidence_per_1000h)} color={SETTING_COLORS.all} />}
        >
          <ScopeChip show={showsOverallOnlyKpiTrends} label="Overall Trend" />
          <Sparkline values={incidenceTrend} color="#ffc45c" ariaLabel="Incidence By Month" />
        </StatTile>
        <StatTile
          label="Burden"
          value={fmt(active?.burden_per_1000h ?? (filtered ? null : headline.burden_per_1000h))}
          unit="days /1,000 h"
        >
          <ScopeChip show={showsOverallOnlyKpiTrends} label="Overall Trend" />
          <Sparkline values={burdenTrend} color="#ef7189" ariaLabel="Burden By Month" />
        </StatTile>
        <StatTile
          label="Exposure"
          value={fmtHours(filtered ? active?.exposure_hours : dashboard.coverage.hours)}
          unit="player-hours"
        >
          <ScopeChip show={showsOverallOnlyKpiTrends} label="Overall Trend" />
          <Sparkline values={trend.map((row) => row.exposure_hours)} color="#42d8b4" ariaLabel="Exposure Hours By Month" />
        </StatTile>
      </div>

      <Panel contentClassName="p-4 sm:p-5">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <h3 className={PANEL_HEADING_CLASS}>Season Timeline</h3>
            <ScopeChip show={effectiveSetting !== 'all' && !perSettingMonthly} />
          </div>
          <div className="flex flex-wrap gap-4">
            <CheckToggle checked={showInjuries} onChange={setShowInjuries} label="Overall Injuries" swatch={SETTING_COLORS.all} />
            <CheckToggle checked={showTlInjuries} onChange={setShowTlInjuries} label="Time Loss Injuries" swatch="#ffc45c" />
            <CheckToggle checked={showOverallIncidence && timelineHasOverallIncidence} disabled={!timelineHasOverallIncidence} onChange={setShowOverallIncidence} label="Overall Incidence" swatch={SETTING_COLORS.all} />
            <CheckToggle checked={showTlIncidence && timelineHasTlIncidence} disabled={!timelineHasTlIncidence} onChange={setShowTlIncidence} label="Time Loss Incidence" swatch="#ffc45c" />
          </div>
        </div>
        <div className="overflow-x-auto">
          <SeasonTimelineChart
            rows={timelineRows}
            showInjuries={showInjuries}
            showTlInjuries={showTlInjuries}
            showOverallIncidence={showOverallIncidence && timelineHasOverallIncidence}
            showTlIncidence={showTlIncidence && timelineHasTlIncidence}
          />
        </div>
      </Panel>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]">
        <Panel contentClassName="p-4 sm:p-5">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <h3 className={PANEL_HEADING_CLASS}>Injury Location</h3>
            <Segmented
              value={locationMetric}
              options={[
                { value: 'time_loss_injuries' as LocationMetric, label: 'Count' },
                { value: 'incidence_per_1000h' as LocationMetric, label: 'Incidence' },
                { value: 'burden_per_1000h' as LocationMetric, label: 'Burden' },
              ]}
              onChange={setLocationMetric}
              label="Choose body map metric"
            />
          </div>
          {locationRows.length ? (
            <div className="grid gap-5 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] sm:items-start">
              <BodyMap
                rows={locationRows}
                metric={locationMetric}
                activeCode={activeCode}
                onHover={setHoveredCode}
                onSelect={setSelectedCode}
              />
              <div>
                <p className="mb-2 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">Top Locations</p>
                <ol className="space-y-1">
                  {barRows.slice(0, 8).map((row) => {
                    const value = metricValue(row, locationMetric);
                    const isActive = row.code === activeCode;
                    return (
                      <li key={row.code}>
                        <button
                          type="button"
                          onMouseEnter={() => setHoveredCode(row.code)}
                          onFocus={() => setHoveredCode(row.code)}
                          onMouseLeave={() => setHoveredCode(undefined)}
                          onClick={() => setSelectedCode(row.code)}
                          className={`grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-3 rounded px-1.5 py-1.5 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${isActive ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
                          aria-label={`${row.label}: ${fmt(value)}`}
                        >
                          <span className="min-w-0">
                            <span className="block truncate text-xs text-foreground">{row.label}</span>
                            <span className="mt-1 block h-1.5 overflow-hidden rounded-full bg-muted">
                              <span
                                className="block h-full rounded-full"
                                style={{
                                  width: `${locationMax > 0 ? Math.max((value / locationMax) * 100, 2) : 0}%`,
                                  background: locationHeatColor(value, locationMax),
                                }}
                              />
                            </span>
                          </span>
                          <span className="text-xs font-semibold tabular-nums text-foreground">{fmt(value)}</span>
                        </button>
                      </li>
                    );
                  })}
                </ol>
                {selected && (
                  <p className="mt-3 border-t border-border/60 pt-3 text-xs text-muted-foreground">
                    <span className="font-semibold text-foreground">{selected.label}</span>
                    {' - '}
                    {fmt(selected.time_loss_injuries, 0)} injuries, {fmt(selected.mean_severity_days)} mean days lost
                  </p>
                )}
              </div>
            </div>
          ) : <EmptyState />}
        </Panel>

        <Panel contentClassName="p-4 sm:p-5">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <h3 className={PANEL_HEADING_CLASS}>Severity</h3>
            {severitySettings.length > 1 && (
              <SettingControl value={effectiveSeveritySetting} settings={severitySettings} onChange={setSeveritySetting} />
            )}
          </div>
          <SeverityArc rows={severityRows} />
        </Panel>
      </div>

      {/* Contact mechanism sits beside the match/training bench so the setting
          split is read with the mechanism that produced it. The bench keeps the
          wider column; the ring is the compact square card. */}
      <div className={`grid gap-5 ${contactRows.length ? 'xl:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]' : ''}`}>
        {contactRows.length > 0 && (
          <Panel contentClassName="p-4 sm:p-5">
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
              <h3 className={PANEL_HEADING_CLASS}>Contact Mechanism</h3>
              {contactSettings.length > 1 && (
                <SettingControl value={effectiveContactSetting} settings={contactSettings} onChange={setContactSetting} />
              )}
            </div>
            <SeverityArc rows={contactRows} scaleLabels={null} ariaLabel="Contact Mechanism Breakdown" />
          </Panel>
        )}
        <Panel contentClassName="p-4 sm:p-5">
          <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
            <h3 className={PANEL_HEADING_CLASS}>Match Vs Training</h3>
            <MetricControl value={benchMetric} onChange={setBenchMetric} />
          </div>
          <SettingBench match={match} training={training} metric={benchMetric} />
        </Panel>
      </div>
    </div>
  );
}

/**
 * Season order for the sparkline series. Delegates to the charts module so the
 * tiles and the plots order a season identically, and so neither of them parses
 * a month label as a date: Safari rejects `"Sep 2024"` where V8 accepts it.
 */
function sortByMonth<T extends { month: string }>(rows: T[]) {
  return sortSeasonMonths(rows);
}

function StatTile({ label, value, unit, companion, children }: {
  label: string;
  value: string;
  unit?: string;
  companion?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <Card className="min-w-0 border-border/70 bg-card/70 shadow-none">
      <CardContent className="p-4 sm:p-5">
        <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">{label}</p>
        <div className="mt-2 flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-3xl font-bold leading-none tracking-tight tabular-nums text-foreground sm:text-4xl">{value}</p>
            {unit && <p className="mt-1.5 text-[11px] text-muted-foreground">{unit}</p>}
          </div>
          {companion}
        </div>
        {children && <div className="mt-3">{children}</div>}
      </CardContent>
    </Card>
  );
}

function PairedStat({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <p className="shrink-0 text-right text-xs" style={{ color }}>
      <span className="block font-medium">{label}</span>
      <span className="mt-1 block text-lg font-semibold leading-none tabular-nums">{value}</span>
    </p>
  );
}

function ScopeChip({ show, label = 'Overall' }: { show: boolean; label?: string }) {
  if (!show) return null;
  return (
    <span className="rounded border border-border/70 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
      {label}
    </span>
  );
}

function CheckToggle({ checked, onChange, label, swatch, disabled = false }: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  swatch?: string;
  disabled?: boolean;
}) {
  return (
    <label title={disabled ? `${label} is not available for the released monthly cohort.` : undefined} className={`inline-flex min-h-11 select-none items-center gap-2 text-xs font-medium text-muted-foreground ${disabled ? 'cursor-not-allowed opacity-50' : 'cursor-pointer'}`}>
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.target.checked)}
        className="h-4 w-4 rounded border-border accent-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      />
      {swatch && <span className="h-2 w-2 rounded-full" style={{ background: swatch }} aria-hidden="true" />}
      {label}
    </label>
  );
}

function SettingBench({ match, training, metric }: {
  match?: SettingMetricRow;
  training?: SettingMetricRow;
  metric: ProfileMetric;
}) {
  const meta = metricMeta(metric);
  const rows = [
    { key: 'match', label: 'Match', row: match, color: SETTING_COLORS.match },
    { key: 'training', label: 'Training', row: training, color: SETTING_COLORS.training },
  ];
  const max = Math.max(...rows.map((entry) => settingMetricValue(entry.row, metric)), 0);
  if (max <= 0) return <EmptyState />;

  return (
    <div className="space-y-4">
      {rows.map((entry) => {
        const value = settingMetricValue(entry.row, metric);
        return (
          <div key={entry.key} className="grid gap-2 sm:grid-cols-[5.5rem_minmax(0,1fr)_9rem] sm:items-center sm:gap-4">
            <p className="text-sm font-semibold text-foreground">{entry.label}</p>
            <div className="h-7 overflow-hidden rounded-md bg-muted/60">
              <div
                className="h-full rounded-md transition-[width] duration-300"
                style={{ width: `${Math.max((value / max) * 100, 1.5)}%`, background: entry.color }}
              />
            </div>
            {/* The unit sits on its own line and never breaks inside itself, so a
                long one (days/1,000 h) cannot push the value out of the card. */}
            <p className="min-w-0 text-right text-lg font-semibold tabular-nums text-foreground sm:text-xl">
              {fmt(value)}
              <span className="block whitespace-nowrap text-[10px] font-normal text-muted-foreground">{meta.shortUnit}</span>
            </p>
          </div>
        );
      })}
      <div className="grid gap-3 border-t border-border/60 pt-4 sm:grid-cols-2">
        <BenchFoot label="Match Injuries" value={fmt(match?.time_loss_injuries, 0)} />
        <BenchFoot label="Training Injuries" value={fmt(training?.time_loss_injuries, 0)} />
      </div>
    </div>
  );
}

function settingMetricValue(row: SettingMetricRow | undefined, metric: ProfileMetric) {
  const value = row?.[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function BenchFoot({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="mt-1 text-lg font-semibold tabular-nums text-foreground">{value}</p>
    </div>
  );
}

function OverviewStat({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div className="border-b border-border/60 p-5 last:border-b-0 sm:border-b-0 sm:border-r sm:last:border-r-0 lg:p-6">
      <p className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="mt-3 text-4xl font-bold tracking-tight tabular-nums text-foreground sm:text-5xl">{value}</p>
      {unit && <p className="mt-1 text-xs text-muted-foreground">{unit}</p>}
    </div>
  );
}

function CommonInjuriesTab({ dashboard, profiles, supplement }: {
  dashboard: TeamDashboardData;
  profiles: InjuryProfileRow[];
  supplement?: DashboardSupplement;
}) {
  const [impactDimension, setImpactDimension] = useState<'diagnosis' | 'location' | 'type'>('diagnosis');
  const source = reportingDiagnosisRows(profiles, dashboard.diagnosis_families, supplement);
  const settings = availableSettings(source, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const rows = source.filter((row) => row.setting === setting);
  const injuryColors = commonInjuryColorMap(source);
  const totalInjuries = supplement?.rate_setting_metrics
    .find((row) => row.setting === setting)?.time_loss_injuries
    ?? (setting === 'all'
      ? dashboard.headline.find((row) => row.key === 'time_loss_injuries')?.value
      : dashboard.setting_metrics.find((row) => row.setting === setting)?.time_loss_injuries)
    ?? 0;
  const settingTitle = setting === 'all' ? '' : `${setting[0].toUpperCase()}${setting.slice(1)} `;
  // The tab's own setting control already filtered these rows, so the impact panel
  // honours the filter directly and needs no scope chip of its own.
  const impactSource = impactDimension === 'diagnosis'
    ? source
    : profiles.filter((row) => row.dimension === (impactDimension === 'location' ? 'body_location' : 'injury_type'));
  const impactCohort = impactSource.filter((row) => row.setting === setting);
  const impactRows = impactCohort
    .filter((row) => totalInjuries > 0 && row.time_loss_injuries / totalInjuries >= 0.013)
    .sort((a, b) => b.time_loss_injuries - a.time_loss_injuries || (b.burden_per_1000h ?? 0) - (a.burden_per_1000h ?? 0));
  if (impactDimension === 'diagnosis') {
    const included = new Set(impactRows.map((row) => row.code));
    impactCohort
      .filter((row) => row.time_loss_injuries > 0 && isKneeLigamentDiagnosis(row) && !included.has(row.code))
      .forEach((row) => impactRows.push(row));
  }
  return (
    <div>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4 border-b border-border/60 pb-4">
        <div>
          <h2 className={SECTION_HEADING_CLASS}>Most Common {settingTitle}Injuries</h2>
        </div>
        <SettingControl value={setting} settings={settings.length ? settings : ['all', 'match', 'training']} onChange={setSetting} />
      </div>
      {rows.length ? (
        <>
          <CommonInjuryRankings rows={rows} totalInjuries={totalInjuries} injuryColors={injuryColors} />
          <section aria-labelledby="common-injuries-risk-matrix" className="mt-8">
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
              <h3 id="common-injuries-risk-matrix" className={PANEL_HEADING_CLASS}>Risk Matrix</h3>
              <Segmented
                value={impactDimension}
                options={[
                  { value: 'diagnosis', label: 'Diagnosis' },
                  { value: 'location', label: 'Location' },
                  { value: 'type', label: 'Type' },
                ]}
                onChange={setImpactDimension}
                label="Choose impact grouping"
              />
            </div>
            <Panel>
              <ImpactScatterChart rows={impactRows} />
            </Panel>
          </section>
        </>
      ) : <EmptyState />}
    </div>
  );
}

type IllnessMetric = 'recorded_illnesses' | 'incidence_per_1000h' | 'burden_per_1000h' | 'mean_severity_days';

const ILLNESS_METRICS: Array<{ key: IllnessMetric; label: string; unit: string }> = [
  { key: 'recorded_illnesses', label: 'Count', unit: 'illnesses' },
  { key: 'incidence_per_1000h', label: 'Incidence', unit: 'illnesses per 1,000 player-h' },
  { key: 'burden_per_1000h', label: 'Burden', unit: 'days per 1,000 player-h' },
  { key: 'mean_severity_days', label: 'Severity', unit: 'mean days lost' },
];

function IllnessesTab({ dashboard }: { dashboard: TeamDashboardData }) {
  const summary = dashboard.illness_summary;
  const rows = withoutFrontFacingUnknown(dashboard.illness_profiles ?? [])
    .filter((row) => row.setting === 'all')
    .sort((left, right) => right.recorded_illnesses - left.recorded_illnesses || left.label.localeCompare(right.label));
  const totalIllnesses = summary?.recorded_illnesses
    ?? rows.reduce((total, row) => total + row.recorded_illnesses, 0);
  const illnessColors = illnessColorMap(rows);

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className={SECTION_HEADING_CLASS}>Most Common Illnesses</h2>
      </div>

      <p className="text-xs text-muted-foreground" role="note">
        Overall illness reporting only. Illnesses are not attributed to Match or Training.
      </p>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {ILLNESS_METRICS.map((metric) => (
          <StatTile
            key={metric.key}
            label={metric.key === 'recorded_illnesses' ? 'Illnesses' : metric.label}
            value={fmt(summary?.[metric.key], metric.key === 'recorded_illnesses' ? 0 : 1)}
            unit={ILLNESS_KPI_UNITS[metric.key]}
          >
            <Sparkline
              values={rankedIllnesses(rows, metric.key).map((row) => row[metric.key])}
              color={ILLNESS_KPI_COLORS[metric.key]}
              ariaLabel={`Top Illnesses By ${metric.label}`}
            />
          </StatTile>
        ))}
      </div>

      {rows.length ? (
        <div className="grid gap-6 pt-1 md:grid-cols-2 xl:grid-cols-4">
          {ILLNESS_METRICS.map((metric) => (
            <IllnessLane
              key={metric.key}
              metric={metric}
              rows={rows}
              totalIllnesses={totalIllnesses}
              illnessColors={illnessColors}
            />
          ))}
        </div>
      ) : <EmptyState>No released illness profiles are available.</EmptyState>}
    </div>
  );
}

const ILLNESS_KPI_UNITS: Record<IllnessMetric, string> = {
  recorded_illnesses: 'illnesses',
  incidence_per_1000h: 'illnesses /1,000 h',
  burden_per_1000h: 'days /1,000 h',
  mean_severity_days: 'mean days lost',
};

const ILLNESS_KPI_COLORS: Record<IllnessMetric, string> = {
  recorded_illnesses: SETTING_COLORS.all,
  incidence_per_1000h: '#ffc45c',
  burden_per_1000h: '#ef7189',
  mean_severity_days: '#42d8b4',
};

function IllnessLane({
  metric,
  rows,
  totalIllnesses,
  illnessColors,
}: {
  metric: (typeof ILLNESS_METRICS)[number];
  rows: IllnessProfileRow[];
  totalIllnesses: number;
  illnessColors: Map<string, InjuryCardColor>;
}) {
  const ranked = rankedIllnesses(rows, metric.key);

  return (
    <section aria-labelledby={`common-illnesses-${metric.key}`}>
      <h3 id={`common-illnesses-${metric.key}`} className={`${PANEL_HEADING_CLASS} mb-3`}>{metric.label}</h3>
      {ranked.length ? (
        <ol className="space-y-2.5">
          {ranked.map((row, index) => (
            <IllnessCard
              key={`${metric.key}-${row.code}`}
              row={row}
              metric={metric}
              rank={index + 1}
              totalIllnesses={totalIllnesses}
              color={illnessColors.get(row.code) ?? { background: profileColor(row.code), foreground: '#ffffff' }}
            />
          ))}
        </ol>
      ) : <EmptyState>No ranked illnesses are available for {metric.label.toLowerCase()}.</EmptyState>}
    </section>
  );
}

function IllnessCard({
  row,
  metric,
  rank,
  totalIllnesses,
  color,
}: {
  row: IllnessProfileRow;
  metric: (typeof ILLNESS_METRICS)[number];
  rank: number;
  totalIllnesses: number;
  color: InjuryCardColor;
}) {
  const share = totalIllnesses > 0 ? Math.round((row.recorded_illnesses / totalIllnesses) * 100) : 0;
  const value = fmt(row[metric.key], metric.key === 'recorded_illnesses' ? 0 : 1);

  return (
    <li
      className="group min-h-24 animate-in overflow-hidden rounded-lg px-3 py-3.5 shadow-sm fill-mode-both fade-in slide-in-from-bottom-2 duration-200 transition-[transform,box-shadow,filter] ease-out hover:-translate-y-0.5 hover:shadow-lg hover:shadow-black/40 hover:brightness-110 motion-reduce:animate-none motion-reduce:transition-none motion-reduce:hover:transform-none"
      style={{
        backgroundColor: `color-mix(in srgb, ${color.background} 90%, black)`,
        color: color.foreground,
        animationDelay: `${(rank - 1) * 60}ms`,
        animationDuration: '450ms',
      }}
    >
      <article className="flex h-full items-center justify-between gap-3" aria-label={`${rank}. ${row.label}, ${value} ${metric.unit}`}>
        <div className="min-w-0 self-center">
          <h4 className="text-sm font-semibold leading-snug text-inherit">{row.label}</h4>
          {metric.key === 'recorded_illnesses' && (
            <p className="mt-1 text-xs text-inherit">{share}% of illnesses</p>
          )}
        </div>
        <div className="shrink-0 text-right">
          <p className="text-xl font-bold leading-none tabular-nums text-inherit transition-transform duration-200 ease-out origin-right group-hover:scale-105 motion-reduce:transform-none">{value}</p>
          <p className="mt-1 text-[11px] leading-tight text-inherit">{metric.unit}</p>
        </div>
      </article>
    </li>
  );
}

function CommonInjuryRankings({
  rows,
  totalInjuries,
  injuryColors,
}: {
  rows: InjuryProfileRow[];
  totalInjuries: number;
  injuryColors: Map<string, InjuryCardColor>;
}) {
  return (
    <div className="grid gap-6 md:grid-cols-2 xl:grid-cols-4">
      {METRICS.map((metric) => (
        <CommonInjuryLane
          key={metric.key}
          metric={metric}
          rows={rows}
          totalInjuries={totalInjuries}
          injuryColors={injuryColors}
        />
      ))}
    </div>
  );
}

function CommonInjuryLane({
  metric,
  rows,
  totalInjuries,
  injuryColors,
}: {
  metric: (typeof METRICS)[number];
  rows: InjuryProfileRow[];
  totalInjuries: number;
  injuryColors: Map<string, InjuryCardColor>;
}) {
  const ranked = rankedCommonInjuries(rows, metric.key);

  return (
    <section aria-labelledby={`common-injuries-${metric.key}`}>
      <h3 id={`common-injuries-${metric.key}`} className={`${PANEL_HEADING_CLASS} mb-3 capitalize`}>
        {metric.label}
      </h3>
      {ranked.length ? (
        <ol className="space-y-2.5">
          {ranked.map((row, index) => (
            <CommonInjuryCard
              key={`${row.setting}-${metric.key}-${row.code}`}
              row={row}
              metric={metric.key}
              rank={index + 1}
              totalInjuries={totalInjuries}
              color={injuryColors.get(row.code) ?? { background: profileColor(row.code), foreground: '#ffffff' }}
            />
          ))}
        </ol>
      ) : <EmptyState>No ranked injuries are available for {metric.label.toLowerCase()}.</EmptyState>}
    </section>
  );
}

function CommonInjuryCard({
  row,
  metric,
  rank,
  totalInjuries,
  color,
}: {
  row: InjuryProfileRow;
  metric: ProfileMetric;
  rank: number;
  totalInjuries: number;
  color: InjuryCardColor;
}) {
  const share = totalInjuries > 0 ? Math.round((row.time_loss_injuries / totalInjuries) * 100) : 0;
  const unit = metric === 'time_loss_injuries'
    ? 'injuries'
    : metric === 'incidence_per_1000h'
      ? 'injuries per 1,000 player-h'
      : metric === 'burden_per_1000h'
        ? 'days per 1,000 player-h'
        : 'mean days lost';

  return (
    <li
      className="group min-h-24 animate-in overflow-hidden rounded-lg px-3 py-3.5 shadow-sm fill-mode-both fade-in slide-in-from-bottom-2 duration-200 transition-[transform,box-shadow,filter] ease-out hover:-translate-y-0.5 hover:shadow-lg hover:shadow-black/40 hover:brightness-110 motion-reduce:animate-none motion-reduce:transition-none motion-reduce:hover:transform-none"
      style={{
        backgroundColor: `color-mix(in srgb, ${color.background} 90%, black)`,
        color: color.foreground,
        animationDelay: `${(rank - 1) * 60}ms`,
        animationDuration: '450ms',
      }}
    >
      <article className="flex h-full items-center justify-between gap-3" aria-label={`${rank}. ${row.label}, ${fmt(row[metric], metric === 'time_loss_injuries' ? 0 : 1)} ${unit}`}>
        <div className="min-w-0 self-center">
          <h4 className="text-sm font-semibold leading-snug text-inherit capitalize">{row.label}</h4>
          {metric === 'time_loss_injuries' && (
            <p className="mt-1 text-xs text-inherit">{share}% of injuries</p>
          )}
        </div>
        <div className="shrink-0 text-right">
          <p className="text-xl font-bold leading-none tabular-nums text-inherit transition-transform duration-200 ease-out origin-right group-hover:scale-105 motion-reduce:transform-none">{fmt(row[metric], metric === 'time_loss_injuries' ? 0 : 1)}</p>
          <p className="mt-1 text-[11px] leading-tight text-inherit">{unit}</p>
        </div>
      </article>
    </li>
  );
}

type ComparisonMetric = 'incidence_per_1000h' | 'burden_per_1000h';
type ComparisonSetting = 'all' | 'match' | 'training';

function deltaTone(delta: number) {
  if (delta <= -10) return 'bg-emerald-500/20 text-emerald-100';
  if (delta >= 10) return 'bg-red-500/20 text-red-100';
  return 'bg-amber-400/20 text-amber-100';
}

function TeamComparisonTab({
  rows,
  leagueMetrics,
  teamName,
  viewerComparisonId,
  teamColor,
}: {
  rows: TeamComparisonRow[];
  leagueMetrics: SettingMetricRow[];
  teamName: string;
  viewerComparisonId?: string | null;
  teamColor?: TeamColorSet;
}) {
  const comparisonSettings: Array<{ value: ComparisonSetting; label: string }> = [
    { value: 'all', label: 'Overall' },
    { value: 'match', label: 'Match' },
    { value: 'training', label: 'Training' },
  ];
  const availableSettingOptions = comparisonSettings.filter(({ value }) => rows.some((row) => row[value]));
  const [setting, setSetting] = useState<ComparisonSetting>('all');
  const [metric, setMetric] = useState<ComparisonMetric>('incidence_per_1000h');
  const [hoveredId, setHoveredId] = useState<string>();
  const [selectedId, setSelectedId] = useState<string>();
  const activeSetting = availableSettingOptions.some(({ value }) => value === setting)
    ? setting
    : availableSettingOptions[0]?.value ?? 'all';
  const benchmark = leagueMetrics.find((row) => row.setting === activeSetting);
  const matchBenchmark = leagueMetrics.find((row) => row.setting === 'match');
  const trainingBenchmark = leagueMetrics.find((row) => row.setting === 'training');
  const ranked = [...rows]
    .filter((row) => row[activeSetting]?.[metric] != null)
    .sort((a, b) => (b[activeSetting]?.[metric] ?? 0) - (a[activeSetting]?.[metric] ?? 0));
  const leagueMean = benchmark?.[metric];
  const max = Math.max(
    ...ranked.map((row) => row[activeSetting]?.[metric] ?? 0),
    typeof leagueMean === 'number' && Number.isFinite(leagueMean) ? leagueMean : 0,
    1,
  );
  const activeId = hoveredId ?? selectedId;
  const ladderRef = useRef<HTMLDivElement>(null);
  const ladderPositions = useRef(new Map<string, number>());

  // Re-rank smoothly: capture each row's previous offset and slide it to its new place.
  useLayoutEffect(() => {
    const list = ladderRef.current;
    if (!list) return;
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    list.querySelectorAll<HTMLElement>('[data-row-id]').forEach((item) => {
      const id = item.dataset.rowId ?? '';
      const next = item.offsetTop;
      const previous = ladderPositions.current.get(id);
      ladderPositions.current.set(id, next);
      if (reduceMotion || previous === undefined || previous === next) return;
      item.animate(
        [{ transform: `translateY(${previous - next}px)` }, { transform: 'translateY(0)' }],
        { duration: COMPARISON_ANIMATION_MS, easing: COMPARISON_EASING },
      );
    });
  }, [activeSetting, metric]);

  if (!rows.length) return <EmptyState>No approved team comparison rows are available.</EmptyState>;
  const settingLabel = activeSetting === 'all'
    ? 'Overall'
    : `${activeSetting[0].toUpperCase()}${activeSetting.slice(1)}`;
  const metricLabel = metric === 'incidence_per_1000h' ? 'Incidence' : 'Burden';
  const metricUnit = metric === 'incidence_per_1000h' ? 'injuries /1,000 hours' : 'days /1,000 hours';
  // The viewer's own row leads the table; the rest stay alphabetical by alias.
  const alphabetical = [...rows].sort((a, b) => {
    if (a.comparison_id === viewerComparisonId) return -1;
    if (b.comparison_id === viewerComparisonId) return 1;
    return a.team_alias.localeCompare(b.team_alias);
  });
  // Positions, dot area and crosshairs all read released comparison fields; the
  // panel is fixed to match against training, so the setting control above it
  // does not apply and says so with a chip.
  const scatterRows: ComparisonScatterRow[] = rows
    .filter((row) => (
      typeof row.match?.incidence_per_1000h === 'number'
      && typeof row.training?.incidence_per_1000h === 'number'
    ))
    .filter(hasKnownExposure)
    .map((row) => ({
      comparison_id: row.comparison_id,
      label: row.comparison_id === viewerComparisonId ? teamName : row.team_alias,
      match_incidence: row.match?.incidence_per_1000h ?? 0,
      training_incidence: row.training?.incidence_per_1000h ?? 0,
      exposure_hours: row.exposure_hours,
      is_viewer: row.comparison_id === viewerComparisonId,
    }));
  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-x-4 gap-y-3">
        <h2 className={SECTION_HEADING_CLASS}>Team Comparison</h2>
        <div className="flex flex-wrap items-center gap-2">
          <Segmented value={activeSetting} options={availableSettingOptions.length ? availableSettingOptions : comparisonSettings} onChange={setSetting} label="Choose comparison setting" />
          <Segmented value={metric} options={[{ value: 'incidence_per_1000h', label: 'Incidence' }, { value: 'burden_per_1000h', label: 'Burden' }]} onChange={setMetric} label="Choose comparison metric" />
        </div>
      </div>
      <div className="mb-4 grid grid-cols-2 overflow-hidden rounded-lg border border-border/70 bg-card/70">
        <OverviewStat label={`League ${settingLabel} Incidence`} value={fmt(benchmark?.incidence_per_1000h)} unit="injuries /1,000 hours" />
        <OverviewStat label={`League ${settingLabel} Burden`} value={fmt(benchmark?.burden_per_1000h)} unit="days /1,000 hours" />
      </div>
      <div className="space-y-4">
        <Panel title={`Ranked By ${settingLabel} ${metricLabel} (${metricUnit})`}>
          <div ref={ladderRef} className="min-w-0">
            {ranked.map((row, index) => (
              <ComparisonBarRow
                key={row.comparison_id}
                row={row}
                rank={index + 1}
                value={row[activeSetting]?.[metric] ?? 0}
                max={max}
                metric={metric}
                metricLabel={metricLabel}
                setting={activeSetting}
                leagueMean={leagueMean}
                active={activeId === row.comparison_id}
                isViewer={row.comparison_id === viewerComparisonId}
                viewerColor={teamColor?.mark}
                viewerName={teamName}
                onHover={setHoveredId}
                onSelect={setSelectedId}
              />
            ))}
          </div>
          {typeof leagueMean === 'number' && Number.isFinite(leagueMean) && (
            <div className="mt-4 flex justify-end border-t border-border/60 pt-3" aria-label="Chart legend">
              <span className="inline-flex items-center gap-2 rounded-md bg-muted/50 px-3 py-2 text-xs text-muted-foreground">
                <i aria-hidden="true" className="h-4 border-l-2 border-dotted border-orange-400" />
                <strong className="font-semibold text-foreground">League Mean</strong>
              </span>
            </div>
          )}
        </Panel>
        <Panel title="Match And Training Values Vs League Average">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[560px] table-fixed text-sm">
              <thead className="text-muted-foreground">
                <tr>
                  <th rowSpan={2} className="w-[22%] px-3 pb-2 text-left text-sm font-semibold text-foreground align-bottom">Team</th>
                  <th colSpan={2} className="rounded-t-md border-l-2 border-card bg-primary/15 px-3 py-1.5 text-center text-sm font-semibold uppercase tracking-[0.14em] text-foreground">Match</th>
                  <th colSpan={2} className="rounded-t-md border-l-4 border-card bg-primary/15 px-3 py-1.5 text-center text-sm font-semibold uppercase tracking-[0.14em] text-foreground">Training</th>
                </tr>
                <tr>
                  <th className="border-l-2 border-card px-3 pb-1.5 pt-1 text-center text-sm font-medium text-foreground">Incidence</th>
                  <th className="border-l-2 border-card px-3 pb-1.5 pt-1 text-center text-sm font-medium text-foreground">Burden</th>
                  <th className="border-l-4 border-card px-3 pb-1.5 pt-1 text-center text-sm font-medium text-foreground">Incidence</th>
                  <th className="border-l-2 border-card px-3 pb-1.5 pt-1 text-center text-sm font-medium text-foreground">Burden</th>
                </tr>
              </thead>
              <tbody>
                {alphabetical.map((row) => (
                  <tr
                    key={row.comparison_id}
                    className={`border-t border-border/40 ${activeId === row.comparison_id ? 'bg-muted/40' : ''}`}
                    onMouseEnter={() => setHoveredId(row.comparison_id)}
                    onMouseLeave={() => setHoveredId(undefined)}
                  >
                    <td className="font-medium text-foreground">
                      <button
                        type="button"
                        onFocus={() => setHoveredId(row.comparison_id)}
                        onBlur={() => setHoveredId(undefined)}
                        onClick={() => setSelectedId(row.comparison_id)}
                        className="flex min-h-12 w-full items-center rounded px-3 text-left text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:min-h-14 sm:text-base lg:min-h-8"
                      >
                        {row.comparison_id === viewerComparisonId ? teamName : row.team_alias}
                      </button>
                    </td>
                    <BenchmarkCell value={row.match?.incidence_per_1000h} average={matchBenchmark?.incidence_per_1000h} />
                    <BenchmarkCell value={row.match?.burden_per_1000h} average={matchBenchmark?.burden_per_1000h} />
                    <BenchmarkCell value={row.training?.incidence_per_1000h} average={trainingBenchmark?.incidence_per_1000h} groupStart />
                    <BenchmarkCell value={row.training?.burden_per_1000h} average={trainingBenchmark?.burden_per_1000h} />
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-3 flex flex-wrap justify-end gap-x-4 gap-y-2 border-t border-border/60 pt-2.5 text-right text-[11px] text-muted-foreground">
            <span>Values are per 1,000 player-hours.</span>
            <span><i className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-emerald-500/55" />≥10% below league average</span>
            <span><i className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-amber-400/55" />within ±10%</span>
            <span><i className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-red-500/55" />≥10% above</span>
          </div>
        </Panel>
        <Panel contentClassName="p-4 sm:p-5">
          <h3 className={`${PANEL_HEADING_CLASS} mb-4`}>Match And Training Incidence</h3>
          <ComparisonScatterChart
            rows={scatterRows}
            leagueMatchIncidence={matchBenchmark?.incidence_per_1000h}
            leagueTrainingIncidence={trainingBenchmark?.incidence_per_1000h}
            viewerColor={teamColor?.mark}
          />
        </Panel>
      </div>
    </div>
  );
}

const COMPARISON_ANIMATION_MS = 300;
const COMPARISON_EASING = 'cubic-bezier(0.22, 1, 0.36, 1)';

function ComparisonBarRow({
  row,
  rank,
  value,
  max,
  metric,
  metricLabel,
  setting,
  leagueMean,
  active,
  isViewer = false,
  viewerColor,
  viewerName,
  onHover,
  onSelect,
}: {
  row: TeamComparisonRow;
  rank: number;
  value: number;
  max: number;
  metric: ComparisonMetric;
  metricLabel: string;
  setting: ComparisonSetting;
  leagueMean?: number | null;
  active: boolean;
  isViewer?: boolean;
  viewerColor?: string;
  viewerName?: string;
  onHover: (id?: string) => void;
  onSelect: (id: string) => void;
}) {
  const metricRow = row[setting];
  const label = isViewer && viewerName ? viewerName : row.team_alias;
  const hasLeagueMean = typeof leagueMean === 'number' && Number.isFinite(leagueMean);
  const leagueMeanPosition = hasLeagueMean ? Math.min((leagueMean / max) * 100, 100) : 0;
  return (
    <button
      data-row-id={row.comparison_id}
      type="button"
      aria-label={`${label}${isViewer ? ', this team' : ''}, ${setting} ${metricLabel}: ${fmtRanked(value, metric)} ${metric === 'incidence_per_1000h' ? 'injuries per 1,000 player-hours' : 'days per 1,000 player-hours'}${hasLeagueMean ? `, league mean ${fmtRanked(leagueMean, metric)}` : ''}${metricRow ? `, ${fmt(metricRow.time_loss_injuries, 0)} injuries` : ''}`}
      onMouseEnter={() => onHover(row.comparison_id)}
      onMouseLeave={() => onHover(undefined)}
      onFocus={() => onHover(row.comparison_id)}
      onBlur={() => onHover(undefined)}
      onClick={() => onSelect(row.comparison_id)}
      className={`group grid min-h-12 w-full grid-cols-[26px_minmax(84px,140px)_minmax(80px,1fr)_76px] items-center gap-3 rounded px-2 text-left text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:min-h-14 sm:gap-4 lg:min-h-10 ${active ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
    >
      <span className="tabular-nums text-xs text-muted-foreground transition-colors duration-300 group-hover:text-foreground">{rank}</span>
      <span className="flex min-w-0 items-center gap-1.5">
        <span className="truncate font-semibold text-foreground sm:text-base">{label}</span>
      </span>
      <span className="relative h-4 rounded-full bg-muted sm:h-5">
        <span
          className={`block h-full rounded-full transition-[width,filter] ease-[cubic-bezier(0.22,1,0.36,1)] duration-300 ${isViewer && viewerColor ? '' : 'bg-primary'} ${active ? 'brightness-125' : ''}`}
          style={{ width: `${(value / max) * 100}%`, background: isViewer ? viewerColor : undefined }}
        />
        {hasLeagueMean && (
          <span
            aria-hidden="true"
            className="absolute -bottom-4 -top-4 z-10 border-l-2 border-dotted border-orange-400 sm:-bottom-[18px] sm:-top-[18px] lg:-bottom-[10px] lg:-top-[10px]"
            style={{ left: `calc(${leagueMeanPosition}% - 1px)` }}
          />
        )}
      </span>
      <span className="text-right font-semibold tabular-nums text-foreground sm:text-lg">{fmtRanked(value, metric)}</span>
    </button>
  );
}

function BenchmarkCell({ value, average, groupStart = false }: {
  value?: number | null;
  average?: number | null;
  groupStart?: boolean;
}) {
  const divider = groupStart ? 'border-l-4' : 'border-l-2';
  if (value === null || value === undefined || !Number.isFinite(value)) {
    return <td className={`${divider} border-card px-3 text-center text-xs text-muted-foreground`}>n/a</td>;
  }
  const comparable = average !== null && average !== undefined && average !== 0;
  const tone = comparable ? deltaTone((value - average) / average * 100) : '';
  return <td className={`${divider} border-card px-3 text-center font-semibold tabular-nums sm:text-lg ${tone}`}>{fmt(value)}</td>;
}

function ExposureTab({
  dashboard,
  comparisons,
  viewerComparisonId,
  teamColor,
  teamName,
}: {
  dashboard: TeamDashboardData;
  comparisons: TeamComparisonRow[];
  viewerComparisonId?: string | null;
  teamColor?: TeamColorSet;
  teamName?: string;
}) {
  type ExposureMeasure = 'hours' | 'distance';
  const [comparisonMeasure, setComparisonMeasure] = useState<ExposureMeasure>('hours');
  const coverage = dashboard.coverage;
  const monthlyRows = dashboard.monthly;
  const totalHours = coverage.hours;
  const totalDistance = coverage.distance_km;
  const totalHsr = coverage.hsr_distance_km;
  const hsrWarnings = currentExposureWarnings(coverage.data_quality_warnings ?? []);
  const options: Array<{ value: ExposureMeasure; label: string }> = [
    { value: 'hours', label: 'Hours' },
    { value: 'distance', label: 'Distance' },
  ];
  const hasExposureData = [totalHours, totalDistance].some((value) => typeof value === 'number' && Number.isFinite(value))
    || monthlyRows.some((row) => [row.exposure_hours, row.distance_km, row.hsr_distance_km].some((value) => typeof value === 'number' && Number.isFinite(value)))
    || comparisons.some((row) => [row.exposure_hours, row.distance_km, row.hsr_distance_km].some((value) => typeof value === 'number' && Number.isFinite(value)));
  const hasExposureTotals = [totalHours, totalDistance].some((value) => typeof value === 'number' && Number.isFinite(value));
  const hoursLabel = 'Total Hours';
  const distanceLabel = 'Total Distance';

  if (!hasExposureData) {
    return (
      <div className="space-y-5 sm:space-y-6">
        <SectionHeading title="Exposure" />
        <EmptyState>No approved exposure data is available for this season.</EmptyState>
      </div>
    );
  }

  return (
    <div className="space-y-5 sm:space-y-6">
      <SectionHeading title="Exposure" />
      <section aria-labelledby="total-exposure-heading">
        <h3 id="total-exposure-heading" className={`${PANEL_HEADING_CLASS} mb-3`}>Total Exposure</h3>
        {hasExposureTotals ? (
          <div className="grid overflow-hidden rounded-xl border border-border/70 bg-card/70 sm:grid-cols-3">
            <OverviewStat label={hoursLabel} value={fmtHours(totalHours)} unit="player-hours" />
            <OverviewStat label={distanceLabel} value={fmt(totalDistance)} unit="km" />
            <OverviewStat label="HSR Distance" value={fmt(totalHsr)} unit="km" />
          </div>
        ) : (
          <EmptyState>No approved exposure totals are available for this season.</EmptyState>
        )}
      </section>
      {hsrWarnings.map((warning) => (
        <div key={warning} className="rounded-lg border border-amber-400/60 bg-amber-950/30 px-4 py-3 text-sm text-amber-100" role="note">
          <span className="font-semibold">Data Quality Warning. </span>{warning}
        </div>
      ))}
      <Panel contentClassName="p-4 sm:p-5">
        <h3 className={`${PANEL_HEADING_CLASS} mb-3`}>Monthly Exposure</h3>
        <ExposureTrendChart
          rows={monthlyRows}
          totalHoursColor={teamColor?.mark}
        />
      </Panel>
      <ExposureComparison
        rows={comparisons}
        measure={comparisonMeasure}
        onMeasureChange={setComparisonMeasure}
        options={options}
        viewerComparisonId={viewerComparisonId}
        teamName={teamName}
        teamColor={teamColor}
      />
    </div>
  );
}

function ReportsTab({ model }: { model: ReportModel }) {
  const [enabledSectionIds, setEnabledSectionIds] = useState<ReportSectionId[]>([...DEFAULT_REPORT_SECTION_IDS]);
  const removeButtonRefs = useRef(new Map<ReportSectionId, HTMLButtonElement>());
  const restoreButtonRefs = useRef(new Map<ReportSectionId, HTMLButtonElement>());
  const pendingRestoredFocusRef = useRef<ReportSectionId | null>(null);
  const hiddenSectionIds = DEFAULT_REPORT_SECTION_IDS.filter((sectionId) => !enabledSectionIds.includes(sectionId));

  const removeSection = (sectionId: ReportSectionId) => {
    setEnabledSectionIds((current) => orderedReportSectionIds(current.filter((currentId) => currentId !== sectionId)));
    window.requestAnimationFrame(() => restoreButtonRefs.current.get(sectionId)?.focus());
  };

  const restoreSection = (sectionId: ReportSectionId) => {
    pendingRestoredFocusRef.current = sectionId;
    setEnabledSectionIds((current) => orderedReportSectionIds([...current, sectionId]));
  };

  const restoreAllSections = () => {
    pendingRestoredFocusRef.current = hiddenSectionIds[0] ?? null;
    setEnabledSectionIds([...DEFAULT_REPORT_SECTION_IDS]);
  };

  const focusRestoredSection = () => {
    const sectionId = pendingRestoredFocusRef.current;
    if (!sectionId) return;
    pendingRestoredFocusRef.current = null;
    window.requestAnimationFrame(() => removeButtonRefs.current.get(sectionId)?.focus());
  };

  return (
    <div className="space-y-5 sm:space-y-6">
      <div>
        <SectionHeading title="Reports" />
        <p className="-mt-4 text-sm text-muted-foreground">
          Preview and export a versioned PDF built from this dashboard&apos;s values.
        </p>
      </div>
      <ReportPreview
        model={model}
        enabledSectionIds={enabledSectionIds}
        onPreviewReady={focusRestoredSection}
        sectionControls={hiddenSectionIds.length > 0 ? (
          <div className="mb-3 flex flex-wrap items-center gap-2 rounded-lg border bg-background/70 p-2" aria-label="Restore report sections">
            <span className="px-1 text-sm text-muted-foreground">Hidden sections ({hiddenSectionIds.length})</span>
            {hiddenSectionIds.map((sectionId) => (
              <Button key={sectionId} ref={(node) => { if (node) restoreButtonRefs.current.set(sectionId, node); else restoreButtonRefs.current.delete(sectionId); }} type="button" variant="outline" size="sm" onClick={() => restoreSection(sectionId)} className="min-h-11 focus-visible:ring-2 focus-visible:ring-ring">
                Add {REPORT_SECTION_LABELS[sectionId]}
              </Button>
            ))}
            <Button type="button" variant="ghost" size="sm" onClick={restoreAllSections} className="min-h-11 focus-visible:ring-2 focus-visible:ring-ring">Restore all</Button>
          </div>
        ) : null}
        renderPageAction={({ sectionId }) => (
          <Button
            key={sectionId}
            ref={(node) => { if (node) removeButtonRefs.current.set(sectionId, node); else removeButtonRefs.current.delete(sectionId); }}
            type="button"
            variant="outline"
            size="sm"
            onClick={() => removeSection(sectionId)}
            aria-label={`Remove ${REPORT_SECTION_LABELS[sectionId]} from PDF`}
            title={`Remove ${REPORT_SECTION_LABELS[sectionId]} from PDF`}
            className="min-h-11 min-w-11 border-red-400/60 bg-red-950/90 px-2 text-red-100 shadow-sm hover:bg-red-900 hover:text-white focus-visible:ring-2 focus-visible:ring-red-400 sm:px-3"
          >
            <X className="size-4 sm:hidden" aria-hidden="true" />
            <span className="hidden sm:inline">Remove</span>
          </Button>
        )}
      />
    </div>
  );
}

function ExposureComparison({
  rows,
  measure,
  onMeasureChange,
  options,
  viewerComparisonId,
  teamColor,
  teamName,
}: {
  rows: TeamComparisonRow[];
  measure: 'hours' | 'distance';
  onMeasureChange: (measure: 'hours' | 'distance') => void;
  options: Array<{ value: 'hours' | 'distance'; label: string }>;
  viewerComparisonId?: string | null;
  teamColor?: TeamColorSet;
  teamName?: string;
}) {
  const metric = (row: typeof rows[number]) => measure === 'hours'
    ? row.exposure_hours
    : row.distance_km;
  const ranked = [...rows]
    .filter((row) => typeof metric(row) === 'number' && Number.isFinite(metric(row)))
    .sort((a, b) => (metric(b) ?? 0) - (metric(a) ?? 0));
  const leagueMean = ranked.length
    ? ranked.reduce((sum, row) => sum + (metric(row) ?? 0), 0) / ranked.length
    : 0;
  const max = Math.max(...ranked.map((row) => metric(row) ?? 0), 1);
  const leagueMeanPosition = Math.min((leagueMean / max) * 100, 100);
  const label = measure === 'hours' ? 'player-hours' : 'km';
  const measureLabel = measure === 'hours' ? 'Hours' : 'Distance';
  return (
    <Panel contentClassName="p-4 sm:p-5">
      <div className="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h3 className={PANEL_HEADING_CLASS}>Team Comparison</h3>
        <Segmented value={measure} options={options} onChange={onMeasureChange} label="Choose team comparison exposure measure" scrollable={false} />
      </div>
      {!ranked.length ? (
        <EmptyState>{measureLabel} is not available in the approved team comparison contract.</EmptyState>
      ) : (
        <div className="space-y-1" aria-label={`Team comparison by ${measureLabel.toLowerCase()}, league mean ${measure === 'hours' ? fmtHours(leagueMean) : fmt(leagueMean)} ${label}`}>
          <div className="mb-2 grid grid-cols-[minmax(72px,8rem)_minmax(0,1fr)_4.5rem] gap-3 px-2 text-[11px] font-medium uppercase tracking-wide text-muted-foreground sm:grid-cols-[minmax(100px,10rem)_minmax(0,1fr)_6rem]">
            <span>Team</span><span>Total</span><span className="text-right">{label}</span>
          </div>
          {ranked.map((row) => {
            const value = metric(row) ?? 0;
            const displayValue = measure === 'hours' ? fmtHours(value) : fmt(value);
            const width = value / max * 100;
            const isViewer = row.comparison_id === viewerComparisonId;
            return (
              <div key={row.comparison_id} className={`grid min-h-11 grid-cols-[minmax(72px,8rem)_minmax(0,1fr)_4.5rem] items-center gap-3 rounded-md px-2 text-sm hover:bg-muted/40 sm:min-h-8 sm:grid-cols-[minmax(100px,10rem)_minmax(0,1fr)_6rem] ${isViewer ? 'bg-muted/40' : ''}`}>
                <span className="flex min-w-0 items-center gap-1.5">
                  <span className="truncate font-medium text-foreground">{isViewer && teamName ? teamName : row.team_alias}</span>
                  {row.included_exposure_status.includes('estimate') && (
                    <span className="shrink-0 rounded bg-amber-100 px-1 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-900 dark:bg-amber-950 dark:text-amber-100">Est.</span>
                  )}
                </span>
                <span className="relative h-3 rounded-sm bg-muted" aria-hidden="true">
                  <span
                    className={`block h-full rounded-sm ${isViewer && teamColor ? '' : 'bg-primary'}`}
                    style={{ width: `${width}%`, background: isViewer ? teamColor?.mark : undefined }}
                  />
                  <span
                    aria-hidden="true"
                    className="absolute -bottom-4 -top-4 z-10 border-l-2 border-dotted border-orange-400 sm:-bottom-[10px] sm:-top-[10px]"
                    style={{ left: `calc(${leagueMeanPosition}% - 1px)` }}
                  />
                </span>
                <span className="text-right font-semibold tabular-nums text-foreground">{displayValue}</span>
              </div>
            );
          })}
          <div className="mt-4 flex justify-end border-t border-border/60 pt-3" aria-label="Chart legend">
            <span className="inline-flex items-center gap-2 rounded-md bg-muted/50 px-3 py-2 text-xs text-muted-foreground">
              <i aria-hidden="true" className="h-4 border-l-2 border-dotted border-orange-400" />
              <strong className="font-semibold text-foreground">League Mean</strong>
            </span>
          </div>
        </div>
      )}
    </Panel>
  );
}

function LocationTab({ profiles }: { profiles: InjuryProfileRow[] }) {
  const locationProfiles = profiles.filter((row) => row.dimension === 'body_location');
  const settings = availableSettings(locationProfiles, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const [metric, setMetric] = useState<ProfileMetric>('time_loss_injuries');
  const [selectedCode, setSelectedCode] = useState<string>();
  const [hoveredCode, setHoveredCode] = useState<string>();
  const effectiveSetting = settings.includes(setting) ? setting : settings[0] ?? 'all';
  const { rows, barRows, activeCode, selected } = resolveLocationView({
    profiles: locationProfiles,
    setting: effectiveSetting,
    metric: metric as LocationMetric,
    selectedCode,
    hoveredCode,
  });

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h2 className={SECTION_HEADING_CLASS}>Injury Location</h2>
        <div className="flex w-full flex-col items-start gap-2 sm:w-auto sm:flex-row sm:flex-wrap sm:justify-end">
          <SettingControl value={effectiveSetting} settings={settings.length ? settings : ['all', 'match', 'training']} onChange={setSetting} />
          <MetricControl value={metric} onChange={setMetric} locationOnly />
        </div>
      </div>
      {rows.length ? (
        <div className="space-y-4">
          <div className="grid gap-4 lg:grid-cols-2">
            <Panel contentClassName="p-4">
              <MetricBars
                rows={barRows}
                metric={metric}
                activeCode={activeCode}
                onHover={setHoveredCode}
                onSelect={setSelectedCode}
                heatMapColors
              />
            </Panel>
            <Panel contentClassName="p-4">
              <div className="xl:grid xl:grid-cols-[minmax(0,1fr)_10rem] xl:items-stretch xl:gap-4">
                <BodyMap
                  rows={rows}
                  metric={metric as LocationMetric}
                  activeCode={activeCode}
                  onHover={setHoveredCode}
                  onSelect={setSelectedCode}
                />
                <LocationDetail row={selected} metric={metric} />
              </div>
            </Panel>
          </div>
          <SettingSplitBars
            profiles={locationProfiles}
            title="Match Vs Training By Region"
            emptyMessage="No body region has both a match and a training row."
          />
        </div>
      ) : <EmptyState />}
    </div>
  );
}

/**
 * Match against training per category, read from the released per-setting rows
 * (body regions on the location tab, injury type families on the types tab). It
 * shows both settings at once, so the tab's setting control does not apply to
 * it. Counts are the default because match and training rates rest on different
 * exposure denominators.
 */
function SettingSplitBars({ profiles, title, emptyMessage }: {
  profiles: ProfileMetricRow[];
  title: string;
  emptyMessage: string;
}) {
  const [metric, setMetric] = useState<ProfileMetric>('time_loss_injuries');
  const match = new Map(profiles.filter((row) => row.setting === 'match').map((row) => [row.code, row]));
  const training = new Map(profiles.filter((row) => row.setting === 'training').map((row) => [row.code, row]));
  const rows = [...new Set([...match.keys(), ...training.keys()])]
    .map((code) => {
      const matchRow = match.get(code);
      const trainingRow = training.get(code);
      return {
        code,
        label: matchRow?.label ?? trainingRow?.label ?? code,
        match: matchRow ? metricValue(matchRow, metric) : 0,
        training: trainingRow ? metricValue(trainingRow, metric) : 0,
      };
    })
    .filter((row) => row.match > 0 || row.training > 0)
    .sort((a, b) => Math.max(b.match, b.training) - Math.max(a.match, a.training)
      || a.label.localeCompare(b.label));
  const max = Math.max(...rows.map((row) => Math.max(row.match, row.training)), 0);
  const meta = metricMeta(metric);
  const barWidth = (value: number) => `${max > 0 ? Math.max((value / max) * 100, value > 0 ? 2 : 0) : 0}%`;

  return (
    <Panel contentClassName="p-4 sm:p-5">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <h3 className={`${PANEL_HEADING_CLASS} capitalize`}>{title}</h3>
          <ScopeChip show label="Match & Training" />
        </div>
        <MetricControl value={metric} onChange={setMetric} locationOnly />
      </div>
      {rows.length ? (
        <>
          <div className="overflow-x-auto">
            <div className="min-w-[300px]">
              <div className="mb-2 grid grid-cols-[2rem_minmax(0,1fr)_7rem_minmax(0,1fr)_2rem] sm:grid-cols-[2.5rem_minmax(0,1fr)_7.5rem_minmax(0,1fr)_2.5rem] items-center gap-2 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                <span />
                <span className="flex items-center justify-start gap-1.5">
                  <i className="h-2 w-2 shrink-0 rounded-full" style={{ background: SETTING_COLORS.match }} aria-hidden="true" />
                  Match, {meta.longUnit}
                </span>
                <span />
                <span className="flex items-center justify-end gap-1.5">
                  Training, {meta.longUnit}
                  <i className="h-2 w-2 shrink-0 rounded-full" style={{ background: SETTING_COLORS.training }} aria-hidden="true" />
                </span>
                <span />
              </div>
              <ul className="space-y-1">
                {rows.map((row) => (
                  <li
                    key={row.code}
                    className="grid min-h-8 grid-cols-[2rem_minmax(0,1fr)_7rem_minmax(0,1fr)_2rem] sm:grid-cols-[2.5rem_minmax(0,1fr)_7.5rem_minmax(0,1fr)_2.5rem] items-center gap-2 rounded px-0.5 hover:bg-muted/40"
                  >
                    <span className="text-left text-[11px] tabular-nums text-muted-foreground">
                      <span className="sr-only">{row.label} match </span>
                      {fmtRanked(row.match, metric)}
                    </span>
                    <span className="flex h-3 justify-end overflow-hidden rounded-sm bg-muted/60">
                      <span className="block h-full rounded-sm" style={{ width: barWidth(row.match), background: SETTING_COLORS.match }} />
                    </span>
                    <span className="truncate text-center text-xs text-foreground">{row.label}</span>
                    <span className="flex h-3 justify-start overflow-hidden rounded-sm bg-muted/60">
                      <span className="block h-full rounded-sm" style={{ width: barWidth(row.training), background: SETTING_COLORS.training }} />
                    </span>
                    <span className="text-right text-[11px] tabular-nums text-muted-foreground">
                      <span className="sr-only">training </span>
                      {fmtRanked(row.training, metric)}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
          {/* Kept for the rate metrics only: a methodological caveat, not an instruction. */}
          {metric !== 'time_loss_injuries' && (
            <p className="mt-3 text-xs text-muted-foreground">
              Match and training rates rest on different exposure denominators.
            </p>
          )}
        </>
      ) : <EmptyState>{emptyMessage}</EmptyState>}
    </Panel>
  );
}

function LocationDetail({ row, metric }: { row?: InjuryProfileRow; metric: ProfileMetric }) {
  return (
    <div className="mt-3 overflow-hidden rounded-md border border-border/70 bg-background/35 xl:mt-0 xl:flex xl:flex-col">
      <div className="flex items-baseline justify-between gap-3 px-4 py-3 xl:block xl:py-4">
        <p className="text-xs font-medium text-muted-foreground">Selected Location</p>
        <p className="truncate text-base font-semibold text-foreground xl:mt-1 xl:text-lg">{row?.label ?? 'Not available'}</p>
      </div>
      <div className="grid grid-cols-3 border-t border-border/60 xl:flex xl:flex-1 xl:flex-col">
        <LocationMetricValue label="Injuries" value={fmt(row?.time_loss_injuries, 0)} active={metric === 'time_loss_injuries'} />
        <LocationMetricValue label="Incidence" value={fmtRanked(row?.incidence_per_1000h, 'incidence_per_1000h')} unit="/1,000 h" active={metric === 'incidence_per_1000h'} />
        <LocationMetricValue label="Burden" value={fmtRanked(row?.burden_per_1000h, 'burden_per_1000h')} unit="days /1,000 h" active={metric === 'burden_per_1000h'} />
      </div>
    </div>
  );
}

function LocationMetricValue({ label, value, unit, active }: { label: string; value: string; unit?: string; active: boolean }) {
  return (
    <div className={`min-w-0 border-r border-border/50 px-3 py-3 last:border-r-0 sm:px-4 xl:flex xl:flex-1 xl:flex-col xl:justify-center xl:border-r-0 xl:border-b xl:px-4 xl:last:border-b-0 ${active ? 'xl:border-l-2 xl:border-l-primary xl:bg-primary/[0.04]' : 'xl:border-l-2 xl:border-l-transparent'}`}>
      <p className="text-[11px] text-muted-foreground">{label}</p>
      <p className="mt-1 truncate text-lg font-semibold tabular-nums text-foreground">{value}</p>
      {unit && <p className="truncate text-[10px] text-muted-foreground">{unit}</p>}
    </div>
  );
}

function MetricBars({ rows, metric, activeCode, onHover, onSelect, heatMapColors = false, showSummary = true }: {
  rows: ProfileMetricRow[];
  metric: ProfileMetric;
  activeCode?: string;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
  heatMapColors?: boolean;
  showSummary?: boolean;
}) {
  const max = Math.max(...rows.map((row) => rankedBarValue(metricValue(row, metric), metric)), 1);
  const meta = metricMeta(metric);
  const tooltipId = useId();
  const activeRow = rows.find((row) => row.code === activeCode) ?? rows[0];
  return (
    <div className={heatMapColors ? 'space-y-0' : 'space-y-1'}>
      <div id={tooltipId} aria-live="polite" className={heatMapColors || !showSummary ? 'sr-only' : 'mb-4 rounded-md border border-border bg-background/60 px-4 py-3 text-sm leading-relaxed text-popover-foreground'}>
        {activeRow ? (
          <>
            <span className="font-semibold text-foreground">{activeRow.label}</span>
            <span className="mx-1 text-muted-foreground">:</span>
            <span className="font-medium tabular-nums text-foreground">{fmtRanked(activeRow[metric], metric)} {meta.longUnit}</span>
            <span className="block mt-0.5 text-muted-foreground">n = {fmt(activeRow.time_loss_injuries, 0)} injuries.</span>
          </>
        ) : 'No injury type selected.'}
      </div>
      {rows.map((row) => {
        const value = rankedBarValue(metricValue(row, metric), metric);
        const active = activeCode === row.code;
        return (
          <button
            key={row.code}
            type="button"
            aria-describedby={tooltipId}
            aria-label={`${row.label}: ${fmtRanked(row[metric], metric)} ${meta.longUnit}. ${row.setting === 'all' ? 'All settings' : row.setting} cohort; n = ${fmt(row.time_loss_injuries, 0)} injuries.`}
            onMouseEnter={() => onHover(row.code)}
            onMouseLeave={() => onHover()}
            onFocus={() => onHover(row.code)}
            onBlur={() => onHover()}
            onClick={() => onSelect(row.code)}
            className="group grid min-h-11 w-full grid-cols-[minmax(92px,0.42fr)_minmax(84px,1fr)_auto] items-center gap-3 rounded px-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <span className={`truncate text-sm ${active ? 'font-semibold text-foreground' : 'text-muted-foreground'}`}>{row.label}</span>
            <span className="h-3 overflow-hidden rounded-full bg-background/70">
              <span
                className={`block h-full rounded-full ${heatMapColors ? '' : 'bg-primary'}`}
                style={{
                  width: `${Math.max((value / max) * 100, value > 0 ? 2 : 0)}%`,
                  backgroundColor: heatMapColors ? locationHeatColor(value, max) : undefined,
                  opacity: active ? 1 : activeCode ? 0.25 : heatMapColors ? 1 : 0.75,
                }}
              />
            </span>
            <span className="min-w-16 text-right text-base font-semibold tabular-nums text-foreground">{fmtRanked(row[metric], metric)}</span>
          </button>
        );
      })}
    </div>
  );
}

function InjuryTypesTab({ families }: { families: InjuryTypeFamilyRow[] }) {
  const classifiedFamilies = families.filter((row) => (
    row.code !== 'other_unclassified'
    && row.code !== 'unmapped_review'
  ));
  const settings = availableSettings(classifiedFamilies, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const [metric, setMetric] = useState<ProfileMetric>('time_loss_injuries');
  const [selectedCode, setSelectedCode] = useState<string>();
  const [hoveredCode, setHoveredCode] = useState<string>();
  const effectiveSetting = settings.includes(setting) ? setting : settings[0] ?? 'all';
  const rows = classifiedFamilies
    .filter((row) => row.setting === effectiveSetting && row.time_loss_injuries > 0)
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label));
  const pinnedCode = rows.some((row) => row.code === selectedCode)
    ? selectedCode
    : rows[0]?.code;
  const activeCode = rows.some((row) => row.code === hoveredCode)
    ? hoveredCode
    : pinnedCode;
  const activeRow = rows.find((row) => row.code === activeCode);
  const activeRank = activeRow ? rows.findIndex((row) => row.code === activeRow.code) + 1 : undefined;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h2 className={SECTION_HEADING_CLASS}>Injury Types</h2>
        <div className="flex w-full flex-col items-start gap-2 sm:w-auto sm:flex-row sm:flex-wrap sm:justify-end">
          <SettingControl value={effectiveSetting} settings={settings.length ? settings : ['all']} onChange={setSetting} />
          <MetricControl value={metric} onChange={setMetric} locationOnly />
        </div>
      </div>
      {rows.length ? (
        <div className="space-y-4">
          <div className="grid gap-4 lg:grid-cols-[minmax(0,1.2fr)_minmax(20rem,0.8fr)]">
            <Panel contentClassName="p-4">
              <InjuryTypeRanking
                rows={rows}
                metric={metric as InjuryTypeMetric}
                activeCode={activeCode}
                selectedCode={pinnedCode}
                onHover={setHoveredCode}
                onSelect={setSelectedCode}
              />
            </Panel>
            <Panel contentClassName="p-4">
              <InjuryTypeDossier
                row={activeRow}
                metric={metric as InjuryTypeMetric}
                rank={activeRank}
                total={rows.length}
              />
            </Panel>
          </div>
          <SettingSplitBars
            profiles={classifiedFamilies}
            title="Match Vs Training By Injury Type"
            emptyMessage="No injury type has both a match and a training row."
          />
        </div>
      ) : <EmptyState />}
    </div>
  );
}

function availableSettings(rows: Array<{ setting: Setting }>, preference: Setting[]) {
  const available = new Set(rows.map((row) => row.setting));
  return preference.filter((setting) => available.has(setting));
}

export function TeamDashboard({
  dashboard,
  crest,
  teamName,
  comparisons = [],
  leagueMetrics = [],
  supplement,
  seasonComparison,
  viewerComparisonId = null,
  teamColor,
  season,
  seasonPath,
  reportModel,
}: {
  dashboard: TeamDashboardData;
  crest: string;
  teamName: string;
  comparisons?: TeamComparisonRow[];
  leagueMetrics?: SettingMetricRow[];
  supplement?: DashboardSupplement;
  seasonComparison?: SeasonComparisonData;
  /** The viewing team's own comparison row, resolved server-side (§1.0). */
  viewerComparisonId?: string | null;
  /**
   * Resolved club identity colours. Absent on the league page, where every
   * accent-coloured mark falls back to the --primary brand cyan.
   */
  teamColor?: TeamColorSet;
  /** Selected supported season, resolved by the route before reporting loads. */
  season: DashboardSeason;
  /** Current league or team route, retained when a reader changes season. */
  seasonPath: string;
  reportModel: ReportModel;
}) {
  const searchParams = useSearchParams();
  const activeTab = resolveDashboardTab(searchParams.get('tab'));
  const selectTab = (value: string) => {
    const nextTab = resolveDashboardTab(value);
    const url = new URL(window.location.href);
    if (nextTab === DEFAULT_DASHBOARD_TAB) url.searchParams.delete('tab');
    else url.searchParams.set('tab', nextTab);
    window.history.replaceState(null, '', url);
  };
  const approvedProfiles = dashboard.injury_profiles ?? [];
  const profiles = withoutFrontFacingUnknown(supplement
    ? [
        ...approvedProfiles.filter((row) => !['body_location', 'injury_type'].includes(row.dimension)),
        ...supplement.body_locations,
        ...supplement.injury_types,
      ]
    : approvedProfiles);
  const injuryTypeFamilies = withoutFrontFacingUnknown(dashboard.injury_type_families).map((family) => ({
    ...family,
    subtypes: withoutFrontFacingUnknown(family.subtypes),
  }));
  const usesExposureEstimate = dashboard.coverage.included_exposure_status.includes('estimate');
  const exposureEstimateNote = dashboard.limitations.find((item) => (
    /temporary/i.test(item) && /estimate/i.test(item)
  )) ?? 'Rates use a temporary league-mean season exposure estimate. Monthly exposure and distance are unavailable for estimated teams.';

  return (
    <div className="mx-auto w-full max-w-7xl overflow-x-clip px-4 pb-16 pt-6 sm:px-6 lg:px-8">
      <Link href="/" className="mb-4 inline-flex min-h-11 items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
        <ArrowLeft className="h-4 w-4" />
        Back to dashboards
      </Link>

      <header className="mb-6 flex items-center gap-4">
        <div className="relative h-14 w-14 shrink-0 sm:h-16 sm:w-16">
          <Image src={crest} alt={`${teamName} crest`} fill sizes="64px" className="object-contain" />
        </div>
        <div className="min-w-0">
          <h1
            className="text-2xl font-bold leading-tight text-foreground capitalize sm:text-3xl"
            style={teamColor && teamColor.source !== 'achromatic' ? { color: teamColor.text } : undefined}
          >
            {teamName}
          </h1>
          <SeasonSelector season={season} seasonPath={seasonPath} activeTab={activeTab} />
        </div>
      </header>

      {usesExposureEstimate && (
        <div
          className="mb-6 rounded-xl border border-amber-400/50 bg-amber-50 px-4 py-3 text-sm text-amber-950 dark:bg-amber-950/30 dark:text-amber-100"
          role="note"
          aria-label="Temporary Exposure Estimate"
        >
          <p>{exposureEstimateNote}</p>
        </div>
      )}

      <Tabs value={activeTab} onValueChange={selectTab}>
        <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
          <TabsList aria-label="Dashboard sections" className="mb-3 h-auto min-w-max justify-start bg-muted/80 p-1">
            {DASHBOARD_TABS.map((tab) => (
              <TabsTrigger key={tab.value} value={tab.value} className="min-h-11 px-4">
                {tab.label}
              </TabsTrigger>
            ))}
          </TabsList>
        </div>

        <TabsContent value="overview"><OverviewTab dashboard={dashboard} profiles={profiles} supplement={supplement} /></TabsContent>
        <TabsContent value="comparison">
          <TeamComparisonTab
            rows={comparisons}
            leagueMetrics={leagueMetrics}
            teamName={teamName}
            viewerComparisonId={viewerComparisonId}
            teamColor={teamColor}
          />
        </TabsContent>
        <TabsContent value="common"><CommonInjuriesTab dashboard={dashboard} profiles={profiles} supplement={supplement} /></TabsContent>
        <TabsContent value="illnesses"><IllnessesTab dashboard={dashboard} /></TabsContent>
        <TabsContent value="location"><LocationTab profiles={profiles} /></TabsContent>
        <TabsContent value="types"><InjuryTypesTab families={injuryTypeFamilies} /></TabsContent>
        <TabsContent value="exposure">
          <ExposureTab
            dashboard={dashboard}
            comparisons={comparisons}
            viewerComparisonId={viewerComparisonId}
            teamColor={teamColor}
            teamName={teamName}
          />
        </TabsContent>
        <TabsContent value="season-comparison">
          <SeasonComparison comparison={seasonComparison} />
        </TabsContent>
        <TabsContent value="reports"><ReportsTab key={`${reportModel.scope}:${reportModel.subjectName}:${reportModel.season}:${reportModel.exportedAt}`} model={reportModel} /></TabsContent>
      </Tabs>
    </div>
  );
}
