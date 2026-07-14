from __future__ import annotations

import unittest
from pathlib import Path


MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "supabase/migrations/20260714230000_dashboard_v2_reader_fix.sql"
)


class DashboardV2ReaderFixMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text()
        cls.lowered = cls.sql.lower()

    def test_replaces_only_the_private_gate(self) -> None:
        self.assertIn(
            "create or replace view reporting.latest_approved_dashboard_bundle_v2",
            self.lowered,
        )
        self.assertNotIn("create or replace view reporting.latest_league_dashboard_v2", self.lowered)
        self.assertNotIn("create or replace view reporting.latest_team_dashboard_v2", self.lowered)

    def test_runtime_gate_has_no_security_invoker_analysis_dependency(self) -> None:
        self.assertNotIn("analysis.", self.lowered)
        self.assertIn("join curated.team_exposure_denominators exposure", self.lowered)
        self.assertIn("team_context.analysis_view_version = 'v1'", self.lowered)
        self.assertIn("team_release.status = 'approved'", self.lowered)
        self.assertNotIn("team_release.status = 'retired'", self.lowered)

    def test_exact_roster_snapshot_and_denominator_gates_remain(self) -> None:
        self.assertGreaterEqual(self.sql.count("= 16"), 3)
        self.assertIn("exposure.match_hours = exposure.matches_played * 20.0", self.sql)
        self.assertIn("exposure.total_hours = exposure.match_hours + exposure.training_hours", self.sql)
        self.assertIn("sum(exposure.matches_played) = 302", self.sql)
        self.assertIn("sum(exposure.match_hours) = 6040.0", self.sql)
        self.assertIn("payload.team_release_id = m.team_release_id", self.sql)
        self.assertIn("payload.curated_build_id = m.curated_build_id", self.sql)


if __name__ == "__main__":
    unittest.main()
