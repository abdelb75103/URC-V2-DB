'use client';

import { useId, useState, type ReactNode } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { ArrowLeft, Info } from 'lucide-react';
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

function zeroDayFallback(dashboard: TeamDashboardData) {
  return dashboard.severity_distribution.find((row) => row.key === 'zero_days_medical_attention_only')?.recorded_injuries ?? 0;
}

function Panel({ title, description, children, className = '' }: {
  title?: string;
  description?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <Card className={`min-w-0 border-border/70 bg-card/70 shadow-none ${className}`}>
      <CardContent className="p-4 sm:p-5">
        {(title || description) && (
          <div className="mb-4">
            {title && <h3 className="text-base font-semibold text-foreground">{title}</h3>}
            {description && <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{description}</p>}
          </div>
        )}
        {children}
      </CardContent>
    </Card>
  );
}

function MetricInfo({ label, children }: { label: string; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const tooltipId = useId();
  return (
    <span className="inline-flex">
      <button
        type="button"
        aria-label={`What ${label} means`}
        aria-expanded={open}
        aria-describedby={open ? tooltipId : undefined}
        onMouseEnter={() => setOpen(true)}
        onMouseLeave={() => setOpen(false)}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onKeyDown={(event) => {
          if (event.key === 'Escape') setOpen(false);
        }}
        onClick={() => setOpen(true)}
        className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted-foreground transition-colors hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        <Info className="h-4 w-4" aria-hidden="true" />
      </button>
      {open && (
        <span
          id={tooltipId}
          role="tooltip"
          className="fixed inset-x-4 bottom-4 z-50 mx-auto max-w-sm rounded-md border border-border bg-popover px-3 py-2 text-left text-xs leading-relaxed text-popover-foreground shadow-xl"
        >
          {children}
        </span>
      )}
    </span>
  );
}

function SectionHeading({ title, description }: { title: string; description?: string }) {
  return (
    <div className="mb-5">
      <h2 className="text-xl font-semibold text-foreground sm:text-2xl">{title}</h2>
      {description && <p className="mt-1 max-w-2xl text-sm text-muted-foreground">{description}</p>}
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
          label: setting === 'all' ? 'All' : setting[0].toUpperCase() + setting.slice(1),
        }))}
        onChange={onChange}
        label="Choose setting"
      />
    </div>
  );
}

