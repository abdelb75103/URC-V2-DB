'use client';

import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import type {
  DashboardSupplement,
  ExposureReviewPreview,
  InjuryProfileRow,
  InjuryTypeFamilyRow,
  SettingMetricRow,
  TeamDashboardData,
  TeamComparisonRow,
} from '@/lib/reporting-types';
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
  ComparisonScatterChart,
  ExposureTrendChart,
  ImpactBubbleChart,
  SETTING_COLORS,
  SEVERITY_BAND_COLORS,
  SeasonTimelineChart,
  SeverityArc,
  Sparkline,
  sortSeasonMonths,
  profileColor,
  type ComparisonScatterRow,
} from '@/components/dashboard/charts';
import type { TeamColorSet } from '@/lib/team-color';
import { SUPPORTED_DASHBOARD_SEASONS, type DashboardSeason } from '@/lib/dashboard-season';

type ProfileMetric =
  | 'time_loss_injuries'
  | 'incidence_per_1000h'
  | 'burden_per_1000h'
  | 'mean_severity_days';
type Setting = InjuryProfileRow['setting'];

const TABS = [
  ['overview', 'Overview'],
  ['comparison', 'Team Comparison'],
  ['exposure', 'Exposure'],
  ['common', 'Common Injuries'],
  ['location', 'Injury Location'],
  ['types', 'Injury Types'],
] as const;

const METRICS: Array<{ key: ProfileMetric; label: string; shortUnit: string; longUnit: string }> = [
  { key: 'time_loss_injuries', label: 'Count', shortUnit: 'injuries', longUnit: 'time-loss injuries' },
  { key: 'incidence_per_1000h', label: 'Incidence', shortUnit: '/1,000 h', longUnit: 'injuries /1,000 h' },
  { key: 'burden_per_1000h', label: 'Burden', shortUnit: 'days/1,000 h', longUnit: 'days /1,000 h' },
  { key: 'mean_severity_days', label: 'Severity', shortUnit: 'days', longUnit: 'days' },
];

type InjuryCardColor = { background: string; foreground: string };

const REFERENCE_INJURY_COLORS: Record<string, InjuryCardColor> = {
  concussion: { background: '#e5252a', foreground: '#ffffff' },
  contusion_haematoma: { background: '#f59e0b', foreground: '#ffffff' },
  compound__thigh__contusion_superficial: { background: '#f59e0b', foreground: '#ffffff' },
  compound__knee__joint_sprain: { background: '#3b82f6', foreground: '#ffffff' },
  hamstring_strain: { background: '#9333ea', foreground: '#ffffff' },
  compound__thigh__muscle_injury: { background: '#9333ea', foreground: '#ffffff' },
  compound__ankle__joint_sprain: { background: '#16a34a', foreground: '#ffffff' },
  adductor_groin: { background: '#db2777', foreground: '#ffffff' },
  compound__knee__peripheral_nerve_injury: { background: '#db2777', foreground: '#ffffff' },
  calf_muscle: { background: '#f97316', foreground: '#ffffff' },
  compound__lower_leg__muscle_injury: { background: '#f97316', foreground: '#ffffff' },
  compound__shoulder__joint_sprain: { background: '#14b8a6', foreground: '#ffffff' },
  compound__shoulder__tendon_rupture: { background: '#06b6d4', foreground: '#ffffff' },
  compound__ankle__fracture: { background: '#0d9488', foreground: '#ffffff' },
  compound__lower_leg__fracture: { background: '#4f46e5', foreground: '#ffffff' },
  compound__wrist__fracture: { background: '#0ea5e9', foreground: '#ffffff' },
  compound__wrist__tendinopathy: { background: '#14b8a6', foreground: '#ffffff' },
  compound__shoulder__fracture: { background: '#eab308', foreground: '#ffffff' },
  compound__lumbosacral__synovitis_capsulitis: { background: '#65a30d', foreground: '#ffffff' },
  compound__lumbosacral__cartilage_injury: { background: '#84cc16', foreground: '#ffffff' },
  compound__lumbosacral__tendinopathy: { background: '#eab308', foreground: '#ffffff' },
  compound__lumbosacral__nonspecific: { background: '#c026d3', foreground: '#ffffff' },
  compound__forearm__fracture: { background: '#1e40af', foreground: '#ffffff' },
};

