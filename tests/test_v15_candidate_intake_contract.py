from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import pipeline.__main__ as pipeline


def write_json(path: Path, value: object) -> str:
    path.write_text(json.dumps(value, sort_keys=True) + "\n")
    path.chmod(0o600)
    return hashlib.sha256(path.read_bytes()).hexdigest()


class V15CandidateIntakeContractTests(unittest.TestCase):
    def build_root(self) -> tuple[Path, dict[str, object], dict[str, str]]:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        root.chmod(0o700)
        approval_line = "Register these six candidate source inputs only."
        approval_sha = hashlib.sha256(approval_line.encode()).hexdigest()
        bindings = []
        members: dict[str, str] = {}
        for team_key, input_kind in pipeline.V15_CANDIDATE_INPUT_KINDS.items():
            team_dir = root / team_key
            team_dir.mkdir()
            team_dir.chmod(0o700)
            input_path = team_dir / f"{input_kind}.csv"
            input_path.write_text("field\nvalue\n")
            input_path.chmod(0o600)
            profile_path = team_dir / "profile.json"
            mapping_path = team_dir / "mapping.json"
            manifest_path = team_dir / "manifest.json"
            profile_sha = write_json(profile_path, {"schema": pipeline.V15_CANDIDATE_PROFILE_SCHEMA})
            mapping_sha = write_json(mapping_path, {"mapping_version": "v15", "mappings": [{"canonical_field": "x"}]})
            input_sha = hashlib.sha256(input_path.read_bytes()).hexdigest()
            manifest = {
                "schema": pipeline.V15_CANDIDATE_MANIFEST_SCHEMA,
                "team_key": team_key,
                "input_kind": input_kind,
                "authorisation": pipeline.V15_CANDIDATE_AUTHORISATION,
                "approval_line": approval_line,
                "approval_line_sha256": approval_sha,
                "intake_profile": {
                    "profile_path": "profile.json",
                    "mapping_path": "mapping.json",
                },
            }
            manifest_sha = write_json(manifest_path, manifest)
            bindings.append({
                "team_key": team_key,
                "input_kind": input_kind,
                "input": f"{team_key}/{input_path.name}",
                "input_sha256": input_sha,
                "manifest": f"{team_key}/{manifest_path.name}",
                "manifest_sha256": manifest_sha,
                "profile": f"{team_key}/{profile_path.name}",
                "profile_sha256": profile_sha,
                "mapping": f"{team_key}/{mapping_path.name}",
                "mapping_sha256": mapping_sha,
            })
            members[team_key] = str(manifest_path)
        outputs = {
            path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob("*") if path.is_file()
        }
        root_manifest = {
            "schema": pipeline.V15_CANDIDATE_ROOT_SCHEMA,
            "season": "2025-26",
            "candidate_scope": "isolated_candidate_only",
            "approved_by": "Abdel Babiker",
            "approval_ready": True,
            "ingest_ready": True,
            "approval_line": approval_line,
            "approval_line_sha256": approval_sha,
            "authorisation": pipeline.V15_CANDIDATE_AUTHORISATION,
            "team_inputs": bindings,
            "output_sha256s": outputs,
            "root_file_set_sha256": hashlib.sha256(
                json.dumps(outputs, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest(),
        }
        root_path = root / "v15_candidate_intake_root_manifest.json"
        write_json(root_path, root_manifest)
        return root_path, root_manifest, members

    def test_exact_six_input_ingestion_only_root_passes(self) -> None:
        root_path, _, members = self.build_root()
        manifest_path = Path(members["benetton"])
        input_path = manifest_path.with_name("exposure.csv")
        with patch.object(pipeline, "validate_intake_profile_manifest") as validate_profile:
            digest = pipeline.validate_v15_candidate_root_for_ingest(
                root_path, manifest_path, input_path,
                hashlib.sha256(input_path.read_bytes()).hexdigest(), "Benetton", "2025-26",
            )
        self.assertEqual(digest, hashlib.sha256(root_path.read_bytes()).hexdigest())
        self.assertEqual(validate_profile.call_count, 6)

    def test_release_scope_is_rejected_before_member_validation(self) -> None:
        root_path, root, members = self.build_root()
        root["authorisation"] = {
            **pipeline.V15_CANDIDATE_AUTHORISATION,
            "actions": ["ingestion", "release"],
        }
        write_json(root_path, root)
        manifest_path = Path(members["benetton"])
        input_path = manifest_path.with_name("exposure.csv")
        with self.assertRaisesRegex(SystemExit, "scope"):
            pipeline.validate_v15_candidate_root_for_ingest(
                root_path, manifest_path, input_path,
                hashlib.sha256(input_path.read_bytes()).hexdigest(), "Benetton", "2025-26",
            )


if __name__ == "__main__":
    unittest.main()
