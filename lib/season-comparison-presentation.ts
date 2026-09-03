import type { SeasonComparisonData } from './season-comparison';

type Comparison = Pick<SeasonComparisonData, 'kpis' | 'impact'>;
type Setting = SeasonComparisonData['impact'][number]['setting'];
type Kpi = SeasonComparisonData['kpis'][number];
type ImpactValue = SeasonComparisonData['impact'][number]['previous'];

const KPI_FIELDS = {
  time_loss_incidence: 'time_loss_incidence_per_1000h',
  mean_severity: 'mean_severity_days',
  injury_burden: 'burden_per_1000h',
  time_loss_injuries: 'time_loss_injuries',
} as const satisfies Record<Kpi['key'], keyof ImpactValue>;

// Presentation v1, approved 2026-09-03: reuse released setting values and the
// existing comparison formula; Overall keeps its precomputed values unchanged.
export function seasonComparisonKpis(comparison: Comparison, setting: Setting): Kpi[] {
  if (setting === 'all') return comparison.kpis;
  const impact = comparison.impact.find((row) => row.setting === setting);
  return comparison.kpis.map((metric) => {
    const field = KPI_FIELDS[metric.key];
    const previous = impact?.previous[field] ?? null;
    const current = impact?.current[field] ?? null;
    return {
      ...metric,
      previous: { ...metric.previous, value: previous },
      current: { ...metric.current, value: current },
      outcome_improvement_percent: previous === null || previous === 0 || current === null
        ? null
        : 100 * (previous - current) / previous,
    };
  });
}
