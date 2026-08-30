from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260829230000_urc_2025_26_valid_injury_ingest.sql"
REGISTRATION = ROOT / "tools/sql/register_urc_2025_26_valid_injury_ingest_migration.sql"
INGEST = ROOT / "tools/sql/ingest_urc_2025_26_valid_injury_lineage.sql"
EXECUTOR = ROOT / "pipeline/sql_exec.mjs"
SUCCESSOR_MIGRATION = ROOT / (
    "supabase/migrations/"
    "20260830140000_urc_2025_26_injury_review_triage_successor.sql"
)
SUCCESSOR_REGISTRATION = ROOT / (
    "tools/sql/register_urc_2025_26_injury_review_triage_successor_migration.sql"
)
SUCCESSOR_INGEST = ROOT / (
    "tools/sql/ingest_urc_2025_26_injury_review_triage_successor.sql"
)
SUCCESSOR_VERIFICATION = ROOT / (
    "tools/sql/verify_urc_2025_26_injury_review_triage_successor.sql"
)


class ValidInjuryIngestSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text(encoding="utf-8")
        cls.registration = REGISTRATION.read_text(encoding="utf-8")
        cls.ingest = INGEST.read_text(encoding="utf-8")
        cls.executor = EXECUTOR.read_text(encoding="utf-8")
        cls.migration_sha = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()

    def test_migration_hash_is_bound_in_registration_and_ingest(self):
        self.assertEqual(
            self.migration_sha,
            "f4c5e3986e13a0b3b1a2e4dda6759f1cf476095ecb77e38554d1226936eba62b",
        )
        for sql in (self.registration, self.ingest):
            self.assertIn(f"migration_sha256={self.migration_sha}", sql)

    def test_private_additive_tables_and_rule_are_present(self):
        for name in (
            "lineage.injury_classification_rules_v2",
            "lineage.injury_master_versions_v2",
            "lineage.injury_master_rows_v2",
            "lineage.injury_inclusion_rows_v2",
        ):
            self.assertIn(f"create table {name}", self.migration.lower())
            self.assertIn(f"revoke all on {name}", self.migration.lower())
        self.assertIn("positive clinical duration alone", self.migration.lower())
        versions = self.migration.lower().split(
            "create table lineage.injury_master_versions_v2", 1
        )[1]
        self.assertRegex(
            versions,
            r"season\s+text\s+not\s+null\s+unique\s+check\s*\(season\s*=\s*'2025-26'\)",
        )
        self.assertNotRegex(
            self.migration.lower(), r"(?m)^\s*(drop|truncate|delete from|update)\b"
        )

    def test_master_shape_and_processing_fields_stay_separate(self):
        for header in (
            "Reporting At Club",
            "TimeLoss vs Medical Attention",
            "Specific Diagnosis",
        ):
            self.assertIn(f"'{header}'", self.migration)
        for field in (
            "clinical_duration_days",
            "time_loss_days",
            "classification_basis",
            "return_date_basis",
            "open_status",
            "participation_restriction_evidence",
            "unrestricted_participation_evidence",
        ):
            self.assertIn(field, self.migration)
        self.assertIn("lineage.valid_urc_injury_master_row_v2(row_values)", self.migration)

    def test_ingest_is_first_valid_private_lineage_only(self):
        lower = self.ingest.lower()
        self.assertIn("_pipeline_params_attestation", lower)
        self.assertIn(
            "7a11596713ce730a4404039a958d8a8c10cca2092115a8fa40d951e22940e8c2",
            lower,
        )
        self.assertIn("load payload sha-256 is not the accepted byte digest", lower)
        self.assertIn("a valid 2025-26 injury lineage already exists", lower)
        self.assertIn("the exact 16-team roster", lower)
        self.assertIn("master-to-inclusion bridge is invalid", lower)
        self.assertIn("frozen 2024-25 lineage changed", lower)
        self.assertIn("and not unrestricted_participation_evidence", lower)
        self.assertIn("return_date_basis <> 'missing_open_record'", lower)
        self.assertNotRegex(
            lower,
            r"insert\s+into\s+(curated|reporting|analysis|ingestion|processing)\.",
        )

    def test_executor_attests_payload_bytes_before_connecting(self):
        self.assertIn('import { createHash } from "node:crypto"', self.executor)
        self.assertIn("PIPELINE_PARAMS_SHA256", self.executor)
        self.assertIn("_pipeline_params_attestation", self.executor)
        self.assertLess(
            self.executor.index('createHash("sha256")'),
            self.executor.index("await client.connect()"),
        )

    def test_no_reader_grant_or_release_operation(self):
        combined = f"{self.migration}\n{self.registration}\n{self.ingest}".lower()
        self.assertNotRegex(combined, r"grant\s+select.*web_reader")
        self.assertNotRegex(combined, r"insert\s+into\s+reporting\..*release")
        self.assertNotRegex(combined, r"insert\s+into\s+curated\.exposure")


class InjuryReviewTriageSuccessorSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = SUCCESSOR_MIGRATION.read_text(encoding="utf-8")
        cls.registration = SUCCESSOR_REGISTRATION.read_text(encoding="utf-8")
        cls.ingest = SUCCESSOR_INGEST.read_text(encoding="utf-8")
        cls.verification = SUCCESSOR_VERIFICATION.read_text(encoding="utf-8")
        cls.migration_sha = hashlib.sha256(SUCCESSOR_MIGRATION.read_bytes()).hexdigest()

    def test_migration_hash_is_bound_in_registration_and_ingest(self):
        self.assertEqual(
            self.migration_sha,
            "76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a",
        )
        for sql in (self.registration, self.ingest):
            self.assertIn(f"migration_sha256={self.migration_sha}", sql)

    def test_successor_is_private_additive_and_immutable(self):
        lower = self.migration.lower()
        for name in (
            "lineage.injury_classification_rules_v3",
            "lineage.injury_master_versions_v3",
            "lineage.injury_master_rows_v3",
            "lineage.injury_inclusion_rows_v3",
        ):
            self.assertIn(f"create table {name}", lower)
            self.assertIn(f"revoke all on {name}", lower)
            self.assertRegex(
                lower,
                rf"before update or delete on {re.escape(name)}",
            )
        self.assertNotRegex(
            lower,
            r"(?m)^\s*(drop|truncate|delete\s+from|update)\b",
        )
        self.assertNotRegex(lower, r"grant\s+select.*web_reader")

    def test_predecessor_and_payload_are_exactly_bound(self):
        lower = self.ingest.lower()
        self.assertIn("bab7731d-975b-5d49-a34c-6acc6b0c8c94", lower)
        self.assertIn(
            "111328427560503939a66e845d4a6e0fb8fa606f9dbf4a6f508aa0df04cab637",
            lower,
        )
        self.assertIn("_pipeline_params_attestation", lower)
        self.assertIn(
            "2025-26 injury successor predecessor state does not match live",
            lower,
        )
        self.assertIn("to_jsonb(predecessor) - 'version_id'", lower)
        self.assertNotRegex(
            lower,
            r"(?m)^\s*(update|delete\s+from|truncate)\s+lineage\."
            r"injury_(master_versions|master_rows|inclusion_rows)_v2\b",
        )

    def test_load_clones_full_lineage_and_substitutes_only_delta_rows(self):
        lower = self.ingest.lower()
        self.assertIn("insert into lineage.injury_master_rows_v3", lower)
        self.assertIn("from lineage.injury_master_rows_v2 predecessor", lower)
        self.assertIn("jsonb_populate_record", lower)
        self.assertIn("else delta.value -> 'successor'", lower)
        self.assertIn("differs outside the accepted delta", lower)
        for contract in (
            "affected_row_count <> 1975",
            "changed_master_row_count <> 438",
            "changed_classification_row_count <> 162",
            "changed_duration_row_count <> 71",
        ):
            self.assertIn(contract, lower)
        self.assertIn(
            "successor.row_values <> predecessor.row_values) <> 438",
            self.verification.lower(),
        )

    def test_inclusion_membership_and_protected_boundaries_are_preserved(self):
        lower = self.ingest.lower()
        self.assertIn("insert into lineage.injury_inclusion_rows_v3", lower)
        self.assertIn("injury successor inclusion bridge is invalid", lower)
        self.assertIn("frozen 2024-25 lineage changed", lower)
        self.assertNotRegex(
            lower,
            r"insert\s+into\s+(curated|reporting|analysis|ingestion|processing)\.",
        )

    def test_successor_binds_all_accepted_artefact_hashes(self):
        for digest in (
            "2b5e2243bfc912fac1561789e9327987d058a5543233f068f3bef9928c397670",
            "7f890764273b1a8e389fd8c4b9881f41c76bd82926d8a7af9dc87e79bf17b4ab",
            "f9e8d82998232a2e7e6f7325f319a685546197b4f4c3ff022f366fafa854c78a",
        ):
            self.assertIn(digest, self.ingest)
        for field in (
            "master_csv_sha256",
            "inclusion_csv_sha256",
            "classification_evidence_sha256",
        ):
            self.assertIn(f"value ->> '{field}'", self.ingest)


if __name__ == "__main__":
    unittest.main()
