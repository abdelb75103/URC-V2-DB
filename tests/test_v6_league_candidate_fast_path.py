from __future__ import annotations

import hashlib
from pathlib import Path
import unittest

from pipeline.season_contracts import (
    YEAR2_2025_26_RELEASE_CONTRACT,
)


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT
    / "supabase/migrations/20260823120000_urc_2025_26_v6_league_candidate_fast_path.sql"
)
SQL = MIGRATION.read_text(encoding="utf-8").lower()


class V6LeagueCandidateFastPathTests(unittest.TestCase):
    def test_contract_binds_the_exact_migration_bytes(self) -> None:
        contract = YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts[-1]

        self.assertEqual(contract.version, "20260823120000")
        self.assertEqual(contract.name, "urc_2025_26_v6_league_candidate_fast_path")
        self.assertEqual(
            hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
            contract.sha256,
        )

    def test_snapshot_seals_the_existing_candidate_before_replacing_its_view(self) -> None:
        population = SQL.index("with current_members as materialized")
        existing_candidate = SQL.index(
            "from analysis.league_dashboard_release_candidates_analysis_window_v6 candidate",
            population,
        )
        replacement = SQL.index(
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6",
            existing_candidate,
        )

        self.assertLess(population, existing_candidate)
        self.assertLess(existing_candidate, replacement)
        self.assertIn("members.member_set_sha256, candidate.dashboard", SQL)
        self.assertIn(
            "reporting.canonical_jsonb_sha256_v1(candidate.dashboard)",
            SQL,
        )

    def test_member_hash_binds_all_sixteen_release_and_build_identities(self) -> None:
        for token in (
            "'team_key', team_key",
            "'team_release_id', team_release_id::text",
            "'curated_build_id', curated_build_id::text",
            "order by team_key",
            "having count(*) = 16",
            "count(distinct team_key) = 16",
            "count(distinct team_release_id) = 16",
            "count(distinct curated_build_id) = 16",
        ):
            self.assertEqual(SQL.count(token), 2, token)

    def test_candidate_fails_closed_when_the_current_member_hash_changes(self) -> None:
        replacement = SQL.split(
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6",
            1,
        )[1]

        self.assertIn("join member_set members", replacement)
        self.assertIn("members.member_count = snapshot.member_count", replacement)
        self.assertIn("members.member_set_sha256 = snapshot.member_set_sha256", replacement)
        self.assertNotIn("union", replacement)
        self.assertNotIn("league_dashboard_payload_analysis_window_v6_enriched", replacement)

    def test_snapshot_is_private_row_locked_and_payload_hash_checked(self) -> None:
        for token in (
            "enable row level security",
            "revoke all on analysis.league_dashboard_release_candidate_snapshot_v6_20260823",
            "from public, anon, authenticated, web_reader",
            "before update or delete",
            "v6 league candidate snapshot is immutable",
            "payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)",
            "has_table_privilege(",
        ):
            self.assertIn(token, SQL)
        self.assertNotIn("grant select", SQL)

    def test_fast_path_does_not_reference_year_one(self) -> None:
        self.assertNotIn("2024-25", SQL)
        self.assertNotIn("analysis_window_2024-25", SQL)
        self.assertNotIn("latest_approved_dashboard_bundle", SQL)


if __name__ == "__main__":
    unittest.main()
