from __future__ import annotations

import csv
import importlib.util
import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from openpyxl import Workbook


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/export_included_injury_dataset.py"
SPEC = importlib.util.spec_from_file_location("export_included_injury_dataset", SCRIPT)
assert SPEC and SPEC.loader
EXPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORTER)


class ExportIncludedInjuryDatasetTests(unittest.TestCase):
    def build_workbook(self, path: Path, *, with_formula: bool = False) -> None:
        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "Injury Master"
        sheet.append(["Team", "Date Injured", "Days Injured", "Exclusion Reason"])
        sheet.append(["Team A", datetime(2024, 9, 20), 4, None])
        sheet.append(["Team A", datetime(2024, 9, 21), 5, "  "])
        sheet.append(["Team B", datetime(2024, 9, 22), 6, "Non-URC match"])
        if with_formula:
            sheet["C2"] = "=2+2"
        workbook.save(path)

    def test_exports_only_blank_exclusion_rows_with_manifest_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "frozen.xlsx"
            output_csv = root / "included.csv"
            manifest = root / "included.manifest.json"
            self.build_workbook(source)

            payload = EXPORTER.export_included_dataset(
                source=source,
                output_csv=output_csv,
                manifest=manifest,
                script_path=SCRIPT,
                repo_root=ROOT,
                season="2024-25",
                generated_at="2026-07-23T18:00:00Z",
            )

            with output_csv.open(encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["Date Injured"], "20/09/2024")
            self.assertEqual(rows[0]["Days Injured"], "4")
            self.assertEqual(rows[1]["Exclusion Reason"], "  ")

            saved_manifest = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(saved_manifest, payload)
            self.assertEqual(payload["selection"]["included_source_rows"], [2, 3])
            self.assertEqual(payload["selection"]["included_rows"], 2)
            self.assertEqual(payload["selection"]["excluded_rows"], 1)
            self.assertEqual(payload["counts_by_team"]["Team A"]["included_rows"], 2)
            self.assertEqual(payload["counts_by_team"]["Team B"]["excluded_rows"], 1)
            self.assertEqual(
                payload["output"]["csv_sha256"],
                EXPORTER.sha256_file(output_csv),
            )
            self.assertEqual(
                payload["output"]["preserved_source_value_warnings"],
                [],
            )

    def test_refuses_formula_cells(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "formula.xlsx"
            self.build_workbook(source, with_formula=True)
            with self.assertRaisesRegex(ValueError, "Formula found"):
                EXPORTER.export_included_dataset(
                    source=source,
                    output_csv=root / "included.csv",
                    manifest=root / "included.manifest.json",
                    script_path=SCRIPT,
                    repo_root=ROOT,
                    season="2024-25",
                    generated_at="2026-07-23T18:00:00Z",
                )

    def test_refuses_to_overwrite_existing_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "frozen.xlsx"
            output_csv = root / "included.csv"
            manifest = root / "included.manifest.json"
            self.build_workbook(source)
            output_csv.write_text("existing\n", encoding="utf-8")
            with self.assertRaisesRegex(FileExistsError, "Refusing to overwrite"):
                EXPORTER.export_included_dataset(
                    source=source,
                    output_csv=output_csv,
                    manifest=manifest,
                    script_path=SCRIPT,
                    repo_root=ROOT,
                    season="2024-25",
                    generated_at="2026-07-23T18:00:00Z",
                )

    def test_refuses_csv_and_manifest_path_collision(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "frozen.xlsx"
            shared_output = root / "included.csv"
            self.build_workbook(source)
            with self.assertRaisesRegex(ValueError, "three distinct paths"):
                EXPORTER.export_included_dataset(
                    source=source,
                    output_csv=shared_output,
                    manifest=shared_output,
                    script_path=SCRIPT,
                    repo_root=ROOT,
                    season="2024-25",
                    generated_at="2026-07-23T18:00:00Z",
                )

    def test_refuses_source_and_output_path_collision_with_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "frozen.xlsx"
            self.build_workbook(source)
            source_hash = EXPORTER.sha256_file(source)
            with self.assertRaisesRegex(ValueError, "three distinct paths"):
                EXPORTER.export_included_dataset(
                    source=source,
                    output_csv=source,
                    manifest=root / "included.manifest.json",
                    script_path=SCRIPT,
                    repo_root=ROOT,
                    season="2024-25",
                    generated_at="2026-07-23T18:00:00Z",
                    overwrite=True,
                )
            self.assertEqual(EXPORTER.sha256_file(source), source_hash)


if __name__ == "__main__":
    unittest.main()
