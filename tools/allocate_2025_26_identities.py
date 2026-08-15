"""Prepare a protected, append-only Year 2 player identity allocation.

The command never mutates the authoritative codebook. It writes a candidate
codebook, a protected row-level bridge, and an aggregate-only audit record.
Raw identities are intentionally absent from stdout and the audit record.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import tempfile
import unicodedata
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SEASON = "2025-26"
REQUEST_NAME = "identity_allocation_request.json"
PRIVATE_ROW_REQUEST_NAME = "identity_allocation_request_raw_private.json"
CODEBOOK_FIELDS = ["original_id", "new_id"]
PSEUDONYM = re.compile(r"Ath_(\d+)\Z", re.IGNORECASE)


def normalise_identity(value: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", value).strip().casefold().split())


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _require_protected_output(path: Path) -> None:
    resolved = path.resolve(strict=False)
    if resolved == ROOT or ROOT in resolved.parents:
        raise ValueError("identity allocation outputs must remain outside the repository")


def _atomic_write(path: Path, value: bytes) -> None:
    _require_protected_output(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    descriptor, temporary = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _json_bytes(value: dict[str, Any]) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode(
        "utf-8"
    )


def _read_codebook(path: Path, expected_sha256: str) -> tuple[bytes, list[dict[str, str]]]:
    source = path.read_bytes()
    if sha256_bytes(source) != expected_sha256:
        raise ValueError("codebook checksum drift")
    with io.StringIO(source.decode("cp1252"), newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != CODEBOOK_FIELDS:
            raise ValueError("codebook schema drift")
        rows = list(reader)
    if any(not normalise_identity(row["original_id"]) or not row["new_id"].strip() for row in rows):
        raise ValueError("codebook contains a blank identity or pseudonym")
    pseudonyms = [row["new_id"].strip().casefold() for row in rows]
    if len(pseudonyms) != len(set(pseudonyms)):
        raise ValueError("codebook pseudonyms are not unique")
    return source, rows


def _read_requests(root: Path) -> tuple[list[dict[str, str]], int, int]:
    requests: list[dict[str, str]] = []
    request_files = 0
    source_candidate_rows = 0
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        private_path = directory / PRIVATE_ROW_REQUEST_NAME
        standard_path = directory / REQUEST_NAME
        path = private_path if private_path.exists() else standard_path
        if not path.exists():
            continue
        request_files += 1
        payload = json.loads(path.read_text(encoding="utf-8"))
        team = payload.get("team_key")
        if payload.get("season") != SEASON or not isinstance(team, str) or not team:
            raise ValueError("identity allocation request season or team drift")
        if team != directory.name:
            raise ValueError("identity allocation request team/path mismatch")

        if path.name == PRIVATE_ROW_REQUEST_NAME:
            candidates = payload.get("raw_identity_candidates")
            if payload.get("schema") != "identity_allocation_request_raw_private_v1":
                raise ValueError("private identity allocation request schema drift")
            if payload.get("do_not_allocate_ids") is not True:
                raise ValueError("private identity allocation request worker gate drift")
            if not isinstance(candidates, list) or not all(isinstance(item, dict) for item in candidates):
                raise ValueError("private identity allocation candidates must be objects")
            if payload.get("present_new_allocation_candidate_count") != len(candidates):
                raise ValueError("private identity allocation request count mismatch")
            source_candidate_rows += len(candidates)
            identities = []
            for candidate in candidates:
                raw_identity = candidate.get("raw_identity_value")
                if (
                    not isinstance(raw_identity, str)
                    or candidate.get("request_status") != "new_identity_allocation_candidate"
                ):
                    raise ValueError("private identity allocation candidate contract drift")
                identities.append(raw_identity)
            identities = sorted(set(identities), key=lambda value: (normalise_identity(value), value))
        else:
            identities = payload.get("raw_identities_absent_from_codebook")
            if not isinstance(identities, list) or not all(isinstance(item, str) for item in identities):
                raise ValueError("identity allocation request values must be strings")
            if payload.get("count") != len(identities):
                raise ValueError("identity allocation request count mismatch")
            if len(identities) != len(set(identities)):
                raise ValueError("identity allocation request contains duplicate values")
            source_candidate_rows += len(identities)

        for raw_identity in identities:
            if not normalise_identity(raw_identity):
                raise ValueError("identity allocation request contains a blank value")
            requests.append({"team_key": team, "raw_identity": raw_identity})
    if not request_files:
        raise ValueError("no identity allocation requests found")
    return requests, request_files, source_candidate_rows


def _candidate_bytes(
    source: bytes, appended: list[dict[str, str]]
) -> bytes:
    if not appended:
        return source
    newline = "\r\n" if b"\r\n" in source[:4096] else "\n"
    prefix = source if source.endswith((b"\n", b"\r")) else source + newline.encode("ascii")
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(
        buffer,
        fieldnames=CODEBOOK_FIELDS,
        lineterminator=newline,
        extrasaction="raise",
    )
    writer.writerows(appended)
    try:
        suffix = buffer.getvalue().encode("cp1252")
    except UnicodeEncodeError as error:
        raise ValueError("new identity cannot be represented in the codebook encoding") from error
    return prefix + suffix


def prepare_identity_allocation(
    *,
    codebook: Path,
    requests_root: Path,
    expected_codebook_sha256: str,
    candidate_codebook: Path,
    bridge_path: Path,
    audit_path: Path,
) -> dict[str, int | str]:
    for output in (candidate_codebook, bridge_path, audit_path):
        _require_protected_output(output)
    source, codebook_rows = _read_codebook(codebook, expected_codebook_sha256)
    requests, request_files, source_candidate_rows = _read_requests(requests_root)

    existing: dict[str, list[dict[str, str]]] = defaultdict(list)
    numeric_ids: list[int] = []
    for row in codebook_rows:
        existing[normalise_identity(row["original_id"])].append(row)
        match = PSEUDONYM.fullmatch(row["new_id"].strip())
        if not match:
            raise ValueError("codebook contains a nonconforming pseudonym")
        numeric_ids.append(int(match.group(1)))

    grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
    for request in requests:
        grouped[normalise_identity(request["raw_identity"])].append(request)

    next_id = max(numeric_ids, default=0) + 1
    appended: list[dict[str, str]] = []
    resolved: list[dict[str, str]] = []
    unresolved: list[dict[str, str]] = []
    existing_matches = 0

    for identity_key in sorted(grouped):
        entries = sorted(
            grouped[identity_key], key=lambda item: (item["team_key"], item["raw_identity"])
        )
        existing_rows = existing.get(identity_key, [])
        existing_pseudonyms = {row["new_id"].strip() for row in existing_rows}
        if existing_rows:
            if len(existing_pseudonyms) == 1:
                pseudonym = next(iter(existing_pseudonyms))
                for entry in entries:
                    resolved.append({**entry, "new_id": pseudonym, "resolution": "existing_normalised_match"})
                existing_matches += len(entries)
            else:
                for entry in entries:
                    unresolved.append({**entry, "reason": "ambiguous_existing_identity"})
            continue

        if len({entry["team_key"] for entry in entries}) > 1:
            for entry in entries:
                unresolved.append({**entry, "reason": "cross_team_identity_requires_review"})
            continue

        if any("\n" in entry["raw_identity"] or "\r" in entry["raw_identity"] for entry in entries):
            for entry in entries:
                unresolved.append({**entry, "reason": "unsafe_identity_text"})
            continue

        canonical = min((entry["raw_identity"].strip() for entry in entries), key=lambda value: (value.casefold(), value))
        try:
            canonical.encode("cp1252")
        except UnicodeEncodeError:
            for entry in entries:
                unresolved.append({**entry, "reason": "unsupported_codebook_encoding"})
            continue
        pseudonym = f"Ath_{next_id}"
        next_id += 1
        appended.append({"original_id": canonical, "new_id": pseudonym})
        for entry in entries:
            resolved.append({**entry, "new_id": pseudonym, "resolution": "new_append_only_allocation"})

    candidate = _candidate_bytes(source, appended)
    candidate_sha256 = sha256_bytes(candidate)
    bridge = {
        "schema_version": "urc_2025_26_identity_bridge_v1",
        "season": SEASON,
        "source_codebook_sha256": expected_codebook_sha256,
        "candidate_codebook_sha256": candidate_sha256,
        "resolved": resolved,
        "unresolved": unresolved,
    }
    audit = {
        "schema_version": "urc_2025_26_identity_allocation_audit_v1",
        "season": SEASON,
        "source_codebook_sha256": expected_codebook_sha256,
        "candidate_codebook_sha256": candidate_sha256,
        "source_codebook_rows": len(codebook_rows),
        "request_files": request_files,
        "source_identity_candidate_rows": source_candidate_rows,
        "requested_identity_rows": len(requests),
        "normalised_request_groups": len(grouped),
        "existing_matches": existing_matches,
        "appended_identities": len(appended),
        "resolved_identity_rows": len(resolved),
        "unresolved_identity_rows": len(unresolved),
        "candidate_codebook_rows": len(codebook_rows) + len(appended),
        "allocation_start": max(numeric_ids, default=0) + 1,
        "allocation_end": next_id - 1 if appended else None,
        "prefix_bytes_preserved": candidate.startswith(source),
    }

    _atomic_write(candidate_codebook, candidate)
    _atomic_write(bridge_path, _json_bytes(bridge))
    _atomic_write(audit_path, _json_bytes(audit))
    return {
        "source_codebook_sha256": expected_codebook_sha256,
        "candidate_codebook_sha256": candidate_sha256,
        "existing_matches": existing_matches,
        "appended_identities": len(appended),
        "resolved_identities": len(resolved),
        "unresolved_identities": len(unresolved),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--codebook", type=Path, required=True)
    parser.add_argument("--requests-root", type=Path, required=True)
    parser.add_argument("--expected-codebook-sha256", required=True)
    parser.add_argument("--candidate-codebook", type=Path, required=True)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    args = parser.parse_args()
    result = prepare_identity_allocation(
        codebook=args.codebook,
        requests_root=args.requests_root,
        expected_codebook_sha256=args.expected_codebook_sha256,
        candidate_codebook=args.candidate_codebook,
        bridge_path=args.bridge,
        audit_path=args.audit,
    )
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
