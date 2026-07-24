from __future__ import annotations

import csv
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INTAKE = ROOT / "tools/intake.py"
CHECKS = ROOT / "tools/checks.py"
HEADERS = [
    "Team",
    "PlayerID",
    "Received At Club",
    "Received/Injured In Team",
    "Problem type",
    "Date Injured",
    "Fit For Selection Date",
    "Confirmed Return Date",
    "Days Injured",
    "Occasion category",
    "Body Part",
    "Orchard Code",
    "Illness Code",
    "Description",
    "Injury Tissue Type/s",
    "Side",
    "Nature of onset",
    "Recurrence",
    "Is Contact",
    "Mechanism of Injury",
    "Mechanism Notes",
    "Injury Surface Type",
    "Match Type",
    "Received At Position",
    "Required Surgery",
    "TimeLoss vs Medical Attention",
    "Diagnosis",
    "Exclusion Reason",
]


def blank_row(**values: str) -> list[str]:
    return [values.get(header, "") for header in HEADERS]


def master_payload(headers: list[str], rows: list[list[object]]) -> dict:
    return {
        "format": "urc-master-workbook",
        "format_version": 1,
        "source": {"path": "synthetic", "sha256": "0" * 64},
        "sheets": [
            {
                "name": "Injury Master",
                "max_row": len(rows) + 1,
                "max_column": len(headers),
                "values": [headers, *rows],
                "styles": {},
                "column_widths": {},
                "row_heights": {},
                "merged_ranges": [],
                "tables": [],
            }
        ],
    }


