from __future__ import annotations

import copy
import unittest

from pipeline.__main__ import assert_v6_public_dashboard_contract


def dashboard() -> dict[str, object]:
    headline = [
        {"key": "recorded_injuries", "label": "Recorded injuries", "value": 12, "unit": "injuries", "formula": "count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)"},
        {"key": "time_loss_injuries", "label": "Time-loss injuries", "value": 9, "unit": "injuries", "formula": "count(eligible injury rows where days lost > 0)"},
        {"key": "incidence_per_1000h", "label": "Incidence", "value": 4.5, "unit": "per 1,000 player-hours", "numerator": 9, "denominator": 2000, "formula": "pooled time-loss injuries / pooled exposure hours * 1000"},
        {"key": "severity_mean_days", "label": "Mean severity", "value": 7, "unit": "days lost per injury", "numerator": 63, "denominator": 9, "formula": "pooled days lost / pooled time-loss injuries"},
        {"key": "severity_median_days", "label": "Median severity", "value": 6, "unit": "days lost per injury", "formula": "median(days lost) across pooled time-loss injuries"},
        {"key": "burden_per_1000h", "label": "Burden", "value": 31.5, "unit": "days lost per 1,000 player-hours", "numerator": 63, "denominator": 2000, "formula": "pooled days lost / pooled exposure hours * 1000"},
    ]
    profile = {
        "dimension": "injury_type", "code": "muscle_injury", "label": "Muscle injury", "setting": "all",
        "time_loss_injuries": 9, "days_lost": 63, "exposure_hours": 2000,
        "incidence_per_1000h": 4.5, "burden_per_1000h": 31.5, "mean_severity_days": 7,
    }
    contact = [
        {"key": key, "label": label, "setting": setting, "recorded_injuries": 0, "time_loss_injuries": 0}
        for setting in ("all", "match", "training", "unknown")
        for key, label in (("contact", "Contact"), ("non_contact", "Non-contact"), ("unknown", "Unknown"))
    ]
    return {
        "generated_at": "2026-08-15T00:00:00Z", "team": "URC Overall", "season": "2025-26",
        "analysis_window": {"start": "2025-09-01", "end": "2026-06-30", "basis": "Registered Year 2 reporting window."},
        "method": ["method"],
        "coverage": {"hours": 2000, "match_hours": 800, "training_hours": 1200, "distance_km": 1,
                     "exposure_rows": 2, "exposed_players": 3, "weeks": 4,
                     "included_exposure_status": "included_pending_protocol",
                     "analysis_window_start": "2025-09-01", "analysis_window_end": "2026-06-30", "teams_included": 16},
        "headline": headline, "monthly": [], "body_locations": [], "injury_types": [],
        "injury_profiles": [
            profile,
            {**profile, "dimension": "diagnosis", "code": "compound__thigh__muscle_injury", "label": "Thigh · Muscle injury"},
        ],
        "injury_type_families": [{**profile, "dimension": "injury_type_family", "mapping_version": "injury_type_family_2026-07-21_v1", "subtypes": [profile]}],
        "severity_distribution": [],
        "setting_split": [
            {"key": key, "label": label, "time_loss_injuries": 0, "days_lost": 0,
             "exposure_hours": None if key == "unknown" else 2000}
            for key, label in (("all", "All"), ("match", "Match"), ("training", "Training"), ("unknown", "Unknown"))
        ],
        "setting_metrics": [
            {"setting": key, "label": label, "time_loss_injuries": 0, "days_lost": 0,
             "exposure_hours": None if key == "unknown" else 2000,
             "incidence_per_1000h": None, "burden_per_1000h": None, "mean_severity_days": None}
            for key, label in (("all", "All"), ("match", "Match"), ("training", "Training"), ("unknown", "Unknown"))
        ],
        "contact_distribution": contact,
        "prior_season": {"season": "2024-25", "status": "frozen", "note": "Frozen."},
        "limitations": ["limit"],
    }


class V6PublicPayloadContractTests(unittest.TestCase):
    def test_accepts_the_exact_public_payload_shape(self) -> None:
        assert_v6_public_dashboard_contract(dashboard(), "fixture")

    def test_rejects_an_unpublished_field_or_incomplete_contact_grid(self) -> None:
        with_private = dashboard()
        with_private["release_id"] = "not-public"
        with self.assertRaisesRegex(SystemExit, "unexpected top-level"):
            assert_v6_public_dashboard_contract(with_private, "fixture")

        missing_contact = copy.deepcopy(dashboard())
        missing_contact["contact_distribution"].pop()  # type: ignore[index]
        with self.assertRaisesRegex(SystemExit, "12-cell contact"):
            assert_v6_public_dashboard_contract(missing_contact, "fixture")

    def test_rejects_extra_nested_public_fields_and_wrong_headline_formula(self) -> None:
        with_extra_coverage = dashboard()
        with_extra_coverage["coverage"]["candidate_build_id"] = "private"  # type: ignore[index]
        with self.assertRaisesRegex(SystemExit, "coverage"):
            assert_v6_public_dashboard_contract(with_extra_coverage, "fixture")

        wrong_formula = dashboard()
        wrong_formula["headline"][2]["formula"] = "unreviewed"  # type: ignore[index]
        with self.assertRaisesRegex(SystemExit, "formula"):
            assert_v6_public_dashboard_contract(wrong_formula, "fixture")

    def test_rejects_missing_duplicate_or_reordered_setting_grids(self) -> None:
        for section in ("setting_split", "setting_metrics"):
            missing = copy.deepcopy(dashboard())
            missing[section].pop()  # type: ignore[index]
            with self.assertRaisesRegex(SystemExit, "ordered all/match/training/unknown"):
                assert_v6_public_dashboard_contract(missing, "fixture")

            duplicate = copy.deepcopy(dashboard())
            duplicate[section][1] = copy.deepcopy(duplicate[section][0])  # type: ignore[index]
            with self.assertRaisesRegex(SystemExit, "ordered all/match/training/unknown"):
                assert_v6_public_dashboard_contract(duplicate, "fixture")

            reordered = copy.deepcopy(dashboard())
            reordered[section][0], reordered[section][1] = reordered[section][1], reordered[section][0]  # type: ignore[index]
            with self.assertRaisesRegex(SystemExit, "ordered all/match/training/unknown"):
                assert_v6_public_dashboard_contract(reordered, "fixture")

    def test_rejects_profiles_that_drop_the_accepted_diagnosis_dimension(self) -> None:
        missing_diagnosis = dashboard()
        missing_diagnosis["injury_profiles"] = [
            row for row in missing_diagnosis["injury_profiles"]  # type: ignore[index]
            if row["dimension"] != "diagnosis"
        ]
        with self.assertRaisesRegex(SystemExit, "diagnosis dimension"):
            assert_v6_public_dashboard_contract(missing_diagnosis, "fixture")


if __name__ == "__main__":
    unittest.main()
