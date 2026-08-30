#!/usr/bin/env python3
"""Build the closed 14-team Year 2 exposure approval package."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from datetime import datetime
from pathlib import Path

from pipeline.__main__ import (
    V13_REVIEWED_V12_TEAMS,
    V14_EXPOSURE_CANDIDATE_MANIFEST_SHA256,
    V14_EXPOSURE_CANDIDATE_QC_SHA256,
    V14_EXPOSURE_MANIFEST_SCHEMA,
    V14_EXPOSURE_PROFILE_SCHEMA,
    V14_EXPOSURE_ROOT_SCHEMA,
    V14_EXPOSURE_SHA256S,
    V14_EXPOSURE_TASK_APPROVAL_SHA256,
    sha256_file,
    validate_v14_task_approval_evidence,
)

AUTHORISATION = {
    "database_action_authorised": True,
    "project_ref": "eukkvswaxweenovqqgzr",
    "database": "postgres",
    "actions": ["ingestion", "processing", "build", "migration", "release"],
}


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    path.chmod(0o600)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--review-evidence", type=Path, required=True)
    parser.add_argument("--approval-evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    candidate = args.candidate.resolve()
    output = args.output.absolute()
    if output.exists():
        raise SystemExit(f"output already exists: {output}")
    review = json.loads(args.review_evidence.read_text())
    approval, requested_at = validate_v14_task_approval_evidence(
        args.approval_evidence
    )
    reviewer = review.get("reviewer") if isinstance(review, dict) else None
    if (
        not isinstance(review, dict)
        or review.get("decision") != "PASS"
        or not isinstance(reviewer, dict)
        or reviewer.get("model") != "gpt-5.6-sol"
        or reviewer.get("reasoning_effort") not in {"high", "xhigh"}
    ):
        raise SystemExit("review evidence must contain a passing independent Sol review")
    approval_line = approval.get("approval_statement")
    candidate_manifest = candidate / "exposure_scope_adjudication_manifest.json"
    candidate_qc = candidate / "exposure_scope_adjudication_qc.json"
    if sha256_file(candidate_manifest) != V14_EXPOSURE_CANDIDATE_MANIFEST_SHA256:
        raise SystemExit("candidate manifest checksum mismatch")
    if sha256_file(candidate_qc) != V14_EXPOSURE_CANDIDATE_QC_SHA256:
        raise SystemExit("candidate QC checksum mismatch")

    output.mkdir(mode=0o700, parents=False)
    (output / "evidence").mkdir(mode=0o700)
    reviewed_at = datetime.fromisoformat(review["completed_at"].replace("Z", "+00:00"))
    if reviewed_at.tzinfo is None or requested_at.tzinfo is None or reviewed_at < requested_at:
        raise SystemExit("review must complete after the conditional task authorisation")
    approved_at = review["completed_at"]
    approval_sha256 = hashlib.sha256(approval_line.encode()).hexdigest()
    copied_evidence = {
        "candidate_manifest": (
            candidate_manifest,
            output / "evidence" / "exposure_scope_adjudication_manifest.json",
        ),
        "candidate_qc": (
            candidate_qc,
            output / "evidence" / "exposure_scope_adjudication_qc.json",
        ),
        "fresh_review": (
            args.review_evidence,
            output / "evidence" / "fresh_ai_review.json",
        ),
        "task_approval": (
            args.approval_evidence,
            output / "evidence" / "task_approval.json",
        ),
    }
    for source, destination in copied_evidence.values():
        shutil.copyfile(source, destination)
        destination.chmod(0o600)

    team_inputs: dict[str, dict[str, str]] = {}
    for team_key, expected_sha in V14_EXPOSURE_SHA256S.items():
        team_dir = output / team_key
        team_dir.mkdir(mode=0o700)
        source = candidate / team_key / "exposure_intake_final_clean_v10.csv"
        input_path = team_dir / source.name
        shutil.copyfile(source, input_path)
        input_path.chmod(0o600)
        if sha256_file(input_path) != expected_sha:
            raise SystemExit(f"candidate exposure checksum mismatch for {team_key}")
        display_team = V13_REVIEWED_V12_TEAMS[team_key][0]
        shared_profile = {
            "team": display_team,
            "season": "2025-26",
            "profile_version": "urc_2025_26_v14_exposure_profile_v1",
            "decision": "compatible",
            "ai_review_status": "completed",
            "ai_reviewed_by": (
                f"{reviewer['model']}/{reviewer['reasoning_effort']} "
                f"{reviewer.get('task', '/root/year2_exposure_release_review')}"
            ),
            "ai_reviewed_at": review["completed_at"],
            "approved_by": "Abdel Babiker",
            "approved_at": approved_at,
            "approval_requested_at": approval["requested_at"],
            "approval_line_sha256": approval_sha256,
            "unresolved_adjudication_ids": [],
            "approved_input_sha256s": [expected_sha],
            "mapping_path": None,
            "mapping_sha256": None,
            "mapping_version": None,
            "authorisation": AUTHORISATION,
        }
        profile = {"schema": V14_EXPOSURE_PROFILE_SCHEMA, **shared_profile}
        profile_path = team_dir / "v14_exposure_profile.json"
        write_json(profile_path, profile)
        profile_sha256 = sha256_file(profile_path)
        manifest = {
            "schema": V14_EXPOSURE_MANIFEST_SCHEMA,
            "team_key": team_key,
            "team": display_team,
            "season": "2025-26",
            "input_file": input_path.name,
            "input_sha256": expected_sha,
            "approved_by": "Abdel Babiker",
            "approved_at": approved_at,
            "approval_line": approval_line,
            "approval_line_sha256": approval_sha256,
            "authorisation": AUTHORISATION,
            "intake_profile": {
                **shared_profile,
                "profile_path": profile_path.name,
                "profile_sha256": profile_sha256,
            },
        }
        manifest_path = team_dir / "v14_exposure_manifest.json"
        write_json(manifest_path, manifest)
        team_inputs[team_key] = {
            "input": f"{team_key}/{input_path.name}",
            "input_sha256": expected_sha,
            "profile": f"{team_key}/{profile_path.name}",
            "profile_sha256": profile_sha256,
            "manifest": f"{team_key}/{manifest_path.name}",
            "manifest_sha256": sha256_file(manifest_path),
        }

    outputs = {
        path.relative_to(output).as_posix(): sha256_file(path)
        for path in sorted(output.rglob("*"))
        if path.is_file()
    }
    file_set_sha256 = hashlib.sha256(
        json.dumps(outputs, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    root = {
        "schema": V14_EXPOSURE_ROOT_SCHEMA,
        "season": "2025-26",
        "approved_by": "Abdel Babiker",
        "approved_at": approved_at,
        "approval_requested_at": approval["requested_at"],
        "approval_ready": True,
        "ingest_ready": True,
        "approval_line": approval_line,
        "approval_line_sha256": approval_sha256,
        "authorisation": AUTHORISATION,
        "candidate_evidence": {
            "candidate_manifest": {
                "path": "evidence/exposure_scope_adjudication_manifest.json",
                "sha256": V14_EXPOSURE_CANDIDATE_MANIFEST_SHA256,
            },
            "candidate_qc": {
                "path": "evidence/exposure_scope_adjudication_qc.json",
                "sha256": V14_EXPOSURE_CANDIDATE_QC_SHA256,
            },
        },
        "fresh_ai_review_evidence": {
            "path": "evidence/fresh_ai_review.json",
            "sha256": sha256_file(output / "evidence" / "fresh_ai_review.json"),
        },
        "task_approval_evidence": {
            "path": "evidence/task_approval.json",
            "sha256": V14_EXPOSURE_TASK_APPROVAL_SHA256,
        },
        "team_inputs": team_inputs,
        "output_sha256s": outputs,
        "root_file_set_sha256": file_set_sha256,
    }
    write_json(output / "v14_exposure_root_manifest.json", root)
    os.chmod(output, 0o700)
    print(json.dumps({
        "status": "built",
        "root_manifest": str(output / "v14_exposure_root_manifest.json"),
        "root_sha256": sha256_file(output / "v14_exposure_root_manifest.json"),
        "team_count": len(team_inputs),
        "output_count": len(outputs),
    }, indent=2))


if __name__ == "__main__":
    main()
