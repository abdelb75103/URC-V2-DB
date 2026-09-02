'use client';

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import {
  Bar,
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
import type { BarShapeProps } from 'recharts';
import type { AnalyticsRow, InjuryProfileRow, MonthlySettingRow } from '@/lib/reporting-types';
import {
  exposureMonthLabel,
  hasReportedExposureValue,
  hsrPercentage,
  showExposureMonthLabel,
} from '@/lib/exposure-chart';
import type { SeasonTimelineRow } from '@/lib/season-timeline';
import {
  PROFILE_COLORS,
  SETTING_COLORS,
  monthIndex,
  sortSeasonMonths,
} from '@/components/dashboard/chart-primitives';

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
/**
 * The hovered category band. Every categorical chart highlights the whole band
 * behind its series, so the tooltip rows and the bars they describe read as one
 * group.
 */
export const HOVER_BAND = { fill: 'hsl(0 0% 100% / 0.1)' };

function number(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return numberFormatter(digits, Number.isInteger(value) ? 0 : digits).format(value);
}

function count(value: number | null | undefined) {
  return number(value, 0);
}

function hours(value: number | null | undefined) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: 0,
    minimumFractionDigits: 0,
  }).format(value);
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

/** The dashboard's metric identity colours, shared by the KPI cards and tooltips. */
const METRIC_COLORS = {
  count: SETTING_COLORS.all,
  incidence: '#ffc45c',
  burden: '#ef7189',
  severity: '#42d8b4',
} as const;

/** Time-loss series colour, shared by the timeline bars, line and tooltip rows. */
const TIME_LOSS_COLOR = METRIC_COLORS.incidence;

/**
 * The one tooltip surface every chart uses: a dark, slightly transparent panel,
 * a bold header naming the category, and one compact row per series with both
 * the label and the value drawn in that series' own colour, so a row and its
 * mark are matched by colour alone. The cohort footer was removed on
 * 25 July 2026: the hover states the values and stops there.
 *
 * `id` is passed by the charts that own their tooltip element rather than
 * letting Recharts position it; those need the live region and the id that
 * their marks point at with aria-describedby.
 */
export function TooltipCard({
  id,
  title,
  aside,
  rows,
  note,
}: {
  id?: string;
  title: string;
  aside?: ReactNode;
  rows: TooltipRow[];
  note?: string;
}) {
  return (
    <div
      id={id}
      role={id ? 'tooltip' : undefined}
      aria-live={id ? 'polite' : undefined}
      className="max-w-[min(18rem,calc(100vw-2rem))] rounded-lg px-3 py-2 text-xs shadow-xl backdrop-blur-sm"
      style={TOOLTIP_SURFACE}
    >
      <div className="flex items-baseline justify-between gap-3">
        <p className="font-semibold text-white">{title}</p>
        {aside && <span className="shrink-0 text-[11px] capitalize text-muted-foreground">{aside}</span>}
      </div>
      <dl className="mt-1.5 space-y-1">
        {rows.map((row) => (
          <div key={row.label} className="grid grid-cols-[minmax(0,1fr)_auto] gap-4" style={row.color ? { color: row.color } : undefined}>
            <dt className={row.color ? undefined : 'text-white'}>{row.label}</dt>
            <dd className={`text-right font-semibold tabular-nums ${row.color ? '' : 'text-white'}`}>{row.value}</dd>
          </div>
        ))}
      </dl>
      {note && <p className="mt-1.5 text-[11px] leading-snug text-muted-foreground">{note}</p>}
    </div>
  );
}

type ExposureMonthlyRow = AnalyticsRow;

const HSR_COLOR = '#f59e0b';
const DISTANCE_COLOR = SETTING_COLORS.all;

function useCompactExposureMonths() {
  const [compact, setCompact] = useState(false);

  useEffect(() => {
    const media = window.matchMedia('(max-width: 639px)');
    const update = () => setCompact(media.matches);
    update();
    media.addEventListener('change', update);
    return () => media.removeEventListener('change', update);
  }, []);

  return compact;
}

