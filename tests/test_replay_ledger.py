from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/replay.py"
SPEC = importlib.util.spec_from_file_location("replay_ledger", SCRIPT)
assert SPEC and SPEC.loader
REPLAY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPLAY)


HEADERS = [
    "Team",
    "PlayerID",
    "Received At Club",
    "Received/Injured In Team",
    "Problem type",
    "Date Injured",
    "Fit For Selection Date",
    "Confirmed Return Date",
    "Days Injured",
    "Occasion category",
    "Body Part",
    "Orchard Code",
    "Illness Code",
    "Description",
    "Injury Tissue Type/s",
    "Side",
    "Nature of onset",
    "Recurrence",
    "Is Contact",
    "Mechanism of Injury",
    "Mechanism Notes",
    "Injury Surface Type",
    "Match Type",
    "Received At Position",
    "Required Surgery",
    "TimeLoss vs Medical Attention",
    "Diagnosis",
    "Exclusion Reason",
]


def row(
    team: str,
    player_id: str,
    *,
    days: object = "",
    time_loss: str = "Unknown",
    exclusion: str = "",
    injured: str = "01/09/2024",
    fit: str = "",
    returned: str = "",
) -> list[object]:
    values: list[object] = [""] * len(HEADERS)
    updates = {
        "Team": team,
        "PlayerID": player_id,
        "Problem type": "Injury",
        "Date Injured": injured,
        "Fit For Selection Date": fit,
        "Confirmed Return Date": returned,
        "Days Injured": days,
        "Occasion category": "Training",
        "TimeLoss vs Medical Attention": time_loss,
        "Exclusion Reason": exclusion,
    }
    for field, value in updates.items():
        values[HEADERS.index(field)] = value
    return values


def master(rows: list[list[object]]) -> dict[str, object]:
    return {
        "format": "urc-master-workbook",
        "format_version": 1,
        "sheets": [
            {
                "name": "Injury Master",
                "values": [HEADERS, *rows],
            }
        ],
    }


def entry(
    source_row: int,
    player_id: str,
    field: str,
    old: str,
    new: str,
    action: str = "value_update",
) -> dict[str, object]:
    return {
        "source_workbook_row": source_row,
        "team": "A",
        "player_id": player_id,
        "field": field,
        "old_value": old,
        "new_value": new,
        "action": action,
        "reason": "test",
        "evidence_origin": "synthetic",
        "value_origin": "test",
    }


def ledger(entries: list[dict[str, object]]) -> dict[str, object]:
    return {
        "season": "2024-25",
        "steps": [
            {
                "order": 1,
                "rule_version": "synthetic_v1",
                "entries": entries,
            }
        ],
    }


