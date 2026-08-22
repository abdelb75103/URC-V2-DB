import argparse
import hashlib
import json
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from pipeline.__main__ import (
    V13_REVIEWED_V12_TEAMS,
    ingest,
    validate_intake_profile_manifest,
    validate_v13_signed_root_candidate,
)


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
EXPECTED_APPROVAL_LINE = (
    "I approve URC 2025-26 V12, root SHA-256 "
    "01dd17a82ab1835fd84f2c84048b9e15b4072a4f9bca3b3d3a348817a68d7241 "
    "and file-set SHA-256 "
    "5ea322d4e246510ce82075f5690ea2ac5715dace31ead35bff9db3bacc6a7abd, "
    "for ingestion, processing, build and release on project "
    "eukkvswaxweenovqqgzr database postgres."
)
EXPECTED_INJURY_SHA256 = (
    "58602000b171e29d0db271eec95b4357508a484602a1e80d95b20d1d1cde4d9b"
)
EXPECTED_EXPOSURE_SHA256 = (
    "6d9fdd02873a2b69c81cd2ce1e6bfe1bd4c82812ae710e52f1809c3ebcb40c61"
)
EXPECTED_TEAM_MANIFEST_SHA256 = (
    "61ea454fb28bb98db8f6c6df2ddfef95873ed145c19a7542b442af88b73ee408"
)
EXPECTED_REVIEW_SHA256 = (
    "61caebf232f0422f7bd5340609c113b0e0931ab01f15262f75a1e5da860ae1df"
)
EXPECTED_HARNESS_SHA256 = (
    "03d3d2e10df00a5702d7d88e5f1be6cfb619353557859b24a7ec2db2d4acaf43"
)
EXPECTED_REVIEW = {
    "path": "provenance/v12_fresh_ai_review_evidence.json",
    "sha256": EXPECTED_REVIEW_SHA256,
    "reviewer": {
        "model": "gpt-5.6-sol",
        "reasoning_effort": "xhigh",
        "task": "/root/v13_signer_acceptance",
        "completed_at": "2026-08-22T17:55:08Z",
    },
    "decision": "COMPLETED_WITH_RECORDED_LIMITATIONS",
    "v12_root_manifest_sha256": (
        "01dd17a82ab1835fd84f2c84048b9e15b4072a4f9bca3b3d3a348817a68d7241"
    ),
    "v12_root_file_set_sha256": (
        "5ea322d4e246510ce82075f5690ea2ac5715dace31ead35bff9db3bacc6a7abd"
    ),
}


