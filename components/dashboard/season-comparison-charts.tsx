'use client';

import { useCallback, useEffect, useId, useMemo, useState } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Scatter,
  ScatterChart,
  XAxis,
  YAxis,
} from 'recharts';

export type ComparisonSeasonPoint = {
  season: string;
  exposureHours: number | null;
  timeLossInjuries: number | null;
  incidence: number | null;
  severity: number | null;
  burden: number | null;
};

export type ComparisonMonthlyPoint = {
  month: string;
  prior: number | null;
  current: number | null;
};

const OLD_COLOUR = 'hsl(var(--chart-3))';
const CURRENT_COLOUR = 'hsl(var(--chart-1))';
const GRID_COLOUR = 'hsl(var(--border))';
const AXIS_COLOUR = 'hsl(var(--muted-foreground))';
const ACCENT_COLOUR = 'hsl(var(--chart-2))';

function finite(value: number | null | undefined): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function formatNumber(value: number | null | undefined, digits = 1): string {
  if (!finite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(value);
}

function domainFor(values: Array<number | null>, zeroFloor = false): [number, number] {
  const usable = values.filter(finite);
  if (!usable.length) return [0, 1];
  const low = Math.min(...usable);
  const high = Math.max(...usable);
  const span = Math.max(high - low, Math.abs(high) * 0.1, 0.5);
  const domainLow = low - span * 0.55;
  const domainHigh = high + span * 0.55;
  return [zeroFloor ? Math.max(0, domainLow) : domainLow, domainHigh];
}

function SeasonLegend({ burden = false }: { burden?: boolean }) {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs font-semibold" aria-label="Chart Legend">
      <span className="flex items-center gap-1.5 text-blue-300">
        <span className="h-2.5 w-2.5 rounded-full bg-blue-400" aria-hidden="true" />
        2024-25
      </span>
      <span className="flex items-center gap-1.5 text-cyan-200">
        <span className="h-2.5 w-2.5 rounded-full bg-cyan-300" aria-hidden="true" />
        2025-26
      </span>
      {burden && (
        <span className="flex items-center gap-1.5 text-muted-foreground">
          <span className="grid h-4 w-4 place-items-center rounded-full border border-muted-foreground/70" aria-hidden="true" />
          Circle Area: Burden
        </span>
      )}
    </div>
  );
}

type InteractiveDatum = { interactionKey: string };

function useInteractiveTooltip<T extends InteractiveDatum>(resetKey: string) {
  const [preview, setPreview] = useState<T>();
  const [pinned, setPinned] = useState<T>();
  const dismiss = useCallback(() => {
    setPreview(undefined);
    setPinned(undefined);
  }, []);

  useEffect(() => dismiss(), [dismiss, resetKey]);
  useEffect(() => {
    if (!pinned) return;
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') dismiss();
    };
    document.addEventListener('keydown', dismissOnEscape);
    return () => document.removeEventListener('keydown', dismissOnEscape);
  }, [dismiss, pinned]);

  return {
    active: pinned ?? preview,
    pinned,
    preview: (datum: T) => setPreview(datum),
    clearPreview: () => setPreview(undefined),
    pin: (datum: T) => setPinned(datum),
    dismiss,
  };
}

type ImpactPlotPoint = ComparisonSeasonPoint & {
  interactionKey: string;
  radius: number | null;
  seasonIndex: number;
};

type ScatterShapeProps = {
  cx?: number;
  cy?: number;
  payload?: ImpactPlotPoint;
};

