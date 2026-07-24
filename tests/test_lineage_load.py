from __future__ import annotations

import importlib.util
import unittest
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/lineage_load.py"
SPEC = importlib.util.spec_from_file_location("lineage_load", SCRIPT)
assert SPEC and SPEC.loader
LINEAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LINEAGE)


class LineageLoadTests(unittest.TestCase):
    @staticmethod
    def _master(source_row: int, player_id: str, injured: str) -> dict:
        return {
            "source_row": source_row,
            "team": "Dragons",
            "row_values": {
                "PlayerID": player_id,
                "Date Injured": injured,
            },
        }

    @staticmethod
    def _dump(source_row_number: int, player_id: str, injured: str) -> dict:
        return {
            "source_row_number": source_row_number,
            "source_row_id": f"source-{source_row_number}",
            "injury_id": f"injury-{source_row_number}",
            "source_values": {
                "PlayerID": player_id,
                "Date Injured": injured,
            },
        }

    def test_date_candidates_cover_supported_and_ambiguous_formats(self) -> None:
        self.assertEqual(
            LINEAGE.parse_date_candidates("2024-07-03"),
            {date(2024, 7, 3)},
        )
        self.assertEqual(
            LINEAGE.parse_date_candidates("3/7/24"),
            {date(2024, 7, 3), date(2024, 3, 7)},
        )
        self.assertEqual(
            LINEAGE.parse_date_candidates("07/03/2024"),
            {date(2024, 7, 3), date(2024, 3, 7)},
        )
        self.assertEqual(LINEAGE.parse_date_candidates("not a date"), set())

    def test_field_compatibility_uses_dates_numbers_and_nonblank_values(self) -> None:
        master = {
            "PlayerID": " P1 ",
            "Date Injured": "03/07/2024",
            "Days Injured": "2",
            "Body Part": "Knee",
            "Description": "",
        }
        source = {
            "PlayerID": "P1",
            "Date Injured": "7/3/24",
            "Days Injured": "2.0",
            "Body Part": "Knee",
            "Description": "Source detail",
        }
        self.assertTrue(LINEAGE.fields_compatible(master, source))
        self.assertFalse(
            LINEAGE.fields_compatible(
                master, {**source, "Body Part": "Shoulder"}
            )
        )
        self.assertFalse(
            LINEAGE.fields_compatible(master, {**source, "PlayerID": "P2"})
        )
        self.assertFalse(
            LINEAGE.fields_compatible(
                master, {**source, "Date Injured": "2024-08-01"}
            )
        )

    def test_field_compatibility_rejects_blank_against_dated_date_fields(
        self,
    ) -> None:
        for field in LINEAGE.DATE_FIELDS:
            with self.subTest(field=field):
                master = {"PlayerID": "P1", field: ""}
                source = {"PlayerID": "P1", field: "2024-09-13"}
                self.assertFalse(LINEAGE.fields_compatible(master, source))
                self.assertFalse(LINEAGE.fields_compatible(source, master))
                self.assertTrue(
                    LINEAGE.fields_compatible(
                        {**master, "Description": ""},
                        {**master, "Description": "Source detail"},
                    )
                )

    def test_match_team_pairs_one_incompatible_remainder_as_leftover_singleton(
        self,
    ) -> None:
        matched, identical_sizes = LINEAGE.match_team(
            "dragons",
            [self._master(505, "P1", "2024-09-13")],
            [self._dump(73, "P1", "2024-09-14")],
        )

        self.assertEqual(identical_sizes, [])
        self.assertEqual(len(matched), 1)
        self.assertEqual(matched[0]["master"]["source_row"], 505)
        self.assertEqual(matched[0]["dump"]["source_row_number"], 73)
        self.assertEqual(matched[0]["match_method"], "leftover_singleton")

    def test_match_team_aborts_when_multiple_rows_remain_for_a_player(
        self,
    ) -> None:
        masters = [
            self._master(505, "P1", "2024-09-13"),
            self._master(535, "P1", "2024-09-14"),
        ]
        dumps = [
            self._dump(73, "P1", "2024-10-13"),
            self._dump(74, "P1", "2024-10-14"),
        ]

        with self.assertRaisesRegex(
            LINEAGE.LineageLoadError,
            r'"source_row": 505.*"source_row": 535',
        ):
            LINEAGE.match_team("dragons", masters, dumps)

    def test_identical_group_verification_accepts_verified_duplicates(self) -> None:
        values = {"PlayerID": "P1", "Body Part": "Knee"}
        rows = [
            {"row_sha256": "first", "source_values": {**values, "extra": "a"}},
            {"row_sha256": "second", "source_values": {**values, "extra": "b"}},
        ]
        self.assertTrue(LINEAGE.identical_group_is_verified(rows))

    def test_identical_group_verification_rejects_matching_field_difference(
        self,
    ) -> None:
        rows = [
            {
                "row_sha256": "same",
                "source_values": {"PlayerID": "P1", "Body Part": "Knee"},
            },
            {
                "row_sha256": "same",
                "source_values": {"PlayerID": "P1", "Body Part": "Ankle"},
            },
        ]
        self.assertFalse(LINEAGE.identical_group_is_verified(rows))

    def test_sql_literal_escapes_quotes_and_preserves_newlines_and_unicode(
        self,
    ) -> None:
        self.assertEqual(
            LINEAGE.sql_literal("O'Brien\ncafé"),
            "'O''Brien\ncafé'",
        )
        payload = LINEAGE.sql_json({"note": "O'Brien\ncafé"})
        self.assertEqual(
            payload,
            """'{"note": "O''Brien\\ncafé"}'::jsonb""",
        )


if __name__ == "__main__":
    unittest.main()
