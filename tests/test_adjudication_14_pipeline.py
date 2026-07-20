import hashlib
import json
import unittest
from pathlib import Path

from pipeline.__main__ import (
    APPROVED_ADJUDICATION_14_EVIDENCE_SHA256,
    APPROVED_ADJUDICATION_14_MANIFEST_SHA256,
    APPROVED_ADJUDICATION_14_WORKBOOK_SHA256,
    adjudicated_derived_change_events,
    apply_source_field_adjudications,
    effective_days_injured_with_origin,
    expected_adjudication_batch_records,
)


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260720150000_adjudicated_reporting_classification.sql"
READER_MIGRATION = ROOT / "supabase/migrations/20260720151000_dashboard_bundle_successor_reader.sql"
MANIFEST = ROOT / "data/reporting/adjudication_14_approved_batch.json"
PIPELINE = ROOT / "pipeline/__main__.py"


class AdjudicationPipelineTest(unittest.TestCase):
    def test_batch_is_exactly_the_approved_14(self):
        manifest = json.loads(MANIFEST.read_text())
        item_ids = {
            *(item["item_id"] for item in manifest["source_corrections"]),
            *(item["item_id"] for item in manifest["duplicate_reviews"]),
            *(item["item_id"] for item in manifest["rule_decisions"]),
        }
        self.assertEqual(len(item_ids), 14)
        self.assertEqual(len(manifest["source_corrections"]), 3)
        self.assertEqual(len(manifest["duplicate_reviews"]), 9)
        self.assertEqual(len(manifest["rule_decisions"]), 2)
        self.assertEqual(
            manifest["workbook_sha256"],
            hashlib.sha256((ROOT / "data/reporting/adjudication_14_needs_abdel_2024-25_approved_b258bd9a.xlsx").read_bytes()).hexdigest(),
        )
        self.assertEqual(manifest["workbook_sha256"], APPROVED_ADJUDICATION_14_WORKBOOK_SHA256)
        self.assertEqual(
            manifest["evidence_manifest_sha256"],
            hashlib.sha256((ROOT / "data/reporting/adjudication_checklist_2024-25_evidence.json").read_bytes()).hexdigest(),
        )
        self.assertEqual(manifest["evidence_manifest_sha256"], APPROVED_ADJUDICATION_14_EVIDENCE_SHA256)
        self.assertEqual(hashlib.sha256(MANIFEST.read_bytes()).hexdigest(), APPROVED_ADJUDICATION_14_MANIFEST_SHA256)
        self.assertEqual(
            manifest["classification_migration_sha256"],
            hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
        )

    def test_source_overlay_is_allowlisted_fingerprinted_and_non_mutating(self):
        row = {"Date Injured": "04/04/2024", "other": "preserved"}
        events = apply_source_field_adjudications(row, [{
            "adjudication_id": "decision-1",
            "row_sha256": "a" * 64,
            "field_name": "Date Injured",
            "rationale": "approved",
            "decision": {
                "decision_type": "source_field_correction",
                "item_id": "ID-03",
                "old_value": "04/04/2024",
                "new_value": "04/04/2025",
                "source_row_sha256": "a" * 64,
                "evidence_sha256": "b" * 64,
            },
        }])
        self.assertEqual(row["Date Injured"], "04/04/2025")
        self.assertEqual(row["other"], "preserved")
        self.assertEqual(events[0]["action"], "correct")
        with self.assertRaises(SystemExit):
            apply_source_field_adjudications(
                {"Description": "old"},
                [{"field_name": "Description", "decision": {}}],
            )

        cardiff = {"Date Injured": "30/11/2024", "Fit For Selection Date": "10/02/24"}
        apply_source_field_adjudications(cardiff, [{
            "adjudication_id": "decision-2", "row_sha256": "c" * 64,
            "field_name": "Fit For Selection Date",
            "decision": {"item_id": "ID-01", "old_value": "10/02/24",
                "new_value": "10/02/2025", "source_row_sha256": "c" * 64,
                "evidence_sha256": "d" * 64},
        }])
        self.assertEqual(cardiff["Adapter Canonical Confirmed Return Date"], "10/02/2025")
        self.assertEqual(effective_days_injured_with_origin(cardiff)[0], 71)

        cardiff_two = {"Date Injured": "12/04/2025", "Fit For Selection Date": "01/05/24"}
        apply_source_field_adjudications(cardiff_two, [{
            "adjudication_id": "decision-3", "row_sha256": "e" * 64,
            "field_name": "Fit For Selection Date",
            "decision": {"item_id": "ID-02", "old_value": "01/05/24",
                "new_value": "01/05/2025", "source_row_sha256": "e" * 64,
                "evidence_sha256": "f" * 64},
        }])
        self.assertEqual(effective_days_injured_with_origin(cardiff_two)[0], 18)

        dragons = {
            "Date Injured": "04/04/2024",
            "Adapter Canonical Confirmed Return Date": "04/04/2025",
            "Adapter Canonical Confirmed Return Date Origin":
                "approved_mapping:standardized_return_to_availability_exact_row",
        }
        apply_source_field_adjudications(dragons, [{
            "adjudication_id": "decision-4", "row_sha256": "1" * 64,
            "field_name": "Date Injured",
            "decision": {"item_id": "ID-03", "old_value": "04/04/2024",
                "new_value": "04/04/2025", "source_row_sha256": "1" * 64,
                "evidence_sha256": "2" * 64},
        }])
        self.assertEqual(effective_days_injured_with_origin(dragons)[0], 0)

    def test_exact_expected_records_bind_every_replay_field(self):
        manifest = json.loads(MANIFEST.read_text())
        row_records, rule_records = expected_adjudication_batch_records(
            source_corrections=manifest["source_corrections"],
            duplicate_reviews=manifest["duplicate_reviews"],
            rule_decisions=manifest["rule_decisions"],
            workbook_sha256=manifest["workbook_sha256"],
            evidence_manifest_sha256=manifest["evidence_manifest_sha256"],
            workbook_path=(
                ROOT / "data/reporting/"
                "adjudication_14_needs_abdel_2024-25_approved_b258bd9a.xlsx"
            ).resolve(),
            migration_version=manifest["classification_migration_version"],
            migration_sha256=manifest["classification_migration_sha256"],
        )
        self.assertEqual(len(row_records), 12)
        self.assertEqual(len(rule_records), 2)
        self.assertEqual(
            [record["decision"]["item_id"] for record in row_records],
            sorted(["ID-01", "ID-02", "ID-03", "DX-02", "DX-03", "DX-12",
                    "DX-13", "DX-14", "DX-15", "DX-16", "DX-17", "DX-18"]),
        )
        self.assertEqual(
            [record["adjudication_ref"] for record in rule_records],
            ["ACL-01", "IA-02"],
        )
        self.assertTrue(all(record["reviewer"] == "Abdel Babiker" for record in row_records))
        self.assertTrue(all(record["reviewer"] == "Abdel Babiker" for record in rule_records))
        self.assertTrue(all(record["rationale"] for record in row_records + rule_records))
        self.assertTrue(all(
            record["workbook_snapshot_locator"].startswith(str(ROOT))
            for record in rule_records
        ))

    def test_every_changed_derived_field_gets_an_event(self):
        events = adjudicated_derived_change_events(
            {"date_injured": "2024-04-04", "days_injured_source": 364, "unchanged": 1},
            {"date_injured": "2025-04-04", "days_injured_source": 0, "unchanged": 1},
            ["ID-03"],
        )
        self.assertEqual({event["field_name"] for event in events}, {"date_injured", "days_injured_source"})
        self.assertTrue(all(event["review_status"] == "adjudicated" for event in events))

    def test_classification_is_additive_and_keeps_v2_cohort(self):
        sql = MIGRATION.read_text()
        self.assertIn("analysis.injury_cohort_by_build_v2", sql)
        self.assertIn("analysis.accepted_reporting_classification_rules_v3", sql)
        self.assertIn("'concussion'", sql)
        self.assertIn("concat(c.body_location_label, ' · ', c.injury_type_label)", sql)
        self.assertIn("analysis.team_dashboard_payload_adjudicated_v3", sql)
        self.assertIn("analysis.league_dashboard_payload_adjudicated_v3", sql)
        self.assertGreaterEqual(sql.count("join analysis.league_member_releases_v2 m"), 3)
        self.assertNotIn("date '2024-07-01'", sql)
        self.assertNotIn("date '2025-06-30'", sql)

    def test_old_bundle_stays_visible_after_successful_member_restatement(self):
        sql = READER_MIGRATION.read_text()
        self.assertIn("team_release.status = 'retired'", sql)
        self.assertIn("source_run.status = 'succeeded'", sql)
        self.assertIn("count(distinct rows.section)", sql)
        self.assertIn("sum(exposure.match_hours) = 6040.0", sql)

    def test_bundle_successor_is_predecessor_bound_and_recoverable(self):
        source = PIPELINE.read_text()
        self.assertIn("--previous-bundle-file", source)
        self.assertIn("approved predecessor changed after preflight validation", source)
        self.assertIn("perform 1 from reporting.teams order by team_key for update", source)
        self.assertIn("predecessor_bundle_sha256", source)
        self.assertIn("database_promotion_rolled_back", source)
        self.assertIn("local_export_failed_predecessor_restored", source)
        self.assertIn("--snapshot-current", source)


if __name__ == "__main__":
    unittest.main()
