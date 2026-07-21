'use client';

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  LabelList,
  Legend,
  Pie,
  PieChart,
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
        ? `n = ${count(row.recorded_injuries)} recorded cases.`
        : `n = ${count(row.time_loss_injuries)} time-loss cases.`}
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
      cohort={`n = ${count(row.rate_time_loss_injuries)} time-loss cases.`}
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
      cohort={`n = ${hours(row.exposure_hours)} player-hours.`}
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
        <AreaChart accessibilityLayer data={data} margin={{ top: 70, right: 14, bottom: 28, left: 12 }}>
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
    () => sortSeasonMonths(rows.filter((row) => row.exposure_hours !== null && row.incidence_per_1000h !== null)),
    [rows]
  );
  if (!data.length) return <ChartEmpty reason="No month has both an exposure denominator and an incidence rate for this view." />;

  return (
    <div className="h-[286px] min-w-[540px]" aria-label="Monthly injury incidence chart">
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

export type RingDatum = { key: string; label: string; value: number };

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
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 grid place-content-center text-center">
          <strong className="max-w-[112px] text-lg leading-tight text-foreground">{selected?.label ?? centerLabel}</strong>
          <span className="mt-1 text-xl font-semibold tabular-nums text-primary">{count(selected?.value)}</span>
          <span className="text-[10px] font-medium text-muted-foreground">{valueLabel}</span>
        </div>
      </div>
      <div className="space-y-1">
        {selected && (
          <div aria-live="polite" className="mb-2 rounded-md border border-border bg-background/60 px-3 py-2 text-xs leading-relaxed text-popover-foreground">
            <span className="font-semibold text-foreground">{selected.label}</span>
            <span className="mx-1 text-muted-foreground">:</span>
            <span className="font-medium tabular-nums text-foreground">{count(selected.value)} {valueLabel}</span>
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
              aria-label={`${row.label}: ${count(row.value)} ${valueLabel}.`}
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
        <AreaChart accessibilityLayer data={data} margin={{ top: 70, right: 14, bottom: 28, left: 30 }}>
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
            position={{ x: 14, y: 10 }}
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
    ? 'Caution: based on 1 injury.'
    : row.time_loss_injuries === 2
      ? 'Small sample: interpret 2 injuries cautiously.'
      : '';

  return (
    <div id={id} role="tooltip" aria-live="polite" className="w-[min(18rem,calc(100vw-2rem))] rounded-md border border-border bg-popover px-3 py-2 text-xs text-popover-foreground shadow-xl">
      <p className="font-semibold text-foreground">{row.label} <span className="font-normal text-muted-foreground">- {settingLabel(row.setting)}</span></p>
      <p className="mt-2 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Burden</p>
      <p className="text-lg font-semibold tabular-nums text-foreground">{number(row.burden_per_1000h)} <span className="text-xs font-medium text-muted-foreground">days /1,000 h</span></p>
      <dl className="mt-2 grid grid-cols-2 gap-x-4 gap-y-1 border-t border-border/70 pt-2">
        <div>
          <dt className="text-muted-foreground">Incidence</dt>
          <dd className="font-medium tabular-nums text-foreground">{number(row.incidence_per_1000h)} /1,000 h</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">Mean severity</dt>
          <dd className="font-medium tabular-nums text-foreground">{number(row.mean_severity_days)} days</dd>
        </div>
      </dl>
      <p className="mt-2 border-t border-border/70 pt-2 leading-snug text-muted-foreground">n = {count(row.time_loss_injuries)} time-loss {row.time_loss_injuries === 1 ? 'injury' : 'injuries'} · {count(row.days_lost)} total days lost.{caution && ` ${caution}`}{pinned && ' Pinned. Press Escape or click outside to dismiss.'}</p>
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
  impactKey: string;
};

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

export function ImpactBubbleChart({ rows }: { rows: InjuryProfileRow[] }) {
  const chartRef = useRef<HTMLDivElement>(null);
  const focusedImpactKeyRef = useRef<string | undefined>(undefined);
  const dismissedImpactKeyRef = useRef<string | undefined>(undefined);
  const activeImpactKeyRef = useRef<string | undefined>(undefined);
  const [preview, setPreview] = useState<ImpactPointPosition>();
  const [pinned, setPinned] = useState<ImpactPointPosition>();
  const [scrollLeft, setScrollLeft] = useState(0);
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
      .filter(
        (row) =>
          row.incidence_per_1000h !== null &&
          Number.isFinite(row.incidence_per_1000h) &&
          row.burden_per_1000h !== null &&
          Number.isFinite(row.burden_per_1000h) &&
          isPlottableLogSeverity(row.mean_severity_days)
      )
      .map((row) => ({ ...row, bubble_burden: Math.max(row.burden_per_1000h ?? 0, 0.01), impactKey: `${row.setting}-${row.code}` })),
    [rows]
  );

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

  const chartData = useMemo(() => {
    const labels = new Set(
      [...data]
        .sort((a, b) => (b.burden_per_1000h ?? 0) - (a.burden_per_1000h ?? 0))
        .slice(0, 4)
        .map((row) => row.code)
    );
    return data.map((row) => ({ ...row, displayLabel: labels.has(row.code) ? row.label : '' }));
  }, [data]);

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
    <section aria-label={`Injury impact chart. Horizontal position is incidence, vertical position is logarithmic mean severity from 1 to ${number(severityDomain[1])} days, and bubble area is burden. Focus a bubble to preview its values, then press Enter or Space to pin it.`}>
      <div className="relative">
        <div
          onScroll={(event) => setScrollLeft(event.currentTarget.scrollLeft)}
          className="overflow-x-auto pb-2"
        >
          <div ref={chartRef} onPointerDown={dismissTooltip} className="h-[430px] min-w-[680px]">
            <ResponsiveContainer width="100%" height="100%">
              <ScatterChart accessibilityLayer margin={{ top: 30, right: 30, bottom: 34, left: 18 }}>
                <CartesianGrid stroke={GRID} strokeDasharray="3 5" />
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
                  domain={severityDomain}
                  scale="log"
                  ticks={severityTicks}
                  name="Mean severity"
                  tickFormatter={formatAxisTick}
                  width={54}
                  tick={{ fill: AXIS, fontSize: 11 }}
                  tickLine={false}
                  axisLine={false}
                  label={{ value: 'Mean severity, days (logarithmic scale)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 0 }}
                />
                <ZAxis type="number" dataKey="bubble_burden" range={[160, 1_100]} name="Burden" />
                <Scatter
                  data={chartData}
                  isAnimationActive={false}
                  shape={renderImpactBubble}
                >
                  <LabelList dataKey="displayLabel" position="top" fill="hsl(0 0% 90%)" fontSize={11} />
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
      <div className="mt-2 space-y-1 text-xs text-muted-foreground">
        <p>Mean severity uses a logarithmic scale from 1 to {number(severityDomain[1])} days. Bubble area shows burden.</p>
        {nonPositiveSeverityRows.length > 0 && <p>{count(nonPositiveSeverityRows.length)} profile{nonPositiveSeverityRows.length === 1 ? '' : 's'} with non-positive mean severity {nonPositiveSeverityRows.length === 1 ? 'is' : 'are'} not shown because a logarithmic scale cannot represent those values.</p>}
      </div>
    </section>
  );
}
