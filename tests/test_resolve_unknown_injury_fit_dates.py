from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/resolve_unknown_injury_fit_dates.py"
SPEC = importlib.util.spec_from_file_location("unknown_fit_resolution", SCRIPT)
assert SPEC and SPEC.loader
RESOLUTION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RESOLUTION)


HEADERS = [
    "Team",
    "PlayerID",
    "Problem type",
    "Date Injured",
    "Fit For Selection Date",
    "Confirmed Return Date",
    "Days Injured",
    "TimeLoss vs Medical Attention",
]


def row(source_row: int) -> dict[str, str]:
    return {
        "Team": "Dragons",
        "PlayerID": f"Ath_{source_row}",
        "Problem type": "Injury",
        "Date Injured": "01/01/2025",
        "Fit For Selection Date": "",
        "Confirmed Return Date": "",
        "Days Injured": "",
        "TimeLoss vs Medical Attention": "Unknown",
    }


class ResolveUnknownInjuryFitDatesTests(unittest.TestCase):
    def fixture(self):
        source_rows = list(range(1000, 1055)) + [210, 359, 470, 505, 1735]
        rows = [row(source_row) for source_row in source_rows]
        source_master = [dict.fromkeys(HEADERS, "") for _ in range(1734)]
        indexed = {source_row: index for index, source_row in enumerate(source_rows)}
        values = {
            210: ("Cardiff", "Ath_210", "", "10/02/25"),
            359: ("Dragons", "Ath_359", "18/07/2024", "19/08/2025"),
            470: ("Dragons", "Ath_470", "25/01/2025", "10/02/25q"),
            505: ("Dragons", "Ath_505", "04/04/2025", "04/04/2025"),
            1735: ("Ospreys", "Ath_1735", "26/07/2024", "20/07/2024"),
        }
        for source_row, (team, player, injured, fit) in values.items():
            rows[indexed[source_row]].update(
                {
                    "Team": team,
                    "PlayerID": player,
                    "Date Injured": injured,
                    "Fit For Selection Date": fit,
                }
            )
            source_master[source_row - 2].update(
                {
                    "Team": team,
                    "PlayerID": player,
                    "Date Injured": injured,
                    "Fit For Selection Date": fit,
                }
            )
        return rows, source_rows, source_master

    def test_applies_only_defensible_fit_date_changes(self) -> None:
        rows, source_rows, source_master = self.fixture()
        transformed, audit, qa = RESOLUTION.transform_dataset(
            rows, source_rows, source_master
        )
        indexed = dict(zip(source_rows, transformed, strict=True))

        self.assertEqual(indexed[210]["Confirmed Return Date"], "10/02/2025")
        self.assertEqual(indexed[210]["Days Injured"], "")
        self.assertEqual(indexed[210]["TimeLoss vs Medical Attention"], "Unknown")
        self.assertEqual(indexed[359]["Confirmed Return Date"], "19/08/2025")
        self.assertEqual(indexed[359]["Days Injured"], "397")
        self.assertEqual(indexed[359]["TimeLoss vs Medical Attention"], "Time Loss")
        self.assertEqual(indexed[505]["Confirmed Return Date"], "04/04/2025")
        self.assertEqual(indexed[505]["Days Injured"], "0")
        self.assertEqual(
            indexed[505]["TimeLoss vs Medical Attention"], "Medical Attention"
        )
        self.assertEqual(indexed[470], rows[source_rows.index(470)])
        self.assertEqual(indexed[1735], rows[source_rows.index(1735)])
        self.assertEqual(len(audit), 7)
        self.assertEqual(qa["unknown_injuries_after"], 58)

    def test_rejects_source_binding_drift(self) -> None:
        rows, source_rows, source_master = self.fixture()
        source_master[359 - 2]["PlayerID"] = "Different"
        with self.assertRaisesRegex(ValueError, "Source binding mismatch"):
            RESOLUTION.transform_dataset(rows, source_rows, source_master)


if __name__ == "__main__":
    unittest.main()
