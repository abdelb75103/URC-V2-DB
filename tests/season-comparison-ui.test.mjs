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

test('the rugby setting drives KPI cards without changing the monthly or diagnosis sections', async () => {
  const component = await source('components/dashboard/season-comparison.tsx');

  assert.match(component, /const kpis = seasonComparisonKpis\(comparison, setting\)/);
  assert.match(component, /kpis\.map\(\(metric\) => <KpiTile key=\{metric\.key\} metric=\{metric\}/);
  assert.doesNotMatch(component, /comparison\.kpis\.map/);
  assert.match(component, /<MonthlyBars monthly=\{monthlyPoints\(comparison\)\}/);
  assert.match(component, /<DiagnosisDrivers data=\{comparison\}/);
});

test('comparison UI maps decreases and increases to the requested outcome direction', async () => {
  const component = await source('components/dashboard/season-comparison.tsx');
  const charts = await source('components/dashboard/season-comparison-charts.tsx');
  const report = await source('components/report/report-document.tsx');
  const presentationMigration = await source('supabase/migrations/20260831150000_season_comparison_presentation_v2.sql');

  assert.match(component, /import type \{ SeasonComparisonData \} from '@\/lib\/season-comparison'/);
  assert.match(component, /outcome_improvement_percent/);
  assert.match(component, /ArrowUp/);
  assert.match(component, /ArrowDown/);
  assert.match(component, /state === 'favourable'[\s\S]*\? 'Decreased'/);
  assert.match(component, /state === 'adverse'[\s\S]*\? 'Increased'/);
  assert.match(component, /state === 'favourable' \? ArrowDown : state === 'adverse' \? ArrowUp : Minus/);
  assert.doesNotMatch(component, /Improved/);
  assert.doesNotMatch(report, /improvement > 0 \? "Improved"/);
  assert.match(report, /improvement > 0 \? "Decreased" : improvement < 0 \? "Increased"/);
  assert.match(component, /Increased/);
  assert.doesNotMatch(component, /Worsened/);
  assert.match(component, /No Change/);
  assert.match(component, /Season Comparison/);
  assert.match(component, /Most Common Diagnosis/);
  assert.doesNotMatch(component, /Diagnosis Drivers/);
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
  assert.match(component, /accessibleLabel/);
  assert.match(component, /bg-blue-400/);
  assert.match(component, /bg-cyan-300/);
  assert.match(presentationMigration, /Hamstring Injury/);
  assert.doesNotMatch(component, /comparison\.exposure\.(?:previous|current)\.qualification/);
  assert.doesNotMatch(component, /Outcome improvement vs 2024-25/);
  assert.doesNotMatch(component, /Approved reporting values for/);
  assert.doesNotMatch(component, /Selected team values only/);
  assert.doesNotMatch(component, /<select/);
  assert.doesNotMatch(component, /Severe injury incidence/i);
  assert.match(charts, /Circle Area: Burden/);
  assert.match(charts, /not causality/);
  assert.match(charts, /Injury Count/);
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

  assert.match(charts, /Math\.sqrt\(Math\.max\(row\.burden, 0\) \/ maxBurden\)/);
  assert.match(charts, /Bubble area unavailable because the approved burden value is missing/);
  assert.match(charts, /filter\(\(row\) => finite\(row\.incidence\) && finite\(row\.severity\)\)/);
  assert.doesNotMatch(charts, /Math\.random|jitter/i);
});

test('comparison charts fill their cards and expose accessible preview and pin tooltips', async () => {
  const charts = await source('components/dashboard/season-comparison-charts.tsx');

  assert.match(charts, /ResponsiveContainer width="100%" height="100%"/);
  assert.match(charts, /h-\[390px\][\s\S]*sm:h-\[460px\]/);
  assert.match(charts, /h-\[350px\][\s\S]*sm:h-\[420px\]/);
  assert.doesNotMatch(charts, /const width = 520|viewBox=\{`0 0 \$\{width\}/);
  assert.match(charts, /role="tooltip"/);
  assert.match(charts, /aria-live="polite"/);
  assert.match(charts, /aria-describedby=\{tooltipId\}/);
  assert.match(charts, /onMouseEnter=/);
  assert.match(charts, /onFocus=/);
  assert.match(charts, /onPointerDown=/);
  assert.match(charts, /event\.key === 'Enter' \|\| event\.key === ' '/);
  assert.match(charts, /event\.key === 'Escape'/);
  assert.match(charts, /Math\.max\(22, visualRadius\)/);
  assert.match(charts, /Math\.max\(44, height\)/);
  assert.match(charts, /Math\.max\(44, width\)/);
  assert.match(charts, /function FloatingChartTooltip[\s\S]*pointer-events-none absolute z-30/);
  assert.match(charts, /<TooltipCard/);
  assert.match(charts, /const colour = point\.seasonIndex === 0 \? OLD_COLOUR : CURRENT_COLOUR/);
  assert.match(charts, /label: 'Injuries'[\s\S]*color: colour[\s\S]*label: 'Burden'[\s\S]*color: colour/);
  assert.doesNotMatch(charts, /rounded-lg border border-border\/70 bg-background\/80/);
});

test('diagnosis ranks stack on mobile and use the mirrored comparison from sm upwards', async () => {
  const component = await source('components/dashboard/season-comparison.tsx');

  assert.match(component, /className="block sm:hidden"/);
  assert.match(component, /className="hidden min-w-0 grid-cols-[^\"]+ sm:grid"/);
  assert.match(component, /data-diagnosis-target/);
  assert.match(component, /aria-describedby=\{tooltipId\}/);
  assert.match(component, /role="tooltip"/);
  assert.match(component, /SETTING_LABELS\[activeRow!\.setting\][\s\S]*activeRank\.rank[\s\S]*activeMetricLabel/);
  assert.match(component, /activePrevious\?\.diagnosis[\s\S]*activeCurrent\?\.diagnosis/);
  assert.match(component, /pointer-events-none fixed z-50/);
  assert.match(component, /<TooltipCard/);
  assert.doesNotMatch(component, /className=\{activeRank[\s\S]*mb-5 rounded-lg/);
  assert.doesNotMatch(component, /overflow-x-auto/);
  assert.match(component, /h-4 justify-end/);
  assert.match(component, /h-4 justify-start/);
});

test('comparison headings and metric labels use Title Case and the default injury wording', async () => {
  const component = await source('components/dashboard/season-comparison.tsx');

  assert.match(component, /time_loss_incidence: 'Injury Incidence'/);
  assert.match(component, /time_loss_injuries: 'Injuries'/);
  assert.match(component, /title="Injury Impact By Season"/);
  assert.match(component, /title="Injuries By Month"/);
  assert.match(component, />Most Common Diagnosis</);
  assert.doesNotMatch(component, /TL Injury Incidence|Time-Loss Injuries By Month/);
});

test('comparison UI contains no forbidden dash glyphs', async () => {
  const [component, charts] = await Promise.all([
    source('components/dashboard/season-comparison.tsx'),
    source('components/dashboard/season-comparison-charts.tsx'),
  ]);

  assert.doesNotMatch(`${component}\n${charts}`, /[—–]/);
});
