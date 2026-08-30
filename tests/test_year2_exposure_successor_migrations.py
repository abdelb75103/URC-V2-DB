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
TEAM_SNAPSHOT = (
    ROOT
    / "supabase/migrations/20260830155000_urc_2025_26_v6_exposure_successor_team_snapshot.sql"
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
            by_version["20260830155000"].sha256,
            hashlib.sha256(TEAM_SNAPSHOT.read_bytes()).hexdigest(),
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

    def test_placeholder_is_source_first_and_league_snapshot_is_member_bound(self) -> None:
        placeholder = PLACEHOLDER.read_text().lower()
        league = LEAGUE.read_text().lower()

        self.assertIn("source_hours / 14", placeholder)
        self.assertIn("when completeness.denominator_available", placeholder)
        self.assertIn("member_set_sha256", league)
        self.assertIn("member_count = 16", league)
        self.assertNotIn("2024-25", placeholder)
        self.assertNotIn("2024-25", league)

    def test_league_snapshot_uses_the_bounded_materialised_member_path(self) -> None:
        sql = LEAGUE.read_text().lower()
        pre_replacement = sql.split(
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6",
            maxsplit=1,
        )[0]

        self.assertEqual(sql.count("create temporary table _v6_"), 11)
        for token in (
            "current_setting('transaction_isolation') <> 'repeatable read'",
            "set local statement_timeout = '5min'",
            "set local lock_timeout = '5s'",
            "reporting.team_release_payloads_v6",
            "payload.payload_sha256 =",
            "reporting.canonical_jsonb_sha256_v1(payload.dashboard_payload)",
            "accepted_urc_2025_26_exposure_successor_evidence_v6",
            "76872.2616717166666666::numeric",
            "87854.0133391047619046::numeric",
            "5490.8758336940476190::numeric",
            "exposure_rows = 62481",
            "exposed_players = 490",
            "weeks = 44",
            "includes_temporary_league_mean_estimates_for_two_teams",
            "before update or delete",
            "enable row level security",
        ):
            self.assertIn(token, sql)
        self.assertNotIn(
            "analysis.league_dashboard_payload_analysis_window_v6_enriched",
            pre_replacement,
        )
        self.assertNotIn("set local statement_timeout = 0", sql)
        self.assertNotIn("grant select", sql)

    def test_league_snapshot_keeps_estimated_months_and_distance_unavailable(self) -> None:
        sql = LEAGUE.read_text().lower()

        for token in (
            "'distance_km', null::numeric",
            "month -> 'exposure_hours' is distinct from 'null'::jsonb",
            "month -> 'distance_km' is distinct from 'null'::jsonb",
            "month -> 'incidence_per_1000h' is distinct from 'null'::jsonb",
            "month -> 'burden_per_1000h' is distinct from 'null'::jsonb",
            "jsonb_array_length(dashboard -> 'limitations') = 3",
        ):
            self.assertIn(token, sql)

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
