from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/apply_adjudicated_included_injury_decisions.py"
SPEC = importlib.util.spec_from_file_location("adjudicated_decisions", SCRIPT)
assert SPEC and SPEC.loader
DECISIONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DECISIONS)


HEADERS = [
    "Team", "PlayerID", "Days Injured", "TimeLoss vs Medical Attention",
    "Orchard Code", "Illness Code", "Description", "Received/Injured In Team",
]


def row(source_row: int, team: str = "Other") -> dict[str, str]:
    return {
        "Team": team, "PlayerID": f"P{source_row}", "Days Injured": "",
        "TimeLoss vs Medical Attention": "Time Loss", "Orchard Code": "",
        "Illness Code": "", "Description": "",
        "Received/Injured In Team": "",
    }


class ApplyAdjudicatedDecisionsTests(unittest.TestCase):
    def fixture(self) -> tuple[list[dict[str, str]], list[int]]:
        sources = list(range(10_000, 10_000 + DECISIONS.EXPECTED_ROWS_BEFORE))
        required = [358, 2740, 1521, 1522, 1976, 1977, 2170, 2171, 2391, 2392]
        for position, source in enumerate(required):
            sources[position] = source
        rows = [row(source) for source in sources]
        indexed = {source: index for index, source in enumerate(sources)}
        rows[indexed[358]].update({"Team": "Dragons", "Days Injured": "400"})
        rows[indexed[2740]].update({"Team": "Ulster", "Days Injured": "321"})
        rows[indexed[1521]].update({"Team": "Lions", "Days Injured": "0", "TimeLoss vs Medical Attention": "Medical Attention"})
        rows[indexed[1522]].update({"Team": "Lions", "Days Injured": "50"})
        rows[indexed[1976]].update({"Team": "Scarlets", "Days Injured": "2"})
        rows[indexed[1977]].update({"Team": "Scarlets", "Days Injured": "1"})
        rows[indexed[2170]].update({"Team": "Sharks", "Days Injured": "0", "TimeLoss vs Medical Attention": "Medical Attention"})
        rows[indexed[2171]].update({"Team": "Sharks", "Days Injured": "0", "TimeLoss vs Medical Attention": "Medical Attention"})
        rows[indexed[2391]].update({"Team": "Sharks", "Received/Injured In Team": "Sharks", "Orchard Code": "KDPX", "Illness Code": "NC93.1", "Description": "Patellar dislocation"})
        rows[indexed[2392]].update({"Team": "Sharks", "Received/Injured In Team": "Sharks", "Orchard Code": "KJMA", "Illness Code": "NC93.50", "Description": "Grade 1 MCL tear knee"})
        return rows, sources

    def test_applies_only_approved_changes_and_removals(self) -> None:
        rows, sources = self.fixture()
        transformed, mapped, audit, qa = DECISIONS.transform_dataset(rows, sources)
        indexed = dict(zip(mapped, transformed, strict=True))
        self.assertEqual(len(transformed), 2421)
        self.assertFalse(DECISIONS.REMOVED_SOURCE_ROWS & set(mapped))
        self.assertEqual(indexed[2170]["Days Injured"], "2")
        self.assertEqual(indexed[2170]["TimeLoss vs Medical Attention"], "Time Loss")
        self.assertEqual(indexed[2391]["Orchard Code"], "KDPX; KJMA")
        self.assertEqual(indexed[2391]["Illness Code"], "NC93.1; NC93.50")
        self.assertEqual(indexed[2391]["Description"], "Patellar dislocation; Grade 1 MCL tear knee")
        self.assertEqual(indexed[358]["Days Injured"], "400")
        self.assertEqual(indexed[2740]["Days Injured"], "321")
        self.assertEqual(len(audit), 9)
        self.assertEqual(qa["removals_by_team"], {"Lions": 1, "Scarlets": 1, "Sharks": 2})

    def test_rejects_drift_in_adjudicated_precondition(self) -> None:
        rows, sources = self.fixture()
        rows[sources.index(2170)]["Days Injured"] = "1"
        with self.assertRaisesRegex(ValueError, "Unexpected 'Days Injured' value"):
            DECISIONS.transform_dataset(rows, sources)

    def test_mapping_hash_is_order_sensitive(self) -> None:
        self.assertNotEqual(DECISIONS.source_row_mapping_sha256([1, 2]), DECISIONS.source_row_mapping_sha256([2, 1]))

    def test_manifest_rule_describes_both_selection_stages(self) -> None:
        self.assertEqual(
            DECISIONS.SELECTION_RULE,
            "Exclusion Reason is blank after trimming whitespace, followed by removal of "
            "adjudicated source rows 1521, 1977, 2171, and 2392",
        )


if __name__ == "__main__":
    unittest.main()
