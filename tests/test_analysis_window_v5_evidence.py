import csv
import json
import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "tools" / "generate_analysis_window_v5_evidence.py"


class AnalysisWindowV5EvidenceTests(unittest.TestCase):
    def run_generator(
        self, *args: str, standard_input: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(GENERATOR), *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            input=standard_input,
            check=False,
        )

    def test_injury_audit_hashes_the_stable_source_row(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "injury_audit.csv"
            result = self.run_generator(
                "injury-audit",
                "--output",
                str(output),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(result.stdout),
                {"days_lost": 4920, "rows": 208, "time_loss_rows": 140},
            )
            with output.open(encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 208)
            self.assertEqual(rows[0]["effective_v5_cohort_reason"], "dated_before_2024-09-01")
            self.assertEqual(len(rows[0]["source_row_evidence_key"]), 64)

    def test_injury_audit_rejects_csv_and_mapping_tampering(self) -> None:
        accepted_csv = (
            ROOT
            / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.csv"
        )
        accepted_manifest = (
            ROOT
            / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.manifest.json"
        )
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            tampered_csv = temporary_path / "tampered.csv"
            tampered_csv.write_bytes(accepted_csv.read_bytes() + b"\n")
            csv_result = self.run_generator(
                "injury-audit",
                "--injury-input",
                str(tampered_csv),
                "--injury-manifest",
                str(accepted_manifest),
                "--output",
                str(temporary_path / "csv_output.csv"),
            )
            self.assertNotEqual(csv_result.returncode, 0)
            self.assertIn("accepted inclusion CSV fingerprint", csv_result.stderr)

            tampered_manifest = temporary_path / "tampered_manifest.json"
            manifest = json.loads(accepted_manifest.read_text(encoding="utf-8"))
            source_rows = manifest["selection"]["included_source_rows"]
            source_rows[0], source_rows[1] = source_rows[1], source_rows[0]
            tampered_manifest.write_text(json.dumps(manifest), encoding="utf-8")
            mapping_result = self.run_generator(
                "injury-audit",
                "--injury-input",
                str(accepted_csv),
                "--injury-manifest",
                str(tampered_manifest),
                "--output",
                str(temporary_path / "mapping_output.csv"),
            )
            self.assertNotEqual(mapping_result.returncode, 0)
            self.assertIn("source-row mapping", mapping_result.stderr)

    def test_exposure_evidence_redacts_raw_semantic_value(self) -> None:
        fields = [
            "stable_source_row_id",
            "curated_build_id",
            "approved_member_build",
            "team",
            "reporting_grain",
            "period_start",
            "period_end",
            "historical_eligibility_status",
            "historical_exclusion_reasons",
            "effective_v5_eligibility_status",
            "effective_v5_exclusion_reasons",
            "outside_official_analysis_window_removed",
            "pre_urc_match_rule_rejected",
            "pre_urc_match_evidence_class",
            "pre_urc_match_evidence_value",
            "exposure_hours",
            "rule_basis_code",
        ]
        row = {
            "stable_source_row_id": "opaque-source-row-id",
            "curated_build_id": "opaque-build-id",
            "approved_member_build": "true",
            "team": "Club One",
            "reporting_grain": "session",
            "period_start": "2024-09-08",
            "period_end": "2024-09-08",
            "historical_eligibility_status": "excluded_from_primary",
            "historical_exclusion_reasons": "outside_official_analysis_window",
            "effective_v5_eligibility_status": "excluded_from_primary",
            "effective_v5_exclusion_reasons": "pre_urc_non_urc_match",
            "outside_official_analysis_window_removed": "true",
            "pre_urc_match_rule_rejected": "true",
            "pre_urc_match_evidence_class": "verified_currie_cup_match",
            "pre_urc_match_evidence_value": "sensitive raw source label",
            "exposure_hours": "1.25",
            "rule_basis_code": "pre_urc_non_urc_match",
        }
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            input_path = temporary_path / "effective_exposure.csv"
            output = temporary_path / "exposure_evidence.csv"
            with input_path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                writer.writerow(row)

            result = self.run_generator(
                "exposure-evidence",
                "--input",
                str(input_path),
                "--output",
                str(output),
                "--expected-rejected-rows",
                "1",
                "--expected-rejected-hours",
                "1.25",
                "--evidence-schema",
                str(self._schema_for_team(temporary_path, "Club One", 1, "1.25")),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(result.stdout),
                {"pre_urc_rejected_hours": "1.250000", "pre_urc_rejected_rows": 1, "rows": 1},
            )
            contents = output.read_text(encoding="utf-8")
            self.assertNotIn("opaque-source-row-id", contents)
            self.assertNotIn("opaque-build-id", contents)
            self.assertNotIn("sensitive raw source label", contents)
            self.assertIn("verified_currie_cup_match", contents)

    def test_exposure_evidence_accepts_json_only_from_standard_input(self) -> None:
        row = {
            "stable_source_row_id": "opaque-source-row-id",
            "curated_build_id": "opaque-build-id",
            "approved_member_build": True,
            "team": "Club One",
            "reporting_grain": "session",
            "period_start": "2024-09-08",
            "period_end": "2024-09-08",
            "historical_eligibility_status": "excluded_from_primary",
            "historical_exclusion_reasons": ["outside_official_analysis_window"],
            "effective_v5_eligibility_status": "excluded_from_primary",
            "effective_v5_exclusion_reasons": ["pre_urc_non_urc_match"],
            "outside_official_analysis_window_removed": True,
            "pre_urc_match_rule_rejected": True,
            "pre_urc_match_evidence_class": "verified_currie_cup_match",
            "pre_urc_match_evidence_value": "sensitive raw source label",
            "exposure_hours": 1.25,
            "rule_basis_code": "pre_urc_non_urc_match",
        }
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "exposure_evidence.csv"
            result = self.run_generator(
                "exposure-evidence",
                "--input-json",
                "-",
                "--output",
                str(output),
                "--expected-rejected-rows",
                "1",
                "--expected-rejected-hours",
                "1.25",
                "--evidence-schema",
                str(self._schema_for_team(Path(temporary), "Club One", 1, "1.25")),
                standard_input=json.dumps([row]),
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            contents = output.read_text(encoding="utf-8")
            self.assertNotIn("opaque-source-row-id", contents)
            self.assertNotIn("sensitive raw source label", contents)

    @staticmethod
    def _schema_for_team(
        directory: Path, team: str, rows: int, hours: str
    ) -> Path:
        schema = directory / "evidence_schema.json"
        schema.write_text(
            json.dumps(
                {
                    "required_reconciliation": {
                        "rejected_rows_by_team": {
                            team: {"rows": rows, "hours": hours}
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        return schema

    def test_exposure_evidence_rejects_unapproved_builds_and_duplicate_rows(self) -> None:
        base = {
            "stable_source_row_id": "row-1",
            "curated_build_id": "build-1",
            "approved_member_build": False,
            "team": "Club One",
            "reporting_grain": "session",
            "period_start": "2024-09-08",
            "period_end": "2024-09-08",
            "historical_eligibility_status": "excluded_from_primary",
            "historical_exclusion_reasons": "outside_official_analysis_window",
            "effective_v5_eligibility_status": "excluded_from_primary",
            "effective_v5_exclusion_reasons": "pre_urc_non_urc_match",
            "outside_official_analysis_window_removed": True,
            "pre_urc_match_rule_rejected": True,
            "pre_urc_match_evidence_class": "explicit_match",
            "pre_urc_match_evidence_value": "match",
            "exposure_hours": "1.0",
            "rule_basis_code": "analysis_window_v5_effective_row_cohort",
        }
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "evidence.csv"
            schema = self._schema_for_team(Path(temporary), "Club One", 1, "1.0")
            unapproved = self.run_generator(
                "exposure-evidence",
                "--input-json",
                "-",
                "--output",
                str(output),
                "--expected-rejected-rows",
                "1",
                "--expected-rejected-hours",
                "1.0",
                "--evidence-schema",
                str(schema),
                standard_input=json.dumps([base]),
            )
            self.assertNotEqual(unapproved.returncode, 0)
            self.assertIn("superseded or unapproved build", unapproved.stderr)

            approved = {**base, "approved_member_build": True}
            duplicate = self.run_generator(
                "exposure-evidence",
                "--input-json",
                "-",
                "--output",
                str(output),
                "--expected-rejected-rows",
                "2",
                "--expected-rejected-hours",
                "2.0",
                "--evidence-schema",
                str(schema),
                standard_input=json.dumps([approved, approved]),
            )
            self.assertNotEqual(duplicate.returncode, 0)
            self.assertIn("duplicate stable source-row identifier", duplicate.stderr)


if __name__ == "__main__":
    unittest.main()
