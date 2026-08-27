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

test('dashboard does not rebuild visible severity rows, and keeps the contact Unknown slice', async () => {
  const dashboardSource = await readFile(
    new URL('../components/dashboard/team-dashboard.tsx', import.meta.url),
    'utf8',
  );
  assert.doesNotMatch(dashboardSource, /label:\s*['"]Unknown \/ censored/);

  // Abdel, 26 July 2026: the contact ring keeps its Unknown slice, unlike every
  // other breakdown. For a mechanism field the unknown share is a real coverage
  // statement, and hiding it would silently inflate the contact and non-contact
  // percentages. This assertion is the inverse of what it was before that
  // decision: the contact rows must NOT be routed through the suppression.
  assert.match(
    dashboardSource,
    /const contactDistribution = dashboard\.contact_distribution \?\? supplement\?\.contact_distribution \?\? \[\];/,
  );
  // Check the contact-data block itself rather than the whole file, so any
  // wrapped form such as withoutFrontFacingUnknown(contactDistribution.filter(...))
  // is caught, without matching unrelated uses elsewhere in the component.
  const contactStatement = dashboardSource.slice(
    dashboardSource.indexOf('const contactDistribution ='),
    dashboardSource.indexOf('return (', dashboardSource.indexOf('const contactDistribution =')),
  );
  assert.ok(contactStatement.length > 0);
  assert.match(contactStatement, /const contactRows = contactDistribution\s*\.filter/);
  assert.doesNotMatch(contactStatement, /withoutFrontFacingUnknown/);
});
