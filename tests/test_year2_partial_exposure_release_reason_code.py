from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
VERSION = "20260831132000"
NAME = "urc_2025_26_partial_exposure_release_reason_code"
MIGRATION = ROOT / "supabase/migrations" / f"{VERSION}_{NAME}.sql"
REGISTRATION = ROOT / "tools/sql" / f"register_{NAME}_migration.sql"


class Year2PartialExposureReleaseReasonCodeTests(unittest.TestCase):
    def test_registers_only_the_exact_audit_reason(self) -> None:
        raw = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("insert into audit.reason_codes", raw)
        self.assertIn(YEAR2_2025_26_RELEASE_CONTRACT.release_reason_code, raw)
        self.assertNotRegex(raw.lower(), r"(?:update|delete)\s+(?:curated|reporting|analysis)\.")

    def test_checksum_is_registered_and_required(self) -> None:
        migration_sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        registration = REGISTRATION.read_text(encoding="utf-8")
        self.assertEqual(registration.count(f"migration_sha256={migration_sha256}"), 2)
        item = next(
            entry for entry in YEAR2_2025_26_RELEASE_CONTRACT.required_migration_contracts
            if entry.version == VERSION
        )
        self.assertEqual(item.name, NAME)
        self.assertEqual(item.sha256, migration_sha256)


if __name__ == "__main__":
    unittest.main()
