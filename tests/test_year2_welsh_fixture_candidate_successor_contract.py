from __future__ import annotations

import hashlib
import inspect
from pathlib import Path
import unittest

import pipeline.__main__ as pipeline
from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
VERSION = "20260831121000"
NAME = "urc_2025_26_welsh_fixture_candidate_successor"
MIGRATION = ROOT / "supabase/migrations" / f"{VERSION}_{NAME}.sql"
REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_welsh_fixture_candidate_successor_migration.sql"
)


class Year2WelshFixtureCandidateSuccessorContractTests(unittest.TestCase):
    def test_only_cardiff_and_dragons_dashboard_bytes_change(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        self.assertIn("changed_teams <> array['cardiff', 'dragons']", sql)
        self.assertIn("team_key not in ('cardiff', 'dragons')", sql)
        self.assertIn("candidate.dashboard <> predecessor.dashboard", sql)
        self.assertIn("then material.dashboard else predecessor.dashboard", sql)
        self.assertNotIn("interval '1 day'", sql)
        self.assertNotIn("2024-25'::text as season", sql)

    def test_candidate_pins_reviewed_counts_rates_and_evidence(self) -> None:
        sql = MIGRATION.read_text(encoding="utf-8").lower()

        for token in (
            "injury_lineage_2025-26_2026-08-31_v3",
            "e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450",
            ") <> 1545",
            ") <> 938",
            ") <> 782",
            ") <> 20665",
            "candidate.team_key = 'cardiff'",
            "analysis.rate_per_1000_v1(19, 380)",
            "candidate.team_key = 'dragons'",
            "analysis.rate_per_1000_v1(42, 360)",
            "accepted_release_contracts_v3",
            "enable row level security",
        ):
            self.assertIn(token, sql)

    def test_registration_and_release_contract_bind_exact_bytes(self) -> None:
        migration_bytes = MIGRATION.read_bytes()
        sha256 = hashlib.sha256(migration_bytes).hexdigest()
        registration = REGISTRATION.read_text(encoding="utf-8")

        self.assertEqual(registration.count(f"migration_sha256={sha256}"), 2)
        contract = next(
            item
            for item in YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts
            if item.version == VERSION
        )
        self.assertEqual(contract.name, NAME)
        self.assertEqual(contract.sha256, sha256)
        for statement in contract.registration_statements:
            self.assertEqual(registration.count(statement), 2)

    def test_league_provenance_uses_corrected_totals_and_monthly_gap(self) -> None:
        source = inspect.getsource(pipeline.release_league)

        self.assertIn('"recorded_injuries": 1545', source)
        self.assertIn('"time_loss_injuries": 938', source)
        self.assertIn("year2_release_contract.cohort_migration_version", source)
        self.assertIn("and year2_release_contract is not None", source)
        self.assertEqual(
            YEAR2_2025_26_RELEASE_CONTRACT.cohort_migration_version,
            "20260831120000",
        )


if __name__ == "__main__":
    unittest.main()
