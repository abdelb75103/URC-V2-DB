from __future__ import annotations

import csv
import hashlib
import json
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import patch

from pipeline.welsh_intake_adapter import (
    CONFIG,
    CROSSWALK,
    Crosswalk,
    INTAKE,
    MEDICAL_EXPECTED,
    _valid_days,
    _verify_team_bindings,
    generate_team,
    stamp_approval,
)
from pipeline.__main__ import (
    activity_context,
    body_location,
    contact_context,
    effective_confirmed_return_date,
    effective_days_injured_with_origin,
    injury_closed,
    injury_type,
    problem_type,
    received_in_team_status,
    recurrence_status,
    validate_intake_profile_manifest,
)


class WelshIntakeAdapterTests(unittest.TestCase):
    def test_crosswalk_fails_closed_on_checksum_and_schema_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            drift = Path(temporary) / "crosswalk.csv"
            drift.write_bytes(CROSSWALK.read_bytes() + b"\n")
            with self.assertRaisesRegex(ValueError, "checksum drift"):
                Crosswalk(drift)

            schema = Path(temporary) / "schema.csv"
            schema.write_text("wrong,new_id\na,b\n", encoding="cp1252")
            expected = hashlib.sha256(schema.read_bytes()).hexdigest()
            with patch("pipeline.welsh_intake_adapter.CROSSWALK_SHA256", expected):
                with self.assertRaisesRegex(ValueError, "schema drift"):
                    Crosswalk(schema)

    def test_days_reject_negative_fractional_and_excel_artifacts(self) -> None:
        self.assertEqual(0, _valid_days("0"))
        self.assertEqual(12, _valid_days("12.0"))
        for value in ("-1", "1.5", "01/02/2025", "12:00:00", "45000"):
            self.assertIsNone(_valid_days(value))

    def test_source_binding_drift_fails_closed(self) -> None:
        real = __import__("pipeline.welsh_intake_adapter", fromlist=["sha256_file"]).sha256_file

        def drift(path: Path) -> str:
            return "0" * 64 if path.name == CONFIG["cardiff"]["injury"] else real(path)

        with patch("pipeline.welsh_intake_adapter.sha256_file", side_effect=drift):
            with self.assertRaisesRegex(ValueError, "source checksum drift"):
                _verify_team_bindings("cardiff")

    def test_generated_packages_reconcile_and_are_exactly_approved(self) -> None:
        expected = {
            "cardiff": (62, 7351, 0, 0, 33, 82, 62, 0),
            "dragons": (204, 7126, 17, 2, 49, 5693, 186, 18),
            "ospreys": (163, 8604, 58, 0, 45, 265, 163, 0),
            "scarlets": (200, 5866, 0, 0, 37, 425, 200, 0),
        }
        for team_key, (injuries, exposures, structural, collisions, linked, remapped, own, non_own) in expected.items():
            team_dir = INTAKE / team_key
            manifest = json.loads((team_dir / "intake_manifest.json").read_text())
            injury_qc = json.loads((team_dir / f"{team_key}_injury_adapter_qc_2024-25.json").read_text())
            identity_qc = json.loads((team_dir / f"{team_key}_identity_linkage_qc_2024-25.json").read_text())
            self.assertEqual("PASS", manifest["generation_validation"]["status"])
            self.assertEqual(injuries, manifest["locator_enriched_row_count"])
            self.assertEqual(exposures, manifest["exposure_intake"]["locator_enriched_row_count"])
            self.assertEqual("Abdel Babiker", manifest["intake_profile"]["approved_by"])
            self.assertTrue(manifest["intake_profile"]["approved_at"])
            self.assertEqual([
                manifest["locator_enriched_file_sha256"],
                manifest["exposure_cleaning"]["cleaned_file_sha256"],
            ], manifest["intake_profile"]["approved_input_sha256s"])
            self.assertIn("profile_approval_application", manifest)
            _, _, _, pointer, profile_path, mapping_path = _verify_team_bindings(team_key)
            self.assertEqual(pointer["mapping_sha256"], manifest["intake_profile"]["mapping_sha256"])
            self.assertTrue((team_dir / manifest["intake_profile"]["profile_path"]).is_file())
            self.assertTrue((team_dir / manifest["intake_profile"]["mapping_path"]).is_file())
            self.assertEqual(structural, injury_qc["row_reconciliation"]["structural_nonrecords"])
            self.assertEqual(injuries, injury_qc["row_reconciliation"]["candidate_rows"])
            self.assertEqual(MEDICAL_EXPECTED[team_key], injury_qc["counts"].get("medical_illness_rows", 0))
            self.assertEqual(collisions, len(identity_qc["collision_groups"]))
            self.assertEqual(linked, identity_qc["linkage_counts"]["linked_pairs"])
            self.assertEqual(remapped, identity_qc["identity_remapped_exposure_rows"])
            self.assertFalse(identity_qc["direct_identifiers_serialized"])
            self.assertEqual(own, injury_qc["counts"].get("received_status_own_team", 0))
            self.assertEqual(non_own, injury_qc["counts"].get("received_status_other_team", 0))
            with (team_dir / f"{team_key}_injury_intake_locator_enriched_2024-25.csv").open(
                newline="", encoding="utf-8-sig"
            ) as handle:
                candidate_rows = list(csv.DictReader(handle))
            self.assertTrue(all(row["Received/Injured In Team"] == "[REDACTED_PROTECTED_METADATA]" for row in candidate_rows))
            self.assertEqual(own, sum(bool(row["Adapter Canonical Received In Team Status"]) for row in candidate_rows))

    def test_every_generated_injury_row_is_consumable_by_processing_contract(self) -> None:
        for team_key in CONFIG:
            path = INTAKE / team_key / f"{team_key}_injury_intake_locator_enriched_2024-25.csv"
            with path.open(newline="", encoding="utf-8-sig") as handle:
                rows = list(csv.DictReader(handle))
            for row in rows:
                days, days_origin = effective_days_injured_with_origin(row)
                effective_confirmed_return_date(row, days, days_origin)
                injury_closed(row)
                activity_context(row)
                contact_context(row)
                recurrence_status(row)
                received_in_team_status(row, "intentionally-not-the-protected-alias")
                problem_type(row)
                body_location(row)
                tissue, _ = injury_type(row)
                if team_key == "dragons":
                    self.assertEqual("unknown", tissue)

    def test_processing_consumes_adapter_return_and_derives_days_without_mislabeling_source(self) -> None:
        row = {
            "Date Injured": "01/10/2024", "Days Injured": "", "Confirmed Return Date": "",
            "Adapter Canonical Confirmed Return Date": "11/10/2024",
            "Adapter Canonical Confirmed Return Date Origin": "approved_mapping:raw_return_to_availability_exact_row",
        }
        days, days_origin = effective_days_injured_with_origin(row)
        returned, return_origin = effective_confirmed_return_date(row, days, days_origin)
        self.assertEqual(9, days)
        self.assertEqual("derived_from_dates_excluding_injury_day", days_origin)
        self.assertEqual("2024-10-11", returned.isoformat())
        self.assertEqual("approved_mapping:raw_return_to_availability_exact_row", return_origin)
        row["Adapter Canonical Confirmed Return Date"] = "30/09/2024"
        with self.assertRaisesRegex(SystemExit, "unordered"):
            effective_days_injured_with_origin(row)

    def test_cardiff_generation_is_deterministic_and_dob_free(self) -> None:
        before = json.loads((INTAKE / "cardiff" / "intake_manifest.json").read_text())
        before_bytes = (INTAKE / "cardiff" / "intake_manifest.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "approved intake manifest is immutable"):
            generate_team("cardiff")
        self.assertEqual(before_bytes, (INTAKE / "cardiff" / "intake_manifest.json").read_bytes())
        with tempfile.TemporaryDirectory() as temporary:
            output_root = Path(temporary)
            result = generate_team("cardiff", output_root=output_root)
            self.assertEqual(before["locator_enriched_file_sha256"], result["injury_sha256"])
            with (output_root / "cardiff" / "cardiff_injury_intake_locator_enriched_2024-25.csv").open(
                newline="", encoding="utf-8-sig"
            ) as handle:
                self.assertTrue(all(not row["DOB"] for row in csv.DictReader(handle)))

    def test_candidate_passes_actual_ingest_profile_gate_after_temp_approval_stamp(self) -> None:
        team_key = "cardiff"
        team_dir = INTAKE / team_key
        manifest = json.loads((team_dir / "intake_manifest.json").read_text())
        profile_source = team_dir / manifest["intake_profile"]["profile_path"]
        mapping_source = team_dir / manifest["intake_profile"]["mapping_path"]
        candidate = team_dir / f"{team_key}_injury_intake_locator_enriched_2024-25.csv"
        candidate_sha = hashlib.sha256(candidate.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            mapping_path = directory / "mapping.json"
            mapping_path.write_bytes(mapping_source.read_bytes())
            profile = json.loads(profile_source.read_text())
            profile.update({
                "mapping_path": mapping_path.name,
                "mapping_sha256": hashlib.sha256(mapping_path.read_bytes()).hexdigest(),
                "approved_by": "Abdel Babiker",
                "approved_at": datetime.now(UTC).isoformat(),
                "approved_input_sha256s": [candidate_sha],
            })
            profile_path = directory / "profile.json"
            profile_path.write_text(json.dumps(profile, sort_keys=True))
            bound = {key: profile.get(key) for key in (
                "team", "season", "profile_version", "decision", "mapping_path", "mapping_sha256",
                "mapping_version", "ai_review_status", "ai_reviewed_by", "ai_reviewed_at", "approved_by",
                "approved_at", "unresolved_adjudication_ids", "approved_input_sha256s",
            )}
            bound.update({"profile_path": profile_path.name, "profile_sha256": hashlib.sha256(profile_path.read_bytes()).hexdigest()})
            manifest_path = directory / "manifest.json"
            manifest_path.write_text(json.dumps({"intake_profile": bound}))
            validate_intake_profile_manifest(
                json.loads(manifest_path.read_text()), manifest_path, candidate_sha, "Cardiff", "2024-25"
            )

    def test_real_approval_stamper_is_immutable_idempotent_and_binds_both_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output_root = Path(temporary) / "generated"
            generate_team("cardiff", output_root=output_root)
            team_dir = output_root / "cardiff"
            approved_at = datetime.now(UTC).isoformat()
            manifest = json.loads((team_dir / "intake_manifest.json").read_text())
            evidence = Path(temporary) / "approval-authorization.json"
            evidence.write_text(json.dumps({
                "schema_version": "welsh_profile_authorization_v1",
                "actor": "Abdel Babiker",
                "action": "approve_team_intake_profile",
                "decision": "approved",
                "team": "Cardiff",
                "team_key": "cardiff",
                "season": "2024-25",
                "approved_at": approved_at,
                "reviewed_profile_sha256": manifest["intake_profile"]["profile_sha256"],
                "mapping_sha256": manifest["intake_profile"]["mapping_sha256"],
                "injury_candidate_sha256": manifest["locator_enriched_file_sha256"],
                "cleaned_exposure_sha256": manifest["exposure_cleaning"]["cleaned_file_sha256"],
                "database_action": False,
            }))
            first = stamp_approval(
                "cardiff", approved_at=approved_at, actor_evidence_path=evidence, team_dir=team_dir
            )
            second = stamp_approval(
                "cardiff", approved_at=approved_at, actor_evidence_path=evidence, team_dir=team_dir
            )
            self.assertEqual(first, second)
            manifest = json.loads((team_dir / "intake_manifest.json").read_text())
            self.assertEqual("Abdel Babiker", manifest["intake_profile"]["approved_by"])
            self.assertEqual(2, len(manifest["intake_profile"]["approved_input_sha256s"]))
            self.assertTrue((team_dir / manifest["intake_profile"]["profile_path"]).is_file())
            with (team_dir / "cardiff_exposure_cleaned_2024-25.csv").open("a") as handle:
                handle.write("drift")
            with self.assertRaisesRegex(ValueError, "checksum drift"):
                stamp_approval(
                    "cardiff", approved_at=approved_at, actor_evidence_path=evidence, team_dir=team_dir
                )


if __name__ == "__main__":
    unittest.main()
