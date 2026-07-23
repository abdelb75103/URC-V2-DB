from __future__ import annotations

import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/apply_sharks_squad_normalization.py"
SPEC = importlib.util.spec_from_file_location(
    "apply_sharks_squad_normalization", SCRIPT
)
assert SPEC and SPEC.loader
NORMALIZATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NORMALIZATION)


def workbook_item(
    row: int,
    *,
    team: str,
    received_team: str,
    reason: str = "",
    occasion: str = "Training",
    match_type: str = "",
) -> dict:
    return {
        "source_workbook_row": row,
        "values": {
            "Team": team,
            "PlayerID": f"Ath_{row}",
            "Received/Injured In Team": received_team,
            "Exclusion Reason": reason,
            "Occasion category": occasion,
            "Match Type": match_type,
        },
    }


class SharksNormalizationTests(unittest.TestCase):
    def test_plan_preserves_fixture_rule_and_requires_other_clubs_excluded(self) -> None:
        original_counts = (
            NORMALIZATION.EXPECTED_SHARKS_CHANGES,
            NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES,
            NORMALIZATION.EXPECTED_EXCLUDED_SHARKS_CHANGES,
            NORMALIZATION.EXPECTED_NON_SHARKS_OTHER_TEAM,
        )
        try:
            NORMALIZATION.EXPECTED_SHARKS_CHANGES = 2
            NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES = 1
            NORMALIZATION.EXPECTED_EXCLUDED_SHARKS_CHANGES = 1
            NORMALIZATION.EXPECTED_NON_SHARKS_OTHER_TEAM = 1
            rows = [
                workbook_item(
                    10,
                    team="Sharks",
                    received_team="Other team",
                    occasion="Match",
                    match_type="Confirmed URC match fixture",
                ),
                workbook_item(
                    11,
                    team="Sharks",
                    received_team="Other team",
                    reason="Non-URC match",
                    occasion="Match",
                ),
                workbook_item(
                    12,
                    team="Edinburgh",
                    received_team="Other team",
                    reason="Injury or illness occurred while with another team",
                ),
            ]
            targets, summary = NORMALIZATION.build_normalization_plan(rows)
            self.assertEqual([item["source_workbook_row"] for item in targets], [10, 11])
            self.assertEqual(summary["included_targets"], 1)
            self.assertEqual(summary["excluded_targets"], 1)
            self.assertEqual(summary["non_sharks_other_team_blank_exclusion_reason"], 0)
        finally:
            (
                NORMALIZATION.EXPECTED_SHARKS_CHANGES,
                NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES,
                NORMALIZATION.EXPECTED_EXCLUDED_SHARKS_CHANGES,
                NORMALIZATION.EXPECTED_NON_SHARKS_OTHER_TEAM,
            ) = original_counts

    def test_plan_rejects_included_genuine_other_team_row(self) -> None:
        original_counts = (
            NORMALIZATION.EXPECTED_SHARKS_CHANGES,
            NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES,
            NORMALIZATION.EXPECTED_EXCLUDED_SHARKS_CHANGES,
            NORMALIZATION.EXPECTED_NON_SHARKS_OTHER_TEAM,
        )
        try:
            NORMALIZATION.EXPECTED_SHARKS_CHANGES = 0
            NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES = 0
            NORMALIZATION.EXPECTED_EXCLUDED_SHARKS_CHANGES = 0
            NORMALIZATION.EXPECTED_NON_SHARKS_OTHER_TEAM = 1
            with self.assertRaisesRegex(
                ValueError, "Genuine non-Sharks Other team rows remain included"
            ):
                NORMALIZATION.build_normalization_plan(
                    [
                        workbook_item(
                            12,
                            team="Edinburgh",
                            received_team="Other team",
                        )
                    ]
                )
        finally:
            (
                NORMALIZATION.EXPECTED_SHARKS_CHANGES,
                NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES,
                NORMALIZATION.EXPECTED_EXCLUDED_SHARKS_CHANGES,
                NORMALIZATION.EXPECTED_NON_SHARKS_OTHER_TEAM,
            ) = original_counts

    def test_narrow_csv_patch_preserves_untouched_lines(self) -> None:
        original_rows = NORMALIZATION.EXPECTED_INCLUDED_ROWS
        original_changes = NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES
        try:
            NORMALIZATION.EXPECTED_INCLUDED_ROWS = 3
            NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES = 1
            headers = [
                "Team",
                "Received/Injured In Team",
                "Exclusion Reason",
            ] + [f"Column {index}" for index in range(4, 29)]
            rows = [
                {
                    **{header: "" for header in headers},
                    "Team": "Sharks",
                    "Received/Injured In Team": "Other team",
                },
                {
                    **{header: "" for header in headers},
                    "Team": "Edinburgh",
                    "Received/Injured In Team": "Edinburgh",
                },
                {
                    **{header: "" for header in headers},
                    "Team": "Sharks",
                    "Received/Injured In Team": "Sharks",
                },
            ]
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "included.csv"
                with path.open("w", encoding="utf-8", newline="") as handle:
                    writer = csv.DictWriter(
                        handle, fieldnames=headers, lineterminator="\n"
                    )
                    writer.writeheader()
                    writer.writerows(rows)
                before_lines = path.read_text(encoding="utf-8").splitlines(
                    keepends=True
                )
                changed = NORMALIZATION.patch_included_csv(
                    path, [10, 20, 30], {10}
                )
                after_lines = path.read_text(encoding="utf-8").splitlines(
                    keepends=True
                )
                self.assertEqual(changed, 1)
                self.assertIn(",Sharks,", after_lines[1])
                self.assertEqual(before_lines[2:], after_lines[2:])
        finally:
            NORMALIZATION.EXPECTED_INCLUDED_ROWS = original_rows
            NORMALIZATION.EXPECTED_INCLUDED_SHARKS_CHANGES = original_changes


if __name__ == "__main__":
    unittest.main()
