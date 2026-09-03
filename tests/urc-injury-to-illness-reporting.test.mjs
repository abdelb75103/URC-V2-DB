import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const sql = fs.readFileSync(new URL('../supabase/migrations/20260903010000_urc_2025_26_injury_to_illness_reporting.sql', import.meta.url), 'utf8');
const rollback = fs.readFileSync(new URL('../tools/sql/rollback_urc_2025_26_injury_to_illness_reporting.sql', import.meta.url), 'utf8');
const verification = fs.readFileSync(new URL('../tools/sql/verify_urc_2025_26_injury_to_illness_reporting.sql', import.meta.url), 'utf8');

test('deparsed view substitutions replace column qualifiers as well as FROM relations', () => {
  const illnessReplacement = sql.match(/replace\(previous, '(urc_illness_profile_rows_v1)', '(urc_illness_profile_rows_v2)'\)/);
  assert.ok(illnessReplacement, 'Replace the unqualified relation name throughout the deparsed view');
  assert.match(sql, /replace\(item\.definition, split_part\(source_name, '\.', 2\),\s*split_part\(successor_name, '\.', 2\)\)/);
  for (const [schema, oldName, newName] of [
    ['analysis', illnessReplacement[1], illnessReplacement[2]],
    ['reporting', 'diagnosis_family_team_dashboard_payloads_v2', 'diagnosis_family_team_dashboard_payloads_v3'],
    ['reporting', 'diagnosis_family_league_dashboard_payloads_v2', 'diagnosis_family_league_dashboard_payloads_v3'],
  ]) {
    const deparsed = `SELECT ${oldName}.season FROM ${schema}.${oldName};`;
    const rebound = deparsed.replaceAll(oldName, newName);
    assert.equal(rebound, `SELECT ${newName}.season FROM ${schema}.${newName};`);
    assert.ok(!rebound.includes(oldName));
  }
});

test('exact reviewed cohort moves without changing classification or missing duration', () => {
  const rows = [...sql.matchAll(/\((\d+), '(dragons|ospreys|glasgow)', '([a-f0-9]{64})', '(Time Loss|Medical Attention)', (\d+|null)\)/g)]
    .map(([, row, team, hash, classification, days]) => ({
      row: Number(row), team, hash, classification, days: days === 'null' ? null : Number(days),
    }));
  assert.equal(rows.length, 24);
  assert.equal(new Set(rows.map(({ hash }) => hash)).size, 24);
  assert.deepEqual(rows.map(({ row }) => row), [401, 446, 464, 468, 481, 494, 509, 510, 514, 515, 555, 556, 949, 1608, 1610, 1611, 1622, 1631, 1633, 1645, 1646, 1662, 1666, 1696]);
  for (const [team, count, days] of [['dragons', 12, 54], ['ospreys', 11, 38]]) {
    const selected = rows.filter(row => row.team === team);
    assert.equal(selected.length, count);
    assert.equal(selected.reduce((sum, row) => sum + row.days, 0), days);
    assert.ok(selected.every(row => row.classification === 'Time Loss'));
  }
  assert.deepEqual(rows.filter(row => row.team === 'glasgow').map(({ row, days, classification }) => ({ row, days, classification })), [
    { row: 949, days: null, classification: 'Medical Attention' },
  ]);
  assert.match(sql, /master\.final_master_row_sha256 = approved\.row_sha256/);
  assert.match(sql, /master\.time_loss_days is not distinct from approved\.days/);
  assert.match(sql, /time_loss_days is not null, time_loss_days/);
  assert.match(sql, /retained_source_identity/);
  assert.doesNotMatch(sql, /coalesce\(.*time_loss_days.*,\s*0\)/i);
});

test('all active readers inherit regenerated aggregates with retained rollback and permissions', () => {
  assert.match(sql, /refresh materialized view analysis\.urc_diagnosis_family_rows_v1/);
  assert.match(sql, /reporting\.urc_canonical_injury_sections_json_v2\('2025-26', target_team\)/);
  assert.match(sql, /sections - array\['method', 'headline', 'monthly'\]/);
  assert.match(sql, /when old\.item ->> 'incidence_per_1000h' is null then null/);
  assert.match(sql, /to_date\(month ->> 'month', 'YYYY-MM'\)/);
  for (const kind of ['team', 'league']) {
    assert.match(sql, new RegExp(`create materialized view reporting\\.diagnosis_family_${kind}_dashboard_payloads_v3`));
    assert.match(sql, new RegExp(`from reporting\\.diagnosis_family_${kind}_dashboard_payloads_v2`));
    assert.match(sql, new RegExp(`reporting\\.latest_${kind}_dashboard_v7`));
  }
  assert.match(sql, /':urc_2025_26_injury_to_illness_2026_09_03_v1'/);
  assert.match(sql, /before update or delete/);
  assert.match(sql, /enable row level security/);
  assert.doesNotMatch(sql, /\b(?:insert into|update|delete from|alter table)\s+(?:lineage|ingestion|curated)\./i);
  assert.doesNotMatch(sql, /\b(?:insert into|update|delete from)\s+reporting\./i);
  assert.doesNotMatch(sql, /refresh materialized view reporting\./i);
  assert.doesNotMatch(sql, /\bgrant\b|disable trigger|drop .*cascade/i);
  assert.match(sql, /^begin;$/m);
  assert.match(sql, /commit;\s*$/);
  assert.match(rollback, /create or replace view .*item\.definition/s);
  assert.match(rollback, /refresh materialized view analysis\.urc_diagnosis_family_rows_v1/);
  assert.doesNotMatch(rollback, /\b(?:delete from|truncate|drop)\b/i);
  assert.doesNotMatch(verification, /\b(?:insert|update|delete|create|alter|drop|refresh)\b/i);
});
