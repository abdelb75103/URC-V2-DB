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
