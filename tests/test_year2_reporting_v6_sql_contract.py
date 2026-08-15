from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260815020000_urc_2025_26_reporting_v6.sql"


class Year2ReportingV6SqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_creates_the_registered_v6_scientific_and_candidate_relations(self) -> None:
        for relation in (
            "analysis.analysis_window_injury_cohort_v6",
            "analysis.analysis_window_league_monthly_v6",
            "analysis.analysis_window_league_summary_v6",
            "analysis.team_dashboard_release_candidates_analysis_window_v6",
            "analysis.league_dashboard_release_candidates_analysis_window_v6",
        ):
            self.assertIn(relation, self.sql)

    def test_is_strictly_year2_and_binds_the_registered_tuple(self) -> None:
        self.assertIn("'2025-26'", self.sql)
        self.assertIn("'v6'", self.sql)
        self.assertIn("'reporting_classification_2026-07-22_v2'", self.sql)
        self.assertIn("'analysis_window_2025-26_2026-08-15_v1'", self.sql)
        self.assertIn("date '2025-09-01'", self.sql)
        self.assertIn("date '2026-06-30'", self.sql)
        self.assertNotIn("2024-25", self.sql)
        self.assertNotIn("_v5", self.sql)

    def test_undated_rows_remain_in_totals_but_not_monthly_series(self) -> None:
        cohort = self.sql.split("create view analysis.analysis_window_injury_cohort_v6", 1)[1]
        monthly = self.sql.split("create view analysis.analysis_window_monthly_v6", 1)[1]
        self.assertIn("or injury.date_injured is null", cohort)
        self.assertIn("and date_injured is not null", monthly)

    def test_release_candidates_fail_closed_without_exactly_sixteen_member_builds(self) -> None:
        self.assertIn("count(*) from analysis.league_member_releases_v2 where season='2025-26')=16", self.sql)
        self.assertIn("count(distinct team_key) from analysis.league_member_releases_v2 where season='2025-26')=16", self.sql)
        self.assertIn("analysis.league_member_releases_v2", self.sql)
        self.assertIn("curated.builds", self.sql)

    def test_display_uses_curated_categories_without_new_source_mapping(self) -> None:
        self.assertIn("coalesce(injury.body_location,'unknown')", self.sql)
        self.assertIn("coalesce(injury.injury_type,'unknown')", self.sql)
        self.assertNotIn("ingestion.source_rows", self.sql)
        self.assertNotIn("osiics", self.sql)

    def test_team_and_league_sections_are_materialised_from_curated_values(self) -> None:
        for relation in (
            "analysis_window_profiles_v6",
            "analysis_window_setting_metrics_v6",
            "analysis_window_severity_v6",
            "analysis_window_contact_distribution_v6",
            "analysis_window_league_profiles_v6",
            "analysis_window_league_setting_metrics_v6",
            "analysis_window_league_severity_v6",
            "analysis_window_league_contact_distribution_v6",
            "team_dashboard_payload_analysis_window_v6_enriched",
            "league_dashboard_payload_analysis_window_v6_enriched",
        ):
            self.assertIn(relation, self.sql)
        self.assertIn("sum(time_loss_injuries)", self.sql)
        self.assertIn("sum(days_lost)", self.sql)


if __name__ == "__main__":
    unittest.main()
