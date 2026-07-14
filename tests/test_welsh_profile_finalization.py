from __future__ import annotations

import unittest
from copy import deepcopy

from pipeline.welsh_profile_package import (
    CONFIG,
    DECISION_ACTOR,
    DECISION_ACTOR_BASIS,
    DECISION_APPLICATION_VERSION,
    canonical_team_name,
    decision_application_errors,
    validate_saved_decision_state,
)


DECISIONS = [
    {
        "id": "DRAGONS-2024-25-ADJ-002-PROBLEM-TYPE",
        "choices": [
            {"value": "medical_illness_to_illness"},
            {"value": "leave_unknown"},
        ],
    }
]


def state(choice: str = "medical_illness_to_illness") -> dict:
    return {
        "evidence_fingerprint": "a" * 64,
        "selections": {
            DECISIONS[0]["id"]: {
                "choice": choice,
                "selected_at": "2026-07-14T10:00:00+00:00",
            }
        },
    }


def application_record() -> dict:
    outputs = []
    for team_key in CONFIG:
        outputs.append(
            {
                "team_key": team_key,
                "team": canonical_team_name(team_key),
                "evidence_path": f"data/{team_key}/evidence.json",
                "evidence_sha256": "b" * 64,
                "inventory_path": f"data/{team_key}/inventory.json",
                "inventory_sha256": "c" * 64,
                "draft_mapping_path": f"data/{team_key}/mapping.draft.json",
                "draft_mapping_sha256": "d" * 64,
                "mapping_path": f"data/{team_key}/mapping.json",
                "mapping_sha256": "e" * 64,
                "draft_profile_path": f"data/{team_key}/profile.draft.json",
                "draft_profile_sha256": "f" * 64,
                "profile_path": f"data/{team_key}/profile.json",
                "profile_sha256": "0" * 64,
                "validation_status": "PASS",
            }
        )
    return {
        "schema_version": DECISION_APPLICATION_VERSION,
        "run_id": "20260714T120000000000Z-aaaaaaaaaaaa",
        "evidence_fingerprint": "a" * 64,
        "decision_state_path": "data/intake/2024-25/wales/decision_selections.json",
        "decision_state_sha256": "1" * 64,
        "selected_by": DECISION_ACTOR,
        "actor_basis": DECISION_ACTOR_BASIS,
        "actor_evidence_path": (
            "data/intake/2024-25/wales/reviewed/"
            "20260714T120000000000Z-aaaaaaaaaaaa/urc-welsh-e2e-handoff.md"
        ),
        "actor_evidence_sha256": "2" * 64,
        "applied_at": "2026-07-14T10:30:00+00:00",
        "approval_granted": False,
        "applications": [
            {
                "decision_id": DECISIONS[0]["id"],
                "choice": "medical_illness_to_illness",
                "selected_at": "2026-07-14T10:00:00+00:00",
                "selected_by": DECISION_ACTOR,
                "team_key": "dragons",
                "canonical_team": "Dragons RFC",
                "effect": {
                    "canonical_field": "problem_type",
                    "canonical_value": "illness",
                    "source_evidence": {"Body Part": "Medical_illness"},
                },
            }
        ],
        "outputs": outputs,
    }


class WelshProfileFinalizationTests(unittest.TestCase):
    def test_accepts_complete_supported_fingerprint_bound_selection(self) -> None:
        selections = validate_saved_decision_state(
            state(), current_fingerprint="a" * 64, required_decisions=DECISIONS
        )
        self.assertEqual(
            selections[DECISIONS[0]["id"]]["choice"],
            "medical_illness_to_illness",
        )

    def test_rejects_fingerprint_drift(self) -> None:
        with self.assertRaisesRegex(ValueError, "fingerprint"):
            validate_saved_decision_state(
                state(), current_fingerprint="b" * 64, required_decisions=DECISIONS
            )

    def test_rejects_missing_decision(self) -> None:
        incomplete = state()
        incomplete["selections"] = {}
        with self.assertRaisesRegex(ValueError, "incomplete"):
            validate_saved_decision_state(
                incomplete, current_fingerprint="a" * 64, required_decisions=DECISIONS
            )

    def test_rejects_unimplemented_choice(self) -> None:
        with self.assertRaisesRegex(ValueError, "does not implement"):
            validate_saved_decision_state(
                state("leave_unknown"),
                current_fingerprint="a" * 64,
                required_decisions=DECISIONS,
            )

    def application_errors(self, record: dict) -> list[str]:
        return decision_application_errors(
            record,
            state=state(),
            current_fingerprint="a" * 64,
            current_state_sha256="1" * 64,
            required_decisions=DECISIONS,
            validate_actor_file=False,
        )

    def test_application_record_binds_actor_choice_state_and_all_outputs(self) -> None:
        self.assertEqual(self.application_errors(application_record()), [])

    def test_application_record_rejects_missing_application(self) -> None:
        record = application_record()
        record["applications"] = []
        self.assertTrue(any("IDs/cardinality" in item for item in self.application_errors(record)))

    def test_application_record_rejects_forged_state_hash_and_schema(self) -> None:
        record = application_record()
        record["decision_state_sha256"] = "9" * 64
        record["schema_version"] = "unexpected"
        errors = self.application_errors(record)
        self.assertTrue(any("saved decision state" in item for item in errors))
        self.assertTrue(any("schema version" in item for item in errors))

    def test_application_record_rejects_contradictory_choice_or_actor(self) -> None:
        record = deepcopy(application_record())
        record["applications"][0]["choice"] = "leave_unknown"
        record["applications"][0]["selected_by"] = "Unknown"
        errors = self.application_errors(record)
        self.assertTrue(any("contradicts" in item for item in errors))
        self.assertTrue(any("adjudicator" in item for item in errors))

    def test_application_record_rejects_false_paths_and_timestamp(self) -> None:
        record = application_record()
        record["decision_state_path"] = "wrong.json"
        record["actor_evidence_path"] = "wrong.md"
        record["applied_at"] = "not-a-timestamp"
        errors = self.application_errors(record)
        self.assertTrue(any("state path" in item for item in errors))
        self.assertTrue(any("actor evidence" in item for item in errors))
        self.assertTrue(any("applied_at" in item for item in errors))

    def test_application_record_rejects_malformed_outputs_without_crashing(self) -> None:
        for malformed in ("not-a-list", [None]):
            record = application_record()
            record["outputs"] = malformed
            errors = self.application_errors(record)
            self.assertTrue(any("outputs" in item for item in errors))


if __name__ == "__main__":
    unittest.main()
