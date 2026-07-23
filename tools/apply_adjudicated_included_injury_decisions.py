#!/usr/bin/env python3
"""Apply only the accepted analysis-release decisions to the included CSV."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import shutil
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RULE_VERSION = "included_injury_adjudicated_release_decisions_2026-07-23_v1"
SELECTION_RULE = (
    "Exclusion Reason is blank after trimming whitespace, followed by removal of "
    "adjudicated source rows 1521, 1977, 2171, and 2392"
)
EXPECTED_ROWS_BEFORE = 2425
EXPECTED_ROWS_AFTER = 2421
EXPECTED_COLUMNS = 28
REMOVED_SOURCE_ROWS = {1521, 1977, 2171, 2392}
RETAINED_UNCHANGED = {358: ("Days Injured", "400"), 2740: ("Days Injured", "321")}
FIELD_CHANGES = {
    2170: {
        "Days Injured": ("0", "2"),
        "TimeLoss vs Medical Attention": ("Medical Attention", "Time Loss"),
    },
    2391: {
        "Orchard Code": ("KDPX", "KDPX; KJMA"),
        "Illness Code": ("NC93.1", "NC93.1; NC93.50"),
        "Description": (
            "Patellar dislocation",
            "Patellar dislocation; Grade 1 MCL tear knee",
        ),
    },
}
EXPECTED_TEAM_COUNT_DELTAS = {"Lions": 1, "Scarlets": 1, "Sharks": 2}
EXPECTED_TEAM_COUNTS_BEFORE = {
    "Lions": {"included_rows": 64, "excluded_rows": 26},
    "Scarlets": {"included_rows": 152, "excluded_rows": 48},
    "Sharks": {"included_rows": 398, "excluded_rows": 82},
}
AUDIT_HEADERS = [
    "csv_row_before",
    "source_workbook_row",
    "team",
    "player_id",
    "field",
    "old_value",
    "new_value",
    "action",
    "reason",
    "rule_version",
    "evidence_origin",
    "retained_source_workbook_row",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def display_path(path: Path, repo_root: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo_root.resolve()))
    except ValueError:
        return str(path.resolve())


def source_row_mapping_sha256(source_rows: list[int]) -> str:
    return hashlib.sha256(("\n".join(map(str, source_rows)) + "\n").encode()).hexdigest()


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"CSV has no header: {path}")
        return list(reader.fieldnames), [dict(row) for row in reader]


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False,
        prefix=f".{path.name}.", suffix=".tmp"
    ) as handle:
        temporary_path = Path(handle.name)
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary_path, path)


def write_audit_atomic(path: Path, rows: list[dict[str, Any]]) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", newline="", dir=path.parent, delete=False,
        prefix=f".{path.name}.", suffix=".tmp"
    ) as handle:
        temporary_path = Path(handle.name)
        writer = csv.DictWriter(handle, fieldnames=AUDIT_HEADERS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary_path, path)


def patch_csv_atomic(
    path: Path,
    headers: list[str],
    rows: list[dict[str, str]],
    source_rows: list[int],
    transformed_rows: list[dict[str, str]],
    transformed_source_rows: list[int],
) -> None:
    original_lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if len(original_lines) != len(rows) + 1:
        raise ValueError("CSV has embedded or nonstandard line breaks; narrow patch aborted")
    transformed_by_source = dict(zip(transformed_source_rows, transformed_rows, strict=True))
    output_lines = [original_lines[0]]
    for index, source_row in enumerate(source_rows):
        replacement = transformed_by_source.get(source_row)
        if replacement is None:
            continue
        if rows[index] == replacement:
            output_lines.append(original_lines[index + 1])
            continue
        buffer = io.StringIO(newline="")
        csv.DictWriter(buffer, fieldnames=headers, lineterminator="\n").writerow(replacement)
        output_lines.append(buffer.getvalue())
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", newline="", dir=path.parent, delete=False,
        prefix=f".{path.name}.", suffix=".tmp"
    ) as handle:
        temporary_path = Path(handle.name)
        handle.writelines(output_lines)
    os.replace(temporary_path, path)


def verify_ledger(ledger_path: Path) -> None:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    if ledger.get("status") != "decisions_complete_application_deferred":
        raise ValueError("Decision ledger is not in the accepted deferred-application state")
    answers = {item["decision_number"]: item["answer"] for item in ledger["decisions"]}
    expected = {
        1: "retain", 2: "keep as is with 321 days lost", 3: "keep the time loss record",
        4: "include 2 days time loss", 5: "keep Record A and set Days Injured to 2",
        6: "combine into one injury and semicolon-join differing fields",
    }
    if answers != expected:
        raise ValueError("Decision ledger answers do not match the approved application set")


def transform_dataset(
    rows: list[dict[str, str]], source_rows: list[int]
) -> tuple[list[dict[str, str]], list[int], list[dict[str, Any]], dict[str, Any]]:
    if len(rows) != EXPECTED_ROWS_BEFORE or len(source_rows) != EXPECTED_ROWS_BEFORE:
        raise ValueError("Input row count does not match the current dataset contract")
    if len(set(source_rows)) != len(source_rows):
        raise ValueError("Manifest source-row mapping contains duplicates")
    indexed = {source_row: (index, rows[index]) for index, source_row in enumerate(source_rows)}
    required = REMOVED_SOURCE_ROWS | set(FIELD_CHANGES) | set(RETAINED_UNCHANGED)
    missing = sorted(required - set(indexed))
    if missing:
        raise ValueError(f"Required source rows are absent from the manifest mapping: {missing}")
    for source_row, (field, expected) in RETAINED_UNCHANGED.items():
        if indexed[source_row][1][field] != expected:
            raise ValueError(f"Retain-as-is precondition failed at source row {source_row}")
    for source_row in (2391, 2392):
        if indexed[source_row][1]["Received/Injured In Team"] != "Sharks":
            raise ValueError(
                "Decision 6 must be applied to the post-normalization Sharks rows"
            )

    retained_sources = {1521: 1522, 1977: 1976, 2171: 2170, 2392: 2391}
    audit: list[dict[str, Any]] = []
    transformed: list[dict[str, str]] = []
    mapped: list[int] = []
    removed_by_team: Counter[str] = Counter()
    for index, source_row in enumerate(source_rows):
        original = rows[index]
        row = dict(original)
        csv_row = index + 2
        if source_row in REMOVED_SOURCE_ROWS:
            removed_by_team[row["Team"]] += 1
            audit.append({
                "csv_row_before": csv_row, "source_workbook_row": source_row,
                "team": row["Team"], "player_id": row["PlayerID"], "field": "Inclusion Status",
                "old_value": "Included", "new_value": "Excluded from included CSV",
                "action": "removed_from_inclusion_csv", "reason": "Confirmed duplicate or merged concurrent diagnosis",
                "rule_version": RULE_VERSION,
                "evidence_origin": "Accepted analysis release decision ledger, applied after Sharks normalization",
                "retained_source_workbook_row": retained_sources[source_row],
            })
            continue
        for field, (old_value, new_value) in FIELD_CHANGES.get(source_row, {}).items():
            if row[field] != old_value:
                raise ValueError(f"Unexpected {field!r} value at source row {source_row}: {row[field]!r}")
            row[field] = new_value
            audit.append({
                "csv_row_before": csv_row, "source_workbook_row": source_row,
                "team": row["Team"], "player_id": row["PlayerID"], "field": field,
                "old_value": old_value, "new_value": new_value, "action": "adjudicated_value_update",
                "reason": "Accepted analysis release decision", "rule_version": RULE_VERSION,
                "evidence_origin": "Accepted analysis release decision ledger, applied after Sharks normalization",
                "retained_source_workbook_row": "",
            })
        transformed.append(row)
        mapped.append(source_row)
    if len(transformed) != EXPECTED_ROWS_AFTER or len(audit) != 9:
        raise ValueError("Unexpected transformed row or audit-event count")
    if dict(removed_by_team) != EXPECTED_TEAM_COUNT_DELTAS:
        raise ValueError(f"Affected-team removal counts drifted: {dict(removed_by_team)}")
    qa = {
        "rule_version": RULE_VERSION,
        "input_rows": len(rows), "output_rows": len(transformed), "columns": len(rows[0]),
        "removed_source_workbook_rows": sorted(REMOVED_SOURCE_ROWS),
        "retained_source_workbook_rows": [1522, 1976, 2170, 2391],
        "unchanged_retain_as_is_rows": [358, 2740],
        "field_changes": {str(source): {field: new for field, (_, new) in changes.items()} for source, changes in FIELD_CHANGES.items()},
        "audit_events": len(audit), "removals_by_team": dict(removed_by_team),
        "decision_6_post_normalization_context": {
            "source_workbook_rows": [2391, 2392],
            "received_injured_in_team": "Sharks",
            "note": "The ledger's older Other team analysis-scope note is stale after Sharks normalization and was not relied on.",
        },
    }
    return transformed, mapped, audit, qa


def apply_decisions(*, input_csv: Path, manifest_path: Path, ledger_path: Path, backup_csv: Path,
                    backup_manifest: Path, audit_path: Path, qa_path: Path, script_path: Path,
                    repo_root: Path, generated_at: str) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    input_hash = sha256_file(input_csv)
    if manifest["output"]["csv_sha256"] != input_hash:
        raise ValueError("Input CSV hash does not match the manifest")
    verify_ledger(ledger_path)
    headers, rows = read_csv(input_csv)
    if len(headers) != EXPECTED_COLUMNS:
        raise ValueError(f"Expected {EXPECTED_COLUMNS} columns, found {len(headers)}")
    source_rows = list(manifest["selection"]["included_source_rows"])
    if manifest["selection"]["included_rows"] != EXPECTED_ROWS_BEFORE or manifest["selection"]["excluded_rows"] != 635:
        raise ValueError("Manifest inclusion counts do not match the current dataset contract")
    for team, expected_counts in EXPECTED_TEAM_COUNTS_BEFORE.items():
        actual_counts = manifest["counts_by_team"].get(team, {})
        if any(actual_counts.get(key) != value for key, value in expected_counts.items()):
            raise ValueError(f"Manifest counts for {team} do not match the current dataset contract")
    transformed, mapped, audit, qa = transform_dataset(rows, source_rows)
    if backup_csv.exists() or backup_manifest.exists():
        raise FileExistsError("Backup target already exists, refusing to overwrite it")
    shutil.copy2(input_csv, backup_csv)
    shutil.copy2(manifest_path, backup_manifest)
    patch_csv_atomic(input_csv, headers, rows, source_rows, transformed, mapped)
    write_audit_atomic(audit_path, audit)
    output_hash = sha256_file(input_csv)
    qa.update({"input_csv_sha256": input_hash, "output_csv_sha256": output_hash,
               "source_row_mapping_sha256": source_row_mapping_sha256(mapped)})
    write_json_atomic(qa_path, qa)

    manifest["generated_at"] = generated_at
    manifest["selection"]["rule"] = SELECTION_RULE
    manifest["selection"]["included_rows"] = EXPECTED_ROWS_AFTER
    manifest["selection"]["excluded_rows"] += len(REMOVED_SOURCE_ROWS)
    manifest["selection"]["included_source_rows"] = mapped
    manifest["selection"]["included_source_rows_sha256"] = source_row_mapping_sha256(mapped)
    manifest["output"]["csv_sha256"] = output_hash
    manifest["output"]["data_rows"] = EXPECTED_ROWS_AFTER
    for team, removed in EXPECTED_TEAM_COUNT_DELTAS.items():
        manifest["counts_by_team"][team]["included_rows"] -= removed
        manifest["counts_by_team"][team]["excluded_rows"] += removed
    manifest.setdefault("cleanup_history", []).append({
        "rule_version": RULE_VERSION, "applied_at": generated_at,
        "script": display_path(script_path, repo_root), "script_sha256": sha256_file(script_path),
        "decision_ledger": display_path(ledger_path, repo_root), "decision_ledger_sha256": sha256_file(ledger_path),
        "input_csv_sha256": input_hash, "output_csv_sha256": output_hash,
        "backup_csv": display_path(backup_csv, repo_root), "backup_csv_sha256": sha256_file(backup_csv),
        "backup_manifest": display_path(backup_manifest, repo_root), "backup_manifest_sha256": sha256_file(backup_manifest),
        "audit": display_path(audit_path, repo_root), "audit_sha256": sha256_file(audit_path),
        "qa": display_path(qa_path, repo_root), "qa_sha256": sha256_file(qa_path),
        "removed_source_workbook_rows": sorted(REMOVED_SOURCE_ROWS), "changed_source_workbook_rows": sorted(FIELD_CHANGES),
        "unchanged_retain_as_is_rows": [358, 2740], "source_row_mapping_unchanged_except_removed_rows": True,
        "applied_after": "sharks_single_squad_normalization_2026-07-23_v1",
        "decision_6_post_normalization_context": "Rows 2391/2392 currently have Received/Injured In Team=Sharks; the ledger's older Other team analysis-scope note was not relied on.",
    })
    write_json_atomic(manifest_path, manifest)
    return {"rows": len(transformed), "columns": len(headers), "csv_sha256": output_hash,
            "manifest_sha256": sha256_file(manifest_path), "audit_events": len(audit)}


def parse_args() -> argparse.Namespace:
    output_dir = Path("outputs/urc_final_human_review_2024-25")
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-csv", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.csv")
    parser.add_argument("--manifest", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.manifest.json")
    parser.add_argument("--ledger", type=Path, default=output_dir / "urc_injury_analysis_release_decisions_2026-07-23.json")
    parser.add_argument("--backup-csv", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.pre_adjudicated_release_decisions_2026-07-23.csv")
    parser.add_argument("--backup-manifest", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.pre_adjudicated_release_decisions_2026-07-23.manifest.json")
    parser.add_argument("--audit", type=Path, default=output_dir / "urc_injury_included_dataset_adjudicated_release_decisions_audit_2026-07-23.csv")
    parser.add_argument("--qa", type=Path, default=output_dir / "urc_injury_included_dataset_adjudicated_release_decisions_qa_2026-07-23.json")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    script_path = Path(__file__).resolve()
    result = apply_decisions(input_csv=args.input_csv, manifest_path=args.manifest, ledger_path=args.ledger,
                             backup_csv=args.backup_csv, backup_manifest=args.backup_manifest,
                             audit_path=args.audit, qa_path=args.qa, script_path=script_path,
                             repo_root=script_path.parents[1],
                             generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
