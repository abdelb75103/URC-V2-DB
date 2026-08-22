from __future__ import annotations

import hashlib
import json
from pathlib import Path
import unittest

import pipeline.__main__ as pipeline
from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT
    / "supabase/migrations"
    / "20260822030000_urc_2025_26_injury_eligibility_bridge.sql"
)
EVIDENCE = ROOT / "docs/evidence/urc_2025_26_injury_eligibility_bridge.json"
REGISTRATION = (ROOT / "tools/sql/register_urc_2025_26_v6_migrations.sql").read_text(
    encoding="utf-8"
)


class Year2InjuryEligibilityReportingV6Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lowered = cls.sql.lower()

    def test_additive_year2_bridge_seeds_audited_reason_codes(self) -> None:
        self.assertIn("season_attributed_undated_injury", self.lowered)
        self.assertIn("explicit_source_exclusion", self.lowered)
        self.assertIn("on conflict (code) do update", self.lowered)

    def test_only_checksum_bound_season_attributed_undated_rows_enter_v6_cohort(self) -> None:
        self.assertIn("create or replace view analysis.analysis_window_injury_cohort_v6", self.lowered)
        self.assertIn("processing.record_versions", self.lowered)
        self.assertIn("record_state ->> 'injury_date_basis' = 'season_attributed_undated'", self.lowered)
        self.assertIn("rv.eligibility_status = 'included_pending_protocol'", self.lowered)
        self.assertIn("classification.date_injured is not null", self.lowered)

    def test_year1_relations_and_readers_are_untouched(self) -> None:
        self.assertNotIn("analysis_window_2024", self.lowered)
        self.assertNotIn("create or replace view reporting.", self.lowered)
        self.assertNotIn("latest_team_dashboard_v5", self.lowered)
        self.assertNotIn("latest_league_dashboard_v5", self.lowered)

    def test_release_contract_and_registration_bind_the_same_bridge_evidence(self) -> None:
        evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        migration_contract = next(
            item
            for item in YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts
            if item.version == "20260822030000"
        )
        evidence_sha256 = hashlib.sha256(EVIDENCE.read_bytes()).hexdigest()

        self.assertEqual(
            evidence_sha256,
            YEAR2_2025_26_RELEASE_CONTRACT.injury_eligibility_evidence_sha256,
        )
        self.assertEqual(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), migration_contract.sha256)
        self.assertIn(evidence_sha256, self.sql)
        self.assertEqual(REGISTRATION.count(migration_contract.statement), 2)

    def test_release_preflight_hashes_bridge_evidence_before_live_registration(self) -> None:
        records = pipeline.year2_release_local_evidence_records(
            YEAR2_2025_26_RELEASE_CONTRACT
        )
        self.assertIn(
            {
                "role": "injury_eligibility_bridge",
                "locator": "docs/evidence/urc_2025_26_injury_eligibility_bridge.json",
                "sha256": YEAR2_2025_26_RELEASE_CONTRACT.injury_eligibility_evidence_sha256,
            },
            records,
        )


if __name__ == "__main__":
    unittest.main()
