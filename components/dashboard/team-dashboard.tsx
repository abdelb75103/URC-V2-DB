'use client';

import { useState, type ReactNode } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import type {
  InjuryProfileRow,
  SettingMetricRow,
  TeamDashboardData,
} from '@/lib/reporting-types';
import { Card, CardContent } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { BodyMap, type LocationMetric } from '@/components/dashboard/body-map';
import { ImpactBubbleChart, profileColor } from '@/components/dashboard/charts';

type ProfileMetric =
  | 'time_loss_injuries'
  | 'incidence_per_1000h'
  | 'burden_per_1000h'
  | 'mean_severity_days';
type Setting = InjuryProfileRow['setting'];

const TABS = [
  ['overview', 'Overview'],
  ['common', 'Common Injuries'],
  ['location', 'Injury Location'],
  ['types', 'Injury Types'],
  ['impact', 'Injury Impact'],
] as const;

const METRICS: Array<{ key: ProfileMetric; label: string; shortUnit: string }> = [
  { key: 'time_loss_injuries', label: 'Count', shortUnit: 'injuries' },
  { key: 'incidence_per_1000h', label: 'Incidence', shortUnit: '/1,000h' },
  { key: 'burden_per_1000h', label: 'Burden', shortUnit: 'days/1,000h' },
  { key: 'mean_severity_days', label: 'Severity', shortUnit: 'days' },
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

function metricValue(row: InjuryProfileRow, metric: ProfileMetric) {
  const value = row[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function metricMeta(metric: ProfileMetric) {
  return METRICS.find((item) => item.key === metric) ?? METRICS[0];
}

function Panel({ title, description, children, className = '' }: {
  title?: string;
  description?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <Card className={`border-border/70 bg-card/70 shadow-none ${className}`}>
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

function SectionHeading({ title, description }: { title: string; description: string }) {
  return (
    <div className="mb-5">
      <h2 className="text-xl font-semibold text-foreground sm:text-2xl">{title}</h2>
      <p className="mt-1 max-w-2xl text-sm text-muted-foreground">{description}</p>
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
    <div aria-label={label} className="inline-flex max-w-full gap-1 overflow-x-auto rounded-md border border-border bg-background/50 p-1">
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
    <Segmented
      value={value}
      options={settings.map((setting) => ({
        value: setting,
        label: setting === 'all' ? 'Overall' : setting[0].toUpperCase() + setting.slice(1),
      }))}
      onChange={onChange}
      label="Choose setting"
    />
  );
}

function EmptyState({ children = 'No data available for this view.' }: { children?: ReactNode }) {
  return <div className="grid min-h-40 place-items-center rounded-md border border-dashed border-border p-6 text-center text-sm text-muted-foreground">{children}</div>;
}

function OverviewTab({ dashboard, profiles }: { dashboard: TeamDashboardData; profiles: InjuryProfileRow[] }) {
  const headline = Object.fromEntries(dashboard.headline.map((row) => [row.key, row.value]));
  const all = dashboard.setting_metrics.find((row) => row.setting === 'all');
  const match = dashboard.setting_metrics.find((row) => row.setting === 'match');
  const training = dashboard.setting_metrics.find((row) => row.setting === 'training');
  const diagnosisRows = profiles.some((row) => row.dimension === 'injury_profile')
    ? profiles.filter((row) => row.dimension === 'injury_profile')
    : profiles.filter((row) => row.dimension === 'injury_type');
  const highlights = [
    ['Most common match injury', topRow(diagnosisRows, 'match', 'incidence_per_1000h'), 'incidence_per_1000h'],
    ['Most common training injury', topRow(diagnosisRows, 'training', 'incidence_per_1000h'), 'incidence_per_1000h'],
    ['Highest match burden', topRow(diagnosisRows, 'match', 'burden_per_1000h'), 'burden_per_1000h'],
    ['Highest training burden', topRow(diagnosisRows, 'training', 'burden_per_1000h'), 'burden_per_1000h'],
  ] as const;
  const locations = profiles
    .filter((row) => row.dimension === 'body_location' && row.setting === 'all')
    .sort((a, b) => b.time_loss_injuries - a.time_loss_injuries)
    .slice(0, 5);
  const types = profiles
    .filter((row) => row.dimension === 'injury_type' && row.setting === 'all')
    .sort((a, b) => b.time_loss_injuries - a.time_loss_injuries)
    .slice(0, 5);

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 overflow-hidden rounded-lg border border-border/70 bg-card/70 sm:grid-cols-4">
        <OverviewStat label="Time-loss injuries" value={fmt(headline.time_loss_injuries ?? all?.time_loss_injuries, 0)} />
        <OverviewStat label="Incidence" value={fmt(headline.incidence_per_1000h ?? all?.incidence_per_1000h)} unit="/1,000h" />
        <OverviewStat label="Burden" value={fmt(headline.burden_per_1000h ?? all?.burden_per_1000h)} unit="days/1,000h" />
        <OverviewStat label="Exposure" value={fmt(dashboard.coverage.hours)} unit="player-hours" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <SettingPanel title="Match" row={match} />
        <SettingPanel title="Training" row={training} />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {highlights.map(([title, row, metric]) => (
          <HighlightCard key={title} title={title} row={row} metric={metric} />
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Injury locations" description="Leading IOC body locations by time-loss injury count.">
          <CompactRanking rows={locations} />
        </Panel>
        <Panel title="Injury types" description="Leading IOC tissue and pathology groups by time-loss injury count.">
          <CompactRanking rows={types} />
        </Panel>
      </div>
    </div>
  );
}

function OverviewStat({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div className="border-b border-r border-border/60 p-4 last:border-r-0 sm:border-b-0">
      <p className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="mt-2 text-2xl font-semibold tabular-nums text-foreground sm:text-3xl">{value}</p>
      {unit && <p className="mt-1 text-xs text-muted-foreground">{unit}</p>}
    </div>
  );
}

function SettingPanel({ title, row }: { title: string; row?: SettingMetricRow }) {
  return (
    <Panel className="relative overflow-hidden">
      <div className="absolute inset-y-0 left-0 w-1 bg-primary" aria-hidden="true" />
      <div className="pl-2">
        <p className="text-sm font-semibold uppercase tracking-wider text-primary">{title}</p>
        <div className="mt-4 grid grid-cols-3 gap-3">
          <SettingValue label="Incidence" value={fmt(row?.incidence_per_1000h)} unit="/1,000h" />
          <SettingValue label="Burden" value={fmt(row?.burden_per_1000h)} unit="days/1,000h" />
          <SettingValue label="Injuries" value={fmt(row?.time_loss_injuries, 0)} />
        </div>
      </div>
    </Panel>
  );
}

function SettingValue({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
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

function CommonInjuriesTab({ profiles }: { profiles: InjuryProfileRow[] }) {
  const source = profiles.some((row) => row.dimension === 'injury_profile')
    ? profiles.filter((row) => row.dimension === 'injury_profile')
    : profiles.filter((row) => row.dimension === 'injury_type');
  const settings = availableSettings(source, ['match', 'training', 'all']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'match');
  const [metric, setMetric] = useState<ProfileMetric>('time_loss_injuries');
  const rows = source
    .filter((row) => row.setting === setting)
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label));

  return (
    <div>
      <SectionHeading title="Common Injuries" description="Explore each injury profile across count, incidence, burden and mean severity." />
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <SettingControl value={setting} settings={settings.length ? settings : ['match', 'training']} onChange={setSetting} />
        <MetricControl value={metric} onChange={setMetric} />
      </div>
      {rows.length ? <ProfileCards rows={rows.slice(0, 8)} metric={metric} /> : <EmptyState />}
    </div>
  );
}

function ProfileCards({ rows, metric }: { rows: InjuryProfileRow[]; metric: ProfileMetric }) {
  const meta = metricMeta(metric);
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {rows.map((row) => (
        <article key={`${row.setting}-${row.code}`} className="overflow-hidden rounded-lg border border-border/70 bg-card/70">
          <div className="h-1" style={{ backgroundColor: profileColor(row.code) }} />
          <div className="p-4">
            <h3 className="min-h-10 text-sm font-semibold leading-snug text-foreground">{row.label}</h3>
            <p className="mt-4 text-3xl font-semibold tabular-nums text-foreground">{fmt(row[metric])}</p>
            <p className="mt-1 text-xs text-muted-foreground">{meta.label} {meta.shortUnit}</p>
          </div>
        </article>
      ))}
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
  const activeCode = hoveredCode ?? (rows.some((row) => row.code === selectedCode) ? selectedCode : rows[0]?.code);
  const selected = rows.find((row) => row.code === activeCode);

  return (
    <div>
      <SectionHeading title="Injury Location" description="Body locations follow the IOC 2020 categories from head to foot." />
      <div className="mb-5 flex justify-end">
        <MetricControl value={metric} onChange={setMetric} locationOnly />
      </div>
      {rows.length ? (
        <>
          <div className="grid gap-5 lg:grid-cols-[minmax(0,1.25fr)_minmax(320px,0.75fr)]">
            <Panel title="Head-to-foot profile">
              <MetricBars
                rows={rows}
                metric={metric}
                activeCode={activeCode}
                onHover={setHoveredCode}
                onSelect={setSelectedCode}
              />
            </Panel>
            <Panel title="Body heatmap">
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
      <SettingValue label="Incidence" value={fmt(row?.incidence_per_1000h)} unit="/1,000h" />
      <SettingValue label="Burden" value={fmt(row?.burden_per_1000h)} unit="days/1,000h" />
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
  return (
    <div className="space-y-1">
      {rows.map((row) => {
        const value = metricValue(row, metric);
        const active = activeCode === row.code;
        return (
          <button
            key={row.code}
            type="button"
            title={`${row.label}: ${fmt(row[metric])} ${meta.shortUnit}`}
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
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label));
  const activeCode = hoveredCode ?? (rows.some((row) => row.code === selectedCode) ? selectedCode : rows[0]?.code);
  const activeRow = rows.find((row) => row.code === activeCode);

  return (
    <div>
      <SectionHeading title="Injury Types" description="Compare IOC tissue and pathology groups across the metrics that matter." />
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
          <Panel title="Leading profiles">
            <div className="space-y-2">
              {rows.slice(0, 6).map((row) => (
                <button
                  key={row.code}
                  type="button"
                  onMouseEnter={() => setHoveredCode(row.code)}
                  onMouseLeave={() => setHoveredCode(undefined)}
                  onFocus={() => setHoveredCode(row.code)}
                  onBlur={() => setHoveredCode(undefined)}
                  onClick={() => setSelectedCode(row.code)}
                  className="flex min-h-11 w-full items-center gap-3 rounded px-2 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <span className="h-8 w-1 shrink-0 rounded-full" style={{ backgroundColor: profileColor(row.code) }} />
                  <span className="min-w-0 flex-1 truncate text-sm text-foreground">{row.label}</span>
                  <span className="text-sm font-semibold tabular-nums text-foreground">{fmt(row[metric])}</span>
                </button>
              ))}
            </div>
            <div className="mt-4 border-t border-border/60 pt-4">
              <p className="text-xs uppercase tracking-wider text-muted-foreground">Selected injury type</p>
              <p className="mt-1 font-semibold text-foreground">{activeRow?.label ?? 'Not available'}</p>
              <p className="mt-2 text-sm text-muted-foreground">
                {activeRow ? `${fmt(activeRow.time_loss_injuries, 0)} injuries · ${fmt(activeRow.burden_per_1000h)} days/1,000h burden` : 'No data available'}
              </p>
            </div>
          </Panel>
        </div>
      ) : <EmptyState />}
    </div>
  );
}

function ImpactTab({ profiles }: { profiles: InjuryProfileRow[] }) {
  const source = profiles.some((row) => row.dimension === 'injury_profile')
    ? profiles.filter((row) => row.dimension === 'injury_profile')
    : profiles.filter((row) => row.dimension === 'injury_type');
  const settings = availableSettings(source, ['all', 'match', 'training']);
  const [setting, setSetting] = useState<Setting>(settings[0] ?? 'all');
  const rows = source.filter((row) => row.setting === setting);

  return (
    <div>
      <SectionHeading title="Injury Impact" description="Incidence shows frequency, severity shows time lost per injury, and bubble area represents total burden." />
      <div className="mb-5 flex justify-end">
        <SettingControl value={setting} settings={settings.length ? settings : ['all']} onChange={setSetting} />
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
}: {
  dashboard: TeamDashboardData;
  crest: string;
  teamName: string;
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
          <p className="mt-1 text-sm text-muted-foreground">{scopeLabel} injury and exposure surveillance · {dashboard.season}</p>
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

        <TabsContent value="overview"><OverviewTab dashboard={dashboard} profiles={profiles} /></TabsContent>
        <TabsContent value="common"><CommonInjuriesTab profiles={profiles} /></TabsContent>
        <TabsContent value="location"><LocationTab profiles={profiles} /></TabsContent>
        <TabsContent value="types"><InjuryTypesTab profiles={profiles} /></TabsContent>
        <TabsContent value="impact"><ImpactTab profiles={profiles} /></TabsContent>
      </Tabs>
    </div>
  );
}
