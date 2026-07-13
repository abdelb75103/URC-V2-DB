from __future__ import annotations

import argparse
import csv
import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from openpyxl import Workbook

from pipeline.__main__ import (
    adapt_injury_intake,
    clean_exposure,
    export_xlsx_sheet,
    prepare_exposure,
)


def write_book(path: Path, headers: list[str], rows: list[list[object]]) -> None:
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Standardized Data"
    sheet.append(headers)
    for row in rows:
        sheet.append(row)
    workbook.save(path)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


class SouthAfricaIntakeAdapterTests(unittest.TestCase):
    def test_session_duration_rule_is_recorded_even_when_distance_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "prepared.csv"
            output = root / "cleaned.csv"
            qc = root / "qc.json"
            manifest = root / "manifest.json"
            manifest.write_text("{}\n")
            with source.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(
                    handle,
                    fieldnames=[
                        "name", "session date", "minutes total", "distance total",
                        "declared_exposure_grain",
                    ],
                )
                writer.writeheader()
                writer.writerow(
                    {
                        "name": "opaque-player", "session date": "2024-09-20",
                        "minutes total": "221", "distance total": "",
                        "declared_exposure_grain": "session",
                    }
                )

            clean_exposure(
                argparse.Namespace(
                    file=str(source), output=str(output), qc_output=str(qc),
                    manifest=str(manifest), reporting_grain="session", team="stormers",
                    season="2024-25", date_order="day-first",
                    window_start="2024-09-20", window_end="2025-06-14",
                )
            )

            reasons = set(read_csv(output)[0]["exclusion_reason"].split(";"))
            self.assertEqual(
                {"missing_or_unparseable_distance", "session_minutes_above_220"},
                reasons,
            )

    def test_injury_adapter_fills_only_approved_blank_fields_and_blanks_dob(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "injury.xlsx"
            output = root / "injury.csv"
            audit = root / "audit.json"
            write_book(
                source,
                [
                    "PlayerID", "DOB", "Problem type", "Orchard Code",
                    "Injury Tissue Type/s", "Occasion category", "Match vs Training",
                    "Is Contact", "Mechanism of Injury", "Match Type", "Date Injured",
                ],
                [[
                    "opaque-player", datetime(1990, 1, 1), None, "H1", "Concussion",
                    None, "GAME", None, "Tackle (contact)", None, datetime(2024, 9, 1),
                ]],
            )

            adapt_injury_intake(
                argparse.Namespace(
                    team="bulls", season="2024-25", file=str(source),
                    sheet="Standardized Data", output=str(output),
                    audit_output=str(audit), fixture_file="",
                )
            )

            row = read_csv(output)[0]
            self.assertEqual("", row["DOB"])
            self.assertEqual("Injury", row["Problem type"])
            self.assertEqual("GAME", row["Occasion category"])
            self.assertEqual("Contact", row["Is Contact"])
            self.assertEqual("", row["Match Type"])
            report = json.loads(audit.read_text())
            self.assertEqual(1, report["action_counts"]["blank_dob"])
            self.assertEqual(3, report["action_counts"]["populate_approved_blank_field"])

    def test_export_can_blank_dob_at_the_intake_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "injury.xlsx"
            output = root / "injury.csv"
            write_book(
                source,
                ["PlayerID", "DOB", "Date Injured"],
                [["opaque-player", datetime(1990, 1, 1), datetime(2024, 9, 1)]],
            )

            export_xlsx_sheet(
                argparse.Namespace(
                    file=str(source),
                    sheet="Standardized Data",
                    output=str(output),
                    blank_column=["DOB"],
                )
            )

            rows = read_csv(output)
            self.assertEqual(["PlayerID", "DOB", "Date Injured"], list(rows[0]))
            self.assertEqual("", rows[0]["DOB"])

    def test_prepare_exposure_derives_minutes_from_timestamps_and_records_origin(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "exposure.xlsx"
            output = root / "prepared.csv"
            qc = root / "qc.json"
            manifest = root / "manifest.json"
            codebook = root / "codebook.csv"
            write_book(
                source,
                [
                    "name", "session date", "session start date time",
                    "session end date time", "minutes total", "distance total",
                ],
                [[
                    "opaque-player", datetime(2024, 9, 1), datetime(2024, 9, 1, 10, 0),
                    datetime(2024, 9, 1, 11, 30), None, 1000,
                ]],
            )
            manifest.write_text("{}\n")
            codebook.write_text("Standard_Column_Name\n")

            prepare_exposure(
                argparse.Namespace(
                    team="sharks", season="2024-25", file=str(source),
                    sheet="Standardized Data", codebook=str(codebook), output=str(output),
                    qc_output=str(qc), manifest=str(manifest), reporting_grain="session",
                    player_column="name", date_column="session date",
                    minutes_column="minutes total", distance_column="distance total",
                    date_order="month-first", derive_minutes_from_timestamps=True,
                    start_timestamp_column="session start date time",
                    end_timestamp_column="session end date time",
                    distance_source_file="", distance_source_sheet="",
                    distance_source_column="",
                )
            )

            row = read_csv(output)[0]
            self.assertEqual("90.000000", row["minutes total"])
            self.assertEqual("2024-09-01", row["session date"])
            self.assertEqual("2024-09-01 10:00:00", row["session start date time"])
            self.assertEqual("deterministic_end_minus_start", row["minutes_total_origin"])
            self.assertEqual("source_reported", row["distance_total_origin"])

    def test_prepare_exposure_restores_distance_by_physical_source_row(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "standardised.xlsx"
            reference = root / "reference.xlsx"
            output = root / "prepared.csv"
            qc = root / "qc.json"
            manifest = root / "manifest.json"
            codebook = root / "codebook.csv"
            write_book(
                source,
                ["name", "session date", "minutes total", "distance total"],
                [["opaque-player", datetime(2024, 9, 1), "1:00:00", None]],
            )
            write_book(
                reference,
                ["Player Name", "Date", "Duration", "Total Distance"],
                [["direct-name-not-for-output", datetime(2024, 9, 1), "1:00:00", 1234.5]],
            )
            manifest.write_text("{}\n")
            codebook.write_text("Standard_Column_Name\n")

            prepare_exposure(
                argparse.Namespace(
                    team="stormers", season="2024-25", file=str(source),
                    sheet="Standardized Data", codebook=str(codebook), output=str(output),
                    qc_output=str(qc), manifest=str(manifest), reporting_grain="session",
                    player_column="name", date_column="session date",
                    minutes_column="minutes total", distance_column="distance total",
                    date_order="day-first", derive_minutes_from_timestamps=False,
                    start_timestamp_column="session start date time",
                    end_timestamp_column="session end date time",
                    distance_source_file=str(reference),
                    distance_source_sheet="Standardized Data",
                    distance_source_column="Total Distance",
                )
            )

            row = read_csv(output)[0]
            self.assertEqual("1234.5", row["distance total"])
            self.assertEqual("source_reported", row["minutes_total_origin"])
            self.assertEqual("row_aligned_reference_source", row["distance_total_origin"])
            self.assertNotIn("direct-name-not-for-output", output.read_text(encoding="utf-8-sig"))
            adapter = json.loads(qc.read_text())["adapter"]
            self.assertEqual("physical_source_row", adapter["distance_alignment"])


if __name__ == "__main__":
    unittest.main()
