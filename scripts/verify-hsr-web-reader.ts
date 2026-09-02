import assert from 'node:assert/strict';
import { teams } from '../config/teams';
import { getLeagueDashboard, getTeamDashboard } from '../lib/reporting';
import type { DashboardData } from '../lib/reporting-types';

// Exercise the real least-privilege reader and its strict payload parser.
function verify(dashboard: DashboardData | undefined, season: string) {
  assert.ok(dashboard, 'Expected an approved dashboard');
  assert.equal(dashboard.season, season);
  const coverage = dashboard.coverage;
  assert.ok(coverage.hsr_distance_km === null || typeof coverage.hsr_distance_km === 'number');
  assert.ok(coverage.actual_hsr_distance_km === null || typeof coverage.actual_hsr_distance_km === 'number');
  assert.ok(typeof coverage.hsr_source_status === 'string');
  for (const month of dashboard.monthly) {
    assert.ok(month.hsr_percentage === null || (
      typeof month.hsr_percentage === 'number'
      && month.hsr_percentage >= 0 && month.hsr_percentage <= 100
    ));
    if (month.is_imputed) {
      assert.equal(month.actual_hsr_distance_km, null);
      assert.equal(typeof month.hsr_distance_km, 'number');
      assert.equal(month.imputation_method, 'season_month_pooled_valid_hsr_percentage_v1');
    }
  }
  return dashboard;
}

async function main() {
  for (const season of ['2024-25', '2025-26']) {
    const league = verify(await getLeagueDashboard(season), season);
    for (const team of teams) {
      const dashboard = verify(await getTeamDashboard(team.id, season), season);
      if (season === '2025-26' && ['benetton', 'edinburgh'].includes(team.id)) {
        assert.equal(dashboard.coverage.hsr_distance_km, null);
        assert.equal(dashboard.coverage.hsr_percentage, null);
        assert.equal(dashboard.coverage.is_imputed, false);
      }
    }
    console.log(JSON.stringify({
      season, team_dashboards_verified: teams.length, league_dashboard_verified: true,
      hsr_contributors: league.coverage.hsr_contributor_count,
      actual_hsr_distance_km: league.coverage.actual_hsr_distance_km,
      display_hsr_distance_km: league.coverage.hsr_distance_km,
      hsr_percentage: league.coverage.hsr_percentage,
    }));
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
}).finally(async () => {
  await globalThis.__urcWebReaderPool?.end();
});
