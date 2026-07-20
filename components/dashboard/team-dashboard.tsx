'use client';

import { useId, useState, type ReactNode } from 'react';
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
import { BodyMap, type LocationMetric } from '@/components/dashboard/body-map';
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

function Panel({ title, children, className = '' }: {
  title?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <Card className={`min-w-0 border-border/70 bg-card/70 shadow-none ${className}`}>
      <CardContent className="p-5 sm:p-6">
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
  const diagnosisRows = supplement?.common_injuries.length
    ? supplement.common_injuries
    : profiles.some((row) => row.dimension === 'injury_profile')
    ? profiles.filter((row) => row.dimension === 'injury_profile')
    : profiles.filter((row) => row.dimension === 'injury_type');
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
  const source = supplement?.common_injuries.length
    ? supplement.common_injuries
    : profiles.some((row) => row.dimension === 'injury_profile')
    ? profiles.filter((row) => row.dimension === 'injury_profile')
    : profiles.filter((row) => row.dimension === 'injury_type');
  const settings = availableSettings(source, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const rows = source
    .filter((row) => row.setting === setting)
    .sort((a, b) => b.time_loss_injuries - a.time_loss_injuries || a.label.localeCompare(b.label));

  return (
    <div>
      <SectionHeading title="Common Injuries" />
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <SettingControl value={setting} settings={settings.length ? settings : ['all', 'match', 'training']} onChange={setSetting} />
      </div>
      {rows.length ? <ProfileCards rows={rows.slice(0, 10)} /> : <EmptyState />}
    </div>
  );
}

function ProfileCards({ rows }: { rows: InjuryProfileRow[] }) {
  return (
    <div className="grid gap-3 lg:grid-cols-2">
      {rows.map((row) => (
        <article key={`${row.setting}-${row.code}`} className="grid overflow-hidden rounded-lg border border-border/70 bg-card/70 sm:grid-cols-[5px_minmax(150px,1.25fr)_minmax(320px,2fr)]">
          <div className="h-1 sm:h-auto" style={{ backgroundColor: profileColor(row.code) }} />
          <div className="flex items-center p-5">
            <h3 className="text-lg font-semibold leading-snug text-foreground">{row.label}</h3>
          </div>
          <div className="grid grid-cols-2 border-t border-border/60 sm:grid-cols-4 sm:border-l sm:border-t-0">
            <ProfileValue label="Count" value={fmt(row.time_loss_injuries, 0)} />
            <ProfileValue label="Incidence" value={fmt(row.incidence_per_1000h)} unit="injuries /1,000 h" />
            <ProfileValue label="Burden" value={fmt(row.burden_per_1000h)} unit="days /1,000 h" />
            <ProfileValue label="Severity" value={fmt(row.mean_severity_days)} unit="days" />
          </div>
        </article>
      ))}
    </div>
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

function ComparisonRowTooltip({
  id,
  row,
  setting,
  metric,
}: {
  id: string;
  row?: TeamComparisonRow;
  setting: ComparisonSetting;
  metric: ComparisonMetric;
}) {
  const metricRow = row?.[setting];
  const metricLabel = metric === 'incidence_per_1000h' ? 'Incidence' : 'Burden';
  const unit = metric === 'incidence_per_1000h' ? 'injuries /1,000 h' : 'days /1,000 h';
  return (
    <div id={id} aria-live="polite" className="mb-4 rounded-md border border-border bg-background/60 px-4 py-3 text-sm leading-relaxed text-popover-foreground">
      {row && metricRow ? (
        <>
          <p className="font-semibold text-foreground">{row.team_alias}</p>
          <p className="mt-0.5 text-foreground"><span className="font-medium">{metricLabel}:</span> <span className="tabular-nums">{fmt(metricRow[metric])} {unit}</span></p>
          <p className="mt-1 text-muted-foreground">n = {fmt(metricRow.time_loss_injuries, 0)} time-loss cases. {fmtHours(metricRow.exposure_hours)} player-hours.</p>
        </>
      ) : 'No comparison selected.'}
    </div>
  );
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
  const tooltipId = useId();
  const activeSetting = availableSettingOptions.some(({ value }) => value === setting)
    ? setting
    : availableSettingOptions[0]?.value ?? 'all';
  const benchmark = leagueMetrics.find((row) => row.setting === activeSetting);
  const ranked = [...rows]
    .filter((row) => row[activeSetting]?.[metric] != null)
    .sort((a, b) => (b[activeSetting]?.[metric] ?? 0) - (a[activeSetting]?.[metric] ?? 0));
  const max = Math.max(...ranked.map((row) => row[activeSetting]?.[metric] ?? 0), 1);
  const activeId = hoveredId ?? selectedId ?? ranked[0]?.comparison_id;
  const activeRow = rows.find((row) => row.comparison_id === activeId);

  if (!rows.length) return <EmptyState>No approved team comparison rows are available.</EmptyState>;
  return (
    <div>
      <SectionHeading title="Team Comparison" />
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <Segmented value={activeSetting} options={availableSettingOptions.length ? availableSettingOptions : comparisonSettings} onChange={setSetting} label="Choose comparison setting" />
        <Segmented value={metric} options={[{ value: 'incidence_per_1000h', label: 'Incidence' }, { value: 'burden_per_1000h', label: 'Burden' }]} onChange={setMetric} label="Choose comparison metric" />
      </div>
      <div className="mb-6 grid overflow-hidden rounded-lg border border-border/70 bg-card/70 sm:grid-cols-2">
        <OverviewStat label={`League ${activeSetting === 'all' ? 'overall' : activeSetting} incidence`} value={fmt(benchmark?.incidence_per_1000h)} unit="/1,000 h" />
        <OverviewStat label={`League ${activeSetting === 'all' ? 'overall' : activeSetting} burden`} value={fmt(benchmark?.burden_per_1000h)} unit="days /1,000 h" />
      </div>
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.1fr)_minmax(420px,0.9fr)]">
        <Panel title="League standings">
          <ComparisonRowTooltip id={tooltipId} row={activeRow} setting={activeSetting} metric={metric} />
          <div className="max-h-[560px] space-y-1 overflow-y-auto pr-1">
            {ranked.map((row, index) => {
              const value = row[activeSetting]?.[metric] ?? 0;
              return (
                <button
                  key={row.comparison_id}
                  type="button"
                  aria-describedby={tooltipId}
                  aria-label={`${row.team_alias}, ${activeSetting} ${metric === 'incidence_per_1000h' ? 'incidence' : 'burden'}: ${fmt(value)} ${metric === 'incidence_per_1000h' ? 'injuries per 1,000 player-hours' : 'days per 1,000 player-hours'}`}
                  onMouseEnter={() => setHoveredId(row.comparison_id)}
                  onMouseLeave={() => setHoveredId(undefined)}
                  onFocus={() => setHoveredId(row.comparison_id)}
                  onBlur={() => setHoveredId(undefined)}
                  onClick={() => setSelectedId(row.comparison_id)}
                  className={`grid min-h-12 w-full grid-cols-[28px_minmax(100px,0.7fr)_minmax(110px,1fr)_86px] items-center gap-3 rounded px-3 text-left text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${activeId === row.comparison_id ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
                >
                  <span className="tabular-nums text-muted-foreground">{index + 1}</span>
                  <span className="truncate font-semibold text-foreground">{row.team_alias}</span>
                  <span className="h-3 overflow-hidden rounded-full bg-muted"><span className="block h-full rounded-full bg-primary" style={{ width: `${value / max * 100}%` }} /></span>
                  <span className="text-right text-base font-semibold tabular-nums text-foreground">{fmt(value)}</span>
                </button>
              );
            })}
          </div>
        </Panel>
        <Panel title="Relative to league average" className="min-w-0">
          <div className="overflow-x-auto pb-1">
            <table className="w-full min-w-[480px] table-fixed text-sm">
              <thead className="text-muted-foreground">
                <tr>
                  <th className="w-[38%] px-2 pb-3 text-left font-medium">Team</th>
                  <th className="w-[31%] px-2 pb-3 text-right font-medium leading-tight">Incidence</th>
                  <th className="w-[31%] px-2 pb-3 text-right font-medium leading-tight">Burden</th>
                </tr>
              </thead>
              <tbody>
                {[...rows].sort((a, b) => a.team_alias.localeCompare(b.team_alias)).map((row) => (
                  <tr key={row.comparison_id} className={`border-t border-border/40 ${activeId === row.comparison_id ? 'bg-muted/40' : ''}`}>
                    <td className="px-2 py-2 font-medium text-foreground">
                      <button
                        type="button"
                        aria-describedby={tooltipId}
                        onMouseEnter={() => setHoveredId(row.comparison_id)}
                        onMouseLeave={() => setHoveredId(undefined)}
                        onFocus={() => setHoveredId(row.comparison_id)}
                        onBlur={() => setHoveredId(undefined)}
                        onClick={() => setSelectedId(row.comparison_id)}
                        className="min-h-11 rounded px-1 text-left text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        {row.team_alias}
                      </button>
                    </td>
                    <BenchmarkCell value={row[activeSetting]?.incidence_per_1000h} average={benchmark?.incidence_per_1000h} />
                    <BenchmarkCell value={row[activeSetting]?.burden_per_1000h} average={benchmark?.burden_per_1000h} />
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-4 flex flex-wrap gap-3 border-t border-border/60 pt-4 text-[11px] text-muted-foreground">
            <span><i className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-emerald-500/55" />≥10% below</span>
            <span><i className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-amber-400/55" />within ±10%</span>
            <span><i className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-red-500/55" />≥10% above</span>
          </div>
        </Panel>
      </div>
    </div>
  );
}

function BenchmarkCell({ value, average }: { value?: number | null; average?: number | null }) {
  if (value === null || value === undefined || average === null || average === undefined || average === 0) {
    return <td className="px-2 py-2 text-right text-muted-foreground">Not available</td>;
  }
  const delta = (value - average) / average * 100;
  const tone = delta <= -10 ? 'bg-emerald-500/20 text-emerald-100' : delta >= 10 ? 'bg-red-500/20 text-red-100' : 'bg-amber-400/20 text-amber-100';
  return <td className={`px-2 py-2 text-right text-base font-semibold tabular-nums ${tone}`}>{delta > 0 ? '+' : ''}{fmt(delta)}%</td>;
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
      <SectionHeading title="Injury Location" />
      <div className="mb-5 flex justify-end">
        <MetricControl value={metric} onChange={setMetric} locationOnly />
      </div>
      {rows.length ? (
        <>
          <div className="grid gap-4 lg:grid-cols-[minmax(0,1.15fr)_minmax(300px,0.85fr)]">
            <Panel>
              <MetricBars
                rows={barRows}
                metric={metric}
                activeCode={activeCode}
                onHover={setHoveredCode}
                onSelect={setSelectedCode}
              />
            </Panel>
            <Panel>
              <BodyMap
                rows={rows}
                metric={metric as LocationMetric}
                activeCode={activeCode}
                onHover={setHoveredCode}
                onSelect={setSelectedCode}
              />
            </Panel>
          </div>
          <LocationDetail row={selected} />
        </>
      ) : <EmptyState />}
    </div>
  );
}

function LocationDetail({ row }: { row?: InjuryProfileRow }) {
  return (
    <div className="mt-5 grid gap-4 rounded-lg border border-border/70 bg-card/70 p-5 sm:grid-cols-[minmax(180px,1fr)_repeat(3,minmax(0,1fr))]">
      <div className="self-center">
        <p className="text-xs font-medium text-muted-foreground">Selected location</p>
        <p className="mt-2 text-xl font-semibold text-foreground">{row?.label ?? 'Not available'}</p>
      </div>
      <SettingValue label="Injuries" value={fmt(row?.time_loss_injuries, 0)} />
      <SettingValue label="Incidence" value={fmt(row?.incidence_per_1000h)} unit="/1,000 h" />
      <SettingValue label="Burden" value={fmt(row?.burden_per_1000h)} unit="days /1,000 h" />
    </div>
  );
}

function MetricBars({ rows, metric, activeCode, onHover, onSelect }: {
  rows: InjuryProfileRow[];
  metric: ProfileMetric;
  activeCode?: string;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
}) {
  const max = Math.max(...rows.map((row) => metricValue(row, metric)), 1);
  const meta = metricMeta(metric);
  const tooltipId = useId();
  const activeRow = rows.find((row) => row.code === activeCode) ?? rows[0];
  return (
    <div className="space-y-1">
      <div id={tooltipId} aria-live="polite" className="mb-4 rounded-md border border-border bg-background/60 px-4 py-3 text-sm leading-relaxed text-popover-foreground">
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
            className="group grid min-h-12 w-full grid-cols-[minmax(92px,0.42fr)_minmax(84px,1fr)_auto] items-center gap-3 rounded px-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <span className={`truncate text-sm ${active ? 'font-semibold text-foreground' : 'text-muted-foreground'}`}>{row.label}</span>
            <span className="h-3 overflow-hidden rounded-full bg-background/70">
              <span
                className="block h-full rounded-full bg-primary"
                style={{ width: `${Math.max((value / max) * 100, value > 0 ? 2 : 0)}%`, opacity: active ? 1 : activeCode ? 0.28 : 0.75 }}
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
  const diagnosis = supplement?.common_injuries.length
    ? supplement.common_injuries
    : profiles.some((row) => row.dimension === 'injury_profile')
      ? profiles.filter((row) => row.dimension === 'injury_profile')
      : profiles.filter((row) => row.dimension === 'injury_type');
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
