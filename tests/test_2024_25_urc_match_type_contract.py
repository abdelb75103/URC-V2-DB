import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "data/2024-25/master/master_2024-25_v5.json"
LEDGER = ROOT / "data/2024-25/decisions/ledger.json"


class UrcMatchTypeContractTest(unittest.TestCase):
    def test_only_approved_plus_one_rows_keep_exact_urc_label(self) -> None:
        master = json.loads(MASTER.read_text(encoding="utf-8"))
        ledger = json.loads(LEDGER.read_text(encoding="utf-8"))
        sheet = next(
            sheet
            for sheet in master["sheets"]
            if sheet["name"] == "Injury Master"
        )
        headers = sheet["values"][0]
        match_type_index = headers.index("Match Type")
        values_by_row = {
            row_number: list(values)
            for row_number, values in enumerate(sheet["values"][1:], start=2)
        }

        for step in sorted(ledger["steps"], key=lambda item: item["order"]):
            for entry in step["entries"]:
                if entry.get("field") != "Match Type":
                    continue
                row_number = int(entry["source_workbook_row"])
                current = values_by_row[row_number][match_type_index]
                self.assertEqual(entry["old_value"], current)
                values_by_row[row_number][match_type_index] = entry["new_value"]

        exact_urc_rows = {
            row_number
            for row_number, values in values_by_row.items()
            if values[match_type_index] == "URC"
        }
        self.assertEqual({603, 1120, 1121, 1122}, exact_urc_rows)

        expected_replacements = {
            583: "Friendly",
            605: "Other",
            651: "Other",
            685: "Other",
            709: "Other",
            740: "Friendly",
            741: "Friendly",
            742: "Friendly",
            743: "Friendly",
            1110: "training",
            1161: "Other",
            1182: "Pro team A game",
            1183: "Pro team A game",
            1191: "Pro team A game",
        }
        self.assertEqual(
            expected_replacements,
            {
                row_number: values_by_row[row_number][match_type_index]
                for row_number in expected_replacements
            },
        )


if __name__ == "__main__":
    unittest.main()
