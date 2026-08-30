from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "consolidate_2025_26_injuries",
    ROOT / "tools/consolidate_2025_26_injuries.py",
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def row(**overrides):
    values = {header: "" for header in MODULE.CANONICAL_HEADERS}
    values.update(
        {
            "Team": "Cardiff",
            "PlayerID": "Ath_1",
            "Problem type": "Injury",
            "Date Injured": "01/09/2025",
        }
    )
    values.update(overrides)
    return values


class ClassificationSuccessorTests(unittest.TestCase):
    def test_generic_evidence_csv_does_not_require_master_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.csv"
            path.write_text("Source Row,Final Classification\n2,Time Loss\n", encoding="utf-8")
            headers, rows = MODULE.read_dict_csv(path)
        self.assertEqual(headers, ["Source Row", "Final Classification"])
        self.assertEqual(rows, [{"Source Row": "2", "Final Classification": "Time Loss"}])

    def test_na_duration_is_missing_not_zero(self):
        self.assertIsNone(MODULE.parse_days("NA"))

    def test_explicit_medical_attention_wins_over_positive_duration(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "TimeLoss vs Medical Attention": "Medical Attention",
                    "Days Injured": "5",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertEqual(result["clinical_duration_days"], 5)
        self.assertIsNone(result["time_loss_days"])

    def test_explicit_time_loss_zero_day_uses_frozen_zero_day_precedence(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "TimeLoss vs Medical Attention": "Time Loss",
                    "Days Injured": "0",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertEqual(result["classification_basis"], "reported_zero_days")
        self.assertTrue(result["source_conflict"])
        self.assertFalse(result["review_required"])
        self.assertIsNone(result["time_loss_days"])

    def test_explicit_time_loss_same_day_return_is_medical_attention(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "01/09/2025",
                    "Days Injured": "0",
                    "TimeLoss vs Medical Attention": "Time Loss",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertEqual(result["classification_basis"], "same_or_next_day_return")
        self.assertTrue(result["source_conflict"])
        self.assertFalse(result["review_required"])

    def test_explicit_time_loss_next_day_return_is_medical_attention(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "02/09/2025",
                    "Days Injured": "0",
                    "TimeLoss vs Medical Attention": "Time Loss",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertFalse(result["review_required"])

    def test_scottish_inclusive_one_day_duration_is_accepted(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "03/09/2025",
                    "Days Injured": "1",
                    "TimeLoss vs Medical Attention": "Time Loss",
                }
            ),
            {},
            source_group="scotland",
        )
        self.assertFalse(result["source_conflict"])
        self.assertNotIn(
            "reported_duration_conflicts_with_dates",
            result["review_reasons"],
        )

    def test_scottish_difference_above_one_is_resolved_from_dates(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "05/09/2025",
                    "Days Injured": "1",
                    "TimeLoss vs Medical Attention": "Time Loss",
                }
            ),
            {},
            source_group="scotland",
        )
        self.assertEqual(result["clinical_duration_days"], 4)
        self.assertEqual(result["row_values"]["Days Injured"], "4")
        self.assertTrue(result["source_conflict"])
        self.assertFalse(result["review_required"])

    def test_non_scottish_duration_disagreement_is_resolved_from_dates(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "10/09/2025",
                    "Days Injured": "3",
                    "TimeLoss vs Medical Attention": "Time Loss",
                }
            ),
            {},
            source_group="wales",
        )
        self.assertEqual(result["clinical_duration_days"], 9)
        self.assertEqual(result["row_values"]["Days Injured"], "9")
        self.assertEqual(
            result["clinical_duration_basis"],
            "resolved_from_dates",
        )
        self.assertTrue(result["source_conflict"])
        self.assertFalse(result["review_required"])

    def test_excluded_scottish_one_day_difference_stays_in_audit_only(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "03/09/2025",
                    "Days Injured": "1",
                    "TimeLoss vs Medical Attention": "Time Loss",
                    "Exclusion Reason": "Outside official analysis window",
                }
            ),
            {},
            source_group="scotland",
        )
        self.assertTrue(result["source_conflict"])
        self.assertFalse(result["review_required"])

    def test_valid_fit_for_selection_date_is_time_loss_evidence(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Fit For Selection Date": "05/09/2025",
                    "Confirmed Return Date": "05/09/2025",
                    "Days Injured": "4",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(
            result["classification_basis"],
            "source_fit_for_selection_date",
        )
        self.assertTrue(result["participation_restriction_evidence"])

    def test_zebre_static_closing_date_is_time_loss_evidence(self):
        result = MODULE.derive_row(
            "zebre_days_lost",
            row(**{"Confirmed Return Date": "18/09/2025"}),
            {"Closure Provenance": "authoritative source static closing date"},
        )
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(result["classification_basis"], "source_static_closing_date")
        self.assertEqual(result["clinical_duration_days"], 17)
        self.assertEqual(result["time_loss_days"], 17)

    def test_excluded_row_keeps_conflict_but_does_not_require_review(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "31/08/2025",
                    "Exclusion Reason": "Outside official analysis window",
                }
            ),
            {},
        )
        self.assertTrue(result["source_conflict"])
        self.assertTrue(result["review_reasons"])
        self.assertFalse(result["review_required"])

    def test_irfu_modified_participation_is_time_loss(self):
        result = MODULE.derive_row(
            "irfu_restriction",
            row(**{"Days Injured": "3", "TimeLoss vs Medical Attention": "Time Loss"}),
            {"Source Modified Days": "3", "Source Closure Status": "TRUE"},
        )
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(result["classification_basis"], "source_participation_restriction")
        self.assertEqual(result["time_loss_days"], 3)

    def test_irfu_zero_reported_days_are_authoritative_medical_attention(self):
        result = MODULE.derive_row(
            "irfu_restriction",
            row(
                **{
                    "Days Injured": "0",
                    "TimeLoss vs Medical Attention": "Medical Attention",
                }
            ),
            {"Source Modified Days": "9", "Source Closure Status": "TRUE"},
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertEqual(result["classification_basis"], "source_reported_zero_days")
        self.assertFalse(result["participation_restriction_evidence"])
        self.assertEqual(result["row_values"]["Confirmed Return Date"], "")
        self.assertIsNone(result["return_date"])
        self.assertFalse(result["review_required"])

    def test_irfu_display_class_is_not_qualifying_source_evidence(self):
        result = MODULE.derive_row(
            "irfu_restriction",
            row(
                **{
                    "Days Injured": "3",
                    "TimeLoss vs Medical Attention": "Medical Attention",
                }
            ),
            {"Source Modified Days": "3", "Source Closure Status": "TRUE"},
        )
        self.assertEqual(
            result["row_values"]["TimeLoss vs Medical Attention"],
            "Medical Attention",
        )
        self.assertIsNone(result["qualifying_source_classification"])
        self.assertTrue(result["participation_restriction_evidence"])
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(result["classification_basis"], "source_participation_restriction")

    def test_open_irfu_restriction_keeps_clinical_days_but_not_time_loss_days(self):
        result = MODULE.derive_row(
            "irfu_restriction",
            row(**{"Days Injured": "3", "TimeLoss vs Medical Attention": "Time Loss"}),
            {"Source Modified Days": "3", "Source Closure Status": "FALSE"},
        )
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(result["clinical_duration_days"], 3)
        self.assertIsNone(result["time_loss_days"])
        self.assertIsNone(result["return_date"])
        self.assertEqual(result["return_date_basis"], "missing_open_record")
        self.assertFalse(result["unrestricted_participation_evidence"])

    def test_zero_days_derives_same_day_return(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(**{"Days Injured": "0"}),
            {},
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertEqual(result["return_date"], "2025-09-01")
        self.assertEqual(result["return_date_basis"], "derived_zero_day_return")
        self.assertIn("Confirmed Return Date", result["derived_fields"])

    def test_missing_duration_uses_ordinary_date_difference(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(**{"Confirmed Return Date": "10/09/2025"}),
            {},
        )
        self.assertEqual(result["clinical_duration_days"], 9)
        self.assertEqual(result["row_values"]["Days Injured"], "9")

    def test_excluded_rows_are_not_adjudicated_or_date_derived(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "10/09/2025",
                    "TimeLoss vs Medical Attention": "Time Loss",
                    "Exclusion Reason": "Outside official analysis window",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(result["classification_basis"], "excluded_source_classification")
        self.assertEqual(result["row_values"]["Days Injured"], "")
        self.assertFalse(result["review_required"])

    def test_excluded_fit_date_and_zero_time_loss_stay_audit_only(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Fit For Selection Date": "02/09/2025",
                    "Days Injured": "0",
                    "TimeLoss vs Medical Attention": "Time Loss",
                    "Exclusion Reason": "Outside official analysis window",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(result["row_values"]["Confirmed Return Date"], "")
        self.assertEqual(result["clinical_duration_days"], 0)
        self.assertIn(
            "reported_duration_conflicts_with_dates",
            result["review_reasons"],
        )
        self.assertIn(
            "time_loss_with_zero_clinical_days",
            result["review_reasons"],
        )
        self.assertFalse(result["review_required"])

    def test_existing_medical_attention_keeps_source_basis(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Confirmed Return Date": "02/09/2025",
                    "Days Injured": "0",
                    "TimeLoss vs Medical Attention": "Medical Attention",
                }
            ),
            {},
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertEqual(result["classification_basis"], "explicit_source_classification")

    def test_open_record_fallback_keeps_days_and_return_null(self):
        result = MODULE.derive_row("reviewed_explicit", row(), {})
        self.assertEqual(result["final_classification"], "Time Loss")
        self.assertEqual(result["classification_basis"], "open_record_fallback")
        self.assertTrue(result["open_status"])
        self.assertIsNone(result["return_date"])
        self.assertIsNone(result["time_loss_days"])
        self.assertFalse(result["unrestricted_participation_evidence"])

    def test_positive_clinical_duration_alone_is_unclassified(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(**{"Days Injured": "8", "Confirmed Return Date": "09/09/2025"}),
            {},
        )
        self.assertEqual(result["final_classification"], "unclassified")
        self.assertEqual(result["clinical_duration_days"], 8)
        self.assertIsNone(result["time_loss_days"])

    def test_benetton_medical_open_status_stays_separate(self):
        result = MODULE.derive_row(
            "benetton_status",
            row(
                **{
                    "Days Injured": "4",
                    "Confirmed Return Date": "05/09/2025",
                    "TimeLoss vs Medical Attention": "Medical Attention",
                }
            ),
            {},
            {
                "time_loss_classification": "Medical Attention",
                "medical_closure_status": "Medically open",
            },
        )
        self.assertEqual(result["final_classification"], "Medical Attention")
        self.assertIsNone(result["qualifying_source_classification"])
        self.assertFalse(result["participation_restriction_evidence"])
        self.assertTrue(result["open_status"])
        self.assertIsNone(result["time_loss_days"])

    def test_open_benetton_time_loss_without_green_has_no_burden_days(self):
        result = MODULE.derive_row(
            "benetton_status",
            row(
                **{
                    "Days Injured": "4",
                    "Confirmed Return Date": "05/09/2025",
                    "TimeLoss vs Medical Attention": "Time Loss",
                }
            ),
            {},
            {
                "time_loss_classification": "Time Loss",
                "medical_closure_status": "Medically open",
                "status_timeline": {"green": {"start": None, "end": None}},
            },
        )
        self.assertEqual(result["clinical_duration_days"], 4)
        self.assertIsNone(result["time_loss_days"])
        self.assertIsNone(result["return_date"])
        self.assertFalse(result["unrestricted_participation_evidence"])

    def test_open_benetton_time_loss_with_green_retains_known_burden_days(self):
        result = MODULE.derive_row(
            "benetton_status",
            row(
                **{
                    "Days Injured": "4",
                    "Confirmed Return Date": "05/09/2025",
                    "TimeLoss vs Medical Attention": "Time Loss",
                }
            ),
            {},
            {
                "time_loss_classification": "Time Loss",
                "medical_closure_status": "Medically open",
                "status_timeline": {
                    "green": {"start": "2025-09-05", "end": "2025-09-05"}
                },
            },
        )
        self.assertEqual(result["time_loss_days"], 4)
        self.assertEqual(result["return_date"], "2025-09-05")
        self.assertIsNone(result["qualifying_source_classification"])
        self.assertTrue(result["participation_restriction_evidence"])
        self.assertTrue(result["unrestricted_participation_evidence"])

    def test_open_unknown_benetton_with_green_does_not_use_time_loss_fallback(self):
        result = MODULE.derive_row(
            "benetton_status",
            row(**{"Days Injured": "4", "Confirmed Return Date": "05/09/2025"}),
            {},
            {
                "time_loss_classification": "Unknown",
                "medical_closure_status": "Medically open",
                "status_timeline": {
                    "green": {"start": "2025-09-05", "end": "2025-09-05"}
                },
            },
        )
        self.assertEqual(result["final_classification"], "unclassified")
        self.assertEqual(result["classification_basis"], "unclassified_no_qualifying_evidence")
        self.assertIsNone(result["time_loss_days"])

    def test_excluded_source_row_can_retain_unresolved_problem_type(self):
        unresolved = row(**{"Problem type": "", "Exclusion Reason": "Unresolved"})
        self.assertTrue(MODULE.valid_problem_type(unresolved))
        self.assertFalse(MODULE.valid_problem_type(row(**{"Problem type": ""})))

    def test_known_source_synonyms_are_mapped_to_frozen_values(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Nature of onset": "Traumatic",
                    "Recurrence": "First episode",
                    "Is Contact": "Non-Contact",
                    "Mechanism of Injury": "Tackled",
                    "Injury Surface Type": "Astroturf/Hybrid",
                    "Received At Position": "Winger",
                }
            ),
            {},
        )
        values = result["row_values"]
        self.assertEqual(values["Nature of onset"], "N/A or Unknown")
        self.assertEqual(values["Recurrence"], "New injury")
        self.assertEqual(values["Is Contact"], "Non-contact")
        self.assertEqual(values["Mechanism of Injury"], "Being Tackled")
        self.assertEqual(values["Injury Surface Type"], "astroturf/hybrid")
        self.assertEqual(values["Received At Position"], "Wing")
        self.assertTrue(
            {
                "Nature of onset", "Recurrence", "Is Contact",
                "Mechanism of Injury", "Injury Surface Type", "Received At Position",
            }.issubset(result["derived_fields"])
        )

    def test_unknown_source_values_use_frozen_missing_or_unknown_forms(self):
        result = MODULE.derive_row(
            "reviewed_explicit",
            row(
                **{
                    "Occasion category": "Unknown",
                    "Nature of onset": "Unknown",
                    "Recurrence": "Unknown",
                    "TimeLoss vs Medical Attention": "Unknown",
                }
            ),
            {},
        )
        values = result["row_values"]
        self.assertEqual(values["Occasion category"], "")
        self.assertEqual(values["Nature of onset"], "N/A or Unknown")
        self.assertEqual(values["Recurrence"], "")
        self.assertEqual(values["TimeLoss vs Medical Attention"], "Time Loss")

    def test_unmapped_controlled_value_is_rejected(self):
        with self.assertRaisesRegex(MODULE.ConsolidationError, "unsupported frozen 2024-25 value"):
            MODULE.derive_row(
                "reviewed_explicit",
                row(**{"Mechanism of Injury": "New unsupported mechanism"}),
                {},
            )

    def test_only_included_confirmed_fixture_additions_receive_blue_provenance(self):
        confirmed = row(**{"Match Type": "Confirmed URC match fixture"})
        source_label = row(**{"Match Type": "URC"})
        self.assertTrue(MODULE.is_verified_fixture_addition(confirmed, False))
        self.assertFalse(MODULE.is_verified_fixture_addition(confirmed, True))
        self.assertFalse(MODULE.is_verified_fixture_addition(source_label, False))


if __name__ == "__main__":
    unittest.main()
