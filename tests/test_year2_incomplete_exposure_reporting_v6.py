from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
import unittest

import pipeline.__main__ as pipeline
from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT
    / "supabase/migrations"
    / "20260822020000_urc_2025_26_incomplete_exposure_reporting_v6.sql"
)
EVIDENCE = (
    ROOT
    / "docs/evidence/urc_2025_26_incomplete_exposure_reporting_v6.json"
)
REGISTRATION = (
    ROOT / "tools/sql/register_urc_2025_26_v6_migrations.sql"
).read_text(encoding="utf-8")


class IncompleteExposureReportingV6Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lowered = cls.sql.lower()

    def test_additive_successor_exists_for_incomplete_year2_exposure(self) -> None:
        self.assertTrue(MIGRATION.is_file())

    def test_incomplete_team_keeps_a_candidate_with_null_denominators(self) -> None:
        self.assertIn(
            "create view analysis.analysis_window_team_exposure_completeness_v6",
            self.lowered,
        )
        self.assertIn(
            "left join analysis.analysis_window_team_exposure_v6 exposure",
            self.lowered,
        )
        self.assertIn(
            "source_backed.source_backed_hours >= fixtures.match_hours",
            self.lowered,
        )
        self.assertRegex(
            self.lowered,
            r"case when source_backed\.source_backed_hours >= fixtures\.match_hours\s+then source_backed\.source_backed_hours else null::numeric end as total_hours",
        )
        self.assertRegex(
            self.lowered,
            r"case when source_backed\.source_backed_hours >= fixtures\.match_hours\s+then source_backed\.source_backed_hours - fixtures\.match_hours else null::numeric end as training_hours",
        )
        self.assertIn(
            "source_backed_denominator_unavailable_no_imputation",
            self.lowered,
        )
        self.assertIn("no imputation was applied", self.lowered)
        self.assertNotIn("where exposure.total_hours >=", self.lowered)

    def test_complete_team_keeps_actual_source_backed_values(self) -> None:
        self.assertRegex(
            self.lowered,
            r"then source_backed\.source_backed_distance_km else null::numeric end as distance_km",
        )
        self.assertIn(
            "source_backed_exposure_submitted_may_be_incomplete",
            self.lowered,
        )
        self.assertIn(
            "reported exposure values use source-backed rows only and no imputation was applied",
            self.lowered,
        )

    def test_league_and_monthly_rates_fail_closed_until_coverage_is_complete(self) -> None:
        self.assertIn("complete_team_count = 16", self.lowered)
        self.assertIn("all_team_denominators_available and source_backed_team_months = 16", self.lowered)
        self.assertRegex(
            self.lowered,
            r"case when hours\.total_hours is not null and exposure\.exposure_hours is not null\s+then analysis\.rate_per_1000_v1",
        )

    def test_v6_public_method_formula_text_remains_unchanged(self) -> None:
        self.assertNotIn(
            "exposure denominators use source-backed rows only. no exposure is imputed.",
            self.lowered,
        )

    def test_year1_reader_and_release_storage_are_not_redefined(self) -> None:
        self.assertNotIn("create or replace view reporting.", self.lowered)
        self.assertNotIn("reporting.team_release_payloads_v6", self.lowered)
        self.assertNotIn("reporting.league_release_payloads_v6", self.lowered)
        self.assertNotIn("analysis_window_2024", self.lowered)
        self.assertNotIn("latest_team_dashboard_v5", self.lowered)
        self.assertNotIn("latest_league_dashboard_v5", self.lowered)

    def test_release_contract_and_migration_bind_the_same_public_evidence_bytes(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        migration_contract = next(
            item
            for item in YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts
            if item.version == "20260822020000"
        )
        evidence_sha256 = hashlib.sha256(EVIDENCE.read_bytes()).hexdigest()

        self.assertEqual(
            evidence["schema_version"],
            "urc_2025_26_incomplete_exposure_reporting_v6_evidence_v1",
        )
        self.assertEqual(
            evidence_sha256,
            "b6fae7ce7e4609000337c29d7965e99809da3733b126522a1faabf600fdcc23c",
        )
        self.assertEqual(
            hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
            migration_contract.sha256,
        )
        self.assertIn(evidence_sha256, self.sql)
        self.assertEqual(REGISTRATION.count(migration_contract.statement), 2)

    def test_runtime_preflight_hashes_the_new_evidence_before_live_registration(self) -> None:
        records = pipeline.year2_release_local_evidence_records(
            YEAR2_2025_26_RELEASE_CONTRACT
        )
        self.assertIn(
            {
                "role": "incomplete_exposure_reporting",
                "locator": "docs/evidence/urc_2025_26_exposure_successor_v6.json",
                "sha256": "66ba0a272de96510106a68c74046d4bf59ab04570ed38d83cbb98665f51c3ce1",
            },
            records,
        )


if __name__ == "__main__":
    unittest.main()
