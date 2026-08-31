import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

async function source(path) {
  return readFile(new URL(`../${path}`, import.meta.url), 'utf8');
}

test('season comparison is a shared tab immediately before Reports', async () => {
  const tabs = await source('lib/dashboard-tab.ts');
  const seasonIndex = tabs.indexOf("value: 'season-comparison'");
  const reportsIndex = tabs.indexOf("value: 'reports'");

  assert.ok(seasonIndex >= 0);
  assert.ok(reportsIndex > seasonIndex);
  assert.match(tabs.slice(seasonIndex, reportsIndex), /label: 'Season Comparison'/);
});

test('comparison UI is concise, season-coded and uses explicit outcome direction', async () => {
  const component = await source('components/dashboard/season-comparison.tsx');
  const charts = await source('components/dashboard/season-comparison-charts.tsx');
  const presentationMigration = await source('supabase/migrations/20260831150000_season_comparison_presentation_v2.sql');

  assert.match(component, /import type \{ SeasonComparisonData \} from '@\/lib\/season-comparison'/);
  assert.match(component, /outcome_improvement_percent/);
  assert.match(component, /ArrowUp/);
  assert.match(component, /ArrowDown/);
  assert.match(component, /Improved/);
  assert.match(component, /Increased/);
  assert.doesNotMatch(component, /Worsened/);
  assert.match(component, /No Change/);
  assert.match(component, /Season Comparison/);
  assert.match(component, /Diagnosis Drivers/);
  assert.doesNotMatch(component, /Most Common Diagnosis/);
  assert.match(component, /Diagnosis measure/);
  assert.match(component, /data\.previous_season/);
  assert.match(component, /data\.current_season/);
  assert.match(component, /SETTINGS\.map/);
  assert.match(component, /SEASON_BAR_COLOURS\[0\]/);
  assert.match(component, /SEASON_BAR_COLOURS\[1\]/);
  assert.match(component, /diagnosisColourMap/);
  assert.match(component, /\[1, 2, 3\]\.map/);
  assert.match(component, /#\{rankRow\.rank\}/);
  assert.doesNotMatch(component, /character\.charCodeAt/);
  assert.doesNotMatch(component, /accessibleLabel/);
  assert.match(component, /bg-blue-400/);
  assert.match(component, /bg-cyan-300/);
  assert.match(presentationMigration, /Hamstring Injury/);
  assert.match(component, /comparison\.exposure\.previous\.qualification/);
  assert.doesNotMatch(component, /Outcome improvement vs 2024-25/);
  assert.doesNotMatch(component, /Approved reporting values for/);
  assert.doesNotMatch(component, /Selected team values only/);
  assert.doesNotMatch(component, /<select/);
  assert.doesNotMatch(component, /Severe injury incidence/i);
  assert.match(charts, /Circle area: Burden/);
  assert.match(charts, /strokeDasharray="5 4"/);
  assert.match(charts, /markerEnd=/);
  assert.match(charts, /not causality/);
  assert.match(charts, /Time-loss injury count/);
  assert.doesNotMatch(charts, /Exact injury impact values by season/);
  assert.doesNotMatch(charts, /SevereIncidenceChart/);
});

test('dashboard headers omit redundant injury surveillance subtitles', async () => {
  const [dashboard, leaguePage, teamPage] = await Promise.all([
    source('components/dashboard/team-dashboard.tsx'),
    source('app/urc/page.tsx'),
    source('app/team/[teamId]/page.tsx'),
  ]);

  assert.doesNotMatch(dashboard, /injury and exposure surveillance/);
  assert.doesNotMatch(leaguePage, /League-wide injury and exposure surveillance/);
  assert.doesNotMatch(teamPage, /URC injury & exposure surveillance/);
});

test('impact bubbles use burden-proportional area without jitter and mark missing burden', async () => {
  const charts = await source('components/dashboard/season-comparison-charts.tsx');

  assert.match(charts, /Math\.sqrt\(Math\.max\(value, 0\) \/ maxBurden\)/);
  assert.doesNotMatch(charts, /18 \+ Math\.sqrt/);
  assert.match(charts, /Bubble area unavailable because the approved burden value is missing/);
  assert.match(charts, /finite\(first\.incidence\)[\s\S]*finite\(second\.severity\)/);
  assert.match(charts, /if \(!point\.plottable\) return null/);
});

test('comparison UI contains no forbidden dash glyphs', async () => {
  const [component, charts] = await Promise.all([
    source('components/dashboard/season-comparison.tsx'),
    source('components/dashboard/season-comparison-charts.tsx'),
  ]);

  assert.doesNotMatch(`${component}\n${charts}`, /[—–]/);
});
