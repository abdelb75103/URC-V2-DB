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
TEAM_SNAPSHOT = (
    ROOT
    / "supabase/migrations/20260830155000_urc_2025_26_v6_exposure_successor_team_snapshot.sql"
)


class Year2ExposureSuccessorMigrationTests(unittest.TestCase):
    def test_contracts_bind_the_applied_exposure_migration_byte_sequences(self) -> None:
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
            by_version["20260830155000"].sha256,
            hashlib.sha256(TEAM_SNAPSHOT.read_bytes()).hexdigest(),
        )

    def test_placeholder_candidate_uses_unambiguous_build_keys(self) -> None:
        sql = PLACEHOLDER.read_text().lower()
        candidate = sql.split(
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6",
            1,
        )[1]

        self.assertNotIn("using (curated_build_id, team_key, season)", candidate)
        for predicate in (
            "completeness.curated_build_id = candidate.curated_build_id",
            "completeness.team_key = candidate.team_key",
            "completeness.season = candidate.season",
        ):
            self.assertIn(predicate, candidate)

    def test_candidate_preserves_the_live_integrity_columns_and_limitation(self) -> None:
        sql = PLACEHOLDER.read_text().lower()

        self.assertIn("analysis.urc_2025_26_injury_cohort_reconciliation_v1", sql)
        self.assertIn(
            "cross join analysis.accepted_urc_2025_26_injury_problem_type_successor_v1",
            sql,
        )
        self.assertIn("jsonb_build_array(evidence.release_limitation)", sql)
        for column in (
            "processing_eligible_injury_count",
            "eligible_curated_injury_count",
            "recorded_cohort_count",
            "processing_record_version_set_sha256",
            "curated_record_version_set_sha256",
            "reporting_record_version_set_sha256",
            "approved_injury_source_file_count",
            "unapproved_injury_source_row_count",
            "wrong_problem_type_rule_version_count",
        ):
            self.assertEqual(sql.count(f"candidate.{column}"), 1, column)

    def test_placeholder_is_source_first(self) -> None:
        placeholder = PLACEHOLDER.read_text().lower()

        self.assertIn("source_hours / 14", placeholder)
        self.assertIn("when completeness.denominator_available", placeholder)
        self.assertNotIn("2024-25", placeholder)

    def test_obsolete_league_snapshot_is_not_executable(self) -> None:
        self.assertFalse((
            ROOT / "supabase/migrations/20260830160000_urc_2025_26_v6_exposure_successor_league_snapshot.sql"
        ).exists())

    def test_team_snapshot_is_private_immutable_and_state_bound(self) -> None:
        sql = TEAM_SNAPSHOT.read_text().lower()

        for token in (
            "enable row level security",
            "before update or delete",
            "active_state_sha256",
            "'builds', build_state.builds",
            "'placeholders', placeholder_state.placeholders",
            "count(*) = 16",
            "count(*) = 2",
            "payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)",
        ):
            self.assertIn(token, sql)
        self.assertNotIn("grant select", sql)
        self.assertNotIn("2024-25", sql)

        view_select = sql.split(
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6",
            maxsplit=1,
        )[1].split("from analysis.team_dashboard_release_candidate_snapshot_v6_20260830", maxsplit=1)[0]
        for column in (
            "snapshot.team_key", "snapshot.season", "snapshot.team_release_id",
            "snapshot.curated_build_id", "snapshot.analysis_version",
            "snapshot.classification_view_version",
            "snapshot.classification_evidence_sha256",
            "snapshot.cohort_view_version", "snapshot.cohort_evidence_sha256",
            "snapshot.dashboard", "snapshot.processing_eligible_injury_count",
            "snapshot.eligible_curated_injury_count", "snapshot.recorded_cohort_count",
            "snapshot.processing_record_version_set_sha256",
            "snapshot.curated_record_version_set_sha256",
            "snapshot.reporting_record_version_set_sha256",
            "snapshot.approved_injury_source_file_count",
            "snapshot.unapproved_injury_source_row_count",
            "snapshot.wrong_problem_type_rule_version_count",
        ):
            self.assertEqual(view_select.count(column), 1)


if __name__ == "__main__":
    unittest.main()
