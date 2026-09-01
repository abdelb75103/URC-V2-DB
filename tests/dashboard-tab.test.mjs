import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

async function loadDashboardTab() {
  const source = await readFile(new URL('../lib/dashboard-tab.ts', import.meta.url), 'utf8');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

test('dashboard tab routing accepts every visible tab', async () => {
  const { DASHBOARD_TABS, resolveDashboardTab } = await loadDashboardTab();
  const values = [
    'overview',
    'comparison',
    'common',
    'illnesses',
    'location',
    'types',
    'exposure',
    'season-comparison',
    'reports',
  ];

  assert.deepEqual(DASHBOARD_TABS.map((tab) => tab.value), values);
  for (const value of values) assert.equal(resolveDashboardTab(value), value);
});

test('dashboard tab routing safely falls back to Overview', async () => {
  const { resolveDashboardTab } = await loadDashboardTab();

  assert.equal(resolveDashboardTab(undefined), 'overview');
  assert.equal(resolveDashboardTab(null), 'overview');
  assert.equal(resolveDashboardTab('unknown'), 'overview');
});

test('the shared dashboard keeps tab changes client-side and preserves them across seasons', async () => {
  const dashboard = await readFile(new URL('../components/dashboard/team-dashboard.tsx', import.meta.url), 'utf8');

  assert.match(dashboard, /value=\{activeTab\}/);
  assert.match(dashboard, /window\.history\.replaceState/);
  assert.match(dashboard, /url\.searchParams\.set\('tab', nextTab\)/);
  assert.match(dashboard, /href=\{`\$\{seasonPath\}\?season=\$\{option\}\$\{tabParameter\}`\}/);
  assert.match(dashboard, /href=\{`\$\{seasonPath\}\?season=\$\{option\}\$\{tabParameter\}`\}[\s\S]*?prefetch=\{false\}/);
});
