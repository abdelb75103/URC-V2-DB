import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import test from 'node:test';
import { buildLedger, OUTPUT } from '../scripts/build-diagnosis-family-adjudication.mjs';

const REPORT_2025 = '../content/reporting/urc_dashboard_2025-26.json';
const ILLNESS_INVENTORY_2025 = '../docs/evidence/diagnosis-families/illness_label_inventory_2025-26.raw.json';
const slug = (value) => value.normalize('NFKD')
  .replace(/[^\x00-\x7F]/g, '')
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '_')
  .replace(/^_+|_+$/g, '');
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const deterministicCode = (label) => `dx_${slug(label)}_${sha256(label).slice(0, 10)}`;
const readTracked = () => JSON.parse(fs.readFileSync(OUTPUT, 'utf8'));

test('diagnosis-family adjudication is complete, deterministic and reconciles pinned families', () => {
  const ledger = buildLedger();
  assert.deepEqual(ledger, readTracked());
  assert.deepEqual(ledger.scope.source_label_counts, { '2024-25': 554, '2025-26': 420 });
  assert.equal(ledger.rows.length, 974);

  const keys = ledger.rows.map((row) => `${row.season}:${row.source_label}`);
  assert.equal(new Set(keys).size, keys.length);
  assert.equal(ledger.rows.filter((row) => row.review_status === 'human_review').length, 0);
  assert.equal(ledger.illness_rows_2025.length, 113);
  assert.equal(ledger.illness_mapping['2025-26_source_label_count'], 113);
  assert.equal(ledger.source_artifacts['2025-26_illness_inventory'].sha256, '6708f730cfa0faac40799b3eeafb99edd0e3e2e3c9a25de245daaaca1da3ef8d');
  assert.deepEqual(ledger.illness_mapping['2025-26_inventory_reconciliation'], {
    recorded_illnesses: 439,
    known_duration_illnesses: 202,
    days_lost: 927,
  });
  assert.equal(ledger.mapping_hashes.illness_mapping_rows_sha256, '8c195664f215ab59dc52f0cceaee7cfe0d08b7d839f6475d088dbc0827c7c9f4');
  assert.equal(ledger.mapping_hashes.illness_ledger_sha256, '32e6b9622da98723f8702294e1becc0e39f50a12872aeac6fa93c37c30cd1c92');
  const illnessGroups = new Map();
  for (const row of ledger.illness_rows_2025) {
    const current = illnessGroups.get(row.illness_group_label) ?? { recorded_illnesses: 0, known_duration_illnesses: 0, days_lost: 0 };
    current.recorded_illnesses += row.metrics.recorded_illnesses;
    current.known_duration_illnesses += row.metrics.known_duration_illnesses;
    current.days_lost += row.metrics.days_lost;
    illnessGroups.set(row.illness_group_label, current);
  }
  assert.equal(illnessGroups.size, 50);
  for (const [label, metrics] of Object.entries({
    'Upper respiratory infection': [120, 51, 217],
    'Gastrointestinal infection': [70, 40, 133],
    'Gastrointestinal illness, unspecified': [50, 39, 200],
    'Medical illness': [34, 28, 93],
    'Skin infection': [26, 3, 23],
    'Respiratory illness': [16, 9, 33],
    'Herpes infection': [12, 1, 7],
    'Fungal skin infection': [10, 0, 0],
    'Unknown illness': [10, 8, 38],
  })) {
    assert.deepEqual(illnessGroups.get(label), {
      recorded_illnesses: metrics[0],
      known_duration_illnesses: metrics[1],
      days_lost: metrics[2],
    });
  }
  const illnessInventory = JSON.parse(fs.readFileSync(new URL(ILLNESS_INVENTORY_2025, import.meta.url), 'utf8'));
  assert.deepEqual(ledger.illness_rows_2025.map((row) => row.source_label), illnessInventory.map((row) => row.source_label));
  assert.equal(new Set(ledger.illness_rows_2025.map((row) => row.source_label)).size, 113);
  for (const row of ledger.illness_rows_2025) {
    assert.equal(row.season, '2025-26');
    assert.equal(row.metrics.recorded_illnesses > 0, true);
    assert.equal(row.metrics.known_duration_illnesses <= row.metrics.recorded_illnesses, true);
    assert.equal(row.illness_group_code, deterministicCode(row.illness_group_label));
    assert.equal(row.illness_group_code.startsWith('dx_'), true);
  }
  assert.ok(ledger.illness_rows_2025.some((row) => row.source_label === 'Other upper resp tract infection [N/A]' && row.illness_group_label === 'Upper respiratory infection'));
  assert.ok(ledger.illness_rows_2025.some((row) => row.source_label === 'Influenza (A/B) [N/A]' && row.illness_group_label === 'Influenza'));
  assert.ok(ledger.illness_rows_2025.some((row) => row.source_label === 'Unknown' && row.review_status === 'identity_group' && row.illness_group_label === 'Unknown illness'));
  assert.ok(ledger.illness_rows_2025.some((row) => row.source_label === 'Unknown diagnosis' && row.review_status === 'identity_group' && row.illness_group_label === 'Unknown illness'));
  for (const row of ledger.rows) {
    if (row.diagnosis_group_code && row.diagnosis_group_code !== 'unknown') {
      assert.equal(row.diagnosis_group_code, deterministicCode(row.diagnosis_group_label));
    }
    if (row.illness_group_code) {
      assert.equal(row.illness_group_code, deterministicCode(row.illness_group_label));
    }
  }

  const rows2024 = ledger.rows.filter((row) => row.season === '2024-25');
  const rows2025 = ledger.rows.filter((row) => row.season === '2025-26');
  const rowsAll = ledger.rows;
  for (const row of rows2024.filter((candidate) => candidate.problem_type_scope === 'illness')) {
    assert.equal(row.injury_metric_eligible, false);
    assert.equal(row.diagnosis_group_code, null);
    assert.equal(row.review_status, 'out_of_scope');
    assert.equal(row.illness_group_code, row.source_group_code);
    assert.equal(row.illness_group_label, row.source_group_label);
  }
  for (const row of rows2024.filter((candidate) => candidate.source_row_counts.illness > 0)) {
    assert.equal(row.illness_group_code, row.source_group_code);
    assert.equal(row.illness_group_label, row.source_group_label);
  }
  for (const row of ledger.rows.filter((candidate) => candidate.problem_type_scope === 'mixed')) {
    assert.equal(row.row_filter_required, true);
  }
  for (const row of rows2025.filter((candidate) => candidate.problem_type_scope === 'illness')) {
    assert.equal(row.injury_metric_eligible, false);
    assert.equal(row.diagnosis_group_code, null);
    assert.equal(row.review_status, 'out_of_scope');
    assert.equal(row.illness_group_code, rows2024.find((candidate) => candidate.source_label === row.source_label)?.illness_group_code);
    assert.equal(row.illness_group_label, rows2024.find((candidate) => candidate.source_label === row.source_label)?.illness_group_label);
  }
  assert.equal(rows2025.filter((row) => row.problem_type_scope === 'illness').length, 6);

  const concussions = ledger.rules.concussion.included;
  for (const label of concussions) {
    const matches = rowsAll.filter((candidate) => candidate.source_label === label);
    assert.ok(matches.length > 0, `rule summary label missing: ${label}`);
    assert.ok(matches.every((candidate) => candidate.diagnosis_group_label === 'Concussion'));
  }
  for (const label of ledger.rules.concussion.excluded) {
    const matches = rowsAll.filter((candidate) => candidate.source_label === label);
    assert.ok(matches.length > 0, `rule summary label missing: ${label}`);
    assert.ok(matches.every((candidate) => candidate.diagnosis_group_label !== 'Concussion'));
  }
  for (const label of ledger.rules.hamstring_muscle_injury.included) {
    const matches = rowsAll.filter((candidate) => candidate.source_label === label);
    assert.ok(matches.length > 0, `rule summary label missing: ${label}`);
    assert.ok(matches.every((candidate) => candidate.diagnosis_group_label === 'Hamstring muscle injury'));
  }
  for (const label of ledger.rules.hamstring_muscle_injury.excluded) {
    const matches = rowsAll.filter((candidate) => candidate.source_label === label);
    assert.ok(matches.length > 0, `rule summary label missing: ${label}`);
    assert.ok(matches.every((candidate) => candidate.diagnosis_group_label !== 'Hamstring muscle injury'));
  }

  for (const label of [
    'MCL strain/rupture with chondral/meniscal damage knee',
    'Medial collateral ligament strain or rupture with chondral or meniscal damage of the knee',
  ]) {
    assert.ok(rowsAll.filter((candidate) => candidate.source_label === label).every((candidate) => candidate.diagnosis_group_label === 'MCL injury'));
  }
  for (const label of [
    'Abdominal muscle soreness or spasm',
    'ACL or PCL sprain of the knee',
    'Buttock Muscle Strain/Spasm/Trigger Points',
    'Elbow UCL injury and common flexor origin tear',
    'Foot Muscle Strain/Spasm/trigger Points',
    'Forearm muscle soreness',
    'Knee ligament sprain involving the ACL, PCL or a collateral ligament',
    'Lumbar Spine muscle and Tendon Strain/Spasm/Trigger Points',
    'Lumbar soreness or muscle spasm',
    'Neck muscle and/or tendon strain/spasm/trigger points',
    'Neck muscle soreness/spasm/torticollis',
    'Rectus abdominis trigger points or spasm',
    'Sports hernia or abdominal tendinopathy',
    'Thigh Muscle strain/Spasm/Trigger Points',
    'Thoracic Muscle Strain/Spasm/Trigger Points',
  ]) {
    const matches = rowsAll.filter((candidate) => candidate.source_label === label);
    assert.ok(matches.length > 0, `compound label missing: ${label}`);
    assert.ok(matches.every((candidate) => candidate.review_status === 'identity_group' && candidate.identity_group));
  }

  assert.equal(ledger.reconciliation.current_public_input['2025-26'].diagnosis_profile_labels, 420);
  assert.deepEqual(ledger.reconciliation.current_public_input['2025-26'].before_mapping.concussion_family, {
    recorded_injuries: 126,
    time_loss_injuries: 124,
    days_lost: 1747,
  });
  assert.deepEqual(ledger.reconciliation.current_public_input['2025-26'].before_mapping.hamstring_muscle_injury_family, {
    recorded_injuries: 82,
    time_loss_injuries: 78,
    days_lost: 2323,
  });
  assert.deepEqual(ledger.reconciliation.current_public_input['2025-26'].after_mapping.concussion_family, ledger.reconciliation.current_public_input['2025-26'].before_mapping.concussion_family);
  assert.deepEqual(ledger.reconciliation.current_public_input['2025-26'].after_mapping.hamstring_muscle_injury_family, ledger.reconciliation.current_public_input['2025-26'].before_mapping.hamstring_muscle_injury_family);
  assert.deepEqual(ledger.reconciliation.pinned_2025_26.concussion.training, {
    recorded_injuries: 17,
    time_loss_injuries: 17,
    days_lost: 217,
  });
  assert.equal(ledger.reconciliation.pinned_2025_26.hamstring_muscle_injury.overall.time_loss_injuries, 78);

  const report2025 = JSON.parse(fs.readFileSync(new URL(REPORT_2025, import.meta.url), 'utf8'));
  const totalProfiles = (setting) => report2025.injury_profiles
    .filter((profile) => profile.dimension === 'diagnosis' && profile.setting === setting && ledger.rules.concussion.included.includes(profile.label))
    .reduce((totals, profile) => ({
      recorded_injuries: totals.recorded_injuries + profile.recorded_injuries,
      time_loss_injuries: totals.time_loss_injuries + profile.time_loss_injuries,
      days_lost: totals.days_lost + profile.days_lost,
    }), { recorded_injuries: 0, time_loss_injuries: 0, days_lost: 0 });
  assert.deepEqual(ledger.reconciliation.pinned_2025_26.concussion.overall, totalProfiles('all'));
  assert.deepEqual(ledger.reconciliation.pinned_2025_26.concussion.match, totalProfiles('match'));
  assert.deepEqual(ledger.reconciliation.pinned_2025_26.concussion.training, totalProfiles('training'));
});
