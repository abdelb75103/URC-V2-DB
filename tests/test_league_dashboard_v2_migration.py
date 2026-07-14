from __future__ import annotations

import re
import unittest
from pathlib import Path


MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "supabase/migrations/20260714130000_league_dashboard_v2.sql"
)


class LeagueDashboardV2MigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text()

    def test_is_additive_and_keeps_v1_frozen(self) -> None:
        lowered = self.sql.lower()
        self.assertNotIn("create or replace", lowered)
        self.assertNotRegex(lowered, r"drop\s+(view|table|function)")
        self.assertNotRegex(lowered, r"alter\s+view\s+analysis\.[a-z_]+_v1")
        self.assertNotRegex(lowered, r"alter\s+table\s+curated\.")

    def test_required_v2_contract_exists(self) -> None:
        for relation in (
            "analysis.setting_split_v2",
            "analysis.body_locations_v2",
            "analysis.injury_types_v2",
            "analysis.injury_profiles_v2",
            "analysis.league_headline_v2",
            "analysis.league_setting_split_v2",
            "analysis.league_body_locations_v2",
            "analysis.league_injury_types_v2",
            "analysis.league_injury_profiles_v2",
            "analysis.league_monthly_v2",
            "analysis.league_severity_distribution_v2",
            "analysis.league_coverage_v2",
            "analysis.team_dashboard_payload_v2",
            "analysis.league_dashboard_payload_v2",
            "reporting.latest_league_dashboard_v2",
            "reporting.latest_team_dashboard_v2",
        ):
            self.assertIn(f"create view {relation}", self.sql.lower())

    def test_pooled_rates_reuse_the_frozen_rate_function(self) -> None:
        self.assertGreaterEqual(self.sql.count("analysis.rate_per_1000_v1("), 20)
        self.assertNotIn("avg(incidence_per_1000h)", self.sql.lower())
        self.assertNotIn("avg(burden_per_1000h)", self.sql.lower())

    def test_unknown_setting_has_no_denominator_or_rates(self) -> None:
        setting_view = self.sql.split("create view analysis.setting_split_v2", 1)[1].split(
            "create view analysis.injury_profiles_v2", 1
        )[0]
        self.assertEqual(3, setting_view.count("else null"))
        self.assertRegex(
            setting_view,
            r"case g\.setting_code\s+when 'match' then e\.match_hours\s+when 'training' then e\.training_hours\s+else null",
        )

    def test_approved_fixture_decision_is_auditable(self) -> None:
        self.assertIn("15 players * 80 minutes / 60 = 20", self.sql)
        self.assertIn("302", self.sql)
        self.assertIn("6,040", self.sql)
        self.assertIn(
            "all_registered_season_fixtures_15_players_x_80_minutes_div_60",
            self.sql,
        )
        self.assertIn("decision_recorded_at = date '2026-07-14'", self.sql)
        self.assertIn("bool_and(e.match_hours = e.matches_played * 20.0)", self.sql)
        self.assertIn("bool_and(e.total_hours = e.match_hours + e.training_hours)", self.sql)
        self.assertGreaterEqual(self.sql.count("sum(e.matches_played) = 302"), 2)
        self.assertGreaterEqual(self.sql.count("sum(e.match_hours) = 6040.0"), 2)

    def test_public_views_are_definer_rights_barriers_and_scoped(self) -> None:
        for view in (
            "reporting.latest_league_dashboard_v2",
            "reporting.latest_team_dashboard_v2",
        ):
            pattern = rf"create view {re.escape(view)}\s+with \(security_invoker = false, security_barrier = true\)"
            self.assertRegex(self.sql.lower(), pattern)
            self.assertIn(f"grant select on {view} to web_reader;", self.sql.lower())
        self.assertIn("p.team_key,", self.sql)

    def test_dashboard_payload_shapes_match_reporting_types(self) -> None:
        for field in (
            "'setting_metrics'",
            "'body_locations'",
            "'injury_types'",
            "'injury_profiles'",
            "'dimension'",
            "'coverage_windows'",
            "'match_hours'",
            "'training_hours'",
        ):
            self.assertIn(field, self.sql)
        self.assertNotIn("as body_locations_full", self.sql)
        self.assertNotIn("as injury_types_full", self.sql)

    def test_bundle_snapshots_are_hash_verified_and_immutable(self) -> None:
        self.assertIn("create table reporting.team_dashboard_payloads_v2", self.sql.lower())
        self.assertIn("create function reporting.set_dashboard_v2_payload_hash()", self.sql)
        self.assertIn("digest(convert_to(new.dashboard_payload::text, 'UTF8'), 'sha256')", self.sql)
        self.assertEqual(2, self.sql.count("before insert on reporting."))
        self.assertEqual(2, self.sql.count("payload_sha256 text not null check"))
        self.assertEqual(4, self.sql.count("before update or delete on reporting."))
        self.assertEqual(
            4,
            self.sql.count(
                "for each row execute function reporting.reject_dashboard_v2_snapshot_mutation();"
            ),
        )
        self.assertIn("candidate.dashboard = new.dashboard_payload", self.sql)
        self.assertIn("candidate.dashboard = payload.dashboard_payload", self.sql)

    def test_public_views_only_project_whitelisted_payload_keys(self) -> None:
        public = self.sql.split("create view reporting.latest_league_dashboard_v2", 1)[1]
        self.assertNotIn("dashboard_payload as dashboard", public.lower())
        for key in (
            "analysis_window",
            "method",
            "coverage",
            "headline",
            "setting_metrics",
            "injury_profiles",
            "limitations",
        ):
            self.assertIn(f"dashboard_payload -> '{key}'", public)
        team_public = public.split("create view reporting.latest_team_dashboard_v2", 1)[1]
        self.assertIn("from reporting.latest_approved_dashboard_bundle_v2", team_public)
        self.assertIn("join reporting.team_dashboard_payloads_v2", team_public)
        self.assertNotIn("join analysis.", team_public)

    def test_member_source_is_exact_accepted_v1_roster(self) -> None:
        self.assertIn("create view analysis.accepted_team_release_candidates_v2", self.sql.lower())
        self.assertIn("rc.analysis_view_version = 'v1'", self.sql)
        self.assertIn("join reporting.teams roster", self.sql)
        self.assertGreaterEqual(self.sql.count("count(distinct rows.section)"), 2)
        self.assertGreaterEqual(self.sql.count("(select count(*) from reporting.teams) = 16"), 2)
        self.assertGreaterEqual(self.sql.count("analysis.league_member_releases_v2 current_member"), 2)
        self.assertIn("current_member.team_release_id = m.team_release_id", self.sql)
        self.assertIn("current_member.curated_build_id = m.curated_build_id", self.sql)


if __name__ == "__main__":
    unittest.main()
