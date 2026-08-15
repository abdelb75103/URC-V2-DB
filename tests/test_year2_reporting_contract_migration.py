from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260815010000_urc_2025_26_reporting_contract.sql"


class Year2ReportingContractMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_declares_only_the_explicit_year2_window_and_release_tuple(self) -> None:
        self.assertIn("analysis_window_2025-26_2026-08-15_v1", self.sql)
        self.assertIn("'2025-26'", self.sql)
        self.assertIn("date '2025-09-01'", self.sql)
        self.assertIn("date '2026-06-30'", self.sql)
        self.assertIn("'v6'", self.sql)
        self.assertIn("'reporting_classification_2026-07-22_v2'", self.sql)
        self.assertNotIn("create or replace view analysis.analysis_window_injury_cohort_v5", self.sql)

    def test_contract_is_immutable_and_blocks_promotion_without_v6_candidates(self) -> None:
        self.assertIn("create table analysis.accepted_release_contracts_v1", self.sql)
        self.assertIn("analysis.reject_accepted_release_contract_mutation", self.sql)
        self.assertIn("accepted_release_contracts_v1_immutable", self.sql)
        self.assertIn("analysis.release_contract_candidates_available_v1", self.sql)
        self.assertIn("analysis.team_dashboard_release_candidates_analysis_window_v6", self.sql)
        self.assertIn("analysis.league_dashboard_release_candidates_analysis_window_v6", self.sql)
        self.assertIn("analysis.analysis_window_injury_cohort_v6", self.sql)
        self.assertIn("analysis.analysis_window_league_monthly_v6", self.sql)
        self.assertIn("analysis.analysis_window_league_summary_v6", self.sql)
        self.assertIn("to_regclass", self.sql)

    def test_fixture_provenance_keeps_each_official_match_link_auditable(self) -> None:
        self.assertIn("create table curated.fixture_provenance_v1", self.sql)
        for column in (
            "upstream_match_id",
            "source_locator",
            "source_request_sha256",
            "source_response_sha256",
            "retrieved_at",
        ):
            self.assertIn(column, self.sql)
        self.assertIn("unique (season, upstream_match_id)", self.sql)
        self.assertIn("references curated.fixtures (season, source_row_number)", self.sql)
        self.assertIn("fixture_provenance_v1_immutable", self.sql)

    def test_private_contract_and_provenance_tables_are_rls_protected(self) -> None:
        self.assertIn("alter table analysis.accepted_release_contracts_v1 enable row level security", self.sql)
        self.assertIn("alter table curated.fixture_provenance_v1 enable row level security", self.sql)
        self.assertIn("from public, anon, authenticated, web_reader", self.sql)

    def test_web_reader_gets_only_a_boolean_target_attestation(self) -> None:
        self.assertIn("create view reporting.approved_dashboard_reader_target_v1", self.sql)
        self.assertIn("security_invoker = false, security_barrier = true", self.sql)
        self.assertIn("as target_attested", self.sql)
        self.assertIn("grant select on reporting.approved_dashboard_reader_target_v1 to web_reader", self.sql)
        self.assertIn("revoke all on reporting.approved_dashboard_reader_target_v1", self.sql)


if __name__ == "__main__":
    unittest.main()