function ImpactPoint({
  cx,
  cy,
  payload,
  activeKey,
  pinnedKey,
  tooltipId,
  onPreview,
  onClearPreview,
  onPin,
  onDismiss,
}: ScatterShapeProps & {
  activeKey?: string;
  pinnedKey?: string;
  tooltipId: string;
  onPreview: (point: ImpactPlotPoint) => void;
  onClearPreview: () => void;
  onPin: (point: ImpactPlotPoint) => void;
  onDismiss: () => void;
}) {
  if (cx === undefined || cy === undefined || !payload) return null;
  const colour = payload.seasonIndex === 0 ? OLD_COLOUR : CURRENT_COLOUR;
  const selected = pinnedKey === payload.interactionKey;
  const active = activeKey === payload.interactionKey;
  const exact = `${payload.season}: ${formatNumber(payload.timeLossInjuries, 0)} injuries, ${formatNumber(payload.exposureHours, 0)} player-hours, incidence ${formatNumber(payload.incidence)}, severity ${formatNumber(payload.severity)} days, burden ${formatNumber(payload.burden, 0)} days per 1,000 player-hours${payload.radius === null ? '. Bubble area unavailable because the approved burden value is missing.' : ''}`;
  const accessibleLabel = `${exact}. ${selected ? 'Pinned. Press Escape to dismiss.' : 'Press Enter or Space to pin.'}`;
  const visualRadius = payload.radius ?? 7;

  return (
    <g>
      {active && (
        <circle
          cx={cx}
          cy={cy}
          r={Math.max(visualRadius + 4, 15)}
          fill="none"
          stroke="hsl(var(--foreground))"
          strokeWidth={selected ? 2 : 1.5}
          pointerEvents="none"
        />
      )}
      {payload.radius === null ? (
        <rect
          x={cx - 7}
          y={cy - 7}
          width={14}
          height={14}
          fill="transparent"
          stroke={colour}
          strokeWidth={2}
          strokeDasharray="3 2"
          pointerEvents="none"
        />
      ) : (
        <circle
          cx={cx}
          cy={cy}
          r={visualRadius}
          fill={colour}
          fillOpacity={0.72}
          stroke={colour}
          strokeWidth={2}
          pointerEvents="none"
        />
      )}
      <text
        x={cx}
        y={cy - visualRadius - 9}
        textAnchor="middle"
        fill={colour}
        fontSize={12}
        fontWeight={700}
        stroke="hsl(var(--card))"
        strokeWidth={4}
        paintOrder="stroke"
        pointerEvents="none"
      >
        {payload.season}
      </text>
      <circle
        cx={cx}
        cy={cy}
        r={Math.max(22, visualRadius)}
        fill="transparent"
        tabIndex={0}
        role="button"
        aria-label={accessibleLabel}
        aria-describedby={tooltipId}
        aria-pressed={selected}
        data-impact-target={payload.interactionKey}
        className="outline-none"
        onMouseEnter={() => onPreview(payload)}
        onMouseLeave={onClearPreview}
        onFocus={() => onPreview(payload)}
        onBlur={onClearPreview}
        onPointerDown={(event) => {
          event.stopPropagation();
          onPin(payload);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Escape') {
            event.preventDefault();
            onDismiss();
          }
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            onPin(payload);
          }
        }}
      />
    </g>
  );
}

function ImpactTooltip({ id, point, pinned }: { id: string; point?: ImpactPlotPoint; pinned: boolean }) {
  if (!point) {
    return <div id={id} role="tooltip" aria-live="polite" className="sr-only">Focus or hover over a season point to view its values.</div>;
  }
  return (
    <div id={id} role="tooltip" aria-live="polite" className="rounded-lg border border-border/70 bg-background/80 px-4 py-3 text-sm shadow-sm">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="font-semibold text-foreground">{point.season}</p>
        {pinned && <span className="text-xs text-muted-foreground">Pinned. Press Escape to dismiss.</span>}
      </div>
      <dl className="mt-2 grid gap-x-5 gap-y-1 text-xs sm:grid-cols-2 lg:grid-cols-5">
        <div><dt className="text-muted-foreground">Injuries</dt><dd className="font-semibold tabular-nums">{formatNumber(point.timeLossInjuries, 0)}</dd></div>
        <div><dt className="text-muted-foreground">Player-Hours</dt><dd className="font-semibold tabular-nums">{formatNumber(point.exposureHours, 0)}</dd></div>
        <div><dt className="text-muted-foreground">Incidence</dt><dd className="font-semibold tabular-nums">{formatNumber(point.incidence)} /1,000 h</dd></div>
        <div><dt className="text-muted-foreground">Mean Severity</dt><dd className="font-semibold tabular-nums">{formatNumber(point.severity)} days</dd></div>
        <div><dt className="text-muted-foreground">Burden</dt><dd className="font-semibold tabular-nums">{formatNumber(point.burden, 0)} days/1,000 h</dd></div>
      </dl>
    </div>
  );
}

