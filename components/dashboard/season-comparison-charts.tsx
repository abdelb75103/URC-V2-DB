'use client';

import { useId, type ReactNode, type SVGProps } from 'react';

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
const TEXT_COLOUR = 'hsl(var(--foreground))';
const MUTED_COLOUR = 'hsl(var(--muted-foreground))';
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
    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs font-semibold" aria-label="Chart legend">
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
          Circle area: Burden
        </span>
      )}
    </div>
  );
}

function scale(value: number, low: number, high: number, start: number, size: number): number {
  if (high === low) return start + size / 2;
  return start + ((value - low) / (high - low)) * size;
}

function SvgText({
  children,
  ...props
}: SVGProps<SVGTextElement> & { children: string }) {
  return <text {...props}>{children}</text>;
}

function ChartShell({
  title,
  description,
  labelledBy,
  viewBox,
  className,
  children,
}: {
  title: string;
  description: string;
  labelledBy: string;
  viewBox: string;
  className: string;
  children: ReactNode;
}) {
  return (
    <svg
      className={className}
      viewBox={viewBox}
      role="img"
      aria-labelledby={`${labelledBy}-title ${labelledBy}-description`}
      focusable="false"
    >
      <title id={`${labelledBy}-title`}>{title}</title>
      <desc id={`${labelledBy}-description`}>{description}</desc>
      {children}
    </svg>
  );
}