const FALLBACK_INJURY_COLORS = [
  '#007d92',
  '#6d28d9',
  '#b56000',
  '#00759a',
  '#007a55',
  '#c94b00',
  '#4f46e5',
  '#007a78',
  '#c51b4a',
  '#075fc7',
  '#966b00',
  '#08783f',
  '#1e40af',
  '#7e22ce',
  '#be123c',
  '#007f6d',
  '#0369a1',
  '#5b21b6',
  '#b45309',
  '#0f766e',
  '#4338ca',
  '#0e7490',
  '#15803d',
  '#9f1239',
] as const;

const CONTACT_RING_COLORS: Record<string, string> = {
  contact: '#a78bfa',
  non_contact: '#fb923c',
  // Contact mechanism keeps its unclassified share visible (request, 2026-07-26):
  // the reader needs to know how much of the split is not evidenced.
  unknown: '#94a3b8',
};

function fmt(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: digits,
    minimumFractionDigits: Number.isInteger(value) ? 0 : digits,
  }).format(value);
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
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: digits,
    minimumFractionDigits: digits,
  }).format(value);
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
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
  }).format(value);
}

function addPreviewToKnownValue(
  value: number | null | undefined,
  previewValue: number | undefined,
) {
  if (value === null || value === undefined) return null;
  return value + (previewValue ?? 0);
}

function hasKnownExposure(
  row: TeamComparisonRow,
): row is TeamComparisonRow & { exposure_hours: number } {
  return typeof row.exposure_hours === 'number' && Number.isFinite(row.exposure_hours);
}

type ProfileMetricRow = InjuryProfileRow | InjuryTypeFamilyRow;

