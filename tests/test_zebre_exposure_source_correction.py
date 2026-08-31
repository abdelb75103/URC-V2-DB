from __future__ import annotations

import csv
from decimal import Decimal
from pathlib import Path
import tempfile
import unittest

from pipeline.zebre_exposure_source_correction import repair_zebre_exposure


ROOT = Path(__file__).resolve().parents[1]
PRIVATE_ROOT = Path("/Users/abdelbabiker/Desktop/URC-V2-DB-private/2025-26")
PROFILE = ROOT / "data/intake/2025-26/zebre/team_intake_profile.json"
MAPPING = ROOT / "data/intake/2025-26/zebre/source_to_canonical_mapping_2026_08_31_v1.json"
PREDECESSOR = PRIVATE_ROOT / "v14_exposure_successor_approved_20260830/zebre/exposure_intake_final_clean_v10.csv"
OCT_SOURCE = PRIVATE_ROOT / "raw-drive/2025_26/Zebre/exposure/OCT-2025.csv"
NOV_SOURCE = PRIVATE_ROOT / "raw-drive/2025_26/Zebre/exposure/NOV-2025.csv"


@unittest.skipUnless(
    all(path.is_file() for path in (PROFILE, MAPPING, PREDECESSOR, OCT_SOURCE, NOV_SOURCE)),
    "protected Zebre source snapshot is not available",
)
class ZebreExposureSourceCorrectionTests(unittest.TestCase):
    def test_approved_snapshot_repairs_only_bound_distance_rows(self) -> None:
        with tempfile.TemporaryDirectory(prefix="zebre-source-correction-") as directory:
            output = Path(directory) / "exposure_intake_final_clean_v11.csv"
            qc = Path(directory) / "source_correction_qc.json"
            manifest = Path(directory) / "source_correction_manifest.json"
            summary = repair_zebre_exposure(
                profile_path=PROFILE,
                mapping_path=MAPPING,
                oct_source=OCT_SOURCE,
                nov_source=NOV_SOURCE,
                predecessor_path=PREDECESSOR,
                output_path=output,
                qc_path=qc,
                manifest_path=manifest,
            )

            self.assertEqual(6694, summary.predecessor_rows)
            self.assertEqual(976, summary.matched_locators)
            self.assertEqual(0, summary.duplicate_locators)
            self.assertEqual(976, summary.patched_rows)
            self.assertEqual(953, summary.recovered_rows)
            self.assertEqual(23, summary.retained_exclusions)
            self.assertEqual(1, summary.impossible_source_distance_rows)
            self.assertEqual(Decimal("1077.65694485"), summary.recovered_hours.quantize(Decimal("0.00000001")))
            self.assertEqual(Decimal("4003.98395238"), summary.recovered_distance_km.quantize(Decimal("0.00000001")))
            self.assertEqual(Decimal("4403.34861145"), summary.corrected_season_hours.quantize(Decimal("0.00000001")))
            self.assertEqual(Decimal("15988.84882329"), summary.corrected_season_distance_km.quantize(Decimal("0.00000001")))

            with PREDECESSOR.open(newline="", encoding="utf-8-sig") as handle:
                predecessor = list(csv.DictReader(handle))
            with output.open(newline="", encoding="utf-8-sig") as handle:
                repaired = list(csv.DictReader(handle))
            self.assertEqual(len(predecessor), len(repaired))
            target_keys = {
                ("9bddcf317a4a51158beddefb30fc3ae02b3715417ae2c88748b345c19e7243b4", str(row))
                for row in range(2, 626)
            } | {
                ("20055ff071efe8360a133bf36ae0bd872cef3fae2bb2a93295ad3c999a6418ab", str(row))
                for row in range(2, 354)
            }
            for before, after in zip(predecessor, repaired, strict=True):
                key = (after["source_file_sha256"], after["source_row_number"])
                if key not in target_keys:
                    self.assertEqual(before, after)
                else:
                    for field in (
                        "player_uid",
                        "source_archive_path",
                        "source_file_sha256",
                        "source_sheet",
                        "source_row_number",
                        "source_row_sha256",
                        "standardised_file_sha256",
                        "standardised_row_number",
                    ):
                        self.assertEqual(before[field], after[field])
            target = [
                row
                for row in repaired
                if row["source_file_sha256"] in {
                    "9bddcf317a4a51158beddefb30fc3ae02b3715417ae2c88748b345c19e7243b4",
                    "20055ff071efe8360a133bf36ae0bd872cef3fae2bb2a93295ad3c999a6418ab",
                }
            ]
            self.assertEqual(976, len(target))
            self.assertEqual(
                976,
                len({(row["source_file_sha256"], row["source_row_number"]) for row in target}),
            )
            self.assertEqual(953, sum(row["cleaning_action"] == "include" for row in target))
            self.assertEqual(23, sum(row["cleaning_action"] == "exclude_from_primary" for row in target))
            self.assertEqual(2, summary.exclusion_reason_counts["session_distance_below_200m"])
            self.assertEqual(1, sum("session_impossible_distance_per_minute" in row["exclusion_reason"] for row in target))
            self.assertNotIn("Name", repaired[0])
            oct_first = next(
                row for row in target
                if row["source_file_sha256"] == "9bddcf317a4a51158beddefb30fc3ae02b3715417ae2c88748b345c19e7243b4"
                and row["source_row_number"] == "2"
            )
            self.assertEqual("5256.785010", oct_first["distance total"])
            oct_impossible = next(
                row for row in target
                if row["source_file_sha256"] == "9bddcf317a4a51158beddefb30fc3ae02b3715417ae2c88748b345c19e7243b4"
                and row["source_row_number"] == "486"
            )
            self.assertEqual("exclude_from_primary", oct_impossible["cleaning_action"])
            nov_low_distance = next(
                row for row in target
                if row["source_file_sha256"] == "20055ff071efe8360a133bf36ae0bd872cef3fae2bb2a93295ad3c999a6418ab"
                and row["source_row_number"] == "79"
            )
            self.assertEqual("52.115600", nov_low_distance["distance total"])
            self.assertIn("session_distance_below_200m", nov_low_distance["exclusion_reason"])


if __name__ == "__main__":
    unittest.main()
