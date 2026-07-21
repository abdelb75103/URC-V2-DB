'use client';

import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import type {
  DashboardSupplement,
  InjuryProfileRow,
  SettingMetricRow,
  TeamDashboardData,
  TeamComparisonRow,
} from '@/lib/reporting-types';
import { Card, CardContent } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { BodyMap, locationHeatColor, type LocationMetric } from '@/components/dashboard/body-map';
import {
  ExposureTrendChart,
  ImpactBubbleChart,
  MatchIncidenceChart,
  MonthlyCasesChart,
  RingBreakdown,
  profileColor,
} from '@/components/dashboard/charts';

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
  ['impact', 'Injury Impact'],
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

const LOCATION_ORDER = [
  'head',
  'neck',
  'shoulder',
  'upper_arm',
  'elbow',
  'forearm',
  'wrist',
  'hand',
  'chest',
  'thoracic_spine',
  'abdomen',
  'lumbosacral',
  'hip_groin',
  'thigh',
  'knee',
  'lower_leg',
  'ankle',
  'foot',
  'multiple',
  'unspecified',
  'unknown',
];

function fmt(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: digits,
    minimumFractionDigits: Number.isInteger(value) ? 0 : digits,
  }).format(value);
}

function fmtHours(value: number | null | undefined) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
  }).format(value);
}