function metricValue(row: ProfileMetricRow, metric: ProfileMetric) {
  const value = row[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

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
            <h3 className="text-lg font-semibold text-foreground">{title}</h3>
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
      <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">{title}</h2>
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

function SeasonSelector({ season, seasonPath }: { season: DashboardSeason; seasonPath: string }) {
  return (
    <nav aria-label="Choose season" className="mt-3 inline-flex rounded-md border border-border bg-background/50 p-1">
      {SUPPORTED_DASHBOARD_SEASONS.map((option) => (
        <Link
          key={option}
          href={`${seasonPath}?season=${option}`}
          aria-current={season === option ? 'page' : undefined}
          className={`min-h-11 rounded px-3 py-2 text-sm font-medium transition-[background-color,color] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${season === option ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground'}`}
        >
          {option}
        </Link>
      ))}
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
  supplement?: DashboardSupplement,
): InjuryProfileRow[] {
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
  const [showCases, setShowCases] = useState(true);
  const [showIncidence, setShowIncidence] = useState(true);
  const [locationMetric, setLocationMetric] = useState<LocationMetric>('incidence_per_1000h');
  const [benchMetric, setBenchMetric] = useState<ProfileMetric>('incidence_per_1000h');
  const [includeZeroDay, setIncludeZeroDay] = useState(true);
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
  const perSettingSeverity = Boolean(supplement);
  const filtered = effectiveSetting !== 'all';

  const recorded = supplement?.descriptive_consequence_summary.recorded_injuries
    ?? headline.recorded_injuries
    ?? dashboard.severity_distribution.reduce((sum, row) => sum + row.recorded_injuries, 0);

  const monthlyRows = supplement
    ? supplement.monthly_by_setting.filter((row) => row.setting === effectiveSetting)
    : dashboard.monthly.map((row) => ({
        month: row.month ?? '',
        setting: 'all' as const,
        recorded_injuries: row.recorded_injuries,
        time_loss_injuries: row.time_loss_injuries,
        rate_time_loss_injuries: row.time_loss_injuries,
        exposure_hours: row.exposure_hours ?? null,
        incidence_per_1000h: row.incidence_per_1000h ?? null,
      }));
  // Every monthly chart plots from September and says how many pre-window months
  // it dropped (handled inside the chart components). The KPI sparklines and every
  // headline total stay on the full set, so the tiles keep reconciling.
  const trend = sortByMonth(monthlyRows);
  // The burden tile's own series. Monthly burden is a released value on the
  // approved monthly rows but is not carried per setting, so this one series is
  // always the overall season shape.
  const burdenTrend = sortByMonth(
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

  const severitySource = supplement
    ? supplement.severity_distribution.filter((row) => row.setting === effectiveSetting)
    : dashboard.severity_distribution;
  const severityRows = [
    { key: 'zero', label: '0 days (medical attention)', value: severitySource.find((row) => row.key === 'zero_days_medical_attention_only')?.recorded_injuries ?? 0 },
    { key: 'one_to_seven', label: '1-7 days', value: severitySource.filter((row) => ['one_day', 'two_to_three_days', 'four_to_seven_days'].includes(row.key)).reduce((sum, row) => sum + row.recorded_injuries, 0) },
    { key: 'eight_to_twenty_eight', label: '8-28 days', value: severitySource.find((row) => row.key === 'eight_to_twenty_eight_days')?.recorded_injuries ?? 0 },
    { key: 'greater_than_twenty_eight', label: 'Over 28 days', value: severitySource.find((row) => row.key === 'greater_than_twenty_eight_days')?.recorded_injuries ?? 0 },
  ]
    .filter((row) => includeZeroDay || row.key !== 'zero')
    .map((row) => ({ ...row, color: SEVERITY_BAND_COLORS[row.key] }));

  // Unlike the other breakdowns this one keeps its Unknown slice, so the ring
  // reads as a share of all cases rather than of the classified ones only.
  const contactOrder = ['contact', 'non_contact', 'unknown'];
  const contactRows = (dashboard.contact_distribution ?? supplement?.contact_distribution ?? [])
    .filter((row) => row.setting === effectiveSetting)
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
        <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">
          {dashboard.scope === 'league' ? 'League injury picture' : 'Team injury picture'}
        </h2>
        {settingFilterAvailable && (
          <SettingControl value={effectiveSetting} settings={settingOptions} onChange={setSetting} />
        )}
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatTile
          label={filtered ? 'Time-loss cases' : supplement ? 'Attributed records' : 'Recorded cases'}
          value={filtered ? fmt(active?.time_loss_injuries, 0) : fmt(recorded, 0)}
          unit="cases"
        >
          <Sparkline values={trend.map((row) => row.recorded_injuries ?? row.time_loss_injuries)} ariaLabel="Cases by month" />
        </StatTile>
        <StatTile
          label="Incidence"
          value={fmt(active?.incidence_per_1000h ?? (filtered ? null : headline.incidence_per_1000h))}
          unit="injuries /1,000 h"
        >
          <Sparkline values={trend.map((row) => row.incidence_per_1000h)} color="#ffc45c" ariaLabel="Incidence by month" />
        </StatTile>
        <StatTile
          label="Burden"
          value={fmt(active?.burden_per_1000h ?? (filtered ? null : headline.burden_per_1000h))}
          unit="days /1,000 h"
        >
          <Sparkline values={burdenTrend} color="#ef7189" ariaLabel="Burden by month" />
        </StatTile>
        <StatTile
          label="Exposure"
          value={fmtHours(filtered ? active?.exposure_hours : dashboard.coverage.hours)}
          unit="player-hours"
        >
          <Sparkline values={trend.map((row) => row.exposure_hours)} color="#42d8b4" ariaLabel="Exposure hours by month" />
        </StatTile>
      </div>

      <Panel contentClassName="p-4 sm:p-5">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <h3 className="text-lg font-semibold text-foreground">Season timeline</h3>
            <ScopeChip show={effectiveSetting !== 'all' && !perSettingMonthly} />
          </div>
          <div className="flex flex-wrap gap-4">
            <CheckToggle checked={showCases} onChange={setShowCases} label="Cases" swatch={SETTING_COLORS.all} />
            <CheckToggle checked={showIncidence} onChange={setShowIncidence} label="Incidence" swatch="#ffc45c" />
          </div>
        </div>
        <div className="overflow-x-auto">
          <SeasonTimelineChart rows={monthlyRows} showCases={showCases} showIncidence={showIncidence} />
        </div>
      </Panel>

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]">
        <Panel contentClassName="p-4 sm:p-5">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <h3 className="text-lg font-semibold text-foreground">Injury Location</h3>
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
                <p className="mb-2 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">Top locations</p>
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
                    {fmt(selected.time_loss_injuries, 0)} time-loss injuries, {fmt(selected.mean_severity_days)} mean days lost
                  </p>
                )}
              </div>
            </div>
          ) : <EmptyState />}
        </Panel>

        <Panel contentClassName="p-4 sm:p-5">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <h3 className="text-lg font-semibold text-foreground">Severity</h3>
              <ScopeChip show={effectiveSetting !== 'all' && !perSettingSeverity} />
            </div>
            <CheckToggle checked={includeZeroDay} onChange={setIncludeZeroDay} label="Include 0-day" />
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
            <h3 className="mb-3 text-lg font-semibold text-foreground">Contact mechanism</h3>
            <SeverityArc rows={contactRows} scaleLabels={null} ariaLabel="Contact mechanism breakdown" />
          </Panel>
        )}
        <Panel contentClassName="p-4 sm:p-5">
          <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
            <h3 className="text-lg font-semibold text-foreground">Match vs training</h3>
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

