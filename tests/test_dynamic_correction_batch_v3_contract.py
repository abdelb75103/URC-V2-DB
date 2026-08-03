from __future__ import annotations

import ast
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260803153728_dynamic_row_correction_batch_v3.sql"
CORRECTIONS = ROOT / "pipeline/corrections.py"
PIPELINE_MAIN = ROOT / "pipeline/__main__.py"
REGISTER = ROOT / "tools/sql/register_dynamic_row_correction_batch_v3_migration.sql"
HARDENING_CHAIN = (
    (
        "20260803161707_dynamic_row_correction_batch_v3_hardening.sql",
        "register_dynamic_row_correction_batch_v3_hardening_migration.sql",
        "20260803161707",
        "dynamic_row_correction_batch_v3_hardening",
    ),
    (
        "20260803162112_dynamic_row_correction_batch_v4_hardening.sql",
        "register_dynamic_row_correction_batch_v4_hardening_migration.sql",
        "20260803162112",
        "dynamic_row_correction_batch_v4_hardening",
    ),
    (
        "20260803162702_dynamic_row_correction_batch_v5_hardening.sql",
        "register_dynamic_row_correction_batch_v5_hardening_migration.sql",
        "20260803162702",
        "dynamic_row_correction_batch_v5_hardening",
    ),
    (
        "20260803163038_dynamic_row_correction_batch_v6_hardening.sql",
        "register_dynamic_row_correction_batch_v6_hardening_migration.sql",
        "20260803163038",
        "dynamic_row_correction_batch_v6_hardening",
    ),
    (
        "20260803163430_dynamic_row_correction_batch_v7_hardening.sql",
        "register_dynamic_row_correction_batch_v7_hardening_migration.sql",
        "20260803163430",
        "dynamic_row_correction_batch_v7_hardening",
    ),
)


class DynamicCorrectionBatchV3ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lowered = cls.sql.lower()
        cls.command_source = CORRECTIONS.read_text(encoding="utf-8")
        cls.main_source = PIPELINE_MAIN.read_text(encoding="utf-8")
        cls.registration = REGISTER.read_text(encoding="utf-8")
        cls.tree = ast.parse(cls.command_source)

    def function_source(self, name: str) -> str:
        node = next(
            candidate
            for candidate in self.tree.body
            if isinstance(candidate, ast.FunctionDef) and candidate.name == name
        )
        return ast.get_source_segment(self.command_source, node) or ""

    def test_migration_is_additive_and_exactly_binds_v2(self) -> None:
        self.assertIn("20260727010000", self.sql)
        self.assertIn(
            "29dd76bb42ac7bdc10f3a6691bf538a1af4786a15408acc467a4c9beab4cd57b",
            self.sql,
        )
        self.assertNotIn("create or replace", self.lowered)
        self.assertNotIn("drop table", self.lowered)
        self.assertNotIn("delete from", self.lowered)
        self.assertNotIn("truncate", self.lowered)
        self.assertNotIn("update curated.", self.lowered)
        self.assertNotIn("update ingestion.", self.lowered)

    def test_registration_binds_the_exact_final_migration(self) -> None:
        import hashlib

        digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        self.assertEqual(
            self.registration.count(f"migration_sha256={digest}"), 2
        )
        self.assertIn("20260803153728", self.registration)
        self.assertIn("dynamic_row_correction_batch_v3", self.registration)

    def test_each_installed_hardening_successor_has_an_exact_registration(self) -> None:
        import hashlib

        for migration_name, registration_name, version, name in HARDENING_CHAIN:
            migration = ROOT / "supabase/migrations" / migration_name
            registration = ROOT / "tools/sql" / registration_name
            digest = hashlib.sha256(migration.read_bytes()).hexdigest()
            registration_sql = registration.read_text(encoding="utf-8")
            self.assertEqual(registration_sql.count(f"migration_sha256={digest}"), 2)
            self.assertIn(version, registration_sql)
            self.assertIn(name, registration_sql)

    def test_batch_is_same_team_append_only_and_recomputes_one_candidate(self) -> None:
        for object_name in (
            "audit.correction_batches_v3",
            "audit.correction_batch_items_v3",
            "processing.correction_batch_versions_v3",
            "analysis.row_correction_effective_values_v3",
            "analysis.row_correction_preview_v3",
            "audit.apply_row_correction_batch_v3",
            "reporting.promote_row_correction_batch_v3",
        ):
            self.assertIn(object_name, self.lowered)
        self.assertIn("a correction batch must target exactly one team", self.lowered)
        self.assertGreaterEqual(self.lowered.count("append_only"), 3)
        self.assertIn(
            "reporting.promote_row_correction_v2(text,text,text)", self.lowered
        )
        self.assertIn(
            "analysis.row_correction_team_payload_candidates_incremental_v3",
            self.lowered,
        )
        self.assertIn("row-correction batch v3 dependency graph was not rewired exactly", self.lowered)
        self.assertIn("pg_get_functiondef", self.lowered)
        self.assertIn("pg_get_viewdef", self.lowered)

    def test_batch_items_keep_independent_evidence_and_row_events(self) -> None:
        self.assertIn("evidence_sha256", self.lowered)
        self.assertIn("supersedes_correction_id", self.lowered)
        self.assertIn("audit.record_events", self.lowered)
        self.assertIn("source_row_sha256", self.lowered)
        self.assertIn("row_fingerprint", self.lowered)
        self.assertIn("approval_evidence_by_item", self.lowered)

    def test_cli_has_separate_propose_apply_and_release_gates(self) -> None:
        for command in (
            "correction-batch-propose",
            "correction-batch-apply",
            "correction-batch-release",
        ):
            self.assertIn(f'add_parser(\n        "{command}"', self.main_source)
        propose = self.function_source("correction_batch_propose")
        apply = self.function_source("correction_batch_apply")
        release = self.function_source("correction_batch_release")
        self.assertIn("_batch_preview", propose)
        self.assertNotIn("run_sql", propose)
        self.assertIn("audit.apply_row_correction_batch_v8", apply)
        self.assertIn("run_sql", apply)
        self.assertIn("reporting.promote_row_correction_batch_v8", release)
        self.assertIn("_run_correction_rollback", release)
        self.assertIn("analysis.row_correction_preview_v5", self.command_source)
        self.assertIn("20260803163430", self.command_source)
        self.assertIn("dynamic_row_correction_batch_v7_hardening", self.command_source)

    def test_public_database_roles_cannot_access_batch_internals(self) -> None:
        self.assertGreaterEqual(
            self.lowered.count("from public, anon, authenticated, web_reader"), 8
        )
        self.assertIn("revoke all on audit.correction_batches_v3", self.lowered)
        self.assertIn("reporting.latest_dashboard_cache_token_v1", self.lowered)
        self.assertIn("grant select on reporting.latest_dashboard_cache_token_v1 to web_reader", self.lowered)

    def test_legacy_v2_commands_fail_closed_after_v3_installation(self) -> None:
        guard = self.function_source("_assert_legacy_v2_is_available")
        propose = self.function_source("correction_propose")
        apply = self.function_source("correction_apply")
        release = self.function_source("correction_release")
        self.assertIn("assert_legacy_row_correction_v2_available", guard)
        self.assertIn("_assert_legacy_v2_is_available", propose)
        self.assertIn("_assert_legacy_v2_is_available", apply)
        self.assertIn("_assert_legacy_v2_is_available", release)
        self.assertIn("single-row correction V2 is disabled", self.sql)


if __name__ == "__main__":
    unittest.main()
