from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/apply_unknown_injury_inference_rules.py"
SPEC = importlib.util.spec_from_file_location("unknown_inference", SCRIPT)
assert SPEC and SPEC.loader
RULES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RULES)


def row(source_row: int) -> dict[str, str]:
    return {
        "Team": "Team", "PlayerID": f"P{source_row}",
        "Problem type": "Injury", "Confirmed Return Date": "",
        "Days Injured": "", "TimeLoss vs Medical Attention": "Unknown",
    }


class UnknownInjuryInferenceTests(unittest.TestCase):
    def fixture(self):
        required = sorted(
            RULES.SURGERY_ROWS
            | RULES.POSITIVE_GAMES_MISSED_ROWS
            | {470, 1735}
        )
        sources = required + list(range(3000, 3000 + 58 - len(required)))
        rows = [row(source) for source in sources]
        master = [
            {
                "Team": "", "PlayerID": "", "Date Injured": "",
                "Fit For Selection Date": "", "Games Missed": "",
                "Required Surgery": "",
            }
            for _ in range(max(sources) - 1)
        ]
        for source, current in zip(sources, rows, strict=True):
            master[source - 2].update(
                {"Team": current["Team"], "PlayerID": current["PlayerID"]}
            )
        master[470 - 2].update(
            {"Date Injured": "25/01/2025", "Fit For Selection Date": "10/02/25q"}
        )
        master[1735 - 2].update(
            {"Date Injured": "26/07/2024", "Fit For Selection Date": "20/07/2024"}
        )
        master[209 - 2]["Games Missed"] = "1"
        for source in RULES.SURGERY_ROWS:
            master[source - 2]["Required Surgery"] = "Yes"
        return rows, sources, master

    def test_applies_accepted_rules_only(self) -> None:
        rows, sources, master = self.fixture()
        transformed, audit, qa = RULES.transform_dataset(rows, sources, master)
        indexed = dict(zip(sources, transformed, strict=True))
        self.assertEqual(indexed[470]["Confirmed Return Date"], "10/02/2025")
        self.assertEqual(indexed[470]["Days Injured"], "16")
        self.assertEqual(indexed[470]["TimeLoss vs Medical Attention"], "Time Loss")
        self.assertEqual(indexed[209]["TimeLoss vs Medical Attention"], "Time Loss")
        for source in RULES.SURGERY_ROWS:
            self.assertEqual(
                indexed[source]["TimeLoss vs Medical Attention"], "Time Loss"
            )
            self.assertEqual(indexed[source]["Days Injured"], "")
        self.assertEqual(
            indexed[1735]["TimeLoss vs Medical Attention"], "Unknown"
        )
        self.assertEqual(len(audit), 15)
        self.assertEqual(qa["unknown_injuries_after"], 45)

    def test_rejects_missing_surgery_evidence(self) -> None:
        rows, sources, master = self.fixture()
        master[185 - 2]["Required Surgery"] = "No"
        with self.assertRaisesRegex(ValueError, "Surgery evidence absent"):
            RULES.transform_dataset(rows, sources, master)


if __name__ == "__main__":
    unittest.main()
