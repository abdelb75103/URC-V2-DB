from __future__ import annotations

import inspect
import unittest

from pipeline.__main__ import export_team_dashboard_parity_json


class ExportTeamDashboardParityTests(unittest.TestCase):
    """The 16 committed per-team files must track the served bundle.

    release-league rewrites only the league export, so without this the
    per-team parity exports keep the numbers of whichever release last wrote
    them while the website serves the current approved bundle.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.source = inspect.getsource(export_team_dashboard_parity_json)

    def test_exports_come_from_the_approved_bundle(self) -> None:
        self.assertIn("current_league_bundle_snapshot(season)", self.source)
        # Not the frozen per-team _v1 release path, which would write old numbers.
        self.assertNotIn("export_release_dashboard_json", self.source)

    def test_writes_the_committed_per_team_paths(self) -> None:
        self.assertIn('f"{team_key}_dashboard_{season}.json"', self.source)
        self.assertIn('Path("content") / "reporting"', self.source)
        self.assertIn("write_json_atomic(path, dashboard)", self.source)

    def test_rejects_an_incomplete_payload_instead_of_writing_it(self) -> None:
        self.assertIn("approved bundle contains an incomplete team payload", self.source)

    def test_records_the_release_identity_it_exported(self) -> None:
        self.assertIn("**metadata", self.source)
        self.assertIn('"team_parity_exported"', self.source)


if __name__ == "__main__":
    unittest.main()
