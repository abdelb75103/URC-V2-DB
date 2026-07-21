from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260721120000_injury_type_family_reader_v3.sql"
CANONICAL_CODE_LIST = ROOT / "supabase/migrations/20260709233356_curated_layer.sql"


class InjuryTypeFamilyReaderV3MigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text()
        cls.lowered = cls.sql.lower()

    def test_is_additive_and_keeps_approved_v2_readers_untouched(self) -> None:
        self.assertNotIn("create or replace", self.lowered)
        self.assertNotRegex(self.lowered, r"drop\s+(view|table|function)")
        self.assertIn("create function analysis.injury_type_families_from_payload_v1", self.lowered)
        self.assertIn("create view reporting.latest_team_dashboard_v3", self.lowered)
        self.assertIn("create view reporting.latest_league_dashboard_v3", self.lowered)
        self.assertNotRegex(self.lowered, r"alter\s+view\s+reporting\.latest_(team|league)_dashboard_v2")

    def test_all_current_controlled_types_map_once_to_an_agreed_family(self) -> None:
        canonical_sql = CANONICAL_CODE_LIST.read_text()
        expected = set(re.findall(r"\('injury_type',\s*'([a-z_]+)'", canonical_sql))
        self.assertEqual(26, len(expected), "canonical injury type code-list extraction drifted")
        mapping_block = self.sql.split("with family_map", 1)[1].split("profile_rows as", 1)[0]
        mapped_codes = re.findall(r"\('[a-z_]+',\s*'[A-Za-z /&-]+',\s*\d+,\s*'([a-z_]+)'\)", mapping_block)
        self.assertEqual(expected, set(mapped_codes))
        self.assertEqual(len(expected), len(mapped_codes))
        self.assertIn("unmapped_review", self.sql)

    def test_family_metrics_are_pooled_from_exact_approved_profile_rows(self) -> None:
        self.assertIn("from reporting.latest_team_dashboard_v2", self.lowered)
        self.assertIn("from reporting.latest_league_dashboard_v2", self.lowered)
        self.assertNotIn("from curated.", self.lowered)
        self.assertNotIn("from ingestion.", self.lowered)
        self.assertIn("analysis.rate_per_1000_v1", self.lowered)
        self.assertNotIn("avg(", self.lowered)
        self.assertIn("count(distinct exposure_hours)", self.lowered)
        self.assertIn("sum(time_loss_injuries)", self.lowered)
        self.assertIn("sum(days_lost)", self.lowered)
        self.assertIn("'subtypes'", self.sql)
        self.assertIn("security definer", self.lowered)
        self.assertIn("set search_path = pg_catalog, analysis", self.lowered)
        self.assertIn(
            "grant execute on function analysis.injury_type_families_from_payload_v1(jsonb) to web_reader;",
            self.lowered,
        )

    def test_public_views_are_scoped_definer_rights_barriers(self) -> None:
        for view in (
            "reporting.latest_team_dashboard_v3",
            "reporting.latest_league_dashboard_v3",
        ):
            self.assertRegex(
                self.lowered,
                rf"create view {re.escape(view)}\s+with \(security_invoker = false, security_barrier = true\)",
            )
            self.assertIn(f"grant select on {view} to web_reader;", self.lowered)


if __name__ == "__main__":
    unittest.main()
