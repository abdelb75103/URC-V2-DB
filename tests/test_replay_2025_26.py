from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "year2_replay", ROOT / "tools/replay_2025_26.py"
)
assert SPEC and SPEC.loader
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
HEADERS = [
    "Team", "PlayerID", "Received At Club", "Received/Injured In Team",
    "Problem type", "Date Injured", "Fit For Selection Date",
    "Confirmed Return Date", "Days Injured", "Occasion category",
    "Body Part", "Orchard Code", "Illness Code", "Description",
    "Injury Tissue Type/s", "Side", "Nature of onset", "Recurrence",
    "Is Contact", "Mechanism of Injury", "Mechanism Notes",
    "Injury Surface Type", "Match Type", "Received At Position",
    "Required Surgery", "TimeLoss vs Medical Attention", "Diagnosis",
    "Exclusion Reason",
]


class Year2ReplayTests(unittest.TestCase):
    def payload(self) -> dict:
        return {
            "format": "urc-master-workbook",
            "sheets": [{
                "name": "Injury Master",
                "values": [HEADERS, ["Fixture Club", "PLY_FIXTURE"] + [""] * 26],
            }],
        }

    def ledger(self, master: Path) -> dict:
        return {
            "season": "2025-26",
            "reporting_window": R.WINDOW,
            "baseline": {"master": {"sha256": hashlib.sha256(master.read_bytes()).hexdigest()}},
            "steps": [],
        }

    def test_replays_deterministically_and_generates_methodology(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            master = root / "master.json"
            master.write_text(json.dumps(self.payload()))
            ledger = root / "ledger.json"
            ledger.write_text(json.dumps(self.ledger(master)))
            output = root / "included.csv"
            manifest = root / "manifest.json"
            methodology = root / "method.md"

            result = R.replay(master, ledger, output, manifest, methodology)

            self.assertEqual(result["season"], "2025-26")
            self.assertEqual(result["columns"], 28)
            self.assertIn("September 2025", methodology.read_text())

    def test_rejects_year1_evidence_without_writing_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            master = root / "master.json"
            master.write_text(json.dumps(self.payload()))
            ledger = self.ledger(master)
            ledger["steps"] = [{
                "season": "2025-26",
                "entries": [{
                    "season": "2025-26",
                    "evidence_locator": "evidence/2024-25/example",
                }],
            }]
            ledger_path = root / "ledger.json"
            ledger_path.write_text(json.dumps(ledger))
            output = root / "included.csv"

            with self.assertRaisesRegex(R.Year2ReplayError, "evidence locator"):
                R.replay(master, ledger_path, output, root / "manifest.json", root / "method.md")

            self.assertFalse(output.exists())

    def test_applies_sep_jun_window_without_deleting_preseason_master_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = self.payload()
            date_index = HEADERS.index("Date Injured")
            preseason = ["Fixture Club", "PLY_PRE"] + [""] * 26
            preseason[date_index] = "2025-08-31"
            in_window = ["Fixture Club", "PLY_IN"] + [""] * 26
            in_window[date_index] = "2025-09-01"
            undated = ["Fixture Club", "PLY_UNKNOWN"] + [""] * 26
            payload["sheets"][0]["values"] = [HEADERS, preseason, in_window, undated]
            master = root / "master.json"
            master.write_text(json.dumps(payload))
            ledger = root / "ledger.json"
            ledger.write_text(json.dumps(self.ledger(master)))

            result = R.replay(
                master,
                ledger,
                root / "included.csv",
                root / "manifest.json",
                root / "method.md",
            )

            self.assertEqual(result["master_rows"], 3)
            self.assertEqual(result["included_rows"], 2)
            self.assertEqual(result["reporting_window_filter"], {
                "dated_in_window": 1,
                "dated_outside_window": 1,
                "undated_retained": 1,
            })


if __name__ == "__main__":
    unittest.main()
