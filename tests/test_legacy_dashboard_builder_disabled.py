from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]

class LegacyDashboardBuilderDisabledTests(unittest.TestCase):
    def test_both_legacy_cli_routes_refuse_before_reading_local_files(self) -> None:
        for command in ("build-team-dashboard", "build-munster-dashboard"):
            with self.subTest(command=command):
                result = subprocess.run(
                    [sys.executable, "-m", "pipeline", command],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("local CSV dashboard command is retired", result.stderr)


if __name__ == "__main__":
    unittest.main()