class IntakeAndChecksTests(unittest.TestCase):
    def setUpRoot(self, root: Path) -> None:
        baseline = (
            root
            / "data"
            / "2024-25"
            / "master"
            / "master_2024-25_v5.json"
        )
        baseline.parent.mkdir(parents=True)
        baseline.write_text(
            json.dumps(master_payload(HEADERS, [])),
            encoding="utf-8",
        )

    def write_csv(
        self,
        path: Path,
        headers: list[str],
        rows: list[list[str]],
    ) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(headers)
            writer.writerows(rows)

    def run_intake(self, root: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["python3", str(INTAKE), *args],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )

    def run_checks(self, root: Path, season: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["python3", str(CHECKS), "--season", season, "--report", "report.json"],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_missing_columns_lists_every_missing_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            source = root / "team.csv"
            missing = ["Occasion category", "Required Surgery"]
            supplied = [header for header in HEADERS if header not in missing]
            self.write_csv(source, supplied, [])
            result = self.run_intake(
                root,
                "--team",
                "test",
                "--season",
                "2025-26",
                "--file",
                str(source),
            )
            self.assertEqual(result.returncode, 2)
            for header in missing:
                self.assertIn(header, result.stderr)

    def test_absent_allowed_columns_are_filled_or_blank(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            source = root / "team.csv"
            supplied = [
                header
                for header in HEADERS
                if header not in ("Team", "Diagnosis", "Exclusion Reason")
            ]
            self.write_csv(
                source,
                supplied,
                [["v" if header == "PlayerID" else "" for header in supplied]],
            )
            result = self.run_intake(
                root,
                "--team",
                "test",
                "--season",
                "2025-26",
                "--file",
                str(source),
                "--team-display",
                "Test Team",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            master = json.loads(
                (root / "data/2025-26/master/master_2025-26.json").read_text()
            )
            sheet = master["sheets"][0]
            team_index = sheet["values"][0].index("Team")
            diagnosis_index = sheet["values"][0].index("Diagnosis")
            self.assertEqual(sheet["values"][1][team_index], "Test Team")
            self.assertIsNone(sheet["values"][1][diagnosis_index])

    def test_extra_columns_are_dropped_and_format_only_normalization_holds(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            source = root / "team.csv"
            report = root / "intake.json"
            row = blank_row(
                Team=" Test Team ",
                PlayerID=" P1 ",
                **{
                    "Date Injured": "01/07/2025",
                    "Occasion category": " bespoke-value ",
                },
            )
            supplied_headers = [
                header for header in HEADERS if header != "Exclusion Reason"
            ]
            supplied_row = [
                row[HEADERS.index(header)] for header in supplied_headers
            ]
            self.write_csv(
                source,
                [*supplied_headers, "source_row"],
                [[*supplied_row, "7"]],
            )
            result = self.run_intake(
                root,
                "--team",
                "test",
                "--season",
                "2025-26",
                "--file",
                str(source),
                "--out-report",
                str(report),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            details = json.loads(report.read_text())
            self.assertEqual(details["dropped_columns"], ["source_row"])
            master = json.loads(
                (
                    root / "data/2025-26/master/master_2025-26.json"
                ).read_text()
            )
            values = master["sheets"][0]["values"][1]
            self.assertEqual(values[HEADERS.index("Team")], "Test Team")
            self.assertEqual(
                values[HEADERS.index("Date Injured")],
                {"$type": "datetime", "value": "2025-07-01T00:00:00"},
            )
            self.assertEqual(
                values[HEADERS.index("Occasion category")],
                "bespoke-value",
            )
            self.assertIsNone(values[HEADERS.index("Exclusion Reason")])

    def test_append_is_order_preserving_and_append_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            first = root / "first.csv"
            second = root / "second.csv"
            self.write_csv(first, HEADERS, [blank_row(Team="A", PlayerID="1")])
            self.write_csv(second, HEADERS, [blank_row(Team="B", PlayerID="2")])
            for team, source in (("a", first), ("b", second)):
                result = self.run_intake(
                    root,
                    "--team",
                    team,
                    "--season",
                    "2025-26",
                    "--file",
                    str(source),
                )
                self.assertEqual(result.returncode, 0, result.stderr)
            master = json.loads(
                (
                    root / "data/2025-26/master/master_2025-26.json"
                ).read_text()
            )
            rows = master["sheets"][0]["values"][1:]
            self.assertEqual(
                [row[HEADERS.index("PlayerID")] for row in rows],
                ["1", "2"],
            )

    def test_frozen_season_refuses_without_force_append(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            (root / "data/2024-25/master/baseline_record.json").write_text(
                "{}",
                encoding="utf-8",
            )
            source = root / "team.csv"
            self.write_csv(source, HEADERS, [blank_row(Team="A")])
            result = self.run_intake(
                root,
                "--team",
                "a",
                "--season",
                "2024-25",
                "--file",
                str(source),
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("Refusing to append to frozen season", result.stderr)
            self.assertIn("--force-append", result.stderr)

    def test_validate_classifies_covered_and_unexplained_differences(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            baseline_path = (
                root
                / "data/2024-25/master/master_2024-25_v5.json"
            )
            baseline_row = blank_row(
                Team="Test",
                PlayerID="P1",
                **{
                    "Date Injured": "2024-07-01",
                    "Occasion category": "Match",
                    "Body Part": "Head",
                    "Description": "Event",
                },
            )
            baseline_row[HEADERS.index("Date Injured")] = {
                "$type": "datetime",
                "value": "2024-07-01T00:00:00",
            }
            baseline_path.write_text(
                json.dumps(master_payload(HEADERS, [baseline_row])),
                encoding="utf-8",
            )
            records = (
                root / "data/2024-25/intake/standardization_records"
            )
            records.mkdir(parents=True)
            (records / "test.json").write_text(
                json.dumps(
                    {
                        "team": "Test",
                        "row_reconciliation": {
                            "physical_row_range_in_master": [2, 2]
                        },
                        "value_change_summary": {
                            "by_field": {"Occasion category": {"event_count": 1}},
                            "evidence": [],
                        },
                        "steps_applied": [],
                    }
                ),
                encoding="utf-8",
            )
            source = root / "team.csv"
            intake_row = blank_row(
                Team="Test",
                PlayerID="P1",
                **{
                    "Date Injured": "01/07/2024",
                    "Occasion category": "Training",
                    "Body Part": "Neck",
                    "Description": "Event",
                },
            )
            self.write_csv(source, HEADERS, [intake_row])
            report = root / "validation.json"
            result = self.run_intake(
                root,
                "--team",
                "test",
                "--season",
                "2024-25",
                "--file",
                str(source),
                "--validate-against-baseline",
                "--out-report",
                str(report),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            details = json.loads(report.read_text())
            self.assertEqual(details["alignment"]["aligned_rows"], 1)
            self.assertEqual(details["difference_counts"]["covered"], 1)
            self.assertEqual(details["difference_counts"]["unexplained"], 1)
            self.assertEqual(
                details["unexplained_differences"][0]["field"],
                "Body Part",
            )

    def test_checks_fail_on_header_drift_and_unexcluded_duplicate_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            master_dir = root / "data/2025-26/master"
            master_dir.mkdir(parents=True)
            drifted = [*HEADERS]
            drifted[0], drifted[1] = drifted[1], drifted[0]
            (master_dir / "master_2025-26.json").write_text(
                json.dumps(master_payload(drifted, [blank_row(Team="A")])),
                encoding="utf-8",
            )
            result = self.run_checks(root, "2025-26")
            self.assertEqual(result.returncode, 1)
            details = json.loads((root / "report.json").read_text())
            self.assertEqual(
                details["failures"][0]["check"],
                "canonical_header_order",
            )

            duplicate = blank_row(
                Team="A", PlayerID="P1", **{"Date Injured": "01/07/2025"}
            )
            (master_dir / "master_2025-26.json").write_text(
                json.dumps(master_payload(HEADERS, [duplicate, duplicate])),
                encoding="utf-8",
            )
            result = self.run_checks(root, "2025-26")
            self.assertEqual(result.returncode, 1)
            details = json.loads((root / "report.json").read_text())
            self.assertTrue(
                any(
                    item["check"] == "identical_full_rows"
                    for item in details["failures"]
                )
            )

    def test_checks_flag_out_of_window_date_and_negative_days(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.setUpRoot(root)
            master_dir = root / "data/2025-26/master"
            master_dir.mkdir(parents=True)
            row = blank_row(
                Team="A",
                PlayerID="P1",
                **{
                    "Date Injured": "30/06/2025",
                    "Days Injured": "-1",
                },
            )
            (master_dir / "master_2025-26.json").write_text(
                json.dumps(master_payload(HEADERS, [row])),
                encoding="utf-8",
            )
            result = self.run_checks(root, "2025-26")
            self.assertEqual(result.returncode, 0, result.stderr)
            details = json.loads((root / "report.json").read_text())
            self.assertEqual(
                len(details["flags"]["dates_outside_season_window"]),
                1,
            )
            self.assertEqual(
                len(details["flags"]["negative_days_injured"]),
                1,
            )


if __name__ == "__main__":
    unittest.main()
