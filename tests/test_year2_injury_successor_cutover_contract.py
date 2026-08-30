from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260830170000_urc_2025_26_injury_successor_cutover.sql"
REGISTRATION = ROOT / "tools/sql/register_urc_2025_26_injury_successor_cutover_migration.sql"


class Year2InjurySuccessorCutoverContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.raw = MIGRATION.read_text(encoding="utf-8")
        cls.sql = cls.raw.lower()
        cls.registration = REGISTRATION.read_text(encoding="utf-8")

    def test_exact_private_successor_and_registration_are_bound(self) -> None:
        self.assertEqual(
            hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
            "3df4c44f3e49cad5b2589d4bd6346a7274b11155c20fa30cb582b2a2231ad99e",
        )
        for value in (
            "2f419706-8c36-58dd-b4cb-e92162e782b8",
            "20260830140000",
            "76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a",
            "7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab",
            "111328427560503939a66e845d4a6e0fb8fa606f9dbf4a6f508aa0df04cab637",
            "f9e8d82998232a2e7e6f7325f319a685546197b4f4c3ff022f366fafa854c78a",
            "2b5e2243bfc912fac1561789e9327987d058a5543233f068f3bef9928c397670",
            "migration_sha256=3df4c44f3e49cad5b2589d4bd6346a7274b11155c20fa30cb582b2a2231ad99e",
        ):
            self.assertIn(value, self.raw + self.registration)

    def test_identity_counts_and_known_duration_gates_are_exact(self) -> None:
        for value in (
            "reporting_classification_2025-26_2026-08-30_v2",
            "injury_lineage_2025-26_2026-08-30_v2",
            "<> 1484",
            "<> 877",
            "<> 607",
            "<> 731",
            "<> 19047",
            "87854.0133391047619046::numeric",
            "76872.2616717166666666::numeric",
            "5490.8758336940476190::numeric",
            "<> 62481",
            "candidate.team_key in ('benetton', 'edinburgh')",
            "temporary_league_mean_estimate_no_source_exposure",
            "month -> 'exposure_hours' <> 'null'::jsonb",
            "month -> 'distance_km' <> 'null'::jsonb",
        ):
            self.assertIn(value, self.raw)

    def test_private_v3_rows_supply_all_injury_fields_and_nothing_from_curated_injuries(self) -> None:
        source = self.raw.split(
            "create view analysis.urc_2025_26_injury_successor_rows_v1", 1
        )[1].split(
            "create table analysis.team_dashboard_release_candidate_snapshot", 1
        )[0]
        for value in (
            "lineage.injury_inclusion_rows_v3",
            "lineage.injury_master_rows_v3",
            "inclusion.dashboard_eligible",
            "final_classification = 'Time Loss'",
            "time_loss_days as days_lost",
            "to_char(to_date(raw_injury_date, 'DD/MM/YYYY'), 'DD/MM/YYYY') = raw_injury_date",
            "'Occasion category'",
            "'Is Contact'",
            "'Body Part'",
            "'Injury Tissue Type/s'",
            "'Specific Diagnosis'",
        ):
            self.assertIn(value, source)
        self.assertNotIn("curated.injuries", source.lower())
        self.assertNotIn("injury_master_rows_v2", source.lower())

    def test_snapshot_is_private_immutable_and_binds_member_lineage(self) -> None:
        for value in (
            "enable row level security",
            "revoke all on analysis.team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor",
            "before update or delete",
            "injury_lineage_version_id",
            "injury_lineage_snapshot_version",
            "injury_lineage_member_sha256",
            "'successor', to_jsonb(evidence)",
            "'builds', build_state.builds",
            "'placeholders', placeholder_state.placeholders",
            "count(*) = 16",
            "count(*) = 2",
        ):
            self.assertIn(value, self.sql)
        self.assertNotRegex(self.sql, r"grant\s+select.*web_reader")
        self.assertIn("create table reporting.team_release_injury_lineage_v1", self.sql)
        self.assertIn("release_id uuid primary key", self.sql)

    def test_candidate_replaces_every_injury_dependent_section_with_v3_metrics(self) -> None:
        material = self.raw.split(
            "create view analysis.urc_2025_26_injury_successor_candidate_material_v1", 1
        )[1].rsplit("\n\nwith active_builds as materialized", 1)[0]
        for section in (
            "'headline'",
            "'monthly'",
            "'body_locations'",
            "'injury_types'",
            "'injury_profiles'",
            "'severity_distribution'",
            "'setting_split'",
            "'setting_metrics'",
            "'contact_distribution'",
        ):
            self.assertIn(section, material)
        self.assertIn("'overall_incidence_per_1000h'", material)
        self.assertIn("known_duration_time_loss_injuries", material)
        self.assertEqual(material.count("'key', 'overall_incidence_per_1000h'"), 1)
        self.assertIn("jsonb_array_length(dashboard -> 'headline') <> 7", self.raw)
        self.assertIn("analysis.injury_type_families_from_payload_v1", material)
        for formula in (
            "count(final classified eligible injury rows, including undated)",
            "count(final classification = Time Loss)",
            "pooled recorded injuries / pooled exposure hours * 1000",
            "pooled final Time Loss injuries / pooled exposure hours * 1000",
            "known-duration Time Loss days lost / known-duration Time Loss injuries",
            "median known-duration Time Loss days lost",
            "known-duration Time Loss days lost / pooled exposure hours * 1000",
        ):
            self.assertIn(f"'formula', '{formula}'", material)

    def test_cutover_does_not_reference_or_mutate_year1(self) -> None:
        self.assertNotRegex(
            self.sql,
            r"(?m)^\s*(drop\s+table|truncate|delete\s+from|update)\b",
        )
        self.assertNotIn("lineage.master_rows", self.sql)
        self.assertNotIn("where season = '2024-25'", self.sql)
        self.assertNotIn("20260830155000", self.raw)
        self.assertIn("'analysis_window_2024-25_2026-08-30_v2'", self.raw)

    def test_replacement_candidate_view_preserves_the_live_column_prefix(self) -> None:
        replacement = self.raw.split(
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6",
            1,
        )[1]
        legacy_prefix = replacement.split("snapshot.injury_lineage_version_id", 1)[0]
        for column in (
            "snapshot.dashboard",
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
            self.assertIn(column, legacy_prefix)

    def test_private_semantic_views_replace_the_stale_injury_path(self) -> None:
        for relation in (
            "analysis.urc_2025_26_injury_successor_cohort_v1",
            "analysis.urc_2025_26_injury_successor_league_monthly_v1",
            "analysis.urc_2025_26_injury_successor_league_summary_v1",
        ):
            self.assertIn(f"create view {relation}", self.sql)
            self.assertIn(relation, self.sql.split("revoke all on", 1)[1])
        self.assertIn("sum(exposure.minutes_clean) / 60 as exposure_hours", self.sql)
        self.assertIn("sum(hours.total_hours) = 87854.0133391047619046::numeric", self.sql)

    def test_registration_checks_live_privacy_and_candidate_completeness(self) -> None:
        lower = self.registration.lower()
        for value in (
            "has_table_privilege('web_reader'",
            "team_dashboard_release_candidate_snapshot_v6_20260830_injury_successor",
            "team_release_injury_lineage_v1",
            "on conflict (version) do nothing",
            "year 2 injury-successor cutover registration is invalid",
        ):
            self.assertIn(value, lower)
        self.assertEqual(
            self.registration.count("migration_sha256=3df4c44f3e49cad5b2589d4bd6346a7274b11155c20fa30cb582b2a2231ad99e"),
            2,
        )
        self.assertIsNone(re.search(r"grant\s+select.*web_reader", lower))


if __name__ == "__main__":
    unittest.main()
