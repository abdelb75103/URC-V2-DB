from __future__ import annotations

from datetime import datetime
import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import pipeline.__main__ as pipeline


def injury_row(*, date_injured: str, player_uid: str = "ply_known") -> dict[str, str]:
    row = {
        "PlayerID": "Known player" if player_uid != "Unknown" else "Unknown",
        "Date Injured": date_injured,
        "Body Part": "Knee",
        "Orchard Code": "KL2",
        "Side": "Left",
        "Description": "", "Nature of onset": "Acute",
        "Illness Code": "", "Injury Tissue Type/s": "Sprain",
        "Days Injured": "4", "TimeLoss vs Medical Attention": "Time Loss",
        "Received/Injured In Team": "Unknown", "Received At Club": "Unknown",
        "Problem type": "injury", "Fit For Selection Date": "",
        "Confirmed Return Date": "", "Occasion category": "training",
        "Mechanism of Injury": "", "Recurrence": "", "Is Contact": "",
        "Match Type": "",
        "standardised_row_number": "2",
        "player_uid": player_uid,
        "injury_uid": "inj_00000000000000000001",
    }
    row.update(
        {
            field: "2" if field == "standardised_row_number" else "source"
            for field in pipeline.LOCATOR_FIELDS
        }
    )
    return row


class Year2InjuryEligibilityBridgeTests(unittest.TestCase):
    def test_bridge_status_vector_is_validated_before_any_database_query(self) -> None:
        row = injury_row(date_injured="")
        row["injury_date_basis"] = "season_attributed_undated"
        row["injury_eligibility_status"] = "included_pending_protocol"
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            injury_path = root / "injury.csv"
            with injury_path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(row))
                writer.writeheader()
                writer.writerow(row)
            audit_path = root / "audit.csv"
            audit_path.write_text(
                "standardised_row_number,field,action,reason,review_status\n",
                encoding="utf-8",
            )
            args = SimpleNamespace(
                team="Example Club",
                season="2025-26",
                window_start="2025-09-01",
                window_end="2026-06-30",
                analysis_audit_file=str(audit_path),
                injury_eligibility_bridge_file=str(root / "bridge.json"),
            )
            bridge = {
                "schema": "urc_2025_26_injury_eligibility_bridge_v1",
                "rule_version": pipeline.YEAR2_INJURY_ELIGIBILITY_BRIDGE_RULE_VERSION,
                "team": args.team,
                "season": args.season,
                "injury_file_sha256": pipeline.sha256_file(injury_path),
                "row_count": 1,
                "window": {"start": args.window_start, "end": args.window_end},
                "eligibility_vector_sha256": pipeline.sha256_json(
                    pipeline.year2_injury_eligibility_vector([row])
                ),
                "analysis_audit": {
                    "path": audit_path.name,
                    "sha256": pipeline.sha256_file(audit_path),
                    "allowed_reason_codes": ["explicit_source_exclusion"],
                },
            }
            Path(args.injury_eligibility_bridge_file).write_text(
                json.dumps(bridge), encoding="utf-8"
            )

            with patch.object(pipeline, "query_sql") as query_sql:
                result = pipeline.validate_year2_injury_eligibility_bridge(
                    args=args, rows=[row], file_hash=pipeline.sha256_file(injury_path)
                )

            self.assertEqual(
                result,
                {
                    2: {
                        "date_basis": "season_attributed_undated",
                        "eligibility_status": "included_pending_protocol",
                    }
                },
            )
            query_sql.assert_not_called()

    def test_year2_process_intake_refuses_an_unbridged_input_before_querying_database(self) -> None:
        row = injury_row(date_injured="")
        with TemporaryDirectory() as temporary:
            injury_path = Path(temporary) / "injury.csv"
            with injury_path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(row))
                writer.writeheader()
                writer.writerow(row)
            args = SimpleNamespace(
                file=str(injury_path), team="Example Club", season="2025-26",
                window_start="2025-09-01", window_end="2026-06-30",
                injury_eligibility_bridge_file="", analysis_audit_file="",
                registered_source_file_sha256="", manifest="", adapter_qc_file="",
            )

            with patch.object(pipeline, "query_sql") as query_sql:
                with self.assertRaisesRegex(SystemExit, "requires a checksum-bound injury eligibility bridge"):
                    pipeline.process_intake(args)

            query_sql.assert_not_called()

    def test_season_attributed_blank_date_is_included_without_fabricating_a_date(self) -> None:
        row = injury_row(date_injured="")

        state, events = pipeline.build_processing_state(
            row,
            window_start=datetime(2025, 9, 1),
            window_end=datetime(2026, 6, 30),
            duplicate_signature_rows=set(),
            injury_eligibility_bridge={
                "date_basis": "season_attributed_undated",
                "eligibility_status": "included_pending_protocol",
            },
        )

        self.assertIsNone(state["date_injured"])
        self.assertEqual(state["analysis_eligibility_status"], "included_pending_protocol")
        self.assertEqual(state["injury_date_basis"], "season_attributed_undated")
        self.assertTrue(
            any(event["reason_code"] == "season_attributed_undated_injury" for event in events)
        )

    def test_nonblank_unparseable_or_out_of_window_date_stays_review_required(self) -> None:
        for source_date, expected_basis in (
            ("not a date", "source_date_unparseable"),
            ("01/07/2026", "source_date_outside_window"),
        ):
            with self.subTest(source_date=source_date):
                state, _ = pipeline.build_processing_state(
                    injury_row(date_injured=source_date),
                    window_start=datetime(2025, 9, 1),
                    window_end=datetime(2026, 6, 30),
                    duplicate_signature_rows=set(),
                    injury_eligibility_bridge={
                        "date_basis": expected_basis,
                        "eligibility_status": "review_required",
                    },
                )
                self.assertEqual(state["analysis_eligibility_status"], "review_required")
                self.assertEqual(state["injury_date_basis"], expected_basis)

    def test_unknown_or_insufficient_signatures_never_become_duplicate_candidates(self) -> None:
        unknown_one = injury_row(date_injured="", player_uid="Unknown")
        unknown_two = {**unknown_one, "standardised_row_number": "3", "injury_uid": "inj_00000000000000000002"}
        insufficient_one = injury_row(date_injured="", player_uid="ply_known")
        insufficient_one["standardised_row_number"] = "4"
        insufficient_two = {**insufficient_one, "standardised_row_number": "5", "injury_uid": "inj_00000000000000000003"}

        flagged = pipeline.year2_duplicate_source_row_numbers(
            [unknown_one, unknown_two, insufficient_one, insufficient_two],
            pipeline.DUPLICATE_SIGNATURE_FIELDS,
        )

        self.assertEqual(flagged, set())

    def test_year2_duplicate_candidate_stays_included_and_audit_visible(self) -> None:
        first = injury_row(date_injured="02/10/2025", player_uid="ply_known")
        duplicate = {**first, "standardised_row_number": "3", "injury_uid": "inj_00000000000000000002"}
        duplicate_rows = pipeline.year2_duplicate_source_row_numbers(
            [first, duplicate], pipeline.DUPLICATE_SIGNATURE_FIELDS
        )

        state, events = pipeline.build_processing_state(
            duplicate,
            window_start=datetime(2025, 9, 1),
            window_end=datetime(2026, 6, 30),
            duplicate_signature_rows=duplicate_rows,
            injury_eligibility_bridge={
                "date_basis": "source_date_within_window",
                "eligibility_status": "included_pending_protocol",
            },
        )

        self.assertEqual(state["analysis_eligibility_status"], "included_pending_protocol")
        self.assertTrue(state["duplicate_flags"]["candidate_duplicate_injury_signature"])
        self.assertTrue(
            any(event["reason_code"] == "candidate_duplicate" for event in events)
        )

    def test_legacy_duplicate_output_is_preserved_outside_the_year2_bridge(self) -> None:
        unknown_one = injury_row(date_injured="", player_uid="Unknown")
        unknown_two = {**unknown_one, "standardised_row_number": "3", "injury_uid": "inj_00000000000000000002"}
        known_one = injury_row(date_injured="", player_uid="ply_known")
        known_one["standardised_row_number"] = "4"
        known_two = {**known_one, "standardised_row_number": "5", "injury_uid": "inj_00000000000000000003"}

        flagged = pipeline.duplicate_source_row_numbers(
            [unknown_one, unknown_two, known_one, known_two],
            pipeline.DUPLICATE_SIGNATURE_FIELDS,
        )

        self.assertEqual(flagged, {2, 3, 4, 5})

    def test_legacy_path_is_unchanged_when_no_year2_bridge_is_supplied(self) -> None:
        state, _ = pipeline.build_processing_state(
            injury_row(date_injured=""),
            window_start=datetime(2025, 9, 1),
            window_end=datetime(2026, 6, 30),
            duplicate_signature_rows=set(),
        )

        self.assertEqual(state["analysis_eligibility_status"], "review_required")
        self.assertNotIn("injury_date_basis", state)


if __name__ == "__main__":
    unittest.main()