function EmptyState({ children = 'No audited data is available for this view.' }: { children?: ReactNode }) {
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
  const highlights = [
    ['Most common match injury', topRow(diagnosisRows, 'match', 'incidence_per_1000h'), 'incidence_per_1000h'],
    ['Most common training injury', topRow(diagnosisRows, 'training', 'incidence_per_1000h'), 'incidence_per_1000h'],
    ['Highest match burden', topRow(diagnosisRows, 'match', 'burden_per_1000h'), 'burden_per_1000h'],
    ['Highest training burden', topRow(diagnosisRows, 'training', 'burden_per_1000h'), 'burden_per_1000h'],
  ] as const;
  const recorded = supplement?.descriptive_consequence_summary.recorded_injuries
    ?? headline.recorded_injuries
    ?? dashboard.severity_distribution.reduce((sum, row) => sum + row.recorded_injuries, 0);
  const timeLoss = supplement?.descriptive_consequence_summary.time_loss_injuries
    ?? headline.time_loss_injuries
    ?? all?.time_loss_injuries
    ?? 0;
  const medicalAttention = supplement?.descriptive_consequence_summary.medical_attention_only ?? zeroDayFallback(dashboard);
  const consequenceUnknown = supplement?.descriptive_consequence_summary.consequence_unknown
    ?? Math.max(recorded - timeLoss - medicalAttention, 0);
  const undated = supplement?.descriptive_consequence_summary.undated_injuries ?? 0;
  const outsideSeason = supplement?.descriptive_consequence_summary.outside_season_date_injuries ?? 0;
  const monthlyExcluded = undated + outsideSeason;
  const rateRecorded = supplement?.consequence_summary.recorded_injuries
    ?? headline.recorded_injuries
    ?? recorded;
  const positiveDays = supplement?.consequence_summary.positive_day_cases
    ?? headline.time_loss_injuries
    ?? all?.time_loss_injuries
    ?? 0;
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
  const matchScope = supplement?.match_scope_summary;
  const severityRows = [
    { key: 'zero', label: '0 days recorded', value: severity.find((row) => row.key === 'zero_days_medical_attention_only')?.recorded_injuries ?? 0 },
    { key: 'one_to_seven', label: '1-7 days', value: severity.filter((row) => ['one_day', 'two_to_three_days', 'four_to_seven_days'].includes(row.key)).reduce((sum, row) => sum + row.recorded_injuries, 0) },
    { key: 'eight_to_twenty_eight', label: '8-28 days', value: severity.find((row) => row.key === 'eight_to_twenty_eight_days')?.recorded_injuries ?? 0 },
    { key: 'greater_than_twenty_eight', label: '>28 days', value: severity.find((row) => row.key === 'greater_than_twenty_eight_days')?.recorded_injuries ?? 0 },
    { key: 'unknown', label: 'Unknown / censored', value: severity.find((row) => row.key === 'unknown_or_censored')?.recorded_injuries ?? 0 },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.16em] text-primary">Case surveillance</p>
          <h2 className="mt-1 text-xl font-semibold text-foreground sm:text-2xl">{dashboard.scope === 'league' ? 'League injury picture' : 'Team injury picture'}</h2>
        </div>
        {supplement && <span className="rounded-full border border-amber-400/40 bg-amber-400/10 px-3 py-1 text-[11px] font-medium text-amber-200">V3 inference preview - draft, not released</span>}
      </div>

      <div className="grid grid-cols-2 overflow-hidden rounded-lg border border-border/70 bg-card/70 lg:grid-cols-4">
        <OverviewStat label={supplement ? 'Attributed injury records' : 'Recorded injury cases'} value={fmt(recorded, 0)} />
        <OverviewStat label={supplement ? 'Time-loss records' : 'Positive-day cases'} value={fmt(timeLoss, 0)} />
        <OverviewStat label={supplement ? 'Medical-attention only' : '0 days recorded'} value={fmt(medicalAttention, 0)} />
        <OverviewStat label={supplement ? 'Consequence unknown' : 'Duration unknown / censored'} value={fmt(consequenceUnknown, 0)} />
      </div>
      <p className="px-1 text-xs leading-relaxed text-muted-foreground">
        {supplement
          ? 'Time loss uses positive recorded days or an explicit source classification. Medical-attention only uses an explicit source classification or a closed 0-day record; unresolved cases remain unknown.'
          : 'The approved V2 rate cohort uses positive recorded days; 0-day and unknown/censored cases remain visible and are not relabelled.'}
      </p>
      <div className="flex flex-wrap items-center justify-between gap-2 px-1 text-xs text-muted-foreground">
        <span className="font-semibold uppercase tracking-wider text-foreground">Exposure-aligned rate cohort</span>
        <span>{fmt(rateRecorded, 0)} cases - {fmt(positiveDays, 0)} with positive recorded days</span>
      </div>
      <div className="grid grid-cols-2 overflow-hidden rounded-lg border border-border/70 bg-card/40 sm:grid-cols-4">
        <OverviewStat label="Incidence" value={fmt(supplement ? all?.incidence_per_1000h : headline.incidence_per_1000h ?? all?.incidence_per_1000h)} unit="injuries /1,000 h" info="Time-loss injuries per 1,000 player-hours. It adjusts injury frequency for how much the group was exposed." />
        <OverviewStat label="Burden" value={fmt(supplement ? all?.burden_per_1000h : headline.burden_per_1000h ?? all?.burden_per_1000h)} unit="days /1,000 h" info="Days lost per 1,000 player-hours. It combines how often injuries occur with how much time they cost." />
        <OverviewStat label="Mean severity" value={fmt(supplement ? all?.mean_severity_days : headline.severity_mean_days ?? all?.mean_severity_days)} unit="days" info="Average recorded days lost among time-loss injuries. Unknown and censored durations stay visible rather than being guessed." />
        <OverviewStat label="Exposure" value={fmtHours(dashboard.coverage.hours)} unit="player-hours" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <SettingPanel title="Match" row={match} />
        <SettingPanel title="Training" row={training} />
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <Panel title="Cases by month" description={`Attributed dated cases and the time-loss subset from July 2024 to June 2025${monthlyExcluded ? `; ${fmt(monthlyExcluded, 0)} retained ${monthlyExcluded === 1 ? 'record is' : 'records are'} outside the plotted date window` : ''}.`}>
          {supplement && <div className="mb-2 flex justify-end"><SettingControl value={caseSetting} settings={['all', 'match', 'training']} onChange={setCaseSetting} /></div>}
          <div className="overflow-x-auto"><MonthlyCasesChart rows={monthlyRows} /></div>
        </Panel>
        <Panel
          title={supplement ? 'Match incidence by month' : 'Overall incidence by month'}
          description={supplement && matchScope
            ? `Positive-day match cases divided by registered fixture player-hours; ${fmt(matchScope.confirmed_urc_match_cases, 0)} are directly URC-confirmed and ${fmt(matchScope.retained_generic_match_cases, 0)} generic match records are retained because no non-URC marker is present.`
            : 'Approved positive-day cases divided by recorded player-hours for each month.'}
        >
          <div className="overflow-x-auto"><MatchIncidenceChart rows={supplement ? matchMonthly : approvedMonthly} /></div>
        </Panel>
      </div>

      <div className={`grid gap-4 ${supplement ? 'xl:grid-cols-2' : ''}`}>
        <Panel title="Severity distribution" description="Duration bands are shown separately from consequence classification; unknown or censored cases remain visible.">
          <RingBreakdown rows={severityRows} centerLabel="cases" cohort="Recorded injury cases, grouped by recorded duration" valueLabel="cases" />
        </Panel>
        {supplement && <Panel title="Contact vs non-contact" description="Positive-day cases only; unknown mechanism is retained rather than imputed.">
          <div className="mb-2 flex justify-end">
            <Segmented value={contactSetting} options={['all', 'match', 'training'].map((value) => ({ value: value as typeof contactSetting, label: value === 'all' ? 'Overall' : value[0].toUpperCase() + value.slice(1) }))} onChange={setContactSetting} label="Choose contact setting" />
          </div>
          <RingBreakdown rows={contactRows} centerLabel="positive-day" cohort={`${contactSetting === 'all' ? 'All settings' : contactSetting} positive-day cases, with unknown mechanism retained`} valueLabel="cases" />
        </Panel>}
      </div>

      {supplement && <InferenceCoverageSummary supplement={supplement} />}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {highlights.map(([title, row, metric]) => (
          <HighlightCard key={title} title={title} row={row} metric={metric} />
        ))}
      </div>
    </div>
  );
}

