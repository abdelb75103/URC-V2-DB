from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/remove_nonrugby_gym_injury_rows.py"
SPEC = importlib.util.spec_from_file_location("remove_nonrugby_gym", SCRIPT)
assert SPEC and SPEC.loader
REMOVAL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REMOVAL)


def row(problem_type: str, occasion: str, team: str = "Leinster") -> dict[str, str]:
    return {
        "Problem type": problem_type, "Occasion category": occasion, "Team": team,
        "PlayerID": "Athlete_1", "TimeLoss vs Medical Attention": "Unknown",
    }


class RemoveNonRugbyGymRowsTests(unittest.TestCase):
    def test_exact_match_requires_injury_and_exact_occasion(self) -> None:
        rows = [row("Injury", "Training", team="Other") for _ in range(REMOVAL.EXPECTED_INPUT_ROWS)]
        sources = list(range(2, REMOVAL.EXPECTED_INPUT_ROWS + 2))
        target_index = 0
        for team, count in REMOVAL.EXPECTED_REMOVALS_BY_TEAM.items():
            for _ in range(count):
                rows[target_index] = row("Injury", "Non-Rugby", team)
                target_index += 1
        for index in range(27):
            rows[index]["Occasion category"] = "Gym-Based"
        rows[-2] = row("Illness", "Non-Rugby", "Other")
        rows[-1] = row("Other", "Gym-Based", "Other")
        retained, audit, qa = REMOVAL.transform_dataset(rows, sources)
        self.assertEqual(len(audit), 120)
        self.assertEqual(len(retained), 2301)
        self.assertEqual(qa["illness_rows_matching_target_occasions_retained"], 1)
        self.assertEqual(qa["other_rows_matching_target_occasions_retained"], 1)

    def test_mapping_hash_is_order_sensitive(self) -> None:
        self.assertNotEqual(REMOVAL.source_row_mapping_sha256([1, 2]), REMOVAL.source_row_mapping_sha256([2, 1]))

    def test_selection_rule_has_all_three_stages(self) -> None:
        self.assertIn("Exclusion Reason", REMOVAL.SELECTION_RULE)
        self.assertIn("adjudicated source rows", REMOVAL.SELECTION_RULE)
        self.assertIn("Problem type is exactly 'Injury'", REMOVAL.SELECTION_RULE)


if __name__ == "__main__":
    unittest.main()