function MonthlyExposureTooltip({
  active,
  label,
  payload,
  hoursColor,
}: {
  active?: boolean;
  label?: string;
  payload?: Array<{ payload?: ExposureMonthlyRow }>;
  hoursColor: string;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  const percentage = hsrPercentage(row);
  const rows: TooltipRow[] = [
    { label: 'Hours', value: `${hours(row.exposure_hours)} player-hours`, color: hoursColor },
    { label: 'Total Distance', value: `${number(row.distance_km)} km`, color: DISTANCE_COLOR },
    { label: 'HSR Distance', value: `${number(row.hsr_distance_km)} km`, color: HSR_COLOR },
    { label: 'HSR Percentage', value: percentage === null ? 'Not available' : `${number(percentage, 1)}%`, color: HSR_COLOR },
  ];
  return <TooltipCard title={exposureMonthLabel(label ?? row.month ?? 'Month')} rows={rows} note={row.is_imputed ? row.display_note ?? undefined : undefined} />;
}

function HsrInsetDistanceBar({ x, y, width, height, payload }: BarShapeProps) {
  const totalDistance = payload?.distance_km;
  const hsrDistance = payload?.hsr_distance_km;
  const hasInset = typeof totalDistance === 'number' && totalDistance > 0
    && typeof hsrDistance === 'number' && hsrDistance >= 0;
  const insetHeight = hasInset ? Math.min(height, Math.max((hsrDistance / totalDistance) * height, hsrDistance > 0 ? 3 : 0)) : 0;
  const percentage = payload ? hsrPercentage(payload) : null;

  return (
    <g>
      <rect x={x} y={y} width={width} height={height} rx={3} fill={DISTANCE_COLOR} />
      {hasInset && insetHeight > 0 && (
        <rect
          x={x}
          y={y + height - insetHeight}
          width={width}
          height={insetHeight}
          rx={2}
          fill={HSR_COLOR}
        />
      )}
      {hasInset && percentage !== null && (
        <text className="hidden sm:block" x={x + width / 2} y={y + height - insetHeight - 5} fill="#e2e8f0" fontSize={10} fontWeight={700} textAnchor="middle">
          {number(percentage, 1)}%
        </text>
      )}
    </g>
  );
}

export type RingDatum = { key: string; label: string; value: number; color?: string };

/**
 * The bars count the whole cohort; a preliminary rate is measured on the
 * contributing clubs only. When the month carries one, its own numerator,
 * contributors and exposure are named here so the two denominators cannot be
 * read as the same thing.
 */
function TimelineTooltip({
  active,
  label,
  payload,
}: {
  active?: boolean;
  label?: string;
  payload?: Array<{ payload?: SeasonTimelineRow }>;
}) {
  const row = payload?.[0]?.payload;
  if (!active || !row) return null;
  const preliminary = row.preliminary_rate;
  const rows: TooltipRow[] = [{ label: 'Time Loss Injuries', value: `${count(row.time_loss_injuries)} injuries`, color: TIME_LOSS_COLOR }];
  if (typeof row.recorded_injuries === 'number') {
    rows.unshift({ label: 'Overall Injuries', value: `${count(row.recorded_injuries)} injuries`, color: SETTING_COLORS.all });
  }
  if (typeof row.overall_incidence_per_1000h === 'number') {
    rows.push({ label: 'Overall Incidence', value: `${number(row.overall_incidence_per_1000h)} /1,000 h`, color: SETTING_COLORS.all });
  }
  if (typeof row.incidence_per_1000h === 'number') {
    rows.push({ label: 'Time Loss Incidence', value: `${number(row.incidence_per_1000h)} /1,000 h`, color: TIME_LOSS_COLOR });
  }
  if (preliminary) {
    rows.push({ label: 'Rate Injuries', value: `${count(preliminary.time_loss_injuries)} injuries`, color: TIME_LOSS_COLOR });
    rows.push({ label: 'Contributors', value: `${count(preliminary.contributor_count)} clubs` });
    rows.push({ label: 'Exposure', value: `${hours(preliminary.exposure_hours)} player-hours` });
  } else if (typeof row.overall_incidence_per_1000h === 'number' || typeof row.incidence_per_1000h === 'number') {
    rows.push({ label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` });
  }
  return (
    <TooltipCard
      title={exposureMonthLabel(label ?? row.month)}
      rows={rows}
      note={preliminary?.qualification}
    />
  );
}

export function SeasonTimelineChart({
  rows,
  showInjuries,
  showTlInjuries,
  showOverallIncidence,
  showTlIncidence,
}: {
  rows: SeasonTimelineRow[];
  showInjuries: boolean;
  showTlInjuries: boolean;
  showOverallIncidence: boolean;
  showTlIncidence: boolean;
}) {
  const data = useMemo(() => fromSeptember(sortSeasonMonths(rows)), [rows]);
  if (!data.length) return <ChartEmpty reason="No dated injury cases are available for the selected setting." />;
  if (!showInjuries && !showTlInjuries && !showOverallIncidence && !showTlIncidence) {
    return <ChartEmpty reason="Select at least one series to plot." />;
  }
  const hasRecordedCases = data.every((row) => typeof row.recorded_injuries === 'number');
  const hasOverallIncidence = data.some((row) => typeof row.overall_incidence_per_1000h === 'number');
  const hasTlIncidence = data.some((row) => typeof row.incidence_per_1000h === 'number');

  return (
    <div className="h-[320px] sm:min-w-[560px]" aria-label="Season Timeline of Overall Injuries, Time Loss Injuries, Overall Incidence and Time Loss Incidence">
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart accessibilityLayer data={data} margin={{ top: 34, right: 16, bottom: 32, left: 12 }}>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={(value: string) => exposureMonthLabel(value, true)}
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
            label={{ value: 'Injuries (n)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 11, offset: 4, style: Y_TITLE_STYLE }}
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
            cursor={HOVER_BAND}
            wrapperStyle={{ zIndex: 30 }}
          />
          <Legend verticalAlign="top" height={22} wrapperStyle={{ fontSize: 11, paddingTop: 0 }} />
          {showInjuries && hasRecordedCases && (
            <Bar
              yAxisId="cases"
              dataKey="recorded_injuries"
              name="Overall Injuries"
              fill={SETTING_COLORS.all}
              fillOpacity={0.72}
              radius={[3, 3, 0, 0]}
              maxBarSize={34}
              isAnimationActive={false}
            />
          )}
          {showTlInjuries && (
            <Bar
              yAxisId="cases"
              dataKey="time_loss_injuries"
              name="Time Loss Injuries"
              fill={TIME_LOSS_COLOR}
              fillOpacity={1}
              radius={[3, 3, 0, 0]}
              maxBarSize={34}
              isAnimationActive={false}
            />
          )}
          {showOverallIncidence && hasOverallIncidence && (
            <Line
              yAxisId="rate"
              type="monotone"
              dataKey="overall_incidence_per_1000h"
              name="Overall Incidence"
              stroke={SETTING_COLORS.all}
              strokeWidth={2.5}
              dot={{ r: 3, strokeWidth: 1.5 }}
              activeDot={{ r: 5, strokeWidth: 2 }}
              isAnimationActive={false}
            />
          )}
          {showTlIncidence && hasTlIncidence && (
            <Line
              yAxisId="rate"
              type="monotone"
              dataKey="incidence_per_1000h"
              name="Time Loss Incidence"
              stroke={TIME_LOSS_COLOR}
              strokeWidth={2.5}
              dot={{ r: 3, strokeWidth: 1.5 }}
              activeDot={{ r: 5, strokeWidth: 2 }}
              isAnimationActive={false}
            />
          )}
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

/**
 * Half-ring band breakdown. Severity keeps its ordered least-to-most scale
 * labels; other ordered-but-unranked breakdowns (contact mechanism) pass
 * `scaleLabels={null}` to drop the scale row and reuse the same mark.
 */
export function SeverityArc({
  rows,
  scaleLabels = ['Least Severe', 'Most Severe'],
  ariaLabel = 'Severity Band Breakdown',
}: {
  rows: RingDatum[];
  scaleLabels?: [string, string] | null;
  ariaLabel?: string;
}) {
  const data = rows.filter((row) => row.value > 0);
  const total = data.reduce((sum, row) => sum + row.value, 0);
  const [selectedKey, setSelectedKey] = useState<string>();
  const selected = data.find((row) => row.key === selectedKey);
  if (!data.length) return <ChartEmpty compact reason="No classified cases are available for this breakdown." />;

  return (
    <div>
      <div className="relative mx-auto h-[124px] w-full max-w-[240px]" aria-label={ariaLabel}>
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
      {scaleLabels && (
        <div className="mt-3 flex items-center justify-between px-1 text-[10px] uppercase tracking-wide text-muted-foreground">
          <span>{scaleLabels[0]}</span>
          <span>{scaleLabels[1]}</span>
        </div>
      )}
      <div className={`${scaleLabels ? 'mt-1' : 'mt-3'} space-y-1`}>
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

export function ExposureTrendChart({
  rows,
  totalHoursColor = SETTING_COLORS.training,
}: {
  rows: ExposureMonthlyRow[];
  /** Club identity colour for the player-hours bars. */
  totalHoursColor?: string;
}) {
  const compactMonths = useCompactExposureMonths();
  const data = useMemo(() => {
    const sorted = sortSeasonMonths<ExposureMonthlyRow & { month: string }>((rows
      .filter((row) => {
        if (!row.month) return false;
        return hasReportedExposureValue(row, 'hours')
          || hasReportedExposureValue(row, 'distance')
          || hsrPercentage(row) !== null;
      })) as Array<ExposureMonthlyRow & { month: string }>);
    return fromSeptember(sorted);
  }, [rows]);
  if (!data.length) {
    return <ChartEmpty reason="No monthly exposure is available for this season." />;
  }

  return (
    <div className="min-w-0" aria-label="Monthly exposure comparison chart">
      <div className="h-[340px] w-full min-w-0">
        <ResponsiveContainer width="100%" height="100%">
          <ComposedChart aria-label="Monthly hours, total distance, and high-speed-running exposure chart" accessibilityLayer data={data} margin={{ top: 34, right: 16, bottom: 32, left: 12 }} barCategoryGap="24%" barGap={3}>
          <CartesianGrid stroke={GRID} strokeDasharray="3 5" vertical={false} />
          <XAxis
            dataKey="month"
            tickFormatter={(value, index) => showExposureMonthLabel(index, compactMonths) ? exposureMonthLabel(value, compactMonths) : ''}
            interval={0}
            minTickGap={8}
            tick={{ fill: AXIS, fontSize: 10 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Month', position: 'insideBottom', fill: AXIS, fontSize: 11, offset: -14 }}
          />
          <YAxis
            yAxisId="hours"
            tickFormatter={(value) => value >= 1000 ? `${Math.round(value / 1000)}k` : number(value, 0)}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Player-hours', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 11, offset: 4, style: Y_TITLE_STYLE }}
          />
          <YAxis
            yAxisId="distance"
            orientation="right"
            tickFormatter={(value) => value >= 1000 ? `${number(value / 1000, 1)}k` : number(value, 0)}
            tick={{ fill: AXIS, fontSize: 11 }}
            tickLine={false}
            axisLine={AXIS_LINE}
            label={{ value: 'Distance (km)', angle: 90, position: 'insideRight', fill: AXIS, fontSize: 11, offset: 8, style: Y_TITLE_STYLE }}
          />
          <Tooltip
            content={<MonthlyExposureTooltip hoursColor={totalHoursColor} />}
            cursor={HOVER_BAND}
            allowEscapeViewBox={{ x: false, y: false }}
            wrapperStyle={{ zIndex: 30 }}
          />
          <Legend verticalAlign="top" height={22} wrapperStyle={{ fontSize: 11, paddingTop: 0 }} />
          <Bar yAxisId="hours" dataKey="exposure_hours" name="Hours" fill={totalHoursColor} radius={[3, 3, 0, 0]} maxBarSize={54} isAnimationActive={false} />
          <Bar yAxisId="distance" dataKey="distance_km" name="Total Distance" fill={DISTANCE_COLOR} shape={HsrInsetDistanceBar} maxBarSize={54} isAnimationActive={false} />
          </ComposedChart>
        </ResponsiveContainer>
      </div>
      <div className="mt-1 flex flex-wrap justify-center gap-x-4 gap-y-1 text-xs text-muted-foreground" aria-label="Exposure chart legend">
        <span className="inline-flex items-center gap-1.5"><i className="h-2.5 w-2.5 rounded-sm" style={{ background: totalHoursColor }} aria-hidden="true" />Hours</span>
        <span className="inline-flex items-center gap-1.5"><i className="h-2.5 w-2.5 rounded-sm" style={{ background: DISTANCE_COLOR }} aria-hidden="true" />Total Distance</span>
        <span className="inline-flex items-center gap-1.5"><i className="h-2.5 w-2.5 rounded-sm" style={{ background: HSR_COLOR }} aria-hidden="true" />HSR Distance</span>
      </div>
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
        { label: 'Match Incidence', value: `${number(row.match_incidence, 2)} /1,000 h`, color: SETTING_COLORS.match },
        { label: 'Training Incidence', value: `${number(row.training_incidence, 2)} /1,000 h`, color: SETTING_COLORS.training },
        { label: 'Exposure', value: `${hours(row.exposure_hours)} player-hours` },
      ]}
    />
  );
}

function comparisonMarkerLabel(label: string) {
  const alias = label.match(/^Team\s+(.+)$/i)?.[1];
  if (alias) return alias;
  return label
    .trim()
    .split(/\s+/)
    .map((word) => word[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
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
  const labelledRows = rows.map((row) => ({ ...row, marker_label: comparisonMarkerLabel(row.label) }));
  const others = labelledRows.filter((row) => !row.is_viewer);
  const viewer = labelledRows.filter((row) => row.is_viewer);
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
  const matchDomain = pad(rows.map((row) => row.match_incidence));
  const trainingDomain = pad(rows.map((row) => row.training_incidence));
  const showIncidenceZones = typeof leagueMatchIncidence === 'number' && typeof leagueTrainingIncidence === 'number';
  // The training mean is labelled at the right-hand end of its line in both
  // layouts. Wide puts it outside the plot, which costs a right margin big enough
  // to hold the whole string (~102px at fontSize 10, plus the 5px offset). On a
  // phone that margin would cost a third of the card, so the label moves inside
  // the plot, still right-aligned, and the plot takes the width back.
  const trainingLabel = narrow
    ? { value: 'League Training Mean', position: 'insideTopRight' as const, fill: SETTING_COLORS.training, fontSize: 10 }
    : { value: 'League Training Mean', position: 'right' as const, fill: SETTING_COLORS.training, fontSize: 10 };

  return (
    <section aria-label="Match versus training incidence for every club. Horizontal position is match incidence, vertical position is training incidence, and circle area is player-hours. The green zone is below both league means and the red zone is above both league means.">
      <div className="pb-2" ref={boxRef}>
        <div className="h-[360px] sm:min-w-[620px]">
          <ResponsiveContainer width="100%" height="100%">
            <ScatterChart accessibilityLayer margin={{ top: 34, right: narrow ? 16 : 116, bottom: 32, left: 14 }}>
              {showIncidenceZones && (
                <>
                  <ReferenceArea
                    x1={matchDomain[0]}
                    x2={leagueMatchIncidence}
                    y1={trainingDomain[0]}
                    y2={leagueTrainingIncidence}
                    fill="#22c55e"
                    fillOpacity={0.09}
                    stroke="none"
                  />
                  <ReferenceArea
                    x1={leagueMatchIncidence}
                    x2={matchDomain[1]}
                    y1={leagueTrainingIncidence}
                    y2={trainingDomain[1]}
                    fill="#ef4444"
                    fillOpacity={0.09}
                    stroke="none"
                  />
                </>
              )}
              <CartesianGrid stroke={GRID} strokeDasharray="3 5" />
              <XAxis
                type="number"
                dataKey="match_incidence"
                name="Match Incidence"
                domain={matchDomain}
                tickFormatter={formatAxisTick}
                tick={{ fill: AXIS, fontSize: 11 }}
                tickLine={false}
                axisLine={AXIS_LINE}
                label={{ value: 'Match Incidence, Injuries /1,000 h', position: 'bottom', fill: AXIS, fontSize: 12, offset: 14 }}
              />
              <YAxis
                type="number"
                dataKey="training_incidence"
                name="Training Incidence"
                domain={trainingDomain}
                tickFormatter={formatAxisTick}
                width={50}
                tick={{ fill: AXIS, fontSize: 11 }}
                tickLine={false}
                axisLine={AXIS_LINE}
                label={{ value: 'Training Incidence, Injuries /1,000 h', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 2, style: Y_TITLE_STYLE }}
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
                  label={{ value: 'League Match Mean', position: 'top', fill: SETTING_COLORS.match, fontSize: 10 }}
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
              >
                <LabelList dataKey="marker_label" position="center" fill="hsl(0 0% 100%)" fontSize={9} fontWeight={700} />
              </Scatter>
              {viewer.length > 0 && (
                <Scatter
                  data={viewer}
                  fill={viewerColor}
                  fillOpacity={0.92}
                  stroke="hsl(0 0% 100%)"
                  strokeWidth={2}
                  isAnimationActive={false}
                >
                  <LabelList dataKey="marker_label" position="center" fill="hsl(0 0% 100%)" fontSize={9} fontWeight={700} />
                </Scatter>
              )}
            </ScatterChart>
          </ResponsiveContainer>
        </div>
        <div className="mt-5 flex flex-wrap items-center justify-center gap-x-4 gap-y-1 rounded-md border border-border/70 bg-background/25 px-3 py-2 text-[11px] text-muted-foreground">
          <span>Circle Area = Player-Hours</span>
          {showIncidenceZones && (
            <>
              <span className="inline-flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-sm bg-green-500/70" aria-hidden="true" />
                Below Both League Means
              </span>
              <span className="inline-flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-sm bg-red-500/70" aria-hidden="true" />
                Above Both League Means
              </span>
            </>
          )}
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

  const note = [caution, pinned ? 'Pinned, press Escape to dismiss' : ''].filter(Boolean).join(' · ');

  return (
    <TooltipCard
      id={id}
      title={row.label}
      aside={settingLabel(row.setting)}
      rows={[
        { label: 'Incidence', value: `${number(row.incidence_per_1000h)} /1,000 h`, color: METRIC_COLORS.incidence },
        { label: 'Mean Severity', value: `${number(row.mean_severity_days)} days`, color: METRIC_COLORS.severity },
        { label: 'Burden', value: `${number(row.burden_per_1000h)} days /1,000 h`, color: METRIC_COLORS.burden },
        { label: 'Injuries', value: count(row.time_loss_injuries), color: METRIC_COLORS.count },
        { label: 'Total Days Lost', value: count(row.days_lost), color: METRIC_COLORS.burden },
      ]}
      note={note || undefined}
    />
  );
}

function formatAxisTick(value: number) {
  return number(value);
}

function isPlottableLogSeverity(value: number | null): value is number {
  return value !== null && Number.isFinite(value) && value > 0;
}

function logSeverityTickCandidates(maximum: number) {
  const topExponent = Math.max(1, Math.ceil(Math.log10(Math.max(maximum, 1))));
  return Array.from({ length: topExponent + 1 }, (_, exponent) => [1, 2, 5].map((multiple) => multiple * 10 ** exponent)).flat();
}

function logSeverityDomain(values: number[]): [number, number] {
  if (!values.length) return [1, 10];
  const minimum = Math.min(...values);
  const maximum = Math.max(...values);
  const candidates = logSeverityTickCandidates(maximum * 2);
  const lower = candidates.filter((tick) => tick <= minimum / 1.15).at(-1) ?? 1;
  const upper = candidates.find((tick) => tick >= maximum * 1.15) ?? 10 ** Math.ceil(Math.log10(maximum * 1.15));
  return [lower, Math.max(upper, lower * 2)];
}

function logSeverityTicks(domain: [number, number]) {
  return logSeverityTickCandidates(domain[1]).filter((tick) => tick >= domain[0] && tick <= domain[1]);
}

type ImpactChartRow = InjuryProfileRow & {
  displayIndex: number;
  impactKey: string;
};

const IMPACT_DOT_RADIUS = 9;

/** A profile the log-scaled bubble chart can place at all. */
function isPlottableImpactRow(row: InjuryProfileRow) {
  return row.incidence_per_1000h !== null
    && Number.isFinite(row.incidence_per_1000h)
    && isPlottableLogSeverity(row.mean_severity_days);
}

type ImpactPointPosition = {
  row: ImpactChartRow;
  x: number;
  y: number;
};

type ImpactDotShapeProps = {
  cx?: number;
  cy?: number;
  payload?: ImpactChartRow;
};

function ImpactDot({
  cx,
  cy,
  payload,
  pinnedKey,
  activeKey,
  onPreview,
  onFocusPreview,
  onLeave,
  onBlur,
  onPin,
  onDismiss,
  onPosition,
  tooltipId,
}: ImpactDotShapeProps & {
  pinnedKey?: string;
  activeKey?: string;
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
  const point = { row: payload, x: cx, y: cy };
  const selected = pinnedKey === payload.impactKey;
  const active = activeKey === payload.impactKey;
  const accessibleLabel = `${payload.label}, ${settingLabel(payload.setting)}. Incidence ${number(payload.incidence_per_1000h)} injuries per 1,000 hours. Mean severity ${number(payload.mean_severity_days)} days. ${selected ? 'Pinned. Press Escape to dismiss.' : 'Press Enter or Space to pin.'}`;

  return (
    <g>
      {active && <circle cx={cx} cy={cy} r={IMPACT_DOT_RADIUS + 4} fill="none" stroke="hsl(var(--foreground))" strokeWidth={selected ? 2 : 1.5} strokeOpacity={0.9} pointerEvents="none" />}
      <circle cx={cx} cy={cy} r={IMPACT_DOT_RADIUS} fill="hsl(202 58% 20%)" stroke="hsl(0 0% 100%)" strokeWidth={1.5} strokeOpacity={0.98} pointerEvents="none" />
      <text x={cx} y={cy + 3} textAnchor="middle" fill="white" fontSize={8} fontWeight={700} pointerEvents="none">{payload.displayIndex}</text>
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
        className="outline-none"
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

/** Incidence and mean severity define position; every displayed profile is a numbered fixed-size dot. */
export function ImpactScatterChart({ rows }: { rows: InjuryProfileRow[] }) {
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
      .filter(isPlottableImpactRow)
      .map((row, index) => ({ ...row, displayIndex: index + 1, impactKey: `${row.setting}-${row.code}` })),
    [rows]
  );
  const maxIncidence = Math.max(...data.map((row) => row.incidence_per_1000h ?? 0), 0) * 1.12 || 1;
  const severityDomain = logSeverityDomain(data.map((row) => row.mean_severity_days ?? 1));
  const severityTicks = logSeverityTicks(severityDomain);

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

  const renderImpactDot = useCallback((shapeProps: ImpactDotShapeProps) => (
    <ImpactDot
      {...shapeProps}
      pinnedKey={pinned?.row.impactKey}
      activeKey={(pinned ?? preview)?.row.impactKey}
      onPreview={previewPoint}
      onFocusPreview={previewFromFocus}
      onLeave={clearPreview}
      onBlur={clearFocusPreview}
      onPin={pin}
      onDismiss={dismissTooltip}
      onPosition={syncPointPosition}
      tooltipId="impact-tooltip"
    />
  ), [clearFocusPreview, clearPreview, dismissTooltip, pin, pinned, preview, previewFromFocus, previewPoint, syncPointPosition]);

  if (!data.length) {
    return <ChartEmpty reason="No injury profiles have a finite incidence and positive mean severity needed for this logarithmic chart." />;
  }

  const activePoint = pinned ?? preview;
  const tooltipTop = activePoint && activePoint.y < 190 ? activePoint.y + 16 : (activePoint?.y ?? 0) - 148;
  const visiblePointX = (activePoint?.x ?? 0) - scrollLeft;
  const tooltipLeft = visiblePointX > 430 ? visiblePointX - 296 : visiblePointX + 16;

  return (
    <section aria-label={`Risk Matrix of incidence and severity. Each numbered dot matches the diagnosis key below. Horizontal position is incidence. Vertical position is logarithmic mean severity from ${number(severityDomain[0])} to ${number(severityDomain[1])} days. Focus a dot to preview its values, then press Enter or Space to pin it.`}>
      <div className="relative">
        <div
          onScroll={(event) => setScrollLeft(event.currentTarget.scrollLeft)}
          className="overflow-x-auto pb-2"
        >
          <div ref={chartRef} onPointerDown={dismissTooltip} className="h-[520px] sm:min-w-[680px] [&_.recharts-wrapper:focus]:outline-none [&_svg:focus]:outline-none">
            <ResponsiveContainer width="100%" height="100%">
              <ScatterChart accessibilityLayer margin={{ top: 30, right: 30, bottom: 34, left: 24 }}>
                <defs>
                  <linearGradient id="impact-risk-gradient" x1="0%" y1="100%" x2="100%" y2="0%">
                    <stop offset="0%" stopColor="#2fbf83" />
                    <stop offset="45%" stopColor="#d8cc55" />
                    <stop offset="72%" stopColor="#ed8b43" />
                    <stop offset="100%" stopColor="#df4f52" />
                  </linearGradient>
                </defs>
                <ReferenceArea
                  x1={0}
                  x2={maxIncidence}
                  y1={severityDomain[0]}
                  y2={severityDomain[1]}
                  fill="url(#impact-risk-gradient)"
                  fillOpacity={0.25}
                  stroke="none"
                  ifOverflow="hidden"
                />
                <CartesianGrid stroke={GRID} strokeDasharray="3 5" />
                <XAxis
                  type="number"
                  dataKey="incidence_per_1000h"
                  domain={[0, maxIncidence]}
                  name="Incidence"
                  tickFormatter={formatAxisTick}
                  tick={{ fill: AXIS, fontSize: 11 }}
                  tickLine={false}
                  axisLine={AXIS_LINE}
                  label={{ value: 'Incidence, Injuries /1,000 h', position: 'bottom', fill: AXIS, fontSize: 12, offset: 16 }}
                />
                <YAxis
                  type="number"
                  dataKey="mean_severity_days"
                  domain={severityDomain}
                  scale="log"
                  ticks={severityTicks}
                  name="Mean Severity"
                  tickFormatter={formatAxisTick}
                  width={62}
                  tick={{ fill: AXIS, fontSize: 11 }}
                  tickLine={false}
                  axisLine={AXIS_LINE}
                  label={{ value: 'Mean Severity, Days (Logarithmic Scale)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 0, style: Y_TITLE_STYLE }}
                />
                <Scatter
                  data={data}
                  isAnimationActive={false}
                  shape={renderImpactDot}
                />
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
      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-[11px] text-muted-foreground" aria-label="Risk Matrix key">
        <span className="font-medium text-foreground">Impact Zone</span>
        <span className="inline-flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm bg-[#2fbf83]/60" />Lower Incidence And Severity</span>
        <span className="inline-flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm bg-[#e5bd45]/70" />One Measure Elevated</span>
        <span className="inline-flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm bg-[#df4f52]/70" />Higher Incidence And Severity</span>
      </div>
      <ol className="mt-4 columns-1 gap-6 border-t border-border/60 pt-4 text-sm sm:columns-2 lg:columns-4" aria-label="Diagnoses shown on the Risk Matrix">
        {data.map((row) => (
          <li key={row.impactKey} className="mb-2 grid break-inside-avoid grid-cols-[1.5rem_minmax(0,1fr)] items-center gap-2">
            <span className="grid h-5 w-5 place-items-center rounded-full bg-[#173f52] text-[10px] font-bold text-white">{row.displayIndex}</span>
            <span className="min-w-0 truncate text-foreground">{row.label}</span>
          </li>
        ))}
      </ol>
      {/* Not decoration: this is the only place the chart admits it is hiding rows. */}
      {nonPositiveSeverityRows.length > 0 && (
        <p className="mt-2 text-xs text-muted-foreground">
          {count(nonPositiveSeverityRows.length)} profile{nonPositiveSeverityRows.length === 1 ? '' : 's'} with non-positive mean severity {nonPositiveSeverityRows.length === 1 ? 'is' : 'are'} not shown because a logarithmic scale cannot represent those values.
        </p>
      )}
    </section>
  );
}
