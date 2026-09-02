import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

async function loadExposureChartModule() {
  const source = await readFile(new URL('../lib/exposure-chart.ts', import.meta.url), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

test('reported exposure filtering retains zero and removes unavailable values', async () => {
  const { hasReportedExposureValue } = await loadExposureChartModule();
  assert.equal(hasReportedExposureValue({ exposure_hours: 0 }, 'hours'), true);
  assert.equal(hasReportedExposureValue({ exposure_hours: null }, 'hours'), false);
  assert.equal(hasReportedExposureValue({ distance_km: 0 }, 'distance'), true);
  assert.equal(hasReportedExposureValue({}, 'distance'), false);
});

test('contributor text follows the selected reported measure', async () => {
  const { contributingClubsText } = await loadExposureChartModule();
  const row = { exposure_contributor_count: 14, distance_contributor_count: 10 };
  assert.equal(contributingClubsText(row, 'hours'), '14 of 16 clubs');
  assert.equal(contributingClubsText(row, 'distance'), '10 of 16 clubs');
  assert.equal(contributingClubsText(row, 'hsr'), null);
});

test('exposure month labels use full names on desktop and reduce alternate mobile labels', async () => {
  const { exposureMonthLabel, showExposureMonthLabel } = await loadExposureChartModule();
  assert.equal(exposureMonthLabel('2025-09'), 'September');
  assert.equal(exposureMonthLabel('September 2025', true), 'Sep');
  assert.equal(showExposureMonthLabel(0, true), true);
  assert.equal(showExposureMonthLabel(1, true), false);
  assert.equal(showExposureMonthLabel(1, false), true);
});

test('HSR percentage preserves an explicit display value without deriving a distance', async () => {
  const { hsrPercentage } = await loadExposureChartModule();
  assert.equal(hsrPercentage({ hsr_percentage: 5.6, hsr_distance_km: null }), 5.6);
  assert.equal(hsrPercentage({ hsr_distance_km: 42 }), null);
});

test('HSR status keeps unknown non-imputed months distinct from actual source data', async () => {
  const { hsrStatusLabel } = await loadExposureChartModule();
  assert.equal(hsrStatusLabel({ is_imputed: true, actual_hsr_distance_km: null }), 'League-mean placeholder');
  assert.equal(hsrStatusLabel({ is_imputed: false, actual_hsr_distance_km: 0 }), 'Actual source data');
  assert.equal(hsrStatusLabel({ is_imputed: false, actual_hsr_distance_km: null }), 'HSR not available');
});
