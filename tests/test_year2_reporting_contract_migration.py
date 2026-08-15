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
        self.assertIn("analysis.league_team_dashboard_release_candidates_analysis_window_v6", self.sql)
        self.assertIn("analysis.league_dashboard_release_candidates_analysis_window_v6", self.sql)
        self.assertIn("analysis.analysis_window_injury_cohort_v6", self.sql)
        self.assertIn("analysis.analysis_window_league_monthly_v6", self.sql)
        self.assertIn("analysis.analysis_window_league_summary_v6", self.sql)
        self.assertIn("to_regclass", self.sql)

    def test_contract_distinguishes_build_candidates_from_immutable_league_team_bytes(self) -> None:
        self.assertIn("league_team_candidate_relation", self.sql)
        self.assertIn(
            "analysis.league_team_dashboard_release_candidates_analysis_window_v6",
            self.sql,
        )

    def test_fixture_provenance_keeps_each_official_match_link_auditable(self) -> None:
        self.assertIn("create table curated.fixture_provenance_v1", self.sql)
        for column in (
            "upstream_match_id",
            "source_locator",
            "prepared_file_sha256",
            "source_request_sha256",
            "upstream_response_sha256",
            "retrieved_at",
        ):
            self.assertIn(column, self.sql)
        self.assertIn("unique (season, upstream_match_id)", self.sql)
        self.assertIn("references curated.fixtures (season, source_row_number)", self.sql)
        self.assertNotIn("check (source_file_sha256 = source_response_sha256)", self.sql)
        self.assertIn("fixture_provenance_v1_immutable", self.sql)
        self.assertIn("curated_fixtures_2025_26_immutable", self.sql)
        self.assertIn("accepted 2025-26 curated fixtures are immutable", self.sql)

    def test_fixture_provenance_checksum_is_reconciled_to_the_accepted_fixture_row(self) -> None:
        pipeline_source = (ROOT / "pipeline/__main__.py").read_text(encoding="utf-8")
        self.assertIn("fixture provenance is not bound to the accepted curated fixture bytes", pipeline_source)
        self.assertIn("fixture.source_file_sha256 is distinct from expected.prepared_file_sha256", pipeline_source)
        self.assertIn("expected_curated_fixtures", pipeline_source)
        for field in (
            "actual.stage is distinct from expected.stage",
            "actual.round is distinct from expected.round",
            "actual.match_date is distinct from expected.match_date",
            "actual.date_status is distinct from expected.date_status",
            "actual.home_team_key is distinct from expected.home_team_key",
            "actual.away_team_key is distinct from expected.away_team_key",
        ):
            self.assertIn(field, pipeline_source)

    def test_fixture_preparation_evidence_is_immutable_and_exact(self) -> None:
        for token in (
            "create table analysis.fixture_preparation_evidence_v1",
            "docs/evidence/urc_2025_26_fixture_preparation.json",
            "7b9a79ae5aeb3d8895d31e2c8d48ac0a555b40d772739b7949acac57f3a6d7ff",
            "57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af",
            "411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6",
            "071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b",
            "2026-08-15t01:09:13z",
            "fixture_preparation_evidence_v1_immutable",
        ):
            self.assertIn(token, self.sql)

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

    def test_attestation_binds_the_exact_frozen_v2_base_and_additive_correction(self) -> None:
        """Year 2 must not weaken the hosted target proof to a moving release."""
        for token in (
            "76ac684a-dc60-4b12-ab78-0a502d284555",
            "urc-2024-25-v5-4ae722941285-a1",
            "2f4bb3cbe77e1ea1608cf8442419c2d6e11333473ce73d10559532061382fa53",
            "urc-2024-25-correction-r1122-20260729-a1",
        ):
            self.assertIn(token, self.sql)


if __name__ == "__main__":
    unittest.main()
