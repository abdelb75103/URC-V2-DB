'use client';

import { useMemo, useState } from 'react';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  LabelList,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ReferenceArea,
  ReferenceLine,
  ResponsiveContainer,
  Scatter,
  ScatterChart,
  Tooltip,
  XAxis,
  YAxis,
  ZAxis,
} from 'recharts';
import type { AnalyticsRow, InjuryProfileRow, MonthlySettingRow } from '@/lib/reporting-types';

const AXIS = 'hsl(0 0% 75%)';
const GRID = 'hsl(205 44% 25% / 0.55)';
const TOOLTIP_STYLE = {
  background: 'hsl(var(--popover))',
  border: '1px solid hsl(var(--border))',
  borderRadius: 8,
  color: 'hsl(var(--popover-foreground))',
  boxShadow: '0 12px 28px hsl(205 47% 7% / 0.35)',
};

export const SETTING_COLORS = {
  all: '#02d5f0',
  match: '#02d5f0',
  training: '#42d8b4',
  unknown: '#94a3b8',
} as const;

export const PROFILE_COLORS = [
  '#02d5f0',
  '#42d8b4',
  '#72a7ff',
  '#ffc45c',
  '#ef7189',
  '#a78bfa',
  '#8bd450',
  '#fb923c',
];

export function profileColor(code: string) {
  let hash = 0;
  for (const char of code) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return PROFILE_COLORS[hash % PROFILE_COLORS.length];
}

function number(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: digits,
    minimumFractionDigits: Number.isInteger(value) ? 0 : digits,
  }).format(value);
}

function count(value: number | null | undefined) {
  return number(value, 0);
}

function hours(value: number | null | undefined) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
  }).format(value);
}

function compactMonth(value: string) {
  return value.replace(/\s\d{4}$/, '');
}

function monthOrder(value: string) {
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? value : parsed;
}

function sortSeasonMonths<T extends { month: string }>(rows: T[]) {
  return [...rows].sort((a, b) => {
    const aOrder = monthOrder(a.month);
    const bOrder = monthOrder(b.month);
    return typeof aOrder === 'number' && typeof bOrder === 'number'
      ? aOrder - bOrder
      : String(aOrder).localeCompare(String(bOrder));
  });
}

function settingLabel(setting: MonthlySettingRow['setting'] | InjuryProfileRow['setting'] | undefined) {
  if (setting === 'all') return 'overall';
  if (setting === 'unknown') return 'unknown setting';
  return setting ?? 'all recorded settings';
}

