#!/usr/bin/env python3
"""Remove the approved non-rugby and gym-based injury rows from the included CSV."""

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


RULE_VERSION = "included_injury_nonrugby_gym_removal_2026-07-23_v1"
EXPECTED_INPUT_ROWS = 2421
EXPECTED_COLUMNS = 28
TARGET_OCCASIONS = {"Non-Rugby", "Gym-Based"}
EXPECTED_REMOVALS_BY_OCCASION = {"Gym-Based": 27, "Non-Rugby": 93}
EXPECTED_REMOVALS_BY_TEAM = {
    "Connacht": 12,
    "Dragons": 1,
    "Edinburgh": 4,
    "Glasgow Warriors": 2,
    "Leinster": 36,
    "Munster": 23,
    "Ospreys": 3,
    "Scarlets": 7,
    "Ulster": 27,
    "Zebre": 5,
}
SELECTION_RULE = (
    "Exclusion Reason is blank after trimming whitespace, followed by removal of "
    "adjudicated source rows 1521, 1977, 2171, and 2392, followed by removal of "
    "rows where Problem type is exactly 'Injury' and Occasion category is exactly "
    "'Non-Rugby' or 'Gym-Based'"
)
AUDIT_HEADERS = [
    "csv_row_before", "source_workbook_row", "team", "player_id", "field",
    "old_value", "new_value", "action", "reason", "rule_version",
    "evidence_origin",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_row_mapping_sha256(source_rows: list[int]) -> str:
    return hashlib.sha256(("\n".join(map(str, source_rows)) + "\n").encode()).hexdigest()


def display_path(path: Path, repo_root: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo_root.resolve()))
    except ValueError:
        return str(path.resolve())


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"CSV has no header: {path}")
        return list(reader.fieldnames), [dict(row) for row in reader]


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     delete=False, prefix=f".{path.name}.", suffix=".tmp") as handle:
        temporary_path = Path(handle.name)
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary_path, path)


def write_audit_atomic(path: Path, rows: list[dict[str, str | int]]) -> None:
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="", dir=path.parent,
                                     delete=False, prefix=f".{path.name}.", suffix=".tmp") as handle:
        temporary_path = Path(handle.name)
        writer = csv.DictWriter(handle, fieldnames=AUDIT_HEADERS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary_path, path)


def patch_csv_atomic(path: Path, headers: list[str], rows: list[dict[str, str]],
                     source_rows: list[int], retained_sources: set[int]) -> None:
    original_lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if len(original_lines) != len(rows) + 1:
        raise ValueError("CSV has embedded or nonstandard line breaks; narrow patch aborted")
    output_lines = [original_lines[0]]
    for index, source_row in enumerate(source_rows):
        if source_row in retained_sources:
            output_lines.append(original_lines[index + 1])
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="", dir=path.parent,
                                     delete=False, prefix=f".{path.name}.", suffix=".tmp") as handle:
        temporary_path = Path(handle.name)
        handle.writelines(output_lines)
    os.replace(temporary_path, path)


def transform_dataset(rows: list[dict[str, str]], source_rows: list[int]) -> tuple[list[int], list[dict[str, str | int]], dict[str, Any]]:
    if len(rows) != EXPECTED_INPUT_ROWS or len(source_rows) != EXPECTED_INPUT_ROWS:
        raise ValueError("Input row count does not match the current dataset contract")
    if len(source_rows) != len(set(source_rows)):
        raise ValueError("Manifest source-row mapping contains duplicate source rows")
    retained_sources: list[int] = []
    audit: list[dict[str, str | int]] = []
    by_occasion: Counter[str] = Counter()
    by_team: Counter[str] = Counter()
    illness_targets = 0
    other_targets = 0
    unknown_time_loss_removed = 0
    for index, row in enumerate(rows):
        source_row = source_rows[index]
        occasion = row["Occasion category"]
        is_target = row["Problem type"] == "Injury" and occasion in TARGET_OCCASIONS
        if not is_target:
            retained_sources.append(source_row)
            if row["Problem type"] == "Illness" and occasion in TARGET_OCCASIONS:
                illness_targets += 1
            if row["Problem type"] == "Other" and occasion in TARGET_OCCASIONS:
                other_targets += 1
            continue
        by_occasion[occasion] += 1
        by_team[row["Team"]] += 1
        unknown_time_loss_removed += row["TimeLoss vs Medical Attention"] == "Unknown"
        audit.append({
            "csv_row_before": index + 2,
            "source_workbook_row": source_row,
            "team": row["Team"], "player_id": row["PlayerID"],
            "field": "Inclusion Status", "old_value": "Included",
            "new_value": "Excluded from included CSV",
            "action": "removed_from_inclusion_csv",
            "reason": "Approved removal of non-rugby or gym-based injury from the included dataset",
            "rule_version": RULE_VERSION,
            "evidence_origin": "Problem type='Injury' and Occasion category exact-match rule",
        })
    if dict(sorted(by_occasion.items())) != EXPECTED_REMOVALS_BY_OCCASION:
        raise ValueError(f"Occasion removal counts drifted: {dict(sorted(by_occasion.items()))}")
    if dict(sorted(by_team.items())) != EXPECTED_REMOVALS_BY_TEAM:
        raise ValueError(f"Team removal counts drifted: {dict(sorted(by_team.items()))}")
    qa = {
        "rule_version": RULE_VERSION,
        "selection_rule": SELECTION_RULE,
        "input_rows": len(rows), "output_rows": len(retained_sources), "columns": len(rows[0]),
        "removed_rows": len(audit), "removals_by_occasion": dict(sorted(by_occasion.items())),
        "removals_by_team": dict(sorted(by_team.items())),
        "audit_events": len(audit),
        "illness_rows_matching_target_occasions_retained": illness_targets,
        "other_rows_matching_target_occasions_retained": other_targets,
        "unknown_time_loss_rows_removed": unknown_time_loss_removed,
        "no_value_reclassification_performed": True,
    }
    return retained_sources, audit, qa


