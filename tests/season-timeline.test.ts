import assert from 'node:assert/strict';
import test from 'node:test';
import { rankedCommonInjuries, rankedIllnesses } from '../lib/report-presentation';
import { monthIndex, sortSeasonMonths } from '../lib/dashboard-month';
import { buildSeasonTimelineRows, timelineRate } from '../lib/season-timeline';
import type { MonthlySettingRow, PreliminaryMonthlyRateRow } from '../lib/reporting-types';

const preliminary: PreliminaryMonthlyRateRow = {
  month: '2025-09', contributor_count: 14, exposure_hours: 800,
  time_loss_injuries: 8, days_lost: 40, incidence_per_1000h: 10,
  burden_per_1000h: 50, qualification: 'Preliminary contributor-aligned rate.',
};
const monthly: MonthlySettingRow = {
  month: 'Sep 2025', setting: 'all', recorded_injuries: 20, time_loss_injuries: 12,
  rate_time_loss_injuries: 12, exposure_hours: 1000,
  overall_incidence_per_1000h: null, incidence_per_1000h: null,
};

test('both reader month formats sort together across the year boundary', () => {
  const rows = ['2026-01', 'Oct 2025', '2025-09', 'Jun 2026'].map((month) => ({ month }));
  assert.deepEqual(sortSeasonMonths(rows).map((row) => row.month), ['2025-09', 'Oct 2025', '2026-01', 'Jun 2026']);
  assert.equal(monthIndex('2025-09'), monthIndex('September 2025'));
  assert.equal(monthIndex('2025-13'), -1);
});

test('preliminary timeline rate retains its own cohort and leaves full-cohort bars unchanged', () => {
  const [row] = buildSeasonTimelineRows([monthly], [preliminary]);
  assert.equal(row.incidence_per_1000h, 10);
  assert.equal(row.time_loss_injuries, 12);
  assert.equal(row.exposure_hours, 1000);
  assert.equal(row.preliminary_rate?.time_loss_injuries, 8);
  assert.equal(row.preliminary_rate?.exposure_hours, 800);
  assert.equal(row.preliminary_rate?.contributor_count, 14);
  assert.equal(row.overall_incidence_per_1000h, null);
  assert.equal(monthly.incidence_per_1000h, null);
});

test('official rates including zero take precedence, and missing months stay gaps', () => {
  assert.deepEqual(timelineRate('Sep 2025', 0, [preliminary]), { incidence: 0, preliminary: undefined });
  assert.equal(timelineRate('Sep 2024', null, [preliminary]).incidence, null);
  assert.equal(timelineRate('Oct 2025', null, [preliminary]).incidence, null);
});

test('overall preliminary rates never populate match or training series', () => {
  for (const setting of ['match', 'training'] as const) {
    const [row] = buildSeasonTimelineRows([{ ...monthly, setting }], [preliminary]);
    assert.equal(row.incidence_per_1000h, null);
    assert.equal(row.preliminary_rate, undefined);
  }
});


test('common injury lanes replace excluded labels with the next ranked injuries', () => {
  const rows = ['Foot pain', 'Medical Illness', 'Foot Pain/Injury Not otherwise specified', 'Concussion', 'Ankle fracture', 'Hamstring injury', 'Knee injury', 'Shoulder injury', 'Wrist fracture']
    .map((label, index) => ({ label, time_loss_injuries: 20 - index, recorded_illnesses: 20 - index }));
  assert.deepEqual(rankedCommonInjuries(rows, 'time_loss_injuries').map((row) => row.label), ['Concussion', 'Ankle fracture', 'Hamstring injury', 'Knee injury', 'Shoulder injury']);
  assert.equal(rows.length, 9);
  assert.equal(rankedIllnesses(rows, 'recorded_illnesses')[1].label, 'Medical Illness');
});
