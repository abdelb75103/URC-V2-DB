import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260827170000_urc_2024_25_setting_profile_successor.sql"
REGISTRATION = ROOT / "tools/sql/register_urc_2024_25_setting_profile_successor_migration.sql"
UI = ROOT / "components/dashboard/team-dashboard.tsx"
CHARTS = ROOT / "components/dashboard/charts.tsx"


class SettingProfileSuccessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text()
        cls.registration = REGISTRATION.read_text()
        cls.ui = UI.read_text()
        cls.charts = CHARTS.read_text()

    def test_registration_binds_exact_migration(self):
        digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        self.assertIn(f"migration_sha256={digest}", self.registration)
        self.assertIn("perform analysis.assert_urc_2024_25_setting_profile_successor_v1()", self.registration.lower())

    def test_setting_rows_use_correct_denominators_and_explicit_all_rollup(self):
        self.assertIn("union all select 'all'::text", self.migration.lower())
        self.assertIn("when 'match' then exposure.match_hours", self.migration.lower())
        self.assertIn("when 'training' then exposure.training_hours", self.migration.lower())
        self.assertIn("when 'all' then exposure.all_hours", self.migration.lower())
        self.assertIn("'injury_type_families',", self.migration)
        self.assertIn("analysis.injury_type_families_from_payload_v1(profiles.rows)", self.migration)

    def test_diagnosis_is_injury_only_and_headlines_are_pinned(self):
        self.assertIn("where injury.canonical_problem_type = 'injury'", self.migration.lower())
        self.assertIn("published diagnosis totals do not match injury-only source rows", self.migration.lower())
        self.assertIn("<> 1662", self.migration)
        self.assertIn("<> 913", self.migration)
        self.assertIn("<> 17575", self.migration)

    def test_dashboard_controls_are_independent(self):
        for name in ("showInjuries", "showTlInjuries", "showOverallIncidence", "showTlIncidence"):
            self.assertIn(name, self.ui)
            self.assertIn(name, self.charts)
        self.assertIn('ariaLabel="Injuries by month"', self.ui)
        self.assertIn('ariaLabel="Overall incidence by month"', self.ui)
        self.assertIn("effectiveSeveritySetting", self.ui)
        self.assertIn("effectiveContactSetting", self.ui)

    def test_knee_ligament_boundary_excludes_other_joints(self):
        helper = self.ui[self.ui.index("function isKneeLigamentDiagnosis"):self.ui.index("function rankedLaneCodes")]
        self.assertIn("row.code.startsWith('dx_acl_')", helper)
        self.assertIn("row.code.startsWith('dx_mcl_')", helper)
        self.assertIn("row.code.startsWith('dx_pcl_')", helper)
        self.assertIn("knee posterolateral corner", helper)
        self.assertNotIn("value.includes('collateral ligament')", helper)
        self.assertNotIn("ankle", helper)
        self.assertNotIn("elbow", helper)


if __name__ == "__main__":
    unittest.main()
