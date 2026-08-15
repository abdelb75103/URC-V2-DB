import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
import ts from 'typescript';

const require = createRequire(import.meta.url);

async function loadPreviewForFixtureTest() {
  const source = await readFile(new URL('../lib/reporting-preview.ts', import.meta.url), 'utf8');
  const zodUrl = pathToFileURL(require.resolve('zod')).href;
  const executable = source
    .replace('import "server-only";\n', '')
    .replace('import { z } from "zod";', `import { z } from "${zodUrl}";`);
  const javascript = ts.transpileModule(executable, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString('base64')}`);
}

test('dashboard supplements are bound to the selected season', async () => {
  const fixtureDirectory = await mkdtemp(join(tmpdir(), 'urc-preview-season-'));
  const fixture = join(fixtureDirectory, 'supplement.json');
  const priorFile = process.env.DASHBOARD_V3_PREVIEW_FILE;
  const priorNodeEnv = process.env.NODE_ENV;
  await writeFile(fixture, JSON.stringify({
    status: 'draft_not_for_release',
    supplements: [{
      status: 'draft_not_for_release',
      season: '2024-25',
      team_key: 'urc',
      rule_version: 'urc-diagnosis-inference-v3-draft.9',
      cohort_rule: 'season_bound_2024-07-01_2025-06-30_no_exposure_window',
      generated_at: '2026-08-15T00:00:00Z',
      consequence_summary: {
        recorded_injuries: 0, positive_day_cases: 0, zero_day_cases: 0,
        duration_unknown_or_censored: 0, source_reported_time_loss: 0,
        source_reported_time_loss_without_positive_days: 0,
        source_reported_medical_attention: 0, source_class_unknown: 0,
      },
      descriptive_consequence_summary: {
        recorded_injuries: 0, time_loss_injuries: 0, medical_attention_only: 0,
        consequence_unknown: 0, undated_injuries: 0, outside_season_date_injuries: 0,
        rate_ineligible_time_loss_injuries: 0,
      },
      rate_setting_metrics: [], severity_distribution: [],
      match_scope_summary: {
        positive_day_match_cases: 0, confirmed_urc_match_cases: 0,
        retained_generic_match_cases: 0,
      },
      monthly_by_setting: [], contact_distribution: [], body_locations: [],
      injury_types: [], common_injuries: [],
      diagnosis_coverage: { classified_time_loss_injuries: 0, eligible_time_loss_injuries: 0 },
      inference_coverage: {
        cohort: 'attributed_descriptive_cases',
        body_location: { source_reported: 0, mapped: 0, inferred: 0, adjudicated: 0, remaining_unknown: 0, unknown_before_v3: 0, classified: 0, total: 0 },
        tissue_pathology: { source_reported: 0, mapped: 0, inferred: 0, adjudicated: 0, remaining_unknown: 0, unknown_before_v3: 0, classified: 0, total: 0 },
        diagnosis: { source_reported: 0, mapped: 0, inferred: 0, adjudicated: 0, remaining_unknown: 0, unknown_before_v3: 0, classified: 0, total: 0 },
        contact_context: { source_reported: 0, mapped: 0, inferred: 0, adjudicated: 0, remaining_unknown: 0, unknown_before_v3: 0, classified: 0, total: 0 },
      },
    }],
  }));

  process.env.DASHBOARD_V3_PREVIEW_FILE = fixture;
  process.env.NODE_ENV = 'test';
  try {
    const { getDashboardSupplement } = await loadPreviewForFixtureTest();
    assert.equal((await getDashboardSupplement('urc', '2025-26')), undefined);
    assert.equal((await getDashboardSupplement('urc', '2024-25'))?.season, '2024-25');
  } finally {
    if (priorFile === undefined) delete process.env.DASHBOARD_V3_PREVIEW_FILE;
    else process.env.DASHBOARD_V3_PREVIEW_FILE = priorFile;
    if (priorNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = priorNodeEnv;
    await rm(fixtureDirectory, { recursive: true, force: true });
  }
});

test('dashboard routes pass their selected season to local supplements', async () => {
  const teamPage = await readFile(new URL('../app/team/[teamId]/page.tsx', import.meta.url), 'utf8');
  const leaguePage = await readFile(new URL('../app/urc/page.tsx', import.meta.url), 'utf8');

  assert.match(teamPage, /getDashboardSupplement\(team\.id, season\)/);
  assert.match(leaguePage, /getDashboardSupplement\('urc', season\)/);
});
