from __future__ import annotations

from decimal import Decimal
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools import reconcile_2024_25_timeline as replay


class TimelineSuccessorReconciliationTests(unittest.TestCase):
    def test_local_replay_reconciles_atomic_candidate_and_32_rows(self) -> None:
        candidate, manifest = replay.build_candidate(
            replay.DEFAULT_PREDECESSOR,
            replay.DEFAULT_SOURCE,
            replay.DEFAULT_SOURCE_MANIFEST,
            replay.DEFAULT_MASTER,
            replay.DEFAULT_REVIEW_WORKBOOK,
            replay.DEFAULT_DECISIONS,
            replay.DEFAULT_EVIDENCE,
        )
        league = candidate["league"]
        headline = {item["key"]: item for item in league["headline"]}
        self.assertEqual(len(candidate["teams"]), 16)
        self.assertEqual(headline["recorded_injuries"]["value"], 1662)
        self.assertEqual(headline["time_loss_injuries"]["value"], 913)
        self.assertEqual(headline["severity_mean_days"]["denominator"], 787)
        self.assertEqual(headline["severity_median_days"]["value"], 13)
        self.assertEqual(headline["burden_per_1000h"]["numerator"], 17575)
        expected_rate = float(Decimal(913) * Decimal(1000) / Decimal("81352.91949743334"))
        self.assertEqual(headline["incidence_per_1000h"]["value"], expected_rate)
        expected_overall_rate = float(Decimal(1662) * Decimal(1000) / Decimal("81352.91949743334"))
        self.assertEqual(
            headline["overall_incidence_per_1000h"]["value"],
            expected_overall_rate,
        )

        setting_metrics = {row["setting"]: row for row in league["setting_metrics"]}
        self.assertEqual(
            {key: row["recorded_injuries"] for key, row in setting_metrics.items()},
            {"match": 897, "training": 742, "unknown": 23},
        )
        self.assertEqual(sum(row["recorded_injuries"] for row in setting_metrics.values()), 1662)
        self.assertTrue(all("overall_incidence_per_1000h" in row for row in setting_metrics.values()))

        diagnoses = [
            row for row in league["injury_profiles"]
            if row["dimension"] == "diagnosis" and row["setting"] == "all"
        ]
        self.assertEqual(sum(row["time_loss_injuries"] for row in diagnoses), 913)
        self.assertEqual(sum(row["days_lost"] for row in diagnoses), 17575)
        self.assertFalse(any(row["code"].startswith("compound__") for row in diagnoses))
        self.assertIn("Concussion", {row["label"] for row in diagnoses})
        self.assertIn("unknown", {row["code"] for row in diagnoses})

        self.assertEqual(manifest["classification_contract"]["time_loss_known_duration"], 787)
        self.assertEqual(manifest["classification_contract"]["time_loss_null_duration"], 126)
        self.assertEqual(manifest["classification_contract"]["source_reported_null_duration_time_loss"], 111)
        self.assertEqual(manifest["classification_contract"]["adjudicated_null_duration_time_loss"], 15)
        self.assertEqual(manifest["classification_contract"]["undated_eligible"], 6)
        self.assertEqual(manifest["classification_contract"]["dated_monthly_recorded"], 1656)
        self.assertEqual(manifest["adjudication"]["rows"], 32)
        self.assertEqual(
            manifest["adjudication"]["final_classification_counts"],
            {"Time Loss": 15, "Medical Attention": 1, "unclassified": 16},
        )
        self.assertEqual(
            manifest["adjudication_reconciliation"],
            {
                "adjudicated_null_duration_time_loss": 15,
                "recorded_injuries_delta": 0,
                "observed_days_lost_delta": 0,
            },
        )
        self.assertNotIn("adjudications_delta_vs_predecessor", manifest)

    def test_date_injured_months_and_non_injury_sections_are_preserved(self) -> None:
        candidate, manifest = replay.build_candidate(
            replay.DEFAULT_PREDECESSOR,
            replay.DEFAULT_SOURCE,
            replay.DEFAULT_SOURCE_MANIFEST,
            replay.DEFAULT_MASTER,
            replay.DEFAULT_REVIEW_WORKBOOK,
            replay.DEFAULT_DECISIONS,
            replay.DEFAULT_EVIDENCE,
        )
        predecessor, _ = replay.read_predecessor(replay.DEFAULT_PREDECESSOR)
        for before, after in [(predecessor["league"], candidate["league"])] + [
            (old["dashboard"], new["dashboard"])
            for old, new in zip(predecessor["teams"], candidate["teams"], strict=True)
        ]:
            for key in ("coverage", "prior_season", "analysis_window"):
                self.assertEqual(before[key], after[key])
            self.assertEqual(
                [(row["month"], row["exposure_hours"], row["distance_km"]) for row in before["monthly"]],
                [(row["month"], row["exposure_hours"], row["distance_km"]) for row in after["monthly"]],
            )
            self.assertEqual(after["method"], list(replay.SUCCESSOR_METHOD))
            self.assertEqual(after["limitations"], list(replay.SUCCESSOR_LIMITATIONS))
            self.assertEqual(replay.json_sha256(after["method"]), replay.json_sha256(list(replay.SUCCESSOR_METHOD)))
            self.assertEqual(replay.json_sha256(after["limitations"]), replay.json_sha256(list(replay.SUCCESSOR_LIMITATIONS)))
        self.assertEqual(sum(row["recorded_injuries"] for row in candidate["league"]["monthly"]), 1656)
        self.assertEqual(sum(row["time_loss_injuries"] for row in candidate["league"]["monthly"]), 912)
        self.assertTrue(
            all("overall_incidence_per_1000h" in row for row in candidate["league"]["monthly"])
        )
        self.assertEqual(manifest["classification_contract"]["successor_time_loss_injuries"], 913)
        self.assertEqual(
            manifest["source"]["accepted_review_workbook_sha256"],
            replay.EXPECTED_ACCEPTED_WORKBOOK_SHA256,
        )
        self.assertEqual(
            manifest["source"]["review_workbook_role"],
            "locator only; not authoritative source identity or calculation input",
        )
        self.assertEqual(
            manifest["non_injury_fields_checked"],
            ["analysis_window", "coverage", "prior_season", "monthly exposure_hours", "monthly distance_km"],
        )
        self.assertEqual(
            manifest["controlled_successor_disclosures"],
            {
                "method": list(replay.SUCCESSOR_METHOD),
                "limitations": list(replay.SUCCESSOR_LIMITATIONS),
                "method_sha256": replay.json_sha256(list(replay.SUCCESSOR_METHOD)),
                "limitations_sha256": replay.json_sha256(list(replay.SUCCESSOR_LIMITATIONS)),
            },
        )

    def test_master_hashes_and_source_facts_match_all_adjudications(self) -> None:
        headers, master_rows, _ = replay.read_master(replay.DEFAULT_MASTER)
        evidence = json.loads(replay.DEFAULT_EVIDENCE.read_text(encoding="utf-8"))
        rows = evidence["row_adjudications"]
        self.assertEqual(len(rows), 32)
        self.assertEqual(
            {row["source_value"] for row in rows},
            {"", "FALSE"},
        )
        self.assertEqual(sum(row["source_value"] == "" for row in rows), 29)
        for item in rows:
            self.assertEqual(
                replay.master_row_hash(headers, master_rows[item["source_row"]]),
                item["source_row_sha256"],
            )

    def test_atomic_cli_writes_candidate_and_reconciliation_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "candidate.json"
            manifest = Path(directory) / "candidate.reconciliation.json"
            self.assertEqual(
                replay.main(["--output", str(output), "--manifest", str(manifest)]),
                0,
            )
            self.assertTrue(output.is_file())
            self.assertTrue(manifest.is_file())
            self.assertEqual(json.loads(manifest.read_text())["atomic_output"], True)

    def test_changed_evidence_fails_before_any_candidate_write(self) -> None:
        original_hash = replay.file_sha256

        def altered_hash(path: Path) -> str:
            if path == replay.DEFAULT_EVIDENCE:
                return "0" * 64
            return original_hash(path)

        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            replay, "file_sha256", side_effect=altered_hash
        ):
            output = Path(directory) / "candidate.json"
            with self.assertRaises(replay.ReconciliationError):
                replay.main(["--output", str(output)])
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