class ReplayLedgerTests(unittest.TestCase):
    def test_export_selection_and_mapping_stability(self) -> None:
        headers, rows = REPLAY.load_master_table(
            master(
                [
                    row("A", "P1"),
                    row("A", "P2", exclusion="Excluded"),
                    row("A", "P3"),
                ]
            )
        )
        selected, source_rows = REPLAY.select_inclusion(headers, rows)
        self.assertEqual(source_rows, [2, 4])
        replayed, retained, _, conflicts = REPLAY.apply_ledger(
            headers, selected, source_rows, ledger([])
        )
        self.assertEqual(retained, [2, 4])
        self.assertEqual(len(replayed), 2)
        self.assertEqual(conflicts, [])
        self.assertNotEqual(
            REPLAY.mapping_sha256([2, 4]),
            REPLAY.mapping_sha256([4, 2]),
        )

    def test_old_value_guard_classifies_applied_materialized_and_conflict(self) -> None:
        headers, rows = REPLAY.load_master_table(
            master(
                [
                    row("A", "P1", days=""),
                    row("A", "P2", days="2"),
                    row("A", "P3", days="9"),
                ]
            )
        )
        selected, source_rows = REPLAY.select_inclusion(headers, rows)
        changes = [
            entry(2, "P1", "Days Injured", "", "2"),
            entry(3, "P2", "Days Injured", "", "2"),
            entry(4, "P3", "Days Injured", "", "2"),
        ]
        replayed, retained, summaries, conflicts = REPLAY.apply_ledger(
            headers, selected, source_rows, ledger(changes), rows
        )
        self.assertEqual(retained, [2, 3, 4])
        self.assertEqual(
            summaries[0],
            {
                "order": 1,
                "rule_version": "synthetic_v1",
                "entries": 3,
                "applied": 1,
                "materialized_in_master": 1,
                "row_excluded_from_selection": 0,
                "conflict": 1,
            },
        )
        self.assertEqual(replayed[0][HEADERS.index("Days Injured")], "2")
        self.assertEqual(conflicts[0]["reason"], "old_value_guard_failed")

    def test_row_removals_apply_or_are_materialized(self) -> None:
        headers, rows = REPLAY.load_master_table(
            master(
                [
                    row("A", "P1"),
                    row("A", "P2", exclusion="Already excluded"),
                ]
            )
        )
        selected, source_rows = REPLAY.select_inclusion(headers, rows)
        removals = [
            entry(
                2,
                "P1",
                "Inclusion Status",
                "Included",
                "Excluded from included CSV",
                "removed_from_inclusion_csv",
            ),
            entry(
                3,
                "P2",
                "Inclusion Status",
                "Included",
                "Excluded from included CSV",
                "removed_from_inclusion_csv",
            ),
        ]
        replayed, retained, summaries, conflicts = REPLAY.apply_ledger(
            headers, selected, source_rows, ledger(removals), rows
        )
        self.assertEqual(replayed, [])
        self.assertEqual(retained, [])
        self.assertEqual(summaries[0]["applied"], 1)
        self.assertEqual(summaries[0]["materialized_in_master"], 1)
        self.assertEqual(conflicts, [])

    def test_rows_missing_from_master_entirely_are_conflicts(self) -> None:
        headers, rows = REPLAY.load_master_table(master([row("A", "P1")]))
        selected, source_rows = REPLAY.select_inclusion(headers, rows)
        changes = [
            entry(9, "P9", "Days Injured", "", "2"),
            entry(
                9,
                "P9",
                "Inclusion Status",
                "Included",
                "Excluded from included CSV",
                "removed_from_inclusion_csv",
            ),
        ]
        replayed, retained, summaries, conflicts = REPLAY.apply_ledger(
            headers, selected, source_rows, ledger(changes), rows
        )
        self.assertEqual(summaries[0]["conflict"], 2)
        self.assertTrue(
            all(
                conflict["reason"] == "source_row_missing_from_master"
                for conflict in conflicts
            )
        )

    def test_excluded_row_edits_classify_as_row_excluded(self) -> None:
        headers, rows = REPLAY.load_master_table(
            master([row("A", "P1"), row("A", "P2", exclusion="Excluded")])
        )
        selected, source_rows = REPLAY.select_inclusion(headers, rows)
        changes = [entry(3, "P2", "Days Injured", "", "2")]
        replayed, retained, summaries, conflicts = REPLAY.apply_ledger(
            headers, selected, source_rows, ledger(changes), rows
        )
        self.assertEqual(summaries[0]["row_excluded_from_selection"], 1)
        self.assertEqual(conflicts, [])

    def test_flag_generation_is_advisory_and_includes_fit_date_reversal(self) -> None:
        rows = [
            row(
                "A",
                "P1",
                days="-1",
                time_loss="Novel",
                injured="26/07/2024",
                fit="20/07/2024",
                returned="30/06/2026",
            ),
            row("A", "P2", days="1.5", injured="01/01/2023"),
        ]
        allowed = {
            "TimeLoss vs Medical Attention": {"Unknown", "Time Loss"},
            "Problem type": {"Injury"},
            "Occasion category": {"Training"},
        }
        flags = REPLAY.generate_flags(HEADERS, rows, [1735, 20], allowed)
        flag_types = {(flag["source_workbook_row"], flag["flag"]) for flag in flags}
        self.assertIn((1735, "fit_date_precedes_injury_date"), flag_types)
        self.assertIn((1735, "negative_or_non_integer_days_injured"), flag_types)
        self.assertIn((1735, "category_outside_master_values"), flag_types)
        self.assertIn((1735, "date_outside_season_window"), flag_types)
        self.assertIn((20, "negative_or_non_integer_days_injured"), flag_types)

    def test_deleted_phase5_evidence_is_skipped_only_when_manifested(self) -> None:
        evidence_ledger = {
            "steps": [
                {
                    "rule_version": "synthetic_v1",
                    "evidence": [{"path": "gone/audit.csv", "sha256": "abc"}],
                }
            ]
        }
        with tempfile.TemporaryDirectory() as temp:
            manifest = Path(temp) / "deleted.json"
            with self.assertRaises(REPLAY.ReplayError):
                REPLAY.verify_ledger_evidence(evidence_ledger, manifest)
            manifest.write_text(
                json.dumps(
                    {"entries": [{"path": "gone/audit.csv", "sha256": "abc"}]}
                ),
                encoding="utf-8",
            )
            REPLAY.verify_ledger_evidence(evidence_ledger, manifest)
            # A recorded path whose recorded hash differs is still a failure.
            manifest.write_text(
                json.dumps(
                    {"entries": [{"path": "gone/audit.csv", "sha256": "other"}]}
                ),
                encoding="utf-8",
            )
            with self.assertRaises(REPLAY.ReplayError):
                REPLAY.verify_ledger_evidence(evidence_ledger, manifest)

    def test_csv_writer_uses_the_existing_export_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "out.csv"
            REPLAY.EXPORT.write_csv_atomic(path, ["A", "B"], [[1, "x,y"]])
            self.assertEqual(path.read_bytes(), b'A,B\n1,\"x,y\"\n')


if __name__ == "__main__":
    unittest.main()
