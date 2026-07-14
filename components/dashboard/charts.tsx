'use client';

import {
  CartesianGrid,
  Cell,
  LabelList,
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
import type { InjuryProfileRow } from '@/lib/reporting-types';

const AXIS = 'hsl(0 0% 75%)';
const GRID = 'hsl(205 44% 25% / 0.55)';

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
    <div className="max-w-56 rounded-md border border-border bg-popover px-3 py-2 text-xs shadow-lg">
      <p className="font-semibold text-foreground">{row.label}</p>
      <dl className="mt-1 grid grid-cols-2 gap-x-3 gap-y-0.5 text-muted-foreground">
        <dt>Incidence</dt><dd className="text-right tabular-nums text-foreground">{format(row.incidence_per_1000h)}</dd>
        <dt>Severity</dt><dd className="text-right tabular-nums text-foreground">{format(row.mean_severity_days)} d</dd>
        <dt>Burden</dt><dd className="text-right tabular-nums text-foreground">{format(row.burden_per_1000h)}</dd>
        <dt>Injuries</dt><dd className="text-right tabular-nums text-foreground">{row.time_loss_injuries}</dd>
      </dl>
    </div>
  );
}

function format(value: number | null) {
  if (value === null || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', { maximumFractionDigits: 1 }).format(value);
}

function formatAxisTick(value: number) {
  return new Intl.NumberFormat('en-IE', { maximumFractionDigits: 1 }).format(value);
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
    return <div className="grid h-72 place-items-center text-sm text-muted-foreground">No injury profile data available.</div>;
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
    <div role="img" aria-label="Injury impact bubble plot. Incidence is on the horizontal axis, mean severity is on the vertical axis, and bubble area represents burden.">
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
                label={{ value: 'Incidence per 1,000 player-hours', position: 'bottom', fill: AXIS, fontSize: 12, offset: 16 }}
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
                label={{ value: 'Mean severity (days)', angle: -90, position: 'insideLeft', fill: AXIS, fontSize: 12, offset: 0 }}
              />
              <ZAxis type="number" dataKey="bubble_burden" range={[90, 1_500]} name="Burden" />
              <Tooltip cursor={false} content={<ImpactTooltip />} />
              <Scatter data={chartData} isAnimationActive={false}>
                {chartData.map((row) => (
                  <Cell key={`${row.setting}-${row.code}`} fill={profileColor(row.code)} fillOpacity={0.82} stroke="hsl(0 0% 94%)" strokeOpacity={0.55} />
                ))}
                <LabelList dataKey="displayLabel" position="top" fill="hsl(0 0% 90%)" fontSize={11} />
              </Scatter>
            </ScatterChart>
          </ResponsiveContainer>
        </div>
      </div>
      <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs text-muted-foreground">
        <span><span className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-green-500/50" />Lower frequency + lower severity</span>
        <span>Dashed lines show category medians</span>
        <span><span className="mr-1 inline-block h-2.5 w-2.5 rounded-sm bg-red-500/50" />Priority: frequent + severe</span>
      </div>
    </div>
  );
}