export function ImpactBubbles({ seasons }: { seasons: ComparisonSeasonPoint[] }) {
  const id = useId().replace(/:/g, '');
  const tooltipId = `impact-tooltip-${id}`;
  const burdens = seasons.map((row) => row.burden).filter(finite);
  const maxBurden = Math.max(...burdens, 0);
  const data = useMemo<ImpactPlotPoint[]>(() => seasons
    .filter((row) => finite(row.incidence) && finite(row.severity))
    .map((row, seasonIndex) => ({
      ...row,
      interactionKey: row.season,
      seasonIndex,
      radius: finite(row.burden) && maxBurden > 0
        ? Math.sqrt(Math.max(row.burden, 0) / maxBurden) * 32
        : null,
    })), [maxBurden, seasons]);
  const resetKey = data.map((row) => `${row.interactionKey}-${row.incidence}-${row.severity}-${row.burden}`).join('|');
  const interaction = useInteractiveTooltip<ImpactPlotPoint>(resetKey);
  const xDomain = domainFor(data.map((row) => row.incidence), true);
  const yDomain = domainFor(data.map((row) => row.severity), true);
  const renderPoint = useCallback((shapeProps: ScatterShapeProps) => (
    <ImpactPoint
      {...shapeProps}
      activeKey={interaction.active?.interactionKey}
      pinnedKey={interaction.pinned?.interactionKey}
      tooltipId={tooltipId}
      onPreview={interaction.preview}
      onClearPreview={interaction.clearPreview}
      onPin={interaction.pin}
      onDismiss={interaction.dismiss}
    />
  ), [interaction, tooltipId]);

  return (
    <section className="min-w-0 space-y-3" aria-label="Injury Impact By Season. The horizontal axis shows injury incidence. The vertical axis shows mean severity. Circle area represents burden. Focus a point to preview it, then press Enter or Space to pin it.">
      <div className="h-[390px] w-full min-w-0 sm:h-[460px] [&_.recharts-wrapper:focus]:outline-none [&_svg:focus]:outline-none">
        <ResponsiveContainer width="100%" height="100%">
          <ScatterChart accessibilityLayer margin={{ top: 54, right: 38, bottom: 54, left: 32 }}>
            <defs>
              <marker id={`impact-arrow-${id}`} viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto">
                <path d="M 0 0 L 8 4 L 0 8 z" fill={ACCENT_COLOUR} />
              </marker>
            </defs>
            <CartesianGrid stroke={GRID_COLOUR} strokeDasharray="3 5" />
            <XAxis
              type="number"
              dataKey="incidence"
              domain={xDomain}
              tick={{ fill: AXIS_COLOUR, fontSize: 11 }}
              tickFormatter={(value: number) => formatNumber(value)}
              tickLine={false}
              axisLine={{ stroke: AXIS_COLOUR }}
              label={{ value: 'Injury Incidence, Injuries /1,000 h', position: 'bottom', offset: 18, fill: AXIS_COLOUR, fontSize: 12 }}
            />
            <YAxis
              type="number"
              dataKey="severity"
              domain={yDomain}
              width={72}
              tick={{ fill: AXIS_COLOUR, fontSize: 11 }}
              tickFormatter={(value: number) => formatNumber(value)}
              tickLine={false}
              axisLine={{ stroke: AXIS_COLOUR }}
              label={{ value: 'Mean Severity, Days', angle: -90, position: 'insideLeft', offset: -6, fill: AXIS_COLOUR, fontSize: 12, style: { textAnchor: 'middle' } }}
            />
            <Scatter
              data={data}
              isAnimationActive={false}
              line={{ stroke: ACCENT_COLOUR, strokeWidth: 2, strokeDasharray: '5 4', markerEnd: `url(#impact-arrow-${id})` }}
              lineType="joint"
              shape={renderPoint}
            />
          </ScatterChart>
        </ResponsiveContainer>
      </div>
      <ImpactTooltip id={tooltipId} point={interaction.active} pinned={Boolean(interaction.pinned)} />
      <SeasonLegend burden />
      <p className="sr-only">A dashed arrow shows the sequence from 2024-25 to 2025-26, not causality.</p>
    </section>
  );
}

