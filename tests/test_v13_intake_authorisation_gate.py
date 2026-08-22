import hashlib
import json
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path

from pipeline.__main__ import validate_intake_profile_manifest


EXPECTED_AUTHORISATION = {
    "database_action_authorised": True,
    "basis": (
        "the exact approval line names the project, database, ingestion, "
        "processing, build and release"
    ),
    "project_ref": "eukkvswaxweenovqqgzr",
    "database": "postgres",
    "actions": ["ingestion", "processing", "build", "release"],
    "approval_line_sha256": (
        "49cd90905a27faf74b0f1d53d80ea2084964ca1b6e36bd7e4b795ee2e69eb542"
    ),
}


class V13IntakeAuthorisationGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.input_sha = "a" * 64
        now = datetime.now(UTC)
        self.profile = {
            "schema": "urc_2025_26_v13_signed_intake_profile_v1",
            "team": "Benetton",
            "season": "2025-26",
            "profile_version": "urc_2025_26_v13_signed_profile_v1",
            "decision": "compatible",
            "mapping_path": None,
            "mapping_sha256": None,
            "mapping_version": None,
            "ai_review_status": "completed",
            "ai_reviewed_by": "gpt-5.6-sol/xhigh /root/v13_signer_acceptance",
            "ai_reviewed_at": (now - timedelta(minutes=2)).isoformat(),
            "approved_by": "Abdel Babiker",
            "approved_at": (now - timedelta(minutes=1)).isoformat(),
            "approval_ready": True,
            "ingest_ready": True,
            "database_action_authorised": True,
            "authorisation": EXPECTED_AUTHORISATION,
            "unresolved_adjudication_ids": [],
            "approved_input_sha256s": [self.input_sha],
        }

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def manifest(self, *, profile_updates: dict | None = None) -> tuple[dict, Path]:
        profile = {**self.profile, **(profile_updates or {})}
        profile_path = self.root / "v13_approved_intake_profile.json"
        profile_path.write_text(json.dumps(profile, sort_keys=True) + "\n")
        envelope_fields = (
            "team",
            "season",
            "profile_version",
            "decision",
            "mapping_path",
            "mapping_sha256",
            "mapping_version",
            "ai_review_status",
            "ai_reviewed_by",
            "ai_reviewed_at",
            "approved_by",
            "approved_at",
            "unresolved_adjudication_ids",
            "approved_input_sha256s",
            "approval_ready",
            "ingest_ready",
            "database_action_authorised",
            "authorisation",
        )
        envelope = {field: profile[field] for field in envelope_fields}
        envelope.update(
            {
                "profile_path": profile_path.name,
                "profile_sha256": hashlib.sha256(profile_path.read_bytes()).hexdigest(),
            }
        )
        manifest = {
            "schema": "urc_2025_26_v13_signed_intake_manifest_v1",
            "team": profile["team"],
            "season": profile["season"],
            "intake_profile": envelope,
            "approval_ready": True,
            "ingest_ready": True,
            "database_action_authorised": True,
            "authorisation": EXPECTED_AUTHORISATION,
        }
        return manifest, self.root / "v13_approved_intake_manifest.json"

    def validate(self, manifest: dict, manifest_path: Path) -> None:
        validate_intake_profile_manifest(
            manifest,
            manifest_path,
            self.input_sha,
            "Benetton",
            "2025-26",
        )

    def rewrite_profile(self, manifest: dict, update: dict) -> None:
        profile_path = self.root / manifest["intake_profile"]["profile_path"]
        profile = json.loads(profile_path.read_text())
        profile.update(update)
        profile_path.write_text(json.dumps(profile, sort_keys=True) + "\n")
        manifest["intake_profile"]["profile_sha256"] = hashlib.sha256(
            profile_path.read_bytes()
        ).hexdigest()

    def test_accepts_exact_checksum_bound_v13_authorisation(self) -> None:
        manifest, manifest_path = self.manifest()

        self.validate(manifest, manifest_path)

    def test_rejects_false_profile_database_action_authorisation(self) -> None:
        manifest, manifest_path = self.manifest(
            profile_updates={"database_action_authorised": False}
        )

        with self.assertRaisesRegex(SystemExit, "database action authorisation"):
            self.validate(manifest, manifest_path)

    def test_rejects_unexpected_manifest_project(self) -> None:
        manifest, manifest_path = self.manifest()
        manifest["authorisation"] = {
            **EXPECTED_AUTHORISATION,
            "project_ref": "unexpected-project",
        }

        with self.assertRaisesRegex(SystemExit, "database action authorisation"):
            self.validate(manifest, manifest_path)

    def test_rejects_mutated_authorisation_at_each_execution_boundary(self) -> None:
        cases = (
            ("manifest", "database", "unexpected_database"),
            ("envelope", "actions", ["ingestion", "processing", "build"]),
            ("profile", "approval_line_sha256", "0" * 64),
        )
        for boundary, field, value in cases:
            with self.subTest(boundary=boundary, field=field):
                manifest, manifest_path = self.manifest()
                changed = {**EXPECTED_AUTHORISATION, field: value}
                if boundary == "manifest":
                    manifest["authorisation"] = changed
                elif boundary == "envelope":
                    manifest["intake_profile"]["authorisation"] = changed
                else:
                    self.rewrite_profile(manifest, {"authorisation": changed})

                with self.assertRaisesRegex(SystemExit, "database action authorisation"):
                    self.validate(manifest, manifest_path)

    def test_rejects_missing_or_false_authorisation_flags(self) -> None:
        for boundary in ("manifest", "envelope", "profile"):
            with self.subTest(boundary=boundary):
                manifest, manifest_path = self.manifest()
                if boundary == "manifest":
                    manifest.pop("database_action_authorised")
                elif boundary == "envelope":
                    manifest["intake_profile"]["database_action_authorised"] = False
                else:
                    self.rewrite_profile(
                        manifest, {"database_action_authorised": False}
                    )

                with self.assertRaisesRegex(SystemExit, "database action authorisation"):
                    self.validate(manifest, manifest_path)

    def test_rejects_mixed_v13_and_legacy_schema_markers(self) -> None:
        manifest, manifest_path = self.manifest()
        manifest["schema"] = "legacy_intake_manifest"

        with self.assertRaisesRegex(SystemExit, "database action authorisation"):
            self.validate(manifest, manifest_path)

    def test_rejects_year2_v13_authorisation_marker_removal(self) -> None:
        manifest, manifest_path = self.manifest()
        for field in ("schema", "database_action_authorised", "authorisation"):
            manifest.pop(field)
            manifest["intake_profile"].pop(field, None)
        profile_path = self.root / manifest["intake_profile"]["profile_path"]
        profile = json.loads(profile_path.read_text())
        for field in ("schema", "database_action_authorised", "authorisation"):
            profile.pop(field)
        profile_path.write_text(json.dumps(profile, sort_keys=True) + "\n")
        manifest["intake_profile"]["profile_sha256"] = hashlib.sha256(
            profile_path.read_bytes()
        ).hexdigest()

        with self.assertRaisesRegex(SystemExit, "database action authorisation"):
            self.validate(manifest, manifest_path)

    def test_rejects_profile_authorisation_mutation_without_matching_checksum(self) -> None:
        manifest, manifest_path = self.manifest()
        profile_path = self.root / manifest["intake_profile"]["profile_path"]
        profile = json.loads(profile_path.read_text())
        profile["authorisation"] = {
            **EXPECTED_AUTHORISATION,
            "database": "unexpected_database",
        }
        profile_path.write_text(json.dumps(profile, sort_keys=True) + "\n")

        with self.assertRaisesRegex(SystemExit, "evidence checksum mismatch"):
            self.validate(manifest, manifest_path)


if __name__ == "__main__":
    unittest.main()
