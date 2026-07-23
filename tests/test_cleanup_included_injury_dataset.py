from __future__ import annotations

import csv
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/cleanup_included_injury_dataset.py"
SPEC = importlib.util.spec_from_file_location(
    "cleanup_included_injury_dataset", SCRIPT
)
assert SPEC and SPEC.loader
CLEANUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLEANUP)


HEADERS = [
    "Team",
    "PlayerID",
    "Date Injured",
    "Confirmed Return Date",
    "Days Injured",
    "Recurrence",
    "TimeLoss vs Medical Attention",
    "Occasion category",
    "Body Part",
    "Injury Tissue Type/s",
    "Is Contact",
    "Diagnosis",
]


def row(**overrides: str) -> dict[str, str]:
    base = {
        "Team": "Team A",
        "PlayerID": "Ath_1",
        "Date Injured": "01/09/2024",
        "Confirmed Return Date": "04/09/2024",
        "Days Injured": "",
        "Recurrence": "New case",
        "TimeLoss vs Medical Attention": "",
        "Occasion category": "Training",
        "Body Part": "Thigh",
        "Injury Tissue Type/s": "Muscle injury",
        "Is Contact": "Non-contact",
        "Diagnosis": "Thigh - Muscle injury",
    }
    base.update(overrides)
    return base


class FocusedCleanupTests(unittest.TestCase):
    def test_derives_missing_days_and_standardizes_related_fields(self) -> None:
        transformed, audit, qa = CLEANUP.transform_dataset([row()], [21])

        self.assertEqual(transformed[0]["Days Injured"], "3")
        self.assertEqual(
            transformed[0]["TimeLoss vs Medical Attention"], "Time Loss"
        )
        self.assertEqual(transformed[0]["Recurrence"], "New injury")
        self.assertEqual(qa["days_injured"]["filled_from_dates"], 1)
        self.assertEqual(qa["days_injured"]["remaining_missing_or_invalid"], 0)
        self.assertEqual(
            {entry["field"] for entry in audit},
            {
                "Days Injured",
                "Recurrence",
                "TimeLoss vs Medical Attention",
            },
        )
        self.assertEqual({entry["source_workbook_row"] for entry in audit}, {21})

    def test_existing_numeric_duration_is_not_overwritten(self) -> None:
        source = row()
        source["Days Injured"] = "1"
        transformed, audit, qa = CLEANUP.transform_dataset([source], [42])

        self.assertEqual(transformed[0]["Days Injured"], "1")
        self.assertEqual(
            qa["days_injured"][
                "existing_numeric_date_span_mismatches_unchanged"
            ],
            1,
        )
        self.assertFalse(
            any(entry["field"] == "Days Injured" for entry in audit)
        )

    def test_missing_token_without_dates_becomes_blank_and_unknown(self) -> None:
        source = row(
            **{
                "Date Injured": "05/09/2024",
                "Confirmed Return Date": "",
                "Days Injured": "-",
                "TimeLoss vs Medical Attention": "",
            }
        )
        transformed, _, qa = CLEANUP.transform_dataset([source], [7])

        self.assertEqual(transformed[0]["Days Injured"], "")
        self.assertEqual(
            transformed[0]["TimeLoss vs Medical Attention"], "Unknown"
        )
        self.assertEqual(qa["days_injured"]["missing_tokens_cleared"], 1)
        self.assertEqual(qa["days_injured"]["remaining_missing_or_invalid"], 1)

    def test_same_day_return_is_medical_attention(self) -> None:
        source = row(
            **{
                "Date Injured": "01/09/2024",
                "Confirmed Return Date": "01/09/2024",
                "Days Injured": "",
                "TimeLoss vs Medical Attention": "TRUE",
            }
        )
        transformed, _, _ = CLEANUP.transform_dataset([source], [8])

        self.assertEqual(transformed[0]["Days Injured"], "0")
        self.assertEqual(
            transformed[0]["TimeLoss vs Medical Attention"],
            "Medical Attention",
        )

    def test_full_apply_preserves_shape_and_updates_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            input_csv = root / "included.csv"
            manifest_path = root / "included.manifest.json"
            backup_csv = root / "included.before.csv"
            backup_manifest = root / "included.before.manifest.json"
            audit_path = root / "audit.csv"
            qa_path = root / "qa.json"
            rows = [row(), row(PlayerID="Ath_2", **{"Days Injured": "0"})]

            with input_csv.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(
                    handle, fieldnames=HEADERS, lineterminator="\n"
                )
                writer.writeheader()
                writer.writerows(rows)

            manifest = {
                "source": {"headers": HEADERS},
                "selection": {"included_source_rows": [10, 12]},
                "output": {
                    "csv_sha256": CLEANUP.sha256_file(input_csv),
                    "data_rows": 2,
                    "columns": len(HEADERS),
                },
            }
            manifest_path.write_text(
                json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
            )

            result = CLEANUP.apply_cleanup(
                input_csv=input_csv,
                manifest_path=manifest_path,
                backup_csv=backup_csv,
                backup_manifest=backup_manifest,
                audit_path=audit_path,
                qa_path=qa_path,
                script_path=SCRIPT,
                repo_root=ROOT,
                generated_at="2026-07-23T20:00:00Z",
                expected_rows=2,
                expected_columns=len(HEADERS),
            )

            self.assertEqual(result["rows"], 2)
            self.assertTrue(backup_csv.exists())
            self.assertTrue(backup_manifest.exists())
            self.assertTrue(audit_path.exists())
            self.assertTrue(qa_path.exists())
            saved_manifest = json.loads(
                manifest_path.read_text(encoding="utf-8")
            )
            self.assertEqual(len(saved_manifest["cleanup_history"]), 1)
            self.assertEqual(
                saved_manifest["output"]["csv_sha256"],
                CLEANUP.sha256_file(input_csv),
            )
            self.assertEqual(
                saved_manifest["selection"]["included_source_rows"], [10, 12]
            )


if __name__ == "__main__":
    unittest.main()
