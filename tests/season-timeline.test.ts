import assert from 'node:assert/strict';
import test from 'node:test';
import { rankedCommonInjuries, rankedIllnesses } from '../lib/report-presentation';
import { buildSeasonTimelineRows, monthlyIncidence } from '../lib/season-timeline';
import { monthIndex, sortSeasonMonths } from '../lib/dashboard-month';

test('both reader month formats sort together across the year boundary', () => {
  const rows = ['2026-01', 'Oct 2025', '2025-09', 'Jun 2026'].map((month) => ({ month }));
  assert.deepEqual(sortSeasonMonths(rows).map((row) => row.month), ['2025-09', 'Oct 2025', '2026-01', 'Jun 2026']);
  assert.equal(monthIndex('2025-09'), monthIndex('September 2025'));
  assert.equal(monthIndex('2025-13'), -1);
});

test('common injury lanes replace excluded labels with the next ranked injuries', () => {
  const rows = ['Foot pain', 'Medical Illness', 'Foot Pain/Injury Not otherwise specified', 'Concussion', 'Ankle fracture', 'Hamstring injury', 'Knee injury', 'Shoulder injury', 'Wrist fracture']
    .map((label, index) => ({ label, time_loss_injuries: 20 - index, recorded_illnesses: 20 - index }));
  assert.deepEqual(rankedCommonInjuries(rows, 'time_loss_injuries').map((row) => row.label), ['Concussion', 'Ankle fracture', 'Hamstring injury', 'Knee injury', 'Shoulder injury']);
  assert.equal(rows.length, 9);
});

test('illness rankings replace generic medical illness and undiagnosed foot pain', () => {
  const rows = ['Medical illness', 'Foot pain, undiagnosed', 'Respiratory infection', 'Gastroenteritis', 'Skin infection', 'Influenza', 'Otitis', 'Other illness']
    .map((label, index) => ({ label, recorded_illnesses: 20 - index }));
  assert.deepEqual(rankedIllnesses(rows, 'recorded_illnesses').map((row) => row.label), ['Respiratory infection', 'Gastroenteritis', 'Skin infection', 'Influenza', 'Otitis']);
  assert.equal(rows.length, 8);
});

test('missing monthly incidence uses released counts and exposure while preserving existing rates', () => {
  assert.equal(monthlyIncidence(20, 800, null), 25);
  assert.equal(monthlyIncidence(12, 800, undefined), 15);
  assert.equal(monthlyIncidence(20, 800, 0), 0);
  assert.equal(monthlyIncidence(20, 0, null), null);
  assert.equal(monthlyIncidence(20, null, null), null);
  assert.equal(monthlyIncidence(null, 800, null), null);
  assert.equal(monthlyIncidence(20, 800, null, false), null);
  assert.equal(monthlyIncidence(20, 800, 25, false), 25);
});

test('league timeline plots both incidence series through a contributor-aligned month', () => {
  const rows = buildSeasonTimelineRows([
    {
      month: 'Jun 2026',
      setting: 'all',
      recorded_injuries: 20,
      time_loss_injuries: 8,
      rate_time_loss_injuries: 8,
      exposure_hours: 500,
      overall_incidence_per_1000h: null,
      incidence_per_1000h: null,
    },
  ], false, [{
    month: '2026-06',
    contributor_count: 10,
    exposure_hours: 400,
    time_loss_injuries: 6,
    days_lost: 80,
    incidence_per_1000h: 15,
    burden_per_1000h: 200,
    qualification: 'Preliminary contributor-aligned monthly rates.',
  }]);

  assert.equal(rows[0]?.incidence_per_1000h, 15);
  assert.equal(rows[0]?.overall_incidence_per_1000h, 50);
});
