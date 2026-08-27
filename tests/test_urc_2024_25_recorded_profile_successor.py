import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260827172000_urc_2024_25_recorded_profile_successor.sql"
REGISTRATION = ROOT / "tools/sql/register_urc_2024_25_recorded_profile_successor_migration.sql"
UI = ROOT / "components/dashboard/team-dashboard.tsx"
CHARTS = ROOT / "components/dashboard/charts.tsx"
TYPES = ROOT / "lib/reporting-types.ts"
SCHEMA = ROOT / "lib/reporting.ts"
PIPELINE = ROOT / "pipeline/__main__.py"


class RecordedProfileSuccessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text()
        cls.registration = REGISTRATION.read_text()
        cls.ui = UI.read_text()
        cls.charts = CHARTS.read_text()
        cls.types = TYPES.read_text()
        cls.schema = SCHEMA.read_text()
        cls.pipeline = PIPELINE.read_text()

    def test_registration_binds_exact_migration(self):
        digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        self.assertIn(f"migration_sha256={digest}", self.registration)
        self.assertIn(
            "perform analysis.assert_urc_2024_25_recorded_profile_successor_v1()",
            self.registration.lower(),
        )

    def test_recorded_counts_follow_injury_only_source_rows(self):
        lower = self.migration.lower()
        self.assertIn("count(*)::bigint as recorded_injuries", lower)
        self.assertIn("injury.canonical_problem_type = 'injury'", lower)
        self.assertIn("recorded diagnosis profiles do not match injury-only source rows", lower)
        self.assertIn("recorded profile all row does not reconcile by setting", lower)
        self.assertIn("<> 1662", self.migration)
        self.assertIn("<> 913", self.migration)
        self.assertIn("<> 17575", self.migration)

    def test_reviewed_common_diagnoses_are_pinned(self):
        self.assertIn("dx_lumbar_spine_pain_2022547a07', 41", self.migration)
        self.assertIn("dx_acromioclavicular_joint_injury_1a8d08823b', 39", self.migration)
        self.assertIn("dx_groin_and_adductor_injury_476e2d09eb', 37", self.migration)

    def test_public_contract_carries_optional_recorded_count(self):
        self.assertIn("recorded_injuries?: number", self.types)
        self.assertIn("recorded_injuries: z.number().optional()", self.schema)
        self.assertIn("'recorded_injuries', source.recorded_injuries", self.migration)

    def test_chart_uses_prevalence_heat_map_and_numbered_key(self):
        self.assertIn("row.time_loss_injuries / totalInjuries >= 0.013", self.ui)
        self.assertNotIn("impactRanked.slice(0, 12)", self.ui)
        self.assertIn('<linearGradient id="impact-risk-gradient"', self.charts)
        self.assertIn('fill="url(#impact-risk-gradient)"', self.charts)
        self.assertIn("displayIndex: index + 1", self.charts)
        tooltip = self.charts.split("function ImpactTooltip", 1)[1].split("function formatAxisTick", 1)[0]
        self.assertNotIn("Recorded injuries", tooltip)
        self.assertIn("Total days lost", self.charts)
        self.assertIn("recharts-wrapper:focus", self.charts)

    def test_release_requires_the_successor(self):
        self.assertIn(
            "create materialized view analysis.urc_2024_25_team_profiles_v3",
            self.migration,
        )
        self.assertIn(
            'URC_2024_25_RECORDED_PROFILE_SUCCESSOR_MIGRATION_VERSION = "20260827172000"',
            self.pipeline,
        )
        self.assertIn(
            "URC_2024_25_RECORDED_PROFILE_SUCCESSOR_MIGRATION_VERSION,",
            self.pipeline,
        )


if __name__ == "__main__":
    unittest.main()
