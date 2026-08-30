from __future__ import annotations

import hashlib
from pathlib import Path
import unittest

from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = (
    ROOT
    / "supabase/migrations/20260830150000_urc_2025_26_exposure_successor_placeholders.sql"
)
LEAGUE = (
    ROOT
    / "supabase/migrations/20260830160000_urc_2025_26_v6_exposure_successor_league_snapshot.sql"
)


class Year2ExposureSuccessorMigrationTests(unittest.TestCase):
    def test_contracts_bind_both_migration_byte_sequences(self) -> None:
        contracts = (
            *YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts,
            *YEAR2_2025_26_RELEASE_CONTRACT.league_required_migration_contracts,
        )
        by_version = {item.version: item for item in contracts}

        self.assertEqual(
            by_version["20260830150000"].sha256,
            hashlib.sha256(PLACEHOLDER.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            by_version["20260830160000"].sha256,
            hashlib.sha256(LEAGUE.read_bytes()).hexdigest(),
        )

    def test_placeholder_candidate_uses_unambiguous_build_keys(self) -> None:
        sql = PLACEHOLDER.read_text().lower()
        candidate = sql.split(
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6",
            1,
        )[1]

        self.assertNotIn("using (curated_build_id, team_key, season)", candidate)
        for predicate in (
            "completeness.curated_build_id = active.curated_build_id",
            "completeness.team_key = active.team_key",
            "completeness.season = active.season",
        ):
            self.assertIn(predicate, candidate)

    def test_placeholder_is_source_first_and_league_snapshot_is_member_bound(self) -> None:
        placeholder = PLACEHOLDER.read_text().lower()
        league = LEAGUE.read_text().lower()

        self.assertIn("source_hours / 14", placeholder)
        self.assertIn("when completeness.denominator_available", placeholder)
        self.assertIn("member_set_sha256", league)
        self.assertIn("member_count = 16", league)
        self.assertNotIn("2024-25", placeholder)
        self.assertNotIn("2024-25", league)


if __name__ == "__main__":
    unittest.main()