export function ImpactBubbles({ seasons }: { seasons: ComparisonSeasonPoint[] }) {
  const id = useId().replace(/:/g, '');
  const labelId = `impact-${id}`;
  const width = 520;
  const height = 350;
  const margin = { top: 38, right: 22, bottom: 62, left: 62 };
  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;
  const [xLow, xHigh] = domainFor(seasons.map((row) => row.incidence), true);
  const [yLow, yHigh] = domainFor(seasons.map((row) => row.severity));
  const x = (value: number) => scale(value, xLow, xHigh, margin.left, innerWidth);
  const y = (value: number) => margin.top + innerHeight - scale(value, yLow, yHigh, 0, innerHeight);
  const burdens = seasons.map((row) => row.burden).filter(finite);
  const maxBurden = Math.max(...burdens, 0);
  const radius = (value: number | null) => {
    if (!finite(value)) return null;
    if (maxBurden <= 0) return 0;
    return Math.sqrt(Math.max(value, 0) / maxBurden) * 30;
  };
  const ticks = 5;
  const points = seasons.map((row) => ({
    ...row,
    plottable: finite(row.incidence) && finite(row.severity),
    x: finite(row.incidence) ? x(row.incidence) : margin.left + innerWidth / 2,
    y: finite(row.severity) ? y(row.severity) : margin.top + innerHeight / 2,
    radius: radius(row.burden),
  }));
  const first = points[0];
  const second = points[1];
  const pointsDiffer = first && second
    && finite(first.incidence) && finite(second.incidence)
    && finite(first.severity) && finite(second.severity)
    && (first.x !== second.x || first.y !== second.y);
  const angle = pointsDiffer && first && second
    ? Math.atan2(second.y - first.y, second.x - first.x)
    : 0;

  return (
    <div className="space-y-3">
      <ChartShell
        title="Injury Impact By Season"
        description="The horizontal axis shows time-loss injuries per 1,000 player-hours. The vertical axis shows mean days lost per time-loss injury. Circle area represents burden. A dashed arrow shows the sequence from 2024-25 to 2025-26, not causality."
        labelledBy={labelId}
        viewBox={`0 0 ${width} ${height}`}
        className="block h-[300px] w-full sm:h-[350px]"
      >
        <defs>
          <marker id={`${labelId}-arrow`} viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto">
            <path d="M 0 0 L 8 4 L 0 8 z" fill={ACCENT_COLOUR} />
          </marker>
        </defs>
        <rect x={margin.left} y={margin.top} width={innerWidth} height={innerHeight} fill="transparent" stroke={GRID_COLOUR} />
        {Array.from({ length: ticks }, (_, index) => {
          const ratio = index / (ticks - 1);
          const xPosition = margin.left + ratio * innerWidth;
          const yPosition = margin.top + innerHeight - ratio * innerHeight;
          return (
            <g key={index}>
              <line x1={xPosition} y1={margin.top} x2={xPosition} y2={margin.top + innerHeight} stroke={GRID_COLOUR} strokeWidth="1" />
              <line x1={margin.left} y1={yPosition} x2={margin.left + innerWidth} y2={yPosition} stroke={GRID_COLOUR} strokeWidth="1" />
              <SvgText x={xPosition} y={margin.top + innerHeight + 20} textAnchor="middle" fill={MUTED_COLOUR} fontSize="10">{formatNumber(xLow + ratio * (xHigh - xLow))}</SvgText>
              <SvgText x={margin.left - 9} y={yPosition + 4} textAnchor="end" fill={MUTED_COLOUR} fontSize="10">{formatNumber(yLow + ratio * (yHigh - yLow))}</SvgText>
            </g>
          );
        })}
        <SvgText x={margin.left + innerWidth / 2} y={height - 11} textAnchor="middle" fill={TEXT_COLOUR} fontSize="10" fontWeight="600">TL injuries per 1,000 player-hours</SvgText>
        <SvgText x="15" y={margin.top + innerHeight / 2} textAnchor="middle" transform={`rotate(-90 15 ${margin.top + innerHeight / 2})`} fill={TEXT_COLOUR} fontSize="10" fontWeight="600">Mean days lost per TL injury</SvgText>
        {pointsDiffer && first && second && (
          <line
            x1={first.x + Math.cos(angle) * (first.radius ?? 0)}
            y1={first.y + Math.sin(angle) * (first.radius ?? 0)}
            x2={second.x - Math.cos(angle) * ((second.radius ?? 0) + 7)}
            y2={second.y - Math.sin(angle) * ((second.radius ?? 0) + 7)}
            stroke={ACCENT_COLOUR}
            strokeWidth="2"
            strokeDasharray="5 4"
            markerEnd={`url(#${labelId}-arrow)`}
            aria-hidden="true"
          />
        )}
        {points.map((point, index) => {
          if (!point.plottable) return null;
          const labelY = index === 0
            ? Math.max(margin.top + 14, point.y - (point.radius ?? 0) - 8)
            : Math.min(margin.top + innerHeight - 4, point.y + (point.radius ?? 0) + 16);
          const exact = `${point.season}: ${formatNumber(point.timeLossInjuries, 0)} time-loss injuries, ${formatNumber(point.exposureHours, 0)} player-hours, incidence ${formatNumber(point.incidence)}, severity ${formatNumber(point.severity)} days, burden ${formatNumber(point.burden, 0)} days per 1,000 player-hours${point.radius === null ? '. Bubble area unavailable because the approved burden value is missing.' : ''}`;
          return (
            <g key={point.season} aria-label={exact} tabIndex={0}>
              <title>{exact}</title>
              {point.radius !== null ? (
                <circle
                  cx={point.x}
                  cy={point.y}
                  r={point.radius}
                  fill={index === 0 ? OLD_COLOUR : CURRENT_COLOUR}
                  fillOpacity="0.7"
                  stroke={index === 0 ? OLD_COLOUR : CURRENT_COLOUR}
                  strokeWidth="2"
                />
              ) : (
                <rect
                  x={point.x - 6}
                  y={point.y - 6}
                  width="12"
                  height="12"
                  fill="transparent"
                  stroke={index === 0 ? OLD_COLOUR : CURRENT_COLOUR}
                  strokeWidth="2"
                  strokeDasharray="3 2"
                />
              )}
              <SvgText x={point.x} y={labelY} textAnchor="middle" fill={index === 0 ? OLD_COLOUR : CURRENT_COLOUR} fontSize="12" fontWeight="700" stroke="hsl(var(--card))" strokeWidth="4" paintOrder="stroke">{point.season}</SvgText>
            </g>
          );
        })}
      </ChartShell>
      <SeasonLegend burden />
    </div>
  );
}

