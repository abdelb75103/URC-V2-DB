from __future__ import annotations

import csv
import hashlib
import inspect
import json
import unittest
from pathlib import Path

from pipeline.__main__ import release_league


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260722130000_osiics_exact_reporting_classification.sql"
MAPPING = ROOT / "docs/evidence/osiics_exact_ioc_mapping_2024-25.csv"
MULTI_TYPE = ROOT / "docs/evidence/osiics_multi_type_diagnosis_2024-25.csv"
EVIDENCE = ROOT / "docs/evidence/osiics_exact_mapping_2024-25.json"


class OsiicsExactReportingClassificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text()
        with MAPPING.open() as handle:
            cls.mapping_rows = list(csv.DictReader(handle))
        with MULTI_TYPE.open() as handle:
            cls.multi_type_rows = list(csv.DictReader(handle))
        cls.evidence = json.loads(EVIDENCE.read_text())
        cls.release_source = inspect.getsource(release_league)

    def test_mapping_catalogue_is_exact_bounded_and_codebook_bound(self) -> None:
        self.assertEqual(len(self.mapping_rows), 49)
        self.assertEqual(sum(int(row["expected_live_time_loss_cases"]) for row in self.mapping_rows), 108)
        self.assertEqual(len({row["source_code"] for row in self.mapping_rows}), 49)
        self.assertEqual(
            self.evidence["official_reference"]["official_workbook_sha256"],
            "8bfeab660942f9ff7a25ebeb42544c231d611365fb9ee36cec27233bc82157c5",
        )
        self.assertEqual(
            self.evidence["mapping_catalogue"]["sha256"],
            hashlib.sha256(MAPPING.read_bytes()).hexdigest(),
        )
        counts = self.evidence["expected_live_time_loss_counts"]
        self.assertEqual(counts["exact_code_candidates"], 108)
        self.assertEqual(counts["explicit_text_candidates"], 12)
        self.assertEqual(counts["multi_type_diagnosis_candidates"], 1)
        self.assertEqual(counts["unknown_after"], 124)
        self.assertEqual(self.multi_type_rows[0]["candidate_injury_types"], "muscle_injury;tendinopathy")
        self.assertEqual(self.multi_type_rows[0]["analysis_primary_type"], "nonspecific")
        self.assertEqual(
            self.evidence["multi_type_catalogue"]["sha256"],
            hashlib.sha256(MULTI_TYPE.read_bytes()).hexdigest(),
        )

    def test_nonspecific_and_unsupported_codes_are_not_promoted(self) -> None:
        mapped = {row["source_code"] for row in self.mapping_rows}
        self.assertIn("FPL", mapped)
        self.assertTrue({"NPM", "QPS", "FZ1", "KZZ", "LZ1"}.isdisjoint(mapped))
        self.assertTrue({"#REF!", "BXXX", "GTDT", "KTQS"}.isdisjoint(mapped))

    def test_migration_preserves_original_values_and_requires_body_agreement(self) -> None:
        self.assertIn("create view analysis.osiics_exact_ioc_mapping_v1", self.sql)
        self.assertIn("analysis.injury_cohort_by_build_season_bound_v3", self.sql)
        self.assertIn("mapped_body_location_code = e.effective_body_location_code", self.sql)
        self.assertIn("e.injury_type_code = 'unknown'", self.sql)
        self.assertIn("mapped_from_exact_osiics_code", self.sql)
        self.assertIn("create view analysis.osiics_multi_type_diagnosis_v1", self.sql)
        self.assertIn("'muscle_injury;tendinopathy','nonspecific'", self.sql)
        self.assertIn("create view analysis.season_bound_effective_injury_profiles_v4", self.sql)
        self.assertIn("e.orchard_code <> 'QPS'", self.sql)
        self.assertNotIn(
            "e.clinical_evidence ~ '(muscle (strain|tear|rupture|injury)|\\mstrain(ed)?\\M|hamstring",
            self.sql,
        )
        self.assertNotIn("update curated.injuries", self.sql.lower())
        self.assertNotIn("delete from", self.sql.lower())

    def test_successor_release_contract_is_version_bound_and_rollback_safe(self) -> None:
        self.assertIn("reporting_classification_2026-07-22_v2", self.sql)
        self.assertIn("create view analysis.team_dashboard_release_candidates_v5", self.sql)
        self.assertIn("create view analysis.league_dashboard_release_candidates_v5", self.sql)
        self.assertIn("analysis.team_dashboard_release_candidates_v5", self.release_source)
        self.assertIn("analysis.league_dashboard_release_candidates_v5", self.release_source)
        self.assertIn(
            '("v3", "reporting_classification_2026-07-22_v2", "season_bound_2026-07-20_v1")',
            self.release_source,
        )

    def test_audit_and_output_gates_are_exact(self) -> None:
        source = (ROOT / "pipeline/__main__.py").read_text()
        self.assertIn("--expected-migration-sha256", source)
        fingerprint_gate = source.split("live_rows = query_sql", 1)[1].split("unknown_rows = query_sql", 1)[0]
        self.assertIn("join curated.injuries i on i.source_row_id=sr.id", fingerprint_gate)
        self.assertNotIn("injury_cohort_by_build_season_bound_v3", fingerprint_gate)
        self.assertIn("OSIICS successor matches % of 121 reviewed row outcomes", source)
        self.assertIn("cohort_count <> 1120 or unknown_count <> 124 or changed_count <> 121", source)
        write_contract = source.split("values ('OSIICS-01'", 1)[1].split("do $$", 1)[0]
        self.assertNotIn("on conflict", write_contract.lower())
        self.assertIn("drop constraint rule_adjudications_migration_version_check", self.sql)
        self.assertIn("'20260720150000', '20260722130000'", self.sql)


if __name__ == "__main__":
    unittest.main()