function TooltipCard({
  title,
  cohort,
  rows,
}: {
  title: string;
  cohort: string;
  rows: Array<{ label: string; value: string }>;
}) {
  return (
    <div className="max-w-[min(18rem,calc(100vw-2rem))] rounded-md border border-border bg-popover px-3 py-2 text-xs text-popover-foreground shadow-xl">
      <p className="font-semibold text-foreground">{title}</p>
      <dl className="mt-1.5 space-y-1">
        {rows.map((row) => (
          <div key={row.label} className="grid grid-cols-[minmax(0,1fr)_auto] gap-4">
            <dt className="text-muted-foreground">{row.label}</dt>
            <dd className="text-right font-medium tabular-nums text-foreground">{row.value}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-2 border-t border-border/70 pt-2 leading-snug text-muted-foreground">{cohort}</p>
    </div>
  );
}

function CasesTooltip({
  active,
  label,
  payload,
}: {
  active?: boolean;
  label?: string;
  payload?: Array<{ payload?: MonthlySettingRow }>;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  const hasRecordedCases = typeof row.recorded_injuries === 'number';
  return (
    <TooltipCard
      title={`${label ?? row.month} - ${settingLabel(row.setting)}`}
      rows={hasRecordedCases ? [
        { label: 'Recorded injury cases', value: `${count(row.recorded_injuries)} cases` },
        { label: 'Time-loss cases', value: `${count(row.time_loss_injuries)} cases` },
      ] : [
        { label: 'Time-loss cases', value: `${count(row.time_loss_injuries)} cases` },
      ]}
      cohort={hasRecordedCases
        ? `${settingLabel(row.setting)} dated cases in ${label ?? row.month}. n = ${count(row.recorded_injuries)} recorded cases.`
        : `${settingLabel(row.setting)} dated time-loss cases in ${label ?? row.month}. n = ${count(row.time_loss_injuries)} cases.`}
    />
  );
}

function IncidenceTooltip({
  active,
  label,
  payload,
}: {
  active?: boolean;
  label?: string;
  payload?: Array<{ payload?: MonthlySettingRow }>;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  return (
    <TooltipCard
      title={`${label ?? row.month} - ${settingLabel(row.setting)}`}
      rows={[
        { label: 'Incidence', value: `${number(row.incidence_per_1000h)} injuries /1,000 h` },
        { label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` },
        { label: 'Time-loss cases', value: `${count(row.rate_time_loss_injuries)} cases` },
      ]}
      cohort={`${settingLabel(row.setting)} rate cohort in ${label ?? row.month}. n = ${count(row.rate_time_loss_injuries)} time-loss cases.`}
    />
  );
}

function ExposureTooltip({
  active,
  label,
  payload,
}: {
  active?: boolean;
  label?: string;
  payload?: Array<{ payload?: AnalyticsRow }>;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  return (
    <TooltipCard
      title={`${label ?? row.month ?? 'Month'} - all recorded settings`}
      rows={[{ label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` }]}
      cohort={`Monthly player-hours for ${label ?? row.month ?? 'this period'}. Match and training denominators stay separate in rate views.`}
    />
  );
}

export function MonthlyCasesChart({ rows }: { rows: MonthlySettingRow[] }) {
  const data = useMemo(() => sortSeasonMonths(rows), [rows]);
  if (!data.length) return <ChartEmpty reason="No dated injury cases are available for the selected setting." />;
  const hasRecordedCases = data.every((row) => typeof row.recorded_injuries === 'number');

  return (
    <div
      className="h-[286px] min-w-[540px]"
      aria-label={hasRecordedCases ? 'Monthly recorded and time-loss injury cases chart' : 'Monthly time-loss injury cases chart'}
    >
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart accessibilityLayer data={data} margin={{ top: 34, right: 14, bottom: 28, left: 12 }}>
          <defs>
            <linearGradient id="recordedCases" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={SETTING_COLORS.all} stopOpacity={0.34} />
              <stop offset="100%" stopColor={SETTING_COLORS.all} stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={compactMonth}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            label={{ value: 'Month', position: 'insideBottom', fill: AXIS, fontSize: 12, offset: -12 }}
          />
          <YAxis
            allowDecimals={false}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            label={{ value: 'Injury cases (n)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 0 }}
          />
          <Tooltip
            content={<CasesTooltip />}
            cursor={{ stroke: 'hsl(var(--primary) / 0.55)', strokeWidth: 1 }}
            allowEscapeViewBox={{ x: false, y: false }}
            wrapperStyle={{ zIndex: 30 }}
          />
          <Legend verticalAlign="top" height={22} wrapperStyle={{ fontSize: 11, paddingTop: 0 }} />
          {hasRecordedCases && <Area
            type="monotone"
            dataKey="recorded_injuries"
            name="Recorded cases"
            stroke={SETTING_COLORS.all}
            fill="url(#recordedCases)"
            strokeWidth={2}
            activeDot={{ r: 5, strokeWidth: 2 }}
            isAnimationActive={false}
          />}
          <Line
            type="monotone"
            dataKey="time_loss_injuries"
            name="Time-loss cases"
            stroke="#ffc45c"
            strokeWidth={2.5}
            dot={{ r: 3, strokeWidth: 1.5 }}
            activeDot={{ r: 5, strokeWidth: 2 }}
            isAnimationActive={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

export function MatchIncidenceChart({ rows }: { rows: MonthlySettingRow[] }) {
  const data = useMemo(
    () => sortSeasonMonths(rows.filter((row) => row.exposure_hours !== null && row.incidence_per_1000h !== null)),
    [rows]
  );
  if (!data.length) return <ChartEmpty reason="No month has both an exposure denominator and an incidence rate for this view." />;

  return (
    <div className="h-[286px] min-w-[540px]" aria-label="Monthly injury incidence chart">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart accessibilityLayer data={data} margin={{ top: 12, right: 14, bottom: 28, left: 24 }}>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={compactMonth}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            label={{ value: 'Month', position: 'insideBottom', fill: AXIS, fontSize: 12, offset: -12 }}
          />
          <YAxis
            tickFormatter={formatAxisTick}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            label={{ value: 'Injuries /1,000 h', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 7 }}
          />
          <Tooltip
            content={<IncidenceTooltip />}
            cursor={{ stroke: SETTING_COLORS.match, strokeWidth: 1 }}
            allowEscapeViewBox={{ x: false, y: false }}
            wrapperStyle={{ zIndex: 30 }}
          />
          <Line
            type="monotone"
            dataKey="incidence_per_1000h"
            name="Incidence"
            stroke={SETTING_COLORS.match}
            strokeWidth={2.5}
            dot={{ r: 3, strokeWidth: 1.5 }}
            activeDot={{ r: 5, strokeWidth: 2 }}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}

export type RingDatum = { key: string; label: string; value: number };

function RingTooltip({
  active,
  payload,
  cohort,
  valueLabel,
}: {
  active?: boolean;
  payload?: Array<{ payload?: RingDatum }>;
  cohort: string;
  valueLabel: string;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  return (
    <TooltipCard
      title={row.label}
      rows={[{ label: valueLabel, value: `${count(row.value)} ${valueLabel}` }]}
      cohort={`${cohort}. n = ${count(row.value)} ${valueLabel}.`}
    />
  );
}

export function RingBreakdown({
  rows,
  centerLabel,
  cohort = 'Selected injury cohort',
  valueLabel = 'cases',
}: {
  rows: RingDatum[];
  centerLabel: string;
  cohort?: string;
  valueLabel?: string;
}) {
  const data = rows.filter((row) => row.value > 0);
  const total = data.reduce((sum, row) => sum + row.value, 0);
  const [selectedKey, setSelectedKey] = useState<string>();
  const selected = data.find((row) => row.key === selectedKey) ?? data[0];
  if (!data.length) return <ChartEmpty compact reason={`No ${valueLabel} are available for this breakdown.`} />;

  return (
    <div className="grid items-center gap-3 sm:grid-cols-[170px_1fr]">
      <div className="relative mx-auto h-[160px] w-[160px]" aria-label={`${centerLabel} breakdown chart`}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              nameKey="label"
              cx="50%"
              cy="50%"
              innerRadius={48}
              outerRadius={72}
              paddingAngle={1.5}
              stroke="none"
              isAnimationActive={false}
              onMouseEnter={(_, index: number) => setSelectedKey(data[index]?.key)}
              onClick={(_, index: number) => setSelectedKey(data[index]?.key)}
            >
              {data.map((row, index) => (
                <Cell
                  key={row.key}
                  fill={PROFILE_COLORS[index % PROFILE_COLORS.length]}
                  opacity={selected && selected.key !== row.key ? 0.42 : 1}
                />
              ))}
            </Pie>
            <Tooltip
              content={<RingTooltip cohort={cohort} valueLabel={valueLabel} />}
              allowEscapeViewBox={{ x: false, y: false }}
              wrapperStyle={{ zIndex: 30 }}
            />
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 grid place-content-center text-center">
          <strong className="text-2xl tabular-nums text-foreground">{count(total)}</strong>
          <span className="text-[10px] uppercase tracking-wider text-muted-foreground">{centerLabel}</span>
        </div>
      </div>
      <div className="space-y-1">
        {selected && (
          <div role="tooltip" aria-live="polite" className="mb-2 rounded-md border border-border bg-popover px-3 py-2 text-xs leading-relaxed text-popover-foreground shadow-lg">
            <span className="font-semibold text-foreground">{selected.label}</span>
            <span className="mx-1 text-muted-foreground">:</span>
            <span className="font-medium tabular-nums text-foreground">{count(selected.value)} {valueLabel}</span>
            <span className="block mt-0.5 text-muted-foreground">{cohort}. n = {count(selected.value)} {valueLabel}. Tap, hover, or focus a segment or row to inspect it.</span>
          </div>
        )}
        {data.map((row, index) => {
          const active = selected?.key === row.key;
          return (
            <button
              key={row.key}
              type="button"
              onMouseEnter={() => setSelectedKey(row.key)}
              onFocus={() => setSelectedKey(row.key)}
              onClick={() => setSelectedKey(row.key)}
              className={`grid min-h-11 w-full grid-cols-[8px_minmax(0,1fr)_auto] items-center gap-2 rounded px-1 text-left text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${active ? 'bg-muted/70' : 'hover:bg-muted/40'}`}
              aria-label={`${row.label}: ${count(row.value)} ${valueLabel}. ${cohort}.`}
            >
              <span className="h-2 w-2 rounded-full" style={{ background: PROFILE_COLORS[index % PROFILE_COLORS.length] }} />
              <span className="truncate text-muted-foreground">{row.label}</span>
              <span className="font-semibold tabular-nums text-foreground">{count(row.value)} <span className="font-normal text-muted-foreground">({Math.round(row.value / total * 100)}%)</span></span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function ExposureTrendChart({ rows }: { rows: AnalyticsRow[] }) {
  const data = useMemo(
    () => sortSeasonMonths(rows.filter((row) => typeof row.exposure_hours === 'number') as Array<AnalyticsRow & { month: string }>),
    [rows]
  );
  if (!data.length) return <ChartEmpty reason="No monthly player-hours are available in the approved exposure data." />;

  return (
    <div className="h-[304px] min-w-[560px]" aria-label="Monthly player-hours chart">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart accessibilityLayer data={data} margin={{ top: 12, right: 14, bottom: 28, left: 30 }}>
          <defs>
            <linearGradient id="exposureHours" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={SETTING_COLORS.training} stopOpacity={0.38} />
              <stop offset="100%" stopColor={SETTING_COLORS.training} stopOpacity={0.03} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={compactMonth}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            label={{ value: 'Month', position: 'insideBottom', fill: AXIS, fontSize: 12, offset: -12 }}
          />
          <YAxis
            tickFormatter={(value) => `${Math.round(value / 1000)}k`}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            label={{ value: 'Player-hours', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 10 }}
          />
          <Tooltip
            content={<ExposureTooltip />}
            cursor={{ stroke: SETTING_COLORS.training, strokeWidth: 1 }}
            allowEscapeViewBox={{ x: false, y: false }}
            wrapperStyle={{ zIndex: 30 }}
          />
          <Area
            type="monotone"
            dataKey="exposure_hours"
            name="Player-hours"
            stroke={SETTING_COLORS.training}
            fill="url(#exposureHours)"
            strokeWidth={2.5}
            activeDot={{ r: 5, strokeWidth: 2 }}
            isAnimationActive={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

function ChartEmpty({ compact = false, reason }: { compact?: boolean; reason: string }) {
  return <div className={`grid place-items-center rounded-md border border-dashed border-border px-6 text-center text-sm leading-relaxed text-muted-foreground ${compact ? 'h-40' : 'h-[260px]'}`}>{reason}</div>;
}

function median(values: number[]) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function ImpactTooltip({
  active,
  payload,
}: {
  active?: boolean;
  payload?: Array<{ payload?: InjuryProfileRow }>;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  return (
    <TooltipCard
      title={row.label}
      rows={[
        { label: 'Incidence', value: `${number(row.incidence_per_1000h)} injuries /1,000 h` },
        { label: 'Mean severity', value: `${number(row.mean_severity_days)} days` },
        { label: 'Burden', value: `${number(row.burden_per_1000h)} days /1,000 h` },
        { label: 'Time-loss cases', value: `${count(row.time_loss_injuries)} cases` },
      ]}
      cohort={`${settingLabel(row.setting)} injury profile. n = ${count(row.time_loss_injuries)} time-loss cases.`}
    />
  );
}

function formatAxisTick(value: number) {
  return number(value);
}

export function ImpactBubbleChart({ rows }: { rows: InjuryProfileRow[] }) {
  const data = rows
    .filter(
      (row) =>
        row.incidence_per_1000h !== null &&
        row.mean_severity_days !== null &&
        row.burden_per_1000h !== null
    )
    .map((row) => ({ ...row, bubble_burden: Math.max(row.burden_per_1000h ?? 0, 0.01) }));

  if (!data.length) {
    return <ChartEmpty reason="No injury profiles have the rate and severity values needed for this chart." />;
  }

  const medianIncidence = median(data.map((row) => row.incidence_per_1000h ?? 0));
  const medianSeverity = median(data.map((row) => row.mean_severity_days ?? 0));
  const maxIncidence = Math.max(...data.map((row) => row.incidence_per_1000h ?? 0)) * 1.12 || 1;
  const maxSeverity = Math.max(...data.map((row) => row.mean_severity_days ?? 0)) * 1.15 || 1;
  const labels = new Set(
    [...data]
      .sort((a, b) => (b.burden_per_1000h ?? 0) - (a.burden_per_1000h ?? 0))
      .slice(0, 4)
      .map((row) => row.code)
  );
  const chartData = data.map((row) => ({ ...row, displayLabel: labels.has(row.code) ? row.label : '' }));

  return (
    <div role="img" aria-label="Injury impact chart. Horizontal position is incidence, vertical position is mean severity, and bubble area is burden. Use the data table below for keyboard inspection of every profile.">
      <div className="overflow-x-auto pb-2">
        <div className="h-[430px] min-w-[680px]">
          <ResponsiveContainer width="100%" height="100%">
            <ScatterChart accessibilityLayer margin={{ top: 30, right: 30, bottom: 34, left: 18 }}>
              <CartesianGrid stroke={GRID} strokeDasharray="3 5" />
              <ReferenceArea
                x1={0}
                x2={medianIncidence}
                y1={0}
                y2={medianSeverity}
                fill="#22c55e"
                fillOpacity={0.08}
                ifOverflow="extendDomain"
              />
              <ReferenceArea
                x1={medianIncidence}
                x2={maxIncidence}
                y1={medianSeverity}
                y2={maxSeverity}
                fill="#ef4444"
                fillOpacity={0.09}
                ifOverflow="extendDomain"
              />
              <ReferenceLine x={medianIncidence} stroke="hsl(0 0% 75% / 0.6)" strokeDasharray="5 5" />
              <ReferenceLine y={medianSeverity} stroke="hsl(0 0% 75% / 0.6)" strokeDasharray="5 5" />
              <XAxis
                type="number"
                dataKey="incidence_per_1000h"
                domain={[0, maxIncidence]}
                name="Incidence"
                tickFormatter={formatAxisTick}
                tick={{ fill: AXIS, fontSize: 11 }}
                tickLine={false}
                axisLine={{ stroke: GRID }}
                label={{ value: 'Incidence, injuries /1,000 h', position: 'bottom', fill: AXIS, fontSize: 12, offset: 16 }}
              />
              <YAxis
                type="number"
                dataKey="mean_severity_days"
                domain={[0, maxSeverity]}
                name="Mean severity"
                tickFormatter={formatAxisTick}
                width={54}
                tick={{ fill: AXIS, fontSize: 11 }}
                tickLine={false}
                axisLine={false}
                label={{ value: 'Mean severity, days', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 0 }}
              />
              <ZAxis type="number" dataKey="bubble_burden" range={[160, 1_100]} name="Burden" />
              <Tooltip cursor={false} content={<ImpactTooltip />} wrapperStyle={{ zIndex: 30 }} />
              <Scatter data={chartData} isAnimationActive={false}>
                {chartData.map((row) => (
                  <Cell key={`${row.setting}-${row.code}`} fill={profileColor(row.code)} fillOpacity={0.72} stroke="hsl(0 0% 96%)" strokeWidth={1.5} strokeOpacity={0.9} />
                ))}
                <LabelList dataKey="displayLabel" position="top" fill="hsl(0 0% 90%)" fontSize={11} />
              </Scatter>
            </ScatterChart>
          </ResponsiveContainer>
        </div>
      </div>
      <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs text-muted-foreground">
        <span><span className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-green-500/50" />Lower frequency and lower severity</span>
        <span>Dashed lines show category medians</span>
        <span><span className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-red-500/50" />Priority: frequent and severe</span>
      </div>
    </div>
  );
}
