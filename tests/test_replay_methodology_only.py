import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPLAY = ROOT / "tools" / "replay.py"


class ReplayMethodologyOnlyTests(unittest.TestCase):
    def test_methodology_only_writes_no_inclusion_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            ledger_path = temporary_path / "ledger.json"
            methodology_path = temporary_path / "METHODOLOGY.md"
            inclusion_path = temporary_path / "included.csv"
            manifest_path = temporary_path / "manifest.json"
            ledger_path.write_text(
                json.dumps({"steps": [], "open_items": []}), encoding="utf-8"
            )
            inclusion_path.write_text("sentinel inclusion bytes\n", encoding="utf-8")
            manifest_path.write_text("sentinel manifest bytes\n", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPLAY),
                    "--write-methodology-only",
                    "--ledger",
                    str(ledger_path),
                    "--methodology",
                    str(methodology_path),
                    "--output",
                    str(inclusion_path),
                    "--manifest",
                    str(manifest_path),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(inclusion_path.read_text(encoding="utf-8"), "sentinel inclusion bytes\n")
            self.assertEqual(manifest_path.read_text(encoding="utf-8"), "sentinel manifest bytes\n")
            methodology = methodology_path.read_text(encoding="utf-8")
            self.assertIn("Reporting cohort boundary: v5", methodology)
            self.assertIn("1 September 2024 to 30 June 2025", methodology)
            self.assertIn("Six undated, season-attributed injuries", methodology)
            self.assertIn("--write-methodology-only", methodology)


if __name__ == "__main__":
    unittest.main()
