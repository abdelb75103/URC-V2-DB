from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / (
    "supabase/migrations/20260827150000_urc_2024_25_successor_release_context.sql"
)
REGISTRATION = ROOT / (
    "tools/sql/register_urc_2024_25_successor_release_context_migration.sql"
)


class SuccessorReleaseContextTests(unittest.TestCase):
    def test_successor_classification_and_evidence_are_allowed(self) -> None:
        sql = MIGRATION.read_text()
        self.assertEqual(2, sql.count("reporting_classification_2024-25_2026-08-27_v1"))
        self.assertIn("league_release_context_v2_classification_view_version_check", sql)
        self.assertIn("league_release_context_v2_classification_evidence", sql)

    def test_registration_is_hash_bound(self) -> None:
        registration = REGISTRATION.read_text()
        self.assertIn("20260827150000", registration)
        self.assertIn("migration_sha256=", registration)
        self.assertIn("pg_get_constraintdef", registration)


if __name__ == "__main__":
    unittest.main()
