import assert from 'node:assert/strict';
import test from 'node:test';
import { seasonComparisonKpis } from '../lib/season-comparison-presentation';
import type { SeasonComparisonData } from '../lib/season-comparison';

type Comparison = Pick<SeasonComparisonData, 'kpis' | 'impact'>;
type ImpactValue = Comparison['impact'][number]['previous'];

const impactValue = (incidence: number, severity: number, burden: number, injuries: number): ImpactValue => ({
  time_loss_incidence_per_1000h: incidence,
  mean_severity_days: severity,
  burden_per_1000h: burden,
  time_loss_injuries: injuries,
  exposure_hours: 1000,
});

function fixture(): Comparison {
  return {
    kpis: [
      { key: 'time_loss_incidence', label: 'Incidence', previous: { value: 11.4, unit: '/1,000 h' }, current: { value: 10.5, unit: '/1,000 h' }, outcome_improvement_percent: 7.91 },
      { key: 'mean_severity', label: 'Mean Severity', previous: { value: 20, unit: 'days' }, current: { value: 18, unit: 'days' }, outcome_improvement_percent: 10 },
      { key: 'injury_burden', label: 'Burden', previous: { value: 228, unit: 'days/1,000 h' }, current: { value: 189, unit: 'days/1,000 h' }, outcome_improvement_percent: 17.11 },
      { key: 'time_loss_injuries', label: 'Injuries', previous: { value: 913, unit: 'injuries' }, current: { value: 938, unit: 'injuries' }, outcome_improvement_percent: -2.74 },
    ],
    impact: [
      { setting: 'all', label: 'Overall', previous: impactValue(99, 99, 99, 99), current: impactValue(88, 88, 88, 88) },
      { setting: 'match', label: 'Match', previous: impactValue(80, 30, 2400, 500), current: impactValue(100, 27, 2700, 600) },
      { setting: 'training', label: 'Training', previous: impactValue(4, 10, 40, 400), current: impactValue(3, 12, 36, 300) },
    ],
  };
}

test('KPI values and changes follow the setting while Overall retains its released values exactly', () => {
  const comparison = fixture();
  const before = structuredClone(comparison);
  const values = (setting: 'all' | 'match' | 'training') => seasonComparisonKpis(comparison, setting)
    .map((metric) => [metric.previous.value, metric.current.value, metric.outcome_improvement_percent]);

  assert.equal(seasonComparisonKpis(comparison, 'all'), comparison.kpis);
  assert.deepEqual(values('match'), [[80, 100, -25], [30, 27, 10], [2400, 2700, -12.5], [500, 600, -20]]);
  assert.deepEqual(values('training'), [[4, 3, 25], [10, 12, -20], [40, 36, 10], [400, 300, 25]]);
  assert.deepEqual(values('all'), [[11.4, 10.5, 7.91], [20, 18, 10], [228, 189, 17.11], [913, 938, -2.74]]);
  assert.deepEqual(comparison, before);
});

test('a missing setting stays unavailable instead of falling back to Overall', () => {
  const comparison = fixture();
  comparison.impact = comparison.impact.filter((row) => row.setting !== 'match');
  const kpis = seasonComparisonKpis(comparison, 'match');

  assert.equal(kpis.length, 4);
  for (const metric of kpis) {
    assert.equal(metric.previous.value, null);
    assert.equal(metric.current.value, null);
    assert.equal(metric.outcome_improvement_percent, null);
  }
  assert.equal(seasonComparisonKpis(comparison, 'all'), comparison.kpis);
});

test('missing values and zero baselines are not comparable, but a fall to zero is a 100% decrease', () => {
  const comparison = fixture();
  const match = comparison.impact[1];
  match.previous = { ...impactValue(80, 30, 0, 500), time_loss_incidence_per_1000h: null };
  match.current = { ...impactValue(100, 27, 20, 0), mean_severity_days: null };
  const values = () => seasonComparisonKpis(comparison, 'match')
    .map((metric) => [metric.previous.value, metric.current.value, metric.outcome_improvement_percent]);

  assert.deepEqual(values(), [[null, 100, null], [30, null, null], [0, 20, null], [500, 0, 100]]);
  match.current.burden_per_1000h = 0;
  match.current.time_loss_injuries = 500;
  assert.deepEqual(values(), [[null, 100, null], [30, null, null], [0, 0, null], [500, 500, 0]]);
});