const DISPLAY_MONTHS = ['Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];

function monthLabel(month: string): string {
  const lower = month.trim().toLowerCase();
  return DISPLAY_MONTHS.find((item) => item.toLowerCase() === lower || item.toLowerCase().startsWith(lower.slice(0, 3))) ?? month;
}

export function MonthlyBars({ monthly }: { monthly: ComparisonMonthlyPoint[] }) {
  const id = useId().replace(/:/g, '');
  const labelId = `monthly-${id}`;
  const width = 520;
  const height = 310;
  const margin = { top: 20, right: 16, bottom: 52, left: 46 };
  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;
  const values = monthly.flatMap((row) => [row.prior, row.current]).filter(finite);
  const yMax = Math.ceil((Math.max(...values, 0) * 1.15) / 5) * 5 || 5;
  const y = (value: number) => margin.top + innerHeight - (value / yMax) * innerHeight;
  const groupWidth = innerWidth / Math.max(monthly.length, 1);
  const barWidth = Math.min(15, groupWidth * 0.3);
  const exactMonthly = monthly.map((row) => `${monthLabel(row.month)}: ${formatNumber(row.prior, 0)} time-loss injuries in 2024-25; ${formatNumber(row.current, 0)} in 2025-26`).join('. ');

  return (
    <div className="space-y-3">
      <ChartShell
        title="Monthly Time-Loss Injury Counts By Season"
        description={`Paired vertical bars compare September through June. ${exactMonthly}`}
        labelledBy={labelId}
        viewBox={`0 0 ${width} ${height}`}
        className="block h-[280px] w-full sm:h-[310px]"
      >
      <rect x={margin.left} y={margin.top} width={innerWidth} height={innerHeight} fill="transparent" stroke={GRID_COLOUR} />
      {Array.from({ length: 5 }, (_, index) => {
        const value = (yMax * index) / 4;
        const yPosition = y(value);
        return (
          <g key={index}>
            <line x1={margin.left} y1={yPosition} x2={margin.left + innerWidth} y2={yPosition} stroke={GRID_COLOUR} strokeWidth="1" />
            <SvgText x={margin.left - 8} y={yPosition + 4} textAnchor="end" fill={MUTED_COLOUR} fontSize="10">{formatNumber(value, 0)}</SvgText>
          </g>
        );
      })}
      {monthly.map((row, index) => {
        const centre = margin.left + groupWidth * (index + 0.5);
        const valuesForMonth: Array<[number | null, string, string]> = [
          [row.prior, '2024-25', OLD_COLOUR],
          [row.current, '2025-26', CURRENT_COLOUR],
        ];
        return (
          <g key={`${row.month}-${index}`}>
            <SvgText x={centre} y={margin.top + innerHeight + 19} textAnchor="middle" fill={MUTED_COLOUR} fontSize="10">{monthLabel(row.month)}</SvgText>
            {valuesForMonth.map(([value, season, colour], seriesIndex) => (
              <rect
                key={season}
                x={centre + (seriesIndex === 0 ? -barWidth - 1.5 : 1.5)}
                y={finite(value) ? y(value) : y(0)}
                width={barWidth}
                height={finite(value) ? Math.max(0, margin.top + innerHeight - y(value)) : 0}
                rx="2"
                fill={colour}
                aria-label={`${monthLabel(row.month)} ${season}: ${formatNumber(value, 0)} time-loss injuries`}
              />
            ))}
          </g>
        );
      })}
      <SvgText x={margin.left + innerWidth / 2} y={height - 10} textAnchor="middle" fill={TEXT_COLOUR} fontSize="10" fontWeight="600">Month</SvgText>
      <SvgText x="14" y={margin.top + innerHeight / 2} textAnchor="middle" transform={`rotate(-90 14 ${margin.top + innerHeight / 2})`} fill={TEXT_COLOUR} fontSize="10" fontWeight="600">Time-loss injury count</SvgText>
      </ChartShell>
      <SeasonLegend />
    </div>
  );
}

export { domainFor };