function OverviewStat({ label, value, unit, info }: { label: string; value: string; unit?: string; info?: string }) {
  return (
    <div className="border-b border-r border-border/60 p-4 last:border-r-0 sm:border-b-0">
      <div className="flex items-center justify-between gap-1">
        <p className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">{label}</p>
        {info && <MetricInfo label={label}>{info}</MetricInfo>}
      </div>
      <p className="mt-2 text-2xl font-semibold tabular-nums text-foreground sm:text-3xl">{value}</p>
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
    <Panel
      title="Draft V3 classification coverage"
      description="This preview shows where the draft has evidence for each descriptive field. Unknowns are retained, not guessed."
    >
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
    </Panel>
  );
}

function SettingPanel({ title, row }: { title: string; row?: SettingMetricRow }) {
  return (
    <Panel className="relative overflow-hidden">
      <div className="absolute inset-y-0 left-0 w-1 bg-primary" aria-hidden="true" />
      <div className="pl-2">
        <p className="text-sm font-semibold uppercase tracking-wider text-primary">{title}</p>
        <div className="mt-4 grid grid-cols-3 gap-3">
          <SettingValue label="Incidence" value={fmt(row?.incidence_per_1000h)} unit="injuries /1,000 h" info="Time-loss injuries per 1,000 player-hours for this setting." />
          <SettingValue label="Burden" value={fmt(row?.burden_per_1000h)} unit="days /1,000 h" info="Recorded days lost per 1,000 player-hours for this setting." />
          <SettingValue label="Positive-day cases" value={fmt(row?.time_loss_injuries, 0)} />
        </div>
      </div>
    </Panel>
  );
}

