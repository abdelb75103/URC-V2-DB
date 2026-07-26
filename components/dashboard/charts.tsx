'use client';

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ComposedChart,
  LabelList,
  Legend,
  Line,
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
/** Primary axis lines read as a drawn edge, distinct from the fainter grid. */
const AXIS_LINE = { stroke: 'hsl(0 0% 78%)', strokeWidth: 1.5 };
/**
 * Recharts anchors a rotated y-axis title at the axis midpoint and lets it run
 * upward from there, which clips the longer titles. Centring the text on that
 * same midpoint is what keeps them inside the plot.
 */
const Y_TITLE_STYLE = { textAnchor: 'middle' as const };
/** Every chart tooltip shares this surface: slightly transparent, no border. */
const TOOLTIP_SURFACE = { background: 'hsl(205 47% 9% / 0.92)' };

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

const MONTH_NAMES = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/**
 * The zero-based month in a payload label such as `Sep 2024`, or -1.
 *
 * Read from the label itself rather than from `new Date(label)`: Safari rejects
 * `"Sep 2024"` as an invalid date where V8 accepts it, which silently sorted the
 * season alphabetically on iPhone and left the timeline showing September alone.
 * Never reintroduce date parsing of a free-form month label here.
 */
function monthIndex(value: string) {
  const name = value.trim().slice(0, 3).toLowerCase();
  return MONTH_NAMES.indexOf(name);
}

/** A sortable season-order key for a payload month label, or null. */
function monthOrder(value: string) {
  const month = monthIndex(value);
  const year = Number(value.match(/\d{4}/)?.[0]);
  return month < 0 || !Number.isFinite(year) ? null : year * 12 + month;
}

export function sortSeasonMonths<T extends { month: string }>(rows: T[]) {
  return [...rows].sort((a, b) => {
    const aOrder = monthOrder(a.month);
    const bOrder = monthOrder(b.month);
    return aOrder !== null && bOrder !== null ? aOrder - bOrder : a.month.localeCompare(b.month);
  });
}

/**
 * Every monthly chart on the site plots from September (decision, 25 July 2026,
 * site-wide): earlier months sit outside the official analysis window. The month
 * is read from the label by name, never by date parsing. Rows must already be in
 * season order. The charts do not caption the months they drop (decision,
 * 25 July 2026); the pre-window cases stay counted in the headline totals.
 */
export function fromSeptember<T extends { month: string }>(rows: T[]) {
  const first = rows.findIndex((row) => monthIndex(row.month) === 8);
  return first > 0 ? rows.slice(first) : rows;
}

function settingLabel(setting: MonthlySettingRow['setting'] | InjuryProfileRow['setting'] | undefined) {
  if (setting === 'all') return 'overall';
  if (setting === 'unknown') return 'unknown setting';
  return setting ?? 'all recorded settings';
}

export type TooltipRow = { label: string; value: string; color?: string };

/**
 * The one tooltip surface every chart uses: a dark, slightly transparent panel,
 * a bold header naming the category, and one compact row per series drawn in
 * that series' own colour. Nothing else. The cohort footer was removed on
 * 25 July 2026: the hover states the values and stops there.
 */
