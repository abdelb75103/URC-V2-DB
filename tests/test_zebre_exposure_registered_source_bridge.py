from __future__ import annotations

import argparse
import csv
import copy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import pipeline.__main__ as pipeline


REGISTERED_SHA = pipeline.ZEBRE_EXPOSURE_REGISTERED_SOURCE_SHA256
CANDIDATE_SHA = pipeline.ZEBRE_EXPOSURE_CORRECTED_CANDIDATE_SHA256
STEP_VERSION = pipeline.INPUT_REPRESENTATION_CORRECTION_RULE_VERSION


def _exposure_row(row_number: int, *, corrected: bool) -> dict[str, str]:
    ordinal = row_number - 1
    changed = corrected and ordinal <= 976
    action_changed = corrected and ordinal <= 953
    row = {
        "player_uid": f"ply_{row_number}",
        "source_archive_path": "raw-drive/2025_26/Zebre/exposure/OCT-2025.csv",
        "source_file_sha256": "source-file-sha",
        "source_sheet": "CSV",
        "source_row_number": str(row_number),
        "source_row_sha256": f"source-row-{row_number}",
        "standardised_file_sha256": "standardised-file-sha",
        "standardised_row_number": str(row_number),
        "source_locator_status": "bound",
        "exposure_grain": "session",
        "scope_status": "in_scope",
        "scope_reason": "",
        "cleaned_date": "2025-10-01",
        "week_start_date": "2025-09-29",
        "session_date_clean": "2025-10-01",
        "minutes_total_clean": "60.000000",
        "distance total": "100.000000" if not changed else "200.000000",
        "distance_total_m_clean": "100.000000" if not changed else "200.000000",
        "cleaning_action": "exclude_from_primary" if not action_changed else "include",
        "exclusion_reason": "old_reason" if not corrected and ordinal <= 976 else "",
    }
    return row


def _candidate_and_registered() -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    corrected = [_exposure_row(row_number, corrected=True) for row_number in range(2, 6696)]
    registered = [
        {
            "source_row_number": row_number,
            "source_values": _exposure_row(row_number, corrected=False),
        }
        for row_number in range(2, 6696)
    ]
    return corrected, registered