const DISPLAY_MONTHS = ['Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];

function monthLabel(month: string): string {
  const lower = month.trim().toLowerCase();
  return DISPLAY_MONTHS.find((item) => item.toLowerCase() === lower || item.toLowerCase().startsWith(lower.slice(0, 3))) ?? month;
}

type MonthlyPlotPoint = ComparisonMonthlyPoint & {
  priorPlot: number;
  currentPlot: number;
};

type MonthlySelection = InteractiveDatum & {
  month: string;
  season: string;
  value: number | null;
  colour: string;
};

type BarShapeProps = {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  payload?: MonthlyPlotPoint;
};

function MonthlyBar({
  x,
  y,
  width,
  height,
  payload,
  series,
  season,
  colour,
  activeKey,
  pinnedKey,
  tooltipId,
  onPreview,
  onClearPreview,
  onPin,
  onDismiss,
}: BarShapeProps & {
  series: 'prior' | 'current';
  season: string;
  colour: string;
  activeKey?: string;
  pinnedKey?: string;
  tooltipId: string;
  onPreview: (selection: MonthlySelection) => void;
  onClearPreview: () => void;
  onPin: (selection: MonthlySelection) => void;
  onDismiss: () => void;
}) {
  if (x === undefined || y === undefined || width === undefined || height === undefined || !payload) return null;
  const interactionKey = `${payload.month}-${series}`;
  const value = payload[series];
  const selection = { interactionKey, month: monthLabel(payload.month), season, value, colour };
  const selected = pinnedKey === interactionKey;
  const active = activeKey === interactionKey;
  const targetHeight = Math.max(44, height);
  const targetWidth = Math.max(44, width);
  const accessibleLabel = `${selection.month} ${season}: ${formatNumber(value, 0)} injuries. ${selected ? 'Pinned. Press Escape to dismiss.' : 'Press Enter or Space to pin.'}`;

  return (
    <g>
      <rect
        x={x}
        y={y}
        width={width}
        height={Math.max(height, value === 0 ? 2 : 0)}
        rx={2}
        fill={colour}
        stroke={active ? 'hsl(var(--foreground))' : colour}
        strokeWidth={active ? 2 : 0}
        pointerEvents="none"
      />
      <rect
        x={x + width / 2 - targetWidth / 2}
        y={y + height - targetHeight}
        width={targetWidth}
        height={targetHeight}
        fill="transparent"
        tabIndex={0}
        role="button"
        aria-label={accessibleLabel}
        aria-describedby={tooltipId}
        aria-pressed={selected}
        data-monthly-target={interactionKey}
        className="outline-none"
        onMouseEnter={() => onPreview(selection)}
        onMouseLeave={onClearPreview}
        onFocus={() => onPreview(selection)}
        onBlur={onClearPreview}
        onPointerDown={(event) => {
          event.stopPropagation();
          onPin(selection);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Escape') {
            event.preventDefault();
            onDismiss();
          }
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            onPin(selection);
          }
        }}
      />
    </g>
  );
}

function MonthlyTooltip({ id, selection, pinned }: { id: string; selection?: MonthlySelection; pinned: boolean }) {
  if (!selection) {
    return <div id={id} role="tooltip" aria-live="polite" className="sr-only">Focus or hover over a monthly bar to view its value.</div>;
  }
  return (
    <div id={id} role="tooltip" aria-live="polite" className="rounded-lg border border-border/70 bg-background/80 px-4 py-3 text-sm shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-semibold text-foreground">{selection.month} · {selection.season}</p>
        {pinned && <span className="text-xs text-muted-foreground">Pinned. Press Escape to dismiss.</span>}
      </div>
      <p className="mt-1 text-xs text-muted-foreground">
        Injuries: <span className="font-semibold tabular-nums text-foreground">{formatNumber(selection.value, 0)}</span>
      </p>
    </div>
  );
}

