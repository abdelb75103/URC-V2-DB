from __future__ import annotations

import inspect
import hashlib
import unittest
from pathlib import Path
from types import SimpleNamespace

from pipeline.__main__ import decimal_values_close, integer_values_equal, release_league


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260720170000_season_bound_reporting_v3.sql"
FROZEN_V2 = ROOT / "supabase/migrations/20260714130000_league_dashboard_v2.sql"
EVIDENCE = ROOT / "docs/evidence/season_bound_reporting_2024-25.json"


class SeasonBoundReportingV3ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text()
        cls.source = inspect.getsource(release_league)

    def test_parameterised_season_bound_cohort_includes_undated_and_excludes_months(self) -> None:
        self.assertIn("create table analysis.reporting_season_windows_v3", self.sql)
        self.assertIn("date '2024-07-01'", self.sql)
        self.assertIn("date '2025-06-30'", self.sql)
        self.assertIn("i.date_injured is null or i.date_injured between", self.sql)
        self.assertIn("where date_injured is not null", self.sql)
        self.assertIn("italian elite championship", self.sql)
        self.assertNotIn("coverage_start", self.sql.split("create view analysis.injury_cohort_by_build_season_bound_v3", 1)[1].split("create view analysis.exposure_hours", 1)[0])

    def test_v3_uses_bounded_curated_exposure_and_registered_fixtures(self) -> None:
        exposure = self.sql.split("create view analysis.exposure_hours_by_build_season_bound_v3", 1)[1].split("create view analysis.season_bound_team_summary_v3", 1)[0]
        self.assertIn("curated.exposure", exposure)
        self.assertIn("curated.fixtures", exposure)
        self.assertIn("coalesce(sum(e.minutes_clean), 0) / 60 as total_hours", exposure)
        self.assertIn("* 20.0", exposure)

    def test_only_accepted_ia_acl_classification_is_promoted(self) -> None:
        classification = self.sql.split("create view analysis.season_bound_reporting_classification_v3", 1)[1].split("create view analysis.season_bound_diagnosis_profiles_v3", 1)[0]
        self.assertIn("analysis.accepted_reporting_classification_rules_v3", classification)
        self.assertIn("Unknown diagnosis", classification)
        self.assertNotIn("dashboard_v3_preview", self.sql)

    def test_immutable_evidence_and_v4_candidate_binding_exist(self) -> None:
        self.assertIn("reporting_cohort_rule_adjudications_v3_immutable", self.sql)
        self.assertIn("cohort_evidence_sha256", self.sql)
        self.assertIn("docs/evidence/season_bound_reporting_2024-25.json", self.sql)
        self.assertIn("- 'injury_cohort_filters'", self.sql)
        self.assertIn(hashlib.sha256(EVIDENCE.read_bytes()).hexdigest(), self.sql)
        self.assertIn("create view analysis.team_dashboard_release_candidates_v4", self.sql)
        self.assertIn("create view analysis.league_dashboard_release_candidates_v4", self.sql)
        self.assertIn("candidate.cohort_view_version=context.cohort_view_version", self.sql)
        self.assertIn("candidate.analysis_version=context.analysis_version", self.sql)
        self.assertIn("league_release_context_v2_decision_recorded_at_check", self.sql)

    def test_release_cli_gates_v3_and_preserves_v2_paths(self) -> None:
        self.assertIn("supported_release_variants", self.source)
        self.assertIn("SEASON_BOUND_REPORTING_MIGRATION_VERSION", self.source)
        self.assertIn("analysis.league_dashboard_release_candidates_v4", self.source)
        self.assertIn("cohort_adjudications", self.source)
        self.assertIn("league_dashboard_release_v3", self.source)
        self.assertIn("SEASON_BOUND_LEAGUE_DASHBOARD_RELEASE_RULE_VERSION", self.source)
        self.assertIn("season-bound cohort, headline, or monthly reconciliation failed", self.source)
        self.assertIn("season-bound team payload retained stale V2 cohort filters", self.source)
        self.assertIn("(\"v2\", \"v2\", \"v2\")", self.source)
        self.assertIn("(\"v3\", \"reporting_classification_2026-07-20_v1\", \"season_bound_2026-07-20_v1\")", self.source)

    def test_exposure_reconciliation_tolerates_only_sub_nanohour_rounding(self) -> None:
        self.assertTrue(decimal_values_close("76784.9492188000000000", "76784.9492188000000001"))
        self.assertFalse(decimal_values_close("76784.9492188000", "76784.9492188100"))

    def test_count_reconciliation_accepts_postgres_bigint_strings(self) -> None:
        self.assertTrue(integer_values_equal(2160, "2160"))
        self.assertFalse(integer_values_equal(2160, "2161"))

    def test_release_cli_rejects_an_unbound_v3_tuple_before_database_access(self) -> None:
        with self.assertRaisesRegex(SystemExit, "V3 requires accepted IA-02/ACL-01"):
            release_league(SimpleNamespace(
                season="2024-25", snapshot_current=False, preflight=True,
                preflight_file="", preflight_reviewer="", previous_bundle_file="",
                analysis_version="v3", classification_view_version="v2",
                cohort_view_version="season_bound_2026-07-20_v1",
            ))

    def test_frozen_v2_migration_was_not_modified(self) -> None:
        self.assertIn("create view analysis.injury_cohort_by_build_v2", FROZEN_V2.read_text())
        self.assertNotIn("season_bound", FROZEN_V2.read_text())


if __name__ == "__main__":
    unittest.main()