def apply_removal(*, input_csv: Path, manifest_path: Path, backup_csv: Path,
                  backup_manifest: Path, audit_path: Path, qa_path: Path,
                  script_path: Path, repo_root: Path, generated_at: str) -> dict[str, Any]:
    outputs = (backup_csv, backup_manifest, audit_path, qa_path)
    existing = [str(path) for path in outputs if path.exists()]
    if existing:
        raise FileExistsError("Refusing to overwrite existing artifacts: " + ", ".join(existing))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    input_hash = sha256_file(input_csv)
    if manifest["output"]["csv_sha256"] != input_hash:
        raise ValueError("Input CSV hash does not match the manifest")
    headers, rows = read_csv(input_csv)
    source_rows = list(manifest["selection"]["included_source_rows"])
    if len(headers) != EXPECTED_COLUMNS:
        raise ValueError(f"Expected {EXPECTED_COLUMNS} columns, found {len(headers)}")
    if manifest["selection"]["included_rows"] != EXPECTED_INPUT_ROWS:
        raise ValueError("Manifest inclusion count does not match current dataset contract")
    retained_sources, audit, qa = transform_dataset(rows, source_rows)
    shutil.copy2(input_csv, backup_csv)
    shutil.copy2(manifest_path, backup_manifest)
    if sha256_file(backup_csv) != input_hash:
        raise ValueError("CSV backup hash does not match input")
    patch_csv_atomic(input_csv, headers, rows, source_rows, set(retained_sources))
    write_audit_atomic(audit_path, audit)
    output_hash = sha256_file(input_csv)
    qa.update({"generated_at": generated_at, "input_csv_sha256": input_hash,
               "output_csv_sha256": output_hash,
               "source_row_mapping_sha256": source_row_mapping_sha256(retained_sources)})
    write_json_atomic(qa_path, qa)
    removals_by_team = qa["removals_by_team"]
    manifest["generated_at"] = generated_at
    manifest["selection"].update({"rule": SELECTION_RULE, "included_rows": len(retained_sources),
        "excluded_rows": manifest["selection"]["excluded_rows"] + len(audit),
        "included_source_rows": retained_sources,
        "included_source_rows_sha256": source_row_mapping_sha256(retained_sources)})
    manifest["output"].update({"csv_sha256": output_hash, "data_rows": len(retained_sources), "columns": len(headers)})
    for team, removed in removals_by_team.items():
        manifest["counts_by_team"][team]["included_rows"] -= removed
        manifest["counts_by_team"][team]["excluded_rows"] += removed
    manifest.setdefault("cleanup_history", []).append({
        "rule_version": RULE_VERSION, "applied_at": generated_at,
        "script": display_path(script_path, repo_root), "script_sha256": sha256_file(script_path),
        "input_csv_sha256": input_hash, "output_csv_sha256": output_hash,
        "backup_csv": display_path(backup_csv, repo_root), "backup_csv_sha256": sha256_file(backup_csv),
        "backup_manifest": display_path(backup_manifest, repo_root), "backup_manifest_sha256": sha256_file(backup_manifest),
        "audit": display_path(audit_path, repo_root), "audit_sha256": sha256_file(audit_path),
        "qa": display_path(qa_path, repo_root), "qa_sha256": sha256_file(qa_path),
        "removed_source_workbook_rows": [entry["source_workbook_row"] for entry in audit],
        "removed_rows": len(audit), "removals_by_occasion": qa["removals_by_occasion"],
        "removals_by_team": removals_by_team,
        "master_workbook_application_status": "deferred_until_final_review",
        "source_row_mapping_unchanged_except_removed_rows": True,
        "no_value_reclassification_performed": True,
    })
    write_json_atomic(manifest_path, manifest)
    return {"rows": len(retained_sources), "csv_sha256": output_hash,
            "manifest_sha256": sha256_file(manifest_path), "removed_rows": len(audit),
            "removals_by_occasion": qa["removals_by_occasion"], "removals_by_team": removals_by_team}


def parse_args() -> argparse.Namespace:
    output_dir = Path("outputs/urc_final_human_review_2024-25")
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-csv", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.csv")
    parser.add_argument("--manifest", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.manifest.json")
    parser.add_argument("--backup-csv", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.pre_nonrugby_gym_removal_2026-07-23.csv")
    parser.add_argument("--backup-manifest", type=Path, default=output_dir / "urc_injury_included_dataset_2024-25.pre_nonrugby_gym_removal_2026-07-23.manifest.json")
    parser.add_argument("--audit", type=Path, default=output_dir / "urc_injury_included_dataset_nonrugby_gym_removal_audit_2026-07-23.csv")
    parser.add_argument("--qa", type=Path, default=output_dir / "urc_injury_included_dataset_nonrugby_gym_removal_qa_2026-07-23.json")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    script_path = Path(__file__).resolve()
    result = apply_removal(input_csv=args.input_csv, manifest_path=args.manifest,
        backup_csv=args.backup_csv, backup_manifest=args.backup_manifest,
        audit_path=args.audit, qa_path=args.qa, script_path=script_path,
        repo_root=script_path.parents[1],
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
