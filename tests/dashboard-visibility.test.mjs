import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

async function loadVisibilityHelpers() {
  const source = await readFile(new URL('../lib/dashboard-visibility.ts', import.meta.url), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

test('front-facing category rows exclude every unknown sentinel shape', async () => {
  const { withoutFrontFacingUnknown } = await loadVisibilityHelpers();
  const rows = [
    { code: 'concussion', label: 'Concussion', setting: 'all' },
    { code: 'unknown', label: 'Unknown diagnosis', setting: 'all' },
    { key: 'unknown_or_censored', label: 'Unclassified duration', setting: 'all' },
    { code: 'other', label: 'Unknown / not reported', setting: 'all' },
    { code: 'ankle', label: 'Ankle', setting: 'unknown' },
    { code: 'ankle__unknown', label: 'Ankle · Unknown', setting: 'all' },
  ];

  assert.deepEqual(withoutFrontFacingUnknown(rows), [rows[0]]);
});

test('informative classified and other categories remain visible', async () => {
  const { withoutFrontFacingUnknown } = await loadVisibilityHelpers();
  const rows = [
    { code: 'muscle_injury', label: 'Muscle injury', setting: 'training' },
    { code: 'other_injury', label: 'Other injury', setting: 'match' },
  ];

  assert.deepEqual(withoutFrontFacingUnknown(rows), rows);
});

test('dashboard does not rebuild visible severity or contact unknown rows', async () => {
  const dashboardSource = await readFile(
    new URL('../components/dashboard/team-dashboard.tsx', import.meta.url),
    'utf8',
  );
  assert.doesNotMatch(dashboardSource, /label:\s*['"]Unknown \/ censored/);
  assert.match(
    dashboardSource,
    /withoutFrontFacingUnknown\(supplement\?\.contact_distribution \?\? \[\]\)/,
  );
});
