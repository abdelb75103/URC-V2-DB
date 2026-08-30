from __future__ import annotations

import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT
    / "supabase/migrations/20260831100000_urc_2025_26_reporting_key_family_correction.sql"
)
REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_reporting_key_family_correction_migration.sql"
)
EVIDENCE = ROOT / "docs/evidence/urc_2025_26_reporting_key_family_correction.json"
MAPPING_CONTRACT_MIGRATION = (
    ROOT
    / "supabase/migrations/20260831101000_urc_2025_26_family_mapping_contract_correction.sql"
)
MAPPING_CONTRACT_REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_family_mapping_contract_correction_migration.sql"
)


class Year2ReportingKeyFamilyCorrectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.raw = MIGRATION.read_text(encoding="utf-8")
        cls.sql = cls.raw.lower()
        cls.registration = REGISTRATION.read_text(encoding="utf-8")

    def test_exact_migration_and_evidence_bytes_are_bound(self) -> None:
        self.assertEqual(
            hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
            "36754c640f808db0dc6e27d58135744005a304ba14cb3be7211b11224335b43f",
        )
        self.assertEqual(
            hashlib.sha256(EVIDENCE.read_bytes()).hexdigest(),
            "d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172",
        )
        self.assertEqual(
            self.registration.count(
                "migration_sha256=36754c640f808db0dc6e27d58135744005a304ba14cb3be7211b11224335b43f"
            ),
            2,
        )

    def test_controlled_codes_are_matched_from_retained_labels(self) -> None:
        for value in (
            "curated.code_lists",
            "controlled.list_name = 'body_location'",
            "controlled.list_name = 'injury_type'",
            "lower(controlled.label) = lower(source.body_location_label)",
            "lower(controlled.label) = lower(source.injury_type_label)",
            "coalesce(body.code, 'unknown')",
            "coalesce(injury_type.code, 'unknown')",
            "coalesce(body.label, 'Unknown')",
            "coalesce(injury_type.label, 'Unknown')",
        ):
            self.assertIn(value, self.raw)
        self.assertIn(
            "lower(btrim(source.diagnosis_label)), '[^a-z0-9]+', '_', 'g'",
            self.raw,
        )

    def test_family_mean_uses_known_duration_denominator(self) -> None:
        for value in (
            "create function analysis.injury_type_families_from_payload_v2",
            "known_duration_time_loss_injuries",
            "round(p.days_lost / p.mean_severity_days)",
            "days_lost / nullif(known_duration_time_loss_injuries, 0)",
            "injury_type_family_2026-08-31_v2",
        ):
            self.assertIn(value, self.raw)
        self.assertNotIn(
            "days_lost / time_loss_injuries else null",
            self.sql,
        )

    def test_snapshot_is_private_immutable_and_additive(self) -> None:
        for value in (
            "team_dashboard_release_candidate_snapshot_v6_20260831_reporting_keys",
            "snapshot_version = '20260831100000'",
            "reporting_classification_2025-26_2026-08-31_v3",
            "injury_lineage_2025-26_2026-08-30_v2",
            "enable row level security",
            "before update or delete",
            "from public, anon, authenticated, web_reader",
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6",
        ):
            self.assertIn(value, self.sql)
        self.assertNotRegex(self.sql, r"(?m)^\s*(update|delete\s+from|truncate)\b")

    def test_migration_gates_exact_scientific_invariants(self) -> None:
        for value in (
            ") <> 16",
            ") <> 1484",
            ") <> 1457",
            ") <> 1460",
            ") <> 877",
            ") <> 731",
            ") <> 19047",
            "family ->> 'code' = 'unmapped_review'",
            "jsonb_array_length(candidate.dashboard -> 'headline') <> 7",
            "candidate.dashboard - array[",
        ):
            self.assertIn(value, self.raw)

    def test_registration_requires_private_complete_candidate(self) -> None:
        lower = self.registration.lower()
        for value in (
            "on conflict (version) do nothing",
            "has_table_privilege",
            "has_function_privilege",
            "injury_lineage_snapshot_version = '20260831100000'",
            "year 2 reporting-key and family correction registration is invalid",
        ):
            self.assertIn(value, lower)

    def test_public_mapping_identity_remains_frozen_in_additive_snapshot(self) -> None:
        migration = MAPPING_CONTRACT_MIGRATION.read_text(encoding="utf-8")
        registration = MAPPING_CONTRACT_REGISTRATION.read_text(encoding="utf-8")
        self.assertEqual(
            hashlib.sha256(MAPPING_CONTRACT_MIGRATION.read_bytes()).hexdigest(),
            "a711d6bdd4af0618c2adafb6b30ca7be03f5251150db799bc43915b62e3fd39f",
        )
        for value in (
            "analysis.injury_type_families_from_payload_v3",
            "injury_type_family_2026-07-21_v1",
            "snapshot_version = '20260831101000'",
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6",
            "candidate.dashboard - 'injury_type_families'",
        ):
            self.assertIn(value, migration)
        self.assertEqual(
            registration.count(
                "migration_sha256=a711d6bdd4af0618c2adafb6b30ca7be03f5251150db799bc43915b62e3fd39f"
            ),
            2,
        )


if __name__ == "__main__":
    unittest.main()