export function MonthlyBars({ monthly }: { monthly: ComparisonMonthlyPoint[] }) {
  const id = useId().replace(/:/g, '');
  const tooltipId = `monthly-tooltip-${id}`;
  const data = useMemo<MonthlyPlotPoint[]>(() => monthly.map((row) => ({
    ...row,
    priorPlot: finite(row.prior) ? row.prior : 0,
    currentPlot: finite(row.current) ? row.current : 0,
  })), [monthly]);
  const values = monthly.flatMap((row) => [row.prior, row.current]).filter(finite);
  const yMax = Math.ceil((Math.max(...values, 0) * 1.15) / 5) * 5 || 5;
  const resetKey = data.map((row) => `${row.month}-${row.prior}-${row.current}`).join('|');
  const interaction = useInteractiveTooltip<MonthlySelection>(resetKey);
  const commonShapeProps = {
    activeKey: interaction.active?.interactionKey,
    pinnedKey: interaction.pinned?.interactionKey,
    tooltipId,
    onPreview: interaction.preview,
    onClearPreview: interaction.clearPreview,
    onPin: interaction.pin,
    onDismiss: interaction.dismiss,
  };

  return (
    <section className="min-w-0 space-y-3" aria-label="Injuries By Month. Paired bars compare injuries from September through June. Focus a bar to preview it, then press Enter or Space to pin it.">
      <div className="h-[350px] w-full min-w-0 sm:h-[420px] [&_.recharts-wrapper:focus]:outline-none [&_svg:focus]:outline-none">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart accessibilityLayer data={data} margin={{ top: 24, right: 24, bottom: 48, left: 20 }} barGap={4} barCategoryGap="24%">
            <CartesianGrid stroke={GRID_COLOUR} strokeDasharray="3 5" vertical={false} />
            <XAxis
              dataKey="month"
              tickFormatter={monthLabel}
              tick={{ fill: AXIS_COLOUR, fontSize: 11 }}
              tickLine={false}
              axisLine={{ stroke: AXIS_COLOUR }}
              label={{ value: 'Month', position: 'bottom', offset: 18, fill: AXIS_COLOUR, fontSize: 12 }}
            />
            <YAxis
              domain={[0, yMax]}
              tick={{ fill: AXIS_COLOUR, fontSize: 11 }}
              tickFormatter={(value: number) => formatNumber(value, 0)}
              tickLine={false}
              axisLine={{ stroke: AXIS_COLOUR }}
              width={58}
              label={{ value: 'Injury Count', angle: -90, position: 'insideLeft', offset: -2, fill: AXIS_COLOUR, fontSize: 12, style: { textAnchor: 'middle' } }}
            />
            <Bar
              dataKey="priorPlot"
              name="2024-25"
              fill={OLD_COLOUR}
              isAnimationActive={false}
              maxBarSize={30}
              shape={(shapeProps: unknown) => <MonthlyBar {...shapeProps as BarShapeProps} {...commonShapeProps} series="prior" season="2024-25" colour={OLD_COLOUR} />}
            />
            <Bar
              dataKey="currentPlot"
              name="2025-26"
              fill={CURRENT_COLOUR}
              isAnimationActive={false}
              maxBarSize={30}
              shape={(shapeProps: unknown) => <MonthlyBar {...shapeProps as BarShapeProps} {...commonShapeProps} series="current" season="2025-26" colour={CURRENT_COLOUR} />}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <MonthlyTooltip id={tooltipId} selection={interaction.active} pinned={Boolean(interaction.pinned)} />
      <SeasonLegend />
    </section>
  );
}

export { domainFor };
