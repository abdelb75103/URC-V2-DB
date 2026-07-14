import unittest

from pipeline.italian_profile_package import (
    BENETTON_BODY_LABELS,
    DECISION_EVIDENCE_FINGERPRINT,
    INTAKE,
    load,
    load_decision_selections,
    mappings,
    sheet,
)


SELECTIONS = {
    "BENETTON-2024-25-ADJ-001-TAXONOMY-CONFLICTS": {
        "choice": "prefer_explicit_source_label",
    },
    "ZEBRE-2024-25-ADJ-001-PROBLEM-TYPE": {
        "choice": "medical_to_illness",
    },
}


class ItalianProfileDecisionTests(unittest.TestCase):
    def injury_sheet(self, team_key: str) -> dict:
        evidence = load(INTAKE / team_key / "mechanical_evidence.v1.json")
        return sheet(evidence, "injury")

    def test_saved_choices_are_bound_to_the_reviewed_predecision_fingerprint(self):
        state = load(INTAKE / "italy" / "decision_selections.json")
        self.assertEqual(DECISION_EVIDENCE_FINGERPRINT, state["evidence_fingerprint"])
        self.assertEqual(SELECTIONS, {
            decision_id: {"choice": selection["choice"]}
            for decision_id, selection in load_decision_selections().items()
        })

    def test_benetton_explicit_labels_override_nine_conflicts_with_audit_evidence(self):
        injury_sheet = self.injury_sheet("benetton")
        entries = mappings("benetton", injury_sheet, SELECTIONS)
        conflicts = [
            entry for entry in entries
            if entry.get("adjudication_id")
            == "BENETTON-2024-25-ADJ-001-TAXONOMY-CONFLICTS"
        ]

        self.assertEqual(8, len(conflicts))
        self.assertTrue(all(entry["canonical_value"] != "unknown" for entry in conflicts))
        self.assertTrue(all(entry["evidence_class"] == "manual_adjudication" for entry in conflicts))
        body_conflicts = [entry for entry in conflicts if entry["canonical_field"] == "body_location"]
        pair_counts = {
            tuple(item["values"]): item["count"]
            for item in injury_sheet["joint_category_frequencies"]
            if item["fields"] == ["Body Part", "Orchard Code"]
        }
        self.assertEqual(6, len(body_conflicts))
        self.assertEqual(7, sum(
            pair_counts[(entry["source_evidence"]["Body Part"], entry["supporting_evidence"]["Orchard Code"])]
            for entry in body_conflicts
        ))
        self.assertTrue(all(
            entry["canonical_value"] == BENETTON_BODY_LABELS[entry["source_evidence"]["Body Part"]]
            for entry in body_conflicts
        ))
        tissue_conflicts = [entry for entry in conflicts if entry["canonical_field"] == "tissue_pathology"]
        self.assertEqual({"MAN", "QH2"}, {entry["supporting_evidence"]["Osiics14"] for entry in tissue_conflicts})
        self.assertTrue(all(entry["canonical_value"] == "muscle_injury" for entry in tissue_conflicts))
        self.assertTrue(
            all(entry["source_evidence"] == {"Injury Tissue Type/s": "Muscle"} for entry in tissue_conflicts)
        )

    def test_zebre_medical_is_illness_and_injury_requires_exact_retained_evidence(self):
        injury_sheet = self.injury_sheet("zebre")
        entries = mappings("zebre", injury_sheet, SELECTIONS)
        problem_type = [entry for entry in entries if entry["canonical_field"] == "problem_type"]
        illness = [entry for entry in problem_type if entry["canonical_value"] == "illness"]
        injuries = [entry for entry in problem_type if entry["canonical_value"] == "injury"]

        self.assertEqual(1, len(illness))
        self.assertEqual({"Body Part": "Medical"}, illness[0]["source_evidence"])

        expected_pairs = {
            tuple(item["values"])
            for item in injury_sheet["joint_category_frequencies"]
            if item["fields"] == ["Body Part", "Orchard Code"]
            and item["values"][0] != "Medical"
            and item["values"][1]
        }
        actual_pairs = {
            (entry["source_evidence"]["Body Part"], entry["source_evidence"]["Orchard Code"])
            for entry in injuries
        }
        self.assertEqual(expected_pairs, actual_pairs)
        self.assertNotIn("Medical", {body for body, _ in actual_pairs})
        self.assertTrue(all(set(entry["source_evidence"]) == {"Body Part", "Orchard Code"} for entry in injuries))

    def test_compiled_profiles_are_unapproved_adapter_required_envelopes(self):
        for team_key in ("benetton", "zebre"):
            profile = load(INTAKE / team_key / "team_intake_profile.v2.draft.json")
            self.assertEqual("adapter_required", profile["decision"])
            self.assertEqual([], profile["unresolved_adjudication_ids"])
            self.assertEqual("pending", profile["approval_status"])
            self.assertIsNone(profile["approved_by"])
            self.assertEqual([], profile["approved_input_sha256s"])


if __name__ == "__main__":
    unittest.main()
