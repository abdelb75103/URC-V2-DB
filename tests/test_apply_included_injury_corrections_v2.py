from __future__ import annotations

import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/apply_included_injury_corrections_v2.py"
SPEC = importlib.util.spec_from_file_location(
    "apply_included_injury_corrections_v2", SCRIPT
)
assert SPEC and SPEC.loader
CORRECTIONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CORRECTIONS)


def make_row(
    source_row: int,
    *,
    team: str = "Team",
    player_id: str | None = None,
    problem_type: str = "Injury",
    date_injured: str = "01/09/2024",
    return_date: str = "",
    days_injured: str = "",
    recurrence: str = "New injury",
) -> dict[str, str]:
    return {
        "Team": team,
        "PlayerID": player_id or f"P{source_row}",
        "Problem type": problem_type,
        "Date Injured": date_injured,
        "Confirmed Return Date": return_date,
        "Days Injured": days_injured,
        "Recurrence": recurrence,
        "Exclusion Reason": "",
    }


class SourceCorrectionTests(unittest.TestCase):
    def build_fixture(
        self,
    ) -> tuple[list[dict[str, str]], list[int], set[int]]:
        source_rows = list(range(4000, 4000 + CORRECTIONS.EXPECTED_ROWS_BEFORE))
        for required in (
            CORRECTIONS.DRAGONS_SOURCE_ROW,
            CORRECTIONS.LIONS_RETAINED_SOURCE_ROW,
            CORRECTIONS.LIONS_REMOVED_SOURCE_ROW,
            CORRECTIONS.EDINBURGH_UNCHANGED_SOURCE_ROW,
            CORRECTIONS.GLASGOW_UNCHANGED_SOURCE_ROW,
        ):
            source_rows[required % len(source_rows)] = required
        if len(set(source_rows)) != len(source_rows):
            self.fail("Test fixture source rows are not unique")

        rows = [make_row(source_row) for source_row in source_rows]
        indexed = {source_row: index for index, source_row in enumerate(source_rows)}
        rows[indexed[CORRECTIONS.DRAGONS_SOURCE_ROW]].update(
            {
                "Team": "Dragons",
                "PlayerID": "P144",
                "Date Injured": CORRECTIONS.DRAGONS_OLD_DATE,
            }
        )
        rows[indexed[CORRECTIONS.EDINBURGH_UNCHANGED_SOURCE_ROW]].update(
            {"Team": "Edinburgh", "PlayerID": "P596"}
        )
        rows[indexed[CORRECTIONS.GLASGOW_UNCHANGED_SOURCE_ROW]].update(
            {
                "Team": "Glasgow Warriors",
                "PlayerID": "P491",
                "Problem type": "Illness",
            }
        )
        duplicate = make_row(
            CORRECTIONS.LIONS_RETAINED_SOURCE_ROW,
            team="Lions",
            player_id="P788",
            return_date="24/10/2024",
            days_injured="11",
        )
        rows[indexed[CORRECTIONS.LIONS_RETAINED_SOURCE_ROW]] = dict(duplicate)
        rows[indexed[CORRECTIONS.LIONS_REMOVED_SOURCE_ROW]] = dict(duplicate)

        recurrence_restore_rows = set(source_rows[:430])
        for source_row in recurrence_restore_rows:
            rows[indexed[source_row]]["Problem type"] = "Illness"
            rows[indexed[source_row]]["Recurrence"] = "New injury"
        return rows, source_rows, recurrence_restore_rows

    def test_transform_restores_source_labels_fixes_date_and_removes_duplicate(
        self,
    ) -> None:
        rows, source_rows, recurrence_rows = self.build_fixture()
        transformed, mapped, audit, qa = CORRECTIONS.transform_dataset(
            rows, source_rows, recurrence_rows
        )
        indexed = {source_row: row for source_row, row in zip(mapped, transformed)}

        self.assertEqual(len(transformed), CORRECTIONS.EXPECTED_ROWS_AFTER)
        self.assertNotIn(CORRECTIONS.LIONS_REMOVED_SOURCE_ROW, mapped)
        self.assertIn(CORRECTIONS.LIONS_RETAINED_SOURCE_ROW, mapped)
        self.assertEqual(
            indexed[CORRECTIONS.DRAGONS_SOURCE_ROW]["Date Injured"],
            CORRECTIONS.DRAGONS_NEW_DATE,
        )
        self.assertTrue(
            all(indexed[source_row]["Recurrence"] == "New case"
                for source_row in recurrence_rows
                if source_row != CORRECTIONS.LIONS_REMOVED_SOURCE_ROW)
        )
        self.assertEqual(len(audit), 432)
        self.assertEqual(qa["recurrence_new_case_restored"], 430)
        self.assertEqual(qa["lions_exact_duplicates_removed"], 1)

    def test_rejects_nonidentical_lions_rows(self) -> None:
        rows, source_rows, recurrence_rows = self.build_fixture()
        index = source_rows.index(CORRECTIONS.LIONS_REMOVED_SOURCE_ROW)
        rows[index]["PlayerID"] = "Pnot_duplicate"
        with self.assertRaisesRegex(ValueError, "not exact CSV duplicates"):
            CORRECTIONS.transform_dataset(rows, source_rows, recurrence_rows)

    def test_reads_only_exact_prior_new_case_audit_events(self) -> None:
        path = ROOT / "work" / "test_recurrence_restore_rows.csv"
        path.parent.mkdir(exist_ok=True)
        headers = ["field", "old_value", "new_value", "source_workbook_row"]
        rows = [
            {
                "field": "Recurrence",
                "old_value": "New case",
                "new_value": "New injury",
                "source_workbook_row": str(index),
            }
            for index in range(430)
        ]
        try:
            with path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=headers)
                writer.writeheader()
                writer.writerows(rows)
            self.assertEqual(len(CORRECTIONS.read_recurrence_restore_rows(path)), 430)
        finally:
            path.unlink(missing_ok=True)

    def test_narrow_csv_patch_preserves_untouched_lines_byte_for_byte(self) -> None:
        headers = ["Team", "PlayerID", "Recurrence"]
        original_rows = [
            {"Team": "A", "PlayerID": "P1", "Recurrence": "New injury"},
            {"Team": "B", "PlayerID": "P2", "Recurrence": "New injury"},
            {"Team": "C", "PlayerID": "P3", "Recurrence": "Recurrence"},
        ]
        transformed_rows = [
            {"Team": "A", "PlayerID": "P1", "Recurrence": "New case"},
            {"Team": "C", "PlayerID": "P3", "Recurrence": "Recurrence"},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "included.csv"
            untouched_line = 'C,P3,"Recurrence"\n'
            path.write_text(
                "Team,PlayerID,Recurrence\n"
                "A,P1,New injury\n"
                "B,P2,New injury\n"
                + untouched_line,
                encoding="utf-8",
            )
            CORRECTIONS.patch_csv_atomic(
                path,
                headers,
                original_rows,
                [10, 20, 30],
                transformed_rows,
                [10, 30],
            )
            lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
            self.assertEqual(lines[2], untouched_line)
            self.assertNotIn("P2", path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
