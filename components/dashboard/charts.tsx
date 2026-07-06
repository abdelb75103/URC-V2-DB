'use client';

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

const AXIS = 'hsl(0 0% 75%)';
const GRID = 'hsl(205 44% 25% / 0.5)';

export const CHART_COLORS = [
  'hsl(var(--chart-1))',
  'hsl(var(--chart-2))',
  'hsl(var(--chart-3))',
  'hsl(var(--chart-4))',
  'hsl(var(--chart-5))',
];

function TooltipBox({
  active,
  payload,
  label,
  unit,
}: {
  active?: boolean;
  payload?: Array<{ value?: number | string }>;
  label?: string | number;
  unit?: string;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border border-border bg-popover px-3 py-2 text-xs shadow-md">
      <p className="mb-0.5 font-medium text-foreground">{label}</p>
      <p className="text-muted-foreground">
        <span className="font-semibold text-primary">{payload[0].value}</span>
        {unit ? ` ${unit}` : ''}
      </p>
    </div>
  );
}

/** Vertical bars over a categorical X axis (e.g. months). */
export function TimeSeriesBars({
  data,
  xKey,
  yKey,
  unit,
  color = 'hsl(var(--chart-1))',
  height = 240,
}: {
  data: Array<Record<string, unknown>>;
  xKey: string;
  yKey: string;
  unit?: string;
  color?: string;
  height?: number;
}) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: -12, bottom: 0 }}>
        <CartesianGrid stroke={GRID} vertical={false} />
        <XAxis
          dataKey={xKey}
          tick={{ fill: AXIS, fontSize: 11 }}
          tickLine={false}
          axisLine={{ stroke: GRID }}
          tickFormatter={(v: string) => (typeof v === 'string' ? v.split(' ')[0] : v)}
        />
        <YAxis tick={{ fill: AXIS, fontSize: 11 }} tickLine={false} axisLine={false} width={40} />
        <Tooltip
          cursor={{ fill: 'hsl(var(--muted) / 0.3)' }}
          content={<TooltipBox unit={unit} />}
        />
        <Bar dataKey={yKey} fill={color} radius={[4, 4, 0, 0]} maxBarSize={40} />
      </BarChart>
    </ResponsiveContainer>
  );
}

/** Horizontal ranked bars (e.g. body locations, injury types). */
export function RankedBars({
  data,
  labelKey,
  valueKey,
  unit,
  height,
}: {
  data: Array<Record<string, unknown>>;
  labelKey: string;
  valueKey: string;
  unit?: string;
  height?: number;
}) {
  const h = height ?? Math.max(data.length * 34 + 24, 160);
  return (
    <ResponsiveContainer width="100%" height={h}>
      <BarChart
        data={data}
        layout="vertical"
        margin={{ top: 4, right: 16, left: 8, bottom: 4 }}
      >
        <CartesianGrid stroke={GRID} horizontal={false} />
        <XAxis type="number" tick={{ fill: AXIS, fontSize: 11 }} tickLine={false} axisLine={false} />
        <YAxis
          type="category"
          dataKey={labelKey}
          tick={{ fill: AXIS, fontSize: 11 }}
          tickLine={false}
          axisLine={false}
          width={110}
        />
        <Tooltip
          cursor={{ fill: 'hsl(var(--muted) / 0.3)' }}
          content={<TooltipBox unit={unit} />}
        />
        <Bar dataKey={valueKey} radius={[0, 4, 4, 0]} maxBarSize={22}>
          {data.map((_, i) => (
            <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