function metricValue(row: InjuryProfileRow, metric: ProfileMetric) {
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
}: {
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange: (value: T) => void;
  label: string;
}) {
  return (
    <div role="group" aria-label={label} className="inline-flex max-w-full gap-1 overflow-x-auto rounded-md border border-border bg-background/50 p-1">
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
  if (supplement?.common_injuries.length) return supplement.common_injuries;
  if (profiles.some((row) => row.dimension === 'diagnosis')) {
    return profiles.filter((row) => row.dimension === 'diagnosis');
  }
  if (profiles.some((row) => row.dimension === 'injury_profile')) {
    return profiles.filter((row) => row.dimension === 'injury_profile');
  }
  return profiles.filter((row) => row.dimension === 'injury_type');
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
  const [caseSetting, setCaseSetting] = useState<Setting>('all');
  const [contactSetting, setContactSetting] = useState<'all' | 'match' | 'training'>('all');
  const headline = Object.fromEntries(dashboard.headline.map((row) => [row.key, row.value]));
  const all = supplement?.rate_setting_metrics.find((row) => row.setting === 'all')
    ?? dashboard.setting_metrics.find((row) => row.setting === 'all');
  const match = supplement?.rate_setting_metrics.find((row) => row.setting === 'match')
    ?? dashboard.setting_metrics.find((row) => row.setting === 'match');
  const training = supplement?.rate_setting_metrics.find((row) => row.setting === 'training')
    ?? dashboard.setting_metrics.find((row) => row.setting === 'training');
  const diagnosisRows = reportingDiagnosisRows(profiles, supplement);
  const namedDiagnosisRows = diagnosisRows.filter((row) => row.code !== 'unknown');
  const highlights = [
    ['Most common match injury', topRow(namedDiagnosisRows, 'match', 'incidence_per_1000h'), 'incidence_per_1000h'],
    ['Most common training injury', topRow(namedDiagnosisRows, 'training', 'incidence_per_1000h'), 'incidence_per_1000h'],
    ['Highest match burden', topRow(namedDiagnosisRows, 'match', 'burden_per_1000h'), 'burden_per_1000h'],
    ['Highest training burden', topRow(namedDiagnosisRows, 'training', 'burden_per_1000h'), 'burden_per_1000h'],
  ] as const;
  const recorded = supplement?.descriptive_consequence_summary.recorded_injuries
    ?? headline.recorded_injuries
    ?? dashboard.severity_distribution.reduce((sum, row) => sum + row.recorded_injuries, 0);
  const monthlyRows = supplement?.monthly_by_setting.filter((row) => row.setting === caseSetting)
    ?? (caseSetting === 'all' ? dashboard.monthly.map((row) => ({
      month: row.month ?? '',
      setting: 'all' as const,
      recorded_injuries: row.recorded_injuries,
      time_loss_injuries: row.time_loss_injuries,
      exposure_hours: row.exposure_hours ?? null,
      rate_time_loss_injuries: row.time_loss_injuries,
      incidence_per_1000h: row.incidence_per_1000h ?? null,
    })) : []);
  const matchMonthly = supplement?.monthly_by_setting.filter((row) => row.setting === 'match') ?? [];
  const approvedMonthly = dashboard.monthly.map((row) => ({
    month: row.month ?? '',
    setting: 'all' as const,
    recorded_injuries: row.recorded_injuries,
    time_loss_injuries: row.time_loss_injuries,
    rate_time_loss_injuries: row.time_loss_injuries,
    exposure_hours: row.exposure_hours ?? null,
    incidence_per_1000h: row.incidence_per_1000h ?? null,
  }));
  const contactRows = supplement?.contact_distribution
    .filter((row) => row.setting === contactSetting)
    .map((row) => ({ key: row.key, label: row.label, value: row.time_loss_injuries })) ?? [];
  const severity = supplement?.severity_distribution ?? dashboard.severity_distribution;
  const severityRows = [
    { key: 'zero', label: '0 days recorded', value: severity.find((row) => row.key === 'zero_days_medical_attention_only')?.recorded_injuries ?? 0 },
    { key: 'one_to_seven', label: '1-7 days', value: severity.filter((row) => ['one_day', 'two_to_three_days', 'four_to_seven_days'].includes(row.key)).reduce((sum, row) => sum + row.recorded_injuries, 0) },
    { key: 'eight_to_twenty_eight', label: '8-28 days', value: severity.find((row) => row.key === 'eight_to_twenty_eight_days')?.recorded_injuries ?? 0 },
    { key: 'greater_than_twenty_eight', label: '>28 days', value: severity.find((row) => row.key === 'greater_than_twenty_eight_days')?.recorded_injuries ?? 0 },
    { key: 'unknown', label: 'Unknown / censored', value: severity.find((row) => row.key === 'unknown_or_censored')?.recorded_injuries ?? 0 },
  ];

  return (
    <div className="space-y-8 sm:space-y-10">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-primary">Overview</p>
          <h2 className="mt-1 text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">{dashboard.scope === 'league' ? 'League injury picture' : 'Team injury picture'}</h2>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {highlights.map(([title, row, metric]) => (
          <HighlightCard key={title} title={title} row={row} metric={metric} />
        ))}
      </div>

      <div className="grid overflow-hidden rounded-lg border border-border/70 bg-card/70 sm:grid-cols-2 xl:grid-cols-4">
        <OverviewStat label={supplement ? 'Attributed records' : 'Recorded cases'} value={fmt(recorded, 0)} />
        <OverviewStat label="Incidence" value={fmt(supplement ? all?.incidence_per_1000h : headline.incidence_per_1000h ?? all?.incidence_per_1000h)} unit="/1,000 h" />
        <OverviewStat label="Burden" value={fmt(supplement ? all?.burden_per_1000h : headline.burden_per_1000h ?? all?.burden_per_1000h)} unit="days /1,000 h" />
        <OverviewStat label="Exposure" value={fmtHours(dashboard.coverage.hours)} unit="player-hours" />
      </div>

      <MatchTrainingVisual match={match} training={training} />

      <div className="grid gap-5 xl:grid-cols-2">
        <Panel title="Cases by month">
          {supplement && <div className="mb-4 flex justify-end"><SettingControl value={caseSetting} settings={['all', 'match', 'training']} onChange={setCaseSetting} /></div>}
          <div className="overflow-x-auto"><MonthlyCasesChart rows={monthlyRows} /></div>
        </Panel>
        <Panel title={supplement ? 'Match incidence by month' : 'Overall incidence by month'}>
          <div className="overflow-x-auto"><MatchIncidenceChart rows={supplement ? matchMonthly : approvedMonthly} /></div>
        </Panel>
      </div>

      <div className={`grid gap-5 ${supplement ? 'xl:grid-cols-2' : ''}`}>
        <Panel title="Severity distribution">
          <RingBreakdown rows={severityRows} centerLabel="cases" valueLabel="cases" />
        </Panel>
        {supplement && <Panel title="Contact vs non-contact">
          <div className="mb-4 flex justify-end">
            <Segmented value={contactSetting} options={['all', 'match', 'training'].map((value) => ({ value: value as typeof contactSetting, label: value === 'all' ? 'Overall' : value[0].toUpperCase() + value.slice(1) }))} onChange={setContactSetting} label="Choose contact setting" />
          </div>
          <RingBreakdown rows={contactRows} centerLabel="positive-day" valueLabel="cases" />
        </Panel>}
      </div>

      {supplement && <InferenceCoverageSummary supplement={supplement} />}
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

function InferenceCoverageSummary({ supplement }: { supplement: DashboardSupplement }) {
  const coverage = supplement.inference_coverage;
  const fields = [
    ['Body location', coverage.body_location],
    ['Tissue and pathology', coverage.tissue_pathology],
    ['Diagnosis', coverage.diagnosis],
    ['Contact context', coverage.contact_context],
  ] as const;

  return (
    <details className="rounded-lg border border-border/70 bg-card/60">
      <summary className="flex min-h-11 cursor-pointer items-center px-5 text-sm font-medium text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">Data coverage & provenance</summary>
      <div className="border-t border-border/60 p-5">
      <div className="grid divide-y divide-border/60 sm:grid-cols-2 sm:divide-x sm:divide-y-0">
        {fields.map(([label, counts]) => (
          <div key={label} className="p-3 first:pl-0 sm:[&:nth-child(2)]:pr-0">
            <p className="text-xs font-medium text-foreground">{label}</p>
            <p className="mt-2 text-xl font-semibold tabular-nums text-foreground">{fmt(counts.classified, 0)} / {fmt(counts.total, 0)}</p>
            <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
              classified in the draft. {fmt(counts.source_reported, 0)} source-reported, {fmt(counts.mapped, 0)} mapped through deterministic lookup, {fmt(counts.inferred, 0)} inferred from evidence, {fmt(counts.adjudicated, 0)} adjudicated, {fmt(counts.remaining_unknown, 0)} still unknown.
            </p>
          </div>
        ))}
      </div>
      </div>
    </details>
  );
}

function MatchTrainingVisual({ match, training }: { match?: SettingMetricRow; training?: SettingMetricRow }) {
  const maxIncidence = Math.max(match?.incidence_per_1000h ?? 0, training?.incidence_per_1000h ?? 0, 1);
  return (
    <Panel title="Match vs training">
      <div className="grid gap-6 md:grid-cols-2">
        <SettingPanel title="Match" row={match} maxIncidence={maxIncidence} />
        <SettingPanel title="Training" row={training} maxIncidence={maxIncidence} />
      </div>
    </Panel>
  );
}

function SettingPanel({ title, row, maxIncidence }: { title: string; row?: SettingMetricRow; maxIncidence: number }) {
  const width = Math.max(((row?.incidence_per_1000h ?? 0) / maxIncidence) * 100, row?.incidence_per_1000h ? 3 : 0);
  return (
    <div className="relative overflow-hidden rounded-md border border-border/60 bg-background/35 p-5">
      <div className="absolute inset-x-0 top-0 h-1 bg-primary" aria-hidden="true" />
      <p className="text-sm font-semibold text-primary">{title}</p>
      <div className="mt-4 h-3 overflow-hidden rounded-full bg-muted">
        <div className="h-full rounded-full bg-primary" style={{ width: `${width}%` }} />
      </div>
      <div className="mt-5 grid grid-cols-3 gap-4">
        <SettingValue label="Incidence" value={fmt(row?.incidence_per_1000h)} unit="/1,000 h" />
        <SettingValue label="Burden" value={fmt(row?.burden_per_1000h)} unit="days /1,000 h" />
        <SettingValue label="Cases" value={fmt(row?.time_loss_injuries, 0)} />
      </div>
    </div>
  );
}

function SettingValue({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-2 text-2xl font-semibold tabular-nums text-foreground sm:text-3xl">{value}</p>
      {unit && <p className="text-[11px] text-muted-foreground">{unit}</p>}
    </div>
  );
}

function topRow(rows: InjuryProfileRow[], setting: Setting, metric: ProfileMetric) {
  return [...rows]
    .filter((row) => row.setting === setting)
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label))[0];
}

function HighlightCard({ title, row, metric }: { title: string; row?: InjuryProfileRow; metric: ProfileMetric }) {
  const meta = metricMeta(metric);
  return (
    <Card className="overflow-hidden border-border/70 bg-card/70 shadow-none">
      <div className="h-1.5" style={{ backgroundColor: row ? profileColor(row.code) : 'hsl(var(--border))' }} />
      <CardContent className="p-5 sm:p-6">
        <p className="text-[11px] font-medium text-muted-foreground">{title}</p>
        <p className="mt-5 min-h-12 text-lg font-semibold leading-tight text-foreground sm:text-xl">{row?.label ?? 'Not available'}</p>
        <p className="mt-5 text-sm tabular-nums text-muted-foreground">
          <strong className="text-3xl text-foreground sm:text-4xl">{row ? fmt(row[metric]) : 'Not available'}</strong>{' '}
          {row && <span className="text-xs">{meta.shortUnit}</span>}
        </p>
      </CardContent>
    </Card>
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

function CommonInjuriesTab({ profiles, supplement }: { profiles: InjuryProfileRow[]; supplement?: DashboardSupplement }) {
  const source = reportingDiagnosisRows(profiles, supplement);
  const settings = availableSettings(source, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const rows = source.filter((row) => row.setting === setting && row.code !== 'unknown');
  const injuryColors = commonInjuryColorMap(source);
  const totalInjuries = source
    .filter((row) => row.setting === setting)
    .reduce((sum, row) => sum + row.time_loss_injuries, 0);
  const settingTitle = setting === 'all' ? '' : `${setting[0].toUpperCase()}${setting.slice(1)} `;

  return (
    <div>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4 border-b border-border/60 pb-4">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">Most Common {settingTitle}Injuries</h2>
        </div>
        <SettingControl value={setting} settings={settings.length ? settings : ['all', 'match', 'training']} onChange={setSetting} />
      </div>
      {rows.length ? <CommonInjuryRankings rows={rows} totalInjuries={totalInjuries} injuryColors={injuryColors} /> : <EmptyState />}
    </div>
  );
}

function commonInjuryColorMap(rows: InjuryProfileRow[]) {
  const codes: string[] = [];
  const seen = new Set<string>();
  const visibleBySetting = new Map<Setting, Set<string>>();
  const addCode = (code: string) => {
    if (code !== 'unknown' && !seen.has(code)) {
      seen.add(code);
      codes.push(code);
    }
  };

  for (const setting of ['all', 'match', 'training'] as const) {
    const visibleCodes = new Set<string>();
    for (const metric of METRICS) {
      [...rows]
        .filter((row) => row.setting === setting && row.code !== 'unknown' && metricValue(row, metric.key) > 0)
        .sort((a, b) => metricValue(b, metric.key) - metricValue(a, metric.key) || a.label.localeCompare(b.label))
        .slice(0, 5)
        .forEach((row) => {
          addCode(row.code);
          visibleCodes.add(row.code);
        });
    }
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
  const ranked = [...rows]
    .filter((row) => metricValue(row, metric.key) > 0)
    .sort((a, b) => metricValue(b, metric.key) - metricValue(a, metric.key) || a.label.localeCompare(b.label))
    .slice(0, 5);

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
}: {
  rows: TeamComparisonRow[];
  leagueMetrics: SettingMetricRow[];
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
  const max = Math.max(...ranked.map((row) => row[activeSetting]?.[metric] ?? 0), 1);
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
  const alphabetical = [...rows].sort((a, b) => a.team_alias.localeCompare(b.team_alias));
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
                active={activeId === row.comparison_id}
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
                        {row.team_alias}
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
  active,
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
  active: boolean;
  onHover: (id?: string) => void;
  onSelect: (id: string) => void;
}) {
  const animatedValue = useAnimatedNumber(value);
  const metricRow = row[setting];
  return (
    <button
      data-row-id={row.comparison_id}
      type="button"
      aria-label={`${row.team_alias}, ${setting} ${metricLabel}: ${fmt(value)} ${metric === 'incidence_per_1000h' ? 'injuries per 1,000 player-hours' : 'days per 1,000 player-hours'}${metricRow ? `, ${fmt(metricRow.time_loss_injuries, 0)} time-loss cases` : ''}`}
      onMouseEnter={() => onHover(row.comparison_id)}
      onMouseLeave={() => onHover(undefined)}
      onFocus={() => onHover(row.comparison_id)}
      onBlur={() => onHover(undefined)}
      onClick={() => onSelect(row.comparison_id)}
      className={`group grid min-h-12 w-full grid-cols-[26px_minmax(84px,140px)_minmax(80px,1fr)_76px] items-center gap-3 rounded px-2 text-left text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:min-h-14 sm:gap-4 lg:min-h-10 ${active ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
    >
      <span className="tabular-nums text-xs text-muted-foreground transition-colors duration-300 group-hover:text-foreground">{rank}</span>
      <span className="truncate font-semibold text-foreground sm:text-base">{row.team_alias}</span>
      <span className="h-4 overflow-hidden rounded-full bg-muted sm:h-5">
        <span
          className={`block h-full rounded-full bg-primary transition-[width,filter] ease-[cubic-bezier(0.22,1,0.36,1)] duration-[900ms] ${active ? 'brightness-125' : ''}`}
          style={{ width: `${(value / max) * 100}%` }}
        />
      </span>
      <span className="text-right font-semibold tabular-nums text-foreground sm:text-lg">{fmt(animatedValue)}</span>
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

function ExposureRowTooltip({ id, row }: { id: string; row?: TeamComparisonRow }) {
  return (
    <div id={id} aria-live="polite" className="mb-4 rounded-md border border-border bg-background/60 px-4 py-3 text-sm leading-relaxed text-popover-foreground">
      {row ? (
        <>
          <p className="font-semibold text-foreground">{row.team_alias}</p>
          <p className="mt-0.5 text-foreground"><span className="font-medium">Total exposure:</span> <span className="tabular-nums">{fmtHours(row.exposure_hours)} player-hours</span></p>
          <p className="mt-1 text-muted-foreground">Match {fmtHours(row.match_hours)} h. Training {fmtHours(row.training_hours)} h.</p>
        </>
      ) : 'No club selected.'}
    </div>
  );
}

function ExposureTab({ dashboard, comparisons }: { dashboard: TeamDashboardData; comparisons: TeamComparisonRow[] }) {
  const [hoveredId, setHoveredId] = useState<string>();
  const [selectedId, setSelectedId] = useState<string>();
  const tooltipId = useId();
  const sorted = [...comparisons].sort((a, b) => b.exposure_hours - a.exposure_hours);
  const max = Math.max(...sorted.map((row) => row.exposure_hours), 1);
  const activeId = hoveredId ?? selectedId ?? sorted[0]?.comparison_id;
  const activeRow = sorted.find((row) => row.comparison_id === activeId);
  return (
    <div>
      <SectionHeading title="Exposure" />
      <div className="grid overflow-hidden rounded-lg border border-border/70 bg-card/70 sm:grid-cols-2 xl:grid-cols-4">
        <OverviewStat label="Total exposure" value={fmtHours(dashboard.coverage.hours)} unit="player-hours" />
        <OverviewStat label="Match exposure" value={fmtHours(dashboard.coverage.match_hours)} unit="player-hours" />
        <OverviewStat label="Training exposure" value={fmtHours(dashboard.coverage.training_hours)} unit="player-hours" />
        <OverviewStat label="Distance" value={fmt(dashboard.coverage.distance_km)} unit="km" />
      </div>
      <div className="mt-6 space-y-5">
        <ExposureSettingSplit matchHours={dashboard.coverage.match_hours} trainingHours={dashboard.coverage.training_hours} />
        <Panel title="Exposure by month">
          <div className="overflow-x-auto"><ExposureTrendChart rows={dashboard.monthly} /></div>
        </Panel>
        <Panel title="Club exposure comparison">
          {sorted.length ? (
            <>
              <ExposureRowTooltip id={tooltipId} row={activeRow} />
              <div className="max-h-[640px] space-y-1 overflow-y-auto pr-1">
                {sorted.map((row, index) => (
                  <button
                    key={row.comparison_id}
                    type="button"
                    aria-describedby={tooltipId}
                    aria-label={`${row.team_alias}: ${fmtHours(row.exposure_hours)} player-hours total exposure`}
                    onMouseEnter={() => setHoveredId(row.comparison_id)}
                    onMouseLeave={() => setHoveredId(undefined)}
                    onFocus={() => setHoveredId(row.comparison_id)}
                    onBlur={() => setHoveredId(undefined)}
                    onClick={() => setSelectedId(row.comparison_id)}
                    className={`grid min-h-12 w-full grid-cols-[30px_minmax(100px,0.5fr)_minmax(110px,1fr)_96px] items-center gap-3 rounded px-3 text-left text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${activeId === row.comparison_id ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
                  >
                    <span className="text-muted-foreground">{index + 1}</span>
                    <span className="truncate font-semibold text-foreground">{row.team_alias}</span>
                    <span className="h-3 overflow-hidden rounded-full bg-muted"><span className="block h-full rounded-full bg-primary" style={{ width: `${row.exposure_hours / max * 100}%` }} /></span>
                    <span className="text-right text-base font-semibold tabular-nums text-foreground">{fmtHours(row.exposure_hours)}</span>
                  </button>
                ))}
              </div>
            </>
          ) : <EmptyState />}
        </Panel>
      </div>
    </div>
  );
}

function ExposureSettingSplit({
  matchHours,
  trainingHours,
}: {
  matchHours?: number | null;
  trainingHours?: number | null;
}) {
  const max = Math.max(matchHours ?? 0, trainingHours ?? 0, 1);
  const rows = [
    { label: 'Match', value: matchHours ?? null, color: 'bg-primary' },
    { label: 'Training', value: trainingHours ?? null, color: 'bg-primary/60' },
  ];

  return (
    <div className="grid overflow-hidden rounded-lg border border-border/70 bg-card/60 md:grid-cols-2">
      {rows.map((row) => {
        const width = row.value === null ? 0 : Math.max((row.value / max) * 100, row.value > 0 ? 3 : 0);
        return (
          <div key={row.label} className="border-b border-border/60 p-5 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0">
            <div className="flex items-baseline justify-between gap-3">
              <p className="font-semibold text-foreground">{row.label}</p>
              <p className="text-2xl font-semibold tabular-nums text-foreground">{fmtHours(row.value)} <span className="text-xs font-medium text-muted-foreground">h</span></p>
            </div>
            <div className="mt-4 h-3 overflow-hidden rounded-full bg-muted">
              <div className={`h-full rounded-full ${row.color}`} style={{ width: `${width}%` }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}

function LocationTab({ profiles }: { profiles: InjuryProfileRow[] }) {
  const [metric, setMetric] = useState<ProfileMetric>('incidence_per_1000h');
  const [selectedCode, setSelectedCode] = useState<string>();
  const [hoveredCode, setHoveredCode] = useState<string>();
  const rows = profiles
    .filter((row) => row.dimension === 'body_location' && row.setting === 'all')
    .sort((a, b) => LOCATION_ORDER.indexOf(a.code) - LOCATION_ORDER.indexOf(b.code));
  const barRows = [...rows]
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label))
    .slice(0, 10);
  const activeCode = hoveredCode ?? (rows.some((row) => row.code === selectedCode) ? selectedCode : barRows[0]?.code);
  const selected = rows.find((row) => row.code === activeCode);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-2xl font-semibold tracking-tight text-foreground sm:text-3xl">Injury Location</h2>
        <MetricControl value={metric} onChange={setMetric} locationOnly />
      </div>
      {rows.length ? (
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
      ) : <EmptyState />}
    </div>
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
        <LocationMetricValue label="Incidence" value={fmt(row?.incidence_per_1000h)} unit="/1,000 h" active={metric === 'incidence_per_1000h'} />
        <LocationMetricValue label="Burden" value={fmt(row?.burden_per_1000h)} unit="days /1,000 h" active={metric === 'burden_per_1000h'} />
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

function MetricBars({ rows, metric, activeCode, onHover, onSelect, heatMapColors = false }: {
  rows: InjuryProfileRow[];
  metric: ProfileMetric;
  activeCode?: string;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
  heatMapColors?: boolean;
}) {
  const max = Math.max(...rows.map((row) => metricValue(row, metric)), 1);
  const meta = metricMeta(metric);
  const tooltipId = useId();
  const activeRow = rows.find((row) => row.code === activeCode) ?? rows[0];
  return (
    <div className={heatMapColors ? 'space-y-0' : 'space-y-1'}>
      <div id={tooltipId} aria-live="polite" className={heatMapColors ? 'sr-only' : 'mb-4 rounded-md border border-border bg-background/60 px-4 py-3 text-sm leading-relaxed text-popover-foreground'}>
        {activeRow ? (
          <>
            <span className="font-semibold text-foreground">{activeRow.label}</span>
            <span className="mx-1 text-muted-foreground">:</span>
            <span className="font-medium tabular-nums text-foreground">{fmt(activeRow[metric])} {meta.longUnit}</span>
            <span className="block mt-0.5 text-muted-foreground">n = {fmt(activeRow.time_loss_injuries, 0)} time-loss cases.</span>
          </>
        ) : 'No injury type selected.'}
      </div>
      {rows.map((row) => {
        const value = metricValue(row, metric);
        const active = activeCode === row.code;
        return (
          <button
            key={row.code}
            type="button"
            aria-describedby={tooltipId}
            aria-label={`${row.label}: ${fmt(row[metric])} ${meta.longUnit}. ${row.setting === 'all' ? 'All settings' : row.setting} cohort; n = ${fmt(row.time_loss_injuries, 0)} time-loss cases.`}
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
            <span className="min-w-16 text-right text-base font-semibold tabular-nums text-foreground">{fmt(row[metric])}</span>
          </button>
        );
      })}
    </div>
  );
}

function InjuryTypesTab({ profiles }: { profiles: InjuryProfileRow[] }) {
  const source = profiles.filter((row) => row.dimension === 'injury_type');
  const settings = availableSettings(source, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const [metric, setMetric] = useState<ProfileMetric>('burden_per_1000h');
  const [selectedCode, setSelectedCode] = useState<string>();
  const [hoveredCode, setHoveredCode] = useState<string>();
  const rows = source
    .filter((row) => row.setting === setting)
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label))
    .slice(0, 10);
  const activeCode = hoveredCode ?? (rows.some((row) => row.code === selectedCode) ? selectedCode : rows[0]?.code);
  const activeRow = rows.find((row) => row.code === activeCode);

  return (
    <div>
      <SectionHeading title="Injury Types" />
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <SettingControl value={setting} settings={settings.length ? settings : ['all']} onChange={setSetting} />
        <MetricControl value={metric} onChange={setMetric} />
      </div>
      {rows.length ? (
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1.15fr)_minmax(360px,0.85fr)]">
          <Panel title={`${metricMeta(metric).label} by injury type`}>
            <MetricBars
              rows={rows}
              metric={metric}
              activeCode={activeCode}
              onHover={setHoveredCode}
              onSelect={setSelectedCode}
            />
          </Panel>
          <Panel title="Selected type">
            <div className="flex items-center gap-4">
              <span className="h-16 w-2 shrink-0 rounded-full" style={{ backgroundColor: activeRow ? profileColor(activeRow.code) : 'hsl(var(--border))' }} />
              <p className="text-2xl font-semibold leading-tight text-foreground">{activeRow?.label ?? 'Not available'}</p>
            </div>
            <div className="mt-5 grid grid-cols-2 overflow-hidden rounded-md border border-border/60">
              <ProfileValue label="Count" value={fmt(activeRow?.time_loss_injuries, 0)} />
              <ProfileValue label="Incidence" value={fmt(activeRow?.incidence_per_1000h)} unit="injuries /1,000 h" />
              <ProfileValue label="Burden" value={fmt(activeRow?.burden_per_1000h)} unit="days /1,000 h" />
              <ProfileValue label="Severity" value={fmt(activeRow?.mean_severity_days)} unit="days" />
            </div>
          </Panel>
        </div>
      ) : <EmptyState />}
    </div>
  );
}

function ImpactTab({ profiles, supplement }: { profiles: InjuryProfileRow[]; supplement?: DashboardSupplement }) {
  const [dimension, setDimension] = useState<'diagnosis' | 'location' | 'type'>('diagnosis');
  const diagnosis = reportingDiagnosisRows(profiles, supplement);
  const source = dimension === 'diagnosis'
    ? diagnosis
    : profiles.filter((row) => row.dimension === (dimension === 'location' ? 'body_location' : 'injury_type'));
  const settings = availableSettings(source, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const effectiveSetting = settings.includes(setting) ? setting : settings[0] ?? 'all';
  const rows = source
    .filter((row) => row.setting === effectiveSetting)
    .sort((a, b) => (b.burden_per_1000h ?? 0) - (a.burden_per_1000h ?? 0))
    .slice(0, 12);

  return (
    <div>
      <SectionHeading title="Injury Impact" />
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <Segmented
          value={dimension}
          options={[
            { value: 'diagnosis', label: 'Diagnosis' },
            { value: 'location', label: 'Location' },
            { value: 'type', label: 'Type' },
          ]}
          onChange={setDimension}
          label="Choose impact grouping"
        />
        <SettingControl value={effectiveSetting} settings={settings.length ? settings : ['all']} onChange={setSetting} />
      </div>
      <Panel>
        <ImpactBubbleChart rows={rows} />
      </Panel>
      {rows.length > 0 && <AccessibleDataTable rows={rows} />}
    </div>
  );
}

function AccessibleDataTable({ rows }: { rows: InjuryProfileRow[] }) {
  return (
    <details className="mt-4 rounded-lg border border-border/70 bg-card/60">
      <summary className="flex min-h-11 cursor-pointer items-center px-4 text-sm font-medium text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">View injury impact data</summary>
      <div className="overflow-x-auto border-t border-border/60 p-4">
        <table className="w-full min-w-[620px] text-sm">
          <thead className="text-xs text-muted-foreground">
            <tr>
              <th className="pb-2 text-left font-medium">Injury profile</th>
              <th className="pb-2 text-right font-medium">Injuries</th>
              <th className="pb-2 text-right font-medium">Incidence</th>
              <th className="pb-2 text-right font-medium">Mean severity</th>
              <th className="pb-2 text-right font-medium">Burden</th>
            </tr>
          </thead>
          <tbody>
            {[...rows].sort((a, b) => (b.burden_per_1000h ?? 0) - (a.burden_per_1000h ?? 0)).map((row) => (
              <tr key={row.code} className="border-t border-border/40">
                <td className="py-2 pr-4 text-foreground">{row.label}</td>
                <td className="py-2 text-right tabular-nums text-muted-foreground">{row.time_loss_injuries}</td>
                <td className="py-2 text-right tabular-nums text-muted-foreground">{fmt(row.incidence_per_1000h)}</td>
                <td className="py-2 text-right tabular-nums text-muted-foreground">{fmt(row.mean_severity_days)}</td>
                <td className="py-2 text-right tabular-nums text-muted-foreground">{fmt(row.burden_per_1000h)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </details>
  );
}

function availableSettings(rows: InjuryProfileRow[], preference: Setting[]) {
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
}: {
  dashboard: TeamDashboardData;
  crest: string;
  teamName: string;
  comparisons?: TeamComparisonRow[];
  leagueMetrics?: SettingMetricRow[];
  supplement?: DashboardSupplement;
}) {
  const approvedProfiles = dashboard.injury_profiles ?? [];
  const profiles = supplement
    ? [
        ...approvedProfiles.filter((row) => !['body_location', 'injury_type'].includes(row.dimension)),
        ...supplement.body_locations,
        ...supplement.injury_types,
      ]
    : approvedProfiles;
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
          <h1 className="text-2xl font-bold leading-tight text-foreground sm:text-3xl">{teamName} Dashboard</h1>
          <p className="mt-1 text-sm text-muted-foreground">{scopeLabel} injury and exposure surveillance - {dashboard.season}</p>
          {supplement && <span className="mt-3 inline-flex rounded-full border border-amber-400/40 bg-amber-400/10 px-3 py-1 text-[11px] font-medium text-amber-200">V3 inference preview - draft, not released</span>}
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
        <TabsContent value="comparison"><TeamComparisonTab rows={comparisons} leagueMetrics={leagueMetrics} /></TabsContent>
        <TabsContent value="exposure"><ExposureTab dashboard={dashboard} comparisons={comparisons} /></TabsContent>
        <TabsContent value="common"><CommonInjuriesTab profiles={profiles} supplement={supplement} /></TabsContent>
        <TabsContent value="location"><LocationTab profiles={profiles} /></TabsContent>
        <TabsContent value="types"><InjuryTypesTab profiles={profiles} /></TabsContent>
        <TabsContent value="impact"><ImpactTab profiles={profiles} supplement={supplement} /></TabsContent>
      </Tabs>
    </div>
  );
}