function StatTile({ label, value, unit, children }: {
  label: string;
  value: string;
  unit?: string;
  children?: ReactNode;
}) {
  return (
    <Card className="min-w-0 border-border/70 bg-card/70 shadow-none">
      <CardContent className="p-4 sm:p-5">
        <p className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">{label}</p>
        <p className="mt-2 text-3xl font-bold leading-none tracking-tight tabular-nums text-foreground sm:text-4xl">{value}</p>
        {unit && <p className="mt-1.5 text-[11px] text-muted-foreground">{unit}</p>}
        {children && <div className="mt-3">{children}</div>}
      </CardContent>
    </Card>
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

function CheckToggle({ checked, onChange, label, swatch }: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  swatch?: string;
}) {
  return (
    <label className="inline-flex min-h-11 cursor-pointer select-none items-center gap-2 text-xs font-medium text-muted-foreground">
      <input
        type="checkbox"
        checked={checked}
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
        <BenchFoot label="Match cases" value={fmt(match?.time_loss_injuries, 0)} />
        <BenchFoot label="Training cases" value={fmt(training?.time_loss_injuries, 0)} />
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

function CompactRanking({ rows }: { rows: InjuryProfileRow[] }) {
  if (!rows.length) return <EmptyState />;
  const max = Math.max(...rows.map((row) => row.time_loss_injuries), 1);
  return (
    <ol className="space-y-3">
      {rows.map((row) => (
        <li key={row.code} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3">
          <div className="min-w-0">
            <div className="mb-1 flex justify-between gap-3 text-sm">
              <span className="truncate text-foreground">{row.label}</span>
              <span className="sr-only">{row.time_loss_injuries} injuries</span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-muted">
              <div className="h-full rounded-full bg-primary" style={{ width: `${(row.time_loss_injuries / max) * 100}%` }} />
            </div>
          </div>
          <span className="min-w-8 text-right text-sm font-semibold tabular-nums text-foreground" aria-hidden="true">{row.time_loss_injuries}</span>
        </li>
      ))}
    </ol>
  );
}

function CommonInjuriesTab({ dashboard, profiles, supplement }: {
  dashboard: TeamDashboardData;
  profiles: InjuryProfileRow[];
  supplement?: DashboardSupplement;
}) {
  const [impactDimension, setImpactDimension] = useState<'diagnosis' | 'location' | 'type'>('diagnosis');
  const source = reportingDiagnosisRows(profiles, supplement);
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
  // The chart draws the highest-burden slice but splits its quadrants on the whole
  // cohort, so both are passed rather than the slice alone.
  const impactCohort = impactSource.filter((row) => row.setting === setting);
  const impactRows = [...impactCohort]
    .sort((a, b) => (b.burden_per_1000h ?? 0) - (a.burden_per_1000h ?? 0))
    .slice(0, 12);

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4 border-b border-border/60 pb-4">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">Most Common {settingTitle}Injuries</h2>
        </div>
        <SettingControl value={setting} settings={settings.length ? settings : ['all', 'match', 'training']} onChange={setSetting} />
      </div>
      {rows.length ? (
        <>
          <CommonInjuryRankings rows={rows} totalInjuries={totalInjuries} injuryColors={injuryColors} />
          <section aria-labelledby="common-injuries-impact" className="mt-8">
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
              <h3 id="common-injuries-impact" className="text-lg font-semibold text-foreground">Injury Impact</h3>
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
              <ImpactBubbleChart rows={impactRows} cohort={impactCohort} />
            </Panel>
          </section>
        </>
      ) : <EmptyState />}
    </div>
  );
}

/**
 * One ranked lane: the rows with a value for this metric, highest first. The
 * lanes, the colour map and the slope panel all read their selection from here,
 * so they cannot drift apart when a sort changes.
 */
function rankedForMetric(rows: InjuryProfileRow[], metric: ProfileMetric) {
  return [...rows]
    .filter((row) => metricValue(row, metric) > 0)
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label));
}

const RANKED_LANE_SIZE = 5;

