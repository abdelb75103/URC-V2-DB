from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT
    / "supabase/migrations/"
    "20260726120000_analysis_window_v5_coverage_payload_snapshots.sql"
)
REFRESH = ROOT / "tools/sql/refresh_analysis_window_v5_candidate_snapshots.sql"


class AnalysisWindowV5CoverageSnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.refresh = REFRESH.read_text(encoding="utf-8")

    def test_coverage_reads_the_shared_effective_cohort_once(self) -> None:
        self.assertIn(
            "analysis.analysis_window_effective_exposure_cohort_v5_snapshot",
            self.sql,
        )
        self.assertIn(
            "effective_eligibility_status = 'included_pending_protocol'",
            self.sql,
        )
        self.assertIn("join analysis.league_member_releases_v2 member", self.sql)
        self.assertIn("join curated.exposure source", self.sql)

    def test_every_cohort_derived_coverage_field_is_replaced(self) -> None:
        for field in (
            "exposure_rows",
            "exposed_players",
            "weeks",
            "exposure_periods",
            "exposure_grain",
            "hours",
            "distance_km",
            "scope_status_counts",
            "coverage_windows",
            "analysis_window_start",
            "analysis_window_end",
        ):
            self.assertIn(f"'{field}'", self.sql)

    def test_non_coverage_sections_are_asserted_unchanged(self) -> None:
        self.assertGreaterEqual(
            self.sql.count("dashboard - 'coverage'"), 4
        )
        self.assertIn(
            "V5 coverage correction changed a non-coverage payload section",
            self.sql,
        )

    def test_coverage_hours_match_both_headline_rate_denominators(self) -> None:
        for source in (self.sql, self.refresh):
            self.assertGreaterEqual(
                source.count("headline ->> 'key' = 'incidence_per_1000h'"),
                2,
            )
            self.assertGreaterEqual(
                source.count("headline ->> 'key' = 'burden_per_1000h'"),
                2,
            )
            self.assertIn(
                "V5 coverage hours do not match the headline denominators",
                source,
            )

    def test_corrected_candidates_remain_direct_and_build_pinned(self) -> None:
        self.assertIn(
            "team_dashboard_payload_analysis_window_v5_coverage_snapshot",
            self.sql,
        )
        self.assertIn(
            "league_dashboard_payload_analysis_window_v5_coverage_snapshot",
            self.sql,
        )
        self.assertIn(
            "create or replace view\n"
            "  analysis.team_dashboard_release_candidates_analysis_window_v5",
            self.sql,
        )
        self.assertIn(
            "create or replace view\n"
            "  analysis.league_dashboard_release_candidates_analysis_window_v5",
            self.sql,
        )
        self.assertIn(
            "'analysis_window_2024-25_2026-07-25_v1'",
            self.sql,
        )
        self.assertIn(
            "'reporting_classification_2026-07-22_v2'",
            self.sql,
        )

    def test_production_logic_has_no_reconciliation_target_constants(self) -> None:
        for value in ("64511", "81352.919497", "75312.919497", "865.830"):
            self.assertNotIn(value, self.sql)

    def test_repeatable_refresh_rebuilds_corrected_coverage_last(self) -> None:
        ordered = (
            "analysis.analysis_window_effective_exposure_cohort_v5_snapshot",
            "analysis.team_dashboard_payload_analysis_window_v5_snapshot",
            "analysis.league_dashboard_payload_analysis_window_v5_snapshot",
            "analysis.analysis_window_team_coverage_v5_snapshot",
            "analysis.analysis_window_league_coverage_v5_snapshot",
            "analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot",
            "analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot",
        )
        positions = [self.refresh.index(name) for name in ordered]
        self.assertEqual(sorted(positions), positions)
        self.assertIn(
            "V5 coverage refresh changed a non-coverage payload section",
            self.refresh,
        )


if __name__ == "__main__":
    unittest.main()
