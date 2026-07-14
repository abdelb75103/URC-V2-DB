import unittest
from datetime import datetime

from pipeline.__main__ import (
    activity_context,
    body_location,
    contact_context,
    duplicate_source_row_numbers,
    filled_injury_export_row,
    fit_for_selection_status,
    injury_closed,
    injury_type,
    problem_type,
    recurrence_status,
)
from pipeline.italian_intake_adapters import adapt_exposure_rows, adapt_injury_rows


def mapping_entry(field, value, source, *, supporting=None, source_id="injury", adjudication=None):
    return {
        "canonical_field": field,
        "canonical_value": value,
        "evidence_class": "manual_adjudication" if adjudication else "source_reported",
        "source_evidence": source,
        "supporting_evidence": supporting or {},
        "evidence_source_id": source_id,
        "evidence_sheet": "Sheet1" if source_id == "raw_injury" else "Standardized Data",
        "rule": "test rule",
        "protocol_rule_id": None,
        "adjudication_id": adjudication,
        "specificity_change": "equivalent",
    }


class ItalianIntakeAdapterTests(unittest.TestCase):
    def test_processing_prefers_valid_adapter_overrides_and_rejects_invalid_values(self):
        row = {
            "Problem type": "Injury",
            "Body Part": "Ankle",
            "Orchard Code": "QRA",
            "Injury Tissue Type/s": "Muscle",
            "Adapter Canonical Problem Type": "injury",
            "Adapter Canonical Problem Type Origin": "manual_adjudication:TEST",
            "Adapter Canonical Body Location": "ankle",
            "Adapter Canonical Body Location Origin": "manual_adjudication:TEST",
            "Adapter Canonical Tissue Pathology": "muscle_injury",
            "Adapter Canonical Tissue Pathology Origin": "manual_adjudication:TEST",
            "Adapter Canonical Activity Context": "match",
            "Adapter Canonical Activity Context Origin": "approved_mapping:deterministic_derivation",
            "Adapter Canonical Contact Context": "non_contact",
            "Adapter Canonical Contact Context Origin": "approved_mapping:source_reported",
            "Adapter Canonical Recurrence Status": "first_episode",
            "Adapter Canonical Recurrence Status Origin": "approved_mapping:source_reported",
            "Adapter Canonical Injury Closed": "closed",
            "Adapter Canonical Injury Closed Origin": "approved_mapping:deterministic_derivation",
            "Adapter Canonical Fit For Selection Status": "unknown",
            "Adapter Canonical Fit For Selection Status Origin": "approved_mapping:no_supported_evidence",
        }

        self.assertEqual(("injury", "manual_adjudication:TEST"), problem_type(row))
        self.assertEqual(("ankle", "manual_adjudication:TEST"), body_location(row))
        self.assertEqual(("muscle_injury", "manual_adjudication:TEST"), injury_type(row))
        self.assertEqual(("match", "approved_mapping:deterministic_derivation"), activity_context(row))
        self.assertEqual(("non_contact", "approved_mapping:source_reported"), contact_context(row))
        self.assertEqual(("first_episode", "approved_mapping:source_reported"), recurrence_status(row))
        self.assertEqual((True, "approved_mapping:deterministic_derivation"), injury_closed(row))
        self.assertEqual(
            ("unknown", "approved_mapping:no_supported_evidence"),
            fit_for_selection_status(row, True, "fallback"),
        )

        row["Adapter Canonical Body Location"] = "invented_bucket"
        with self.assertRaisesRegex(SystemExit, "invalid adapter canonical override"):
            body_location(row)

    def test_approved_duplicate_exclusion_leaves_the_retained_original_unflagged(self):
        rows = [
            {"standardised_row_number": "2", "PlayerID": "p", "Date Injured": "01/01/2025"},
            {"standardised_row_number": "3", "PlayerID": "p", "Date Injured": "01/01/2025"},
        ]
        self.assertEqual({2, 3}, duplicate_source_row_numbers(rows, ["PlayerID", "Date Injured"]))
        self.assertEqual(
            set(),
            duplicate_source_row_numbers(rows, ["PlayerID", "Date Injured"], {3}),
        )

    def test_closed_zero_day_without_source_return_does_not_invent_return_date(self):
        row = {
            "PlayerID": "opaque-1",
            "Date Injured": "01/09/2024",
            "Confirmed Return Date": "",
            "Days Injured": "0",
            "Adapter Canonical Injury Closed": "closed",
            "Adapter Canonical Injury Closed Origin": "approved_mapping:deterministic_derivation",
            "Adapter Canonical Fit For Selection Status": "unknown",
            "Adapter Canonical Fit For Selection Status Origin": "approved_mapping:no_supported_evidence",
        }

        output = filled_injury_export_row(row)

        self.assertEqual("Closed", output["Injury Status"])
        self.assertEqual("Unknown", output["Fit for selection"])
        self.assertEqual("", output["Confirmed Return Date"])

    def test_benetton_injury_adapter_applies_explicit_conflicts_and_preserves_raw_evidence(self):
        standard = [{
            "PlayerID": "opaque-1", "DOB": datetime(1990, 1, 1),
            "Problem type": "Injury", "Date Injured": "10/04/2024",
            "Confirmed Return Date": "10/14/2024", "Days Injured": "",
            "Body Part": "Ankle", "Orchard Code": "QRA",
            "Injury Tissue Type/s": "", "Recurrence": "",
        }]
        raw = [{
            "Athlete": "direct-name-never-copy", "Injury Onset": datetime(2024, 10, 4),
            "End of injury": datetime(2024, 10, 14), "Days Injured": 10,
            "Body Part": "Ankle", "Osiics14": "QRA",
            "Injury Tissue Type/s": "Muscle",
            "Recurrence (Recurrence stage)": "New injury (non-recurring)",
        }]
        mapping = {
            "mappings": [
                mapping_entry("problem_type", "injury", {"Problem type": "Injury"}),
                mapping_entry(
                    "body_location", "ankle", {"Body Part": "Ankle"},
                    supporting={"Orchard Code": "QRA"}, adjudication="BENETTON-ADJ",
                ),
            ],
            "adapter_source_mappings": [],
        }

        result = adapt_injury_rows("benetton", standard, raw, mapping)
        row = result.rows[0]
        self.assertEqual("", row["DOB"])
        self.assertEqual("04/10/2024", row["Date Injured"])
        self.assertEqual("14/10/2024", row["Confirmed Return Date"])
        self.assertEqual("10", row["Days Injured"])
        self.assertEqual("Muscle", row["Injury Tissue Type/s"])
        self.assertEqual("New injury (non-recurring)", row["Recurrence"])
        self.assertEqual("ankle", row["Adapter Canonical Body Location"])
        self.assertEqual("manual_adjudication:BENETTON-ADJ", row["Adapter Canonical Body Location Origin"])
        self.assertNotIn("Athlete", row)
        self.assertNotIn("direct-name-never-copy", row.values())

    def test_zebre_problem_type_has_no_generic_injury_fallback(self):
        standard = [
            {"PlayerID": "opaque-1", "DOB": "", "Problem type": "", "Body Part": "Medical", "Orchard Code": "MGXX"},
            {"PlayerID": "opaque-2", "DOB": "", "Problem type": "", "Body Part": "Ankle", "Orchard Code": "AJXX"},
            {"PlayerID": "opaque-3", "DOB": "", "Problem type": "", "Body Part": "Unknown", "Orchard Code": ""},
        ]
        raw = [
            {"Player": "direct-1"}, {"Player": "direct-2"}, {"Player": "direct-3"},
        ]
        mapping = {
            "mappings": [
                mapping_entry("problem_type", "illness", {"Body Part": "Medical"}, adjudication="ZEBRE-ADJ"),
                mapping_entry(
                    "problem_type", "injury", {"Body Part": "Ankle", "Orchard Code": "AJXX"},
                    adjudication="ZEBRE-ADJ",
                ),
            ],
            "adapter_source_mappings": [],
        }

        result = adapt_injury_rows("zebre", standard, raw, mapping)
        self.assertEqual(["illness", "injury", "unknown"], [
            row["Adapter Canonical Problem Type"] for row in result.rows
        ])
        self.assertTrue(all("Player" not in row for row in result.rows))

    def test_exposure_adapter_restores_metrics_without_copying_raw_player_names(self):
        standard = [{
            "Name": "opaque-ben", "name": "", "session date": "",
            "minutes total": "", "distance total": "",
            "HSR > 20 Km/h (m) (5.5 m/s)": "",
            "HSR > 25.2 Km/h (m) (7 m/s)": "",
            "high speed running distance": "", "very high speed running distance": "",
        }]
        raw = [{
            "Name": "direct-name-never-copy", "date": datetime(2024, 9, 1),
            "duration (min)": 90, "distance (m)": 8000,
            "HSR > 20 Km/h (m)": 500, "HSR > 25,2 Km/h (m)": 100,
        }]

        result = adapt_exposure_rows("benetton", standard, raw)
        row = result.rows[0]
        self.assertEqual("opaque-ben", row["name"])
        self.assertEqual("01/09/2024", row["session date"])
        self.assertEqual(90, row["minutes total"])
        self.assertEqual(500, row["high speed running distance"])
        self.assertEqual(100, row["very high speed running distance"])
        self.assertNotIn("direct-name-never-copy", row.values())


if __name__ == "__main__":
    unittest.main()
