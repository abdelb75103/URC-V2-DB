import type { InjuryProfileRow } from '@/lib/reporting-types';

export type LocationViewMetric =
  | 'time_loss_injuries'
  | 'incidence_per_1000h'
  | 'burden_per_1000h';

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

function valueFor(row: InjuryProfileRow, metric: LocationViewMetric) {
  const value = row[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

export function resolveLocationView({
  profiles,
  setting,
  metric,
  selectedCode,
  hoveredCode,
}: {
  profiles: InjuryProfileRow[];
  setting: InjuryProfileRow['setting'];
  metric: LocationViewMetric;
  selectedCode?: string;
  hoveredCode?: string;
}) {
  const rows = profiles
    .filter((row) => row.setting === setting)
    .sort((a, b) => LOCATION_ORDER.indexOf(a.code) - LOCATION_ORDER.indexOf(b.code));
  const barRows = [...rows]
    .sort((a, b) => valueFor(b, metric) - valueFor(a, metric) || a.label.localeCompare(b.label))
    .slice(0, 10);
  const activeCode = rows.some((row) => row.code === hoveredCode)
    ? hoveredCode
    : rows.some((row) => row.code === selectedCode)
      ? selectedCode
      : barRows[0]?.code;

  return {
    rows,
    barRows,
    activeCode,
    selected: rows.find((row) => row.code === activeCode),
  };
}
