from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import pipeline.__main__ as pipeline


class ProcessIntakeBulkWriteTests(unittest.TestCase):
    def test_record_versions_and_events_use_two_semantically_bound_bulk_inserts(self) -> None:
        source_rows = []
        for row_number in (2, 3):
            row = {field: "opaque" for field in pipeline.LOCATOR_FIELDS + pipeline.UID_FIELDS}
            row["standardised_row_number"] = str(row_number)
            source_rows.append(row)

        states_and_events = [
            (
                {
                    "analysis_eligibility_status": "included_pending_protocol",
                    "marker": {"row": 2},
                },
                [
                    {
                        "field_name": "date_injured",
                        "old_value": None,
                        "new_value": "2025-09-01",
                        "action": "derive",
                        "reason_code": "deterministic_derivation",
                        "rationale": "Derived from pseudonymised intake evidence.",
                        "review_status": "not_required",
                    }
                ],
            ),
            (
                {
                    "analysis_eligibility_status": "review_required",
                    "marker": {"row": 3},
                },
                [
                    {
                        "field_name": "candidate_duplicate_injury_signature",
                        "old_value": None,
                        "new_value": True,
                        "action": "flag",
                        "reason_code": "candidate_duplicate",
                        "rationale": "Candidate duplicate retained for review.",
                        "review_status": "needs_review",
                    },
                    {
                        "field_name": "analysis_eligibility_status",
                        "old_value": "included_pending_protocol",
                        "new_value": "review_required",
                        "action": "flag",
                        "reason_code": "outside_provisional_window",
                        "rationale": "Outside the provisional review window.",
                        "review_status": "needs_review",
                    },
                ],
            ),
        ]

        with TemporaryDirectory() as temporary:
            intake_path = Path(temporary) / "injury.csv"
            intake_path.write_text("checksum fixture only\n", encoding="utf-8")
            args = SimpleNamespace(
                file=str(intake_path),
                team="Zebre",
                season="2025-26",
                window_start="2025-09-01",
                window_end="2026-06-30",
                analysis_audit_file="",
                injury_eligibility_bridge_file="",
                registered_source_file_sha256="",
                manifest="",
                adapter_qc_file="",
                step_name="standardise_injury",
                step_version="injury_rule_v1",
                version_number=1,
            )
            captured: dict[str, object] = {}

            def capture_run_sql(sql: str, values: list[object]) -> None:
                captured["sql"] = sql
                captured["values"] = values

            with (
                patch.object(pipeline, "read_rows", return_value=source_rows),
                patch.object(pipeline, "sha256_file", return_value="a" * 64),
                patch.object(
                    pipeline,
                    "validate_year2_injury_eligibility_bridge",
                    return_value={
                        2: {
                            "date_basis": "source_date_within_window",
                            "eligibility_status": "included_pending_protocol",
                        },
                        3: {
                            "date_basis": "source_date_outside_window",
                            "eligibility_status": "review_required",
                        },
                    },
                ),
                patch.object(pipeline, "year2_duplicate_source_row_numbers", return_value=set()),
                patch.object(pipeline, "fetch_standing_eligibility_adjudications", return_value={}),
                patch.object(pipeline, "fetch_standing_source_field_adjudications", return_value={}),
                patch.object(
                    pipeline,
                    "query_sql",
                    side_effect=[
                        [],
                        [{"present": 1}],
                        [
                            {"code": "season_attributed_undated_injury"},
                            {"code": "explicit_source_exclusion"},
                        ],
                    ],
                ),
                patch.object(pipeline, "resolve_team_key", return_value="zebre"),
                patch.object(pipeline, "load_fixture_team_aliases", return_value={}),
                patch.object(pipeline, "own_team_alias_for", return_value=None),
                patch.object(pipeline, "build_processing_state", side_effect=states_and_events),
                patch.object(
                    pipeline,
                    "run_provenance",
                    return_value={
                        "code_version": "test-code",
                        "dependency_lock_hash": "b" * 64,
                        "operator": "test-operator",
                    },
                ),
                patch.object(pipeline, "run_sql", side_effect=capture_run_sql),
            ):
                pipeline.process_intake(args)

        sql = str(captured["sql"])
        values = captured["values"]
        self.assertIsInstance(values, list)
        self.assertEqual(sql.lower().count("insert into processing.record_versions"), 1)
        self.assertEqual(sql.lower().count("insert into audit.record_events"), 1)
        self.assertEqual(sql.count("jsonb_array_elements("), 2)
        self.assertIn(
            "sr.raw_record_id = planned_record.item ->> 'raw_record_id'",
            sql,
        )
        self.assertIn(
            "sr.raw_record_id = planned_event.item ->> 'raw_record_id'",
            sql,
        )
        self.assertIn("planned_event.item -> 'old_value'", sql)
        self.assertIn("planned_event.item -> 'new_value'", sql)
        self.assertIn("injury_rule_v1", values)

        record_payloads = [
            value
            for value in values
            if isinstance(value, list)
            and value
            and isinstance(value[0], dict)
            and set(value[0]) == {"raw_record_id", "record_state", "eligibility_status"}
        ]
        event_payloads = [
            value
            for value in values
            if isinstance(value, list)
            and value
            and isinstance(value[0], dict)
            and set(value[0])
            == {
                "raw_record_id",
                "field_name",
                "old_value",
                "new_value",
                "action",
                "reason_code",
                "rationale",
                "review_status",
            }
        ]
        self.assertEqual(len(record_payloads), 1)
        self.assertEqual(len(event_payloads), 1)

        expected_raw_ids = [
            pipeline.raw_record_id("Zebre", "2025-26", "a" * 64, row_number)
            for row_number in (2, 3)
        ]
        self.assertEqual(
            record_payloads[0],
            [
                {
                    "raw_record_id": expected_raw_ids[0],
                    "record_state": states_and_events[0][0],
                    "eligibility_status": "included_pending_protocol",
                },
                {
                    "raw_record_id": expected_raw_ids[1],
                    "record_state": states_and_events[1][0],
                    "eligibility_status": "review_required",
                },
            ],
        )
        self.assertEqual(
            event_payloads[0],
            [
                {"raw_record_id": expected_raw_ids[0], **states_and_events[0][1][0]},
                {"raw_record_id": expected_raw_ids[1], **states_and_events[1][1][0]},
                {"raw_record_id": expected_raw_ids[1], **states_and_events[1][1][1]},
            ],
        )
        self.assertIsNone(event_payloads[0][0]["old_value"])
        self.assertIs(event_payloads[0][1]["new_value"], True)
        self.assertEqual(
            event_payloads[0][2]["new_value"],
            "review_required",
        )


if __name__ == "__main__":
    unittest.main()
