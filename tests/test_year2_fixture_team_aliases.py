from pathlib import Path
import hashlib
import inspect
import unittest

import pipeline.__main__ as pipeline
from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
SQL = (
    ROOT
    / "supabase/migrations/20260822010000_urc_2025_26_fixture_team_aliases.sql"
).read_text(encoding="utf-8")
REGISTRATION = (
    ROOT / "tools/sql/register_urc_2025_26_v6_migrations.sql"
).read_text(encoding="utf-8")


class Year2FixtureTeamAliasTests(unittest.TestCase):
    def test_official_fixture_names_are_bound_to_canonical_keys(self) -> None:
        expected = {
            "Benetton Rugby": "benetton",
            "Connacht Rugby": "connacht",
            "Leinster Rugby": "leinster",
            "Munster Rugby": "munster",
            "Ulster Rugby": "ulster",
        }
        for alias, team_key in expected.items():
            self.assertIn(f"('{alias}', '{team_key}', false", SQL)

    def test_alias_migration_fails_closed_on_conflicts(self) -> None:
        self.assertIn("on conflict (alias) do nothing", SQL)
        self.assertIn(") <> 5 then", SQL)
        self.assertIn("raise exception", SQL)

    def test_release_and_registration_bind_exact_alias_migration_bytes(self) -> None:
        contract = next(
            migration for migration in YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts
            if migration.version == "20260822010000"
        )
        self.assertEqual(hashlib.sha256(SQL.encode()).hexdigest(), contract.sha256)
        self.assertEqual(REGISTRATION.count(contract.statement), 2)

    def test_registration_requires_exact_active_alias_mappings_first(self) -> None:
        self.assertIn("join reporting.teams team on team.team_key = alias.team_key and team.active", REGISTRATION)
        self.assertIn("official fixture aliases are absent, inactive, or conflict", REGISTRATION)

    def test_fixture_loader_requires_both_provenance_and_alias_migrations(self) -> None:
        source = inspect.getsource(pipeline.load_curated_fixtures)
        self.assertIn("YEAR2_FIXTURE_ALIAS_MIGRATION_VERSION", source)
        self.assertIn("if len(fixture_migrations) != 2", source)
        self.assertIn("assert_checksum_bound_migrations", source)


if __name__ == "__main__":
    unittest.main()