/** The codes on screen for one setting: the union of each metric's top five. */
function rankedLaneCodes(rows: InjuryProfileRow[], setting: Setting) {
  const codes = new Set<string>();
  const scoped = rows.filter((row) => row.setting === setting);
  for (const metric of METRICS) {
    for (const row of rankedForMetric(scoped, metric.key).slice(0, RANKED_LANE_SIZE)) codes.add(row.code);
  }
  return codes;
}

function commonInjuryColorMap(rows: InjuryProfileRow[]) {
  const codes: string[] = [];
  const seen = new Set<string>();
  const visibleBySetting = new Map<Setting, Set<string>>();
  const addCode = (code: string) => {
    if (!seen.has(code)) {
      seen.add(code);
      codes.push(code);
    }
  };

  for (const setting of ['all', 'match', 'training'] as const) {
    const visibleCodes = rankedLaneCodes(rows, setting);
    visibleCodes.forEach(addCode);
    visibleBySetting.set(setting, visibleCodes);
  }

  [...new Set(rows.map((row) => row.code))].sort().forEach(addCode);
  const neighbours = new Map(codes.map((code) => [code, new Set<string>()]));
  for (const visibleCodes of visibleBySetting.values()) {
    for (const code of visibleCodes) {
      for (const other of visibleCodes) {
        if (other !== code) neighbours.get(code)?.add(other);
      }
    }
  }

  const assigned = new Map<string, InjuryCardColor>();
  for (const code of codes) {
    const referenceColor = REFERENCE_INJURY_COLORS[code];
    if (referenceColor) assigned.set(code, referenceColor);
  }

  const available = [...FALLBACK_INJURY_COLORS];
  const orderedCodes = [...codes].sort((a, b) =>
    (neighbours.get(b)?.size ?? 0) - (neighbours.get(a)?.size ?? 0) || a.localeCompare(b));

  for (const code of orderedCodes) {
    if (assigned.has(code)) continue;
    const neighbourColors = [...(neighbours.get(code) ?? [])]
      .map((other) => assigned.get(other)?.background)
      .filter((color): color is string => Boolean(color));
    const comparisonColors = neighbourColors.length
      ? neighbourColors
      : [...assigned.values()].map((color) => color.background);
    let selectedIndex = 0;
    let bestDistance = -1;
    for (let index = 0; index < available.length; index += 1) {
      const candidate = available[index];
      const distance = comparisonColors.length
        ? Math.min(...comparisonColors.map((color) => hexColorDistance(candidate, color)))
        : Number.POSITIVE_INFINITY;
      if (distance > bestDistance) {
        selectedIndex = index;
        bestDistance = distance;
      }
    }
    const paletteColor = available.splice(selectedIndex, 1)[0];
    const generatedHue = (205 + assigned.size * 137.508) % 360;
    assigned.set(code, {
      background: paletteColor ?? `hsl(${generatedHue} 76% 38%)`,
      foreground: '#ffffff',
    });
  }

  return assigned;
}

