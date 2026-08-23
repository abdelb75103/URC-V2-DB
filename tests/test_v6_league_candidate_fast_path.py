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

    def test_snapshot_assembles_staged_relations_before_replacing_the_view(self) -> None:
        population = SQL.index("with member_set as")
        staged_candidate = SQL.index("), candidate as (", population)
        replacement = SQL.index(
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6",
            staged_candidate,
        )

        self.assertLess(population, staged_candidate)
        self.assertLess(staged_candidate, replacement)
        self.assertIn("members.member_set_sha256, candidate.dashboard", SQL)
        self.assertIn(
            "reporting.canonical_jsonb_sha256_v1(candidate.dashboard)",
            SQL,
        )

    def test_eleven_constituent_relations_are_materialised_separately(self) -> None:
        self.assertEqual(SQL.count("create temporary table _v6_"), 11)
        for relation in (
            "analysis.league_member_releases_v6",
            "analysis.analysis_window_league_summary_v6",
            "analysis.analysis_window_league_monthly_v6",
            "analysis.analysis_window_team_hours_v6",
            "analysis.analysis_window_team_exposure_v6",
            "analysis.analysis_window_active_builds_v6",
            "analysis.accepted_analysis_window_cohort_rules_v6",
            "analysis.analysis_window_league_profiles_v6",
            "analysis.analysis_window_league_severity_v6",
            "analysis.analysis_window_league_setting_metrics_v6",
            "analysis.analysis_window_league_contact_distribution_v6",
        ):
            self.assertIn(relation, SQL)
        pre_replacement = SQL.split(
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6",
            1,
        )[0]
        self.assertNotIn(
            "from analysis.league_dashboard_release_candidates_analysis_window_v6",
            pre_replacement,
        )
        self.assertNotIn(
            "analysis.league_dashboard_payload_analysis_window_v6_enriched",
            pre_replacement,
        )

    def test_member_hash_binds_all_sixteen_release_and_build_identities(self) -> None:
        for token in (
            "'team_key', team_key",
            "'team_release_id', team_release_id::text",
            "'curated_build_id', curated_build_id::text",
            "order by team_key",
        ):
            self.assertEqual(SQL.count(token), 2, token)
        for token in (
            "having count(*) = 16",
            "count(distinct team_key) = 16",
            "count(distinct team_release_id) = 16",
            "count(distinct curated_build_id) = 16",
        ):
            self.assertIn(token, SQL)

    def test_stages_are_repeatable_read_and_cardinality_checked(self) -> None:
        self.assertIn(
            "current_setting('transaction_isolation') <> 'repeatable read'",
            SQL,
        )
        for token in (
            "recorded_injuries = 335",
            "time_loss_injuries = 107",
            "days_lost = 1950",
            "exposure_rows = 56769",
            "count(*) from _v6_league_profiles) <> 213",
            "count(*) from _v6_league_severity) <> 7",
            "count(*) from _v6_league_setting_metrics) <> 4",
            "count(*) from _v6_league_contact_distribution) <> 12",
        ):
            self.assertIn(token, SQL)

    def test_assembly_keeps_established_ordering_and_no_imputation_text(self) -> None:
        for token in (
            "order by monthly.month_start",
            "order by time_loss_injuries desc, code",
            "order by dimension, setting_code, code",
            "order by severity_code",
            "array_position(array['all', 'match', 'training', 'unknown'], setting_code)",
            "analysis.injury_type_families_from_payload_v1(",
            "no imputation was applied.",
        ):
            self.assertIn(token, SQL)

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
        self.assertNotIn("analysis_window_2024-25", SQL)
        self.assertNotIn("latest_approved_dashboard_bundle", SQL)
        self.assertNotIn("where season = '2024-25'", SQL)


if __name__ == "__main__":
    unittest.main()