class ZebreRegisteredExposureBridgeTests(unittest.TestCase):
    def test_reconciliation_emits_true_changes_without_duplicates(self) -> None:
        corrected, registered = _candidate_and_registered()

        reconciled, events = pipeline.reconcile_registered_exposure_rows(corrected, registered)

        self.assertEqual(corrected, reconciled)
        self.assertEqual(6694, len(reconciled))
        self.assertEqual(976, len(events))
        self.assertEqual(2905, sum(len(row_events) for row_events in events.values()))
        self.assertEqual(
            976,
            sum(event["field_name"] == "distance_total_m_clean" for row_events in events.values() for event in row_events),
        )
        self.assertEqual(
            976,
            sum(event["field_name"] == "exclusion_reasons" for row_events in events.values() for event in row_events),
        )
        self.assertEqual(
            953,
            sum(event["field_name"] == "analysis_eligibility_status" for row_events in events.values() for event in row_events),
        )
        first_row_events = events[2]
        distance_event = next(event for event in first_row_events if event["field_name"] == "distance_total_m_clean")
        status_event = next(event for event in first_row_events if event["field_name"] == "analysis_eligibility_status")
        self.assertEqual("100.000000", distance_event["old_value"])
        self.assertEqual("200.000000", distance_event["new_value"])
        self.assertEqual("excluded_from_primary", status_event["old_value"])
        self.assertEqual("included_pending_protocol", status_event["new_value"])
        self.assertTrue(all(event["reason_code"] == pipeline.ZEBRE_EXPOSURE_CORRECTION_REASON for row_events in events.values() for event in row_events))

    def test_reconciliation_rejects_order_identity_and_unrelated_field_drift(self) -> None:
        corrected, registered = _candidate_and_registered()

        reordered = copy.deepcopy(registered)
        reordered[0]["source_row_number"] = 3
        with self.assertRaisesRegex(SystemExit, "ordered one-to-one"):
            pipeline.reconcile_registered_exposure_rows(corrected, reordered)

        identity_drift = copy.deepcopy(registered)
        identity_drift[0]["source_values"]["player_uid"] = "different-player"
        with self.assertRaisesRegex(SystemExit, "immutable locator or identity"):
            pipeline.reconcile_registered_exposure_rows(corrected, identity_drift)

        unrelated_drift = copy.deepcopy(registered)
        unrelated_drift[0]["source_values"]["scope_status"] = "out_of_scope"
        with self.assertRaisesRegex(SystemExit, "disallowed field"):
            pipeline.reconcile_registered_exposure_rows(corrected, unrelated_drift)

    def test_bridge_binding_fails_before_database_query(self) -> None:
        with tempfile.TemporaryDirectory(prefix="zebre-exposure-bridge-") as directory:
            candidate = Path(directory) / "candidate.csv"
            with candidate.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=["exposure_grain"])
                writer.writeheader()
                writer.writerow({"exposure_grain": "session"})
            args = argparse.Namespace(
                team="Zebre",
                season="2025-26",
                file=str(candidate),
                reporting_grain="session",
                step_name="exposure_cleaning",
                step_version=STEP_VERSION,
                version_number=102,
                registered_source_file_sha256=REGISTERED_SHA,
                manifest="missing-manifest.json",
                adapter_qc_file="missing-qc.json",
            )
            with patch.object(pipeline, "query_sql") as query:
                with self.assertRaisesRegex(SystemExit, "binding is not exact"):
                    pipeline.process_exposure(args)
            query.assert_not_called()

    def test_bridge_uses_registered_hash_and_emits_gate_counts(self) -> None:
        row = _exposure_row(2, corrected=True)
        metadata = {
            "registered_source_file_sha256": REGISTERED_SHA,
            "manifest_path": Path("manifest.json"),
            "manifest_sha256": "manifest-sha",
            "adapter_qc_path": Path("qc.json"),
            "adapter_qc_sha256": "qc-sha",
            "profile_path": Path("profile.json"),
            "profile_sha256": "profile-sha",
            "mapping_path": Path("mapping.json"),
            "mapping_sha256": "mapping-sha",
        }
        event = {
            "field_name": "distance_total_m_clean",
            "old_value": "100.000000",
            "new_value": "200.000000",
            "action": "correct",
            "reason_code": pipeline.ZEBRE_EXPOSURE_CORRECTION_REASON,
            "rationale": "approved correction",
            "review_status": "adjudicated",
        }
        args = argparse.Namespace(
            team="Zebre",
            season="2025-26",
            file="candidate.csv",
            reporting_grain="session",
            step_name="exposure_cleaning",
            step_version=STEP_VERSION,
            version_number=102,
            registered_source_file_sha256=REGISTERED_SHA,
            manifest="manifest.json",
            adapter_qc_file="qc.json",
        )
        captured: dict[str, object] = {}

        def capture_run_sql(sql: str, params: list[object]) -> None:
            captured["sql"] = sql
            captured["params"] = params

        with tempfile.TemporaryDirectory(prefix="zebre-exposure-bridge-") as directory:
            candidate = Path(directory) / "candidate.csv"
            with candidate.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(row))
                writer.writeheader()
                writer.writerow(row)
            args.file = str(candidate)
            with patch.object(pipeline, "sha256_file", return_value=CANDIDATE_SHA), patch.object(
                pipeline, "_validate_zebre_exposure_bridge", return_value=metadata
            ), patch.object(pipeline, "query_sql", return_value=[]), patch.object(
                pipeline,
                "reconcile_registered_exposure_rows",
                return_value=([row], {2: [event]}),
            ), patch.object(pipeline, "fetch_standing_eligibility_adjudications", return_value={}), patch.object(
                pipeline,
                "run_provenance",
                return_value={"code_version": "test", "dependency_lock_hash": "lock", "operator": "test"},
            ), patch.object(pipeline, "run_sql", side_effect=capture_run_sql):
                pipeline.process_exposure(args)

        self.assertIn(REGISTERED_SHA, captured["params"])
        self.assertIn(CANDIDATE_SHA, captured["params"])
        run_parameters = next(
            value for value in captured["params"] if isinstance(value, dict) and value.get("bridge") == "registered_source_correction"
        )
        self.assertEqual(6694, run_parameters["source_row_count"])
        self.assertEqual(976, run_parameters["patched_rows"])
        self.assertEqual(953, run_parameters["newly_included_rows"])
        self.assertEqual(23, run_parameters["retained_exclusions"])
        self.assertEqual(REGISTERED_SHA, run_parameters["registered_source_file_sha256"])
        self.assertEqual(CANDIDATE_SHA, run_parameters["candidate_sha256"])
        self.assertIn("input_representation_correction", captured["params"])

    def test_process_exposure_parser_accepts_bridge_flags(self) -> None:
        parser = argparse.ArgumentParser()
        subcommands = parser.add_subparsers(dest="command")
        pipeline.add_exposure_cli_parsers(subcommands)

        args = parser.parse_args(
            [
                "process-exposure",
                "--team", "Zebre",
                "--season", "2025-26",
                "--file", "candidate.csv",
                "--reporting-grain", "session",
                "--registered-source-file-sha256", REGISTERED_SHA,
                "--manifest", "manifest.json",
                "--adapter-qc-file", "qc.json",
            ]
        )

        self.assertEqual(REGISTERED_SHA, args.registered_source_file_sha256)
        self.assertEqual("manifest.json", args.manifest)
        self.assertEqual("qc.json", args.adapter_qc_file)


if __name__ == "__main__":
    unittest.main()
