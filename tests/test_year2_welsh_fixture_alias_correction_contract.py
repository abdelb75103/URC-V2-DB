from __future__ import annotations

import hashlib
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
VERSION = "20260831120000"
NAME = "urc_2025_26_welsh_fixture_alias_correction"
MIGRATION_PATH = ROOT / "supabase/migrations" / f"{VERSION}_{NAME}.sql"
REGISTRATION_PATH = (
    ROOT / "tools/sql/register_urc_2025_26_welsh_fixture_alias_correction_migration.sql"
)


class Year2WelshFixtureAliasCorrectionContractTests(unittest.TestCase):
    def test_correction_is_exact_date_private_and_additive(self) -> None:
        sql = MIGRATION_PATH.read_text(encoding="utf-8").lower()

        for token in (
            "fixture reconciliation unresolved",
            "('cardiff rugby', 'cardiff', false",
            "('dragons rfc', 'dragons', false",
            "welsh official fixture aliases are absent, inactive, or conflicting",
            "fixture.match_date = parsed.injury_date",
            "lower(btrim(master.row_values ->> 'problem type')) = 'injury'",
            "lower(btrim(master.row_values ->> 'occasion category')) = 'match'",
            "team_key in ('cardiff', 'dragons')",
            "count(*) filter (where team_key = 'cardiff') = 19",
            "count(*) filter (where team_key = 'dragons') = 42",
            "count(*) = 61",
            "injury_lineage_2025-26_2026-08-31_v3",
            "e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450",
            "docs/evidence/urc_2025_26_welsh_fixture_alias_exact_date_correction.json",
            "from audit.urc_2025_26_fixture_reconciliation_decisions_v1 decision",
            "from public, anon, authenticated, web_reader",
            "before update or delete",
            "enable row level security",
        ):
            self.assertIn(token, sql)

        self.assertNotIn("interval '1 day'", sql)
        self.assertEqual(sql.count("insert into reporting.team_key_aliases"), 1)
        self.assertNotIn("2024-25", sql)
        self.assertNotRegex(sql, r"\b(update\s+lineage|delete\s+from|truncate)\b")

    def test_corrected_projection_keeps_lineage_immutable(self) -> None:
        sql = MIGRATION_PATH.read_text(encoding="utf-8").lower()

        self.assertIn("from lineage.injury_inclusion_rows_v3 inclusion", sql)
        self.assertIn(
            "union all\n\n  select master.team_key, master.source_row",
            sql,
        )
        self.assertIn(
            "from audit.urc_2025_26_fixture_reconciliation_decisions_v1 decision",
            sql,
        )
        self.assertIn(
            "count(*) from analysis.urc_2025_26_injury_fixture_corrected_rows_v2) <> 1545",
            sql,
        )
        self.assertIn("where is_time_loss\n    ) <> 938", sql)
        self.assertIn("where is_time_loss and days_lost is not null\n    ) <> 782", sql)
        self.assertIn("where is_time_loss\n    ) <> 20665", sql)
        self.assertNotRegex(
            sql,
            r"insert\s+into\s+lineage\.injury_(master|inclusion)_rows_v3",
        )

    def test_registration_binds_exact_migration_bytes(self) -> None:
        registration = REGISTRATION_PATH.read_text(encoding="utf-8").lower()
        sha256 = hashlib.sha256(MIGRATION_PATH.read_bytes()).hexdigest()

        self.assertEqual(
            registration.count(f"migration_sha256={sha256}"),
            2,
        )
        self.assertIn(f"'{VERSION}'", registration)
        self.assertIn(f"'{NAME}'", registration)
        self.assertIn(
            "analysis.urc_2025_26_injury_fixture_corrected_rows_v2",
            registration,
        )
        self.assertIn(
            "audit.urc_2025_26_fixture_reconciliation_decisions_v1",
            registration,
        )
        self.assertIn("('cardiff rugby', 'cardiff', false)", registration)
        self.assertIn("('dragons rfc', 'dragons', false)", registration)
        self.assertIn("where is_time_loss and days_lost is not null", registration)
        self.assertIn("has_table_privilege", registration)


if __name__ == "__main__":
    unittest.main()
