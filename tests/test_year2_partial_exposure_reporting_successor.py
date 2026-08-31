from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path

from pipeline.season_contracts import YEAR2_2025_26_RELEASE_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
VERSION = "20260831130000"
NAME = "urc_2025_26_partial_exposure_reporting_successor"
MIGRATION = ROOT / "supabase/migrations" / f"{VERSION}_{NAME}.sql"
REGISTRATION = ROOT / "tools/sql" / f"register_{NAME}_migration.sql"
EVIDENCE = ROOT / "docs/evidence/urc_2025_26_partial_exposure_reporting_v1.json"


class Year2PartialExposureReportingSuccessorTests(unittest.TestCase):
    def test_uses_the_corrected_active_zebre_build_and_seals_team_candidates(self) -> None:
        raw = MIGRATION.read_text(encoding="utf-8")

        for token in (
            "urc_2025_26_zebre_corrected_exposure_gate_v1",
            "26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa",
            "b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394",
            "input_representation_correction_2026-07-13_v1",
            "record_version.version_number) = 1",
            "min(record_version.version_number) = 102",
            "active_zebre.team_key = 'zebre'",
            "from curated.exposure active_exposure",
            "count(distinct step.id) = 1",
            "count(distinct pipeline_run.id) = 1",
            "pipeline_run.command = 'process-exposure'",
            "pipeline_run.output_hash = step.output_hash",
            "step.input_count = 6694",
            "'patched_rows' = '976'",
            "'newly_included_rows' = '953'",
            "'retained_exclusions' = '23'",
            "'mapping_sha256' =",
            "'eddb583ddca717e2489d483fd0e8189b0e916ace34c4669bbcdbfb1507cb8dc1'",
            "'profile_sha256' =",
            "'ca11e601021966f5b2b1c8b018d8fbd11cd445cfda2f183ba3145b6e19e15e67'",
            "'adapter_qc_sha256' =",
            "'a8cde7fa8bf7620b567f129311b5063cc85006849ca6c1a94e3e2333eaf77710'",
            "'manifest_sha256' =",
            "'8190b8eaa6d66692dfa27c6da48f6fb3eb20a84ebec7b5522799e13f3156c199'",
            ") = 624",
            ") = 352",
            ") = 953",
            ") = 23",
            "distance_m_clean <= 0 or exposure.distance_m_clean > 20000",
            "active_exposure_placeholders_v2",
            "mean_of_other_14_source_backed_team_hours_v2",
            "team_dashboard_release_candidate_snapshot_v6_20260831130000",
            "Partial Year 2 exposure team candidate snapshot is immutable",
            "injury_lineage_snapshot_version",
            "null::bigint as processing_eligible_injury_count",
            "null::text as reporting_record_version_set_sha256",
            "null::bigint as wrong_problem_type_rule_version_count",
        ):
            self.assertIn(token, raw)
        self.assertIn(
            "and min(source_file.file_sha256) =\n"
            "    '26c058a659823e5c9f818b2525d3daab6c16fd3a4cd0722b7e9c82af0089c1fa'",
            raw,
        )
        self.assertNotIn(
            "min(source_file.file_sha256) =\n"
            "    'b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394'",
            raw,
        )
        for key in ("profile_sha256", "adapter_qc_sha256", "manifest_sha256"):
            self.assertNotIn(
                f"nullif(btrim(pipeline_run.parameters ->> '{key}'), '') is not null",
                raw,
            )

    def test_aggregates_final_releases_without_a_payload_patch(self) -> None:
        raw = MIGRATION.read_text(encoding="utf-8")

        self.assertIn("from analysis.league_member_releases_v6 member", raw)
        self.assertIn("candidate_snapshot_version = '20260831130000'", raw)
        self.assertIn("ready.refreshed_team_count = 3", raw)
        self.assertNotIn("jsonb_set(", raw)
        self.assertIn("source_backed_team_count", raw)
        self.assertIn("temporary_estimate_team_count", raw)
        self.assertIn("distance_contributor_count", raw)
        self.assertIn("pending_source_teams", raw)

    def test_keeps_the_fixed_month_domain_and_nulls_incomplete_rates(self) -> None:
        raw = MIGRATION.read_text(encoding="utf-8")

        self.assertGreaterEqual(raw.count("generate_series(date '2025-09-01', date '2026-06-01'"), 2)
        self.assertIn("'month', to_char(month_start, 'YYYY-MM')", raw)
        self.assertIn("'exposure_contributor_count', exposure_contributor_count", raw)
        self.assertIn("'distance_contributor_count', distance_contributor_count", raw)
        self.assertGreaterEqual(raw.count("exposure_contributor_count = 16 and exposure_hours > 0"), 3)
        self.assertIn("No zero is inferred for a month without a reported exposure value.", raw)

    def test_registration_contract_and_evidence_are_checksum_bound(self) -> None:
        raw = MIGRATION.read_bytes()
        migration_sha256 = hashlib.sha256(raw).hexdigest()
        evidence_sha256 = hashlib.sha256(EVIDENCE.read_bytes()).hexdigest()
        registration = REGISTRATION.read_text(encoding="utf-8")

        self.assertEqual(registration.count(f"migration_sha256={migration_sha256}"), 2)
        self.assertEqual(registration.count(f"evidence_sha256={evidence_sha256}"), 2)
        self.assertEqual(
            registration.count(
                "correction_candidate_sha256="
                "b5ea70e63052da8672012eb4bcecf1925eaa891db912495a01e2c74115c29394"
            ),
            2,
        )
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        migration = next(
            item for item in contract.required_migration_contracts
            if item.version == VERSION
        )
        self.assertEqual(migration.name, NAME)
        self.assertEqual(migration.sha256, migration_sha256)
        self.assertEqual(
            contract.exposure_coverage_evidence_sha256,
            evidence_sha256,
        )
        self.assertEqual(
            contract.league_monthly_view,
            "analysis.urc_2025_26_partial_reporting_league_monthly_v3",
        )
        self.assertEqual(
            json.loads(EVIDENCE.read_text(encoding="utf-8"))["corrected_zebre_gate"],
            {
                "october_source_rows": 624,
                "november_source_rows": 352,
                "included_rows": 953,
                "clean_rule_exclusions": 23,
            },
        )


if __name__ == "__main__":
    unittest.main()
