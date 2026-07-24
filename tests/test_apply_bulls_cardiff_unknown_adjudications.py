from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/apply_bulls_cardiff_unknown_adjudications.py"
SPEC = importlib.util.spec_from_file_location("bulls_cardiff_adjudications", SCRIPT)
assert SPEC and SPEC.loader
RULES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RULES)


class BullsCardiffUnknownAdjudicationTests(unittest.TestCase):
    def fixture(self):
        protected = set(RULES.TARGET_CSV_ROWS + RULES.EXCLUDED_CSV_ROWS)
        other_unknown = [
            csv_row for csv_row in range(2, 143) if csv_row not in protected
        ][: 44 - len(protected)]
        unknown_rows = protected | set(other_unknown)
        rows = []
        for csv_row in range(2, 143):
            rows.append({
                "Team": "Bulls" if csv_row < 130 else "Cardiff",
                "PlayerID": f"Ath_{csv_row}",
                "Problem type": "Injury",
                "Diagnosis": "Reviewed diagnosis",
                "Description": "Reviewed description",
                "TimeLoss vs Medical Attention": (
                    "Unknown" if csv_row in unknown_rows else "Time Loss"
                ),
            })
        return rows

    def test_changes_only_target_rows(self) -> None:
        rows = self.fixture()
        source_rows = list(range(1000, 1000 + len(rows)))
        transformed, audit, qa = RULES.transform_dataset(rows, source_rows)
        for csv_row in RULES.TARGET_CSV_ROWS:
            self.assertEqual(
                transformed[csv_row - 2]["TimeLoss vs Medical Attention"],
                "Time Loss",
            )
        for csv_row in RULES.EXCLUDED_CSV_ROWS:
            self.assertEqual(
                transformed[csv_row - 2]["TimeLoss vs Medical Attention"],
                "Unknown",
            )
        self.assertEqual(len(audit), 11)
        self.assertEqual(qa["unknown_injuries_after"], 33)

    def test_rejects_non_unknown_target(self) -> None:
        rows = self.fixture()
        rows[74 - 2]["TimeLoss vs Medical Attention"] = "Time Loss"
        with self.assertRaisesRegex(ValueError, "Expected Unknown"):
            RULES.transform_dataset(rows, list(range(1000, 1000 + len(rows))))


if __name__ == "__main__":
    unittest.main()
