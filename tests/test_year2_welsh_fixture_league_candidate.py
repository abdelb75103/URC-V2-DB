from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
VERSION = "20260831122000"
NAME = "urc_2025_26_welsh_fixture_league_candidate_snapshot"
MIGRATION = ROOT / "supabase/migrations" / f"{VERSION}_{NAME}.sql"
REGISTRATION = (
    ROOT / "tools/sql/register_urc_2025_26_welsh_fixture_league_candidate_snapshot_migration.sql"
)
CONTEXT_VERSION = "20260831123000"
CONTEXT_NAME = "urc_2025_26_welsh_fixture_release_context_date"
CONTEXT_MIGRATION = (
    ROOT / "supabase/migrations" / f"{CONTEXT_VERSION}_{CONTEXT_NAME}.sql"
)
CONTEXT_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_welsh_fixture_release_context_date_migration.sql"
)


class Year2WelshFixtureLeagueCandidateTests(unittest.TestCase):
    def test_seals_the_exact_mixed_team_release_set(self) -> None:
        raw = MIGRATION.read_text(encoding="utf-8")

        for release_id in (
            "7cfaf888-773b-43e2-bb9b-f1486ad4823e",
            "b2e069a6-de05-438f-be7d-1441df6136de",
        ):
            self.assertEqual(raw.count(release_id), 1)
        for token in (
            "then '20260831121000' else '20260831101000' end",
            "then 'injury_lineage_2025-26_2026-08-31_v3'",
            "else 'injury_lineage_2025-26_2026-08-30_v2' end",
            "from expected",
            "<> 2",
            "<> 14",
            "analysis.urc_2025_26_injury_fixture_corrected_rows_v2",
            "create or replace view analysis.league_team_dashboard_release_candidates_analysis_window_v6",
            "snapshot.cohort_view_version, snapshot.cohort_evidence_sha256",
            "count(distinct team_release_id) = 16",
            "<> 1545",
            "<> 938",
            "<> 782",
            "<> 20665",
        ):
            self.assertIn(token, raw)

    def test_outer_candidate_is_private_and_checksum_bound(self) -> None:
        raw = MIGRATION.read_text(encoding="utf-8")
        registration = REGISTRATION.read_text(encoding="utf-8")
        sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()

        self.assertIn("enable row level security", raw.lower())
        self.assertIn("revoke all on analysis.league_dashboard_release_candidate_snapshot_v6_20260831122000", raw.lower())
        self.assertIn("create table analysis.accepted_release_contracts_v4", raw.lower())
        self.assertIn("league_candidate_snapshot_version = '20260831122000'", raw)
        self.assertEqual(registration.count(f"migration_sha256={sha256}"), 2)
        contract = YEAR2_2025_26_RELEASE_CONTRACT.league_required_migration_contracts
        self.assertEqual(len(contract), 2)
        self.assertEqual(contract[0].version, VERSION)
        self.assertEqual(contract[0].name, NAME)
        self.assertEqual(contract[0].sha256, sha256)

    def test_context_date_accepts_only_the_corrected_tuple_on_review_date(self) -> None:
        raw = CONTEXT_MIGRATION.read_text(encoding="utf-8")
        registration = CONTEXT_REGISTRATION.read_text(encoding="utf-8")
        sha256 = hashlib.sha256(CONTEXT_MIGRATION.read_bytes()).hexdigest()

        for token in (
            "injury_lineage_2025-26_2026-08-30_v2",
            "injury_lineage_2025-26_2026-08-31_v3",
            "reporting_classification_2025-26_2026-08-31_v3",
            "decision_recorded_at = date '2026-08-31'",
        ):
            self.assertIn(token, raw)
        self.assertEqual(registration.count(f"migration_sha256={sha256}"), 2)
        context = YEAR2_2025_26_RELEASE_CONTRACT.league_required_migration_contracts
        self.assertEqual(context[-1].version, CONTEXT_VERSION)
        self.assertEqual(context[-1].sha256, sha256)


if __name__ == "__main__":
    unittest.main()
