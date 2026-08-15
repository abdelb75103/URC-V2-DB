import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs" / "evidence" / "urc_2025_26_manual_checks.json"


class Year2ManualChecksEvidenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.raw = EVIDENCE.read_text(encoding="utf-8")
        cls.evidence = json.loads(cls.raw)

    def test_authorised_recovery_closes_only_the_encrypted_file_access_gap(self) -> None:
        recovery = self.evidence["source_completeness"]["encrypted_sources"]
        self.assertEqual(recovery["recovery_status"], "authorised_recovery_completed")
        self.assertEqual(recovery["total_files"], 13)
        self.assertEqual(recovery["recovered_and_verified_files"], 13)
        self.assertEqual(recovery["unresolved_encrypted_files"], 0)
        self.assertTrue(recovery["raw_corpus_unchanged_after_recovery"])
        self.assertTrue(recovery["codebook_unchanged_after_recovery"])
        self.assertFalse(recovery["candidate_rows_are_ingest_approved"])

        teams = {record["team"]: record for record in recovery["teams"]}
        self.assertEqual(
            {team: record["protected_candidate_injury_rows"] for team, record in teams.items()},
            {"Dragons": 140, "Ospreys": 154, "Scarlets": 99},
        )
        self.assertEqual(
            sum(record["protected_candidate_injury_rows"] for record in teams.values()),
            recovery["protected_candidate_injury_rows"],
        )
        self.assertEqual(teams["Ospreys"]["zero_evidence_risk"], "resolved_by_authorised_recovery")
        self.assertEqual(teams["Ospreys"]["completeness_status"], "not_yet_adjudicated")
        self.assertTrue(all(record["decision"] == "adjudication_required" for record in teams.values()))
        self.assertTrue(all(record["ingest_ready"] is False for record in teams.values()))

    def test_release_and_profile_gates_remain_closed(self) -> None:
        self.assertEqual(self.evidence["release_eligibility"], "blocked")
        self.assertEqual(self.evidence["profile_and_semantics"]["ingest_ready_teams"], 0)
        self.assertEqual(self.evidence["profile_and_semantics"]["adjudication_required_teams"], 16)
        recovery = self.evidence["source_completeness"]["encrypted_sources"]
        self.assertEqual(
            set(recovery["recovery_does_not_imply"]),
            {"source_completeness", "profile_or_mapping_approval", "ingest_authorisation"},
        )
        self.assertIn("database_ingest", self.evidence["forbidden_while_blocked"])
        self.assertIn("release_approval_or_promotion", self.evidence["forbidden_while_blocked"])

    def test_committed_evidence_contains_no_credential_or_private_path(self) -> None:
        lowered = self.raw.lower()
        self.assertNotIn("password", lowered)
        self.assertNotIn("/users/", lowered)
        self.assertNotIn("exhausted_no_authorised_password", lowered)


if __name__ == "__main__":
    unittest.main()
