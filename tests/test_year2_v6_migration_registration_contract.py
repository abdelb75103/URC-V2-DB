from __future__ import annotations

import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch

import pipeline.__main__ as pipeline
from pipeline.season_contracts import (
    YEAR2_2025_26_RELEASE_CONTRACT,
    YEAR2_2025_26_RELEASE_TUPLE,
    release_contract_for,
)


ROOT = Path(__file__).resolve().parents[1]
REGISTRATION = (
    ROOT / "tools/sql/register_urc_2025_26_v6_migrations.sql"
).read_text(encoding="utf-8")
PLACEHOLDER_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_exposure_successor_placeholder_migration.sql"
).read_text(encoding="utf-8")
TEAM_SNAPSHOT_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_exposure_successor_team_snapshot_migration.sql"
).read_text(encoding="utf-8")
CUTOVER_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_injury_successor_cutover_migration.sql"
).read_text(encoding="utf-8")
REPORTING_KEY_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_reporting_key_family_correction_migration.sql"
).read_text(encoding="utf-8")
FAMILY_MAPPING_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_family_mapping_contract_correction_migration.sql"
).read_text(encoding="utf-8")
WELSH_FIXTURE_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_welsh_fixture_alias_correction_migration.sql"
).read_text(encoding="utf-8")
WELSH_CANDIDATE_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_welsh_fixture_candidate_successor_migration.sql"
).read_text(encoding="utf-8")


def registration_for(version: str) -> str:
    if version == "20260830150000":
        return PLACEHOLDER_REGISTRATION
    if version == "20260830155000":
        return TEAM_SNAPSHOT_REGISTRATION
    if version == "20260830170000":
        return CUTOVER_REGISTRATION
    if version == "20260831100000":
        return REPORTING_KEY_REGISTRATION
    if version == "20260831101000":
        return FAMILY_MAPPING_REGISTRATION
    if version == "20260831120000":
        return WELSH_FIXTURE_REGISTRATION
    if version == "20260831121000":
        return WELSH_CANDIDATE_REGISTRATION
    return REGISTRATION


class Year2V6MigrationRegistrationContractTests(unittest.TestCase):
    def test_candidate_optimisation_is_checksum_bound_before_release(self) -> None:
        contract = next(
            item
            for item in YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts
            if item.version == "20260822220611"
        )
        self.assertEqual(contract.name, "urc_2025_26_v6_candidate_view_optimisation")
        self.assertEqual(
            contract.sha256,
            "5e5c734a0d4b14337a6cf0a12f5891fbdd9b4ef7ea71fadc97c1a1d85a4cd8d6",
        )
        self.assertIn(contract.version, YEAR2_2025_26_RELEASE_CONTRACT.required_migrations)
        self.assertEqual(REGISTRATION.count(contract.statement), 2)

    def test_league_candidate_fast_path_is_checksum_bound_before_release(self) -> None:
        contract = next(
            item
            for item in YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts
            if item.version == "20260823120000"
        )
        self.assertEqual(contract.name, "urc_2025_26_v6_league_candidate_fast_path")
        self.assertEqual(
            contract.sha256,
            "ad8ed2146569c81020f2d8425a84d053045a1bf727f767949eff0cee97f715eb",
        )
        self.assertIn(contract.version, YEAR2_2025_26_RELEASE_CONTRACT.required_migrations)
        self.assertEqual(REGISTRATION.count(contract.statement), 2)

    def test_release_contract_binds_each_local_migration_to_one_registered_checksum(self) -> None:
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)
        self.assertEqual(contract, YEAR2_2025_26_RELEASE_CONTRACT)
        self.assertEqual(
            {item.version for item in contract.required_migration_contracts},
            set(contract.required_migrations),
        )
        for item in contract.required_migration_contracts:
            migration = ROOT / "supabase/migrations" / f"{item.version}_{item.name}.sql"
            self.assertEqual(item.sha256, hashlib.sha256(migration.read_bytes()).hexdigest())
            registration = registration_for(item.version)
            self.assertEqual(registration.count(item.statement), 2)
            self.assertIn(f"'{item.version}',", registration)
            self.assertIn(f"'{item.name}'", registration)

    def test_corrected_league_snapshot_extends_only_the_league_gate(self) -> None:
        base_contracts = pipeline.release_migration_contracts(
            YEAR2_2025_26_RELEASE_CONTRACT
        )
        league_contracts = pipeline.release_migration_contracts(
            YEAR2_2025_26_RELEASE_CONTRACT,
            include_league=True,
        )

        self.assertEqual(league_contracts[:-3], base_contracts)
        self.assertEqual(
            tuple(item.version for item in league_contracts[-3:]),
            ("20260831110000", "20260831111000", "20260831112000"),
        )
        self.assertFalse((
            ROOT / "tools/sql/register_urc_2025_26_exposure_successor_league_snapshot_migration.sql"
        ).exists())

    def test_registration_fails_closed_on_missing_objects_or_private_table_grants(self) -> None:
        for token in (
            "URC 2025-26 V6 migration objects are incomplete",
            "URC 2025-26 V6 private release storage is not least-privilege",
            "URC 2025-26 V6 migration registration is absent or checksum-mismatched",
            "on conflict (version) do nothing",
            "relrowsecurity",
            "analysis.league_dashboard_release_candidate_snapshot_v6_20260823",
        ):
            self.assertIn(token, REGISTRATION)

    def test_runtime_release_gate_checks_local_bytes_and_exact_database_rows(self) -> None:
        source = pipeline.assert_checksum_bound_release_migrations.__doc__ or ""
        self.assertIn("local V6 migration bytes", source)
        implementation = __import__("inspect").getsource(
            pipeline.assert_checksum_bound_release_migrations
        ) + __import__("inspect").getsource(pipeline.assert_checksum_bound_migrations)
        self.assertIn("sha256_file(migration_path) != item.sha256", implementation)
        self.assertIn("item.statement", implementation)
        self.assertIn("schema_migrations", implementation)

    def test_runtime_release_gate_rejects_a_registered_checksum_mismatch_without_database_access(self) -> None:
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        exact_rows = [
            {"version": item.version, "name": item.name, "statements": item.statements}
            for item in contract.required_migration_contracts
        ]
        with patch.object(pipeline, "query_sql", return_value=exact_rows):
            pipeline.assert_checksum_bound_release_migrations(contract, "test")
        mismatch = [*exact_rows]
        mismatch[0] = {**mismatch[0], "statements": ["migration_sha256=" + "0" * 64]}
        with patch.object(pipeline, "query_sql", return_value=mismatch):
            with self.assertRaisesRegex(SystemExit, "exact registered migration checksums"):
                pipeline.assert_checksum_bound_release_migrations(contract, "test")


if __name__ == "__main__":
    unittest.main()
