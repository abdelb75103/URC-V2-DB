export const SETTING_COLORS = {
  all: '#02d5f0',
  match: '#02d5f0',
  training: '#42d8b4',
  unknown: '#94a3b8',
} as const;

export const SEVERITY_BAND_COLORS: Record<string, string> = {
  zero: '#94a3b8',
  one_to_seven: '#02d5f0',
  eight_to_twenty_eight: '#ffc45c',
  greater_than_twenty_eight: '#ef7189',
};

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

const MONTH_NAMES = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** The zero-based month in a payload label such as `Sep 2024`, or -1. */
export function monthIndex(value: string) {
  return MONTH_NAMES.indexOf(value.trim().slice(0, 3).toLowerCase());
}

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