class V13IntakeAuthorisationGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.package_root = Path(self.tempdir.name) / "v13-package"
        self.root = self.package_root / "benetton"
        self.root.mkdir(parents=True)
        provenance = self.package_root / "provenance"
        provenance.mkdir()
        (provenance / "v13_signing_harness.py").write_text("# fixture\n")
        (provenance / "v13_signing_harness_config.json").write_text("{}\n")
        (provenance / "v12_fresh_ai_review_evidence.json").write_text("{}\n")
        (self.root / "intake_manifest_v12.json").write_text("{}\n")
        self.input_sha = EXPECTED_INJURY_SHA256
        now = datetime.now(UTC)
        mapping_path = self.root / "source_to_pipeline_mapping_v10.json"
        mapping_path.write_text(
            json.dumps(
                {
                    "mapping_version": "urc_2025_26_v10",
                    "mappings": [
                        {
                            "canonical_field": "player_uid",
                            "canonical_value": "pseudonymised",
                            "source_evidence": {"PlayerID": "pseudonymised"},
                            "evidence_class": "source_reported",
                        }
                    ],
                },
                sort_keys=True,
            )
            + "\n"
        )
        inputs = {
            "injury": {
                "path": "injury_intake_locator_enriched_v10.csv",
                "sha256": EXPECTED_INJURY_SHA256,
            },
            "exposure": {
                "path": "exposure_intake_final_clean_v10.csv",
                "sha256": EXPECTED_EXPOSURE_SHA256,
            },
        }
        harness_provenance = {
            "script": {
                "path": "provenance/v13_signing_harness.py",
                "sha256": EXPECTED_HARNESS_SHA256,
            },
            "config": {
                "path": "provenance/v13_signing_harness_config.json",
                "sha256": hashlib.sha256(
                    (provenance / "v13_signing_harness_config.json").read_bytes()
                ).hexdigest(),
            },
            "fresh_ai_review_evidence": {
                "path": "provenance/v12_fresh_ai_review_evidence.json",
                "sha256": EXPECTED_REVIEW_SHA256,
            },
        }
        self.profile = {
            "schema": "urc_2025_26_v13_signed_intake_profile_v1",
            "team": "Benetton",
            "team_key": "benetton",
            "season": "2025-26",
            "profile_version": "urc_2025_26_v13_signed_profile_v1",
            "decision": "adapter_required",
            "mapping_path": mapping_path.name,
            "mapping_sha256": hashlib.sha256(mapping_path.read_bytes()).hexdigest(),
            "mapping_version": "urc_2025_26_v10",
            "ai_review_status": "completed",
            "ai_reviewed_by": "gpt-5.6-sol/xhigh /root/v13_signer_acceptance",
            "ai_reviewed_at": "2026-08-22T17:55:08Z",
            "approved_by": "Abdel Babiker",
            "approved_at": (now - timedelta(minutes=1)).isoformat(),
            "approval_ready": True,
            "ingest_ready": True,
            "database_action_authorised": True,
            "authorisation": EXPECTED_AUTHORISATION,
            "unresolved_adjudication_ids": [],
            "approved_input_sha256s": [
                EXPECTED_INJURY_SHA256,
                EXPECTED_EXPOSURE_SHA256,
            ],
            "v12_input_bindings": inputs,
            "v12_manifest": {
                "path": "intake_manifest_v12.json",
                "sha256": EXPECTED_TEAM_MANIFEST_SHA256,
            },
            "fresh_ai_review_evidence": EXPECTED_REVIEW,
            "harness_provenance": harness_provenance,
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
            "team_key": profile["team_key"],
            "season": profile["season"],
            "source_v12_manifest": profile["v12_manifest"],
            "v12_input_bindings": profile["v12_input_bindings"],
            "fresh_ai_review_evidence": profile["fresh_ai_review_evidence"],
            "harness_provenance": profile["harness_provenance"],
            "intake_profile": envelope,
            "approval_ready": True,
            "ingest_ready": True,
            "database_action_authorised": True,
            "authorisation": EXPECTED_AUTHORISATION,
        }
        return manifest, self.root / "v13_approved_intake_manifest.json"

    def fixture_sha256(self, path: Path) -> str:
        if path.parent.name in V13_REVIEWED_V12_TEAMS:
            _, injury_sha, exposure_sha, manifest_sha = V13_REVIEWED_V12_TEAMS[
                path.parent.name
            ]
            if path.name == "injury_intake_locator_enriched_v10.csv":
                return injury_sha
            if path.name == "exposure_intake_final_clean_v10.csv":
                return exposure_sha
            if path.name == "intake_manifest_v12.json":
                return manifest_sha
        if path.name == "v12_fresh_ai_review_evidence.json":
            return EXPECTED_REVIEW_SHA256
        if path.name == "v13_signing_harness.py":
            return EXPECTED_HARNESS_SHA256
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def validate(
        self,
        manifest: dict,
        manifest_path: Path,
        *,
        input_path: Path | None = None,
    ) -> None:
        with patch("pipeline.__main__.sha256_file", side_effect=self.fixture_sha256):
            validate_intake_profile_manifest(
                manifest,
                manifest_path,
                self.input_sha,
                "Benetton",
                "2025-26",
                input_path=input_path,
            )

    def rewrite_profile(self, manifest: dict, update: dict) -> None:
        profile_path = self.root / manifest["intake_profile"]["profile_path"]
        profile = json.loads(profile_path.read_text())
        profile.update(update)
        profile_path.write_text(json.dumps(profile, sort_keys=True) + "\n")
        manifest["intake_profile"]["profile_sha256"] = hashlib.sha256(
            profile_path.read_bytes()
        ).hexdigest()

    def build_signed_root_fixture(
        self,
    ) -> tuple[dict, Path, Path, Path, dict[str, str]]:
        config_path = self.package_root / "provenance" / "v13_signing_harness_config.json"
        accepted_sources = {
            "pipeline/__init__.py": "1" * 64,
            "pipeline/__main__.py": "2" * 64,
            "pipeline/season_contracts.py": "3" * 64,
        }
        config = {
            "schema": "urc_2025_26_v13_signing_harness_config_v3",
            "source_package": (
                "all_16_intake_envelopes_20260822_v12_duplicate_safe_candidate"
            ),
            "successor_package": self.package_root.name,
            "source_root_manifest": "v12_duplicate_safe_root_manifest.json",
            "successor_root_manifest": "v13_signed_root_manifest.json",
            "expected_v12_root_manifest_sha256": (
                EXPECTED_REVIEW["v12_root_manifest_sha256"]
            ),
            "expected_v12_root_file_set_sha256": (
                EXPECTED_REVIEW["v12_root_file_set_sha256"]
            ),
            "expected_v12_non_root_file_count": 196,
            "required_approval_line": EXPECTED_APPROVAL_LINE,
            "required_approver": "Abdel Babiker",
            "required_team_count": 16,
            "repository_root": str(Path.cwd()),
            "repository_acceptance_commit": "c" * 40,
            "repository_validator_main_sha256": accepted_sources[
                "pipeline/__main__.py"
            ],
            "approval_bearing_files": {
                "profile": "v13_approved_intake_profile.json",
                "manifest": "v13_approved_intake_manifest.json",
            },
            "fresh_ai_review": {
                "filename": "v12_fresh_ai_review_evidence.json",
                "sha256": EXPECTED_REVIEW_SHA256,
                **EXPECTED_REVIEW["reviewer"],
            },
            "database_authorisation": {
                "project_ref": "eukkvswaxweenovqqgzr",
                "database": "postgres",
                "actions": ["ingestion", "processing", "build", "release"],
            },
        }
        config_path.write_text(json.dumps(config, sort_keys=True) + "\n")
        config_sha = self.fixture_sha256(config_path)
        self.profile["harness_provenance"]["config"]["sha256"] = config_sha

        manifest, manifest_path = self.manifest()
        approved_at = self.profile["approved_at"]
        manifest.update(
            {
                "approved_by": "Abdel Babiker",
                "approved_at": approved_at,
                "approval_line_sha256": EXPECTED_AUTHORISATION[
                    "approval_line_sha256"
                ],
            }
        )
        manifest_path.write_text(json.dumps(manifest, sort_keys=True) + "\n")

        for team_key in V13_REVIEWED_V12_TEAMS:
            team_root = self.package_root / team_key
            team_root.mkdir(exist_ok=True)
            for filename in (
                "injury_intake_locator_enriched_v10.csv",
                "exposure_intake_final_clean_v10.csv",
                "intake_manifest_v12.json",
            ):
                path = team_root / filename
                if not path.exists():
                    path.write_text("fixture\n")
            if team_key != "benetton":
                (team_root / "v13_approved_intake_profile.json").write_text(
                    json.dumps({"team_key": team_key}) + "\n"
                )
                (team_root / "v13_approved_intake_manifest.json").write_text(
                    json.dumps({"team_key": team_key}) + "\n"
                )

        signing = {
            "schema": "urc_2025_26_v13_signing_record_v1",
            "approved_by": "Abdel Babiker",
            "approved_at": approved_at,
            "approval_line_sha256": EXPECTED_AUTHORISATION[
                "approval_line_sha256"
            ],
            "v12_root_manifest_sha256": EXPECTED_REVIEW[
                "v12_root_manifest_sha256"
            ],
            "v12_root_file_set_sha256": EXPECTED_REVIEW[
                "v12_root_file_set_sha256"
            ],
            "candidate_preservation": {
                "v12_non_root_file_count": 196,
                "all_v12_non_root_bytes_preserved": True,
                "physical_v12_root_manifest_copied": False,
                "coverage_limitations_preserved": True,
            },
            "repository_validator": {
                "entry_point": "pipeline.__main__.validate_intake_profile_manifest",
                "acceptance_commit": "c" * 40,
                "source_sha256s": accepted_sources,
                "passed_team_count": 16,
                "validated_input_count": 32,
                "status": "pass",
            },
            "database_action_authorised": True,
            "authorisation": EXPECTED_AUTHORISATION,
            "fresh_ai_review_evidence": EXPECTED_REVIEW,
            "harness_provenance": self.profile["harness_provenance"],
        }
        signing_path = self.package_root / "v13_signing_record.json"
        signing_path.write_text(json.dumps(signing, sort_keys=True) + "\n")

        output_sha256s = {
            path.relative_to(self.package_root).as_posix(): self.fixture_sha256(path)
            for path in sorted(self.package_root.rglob("*"))
            if path.is_file() and path.name != "v13_signed_root_manifest.json"
        }
        validator_results = []
        for team_key in V13_REVIEWED_V12_TEAMS:
            validator_results.append(
                {
                    "team_key": team_key,
                    "status": "pass",
                    "validated_inputs": ["injury", "exposure"],
                    "profile_sha256": output_sha256s[
                        f"{team_key}/v13_approved_intake_profile.json"
                    ],
                    "manifest_sha256": output_sha256s[
                        f"{team_key}/v13_approved_intake_manifest.json"
                    ],
                }
            )
        root = {
            "schema": "urc_2025_26_v13_signed_root_manifest_v1",
            "season": "2025-26",
            "predecessor": {
                "package": config["source_package"],
                "root_manifest_sha256": EXPECTED_REVIEW[
                    "v12_root_manifest_sha256"
                ],
                "root_file_set_sha256": EXPECTED_REVIEW[
                    "v12_root_file_set_sha256"
                ],
            },
            "approved_by": "Abdel Babiker",
            "approved_at": approved_at,
            "approval_line_sha256": EXPECTED_AUTHORISATION[
                "approval_line_sha256"
            ],
            "approval_ready": True,
            "ingest_ready": True,
            "database_action_authorised": True,
            "authorisation": EXPECTED_AUTHORISATION,
            "output_sha256s": output_sha256s,
            "root_file_set_sha256": hashlib.sha256(
                json.dumps(
                    output_sha256s, sort_keys=True, separators=(",", ":")
                ).encode()
            ).hexdigest(),
            "signing_record": {
                "path": signing_path.name,
                "sha256": output_sha256s[signing_path.name],
            },
            "validator_results": validator_results,
            "fresh_ai_review_evidence": EXPECTED_REVIEW,
            "harness_provenance": self.profile["harness_provenance"],
        }
        root_path = self.package_root / "v13_signed_root_manifest.json"
        root_path.write_text(json.dumps(root, sort_keys=True) + "\n")
        input_path = self.root / "injury_intake_locator_enriched_v10.csv"
        return manifest, manifest_path, input_path, root_path, accepted_sources

    def reclose_root(self, root_path: Path) -> None:
        root = json.loads(root_path.read_text())
        output_sha256s = {
            path.relative_to(self.package_root).as_posix(): self.fixture_sha256(path)
            for path in sorted(self.package_root.rglob("*"))
            if path.is_file() and path.resolve() != root_path.resolve()
        }
        root["output_sha256s"] = output_sha256s
        root["root_file_set_sha256"] = hashlib.sha256(
            json.dumps(output_sha256s, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        root["signing_record"] = {
            "path": "v13_signing_record.json",
            "sha256": output_sha256s["v13_signing_record.json"],
        }
        root_path.write_text(json.dumps(root, sort_keys=True) + "\n")

    def test_accepts_exact_checksum_bound_v13_authorisation(self) -> None:
        manifest, manifest_path = self.manifest()

        self.validate(manifest, manifest_path)

    def test_ingest_rejects_synthetic_authorisation_before_sql(self) -> None:
        intake_path = self.root / "synthetic.csv"
        intake_path.write_text("player_uid\nply_synthetic\n")
        input_sha = hashlib.sha256(intake_path.read_bytes()).hexdigest()
        self.input_sha = input_sha
        self.profile["approved_input_sha256s"] = [input_sha]
        manifest, manifest_path = self.manifest()
        for field in (
            "source_v12_manifest",
            "v12_input_bindings",
            "fresh_ai_review_evidence",
            "harness_provenance",
        ):
            manifest.pop(field)
        profile_path = self.root / manifest["intake_profile"]["profile_path"]
        profile = json.loads(profile_path.read_text())
        for field in (
            "v12_manifest",
            "v12_input_bindings",
            "fresh_ai_review_evidence",
            "harness_provenance",
        ):
            profile.pop(field)
        profile_path.write_text(json.dumps(profile, sort_keys=True) + "\n")
        manifest["intake_profile"]["profile_sha256"] = hashlib.sha256(
            profile_path.read_bytes()
        ).hexdigest()
        manifest_path.write_text(json.dumps(manifest, sort_keys=True) + "\n")

        with (
            patch("pipeline.__main__.run_sql") as run_sql,
            patch("pipeline.__main__.load_fixture_team_aliases", return_value={}),
            self.assertRaisesRegex(SystemExit, "--signed-root-manifest is required"),
        ):
            ingest(
                argparse.Namespace(
                    file=str(intake_path),
                    manifest=str(manifest_path),
                    team="Benetton",
                    season="2025-26",
                    exclude_source_fields="",
                    redact_manifest_keys="",
                    redact_source_values="",
                )
            )
        run_sql.assert_not_called()

    def test_signed_candidate_root_exact_fixture_passes_internal_validation(self) -> None:
        manifest, manifest_path, input_path, root_path, accepted_sources = (
            self.build_signed_root_fixture()
        )
        del manifest
        with (
            patch("pipeline.__main__.sha256_file", side_effect=self.fixture_sha256),
            patch(
                "pipeline.__main__.accepted_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch(
                "pipeline.__main__.current_repository_source_sha256s",
                return_value=accepted_sources,
            ),
        ):
            root_sha = validate_v13_signed_root_candidate(
                root_path,
                manifest_path,
                input_path,
                EXPECTED_INJURY_SHA256,
                "Benetton",
                "2025-26",
            )

        self.assertEqual(self.fixture_sha256(root_path), root_sha)

    def test_ingest_rejects_exact_but_unlisted_root_before_sql(self) -> None:
        _, manifest_path, input_path, root_path, accepted_sources = (
            self.build_signed_root_fixture()
        )
        with (
            patch("pipeline.__main__.sha256_file", side_effect=self.fixture_sha256),
            patch(
                "pipeline.__main__.accepted_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch(
                "pipeline.__main__.current_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch("pipeline.__main__.repository_file_matches_head", return_value=True),
            patch("pipeline.__main__.run_sql") as run_sql,
            self.assertRaisesRegex(SystemExit, "not present in the approved Year2 root ledger"),
        ):
            ingest(
                argparse.Namespace(
                    file=str(input_path),
                    manifest=str(manifest_path),
                    signed_root_manifest=str(root_path),
                    team="Benetton",
                    season="2025-26",
                    exclude_source_fields="",
                    redact_manifest_keys="",
                    redact_source_values="",
                )
            )
        run_sql.assert_not_called()

    def test_ingest_rejects_signed_root_drift_before_sql(self) -> None:
        _, manifest_path, input_path, root_path, accepted_sources = (
            self.build_signed_root_fixture()
        )
        root = json.loads(root_path.read_text())
        root["approved_by"] = "Unexpected Reviewer"
        root_path.write_text(json.dumps(root, sort_keys=True) + "\n")
        with (
            patch("pipeline.__main__.sha256_file", side_effect=self.fixture_sha256),
            patch(
                "pipeline.__main__.accepted_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch(
                "pipeline.__main__.current_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch("pipeline.__main__.run_sql") as run_sql,
            self.assertRaisesRegex(SystemExit, "root approval or predecessor binding"),
        ):
            ingest(
                argparse.Namespace(
                    file=str(input_path),
                    manifest=str(manifest_path),
                    signed_root_manifest=str(root_path),
                    team="Benetton",
                    season="2025-26",
                    exclude_source_fields="",
                    redact_manifest_keys="",
                    redact_source_values="",
                )
            )
        run_sql.assert_not_called()

    def test_ingest_rejects_missing_root_membership_before_sql(self) -> None:
        _, manifest_path, input_path, root_path, accepted_sources = (
            self.build_signed_root_fixture()
        )
        (self.package_root / "zebre" / "intake_manifest_v12.json").unlink()
        with (
            patch("pipeline.__main__.sha256_file", side_effect=self.fixture_sha256),
            patch(
                "pipeline.__main__.accepted_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch(
                "pipeline.__main__.current_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch("pipeline.__main__.run_sql") as run_sql,
            self.assertRaisesRegex(SystemExit, "does not close the physical package"),
        ):
            ingest(
                argparse.Namespace(
                    file=str(input_path),
                    manifest=str(manifest_path),
                    signed_root_manifest=str(root_path),
                    team="Benetton",
                    season="2025-26",
                    exclude_source_fields="",
                    redact_manifest_keys="",
                    redact_source_values="",
                )
            )
        run_sql.assert_not_called()

    def test_ingest_rejects_signing_record_mismatch_before_sql(self) -> None:
        _, manifest_path, input_path, root_path, accepted_sources = (
            self.build_signed_root_fixture()
        )
        signing_path = self.package_root / "v13_signing_record.json"
        signing = json.loads(signing_path.read_text())
        signing["approved_at"] = "2026-08-22T00:00:00Z"
        signing_path.write_text(json.dumps(signing, sort_keys=True) + "\n")
        self.reclose_root(root_path)
        with (
            patch("pipeline.__main__.sha256_file", side_effect=self.fixture_sha256),
            patch(
                "pipeline.__main__.accepted_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch(
                "pipeline.__main__.current_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch("pipeline.__main__.run_sql") as run_sql,
            self.assertRaisesRegex(SystemExit, "signing record differs"),
        ):
            ingest(
                argparse.Namespace(
                    file=str(input_path),
                    manifest=str(manifest_path),
                    signed_root_manifest=str(root_path),
                    team="Benetton",
                    season="2025-26",
                    exclude_source_fields="",
                    redact_manifest_keys="",
                    redact_source_values="",
                )
            )
        run_sql.assert_not_called()

    def test_ingest_passes_only_when_exact_root_is_temporarily_allowlisted(self) -> None:
        _, manifest_path, input_path, root_path, accepted_sources = (
            self.build_signed_root_fixture()
        )
        ledger_path = Path(self.tempdir.name) / "approved_roots_fixture.json"
        root_sha = self.fixture_sha256(root_path)
        ledger_path.write_text(
            json.dumps(
                {
                    "schema": "urc_2025_26_approved_roots_v1",
                    "approved_root_sha256s": [root_sha],
                },
                sort_keys=True,
            )
            + "\n"
        )
        with (
            patch("pipeline.__main__.sha256_file", side_effect=self.fixture_sha256),
            patch(
                "pipeline.__main__.accepted_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch(
                "pipeline.__main__.current_repository_source_sha256s",
                return_value=accepted_sources,
            ),
            patch("pipeline.__main__.YEAR2_APPROVED_ROOTS_PATH", ledger_path),
            patch("pipeline.__main__.repository_file_matches_head", return_value=True),
            patch("pipeline.__main__.load_fixture_team_aliases", return_value={}),
            patch("pipeline.__main__.run_sql") as run_sql,
        ):
            ingest(
                argparse.Namespace(
                    file=str(input_path),
                    manifest=str(manifest_path),
                    signed_root_manifest=str(root_path),
                    team="Benetton",
                    season="2025-26",
                    exclude_source_fields="",
                    redact_manifest_keys="",
                    redact_source_values="",
                )
            )
        run_sql.assert_called_once()

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

    def test_rejects_review_package_mutation_at_manifest_root(self) -> None:
        mutations = (
            (
                "source_v12_manifest",
                {"path": "intake_manifest_v12.json", "sha256": "0" * 64},
            ),
            (
                "v12_input_bindings",
                {
                    "injury": {
                        "path": "injury_intake_locator_enriched_v10.csv",
                        "sha256": "0" * 64,
                    },
                    "exposure": self.profile["v12_input_bindings"]["exposure"],
                },
            ),
            (
                "fresh_ai_review_evidence",
                {**EXPECTED_REVIEW, "decision": "COMPLETED"},
            ),
            (
                "harness_provenance",
                {
                    **self.profile["harness_provenance"],
                    "script": {
                        "path": "provenance/v13_signing_harness.py",
                        "sha256": "0" * 64,
                    },
                },
            ),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                manifest, manifest_path = self.manifest()
                manifest[field] = json.loads(json.dumps(value))

                with self.assertRaisesRegex(
                    SystemExit, "reviewed V12 package binding|package provenance"
                ):
                    self.validate(manifest, manifest_path)

    def test_rejects_review_package_removal_at_manifest_root(self) -> None:
        for field in (
            "source_v12_manifest",
            "v12_input_bindings",
            "fresh_ai_review_evidence",
            "harness_provenance",
        ):
            with self.subTest(field=field):
                manifest, manifest_path = self.manifest()
                manifest.pop(field)

                with self.assertRaisesRegex(
                    SystemExit, "reviewed V12 package binding|package provenance"
                ):
                    self.validate(manifest, manifest_path)

    def test_rejects_review_package_mutation_in_checksummed_profile(self) -> None:
        mutations = (
            (
                "v12_manifest",
                {"path": "intake_manifest_v12.json", "sha256": "0" * 64},
            ),
            (
                "v12_input_bindings",
                {
                    **self.profile["v12_input_bindings"],
                    "injury": {
                        "path": "injury_intake_locator_enriched_v10.csv",
                        "sha256": "0" * 64,
                    },
                },
            ),
            (
                "fresh_ai_review_evidence",
                {**EXPECTED_REVIEW, "v12_root_manifest_sha256": "0" * 64},
            ),
            (
                "harness_provenance",
                {
                    **self.profile["harness_provenance"],
                    "fresh_ai_review_evidence": {
                        "path": "provenance/v12_fresh_ai_review_evidence.json",
                        "sha256": "0" * 64,
                    },
                },
            ),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                manifest, manifest_path = self.manifest()
                self.rewrite_profile(manifest, {field: json.loads(json.dumps(value))})

                with self.assertRaisesRegex(
                    SystemExit, "reviewed V12 package binding|package provenance"
                ):
                    self.validate(manifest, manifest_path)

    def test_rejects_review_package_removal_from_checksummed_profile(self) -> None:
        for field in (
            "v12_manifest",
            "v12_input_bindings",
            "fresh_ai_review_evidence",
            "harness_provenance",
        ):
            with self.subTest(field=field):
                manifest, manifest_path = self.manifest()
                profile_path = self.root / manifest["intake_profile"]["profile_path"]
                profile = json.loads(profile_path.read_text())
                profile.pop(field)
                profile_path.write_text(json.dumps(profile, sort_keys=True) + "\n")
                manifest["intake_profile"]["profile_sha256"] = hashlib.sha256(
                    profile_path.read_bytes()
                ).hexdigest()

                with self.assertRaisesRegex(
                    SystemExit, "reviewed V12 package binding|package provenance"
                ):
                    self.validate(manifest, manifest_path)

    def test_embedded_envelope_checksum_binds_reviewed_profile(self) -> None:
        manifest, manifest_path = self.manifest()
        manifest["intake_profile"]["profile_sha256"] = "0" * 64

        with self.assertRaisesRegex(SystemExit, "evidence checksum mismatch"):
            self.validate(manifest, manifest_path)

    def test_embedded_envelope_cannot_change_approved_inputs(self) -> None:
        manifest, manifest_path = self.manifest()
        manifest["intake_profile"]["approved_input_sha256s"] = ["0" * 64]

        with self.assertRaisesRegex(SystemExit, "current intake checksum is not covered"):
            self.validate(manifest, manifest_path)

    def test_rejects_wrong_current_input_filename(self) -> None:
        manifest, manifest_path = self.manifest()

        with self.assertRaisesRegex(SystemExit, "current input does not match"):
            self.validate(
                manifest,
                manifest_path,
                input_path=self.root / "unexpected.csv",
            )

    def test_rejects_missing_bound_source_v12_manifest_file(self) -> None:
        manifest, manifest_path = self.manifest()
        (self.root / "intake_manifest_v12.json").unlink()

        with self.assertRaisesRegex(SystemExit, "team-manifest checksum mismatch"):
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
