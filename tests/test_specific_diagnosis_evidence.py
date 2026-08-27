import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "tools/generate_specific_diagnosis_evidence.py"
EVIDENCE = ROOT / "docs/evidence/urc_2024-25_specific_diagnosis_evidence.json"


class SpecificDiagnosisEvidenceTests(unittest.TestCase):
    def run_generator(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(GENERATOR), *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_committed_evidence_reproduces_byte_for_byte(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "specific_diagnosis_evidence.json"
            result = self.run_generator("--output", str(output))

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_bytes(), EVIDENCE.read_bytes())

    def test_rows_are_pseudonymised_and_illness_is_explicitly_excluded(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        rows = evidence["rows"]
        reconciliation = evidence["aggregate_reconciliation"]
        fallback = evidence["scope"]["unmapped_effective_cohort_fallback"]

        self.assertEqual(len(rows), 2052)
        self.assertEqual(reconciliation["injury_metric_rows"], 1660)
        self.assertEqual(
            reconciliation["illness_rows_excluded_from_injury_metrics"], 392
        )
        self.assertEqual(reconciliation["injury_rows_with_illness_flag"], 0)
        self.assertEqual(fallback["rows"], 4)
        self.assertEqual(fallback["source_rows"], [603, 1120, 1121, 1122])
        self.assertEqual(
            sum(row["injury_metric_eligible"] for row in rows), 1660
        )
        self.assertTrue(all("PlayerID" not in row for row in rows))
        self.assertEqual(
            len(
                {
                    row["diagnosis_group_code"]
                    for row in rows
                    if row["injury_metric_eligible"]
                }
            ),
            reconciliation["diagnosis_groups_with_injury_rows"],
        )
        self.assertEqual(
            {
                row["diagnosis_group_code"]
                for row in rows
                if row["diagnosis_group_label"] == "Diagnosis not specified"
            },
            {"unknown"},
        )

        illnesses = [row for row in rows if row["problem_type"] == "Illness"]
        injuries = [row for row in rows if row["problem_type"] == "Injury"]
        self.assertEqual(len(illnesses), 392)
        self.assertTrue(all(not row["injury_metric_eligible"] for row in illnesses))
        self.assertTrue(all(row["injury_metric_eligible"] for row in injuries))
        self.assertEqual(
            next(row for row in rows if row["master_source_row"] == 132)[
                "source_row_sha256"
            ],
            "ca50325fe041d5e33e554cd9e8d47b68ea8df1ef84c31b2859f273c99268fdaa",
        )

    def test_changed_workbook_fails_the_pinned_source_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            changed_workbook = Path(temporary) / "changed.xlsx"
            shutil.copyfile(
                ROOT / "data/2024-25/review/urc_injury_master_review_2024-25.xlsx",
                changed_workbook,
            )
            changed_workbook.write_bytes(changed_workbook.read_bytes() + b"changed")
            result = self.run_generator(
                "--workbook",
                str(changed_workbook),
                "--output",
                str(Path(temporary) / "evidence.json"),
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("authoritative review workbook fingerprint changed", result.stderr)


if __name__ == "__main__":
    unittest.main()
