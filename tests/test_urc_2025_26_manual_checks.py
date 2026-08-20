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

    def test_authorised_recovery_and_updated_sources_are_reconciled(self) -> None:
        recovery = self.evidence["source_completeness"]["encrypted_sources"]
        self.assertEqual(recovery["recovery_status"], "authorised_recovery_completed")
        self.assertEqual(recovery["total_files"], 13)
        self.assertEqual(recovery["recovered_and_verified_files"], 13)
        self.assertEqual(recovery["unresolved_encrypted_files"], 0)
        self.assertTrue(recovery["raw_corpus_unchanged_after_recovery"])
        self.assertFalse(recovery["candidate_rows_are_ingest_approved"])

        teams = {record["team"]: record for record in recovery["teams"]}
        self.assertEqual(
            {team: record["protected_candidate_injury_rows"] for team, record in teams.items()},
            {"Dragons": 140, "Ospreys": 154, "Scarlets": 99},
        )
        self.assertEqual(sum(record["protected_candidate_injury_rows"] for record in teams.values()), 393)

        updates = self.evidence["source_completeness"]["updated_exposure_sources"]
        self.assertEqual(updates["ospreys"]["source_rows"], 6965)
        self.assertEqual(updates["ospreys"]["eligible_rows"], 5308)
        self.assertEqual(updates["ospreys"]["excluded_rows"], 1657)
        self.assertEqual(
            updates["ospreys"]["eligible_rows"] + updates["ospreys"]["excluded_rows"],
            updates["ospreys"]["source_rows"],
        )
        self.assertEqual(updates["ospreys"]["identity_dependent_metrics"], "not_produced")
        self.assertEqual(updates["glasgow"]["source_lineage_rows"], 54668)
        self.assertEqual(updates["glasgow"]["session_candidate_rows"], 9600)
        self.assertEqual(updates["glasgow"]["unknown_identity_rows"], 321)
        self.assertEqual(updates["glasgow"]["identity_dependent_metrics"], "suppressed")
        self.assertEqual(updates["glasgow"]["last_observed_date"], "2026-06-05")
        self.assertEqual(updates["glasgow"]["missing_period"], "2026-06-06_to_2026-06-30")

    def test_release_gate_is_only_waiting_for_the_exact_profile_signature(self) -> None:
        self.assertEqual(
            self.evidence["release_eligibility"],
            "blocked_pending_exact_checksum_profile_signature",
        )
        self.assertEqual(self.evidence["profile_and_semantics"]["ingest_ready_teams"], 0)
        self.assertEqual(self.evidence["profile_and_semantics"]["approval_ready_teams"], 16)
        self.assertEqual(self.evidence["profile_and_semantics"]["signed_teams"], 0)
        envelope = self.evidence["profile_and_semantics"]["protected_v8_envelope"]
        self.assertEqual(envelope["teams"], 16)
        self.assertEqual(envelope["injury_rows"], 10786)
        self.assertEqual(envelope["exposure_rows"], 110812)
        self.assertEqual(envelope["intake_gate_validation_status"], "pass")
        self.assertEqual(
            envelope["root_manifest_sha256"],
            "ab54238d226a57045addef923103cefa3c5ebde763ebb0d3d74e650e430ad499",
        )
        self.assertEqual(
            envelope["root_file_set_sha256"],
            "c8c80a1dd277c9944f80045ce340113a458a444942e24104c600dad3345e6d12",
        )
        sessions = self.evidence["profile_and_semantics"]["proved_session_exposure_grain"]
        weekly = self.evidence["profile_and_semantics"]["proved_weekly_exposure_grain"]
        self.assertEqual(len(sessions), 11)
        self.assertEqual(len(weekly), 5)
        self.assertFalse(set(sessions) & set(weekly))
        self.assertIn("database_ingest", self.evidence["forbidden_while_blocked"])
        self.assertIn("release_approval_or_promotion", self.evidence["forbidden_while_blocked"])

    def test_unknown_and_missing_evidence_is_never_fabricated(self) -> None:
        identity = self.evidence["identity_gate"]
        self.assertFalse(identity["identity_allocation_for_ambiguous_or_unproved_rows"])
        self.assertEqual(identity["glasgow_ambiguous_rows_retained_unknown"], 321)
        self.assertEqual(identity["ospreys_rows_retained_unknown"], 6965)
        limitations = " ".join(self.evidence["coverage_gaps_and_limitations"]).lower()
        self.assertIn("no average, placeholder, fabricated date, fabricated identity", limitations)

    def test_committed_evidence_contains_no_credential_or_private_path(self) -> None:
        lowered = self.raw.lower()
        self.assertNotIn("password", lowered)
        self.assertNotIn("/users/", lowered)
        self.assertNotIn("abdel", lowered)
        self.assertNotIn("urc-v2-db-private", lowered)
        self.assertNotIn("exhausted_no_authorised_password", lowered)


if __name__ == "__main__":
    unittest.main()
