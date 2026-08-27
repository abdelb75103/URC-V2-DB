from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / (
    "supabase/migrations/20260827160000_urc_2024_25_successor_correction_guard.sql"
)
REGISTRATION = ROOT / (
    "tools/sql/register_urc_2024_25_successor_correction_guard_migration.sql"
)


class SuccessorCorrectionGuardTests(unittest.TestCase):
    def test_exception_is_narrow_and_hash_bound(self) -> None:
        sql = MIGRATION.read_text()
        self.assertIn("reporting_classification_2024-25_2026-08-27_v1", sql)
        self.assertIn(
            "b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051",
            sql,
        )
        self.assertIn("row_correction_served_sets_v1", sql)
        self.assertIn("correction_release_context_v1", sql)
        self.assertIn("correction_rollback_context_v1", sql)
        self.assertIn("ordinary release blocked while served row corrections are active", sql)

    def test_registration_is_hash_bound(self) -> None:
        registration = REGISTRATION.read_text()
        self.assertIn("20260827160000", registration)
        self.assertIn("migration_sha256=", registration)
        self.assertIn("pg_get_functiondef", registration)


if __name__ == "__main__":
    unittest.main()