function SettingValue({ label, value, unit, info }: { label: string; value: string; unit?: string; info?: string }) {
  return (
    <div>
      <div className="flex items-center gap-1">
        <p className="text-xs text-muted-foreground">{label}</p>
        {info && <MetricInfo label={label}>{info}</MetricInfo>}
      </div>
      <p className="mt-1 text-xl font-semibold tabular-nums text-foreground sm:text-2xl">{value}</p>
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
      <div className="h-1" style={{ backgroundColor: row ? profileColor(row.code) : 'hsl(var(--border))' }} />
      <CardContent className="p-4">
        <p className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">{title}</p>
        <p className="mt-3 min-h-10 text-base font-semibold leading-tight text-foreground">{row?.label ?? 'Not available'}</p>
        <p className="mt-3 text-sm tabular-nums text-muted-foreground">
          <strong className="text-lg text-foreground">{row ? fmt(row[metric]) : 'Not available'}</strong>{' '}
          {row && meta.shortUnit}
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
  const settings = availableSettings(source, ['match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'match');
  const rows = source
    .filter((row) => row.setting === setting)
    .sort((a, b) => b.time_loss_injuries - a.time_loss_injuries || a.label.localeCompare(b.label));

  return (
    <div>
      <SectionHeading title="Common Injuries" description="Diagnosis-level profiles with count, incidence, burden and mean severity shown together." />
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <SettingControl value={setting} settings={settings.length ? settings : ['match', 'training']} onChange={setSetting} />
        {supplement && (
          <p className="text-xs text-muted-foreground">
            High-confidence rules classify {fmt(supplement.diagnosis_coverage.classified_time_loss_injuries, 0)} of {fmt(supplement.diagnosis_coverage.eligible_time_loss_injuries, 0)} positive-day cases; unmatched cases are not guessed.
          </p>
        )}
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
          <div className="flex items-center p-4">
            <h3 className="text-base font-semibold leading-snug text-foreground">{row.label}</h3>
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
    <div className="border-r border-border/50 p-3 last:border-r-0">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="mt-1 text-base font-semibold tabular-nums text-foreground">{value}</p>
      {unit && <p className="text-[10px] text-muted-foreground">{unit}</p>}
    </div>
  );
}

type ComparisonMetric = 'incidence_per_1000h' | 'burden_per_1000h';

function ComparisonRowTooltip({
  id,
  row,
  setting,
  metric,
}: {
  id: string;
  row?: TeamComparisonRow;
  setting: 'match' | 'training';
  metric: ComparisonMetric;
}) {
  const metricRow = row?.[setting];
  const metricLabel = metric === 'incidence_per_1000h' ? 'Incidence' : 'Burden';
  const unit = metric === 'incidence_per_1000h' ? 'injuries /1,000 h' : 'days /1,000 h';
  return (
    <div id={id} role="tooltip" aria-live="polite" className="mb-3 rounded-md border border-border bg-popover px-3 py-2 text-xs leading-relaxed text-popover-foreground shadow-lg">
      {row && metricRow ? (
        <>
          <p className="font-semibold text-foreground">{row.team_alias}</p>
          <p className="mt-0.5 text-foreground"><span className="font-medium">{metricLabel}:</span> <span className="tabular-nums">{fmt(metricRow[metric])} {unit}</span></p>
          <p className="mt-1 text-muted-foreground">{setting[0].toUpperCase() + setting.slice(1)} cohort. n = {fmt(metricRow.time_loss_injuries, 0)} time-loss cases; {fmtHours(metricRow.exposure_hours)} player-hours.</p>
        </>
      ) : 'Focus, hover, or tap a club row to inspect its exact rate and cohort.'}
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
  const [setting, setSetting] = useState<'match' | 'training'>('match');
  const [metric, setMetric] = useState<ComparisonMetric>('incidence_per_1000h');
  const [hoveredId, setHoveredId] = useState<string>();
  const [selectedId, setSelectedId] = useState<string>();
  const tooltipId = useId();
  const benchmark = leagueMetrics.find((row) => row.setting === setting);
  const ranked = [...rows]
    .filter((row) => row[setting]?.[metric] != null)
    .sort((a, b) => (b[setting]?.[metric] ?? 0) - (a[setting]?.[metric] ?? 0));
  const max = Math.max(...ranked.map((row) => row[setting]?.[metric] ?? 0), 1);
  const activeId = hoveredId ?? selectedId ?? ranked[0]?.comparison_id;
  const activeRow = rows.find((row) => row.comparison_id === activeId);

  if (!rows.length) return <EmptyState>No approved team comparison rows are available.</EmptyState>;
  return (
    <div>
      <SectionHeading title="Team Comparison" description="Approved club rates against the pooled league rate. Display aliases protect identities. Lower is green and higher is red." />
      <div className="mb-4 grid grid-cols-2 overflow-hidden rounded-lg border border-border/70 bg-card/70 lg:grid-cols-4">
        <OverviewStat label="League match incidence" value={fmt(leagueMetrics.find((row) => row.setting === 'match')?.incidence_per_1000h)} unit="injuries /1,000 h" info="Time-loss injuries per 1,000 match player-hours across the approved league cohort." />
        <OverviewStat label="League match burden" value={fmt(leagueMetrics.find((row) => row.setting === 'match')?.burden_per_1000h)} unit="days /1,000 h" info="Recorded days lost per 1,000 match player-hours across the approved league cohort." />
        <OverviewStat label="League training incidence" value={fmt(leagueMetrics.find((row) => row.setting === 'training')?.incidence_per_1000h)} unit="injuries /1,000 h" info="Time-loss injuries per 1,000 training player-hours across the approved league cohort." />
        <OverviewStat label="League training burden" value={fmt(leagueMetrics.find((row) => row.setting === 'training')?.burden_per_1000h)} unit="days /1,000 h" info="Recorded days lost per 1,000 training player-hours across the approved league cohort." />
      </div>
      <div className="grid gap-4 xl:grid-cols-[minmax(360px,0.8fr)_minmax(620px,1.2fr)]">
        <Panel title="League standings">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <Segmented value={setting} options={[{ value: 'match', label: 'Match' }, { value: 'training', label: 'Training' }]} onChange={setSetting} label="Choose comparison setting" />
            <Segmented value={metric} options={[{ value: 'incidence_per_1000h', label: 'Incidence' }, { value: 'burden_per_1000h', label: 'Burden' }]} onChange={setMetric} label="Choose comparison metric" />
          </div>
          <ComparisonRowTooltip id={tooltipId} row={activeRow} setting={setting} metric={metric} />
          <div className="max-h-[500px] space-y-1 overflow-y-auto pr-1">
            {ranked.map((row, index) => {
              const value = row[setting]?.[metric] ?? 0;
              return (
                <button
                  key={row.comparison_id}
                  type="button"
                  aria-describedby={tooltipId}
                  aria-label={`${row.team_alias}, ${setting} ${metric === 'incidence_per_1000h' ? 'incidence' : 'burden'}: ${fmt(value)} ${metric === 'incidence_per_1000h' ? 'injuries per 1,000 player-hours' : 'days per 1,000 player-hours'}`}
                  onMouseEnter={() => setHoveredId(row.comparison_id)}
                  onMouseLeave={() => setHoveredId(undefined)}
                  onFocus={() => setHoveredId(row.comparison_id)}
                  onBlur={() => setHoveredId(undefined)}
                  onClick={() => setSelectedId(row.comparison_id)}
                  className={`grid min-h-11 w-full grid-cols-[24px_minmax(92px,0.7fr)_minmax(90px,1fr)_70px] items-center gap-2 rounded px-2 text-left text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${activeId === row.comparison_id ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
                >
                  <span className="tabular-nums text-muted-foreground">{index + 1}</span>
                  <span className="truncate font-medium text-foreground">{row.team_alias}</span>
                  <span className="h-2 overflow-hidden rounded-full bg-muted"><span className="block h-full rounded-full bg-primary" style={{ width: `${value / max * 100}%` }} /></span>
                  <span className="text-right font-semibold tabular-nums text-foreground">{fmt(value)}</span>
                </button>
              );
            })}
          </div>
          <p className="mt-3 border-t border-border/60 pt-3 text-xs text-muted-foreground">League benchmark: {fmt(benchmark?.[metric])} {metric === 'incidence_per_1000h' ? 'injuries /1,000 h' : 'days /1,000 h'}</p>
        </Panel>
        <Panel title="Relative to league average" description="Each cell shows the percentage difference from the pooled league rate. Thresholds are ±10%." className="min-w-0">
          <div className="overflow-x-auto pb-1">
            <table className="w-full min-w-[560px] table-fixed text-xs">
              <thead className="text-muted-foreground">
                <tr>
                  <th className="w-[18%] px-1.5 pb-2 text-left font-medium">Team</th>
                  <th className="w-[20.5%] px-1.5 pb-2 text-right font-medium leading-tight">Match incidence</th>
                  <th className="w-[20.5%] px-1.5 pb-2 text-right font-medium leading-tight">Match burden</th>
                  <th className="w-[20.5%] px-1.5 pb-2 text-right font-medium leading-tight">Training incidence</th>
                  <th className="w-[20.5%] px-1.5 pb-2 text-right font-medium leading-tight">Training burden</th>
                </tr>
              </thead>
              <tbody>
                {[...rows].sort((a, b) => a.team_alias.localeCompare(b.team_alias)).map((row) => (
                  <tr key={row.comparison_id} className={`border-t border-border/40 ${activeId === row.comparison_id ? 'bg-muted/40' : ''}`}>
                    <td className="px-1.5 py-1.5 font-medium text-foreground">
                      <button
                        type="button"
                        aria-describedby={tooltipId}
                        onMouseEnter={() => setHoveredId(row.comparison_id)}
                        onMouseLeave={() => setHoveredId(undefined)}
                        onFocus={() => setHoveredId(row.comparison_id)}
                        onBlur={() => setHoveredId(undefined)}
                        onClick={() => setSelectedId(row.comparison_id)}
                        className="min-h-11 rounded px-1 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        {row.team_alias}
                      </button>
                    </td>
                    <BenchmarkCell value={row.match?.incidence_per_1000h} average={leagueMetrics.find((item) => item.setting === 'match')?.incidence_per_1000h} />
                    <BenchmarkCell value={row.match?.burden_per_1000h} average={leagueMetrics.find((item) => item.setting === 'match')?.burden_per_1000h} />
                    <BenchmarkCell value={row.training?.incidence_per_1000h} average={leagueMetrics.find((item) => item.setting === 'training')?.incidence_per_1000h} />
                    <BenchmarkCell value={row.training?.burden_per_1000h} average={leagueMetrics.find((item) => item.setting === 'training')?.burden_per_1000h} />
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-3 flex flex-wrap gap-4 border-t border-border/60 pt-3 text-[11px] text-muted-foreground">
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
    return <td className="px-2 py-1.5 text-right text-muted-foreground">Not available</td>;
  }
  const delta = (value - average) / average * 100;
  const tone = delta <= -10 ? 'bg-emerald-500/20 text-emerald-100' : delta >= 10 ? 'bg-red-500/20 text-red-100' : 'bg-amber-400/20 text-amber-100';
  return <td className={`px-2 py-1.5 text-right font-semibold tabular-nums ${tone}`}>{delta > 0 ? '+' : ''}{fmt(delta)}%</td>;
}

function ExposureRowTooltip({ id, row }: { id: string; row?: TeamComparisonRow }) {
  return (
    <div id={id} role="tooltip" aria-live="polite" className="mb-3 rounded-md border border-border bg-popover px-3 py-2 text-xs leading-relaxed text-popover-foreground shadow-lg">
      {row ? (
        <>
          <p className="font-semibold text-foreground">{row.team_alias}</p>
          <p className="mt-0.5 text-foreground"><span className="font-medium">Total exposure:</span> <span className="tabular-nums">{fmtHours(row.exposure_hours)} player-hours</span></p>
          <p className="mt-1 text-muted-foreground">Approved total exposure. Match: {fmtHours(row.match_hours)} player-hours. Training: {fmtHours(row.training_hours)} player-hours.</p>
        </>
      ) : 'Focus, hover, or tap a club row to inspect its exact exposure denominator.'}
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
      <SectionHeading title="Exposure" description="Player-hours show the workload used for rates. Match and training denominators stay separate." />
      <div className="grid grid-cols-2 overflow-hidden rounded-lg border border-border/70 bg-card/70 lg:grid-cols-4">
        <OverviewStat label="Total exposure" value={fmtHours(dashboard.coverage.hours)} unit="player-hours" />
        <OverviewStat label="Match exposure" value={fmtHours(dashboard.coverage.match_hours)} unit="player-hours" />
        <OverviewStat label="Training exposure" value={fmtHours(dashboard.coverage.training_hours)} unit="player-hours" />
        <OverviewStat label="Distance" value={fmt(dashboard.coverage.distance_km)} unit="km" />
      </div>
      <div className="mt-4 grid gap-4 xl:grid-cols-[minmax(0,1.15fr)_minmax(380px,0.85fr)]">
        <Panel title="Exposure by month" description="Monthly player-hours. Inspect a point for the exact denominator in that month.">
          <div className="overflow-x-auto"><ExposureTrendChart rows={dashboard.monthly} /></div>
        </Panel>
        <Panel title="Club exposure comparison" description="Approved player-hour denominators. Bar length represents total exposure; display aliases protect club identities.">
          {sorted.length ? (
            <>
              <ExposureRowTooltip id={tooltipId} row={activeRow} />
              <div className="max-h-[520px] space-y-1 overflow-y-auto pr-1">
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
                    className={`grid min-h-11 w-full grid-cols-[24px_minmax(88px,0.8fr)_minmax(80px,1fr)_76px] items-center gap-2 rounded px-2 text-left text-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${activeId === row.comparison_id ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
                  >
                    <span className="text-muted-foreground">{index + 1}</span>
                    <span className="truncate font-medium text-foreground">{row.team_alias}</span>
                    <span className="h-2 overflow-hidden rounded-full bg-muted"><span className="block h-full rounded-full bg-emerald-400" style={{ width: `${row.exposure_hours / max * 100}%` }} /></span>
                    <span className="text-right font-semibold tabular-nums text-foreground">{fmtHours(row.exposure_hours)}</span>
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
      <SectionHeading title="Injury Location" description="Choose a measure, then tap, hover, or focus a bar or body region for the exact value and cohort." />
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
    <div className="mt-4 grid gap-3 rounded-lg border border-border/70 bg-card/70 p-4 sm:grid-cols-[minmax(150px,1fr)_repeat(3,minmax(0,1fr))]">
      <div className="self-center">
        <p className="text-xs uppercase tracking-wider text-muted-foreground">Selected location</p>
        <p className="mt-1 font-semibold text-foreground">{row?.label ?? 'Not available'}</p>
      </div>
      <SettingValue label="Injuries" value={fmt(row?.time_loss_injuries, 0)} />
      <SettingValue label="Incidence" value={fmt(row?.incidence_per_1000h)} unit="injuries /1,000 h" info="Time-loss injuries per 1,000 player-hours for this body location." />
      <SettingValue label="Burden" value={fmt(row?.burden_per_1000h)} unit="days /1,000 h" info="Recorded days lost per 1,000 player-hours for this body location." />
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
      <div id={tooltipId} role="tooltip" aria-live="polite" className="mb-3 rounded-md border border-border bg-popover px-3 py-2 text-xs leading-relaxed text-popover-foreground shadow-lg">
        {activeRow ? (
          <>
            <span className="font-semibold text-foreground">{activeRow.label}</span>
            <span className="mx-1 text-muted-foreground">:</span>
            <span className="font-medium tabular-nums text-foreground">{fmt(activeRow[metric])} {meta.longUnit}</span>
            <span className="block mt-0.5 text-muted-foreground">{activeRow.setting === 'all' ? 'All settings' : activeRow.setting} cohort. n = {fmt(activeRow.time_loss_injuries, 0)} time-loss cases. Tap, hover, or focus a bar to inspect it.</span>
          </>
        ) : 'Tap, hover, or focus a bar to inspect its exact value.'}
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
            className="group grid min-h-11 w-full grid-cols-[minmax(76px,0.42fr)_minmax(64px,1fr)_auto] items-center gap-2 rounded px-1 text-left sm:gap-3 sm:px-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <span className={`truncate text-xs sm:text-sm ${active ? 'font-semibold text-foreground' : 'text-muted-foreground'}`}>{row.label}</span>
            <span className="h-5 overflow-hidden rounded-sm bg-background/70">
              <span
                className="block h-full rounded-sm bg-primary"
                style={{ width: `${Math.max((value / max) * 100, value > 0 ? 2 : 0)}%`, opacity: active ? 1 : activeCode ? 0.28 : 0.75 }}
              />
            </span>
            <span className="min-w-14 text-right text-xs font-semibold tabular-nums text-foreground">{fmt(row[metric])}</span>
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
      <SectionHeading title="Injury Types" description="The 10 tissue and pathology groups with the largest selected measure. Unknowns remain separate rather than being inferred." />
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <SettingControl value={setting} settings={settings.length ? settings : ['all']} onChange={setSetting} />
        <MetricControl value={metric} onChange={setMetric} />
      </div>
      {rows.length ? (
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1.25fr)_minmax(300px,0.75fr)]">
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
            <div className="flex items-center gap-3">
              <span className="h-12 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: activeRow ? profileColor(activeRow.code) : 'hsl(var(--border))' }} />
              <p className="text-lg font-semibold text-foreground">{activeRow?.label ?? 'Not available'}</p>
            </div>
            <div className="mt-5 grid grid-cols-2 overflow-hidden rounded-md border border-border/60">
              <ProfileValue label="Count" value={fmt(activeRow?.time_loss_injuries, 0)} />
              <ProfileValue label="Incidence" value={fmt(activeRow?.incidence_per_1000h)} unit="injuries /1,000 h" />
              <ProfileValue label="Burden" value={fmt(activeRow?.burden_per_1000h)} unit="days /1,000 h" />
              <ProfileValue label="Severity" value={fmt(activeRow?.mean_severity_days)} unit="days" />
            </div>
            <p className="mt-4 text-xs leading-relaxed text-muted-foreground">Select or hover a row to inspect its full metric profile.</p>
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
      <SectionHeading title="Injury Impact" description="Compare frequency and average time lost. Larger bubbles mean more days lost per 1,000 player-hours." />
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
  const profiles = dashboard.injury_profiles ?? [];
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