function hexColorDistance(a: string, b: string) {
  const channels = (color: string) => [1, 3, 5].map((index) => Number.parseInt(color.slice(index, index + 2), 16));
  const [ar, ag, ab] = channels(a);
  const [br, bg, bb] = channels(b);
  return Math.hypot(ar - br, ag - bg, ab - bb);
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
  const ranked = rankedForMetric(rows, metric.key).slice(0, RANKED_LANE_SIZE);

  return (
    <section aria-labelledby={`common-injuries-${metric.key}`}>
      <h3 id={`common-injuries-${metric.key}`} className="mb-3 text-base font-semibold text-foreground sm:text-lg">
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
    ? 'cases'
    : metric === 'incidence_per_1000h'
      ? 'per 1,000 player-h'
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
          <h4 className="text-sm font-semibold leading-snug text-inherit">{row.label}</h4>
          {metric === 'time_loss_injuries' && (
            <p className="mt-1 text-xs text-inherit">{share}% of time-loss cases</p>
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

function ProfileValue({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div className="border-r border-border/50 p-4 last:border-r-0">
      <p className="text-[10px] font-medium text-muted-foreground">{label}</p>
      <p className="mt-1 text-xl font-semibold tabular-nums text-foreground">{value}</p>
      {unit && <p className="text-[10px] text-muted-foreground">{unit}</p>}
    </div>
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
  const settingLabel = activeSetting === 'all' ? 'overall' : activeSetting;
  const metricLabel = metric === 'incidence_per_1000h' ? 'incidence' : 'burden';
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
        <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">Team Comparison</h2>
        <div className="flex flex-wrap items-center gap-2">
          <Segmented value={activeSetting} options={availableSettingOptions.length ? availableSettingOptions : comparisonSettings} onChange={setSetting} label="Choose comparison setting" />
          <Segmented value={metric} options={[{ value: 'incidence_per_1000h', label: 'Incidence' }, { value: 'burden_per_1000h', label: 'Burden' }]} onChange={setMetric} label="Choose comparison metric" />
        </div>
      </div>
      <div className="mb-4 grid grid-cols-2 overflow-hidden rounded-lg border border-border/70 bg-card/70">
        <OverviewStat label={`League ${settingLabel} incidence`} value={fmt(benchmark?.incidence_per_1000h)} unit="injuries /1,000 hours" />
        <OverviewStat label={`League ${settingLabel} burden`} value={fmt(benchmark?.burden_per_1000h)} unit="days /1,000 hours" />
      </div>
      <div className="space-y-4">
        <Panel title={`Ranked by ${settingLabel} ${metricLabel} (${metricUnit})`}>
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
        </Panel>
        <Panel title="Match and training values against the league average">
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
          <div className="mb-4 flex flex-wrap items-center gap-2">
            <h3 className="text-lg font-semibold text-foreground">Match against training incidence</h3>
            <ScopeChip show label="Match & training" />
          </div>
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

const COMPARISON_ANIMATION_MS = 900;
const COMPARISON_EASING = 'cubic-bezier(0.22, 1, 0.36, 1)';

/** Tween a number so a metric change is readable while it happens. */
function useAnimatedNumber(value: number) {
  const [display, setDisplay] = useState(value);
  const displayRef = useRef(value);

  useEffect(() => {
    const from = displayRef.current;
    if (from === value || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      displayRef.current = value;
      setDisplay(value);
      return;
    }
    let frame = 0;
    const start = performance.now();
    const step = (now: number) => {
      const progress = Math.min(1, (now - start) / COMPARISON_ANIMATION_MS);
      const eased = 1 - (1 - progress) ** 3;
      const current = from + (value - from) * eased;
      displayRef.current = current;
      setDisplay(current);
      if (progress < 1) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [value]);

  return display;
}

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
  const animatedValue = useAnimatedNumber(value);
  const metricRow = row[setting];
  const label = isViewer && viewerName ? viewerName : row.team_alias;
  const hasLeagueMean = typeof leagueMean === 'number' && Number.isFinite(leagueMean);
  const leagueMeanPosition = hasLeagueMean ? Math.min((leagueMean / max) * 100, 100) : 0;
  return (
    <button
      data-row-id={row.comparison_id}
      type="button"
      aria-label={`${label}${isViewer ? ', this team' : ''}, ${setting} ${metricLabel}: ${fmtRanked(value, metric)} ${metric === 'incidence_per_1000h' ? 'injuries per 1,000 player-hours' : 'days per 1,000 player-hours'}${hasLeagueMean ? `, league mean ${fmtRanked(leagueMean, metric)}` : ''}${metricRow ? `, ${fmt(metricRow.time_loss_injuries, 0)} time-loss cases` : ''}`}
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
          className={`block h-full rounded-full transition-[width,filter] ease-[cubic-bezier(0.22,1,0.36,1)] duration-[900ms] ${isViewer && viewerColor ? '' : 'bg-primary'} ${active ? 'brightness-125' : ''}`}
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
      <span className="text-right font-semibold tabular-nums text-foreground sm:text-lg">{fmtRanked(animatedValue, metric)}</span>
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
  exposurePreview,
  viewerComparisonId,
  teamColor,
  teamName,
}: {
  dashboard: TeamDashboardData;
  comparisons: TeamComparisonRow[];
  exposurePreview?: ExposureReviewPreview;
  viewerComparisonId?: string | null;
  teamColor?: TeamColorSet;
  teamName?: string;
}) {
  type ExposureMeasure = 'hours' | 'distance' | 'hsr';
  const [monthlyMeasure, setMonthlyMeasure] = useState<ExposureMeasure>('hours');
  const [comparisonMeasure, setComparisonMeasure] = useState<ExposureMeasure>('hours');
  const coverage = dashboard.coverage;
  const previewMonths = new Map(exposurePreview?.monthly.map((row) => [row.month, row]) ?? []);
  const previewTeams = new Map(exposurePreview?.teams.map((row) => [row.team_alias, row]) ?? []);
  const monthlyRows = dashboard.monthly.map((row) => {
    const preview = row.month ? previewMonths.get(row.month) : undefined;
    const exposureHours = addPreviewToKnownValue(row.exposure_hours, preview?.additional_hours);
    const matchHours = preview?.match_hours ?? 0;
    return {
      ...row,
      exposure_hours: exposureHours,
      distance_km: addPreviewToKnownValue(row.distance_km, preview?.additional_distance_km),
      hsr_distance_km: preview?.hsr_distance_km,
      hsr_distance_denominator_km: preview?.hsr_distance_denominator_km,
      match_exposure_hours: exposurePreview ? matchHours : undefined,
      training_exposure_hours: exposurePreview && exposureHours !== null
        ? Math.max(exposureHours - matchHours, 0)
        : undefined,
    };
  });
  const comparisonRows = comparisons.map((row) => {
    const preview = previewTeams.get(row.team_alias);
    return {
      ...row,
      exposure_hours: addPreviewToKnownValue(row.exposure_hours, preview?.additional_hours),
      distance_km: addPreviewToKnownValue(row.distance_km, preview?.additional_distance_km),
      hsr_distance_km: preview?.hsr_distance_km,
    };
  });
  const totalHours = addPreviewToKnownValue(
    coverage.hours,
    exposurePreview?.monthly.reduce((sum, row) => sum + row.additional_hours, 0),
  );
  const totalDistance = addPreviewToKnownValue(
    coverage.distance_km,
    exposurePreview?.monthly.reduce((sum, row) => sum + row.additional_distance_km, 0),
  );
  const totalHsr = exposurePreview?.monthly.reduce((sum, row) => sum + row.hsr_distance_km, 0) ?? 0;
  const options: Array<{ value: ExposureMeasure; label: string }> = [
    { value: 'hours', label: 'Hours' },
    { value: 'distance', label: 'Distance' },
    ...(exposurePreview ? [{ value: 'hsr' as const, label: 'HSR' }] : []),
  ];
  return (
    <div className="space-y-5 sm:space-y-6">
      <SectionHeading title="Exposure" />
      <section aria-labelledby="total-exposure-heading">
        <h3 id="total-exposure-heading" className="mb-3 text-lg font-semibold text-foreground">Total exposure</h3>
        <div className={`grid overflow-hidden rounded-xl border border-border/70 bg-card/70 ${exposurePreview ? 'sm:grid-cols-3' : 'sm:grid-cols-2'}`}>
          <OverviewStat label="Total hours" value={fmtHours(totalHours)} unit="player-hours" />
          <OverviewStat label="Total distance" value={fmt(totalDistance)} unit="km" />
          {exposurePreview && <OverviewStat label="HSR distance" value={fmt(totalHsr)} unit="km" />}
        </div>
      </section>
      <Panel contentClassName="p-4 sm:p-5">
        <div className="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h3 className="text-lg font-semibold text-foreground">Monthly exposure</h3>
          <Segmented value={monthlyMeasure} options={options} onChange={setMonthlyMeasure} label="Choose monthly exposure measure" scrollable={false} />
        </div>
        <ExposureTrendChart rows={monthlyRows} measure={monthlyMeasure} totalHoursColor={teamColor?.mark} />
      </Panel>
      <ExposureComparison
        rows={comparisonRows}
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

function ExposureComparison({
  rows,
  measure,
  onMeasureChange,
  options,
  viewerComparisonId,
  teamColor,
  teamName,
}: {
  rows: Array<TeamComparisonRow & { hsr_distance_km?: number | null }>;
  measure: 'hours' | 'distance' | 'hsr';
  onMeasureChange: (measure: 'hours' | 'distance' | 'hsr') => void;
  options: Array<{ value: 'hours' | 'distance' | 'hsr'; label: string }>;
  viewerComparisonId?: string | null;
  teamColor?: TeamColorSet;
  teamName?: string;
}) {
  const metric = (row: typeof rows[number]) => measure === 'hours'
    ? row.exposure_hours
    : measure === 'distance' ? row.distance_km : row.hsr_distance_km;
  const ranked = [...rows]
    .filter((row) => typeof metric(row) === 'number' && Number.isFinite(metric(row)))
    .sort((a, b) => (metric(b) ?? 0) - (metric(a) ?? 0));
  const max = Math.max(...ranked.map((row) => metric(row) ?? 0), 1);
  const label = measure === 'hours' ? 'player-hours' : 'km';
  const measureLabel = measure === 'hours' ? 'Hours' : measure === 'distance' ? 'Distance' : 'HSR';
  return (
    <Panel contentClassName="p-4 sm:p-5">
      <div className="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h3 className="text-lg font-semibold text-foreground">Team comparison</h3>
        <Segmented value={measure} options={options} onChange={onMeasureChange} label="Choose team comparison exposure measure" scrollable={false} />
      </div>
      {!ranked.length ? (
        <EmptyState>{measureLabel} is not available in the approved team comparison contract.</EmptyState>
      ) : (
        <div className="space-y-1" aria-label={`Team comparison by ${measureLabel.toLowerCase()}`}>
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
                </span>
                <span className="relative h-3 rounded-sm bg-muted" aria-hidden="true">
                  <span
                    className={`block h-full rounded-sm ${isViewer && teamColor ? '' : 'bg-primary'}`}
                    style={{ width: `${width}%`, background: isViewer ? teamColor?.mark : undefined }}
                  />
                </span>
                <span className="text-right font-semibold tabular-nums text-foreground">{displayValue}</span>
              </div>
            );
          })}
        </div>
      )}
    </Panel>
  );
}

function LocationTab({ profiles }: { profiles: InjuryProfileRow[] }) {
  const locationProfiles = profiles.filter((row) => row.dimension === 'body_location');
  const settings = availableSettings(locationProfiles, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const [metric, setMetric] = useState<ProfileMetric>('incidence_per_1000h');
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
        <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">Injury Location</h2>
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
            title="Match against training by region"
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
          <h3 className="text-lg font-semibold text-foreground">{title}</h3>
          <ScopeChip show label="Match & training" />
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
        <p className="text-xs font-medium text-muted-foreground">Selected location</p>
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
            <span className="block mt-0.5 text-muted-foreground">n = {fmt(activeRow.time_loss_injuries, 0)} time-loss cases.</span>
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
            aria-label={`${row.label}: ${fmtRanked(row[metric], metric)} ${meta.longUnit}. ${row.setting === 'all' ? 'All settings' : row.setting} cohort; n = ${fmt(row.time_loss_injuries, 0)} time-loss cases.`}
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
  const [metric, setMetric] = useState<ProfileMetric>('incidence_per_1000h');
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
        <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">Injury Types</h2>
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
            title="Match against training by injury type"
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
  exposurePreview,
  viewerComparisonId = null,
  teamColor,
  season,
  seasonPath,
}: {
  dashboard: TeamDashboardData;
  crest: string;
  teamName: string;
  comparisons?: TeamComparisonRow[];
  leagueMetrics?: SettingMetricRow[];
  supplement?: DashboardSupplement;
  exposurePreview?: ExposureReviewPreview;
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
}) {
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
  const scopeLabel = dashboard.scope === 'league' ? 'League-wide' : teamName;

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
            className="text-2xl font-bold leading-tight text-foreground sm:text-3xl"
            style={teamColor && teamColor.source !== 'achromatic' ? { color: teamColor.text } : undefined}
          >
            {teamName} Dashboard
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">{scopeLabel} injury and exposure surveillance - {dashboard.season}</p>
          <SeasonSelector season={season} seasonPath={seasonPath} />
        </div>
      </header>

      <Tabs defaultValue="overview">
        <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
          <TabsList aria-label="Dashboard sections" className="mb-6 h-auto min-w-max justify-start bg-muted/80 p-1">
            {TABS.map(([value, label]) => (
              <TabsTrigger key={value} value={value} className="min-h-11 px-4">
                {label}
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
        <TabsContent value="exposure">
          <ExposureTab
            dashboard={dashboard}
            comparisons={comparisons}
            exposurePreview={exposurePreview}
            viewerComparisonId={viewerComparisonId}
            teamColor={teamColor}
            teamName={teamName}
          />
        </TabsContent>
        <TabsContent value="common"><CommonInjuriesTab dashboard={dashboard} profiles={profiles} supplement={supplement} /></TabsContent>
        <TabsContent value="location"><LocationTab profiles={profiles} /></TabsContent>
        <TabsContent value="types"><InjuryTypesTab families={injuryTypeFamilies} /></TabsContent>
      </Tabs>
    </div>
  );
}
