from __future__ import annotations

from pathlib import Path
import inspect
import unittest

import pipeline.__main__ as pipeline
from pipeline.season_contracts import YEAR2_2025_26_RELEASE_TUPLE, release_contract_for


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20260815030000_urc_2025_26_team_release_v6.sql").read_text(encoding="utf-8").lower()


class Year2TeamReleaseV6ContractTests(unittest.TestCase):
    def test_team_storage_is_immutable_and_tuple_bound(self) -> None:
        for token in (
            "reporting.team_release_payloads_v6",
            "team_release_payloads_v6_immutable",
            "analysis_version = 'v6'",
            "classification_view_version = 'reporting_classification_2026-07-22_v2'",
            "cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'",
            "dashboard_payload jsonb not null",
        ):
            self.assertIn(token, SQL)

    def test_dependency_direction_is_active_build_then_accepted_member(self) -> None:
        reporting_sql = (ROOT / "supabase/migrations/20260815020000_urc_2025_26_reporting_v6.sql").read_text(encoding="utf-8").lower()
        self.assertIn("analysis.analysis_window_active_builds_v6", reporting_sql)
        self.assertNotIn("league_member_releases", reporting_sql)
        self.assertIn("analysis.league_member_releases_v6", SQL)
        self.assertIn("where release.status = 'approved'", SQL)
        self.assertIn("having count(*) = 16", SQL)

    def test_league_contract_routes_every_v6_member_read(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        self.assertIn("member_view =", source)
        self.assertEqual(source.count("{member_view}"), 3)
        self.assertEqual(release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE).member_view, "analysis.league_member_releases_v6")

    def test_first_release_pipeline_uses_v6_candidate_and_storage(self) -> None:
        source = inspect.getsource(pipeline.release_team_v6)
        for token in (
            "--preflight-file",
            "contract.team_candidate_view",
            "reporting.team_release_payloads_v6",
            "active V6 candidate changed after review",
            "status = 'approved'",
        ):
            self.assertIn(token, source)

    def test_unified_reader_is_v5_passthrough_for_year1(self) -> None:
        for token in (
            "reporting.latest_team_dashboard_v6",
            "reporting.latest_league_dashboard_v6",
            "from reporting.latest_team_dashboard_v5",
            "from reporting.latest_league_dashboard_v5",
            "reporting.approved_dashboard_reader_target_v2",
            "reporting.latest_dashboard_cache_token_v2",
        ):
            self.assertIn(token, SQL)
        reader = (ROOT / "lib/reporting.ts").read_text(encoding="utf-8")
        self.assertNotIn("latest_team_dashboard_v5", reader)
        self.assertNotIn("latest_league_dashboard_v5", reader)
        self.assertIn("latest_team_dashboard_v6", reader)
        self.assertIn("approved_dashboard_reader_target_v2", reader)


if __name__ == "__main__":
    unittest.main()
