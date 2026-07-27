from __future__ import annotations

import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT
    / "supabase/migrations"
    / "20260727010000_dynamic_row_correction_pipeline_hardening.sql"
)
REGISTER = (
    ROOT
    / "tools/sql"
    / "register_dynamic_row_correction_pipeline_hardening_migration.sql"
)
CORRECTIONS = ROOT / "pipeline/corrections.py"


class DynamicCorrectionHardeningMigrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lowered = cls.sql.lower()
        cls.registration = REGISTER.read_text(encoding="utf-8")
        cls.command_source = CORRECTIONS.read_text(encoding="utf-8")

    def test_base_migration_is_exactly_bound_and_v1_objects_are_not_redefined(self) -> None:
        self.assertIn("20260726200000", self.sql)
        self.assertIn(
            "07bbd951aedf19705ba8ea99cff30d445c6634ddfad90f84e3b9f2f38218aac5",
            self.sql,
        )
        for frozen_object in (
            "create or replace view analysis.row_correction_target_teams_v1",
            "create or replace function analysis.row_correction_pending_candidate_data_v1",
            "create or replace function analysis.row_correction_preview_v1",
            "create or replace function audit.apply_row_correction_v1",
            "create or replace function reporting.promote_row_correction_v1",
        ):
            self.assertNotIn(frozen_object, self.lowered)

    def test_v2_candidate_graph_is_scoped_before_payload_building(self) -> None:
        for object_name in (
            "analysis.row_correction_target_teams_v2",
            "analysis.row_correction_incremental_context_v2",
            "analysis.row_correction_team_payload_candidates_incremental_v2",
            "analysis.row_correction_league_dashboard_payload_incremental_v2",
            "analysis.row_correction_pending_candidate_data_v2",
            "analysis.row_correction_preview_v2",
            "audit.apply_row_correction_v2",
            "reporting.promote_row_correction_v2",
        ):
            self.assertIn(object_name, self.lowered)
        self.assertIn("urc.row_correction_target_season", self.lowered)
        self.assertIn("where context.season = target_season", self.lowered)
        self.assertIn("context.affected_team_key as team_key", self.lowered)
        self.assertIn("row_correction_pending_candidate_data_v2(", self.sql)
        self.assertIn("'correction_set.season) candidate'", self.sql)

    def test_cloned_dynamic_segment_uses_corrected_origin_view(self) -> None:
        self.assertIn(
            "create view analysis.row_correction_reporting_classification_v2",
            self.lowered,
        )
        for field in (
            "body_location_code",
            "injury_type_code",
            "diagnosis_code",
        ):
            self.assertIn(f"effective.field_name = '{field}'", self.lowered)
        self.assertGreaterEqual(self.lowered.count("then 'row_correction'"), 3)
        self.assertIn(
            "'analysis.row_correction_reporting_classification_v1',",
            self.sql,
        )
        self.assertIn(
            "'analysis.row_correction_reporting_classification_v2'",
            self.sql,
        )

    def test_apply_requires_the_registered_successor_sha(self) -> None:
        apply_start = self.lowered.index(
            "create function audit.apply_row_correction_v2"
        )
        apply_body = self.lowered[apply_start:]
        self.assertIn("supabase_migrations.schema_migrations", apply_body)
        self.assertIn("20260727010000", apply_body)
        self.assertIn("proposal ->> 'migration_sha256'", apply_body)
        self.assertIn(
            "proposal migration sha does not match the installed", apply_body
        )
        self.assertIn(
            "20260727010000_dynamic_row_correction_pipeline_hardening.sql",
            self.sql,
        )
        self.assertIn("row_correction_candidate_2026-07-27_v2", self.sql)
        self.assertIn("row_correction_release_2026-07-27_v2", self.sql)
        self.assertIn("20260727010000", self.command_source)
        self.assertIn("supabase_migrations.schema_migrations", self.command_source)

    def test_automatic_recovery_is_collision_safe_but_explicit_rollback_stays_v1(self) -> None:
        self.assertIn(
            "reporting.rollback_row_correction_bundle_recovery_v2",
            self.lowered,
        )
        self.assertIn("when unique_violation", self.lowered)
        self.assertIn("aggregate_releases_release_label_key", self.lowered)
        self.assertIn("-recovery-", self.lowered)
        self.assertIn("audit.correction_recovery_labels_v1", self.lowered)
        self.assertIn("fallback_used", self.lowered)
        self.assertIn("from public, anon, authenticated, web_reader", self.lowered)
        self.assertIn(
            "revoke all on audit.correction_recovery_labels_v1", self.lowered
        )
        self.assertIn(
            '"reporting.rollback_row_correction_bundle_recovery_v2"',
            self.command_source,
        )
        self.assertIn(
            '"reporting.rollback_row_correction_bundle_v1"',
            self.command_source,
        )
        self.assertIn("automatic_recovery=True", self.command_source)

    def test_registration_sha_matches_final_migration(self) -> None:
        digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        self.assertNotIn("FINAL_SHA256_PENDING", self.registration)
        self.assertEqual(
            self.registration.count(f"migration_sha256={digest}"),
            2,
        )


if __name__ == "__main__":
    unittest.main()