function TooltipCard({
  title,
  rows,
}: {
  title: string;
  rows: TooltipRow[];
}) {
  return (
    <div
      className="max-w-[min(18rem,calc(100vw-2rem))] rounded-lg px-3 py-2 text-xs shadow-xl backdrop-blur-sm"
      style={TOOLTIP_SURFACE}
    >
      <p className="font-semibold text-white">{title}</p>
      <dl className="mt-1.5 space-y-1">
        {rows.map((row) => (
          <div key={row.label} className="grid grid-cols-[minmax(0,1fr)_auto] gap-4">
            <dt style={row.color ? { color: row.color } : undefined} className={row.color ? undefined : 'text-muted-foreground'}>
              {row.label}
            </dt>
            <dd
              className={`text-right font-semibold tabular-nums ${row.color ? '' : 'text-white'}`}
              style={row.color ? { color: row.color } : undefined}
            >
              {row.value}
            </dd>
          </div>
        ))}
      </dl>
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
      title={label ?? row.month}
      rows={hasRecordedCases ? [
        { label: 'Recorded injury cases', value: `${count(row.recorded_injuries)} cases`, color: SETTING_COLORS.all },
        { label: 'Time-loss cases', value: `${count(row.time_loss_injuries)} cases`, color: '#ffc45c' },
      ] : [
        { label: 'Time-loss cases', value: `${count(row.time_loss_injuries)} cases`, color: '#ffc45c' },
      ]}
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
      title={label ?? row.month}
      rows={[
        { label: 'Incidence', value: `${number(row.incidence_per_1000h)} injuries /1,000 h`, color: SETTING_COLORS.match },
        { label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` },
        { label: 'Time-loss cases', value: `${count(row.rate_time_loss_injuries)} cases` },
      ]}
    />
  );
}

type ExposureMeasure = 'hours' | 'distance' | 'hsr';
type ExposureMonthlyRow = AnalyticsRow & {
  hsr_distance_km?: number;
  hsr_distance_denominator_km?: number;
  match_exposure_hours?: number;
  training_exposure_hours?: number;
  distance_remainder_km?: number;
  hsr_percentage?: number;
};

function exposureMeasureLabel(measure: ExposureMeasure) {
  if (measure === 'hours') return 'Player-hours';
  if (measure === 'distance') return 'Distance';
  return 'HSR distance';
}

function exposureMeasureUnit(measure: ExposureMeasure) {
  return measure === 'hours' ? 'player-hours' : 'km';
}

function MonthlyExposureTooltip({
  active,
  label,
  payload,
  measure,
}: {
  active?: boolean;
  label?: string;
  payload?: Array<{ payload?: ExposureMonthlyRow }>;
  measure: ExposureMeasure;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  const distance = row.distance_km ?? 0;
  const hsrDistanceDenominator = row.hsr_distance_denominator_km ?? 0;
  const hsrDistance = row.hsr_distance_km ?? 0;
  const rows: TooltipRow[] = measure === 'hours'
    ? typeof row.match_exposure_hours === 'number' && typeof row.training_exposure_hours === 'number'
      ? [
          { label: 'Match', value: `${hours(row.match_exposure_hours)} player-hours`, color: SETTING_COLORS.match },
          { label: 'Training', value: `${hours(row.training_exposure_hours)} player-hours`, color: SETTING_COLORS.training },
          { label: 'Total', value: `${hours(row.exposure_hours)} player-hours` },
        ]
      : [{ label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` }]
    : measure === 'distance' && hsrDistanceDenominator > 0
      ? [
          { label: 'Total distance', value: `${number(distance)} km` },
          { label: 'Distance with HSR data', value: `${number(hsrDistanceDenominator)} km`, color: SETTING_COLORS.all },
          { label: 'HSR distance', value: `${number(hsrDistance)} km`, color: '#f59e0b' },
          { label: 'HSR share', value: `${number(hsrDistanceDenominator > 0 ? hsrDistance / hsrDistanceDenominator * 100 : 0, 1)}%`, color: '#f59e0b' },
        ]
      : measure === 'distance'
        ? [{ label: 'Total distance', value: `${number(distance)} km`, color: SETTING_COLORS.all }]
        : [{ label: 'HSR distance', value: `${number(hsrDistance)} km`, color: '#f59e0b' }];
  return <TooltipCard title={label ?? row.month ?? 'Month'} rows={rows} />;
}

function formatHsrPercentage(value: unknown) {
  return typeof value === 'number' && value > 0 ? `${number(value, 1)}%` : '';
}

export function MonthlyCasesChart({ rows }: { rows: MonthlySettingRow[] }) {
  const data = useMemo(() => fromSeptember(sortSeasonMonths(rows)), [rows]);
  if (!data.length) return <ChartEmpty reason="No dated injury cases are available for the selected setting." />;
  const hasRecordedCases = data.every((row) => typeof row.recorded_injuries === 'number');

  return (
    <div
      className="h-[286px] sm:min-w-[540px]"
      aria-label={hasRecordedCases ? 'Monthly recorded and time-loss injury cases chart' : 'Monthly time-loss injury cases chart'}
    >
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart accessibilityLayer data={data} margin={{ top: 70, right: 14, bottom: 28, left: 18 }}>
          <defs>
            <linearGradient id="recordedCases" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={SETTING_COLORS.all} stopOpacity={0.34} />
              <stop offset="100%" stopColor={SETTING_COLORS.all} stopOpacity={0.02} />
            </linearGradient>
            <linearGradient id="timeLossCases" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#ffc45c" stopOpacity={0.30} />
              <stop offset="100%" stopColor="#ffc45c" stopOpacity={0.01} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={compactMonth}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Month', position: 'insideBottom', fill: AXIS, fontSize: 12, offset: -12 }}
          />
          <YAxis
            allowDecimals={false}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Injury cases (n)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 0, style: Y_TITLE_STYLE }}
          />
          <Tooltip
            content={<CasesTooltip />}
            cursor={{ stroke: 'hsl(var(--primary) / 0.55)', strokeWidth: 1 }}
            allowEscapeViewBox={{ x: false, y: false }}
            position={{ x: 14, y: 10 }}
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
          <Area
            type="monotone"
            dataKey="time_loss_injuries"
            name="Time-loss cases"
            stroke="#ffc45c"
            fill="url(#timeLossCases)"
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
    () => fromSeptember(sortSeasonMonths(rows.filter((row) => row.exposure_hours !== null && row.incidence_per_1000h !== null))),
    [rows]
  );
  if (!data.length) return <ChartEmpty reason="No month has both an exposure denominator and an incidence rate for this view." />;

  return (
    <div className="h-[286px] sm:min-w-[540px]" aria-label="Monthly injury incidence chart">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart accessibilityLayer data={data} margin={{ top: 70, right: 14, bottom: 28, left: 24 }}>
          <defs>
            <linearGradient id="incidenceRate" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={SETTING_COLORS.match} stopOpacity={0.34} />
              <stop offset="100%" stopColor={SETTING_COLORS.match} stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={compactMonth}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Month', position: 'insideBottom', fill: AXIS, fontSize: 12, offset: -12 }}
          />
          <YAxis
            tickFormatter={formatAxisTick}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Injuries /1,000 h', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 7, style: Y_TITLE_STYLE }}
          />
          <Tooltip
            content={<IncidenceTooltip />}
            cursor={{ stroke: SETTING_COLORS.match, strokeWidth: 1 }}
            allowEscapeViewBox={{ x: false, y: false }}
            position={{ x: 14, y: 10 }}
            wrapperStyle={{ zIndex: 30 }}
          />
          <Area
            type="monotone"
            dataKey="incidence_per_1000h"
            name="Incidence"
            stroke={SETTING_COLORS.match}
            fill="url(#incidenceRate)"
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

export type RingDatum = { key: string; label: string; value: number; color?: string };

export function RingBreakdown({
  rows,
  centerLabel,
  valueLabel = 'cases',
}: {
  rows: RingDatum[];
  centerLabel: string;
  valueLabel?: string;
}) {
  const data = rows.filter((row) => row.value > 0);
  const total = data.reduce((sum, row) => sum + row.value, 0);
  const [selectedKey, setSelectedKey] = useState<string>();
  const selected = data.find((row) => row.key === selectedKey) ?? data[0];
  if (!data.length) return <ChartEmpty compact reason={`No ${valueLabel} are available for this breakdown.`} />;

  return (
    <div className="grid items-start gap-4 sm:grid-cols-[184px_minmax(0,1fr)]">
      <div className="relative mx-auto h-[176px] w-[176px]" aria-label={`${centerLabel} breakdown chart`}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              nameKey="label"
              cx="50%"
              cy="50%"
              innerRadius={55}
              outerRadius={79}
              paddingAngle={1.5}
              stroke="none"
              isAnimationActive={false}
              onMouseEnter={(_, index: number) => setSelectedKey(data[index]?.key)}
              onClick={(_, index: number) => setSelectedKey(data[index]?.key)}
            >
              {data.map((row, index) => (
                <Cell
                  key={row.key}
                  fill={row.color ?? PROFILE_COLORS[index % PROFILE_COLORS.length]}
                  opacity={selectedKey && selected?.key !== row.key ? 0.42 : 1}
                />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 grid place-content-center text-center">
          <strong className="text-2xl font-semibold leading-none tabular-nums text-primary">{count(selected?.value)}</strong>
          <span className="mt-1 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">{valueLabel}</span>
        </div>
      </div>
      <div className="space-y-1">
        {selected && (
          <span aria-live="polite" className="sr-only">{selected.label}: {count(selected.value)} {valueLabel}.</span>
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
              aria-label={`${row.label}: ${count(row.value)} ${valueLabel}.`}
            >
              <span className="h-2 w-2 rounded-full" style={{ background: row.color ?? PROFILE_COLORS[index % PROFILE_COLORS.length] }} />
              <span className="truncate text-muted-foreground">{row.label}</span>
              <span className="font-semibold tabular-nums text-foreground">{count(row.value)} <span className="font-normal text-muted-foreground">({Math.round(row.value / total * 100)}%)</span></span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export const SEVERITY_BAND_COLORS: Record<string, string> = {
  zero: '#94a3b8',
  one_to_seven: '#02d5f0',
  eight_to_twenty_eight: '#ffc45c',
  greater_than_twenty_eight: '#ef7189',
};

export function Sparkline({
  values,
  color = SETTING_COLORS.all,
  ariaLabel,
}: {
  values: Array<number | null>;
  color?: string;
  ariaLabel: string;
}) {
  const points = values.filter((value): value is number => typeof value === 'number' && Number.isFinite(value));
  if (points.length < 2) return <div className="h-8" aria-hidden="true" />;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = max - min || 1;
  const width = 100;
  const height = 30;
  const step = width / (points.length - 1);
  const coords = points.map((value, index) => [index * step, height - ((value - min) / span) * (height - 4) - 2] as const);
  const line = coords.map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${x.toFixed(2)},${y.toFixed(2)}`).join(' ');
  const area = `${line} L${width},${height} L0,${height} Z`;
  const gradientId = `spark-${ariaLabel.replace(/\W+/g, '-').toLowerCase()}`;
  const [lastX, lastY] = coords[coords.length - 1];

  return (
    <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" className="h-8 w-full" role="img" aria-label={ariaLabel}>
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity={0.3} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#${gradientId})`} stroke="none" />
      <path d={line} fill="none" stroke={color} strokeWidth={1.5} vectorEffect="non-scaling-stroke" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={lastX} cy={lastY} r={2} fill={color} vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function TimelineTooltip({
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
  const rows: TooltipRow[] = [{ label: 'Time-loss cases', value: `${count(row.time_loss_injuries)} cases`, color: SETTING_COLORS.all }];
  if (typeof row.recorded_injuries === 'number') {
    rows.unshift({ label: 'Recorded cases', value: `${count(row.recorded_injuries)} cases` });
  }
  if (typeof row.incidence_per_1000h === 'number') {
    rows.push({ label: 'Incidence', value: `${number(row.incidence_per_1000h)} /1,000 h`, color: '#ffc45c' });
    rows.push({ label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` });
  }
  return (
    <TooltipCard
      title={label ?? row.month}
      rows={rows}
    />
  );
}

export function SeasonTimelineChart({
  rows,
  showCases,
  showIncidence,
}: {
  rows: MonthlySettingRow[];
  showCases: boolean;
  showIncidence: boolean;
}) {
  const data = useMemo(() => fromSeptember(sortSeasonMonths(rows)), [rows]);
  if (!data.length) return <ChartEmpty reason="No dated injury cases are available for the selected setting." />;
  if (!showCases && !showIncidence) return <ChartEmpty reason="Select at least one series to plot." />;
  const hasIncidence = data.some((row) => typeof row.incidence_per_1000h === 'number');

  return (
    <div className="h-[320px] sm:min-w-[560px]" aria-label="Season timeline of injury cases and incidence">
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart accessibilityLayer data={data} margin={{ top: 12, right: 16, bottom: 32, left: 12 }}>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={compactMonth}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Month', position: 'insideBottom', fill: AXIS, fontSize: 11, offset: -14 }}
          />
          <YAxis
            yAxisId="cases"
            allowDecimals={false}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Cases (n)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 11, offset: 4, style: Y_TITLE_STYLE }}
          />
          <YAxis
            yAxisId="rate"
            orientation="right"
            tickFormatter={formatAxisTick}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: '/1,000 h', angle: 90, position: 'insideRight', fill: AXIS, fontSize: 11, offset: 8, style: Y_TITLE_STYLE }}
          />
          <Tooltip
            content={<TimelineTooltip />}
            cursor={{ fill: 'hsl(var(--primary) / 0.08)' }}
            wrapperStyle={{ zIndex: 30 }}
          />
          {showCases && (
            <Bar
              yAxisId="cases"
              dataKey="time_loss_injuries"
              name="Time-loss cases"
              fill={SETTING_COLORS.all}
              fillOpacity={0.45}
              radius={[3, 3, 0, 0]}
              maxBarSize={34}
              isAnimationActive={false}
            />
          )}
          {showIncidence && hasIncidence && (
            <Line
              yAxisId="rate"
              type="monotone"
              dataKey="incidence_per_1000h"
              name="Incidence"
              stroke="#ffc45c"
              strokeWidth={2.5}
              dot={{ r: 3, strokeWidth: 1.5 }}
              activeDot={{ r: 5, strokeWidth: 2 }}
              connectNulls
              isAnimationActive={false}
            />
          )}
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

export function SeverityArc({ rows }: { rows: RingDatum[] }) {
  const data = rows.filter((row) => row.value > 0);
  const total = data.reduce((sum, row) => sum + row.value, 0);
  const [selectedKey, setSelectedKey] = useState<string>();
  const selected = data.find((row) => row.key === selectedKey);
  if (!data.length) return <ChartEmpty compact reason="No classified cases are available for this breakdown." />;

  return (
    <div>
      <div className="relative mx-auto h-[124px] w-full max-w-[240px]" aria-label="Severity band breakdown">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              dataKey="value"
              nameKey="label"
              cx="50%"
              cy="98%"
              startAngle={180}
              endAngle={0}
              innerRadius={72}
              outerRadius={106}
              paddingAngle={1.5}
              stroke="none"
              isAnimationActive={false}
              onMouseEnter={(_, index: number) => setSelectedKey(data[index]?.key)}
              onClick={(_, index: number) => setSelectedKey(data[index]?.key)}
            >
              {data.map((row, index) => (
                <Cell
                  key={row.key}
                  fill={row.color ?? PROFILE_COLORS[index % PROFILE_COLORS.length]}
                  opacity={selectedKey && selected?.key !== row.key ? 0.4 : 1}
                />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-x-0 bottom-1 text-center">
          <strong className="block text-2xl font-semibold leading-none tabular-nums text-primary">{count(selected?.value ?? total)}</strong>
          <span className="mt-1 block text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
            {selected ? 'cases' : 'total cases'}
          </span>
        </div>
      </div>
      <div className="mt-3 flex items-center justify-between px-1 text-[10px] uppercase tracking-wide text-muted-foreground">
        <span>Least severe</span>
        <span>Most severe</span>
      </div>
      <div className="mt-1 space-y-1">
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
              aria-label={`${row.label}: ${count(row.value)} cases.`}
            >
              <span className="h-2 w-2 rounded-full" style={{ background: row.color ?? PROFILE_COLORS[index % PROFILE_COLORS.length] }} />
              <span className="truncate text-muted-foreground">{row.label}</span>
              <span className="font-semibold tabular-nums text-foreground">
                {count(row.value)} <span className="font-normal text-muted-foreground">({Math.round((row.value / total) * 100)}%)</span>
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function ExposureTrendChart({ rows, measure = 'hours', totalHoursColor = SETTING_COLORS.training }: {
  rows: ExposureMonthlyRow[];
  measure?: ExposureMeasure;
  /** Club identity colour for the single-series player-hours bars only. */
  totalHoursColor?: string;
}) {
  const data = useMemo(() => {
    const sorted = sortSeasonMonths<ExposureMonthlyRow & { month: string }>(rows
      .filter((row) => {
        if (!row.month) return false;
        if (measure === 'hours') return typeof row.exposure_hours === 'number';
        if (measure === 'distance') return typeof row.distance_km === 'number';
        return typeof row.hsr_distance_km === 'number';
      })
      .map((row) => ({
        ...row,
        distance_remainder_km: Math.max(
          (row.hsr_distance_denominator_km ?? row.distance_km ?? 0) - (row.hsr_distance_km ?? 0),
          0,
        ),
        hsr_percentage: (row.hsr_distance_denominator_km ?? 0) > 0
          ? (row.hsr_distance_km ?? 0) / (row.hsr_distance_denominator_km ?? 1) * 100
          : 0,
      })) as Array<ExposureMonthlyRow & { month: string }>);
    // Pre-September months go first, then the leading unreported months, so a club
    // whose reporting starts later still opens on its own first reported month.
    const inWindow = fromSeptember(sorted);
    const firstReportedMonth = inWindow.findIndex((row) => (
      measure === 'hours' ? (row.exposure_hours ?? 0) : measure === 'distance' ? (row.distance_km ?? 0) : (row.hsr_distance_km ?? 0)
    ) > 0);
    return firstReportedMonth < 0 ? [] : inWindow.slice(firstReportedMonth);
  }, [measure, rows]);
  if (!data.length) {
    const description = `No monthly ${measure === 'hours' ? 'player-hours' : measure === 'distance' ? 'distance' : 'HSR distance'} are available.`;
    return <ChartEmpty reason={description} />;
  }

  const unit = exposureMeasureUnit(measure);
  return (
    // The plot keeps its fixed height, but the unit and the pre-window note sit
    // outside it: inside, they overflowed the box and landed on the panel below.
    <div className="w-full min-w-0">
    <div className="h-[286px] w-full min-w-0" aria-label={`Monthly ${exposureMeasureLabel(measure).toLowerCase()} chart`}>
      <ResponsiveContainer width="100%" height="100%">
        <BarChart aria-label={`Monthly ${exposureMeasureLabel(measure).toLowerCase()} chart`} accessibilityLayer data={data} margin={{ top: 30, right: 10, bottom: 18, left: 16 }} barCategoryGap="24%">
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis dataKey="month" tickFormatter={compactMonth} interval="preserveStartEnd" minTickGap={8} tick={{ fill: AXIS, fontSize: 10 }} tickLine={false} axisLine={AXIS_LINE} />
          <YAxis tickFormatter={(value) => measure === 'hours' && value >= 1000 ? `${Math.round(value / 1000)}k` : number(value, 0)} tick={{ fill: AXIS, fontSize: 11 }} tickLine={false} axisLine={AXIS_LINE} width={42} />
          <Tooltip content={<MonthlyExposureTooltip measure={measure} />} cursor={{ fill: 'hsl(var(--muted) / 0.5)' }} allowEscapeViewBox={{ x: false, y: false }} wrapperStyle={{ zIndex: 30 }} />
          {measure === 'hours' && typeof data[0]?.match_exposure_hours === 'number' ? (
            <>
              <Legend verticalAlign="top" height={26} iconType="square" />
              <Bar dataKey="match_exposure_hours" name="Match" stackId="hours" fill={SETTING_COLORS.match} isAnimationActive={false} />
              <Bar dataKey="training_exposure_hours" name="Training" stackId="hours" fill={SETTING_COLORS.training} radius={[3, 3, 0, 0]} isAnimationActive={false} />
            </>
          ) : measure === 'hours' ? (
            <Bar dataKey="exposure_hours" name="Player-hours" fill={totalHoursColor} radius={[3, 3, 0, 0]} isAnimationActive={false} />
          ) : measure === 'distance' && typeof data[0]?.hsr_distance_denominator_km === 'number' ? (
            <>
              <Legend verticalAlign="top" height={26} iconType="square" />
              {/* HSR sits on top of the stack so its share can be labelled above the
                  whole bar, in the HSR colour, instead of inside the blue remainder. */}
              <Bar dataKey="distance_remainder_km" name="Other reported distance" stackId="distance" fill={SETTING_COLORS.all} isAnimationActive={false} />
              <Bar dataKey="hsr_distance_km" name="HSR distance" stackId="distance" fill="#f59e0b" radius={[3, 3, 0, 0]} isAnimationActive={false}>
                <LabelList dataKey="hsr_percentage" position="top" formatter={formatHsrPercentage} fill="#f59e0b" fontSize={10} fontWeight={600} />
              </Bar>
            </>
          ) : measure === 'distance' ? (
            <Bar dataKey="distance_km" name="Total distance" fill={SETTING_COLORS.all} radius={[3, 3, 0, 0]} isAnimationActive={false} />
          ) : (
            <Bar dataKey="hsr_distance_km" name="HSR distance" fill="#f59e0b" radius={[3, 3, 0, 0]} isAnimationActive={false} />
          )}
        </BarChart>
      </ResponsiveContainer>
    </div>
      <p className="mt-1 text-right text-[11px] text-muted-foreground">{unit}</p>
      </div>
  );
}

const SCATTER_NARROW_BELOW = 640;

export type ComparisonScatterRow = {
  comparison_id: string;
  label: string;
  match_incidence: number;
  training_incidence: number;
  exposure_hours: number;
  is_viewer: boolean;
};

function ComparisonScatterTooltip({
  active,
  payload,
}: {
  active?: boolean;
  payload?: Array<{ payload?: ComparisonScatterRow }>;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  return (
    <TooltipCard
      title={row.label}
      rows={[
        { label: 'Match incidence', value: `${number(row.match_incidence, 2)} /1,000 h`, color: SETTING_COLORS.match },
        { label: 'Training incidence', value: `${number(row.training_incidence, 2)} /1,000 h`, color: SETTING_COLORS.training },
        { label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` },
      ]}
    />
  );
}

/**
 * Match against training incidence, one dot per club. Every value is read from
 * the approved comparison payload: positions are the released rates, dot area is
 * released exposure, and the crosshairs are the released league means.
 */
export function ComparisonScatterChart({
  rows,
  leagueMatchIncidence,
  leagueTrainingIncidence,
  viewerColor = 'hsl(var(--primary))',
}: {
  rows: ComparisonScatterRow[];
  leagueMatchIncidence?: number | null;
  leagueTrainingIncidence?: number | null;
  viewerColor?: string;
}) {
  const others = rows.filter((row) => !row.is_viewer);
  const viewer = rows.filter((row) => row.is_viewer);
  const boxRef = useRef<HTMLDivElement>(null);
  const [narrow, setNarrow] = useState(false);
  useLayoutEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    const measure = () => setNarrow(box.clientWidth > 0 && box.clientWidth < SCATTER_NARROW_BELOW);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(box);
    return () => observer.disconnect();
  }, []);
  if (!rows.length) {
    return <ChartEmpty reason="No club has both a match and a training incidence in the approved comparison payload." />;
  }
  const pad = (values: number[]) => [0, Math.max(...values) * 1.15 || 1] as [number, number];
  // The training mean is labelled at the right-hand end of its line in both
  // layouts. Wide puts it outside the plot, which costs a right margin big enough
  // to hold the whole string (~102px at fontSize 10, plus the 5px offset). On a
  // phone that margin would cost a third of the card, so the label moves inside
  // the plot, still right-aligned, and the plot takes the width back.
  const trainingLabel = narrow
    ? { value: 'League training mean', position: 'insideTopRight' as const, fill: SETTING_COLORS.training, fontSize: 10 }
    : { value: 'League training mean', position: 'right' as const, fill: SETTING_COLORS.training, fontSize: 10 };

  return (
    <section aria-label="Match against training incidence for every club. Horizontal position is match incidence, vertical position is training incidence, and dot area is reported exposure.">
      <div className="pb-2" ref={boxRef}>
        <div className="h-[360px] sm:min-w-[620px]">
          <ResponsiveContainer width="100%" height="100%">
            <ScatterChart accessibilityLayer margin={{ top: 34, right: narrow ? 16 : 116, bottom: 32, left: 14 }}>
              <CartesianGrid stroke={GRID} strokeDasharray="3 5" />
              <XAxis
                type="number"
                dataKey="match_incidence"
                name="Match incidence"
                domain={pad(rows.map((row) => row.match_incidence))}
                tickFormatter={formatAxisTick}
                tick={{ fill: AXIS, fontSize: 11 }}
                tickLine={false}
                axisLine={AXIS_LINE}
                label={{ value: 'Match incidence, injuries /1,000 h', position: 'bottom', fill: AXIS, fontSize: 12, offset: 14 }}
              />
              <YAxis
                type="number"
                dataKey="training_incidence"
                name="Training incidence"
                domain={pad(rows.map((row) => row.training_incidence))}
                tickFormatter={formatAxisTick}
                width={50}
                tick={{ fill: AXIS, fontSize: 11 }}
                tickLine={false}
                axisLine={AXIS_LINE}
                label={{ value: 'Training incidence, injuries /1,000 h', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 2, style: Y_TITLE_STYLE }}
              />
              <ZAxis type="number" dataKey="exposure_hours" range={[70, 620]} name="Exposure" />
              <Tooltip content={<ComparisonScatterTooltip />} cursor={{ stroke: GRID }} wrapperStyle={{ zIndex: 30 }} />
              {/* Each league mean is drawn in the colour of the axis it belongs to,
                  and labelled outside the plot so it cannot collide with a club dot. */}
              {typeof leagueMatchIncidence === 'number' && (
                <ReferenceLine
                  x={leagueMatchIncidence}
                  stroke={SETTING_COLORS.match}
                  strokeDasharray="4 4"
                  strokeOpacity={0.85}
                  label={{ value: 'League match mean', position: 'top', fill: SETTING_COLORS.match, fontSize: 10 }}
                />
              )}
              {typeof leagueTrainingIncidence === 'number' && (
                <ReferenceLine
                  y={leagueTrainingIncidence}
                  stroke={SETTING_COLORS.training}
                  strokeDasharray="4 4"
                  strokeOpacity={0.85}
                  label={trainingLabel}
                />
              )}
              <Scatter
                data={others}
                fill={SETTING_COLORS.all}
                fillOpacity={0.5}
                stroke="hsl(0 0% 96%)"
                strokeOpacity={0.55}
                isAnimationActive={false}
              />
              {viewer.length > 0 && (
                <Scatter
                  data={viewer}
                  fill={viewerColor}
                  fillOpacity={0.92}
                  stroke="hsl(0 0% 100%)"
                  strokeWidth={2}
                  isAnimationActive={false}
                >
                  <LabelList dataKey="label" position="top" fill="hsl(0 0% 96%)" fontSize={11} />
                </Scatter>
              )}
            </ScatterChart>
          </ResponsiveContainer>
        </div>
      </div>
    </section>
  );
}

function ChartEmpty({ compact = false, reason }: { compact?: boolean; reason: string }) {
  return <div className={`grid place-items-center rounded-md border border-dashed border-border px-6 text-center text-sm leading-relaxed text-muted-foreground ${compact ? 'h-40' : 'h-[260px]'}`}>{reason}</div>;
}

function ImpactTooltip({
  row,
  pinned,
  id,
}: {
  row?: InjuryProfileRow;
  pinned: boolean;
  id: string;
}) {
  if (!row) return null;
  const caution = row.time_loss_injuries === 1
    ? 'Caution: based on 1 injury'
    : row.time_loss_injuries === 2
      ? 'Small sample: interpret 2 injuries cautiously'
      : '';

  const color = profileColor(row.code);
  return (
    <div
      id={id}
      role="tooltip"
      aria-live="polite"
      className="w-[min(18rem,calc(100vw-2rem))] rounded-lg px-3 py-2 text-xs shadow-xl backdrop-blur-sm"
      style={TOOLTIP_SURFACE}
    >
      <p className="font-semibold text-white">{row.label}</p>
      <dl className="mt-1.5 space-y-1">
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-4">
          <dt style={{ color }}>Burden</dt>
          <dd className="text-right font-semibold tabular-nums" style={{ color }}>{number(row.burden_per_1000h)} days /1,000 h</dd>
        </div>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-4">
          <dt style={{ color }}>Incidence</dt>
          <dd className="text-right font-semibold tabular-nums" style={{ color }}>{number(row.incidence_per_1000h)} /1,000 h</dd>
        </div>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-4">
          <dt style={{ color }}>Mean severity</dt>
          <dd className="text-right font-semibold tabular-nums" style={{ color }}>{number(row.mean_severity_days)} days</dd>
        </div>
      </dl>
      <p className="mt-2 text-[11px] leading-snug text-muted-foreground">{settingLabel(row.setting)} · n = {count(row.time_loss_injuries)} time-loss {row.time_loss_injuries === 1 ? 'injury' : 'injuries'} · {count(row.days_lost)} total days lost{caution && ` · ${caution}`}{pinned && ' · Pinned, press Escape to dismiss'}</p>
    </div>
  );
}

function formatAxisTick(value: number) {
  return number(value);
}

const IMPACT_LOG_SEVERITY_BASE_DOMAIN = [1, 400] as const;
const IMPACT_LOG_SEVERITY_BASE_TICKS = [1, 2, 5, 10, 20, 50, 100, 200, 400];

function isPlottableLogSeverity(value: number | null): value is number {
  return value !== null && Number.isFinite(value) && value > 0;
}

function logSeverityDomain(maximum: number): [number, number] {
  return [IMPACT_LOG_SEVERITY_BASE_DOMAIN[0], Math.max(IMPACT_LOG_SEVERITY_BASE_DOMAIN[1], 10 ** Math.ceil(Math.log10(maximum)))];
}

function logSeverityTicks(domainMaximum: number) {
  if (domainMaximum === IMPACT_LOG_SEVERITY_BASE_DOMAIN[1]) return IMPACT_LOG_SEVERITY_BASE_TICKS;
  const ticks = Array.from({ length: Math.ceil(Math.log10(domainMaximum)) + 1 }, (_, exponent) => [1, 2, 5].map((multiple) => multiple * 10 ** exponent))
    .flat()
    .filter((tick) => tick <= domainMaximum);
  return ticks.at(-1) === domainMaximum ? ticks : [...ticks, domainMaximum];
}

type ImpactChartRow = InjuryProfileRow & {
  bubble_burden: number;
  displayLabel: string;
  labelDy: number;
  impactKey: string;
};

/**
 * The bubble chart's inner plot box in its own pixel space. Tied to the
 * `h-[430px]` container and the `{ top: 30, right: 30, bottom: 34, left: 24 }`
 * margins plus the 62px y-axis width below: change either and this must change
 * with it, or the labels drift off their dots. The width is measured at runtime
 * from the container, because the chart is `min-w-[680px]` but stretches, and a
 * fixed width would misjudge every horizontal collision above that size.
 */
const IMPACT_LABEL_BOX = { left: 86, right: 30, top: 30, minWidth: 564, height: 366 };
/** Matches the chart's ZAxis range, so a label clears its own bubble. */
const IMPACT_BUBBLE_SIZE = [160, 1_100] as const;

/** A profile the log-scaled bubble chart can place at all. */
function isPlottableImpactRow(row: InjuryProfileRow) {
  return row.incidence_per_1000h !== null
    && Number.isFinite(row.incidence_per_1000h)
    && row.burden_per_1000h !== null
    && Number.isFinite(row.burden_per_1000h)
    && isPlottableLogSeverity(row.mean_severity_days);
}

const QUADRANT_DIVIDER = 'hsl(0 0% 100% / 0.28)';
/**
 * Read as a traffic light on the two plotted axes: red where both are above the
 * split, green where both are below, amber for the mixed corners. The labels are
 * comparative ("more frequent", "shorter absences") because the split is a median
 * of the plotted profiles, not an absolute threshold: a profile just below the
 * line is not low, only lower than its peers. Fills stay faint enough that a
 * bubble sitting on one is still the strongest thing in the cell.
 */
const IMPACT_QUADRANTS = [
  {
    key: 'high-low',
    top: true,
    right: false,
    label: 'Longer absences · Less frequent',
    fill: 'hsl(43 92% 58% / 0.16)',
    swatch: 'hsl(43 92% 58% / 0.7)',
    labelFill: 'hsl(43 90% 76%)',
    labelPosition: 'insideTopLeft' as const,
  },
  {
    key: 'high-high',
    top: true,
    right: true,
    label: 'Longer absences · More frequent',
    fill: 'hsl(0 74% 54% / 0.22)',
    swatch: 'hsl(0 74% 54% / 0.75)',
    labelFill: 'hsl(0 84% 80%)',
    labelPosition: 'insideTopRight' as const,
  },
  {
    key: 'low-low',
    top: false,
    right: false,
    label: 'Shorter absences · Less frequent',
    fill: 'hsl(150 62% 45% / 0.2)',
    swatch: 'hsl(150 62% 48% / 0.75)',
    labelFill: 'hsl(150 62% 74%)',
    labelPosition: 'insideBottomLeft' as const,
  },
  {
    key: 'low-high',
    top: false,
    right: true,
    label: 'Shorter absences · More frequent',
    fill: 'hsl(43 92% 58% / 0.16)',
    swatch: 'hsl(43 92% 58% / 0.7)',
    labelFill: 'hsl(43 90% 76%)',
    labelPosition: 'insideBottomRight' as const,
  },
];

type ImpactPointPosition = {
  row: ImpactChartRow;
  x: number;
  y: number;
};

type ImpactBubbleShapeProps = {
  cx?: number;
  cy?: number;
  size?: number;
  payload?: ImpactChartRow;
};

function ImpactBubble({
  cx,
  cy,
  size,
  payload,
  pinnedKey,
  onPreview,
  onFocusPreview,
  onLeave,
  onBlur,
  onPin,
  onDismiss,
  onPosition,
  tooltipId,
}: ImpactBubbleShapeProps & {
  pinnedKey?: string;
  onPreview: (point: ImpactPointPosition) => void;
  onFocusPreview: (point: ImpactPointPosition) => void;
  onLeave: () => void;
  onBlur: () => void;
  onPin: (point: ImpactPointPosition) => void;
  onDismiss: () => void;
  onPosition: (point: ImpactPointPosition) => void;
  tooltipId: string;
}) {
  useLayoutEffect(() => {
    if (cx !== undefined && cy !== undefined && payload) onPosition({ row: payload, x: cx, y: cy });
  }, [cx, cy, onPosition, payload]);

  if (cx === undefined || cy === undefined || !payload) return null;
  const radius = Math.sqrt(Math.max(size ?? 0, 0) / Math.PI);
  const point = { row: payload, x: cx, y: cy };
  const selected = pinnedKey === payload.impactKey;
  const accessibleLabel = `${payload.label}, ${settingLabel(payload.setting)}. Burden ${number(payload.burden_per_1000h)} days per 1,000 hours. ${selected ? 'Pinned. Press Escape to dismiss.' : 'Press Enter or Space to pin.'}`;

  return (
    <g>
      {selected && <circle cx={cx} cy={cy} r={radius + 5} fill="none" stroke="hsl(var(--foreground))" strokeWidth={2} strokeOpacity={0.9} pointerEvents="none" />}
      <circle cx={cx} cy={cy} r={radius} fill={profileColor(payload.code)} fillOpacity={0.72} stroke="hsl(0 0% 96%)" strokeWidth={1.5} strokeOpacity={0.9} pointerEvents="none" />
      <circle
        cx={cx}
        cy={cy}
        r={22}
        fill="transparent"
        tabIndex={0}
        role="button"
        aria-label={accessibleLabel}
        aria-describedby={tooltipId}
        aria-pressed={selected}
        data-impact-key={payload.impactKey}
        onMouseEnter={() => onPreview(point)}
        onMouseLeave={onLeave}
        onFocus={() => onFocusPreview(point)}
        onBlur={onBlur}
        onPointerDown={(event) => {
          event.stopPropagation();
          onPin(point);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Escape') {
            event.preventDefault();
            onDismiss();
          }
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            onPin(point);
          }
        }}
      />
    </g>
  );
}

/**
 * `rows` are the bubbles drawn; `cohort` is every profile in the same setting and
 * grouping, before the caller truncates to its highest-burden slice. The quadrant
 * split reads the cohort, so "more frequent" compares a profile with all of that
 * club's profiles rather than with the truncated tail on screen.
 */
export function ImpactBubbleChart({ rows, cohort }: { rows: InjuryProfileRow[]; cohort?: InjuryProfileRow[] }) {
  const chartRef = useRef<HTMLDivElement>(null);
  const focusedImpactKeyRef = useRef<string | undefined>(undefined);
  const dismissedImpactKeyRef = useRef<string | undefined>(undefined);
  const activeImpactKeyRef = useRef<string | undefined>(undefined);
  const [preview, setPreview] = useState<ImpactPointPosition>();
  const [pinned, setPinned] = useState<ImpactPointPosition>();
  const [scrollLeft, setScrollLeft] = useState(0);
  const [plotWidth, setPlotWidth] = useState(IMPACT_LABEL_BOX.minWidth);
  activeImpactKeyRef.current = (pinned ?? preview)?.row.impactKey;
  const previewPoint = useCallback((point: ImpactPointPosition) => {
    if (dismissedImpactKeyRef.current === point.row.impactKey) return;
    setPreview((current) => current?.row.impactKey === point.row.impactKey ? current : point);
  }, []);
  const clearPreview = useCallback(() => {
    dismissedImpactKeyRef.current = undefined;
    setPreview(undefined);
  }, []);
  const previewFromFocus = useCallback((point: ImpactPointPosition) => {
    focusedImpactKeyRef.current = point.row.impactKey;
    previewPoint(point);
  }, [previewPoint]);
  const clearFocusPreview = useCallback(() => {
    window.setTimeout(() => {
      if (!chartRef.current?.contains(document.activeElement)) {
        focusedImpactKeyRef.current = undefined;
        clearPreview();
      }
    }, 0);
  }, [clearPreview]);
  const pin = useCallback((point: ImpactPointPosition) => {
    dismissedImpactKeyRef.current = undefined;
    setPinned(point);
  }, []);
  const dismissTooltip = useCallback(() => {
    dismissedImpactKeyRef.current = activeImpactKeyRef.current;
    setPreview(undefined);
    setPinned(undefined);
  }, []);
  const syncPointPosition = useCallback((point: ImpactPointPosition) => {
    setPreview((current) => current?.row.impactKey === point.row.impactKey && (current.x !== point.x || current.y !== point.y) ? point : current);
    setPinned((current) => current?.row.impactKey === point.row.impactKey && (current.x !== point.x || current.y !== point.y) ? point : current);
  }, []);
  const nonPositiveSeverityRows = useMemo(
    () => rows.filter((row) => row.mean_severity_days !== null && Number.isFinite(row.mean_severity_days) && row.mean_severity_days <= 0),
    [rows]
  );
  const data = useMemo(
    () => rows
      .filter(isPlottableImpactRow)
      .map((row) => ({ ...row, bubble_burden: Math.max(row.burden_per_1000h ?? 0, 0.01), impactKey: `${row.setting}-${row.code}` })),
    [rows]
  );

  // Label collision is resolved in the chart's own pixel space, so it needs the
  // width the chart actually rendered at rather than its minimum width.
  useEffect(() => {
    const node = chartRef.current;
    if (!node) return;
    const measure = () => setPlotWidth(Math.max(node.clientWidth - IMPACT_LABEL_BOX.left - IMPACT_LABEL_BOX.right, 160));
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!pinned) return;
    const dismissIfOutside = (event: PointerEvent) => {
      if (!chartRef.current?.contains(event.target as Node)) dismissTooltip();
    };
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') dismissTooltip();
    };
    document.addEventListener('pointerdown', dismissIfOutside);
    document.addEventListener('keydown', dismissOnEscape);
    return () => {
      document.removeEventListener('pointerdown', dismissIfOutside);
      document.removeEventListener('keydown', dismissOnEscape);
    };
  }, [dismissTooltip, pinned]);

  /**
   * The quadrant split is descriptive, not a released threshold: the median
   * incidence and median severity of every profile in this setting and grouping,
   * not of the highest-burden slice actually drawn. A median over the drawn slice
   * would call a corner "less frequent" while every point in it is among the
   * club's worst problems. Too few profiles and a median says nothing, so the
   * shading stays off.
   */
  /**
   * Below this the four corner labels collide across the split, so they move out
   * to a legend under the plot rather than shrinking into an unreadable overlap.
   */
  const compactQuadrants = plotWidth < 420;

  const quadrantSplit = useMemo(() => {
    const cohortRows = (cohort ?? rows).filter(isPlottableImpactRow);
    if (cohortRows.length < 4 || data.length < 4) return undefined;
    const median = (values: number[]) => {
      const sorted = [...values].sort((a, b) => a - b);
      const middle = sorted.length / 2;
      return sorted.length % 2 ? sorted[Math.floor(middle)] : (sorted[middle - 1] + sorted[middle]) / 2;
    };
    return {
      incidence: median(cohortRows.map((row) => row.incidence_per_1000h ?? 0)),
      severity: median(cohortRows.map((row) => row.mean_severity_days ?? 1)),
    };
  }, [cohort, data.length, rows]);

  const rowSliceKey = useMemo(
    () => data.map((row) => `${row.impactKey}-${row.incidence_per_1000h}-${row.mean_severity_days}-${row.burden_per_1000h}`).join('|'),
    [data]
  );
  useEffect(() => {
    setPreview(undefined);
    setPinned(undefined);
  }, [rowSliceKey]);

  useLayoutEffect(() => {
    const focusedImpactKey = focusedImpactKeyRef.current;
    if (!focusedImpactKey || !chartRef.current) return;
    const target = Array.from(chartRef.current.querySelectorAll<SVGCircleElement>('[data-impact-key]'))
      .find((element) => element.dataset.impactKey === focusedImpactKey);
    if (target && document.activeElement !== target) target.focus();
  }, [preview]);

  const renderImpactBubble = useCallback((shapeProps: ImpactBubbleShapeProps) => (
    <ImpactBubble
      {...shapeProps}
      pinnedKey={pinned?.row.impactKey}
      onPreview={previewPoint}
      onFocusPreview={previewFromFocus}
      onLeave={clearPreview}
      onBlur={clearFocusPreview}
      onPin={pin}
      onDismiss={dismissTooltip}
      onPosition={syncPointPosition}
      tooltipId="impact-tooltip"
    />
  ), [clearFocusPreview, clearPreview, dismissTooltip, pin, pinned?.row.impactKey, previewFromFocus, previewPoint, syncPointPosition]);

  const chartData: ImpactChartRow[] = useMemo(() => {
    const labelled = [...data]
      .sort((a, b) => (b.burden_per_1000h ?? 0) - (a.burden_per_1000h ?? 0))
      .slice(0, 4);
    const labels = new Set(labelled.map((row) => row.code));

    // Labels are placed by box collision, not by axis proximity: two profiles can
    // sit close in both incidence and severity, and alternating above/below alone
    // still overlapped them. Positions are resolved in the chart's own pixel box,
    // trying progressively larger offsets above then below each dot until the
    // label clears every bubble and every label already placed. The bubbles are
    // seeded into the obstacle set first, so a label can never sit on a dot.
    const placed: Array<{ left: number; right: number; top: number; bottom: number }> = [];
    const offsets = new Map<string, number>();
    const domain = logSeverityDomain(Math.max(...data.map((row) => row.mean_severity_days ?? IMPACT_LOG_SEVERITY_BASE_DOMAIN[0])));
    const logMin = Math.log10(domain[0]);
    const logMax = Math.log10(domain[1]);
    const xMax = (Math.max(...data.map((row) => row.incidence_per_1000h ?? 0)) * 1.12) || 1;
    const zMin = Math.min(...data.map((row) => row.bubble_burden));
    const zMax = Math.max(...data.map((row) => row.bubble_burden));
    const bubbleRadius = (burden: number) => {
      const ratio = zMax > zMin ? (burden - zMin) / (zMax - zMin) : 1;
      return Math.sqrt((IMPACT_BUBBLE_SIZE[0] + ratio * (IMPACT_BUBBLE_SIZE[1] - IMPACT_BUBBLE_SIZE[0])) / Math.PI);
    };

    type Plottable = { incidence_per_1000h: number | null; mean_severity_days: number | null; bubble_burden: number };
    const pointX = (row: Plottable) => IMPACT_LABEL_BOX.left + ((row.incidence_per_1000h ?? 0) / xMax) * plotWidth;
    const pointY = (row: Plottable) => {
      const ratio = logMax > logMin
        ? (Math.log10(Math.max(row.mean_severity_days ?? 1, 1)) - logMin) / (logMax - logMin)
        : 0.5;
      return IMPACT_LABEL_BOX.top + (1 - ratio) * IMPACT_LABEL_BOX.height;
    };

    for (const row of data) {
      const px = pointX(row);
      const py = pointY(row);
      const radius = bubbleRadius(row.bubble_burden);
      placed.push({ left: px - radius, right: px + radius, top: py - radius, bottom: py + radius });
    }

    labelled.forEach((row) => {
      const px = pointX(row);
      const py = pointY(row);
      const radius = bubbleRadius(row.bubble_burden);
      const halfWidth = (row.label.length * 5.4) / 2;
      let chosen = -(radius + 8);
      for (let step = 0; step < 12; step += 1) {
        const above = step % 2 === 0;
        const rung = Math.floor(step / 2);
        const candidate = above
          ? -(radius + 8 + rung * 14)
          : radius + 18 + rung * 14;
        const top = py + candidate - 11;
        const box = { left: px - halfWidth, right: px + halfWidth, top, bottom: top + 13 };
        const clashes = placed.some((other) => (
          box.left < other.right && box.right > other.left
          && box.top < other.bottom && box.bottom > other.top
        ));
        if (!clashes) {
          chosen = candidate;
          placed.push(box);
          break;
        }
        if (step === 11) placed.push(box);
      }
      offsets.set(row.impactKey, chosen);
    });

    return data.map((row) => ({
      ...row,
      displayLabel: labels.has(row.code) ? row.label : '',
      labelDy: offsets.get(row.impactKey) ?? 0,
    }));
  }, [data, plotWidth]);

  /**
   * Recharts hands a scatter label the bubble's top-left corner, not its centre,
   * so anchoring straight on `x`/`y` shifts a label left by one radius and, for a
   * label placed below its dot, two radii up into the bubble itself. Every offset
   * is measured from the centre, which is what `cx`/`cy` carry.
   */
  const renderImpactLabel = useCallback((props: {
    x?: string | number;
    y?: string | number;
    cx?: string | number;
    cy?: string | number;
    width?: string | number;
    height?: string | number;
    index?: number;
  }) => {
    const { x, y, cx, cy, width, height, index } = props;
    const num = (value: string | number | undefined) => {
      const parsed = typeof value === 'string' ? Number(value) : value;
      return typeof parsed === 'number' && Number.isFinite(parsed) ? parsed : undefined;
    };
    const row = index === undefined ? undefined : chartData[index];
    const centreX = num(cx) ?? (num(x) === undefined ? undefined : num(x)! + (num(width) ?? 0) / 2);
    const centreY = num(cy) ?? (num(y) === undefined ? undefined : num(y)! + (num(height) ?? 0) / 2);
    if (!row?.displayLabel || centreX === undefined || centreY === undefined) return null;
    // Keep the whole string inside the drawn surface at narrow widths.
    const halfWidth = (row.displayLabel.length * 5.4) / 2;
    const surfaceWidth = IMPACT_LABEL_BOX.left + plotWidth + IMPACT_LABEL_BOX.right;
    const clampedX = Math.min(Math.max(centreX, halfWidth + 2), surfaceWidth - halfWidth - 2);
    return (
      <text x={clampedX} y={centreY} dy={row.labelDy} textAnchor="middle" fill="hsl(0 0% 90%)" fontSize={11}>
        {row.displayLabel}
      </text>
    );
  }, [chartData, plotWidth]);

  if (!data.length) {
    return <ChartEmpty reason="No injury profiles have finite rate and burden values plus a positive mean severity needed for this logarithmic chart." />;
  }

  const maxIncidence = Math.max(...data.map((row) => row.incidence_per_1000h ?? 0)) * 1.12 || 1;
  const severityDomain = logSeverityDomain(Math.max(...data.map((row) => row.mean_severity_days ?? IMPACT_LOG_SEVERITY_BASE_DOMAIN[0])));
  const severityTicks = logSeverityTicks(severityDomain[1]);
  const activePoint = pinned ?? preview;
  const tooltipTop = activePoint && activePoint.y < 190 ? activePoint.y + 16 : (activePoint?.y ?? 0) - 148;
  const visiblePointX = (activePoint?.x ?? 0) - scrollLeft;
  const tooltipLeft = visiblePointX > 430 ? visiblePointX - 296 : visiblePointX + 16;

  return (
    <section aria-label={`Injury impact chart. Horizontal position is incidence, vertical position is logarithmic mean severity from 1 to ${number(severityDomain[1])} days, and bubble area is burden.${quadrantSplit ? ' The plot is split into four quadrants at the median incidence and median severity of every profile in this setting and grouping: red where absences are longer and more frequent than the median, amber for the two mixed corners, green where they are shorter and less frequent.' : ''} Focus a bubble to preview its values, then press Enter or Space to pin it.`}>
      <div className="relative">
        <div
          onScroll={(event) => setScrollLeft(event.currentTarget.scrollLeft)}
          className="overflow-x-auto pb-2"
        >
          <div ref={chartRef} onPointerDown={dismissTooltip} className="h-[430px] sm:min-w-[680px]">
            <ResponsiveContainer width="100%" height="100%">
              <ScatterChart accessibilityLayer margin={{ top: 30, right: 30, bottom: 34, left: 24 }}>
                <CartesianGrid stroke={GRID} strokeDasharray="3 5" />
                {quadrantSplit && IMPACT_QUADRANTS.map((quadrant) => (
                  <ReferenceArea
                    key={quadrant.key}
                    x1={quadrant.right ? quadrantSplit.incidence : 0}
                    x2={quadrant.right ? maxIncidence : quadrantSplit.incidence}
                    y1={quadrant.top ? quadrantSplit.severity : severityDomain[0]}
                    y2={quadrant.top ? severityDomain[1] : quadrantSplit.severity}
                    fill={quadrant.fill}
                    fillOpacity={1}
                    stroke="none"
                    label={compactQuadrants ? undefined : {
                      value: quadrant.label,
                      position: quadrant.labelPosition,
                      fill: quadrant.labelFill,
                      fontSize: 10,
                    }}
                  />
                ))}
                {quadrantSplit && (
                  <ReferenceLine x={quadrantSplit.incidence} stroke={QUADRANT_DIVIDER} strokeDasharray="4 4" />
                )}
                {quadrantSplit && (
                  <ReferenceLine y={quadrantSplit.severity} stroke={QUADRANT_DIVIDER} strokeDasharray="4 4" />
                )}
                <XAxis
                  type="number"
                  dataKey="incidence_per_1000h"
                  domain={[0, maxIncidence]}
                  name="Incidence"
                  tickFormatter={formatAxisTick}
                  tick={{ fill: AXIS, fontSize: 11 }}
                  tickLine={false}
                  axisLine={AXIS_LINE}
                  label={{ value: 'Incidence, injuries /1,000 h', position: 'bottom', fill: AXIS, fontSize: 12, offset: 16 }}
                />
                <YAxis
                  type="number"
                  dataKey="mean_severity_days"
                  domain={severityDomain}
                  scale="log"
                  ticks={severityTicks}
                  name="Mean severity"
                  tickFormatter={formatAxisTick}
                  width={62}
                  tick={{ fill: AXIS, fontSize: 11 }}
                  tickLine={false}
                  axisLine={AXIS_LINE}
                  label={{ value: 'Mean severity, days (logarithmic scale)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 0, style: Y_TITLE_STYLE }}
                />
                <ZAxis type="number" dataKey="bubble_burden" range={[IMPACT_BUBBLE_SIZE[0], IMPACT_BUBBLE_SIZE[1]]} name="Burden" />
                <Scatter
                  data={chartData}
                  isAnimationActive={false}
                  shape={renderImpactBubble}
                >
                  <LabelList dataKey="displayLabel" content={renderImpactLabel} />
                </Scatter>
              </ScatterChart>
            </ResponsiveContainer>
          </div>
        </div>
        {activePoint && (
          <div
            className="pointer-events-none absolute z-30 w-[18rem]"
            style={{
              left: `clamp(0.75rem, ${tooltipLeft}px, calc(100% - 18.75rem))`,
              top: `clamp(0.75rem, ${tooltipTop}px, calc(100% - 9rem))`,
            }}
          >
            <ImpactTooltip id="impact-tooltip" row={activePoint.row} pinned={Boolean(pinned)} />
          </div>
        )}
      </div>
      {quadrantSplit && compactQuadrants && (
        <ul className="mt-3 grid grid-cols-2 gap-x-3 gap-y-1.5 text-[11px] leading-tight text-muted-foreground">
          {IMPACT_QUADRANTS.map((quadrant) => (
            <li key={quadrant.key} className="flex items-start gap-1.5">
              <span className="mt-[3px] h-2.5 w-2.5 shrink-0 rounded-[3px]" style={{ background: quadrant.swatch }} />
              <span>{quadrant.label}</span>
            </li>
          ))}
        </ul>
      )}
      {/* Not decoration: this is the only place the chart admits it is hiding rows. */}
      {nonPositiveSeverityRows.length > 0 && (
        <p className="mt-2 text-xs text-muted-foreground">
          {count(nonPositiveSeverityRows.length)} profile{nonPositiveSeverityRows.length === 1 ? '' : 's'} with non-positive mean severity {nonPositiveSeverityRows.length === 1 ? 'is' : 'are'} not shown because a logarithmic scale cannot represent those values.
        </p>
      )}
    </section>
  );
}

export type RankSlopePoint = {
  /** Competition rank on the displayed (rounded) value, 1 = highest. */
  rank: number;
  /** The already-formatted released value for this metric. */
  value: string;
};

export type RankSlopeSeries = {
  code: string;
  label: string;
  color: string;
  /** One point per metric, in the same order as `metricLabels`. */
  points: RankSlopePoint[];
};

const SLOPE_PLOT_TOP = 46;
const SLOPE_PLOT_HEIGHT = 300;
const SLOPE_HEIGHT = SLOPE_PLOT_TOP + SLOPE_PLOT_HEIGHT + 30;

/**
 * Two layouts, chosen from the measured container width. The wide one labels
 * both gutters. A phone cannot carry two gutters and four column headings in
 * 350px, and scaling the wide viewBox down to fit would put the labels at about
 * 5px, so the narrow layout drops the right gutter and shortens the labels
 * instead. Neither layout scrolls sideways.
 */
const SLOPE_LAYOUTS = {
  wide: { width: 960, left: 190, right: 190, labelLimit: 24, fontSize: 12, bothGutters: true },
  // The narrow right margin is the last column heading's half-width, not padding:
  // at 14 the centred "Severity" ran off the viewBox.
  narrow: { width: 380, left: 100, right: 34, labelLimit: 13, fontSize: 11, bothGutters: false },
} as const;

const SLOPE_NARROW_BELOW = 640;

function truncateLabel(label: string, limit = 24) {
  return label.length > limit ? `${label.slice(0, limit - 1)}…` : label;
}

/**
 * Gutter label positions: one evenly spaced slot per injury down the full plot
 * height, ordered by that gutter's rank. Anchoring each label to its own dot
 * bunched them wherever ranks cluster (ties share a rank, and the top ranks sit
 * in a narrow band), so the two gutters read at different densities. Even slots
 * give the same pitch on both sides at every setting; a leader line carries each
 * label back to the dot it belongs to.
 */
function slopeLabelSlots(anchors: number[]) {
  const pitch = SLOPE_PLOT_HEIGHT / anchors.length;
  const placed = new Array<number>(anchors.length);
  anchors
    .map((y, index) => ({ y, index }))
    .sort((a, b) => a.y - b.y || a.index - b.index)
    .forEach(({ index }, slot) => {
      placed[index] = SLOPE_PLOT_TOP + (slot + 0.5) * pitch;
    });
  return placed;
}

/**
 * One line per injury across the four ranked metrics, y = that injury's rank in
 * that metric. Every rank and value is supplied by the caller from released
 * payload values; this component only draws them. The caller filters its rows to
 * the chosen setting first, so the panel carries no scope chip of its own.
 */
export function RankSlopeChart({
  series,
  metricLabels,
  maxRank,
}: {
  series: RankSlopeSeries[];
  metricLabels: string[];
  maxRank: number;
}) {
  const [activeCode, setActiveCode] = useState<string>();
  const boxRef = useRef<HTMLDivElement>(null);
  const [narrow, setNarrow] = useState(false);
  useLayoutEffect(() => {
    const box = boxRef.current;
    if (!box) return;
    const measure = () => setNarrow(box.clientWidth > 0 && box.clientWidth < SLOPE_NARROW_BELOW);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(box);
    return () => observer.disconnect();
  }, []);
  if (series.length < 2 || metricLabels.length < 2) {
    return <ChartEmpty reason="At least two ranked injuries are needed to compare rankings across metrics." />;
  }

  const layout = narrow ? SLOPE_LAYOUTS.narrow : SLOPE_LAYOUTS.wide;
  const plotWidth = layout.width - layout.left - layout.right;
  const columnX = (index: number) => layout.left + (index * plotWidth) / (metricLabels.length - 1);
  const rankY = (rank: number) => SLOPE_PLOT_TOP + ((rank - 1) / Math.max(maxRank - 1, 1)) * SLOPE_PLOT_HEIGHT;
  const active = series.find((entry) => entry.code === activeCode);
  const leftLabelY = slopeLabelSlots(series.map((entry) => rankY(entry.points[0].rank)));
  const rightLabelY = slopeLabelSlots(series.map((entry) => rankY(entry.points[entry.points.length - 1].rank)));
  const describe = (entry: RankSlopeSeries) => `${entry.label}: ${entry.points
    .map((point, index) => `${metricLabels[index]} rank ${point.rank}, ${point.value}`)
    .join('; ')}`;

  return (
    <div className="relative" ref={boxRef}>
      <div className="pb-2">
        <div>
          <svg
            viewBox={`0 0 ${layout.width} ${SLOPE_HEIGHT}`}
            className="h-auto w-full"
            role="group"
            aria-label={`Rank of each injury across ${metricLabels.join(', ')}. Rank 1 is highest. Focus a line for its four ranks.`}
            onMouseLeave={() => setActiveCode(undefined)}
          >
            {/* The narrow layout gives its whole gutter to the injury labels, so the
                rotated title would cross them. Rank order still reads top to bottom
                and the accessible description states it. */}
            {layout.bothGutters && (
              <text x={14} y={SLOPE_PLOT_TOP + SLOPE_PLOT_HEIGHT / 2} fill={AXIS} fontSize={layout.fontSize} textAnchor="middle" transform={`rotate(-90 14 ${SLOPE_PLOT_TOP + SLOPE_PLOT_HEIGHT / 2})`}>
                Rank (1 = highest)
              </text>
            )}
            {metricLabels.map((label, index) => (
              <g key={label}>
                <text x={columnX(index)} y={SLOPE_PLOT_TOP - 20} fill={AXIS} fontSize={layout.fontSize + 1} fontWeight={600} textAnchor="middle">{label}</text>
                <line
                  x1={columnX(index)}
                  x2={columnX(index)}
                  y1={SLOPE_PLOT_TOP - 8}
                  y2={SLOPE_PLOT_TOP + SLOPE_PLOT_HEIGHT + 8}
                  stroke={GRID}
                  strokeWidth={1}
                />
              </g>
            ))}
            {series.map((entry, seriesIndex) => {
              const isActive = activeCode === entry.code;
              const dimmed = Boolean(activeCode) && !isActive;
              const points = entry.points.map((point, index) => [columnX(index), rankY(point.rank)] as const);
              const path = points.map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${x},${y}`).join(' ');
              return (
                <g
                  key={entry.code}
                  tabIndex={0}
                  // A line is a graphic that reports its own ranks on focus, not a
                  // control: it has nothing to activate, so role="button" would
                  // promise a keyboard action that does not exist.
                  role="img"
                  aria-label={describe(entry)}
                  className="cursor-pointer outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
                  opacity={dimmed ? 0.25 : 1}
                  onMouseEnter={() => setActiveCode(entry.code)}
                  onFocus={() => setActiveCode(entry.code)}
                  onBlur={() => setActiveCode(undefined)}
                >
                  <path d={path} fill="none" stroke="transparent" strokeWidth={16} />
                  <path
                    d={path}
                    fill="none"
                    stroke={entry.color}
                    strokeWidth={isActive ? 3.5 : 2}
                    strokeLinejoin="round"
                    strokeLinecap="round"
                  />
                  {points.map(([x, y], index) => (
                    <circle
                      key={metricLabels[index]}
                      cx={x}
                      cy={y}
                      r={isActive ? 5.5 : 4}
                      fill={entry.color}
                      stroke={isActive ? 'hsl(0 0% 100%)' : 'none'}
                      strokeWidth={isActive ? 2 : 0}
                    />
                  ))}
                  {/* Leader lines: the label sits in its own evenly spaced slot, so
                      each one is tied back to the dot it describes. */}
                  <polyline
                    points={`${layout.left - 10},${leftLabelY[seriesIndex]} ${layout.left - 6},${points[0][1]} ${points[0][0]},${points[0][1]}`}
                    fill="none"
                    stroke={entry.color}
                    strokeWidth={1}
                    strokeOpacity={isActive ? 0.9 : 0.4}
                  />
                  <text
                    x={layout.left - 14}
                    y={leftLabelY[seriesIndex] + 4}
                    textAnchor="end"
                    fontSize={layout.fontSize}
                    fontWeight={isActive ? 700 : 500}
                    fill={entry.color}
                  >
                    {truncateLabel(entry.label, layout.labelLimit)}
                  </text>
                  {layout.bothGutters && (
                    <>
                      <polyline
                        points={`${layout.width - layout.right + 10},${rightLabelY[seriesIndex]} ${layout.width - layout.right + 6},${points[points.length - 1][1]} ${points[points.length - 1][0]},${points[points.length - 1][1]}`}
                        fill="none"
                        stroke={entry.color}
                        strokeWidth={1}
                        strokeOpacity={isActive ? 0.9 : 0.4}
                      />
                      <text
                        x={layout.width - layout.right + 14}
                        y={rightLabelY[seriesIndex] + 4}
                        textAnchor="start"
                        fontSize={layout.fontSize}
                        fontWeight={isActive ? 700 : 500}
                        fill={entry.color}
                      >
                        {truncateLabel(entry.label, layout.labelLimit)}
                      </text>
                    </>
                  )}
                </g>
              );
            })}
          </svg>
        </div>
      </div>
      {active && (
        <div
          className="pointer-events-none absolute z-30"
          style={{
            left: `clamp(0.5rem, ${(columnX(1) / layout.width) * 100}%, calc(100% - 12rem))`,
            top: `${(rankY(active.points[0].rank) / SLOPE_HEIGHT) * 100}%`,
          }}
        >
          <TooltipCard
            title={active.label}
            rows={active.points.map((point, index) => ({
              label: metricLabels[index],
              value: `${point.value} (rank ${point.rank})`,
              color: active.color,
            }))}
          />
        </div>
      )}
    </div>
  );
}
