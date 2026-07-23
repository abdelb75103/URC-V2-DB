#!/usr/bin/env python3
"""Apply the accepted source corrections to the included injury CSV."""

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


RULE_VERSION = "included_injury_source_corrections_2026-07-23_v2"
EXPECTED_ROWS_BEFORE = 2426
EXPECTED_ROWS_AFTER = 2425
EXPECTED_COLUMNS = 28
DRAGONS_SOURCE_ROW = 535
DRAGONS_OLD_DATE = "24/0/2/25"
DRAGONS_NEW_DATE = "24/02/2025"
LIONS_RETAINED_SOURCE_ROW = 1529
LIONS_REMOVED_SOURCE_ROW = 1530
EDINBURGH_UNCHANGED_SOURCE_ROW = 756
GLASGOW_UNCHANGED_SOURCE_ROW = 1168
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
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(repo_root.resolve()))
    except ValueError:
        return str(resolved)


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"CSV has no headers: {path}")
        return list(reader.fieldnames), [dict(row) for row in reader]


def patch_csv_atomic(
    path: Path,
    headers: list[str],
    original_rows: list[dict[str, str]],
    original_source_rows: list[int],
    transformed_rows: list[dict[str, str]],
    transformed_source_rows: list[int],
) -> None:
    physical_lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if len(physical_lines) != len(original_rows) + 1:
        raise ValueError(
            "CSV contains embedded or nonstandard line breaks; narrow line patch aborted"
        )
    transformed_by_source_row = dict(
        zip(transformed_source_rows, transformed_rows, strict=True)
    )
    output_lines = [physical_lines[0]]
    for index, source_row in enumerate(original_source_rows):
        if source_row not in transformed_by_source_row:
            continue
        old_row = original_rows[index]
        new_row = transformed_by_source_row[source_row]
        if old_row == new_row:
            output_lines.append(physical_lines[index + 1])
            continue
        buffer = io.StringIO(newline="")
        writer = csv.DictWriter(buffer, fieldnames=headers, lineterminator="\n")
        writer.writerow(new_row)
        output_lines.append(buffer.getvalue())

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        temporary_path = Path(handle.name)
        handle.writelines(output_lines)
    os.replace(temporary_path, path)


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        temporary_path = Path(handle.name)
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary_path, path)


def write_audit_atomic(path: Path, rows: list[dict[str, Any]]) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        temporary_path = Path(handle.name)
        writer = csv.DictWriter(handle, fieldnames=AUDIT_HEADERS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary_path, path)


def source_row_mapping_sha256(source_rows: list[int]) -> str:
    payload = "\n".join(str(value) for value in source_rows) + "\n"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def read_recurrence_restore_rows(previous_audit_path: Path) -> set[int]:
    with previous_audit_path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    restore_rows = {
        int(row["source_workbook_row"])
        for row in rows
        if row["field"] == "Recurrence"
        and row["old_value"] == "New case"
        and row["new_value"] == "New injury"
    }
    if len(restore_rows) != 430:
        raise ValueError(
            f"Expected 430 audited New case changes, found {len(restore_rows)}"
        )
    return restore_rows


def transform_dataset(
    rows: list[dict[str, str]],
    source_rows: list[int],
    recurrence_restore_rows: set[int],
) -> tuple[list[dict[str, str]], list[int], list[dict[str, Any]], dict[str, Any]]:
    if len(rows) != len(source_rows):
        raise ValueError("CSV rows and manifest source-row mapping differ in length")
    if len(rows) != EXPECTED_ROWS_BEFORE:
        raise ValueError(f"Expected {EXPECTED_ROWS_BEFORE} input rows, found {len(rows)}")
    if len(set(source_rows)) != len(source_rows):
        raise ValueError("Manifest source-row mapping contains duplicates")

    indexed = {
        source_row: (index, dict(rows[index]))
        for index, source_row in enumerate(source_rows)
    }
    required = {
        DRAGONS_SOURCE_ROW,
        LIONS_RETAINED_SOURCE_ROW,
        LIONS_REMOVED_SOURCE_ROW,
        EDINBURGH_UNCHANGED_SOURCE_ROW,
        GLASGOW_UNCHANGED_SOURCE_ROW,
    }
    missing = sorted(required - indexed.keys())
    if missing:
        raise ValueError(f"Required source rows missing from mapping: {missing}")

    retained_duplicate = indexed[LIONS_RETAINED_SOURCE_ROW][1]
    removed_duplicate = indexed[LIONS_REMOVED_SOURCE_ROW][1]
    if retained_duplicate != removed_duplicate:
        raise ValueError("Lions source rows 1529 and 1530 are not exact CSV duplicates")
    if removed_duplicate["Exclusion Reason"].strip():
        raise ValueError("Lions source row 1530 is already excluded in the CSV")

    audit_rows: list[dict[str, Any]] = []
    transformed_rows: list[dict[str, str]] = []
    transformed_source_rows: list[int] = []
    recurrence_by_team: Counter[str] = Counter()

    for index, source_row in enumerate(source_rows):
        csv_row = index + 2
        row = dict(rows[index])

        if source_row in recurrence_restore_rows:
            if row["Problem type"] != "Illness" or row["Recurrence"] != "New injury":
                raise ValueError(
                    "Audited recurrence restoration precondition failed for "
                    f"source row {source_row}"
                )
            row["Recurrence"] = "New case"
            recurrence_by_team[row["Team"]] += 1
            audit_rows.append(
                {
                    "csv_row_before": csv_row,
                    "source_workbook_row": source_row,
                    "team": row["Team"],
                    "player_id": row["PlayerID"],
                    "field": "Recurrence",
                    "old_value": "New injury",
                    "new_value": "New case",
                    "action": "restored_source_label",
                    "reason": "New case is the accepted first-episode label for illnesses",
                    "rule_version": RULE_VERSION,
                    "evidence_origin": (
                        "Prior focused-cleanup audit proves the source value was New case"
                    ),
                    "retained_source_workbook_row": "",
                }
            )

        if source_row == DRAGONS_SOURCE_ROW:
            if row["Date Injured"] != DRAGONS_OLD_DATE:
                raise ValueError(
                    f"Unexpected Dragons date: {row['Date Injured']!r}"
                )
            row["Date Injured"] = DRAGONS_NEW_DATE
            audit_rows.append(
                {
                    "csv_row_before": csv_row,
                    "source_workbook_row": source_row,
                    "team": row["Team"],
                    "player_id": row["PlayerID"],
                    "field": "Date Injured",
                    "old_value": DRAGONS_OLD_DATE,
                    "new_value": DRAGONS_NEW_DATE,
                    "action": "source_date_correction",
                    "reason": "Corrected an unambiguous malformed date token",
                    "rule_version": RULE_VERSION,
                    "evidence_origin": (
                        "Dragons Standardized Data row 154 and retained Excel serial "
                        "45712 both resolve to 24/02/2025"
                    ),
                    "retained_source_workbook_row": "",
                }
            )

        if source_row == LIONS_REMOVED_SOURCE_ROW:
            audit_rows.append(
                {
                    "csv_row_before": csv_row,
                    "source_workbook_row": source_row,
                    "team": row["Team"],
                    "player_id": row["PlayerID"],
                    "field": "Exclusion Reason",
                    "old_value": "",
                    "new_value": "Confirmed duplicate",
                    "action": "removed_from_inclusion_csv",
                    "reason": "Exact source duplicate, retaining the first physical occurrence",
                    "rule_version": RULE_VERSION,
                    "evidence_origin": (
                        "Lions Standardized Data rows 26 and 27 are identical across "
                        "all 48 source fields; successor review workbook AB1530 records "
                        "the exclusion before removal"
                    ),
                    "retained_source_workbook_row": LIONS_RETAINED_SOURCE_ROW,
                }
            )
            continue

        transformed_rows.append(row)
        transformed_source_rows.append(source_row)

    if len(transformed_rows) != EXPECTED_ROWS_AFTER:
        raise ValueError(
            f"Expected {EXPECTED_ROWS_AFTER} output rows, found {len(transformed_rows)}"
        )
    if len(audit_rows) != 432:
        raise ValueError(f"Expected 432 audit events, found {len(audit_rows)}")

    for unchanged_source_row, team in (
        (EDINBURGH_UNCHANGED_SOURCE_ROW, "Edinburgh"),
        (GLASGOW_UNCHANGED_SOURCE_ROW, "Glasgow Warriors"),
    ):
        unchanged = indexed[unchanged_source_row][1]
        if unchanged["Team"] != team:
            raise ValueError(f"Unexpected team at source row {unchanged_source_row}")
        if unchanged["Confirmed Return Date"].strip() or unchanged["Days Injured"].strip():
            raise ValueError(
                f"Expected retained source blanks at source row {unchanged_source_row}"
            )

    qa = {
        "rule_version": RULE_VERSION,
        "input_rows": len(rows),
        "output_rows": len(transformed_rows),
        "columns": len(rows[0]) if rows else 0,
        "recurrence_new_case_restored": len(recurrence_restore_rows),
        "recurrence_restores_by_team": dict(sorted(recurrence_by_team.items())),
        "dragons_date_corrections": 1,
        "lions_exact_duplicates_removed": 1,
        "removed_source_workbook_rows": [LIONS_REMOVED_SOURCE_ROW],
        "retained_duplicate_source_workbook_row": LIONS_RETAINED_SOURCE_ROW,
        "source_blank_return_dates_preserved": [
            {
                "source_workbook_row": EDINBURGH_UNCHANGED_SOURCE_ROW,
                "team": "Edinburgh",
                "reason": "Raw and standardised retained sources are blank",
            },
            {
                "source_workbook_row": GLASGOW_UNCHANGED_SOURCE_ROW,
                "team": "Glasgow Warriors",
                "reason": "Raw and standardised retained sources are blank",
            },
        ],
        "audit_events": len(audit_rows),
    }
    return transformed_rows, transformed_source_rows, audit_rows, qa


def apply_corrections(
    *,
    input_csv: Path,
    manifest_path: Path,
    previous_audit_path: Path,
    successor_workbook: Path,
    backup_csv: Path,
    backup_manifest: Path,
    audit_path: Path,
    qa_path: Path,
    workbook_audit_path: Path,
    script_path: Path,
    repo_root: Path,
    generated_at: str,
) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    input_hash = sha256_file(input_csv)
    if manifest["output"]["csv_sha256"] != input_hash:
        raise ValueError("Input CSV hash does not match the current manifest")
    headers, rows = read_csv(input_csv)
    if len(headers) != EXPECTED_COLUMNS:
        raise ValueError(f"Expected {EXPECTED_COLUMNS} columns, found {len(headers)}")

    source_rows = list(manifest["selection"]["included_source_rows"])
    recurrence_restore_rows = read_recurrence_restore_rows(previous_audit_path)
    transformed, transformed_source_rows, audit_rows, qa = transform_dataset(
        rows, source_rows, recurrence_restore_rows
    )

    if backup_csv.exists() or backup_manifest.exists():
        raise FileExistsError("Correction backup target already exists")
    shutil.copy2(input_csv, backup_csv)
    shutil.copy2(manifest_path, backup_manifest)

    patch_csv_atomic(
        input_csv,
        headers,
        rows,
        source_rows,
        transformed,
        transformed_source_rows,
    )
    write_audit_atomic(audit_path, audit_rows)
    write_json_atomic(qa_path, qa)

    workbook_hash = sha256_file(successor_workbook)
    workbook_audit = {
        "rule_version": RULE_VERSION,
        "workbook": display_path(successor_workbook, repo_root),
        "workbook_sha256": workbook_hash,
        "sheet": "Injury Master",
        "changes": [
            {
                "cell": "F535",
                "field": "Date Injured",
                "old_value": DRAGONS_OLD_DATE,
                "new_value": DRAGONS_NEW_DATE,
                "evidence_origin": "Dragons Standardized Data row 154; Excel serial 45712",
            },
            {
                "cell": "AB1530",
                "field": "Exclusion Reason",
                "old_value": "",
                "new_value": "Confirmed duplicate",
                "evidence_origin": (
                    "Lions Standardized Data rows 26 and 27 exact duplicate"
                ),
            },
            {
                "range": "A1530:AB1530",
                "field": "Excluded-row font colour",
                "old_value": "source formatting",
                "new_value": "red, Excel colour index 3",
                "evidence_origin": "Human review excluded-row convention",
            },
        ],
        "unchanged_source_blanks": [
            "H756/I756 Edinburgh Ath_596",
            "H1168/I1168 Glasgow Ath_491",
        ],
    }
    write_json_atomic(workbook_audit_path, workbook_audit)

    output_hash = sha256_file(input_csv)
    audit_hash = sha256_file(audit_path)
    qa_hash = sha256_file(qa_path)
    workbook_audit_hash = sha256_file(workbook_audit_path)
    manifest["generated_at"] = generated_at
    manifest["source"]["workbook"] = display_path(successor_workbook, repo_root)
    manifest["source"]["workbook_sha256"] = workbook_hash
    manifest["selection"]["included_rows"] = EXPECTED_ROWS_AFTER
    manifest["selection"]["excluded_rows"] = 635
    manifest["selection"]["included_source_rows"] = transformed_source_rows
    manifest["selection"]["included_source_rows_sha256"] = (
        source_row_mapping_sha256(transformed_source_rows)
    )
    manifest["output"]["csv_sha256"] = output_hash
    manifest["output"]["data_rows"] = EXPECTED_ROWS_AFTER
    manifest["counts_by_team"]["Lions"]["included_rows"] = 64
    manifest["counts_by_team"]["Lions"]["excluded_rows"] = 26
    manifest.setdefault("cleanup_history", []).append(
        {
            "rule_version": RULE_VERSION,
            "applied_at": generated_at,
            "script": display_path(script_path, repo_root),
            "script_sha256": sha256_file(script_path),
            "input_csv_sha256": input_hash,
            "output_csv_sha256": output_hash,
            "backup_csv": display_path(backup_csv, repo_root),
            "backup_csv_sha256": sha256_file(backup_csv),
            "backup_manifest": display_path(backup_manifest, repo_root),
            "backup_manifest_sha256": sha256_file(backup_manifest),
            "audit": display_path(audit_path, repo_root),
            "audit_sha256": audit_hash,
            "qa": display_path(qa_path, repo_root),
            "qa_sha256": qa_hash,
            "successor_review_workbook": display_path(successor_workbook, repo_root),
            "successor_review_workbook_sha256": workbook_hash,
            "workbook_audit": display_path(workbook_audit_path, repo_root),
            "workbook_audit_sha256": workbook_audit_hash,
            "restored_new_case_illness_rows": 430,
            "corrected_dragons_source_rows": [DRAGONS_SOURCE_ROW],
            "removed_duplicate_source_rows": [LIONS_REMOVED_SOURCE_ROW],
            "retained_duplicate_source_rows": [LIONS_RETAINED_SOURCE_ROW],
            "source_blank_return_dates_preserved": [
                EDINBURGH_UNCHANGED_SOURCE_ROW,
                GLASGOW_UNCHANGED_SOURCE_ROW,
            ],
        }
    )
    write_json_atomic(manifest_path, manifest)

    return {
        "rows": len(transformed),
        "columns": len(headers),
        "csv_sha256": output_hash,
        "manifest_sha256": sha256_file(manifest_path),
        "workbook_sha256": workbook_hash,
        "audit_events": len(audit_rows),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    output_dir = Path("outputs/urc_final_human_review_2024-25")
    parser.add_argument(
        "--input-csv",
        type=Path,
        default=output_dir / "urc_injury_included_dataset_2024-25.csv",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=output_dir / "urc_injury_included_dataset_2024-25.manifest.json",
    )
    parser.add_argument(
        "--previous-audit",
        type=Path,
        default=output_dir
        / "urc_injury_included_dataset_focused_cleanup_audit_2026-07-23.csv",
    )
    parser.add_argument(
        "--successor-workbook",
        type=Path,
        default=output_dir
        / (
            "urc_injury_reviewed_master_with_exclusion_decisions_2024-25_"
            "successor_2026-07-23_v2.xlsx"
        ),
    )
    parser.add_argument(
        "--backup-csv",
        type=Path,
        default=output_dir
        / "urc_injury_included_dataset_2024-25.pre_source_corrections_v2_2026-07-23.csv",
    )
    parser.add_argument(
        "--backup-manifest",
        type=Path,
        default=output_dir
        / (
            "urc_injury_included_dataset_2024-25."
            "pre_source_corrections_v2_2026-07-23.manifest.json"
        ),
    )
    parser.add_argument(
        "--audit",
        type=Path,
        default=output_dir
        / "urc_injury_included_dataset_source_corrections_v2_audit_2026-07-23.csv",
    )
    parser.add_argument(
        "--qa",
        type=Path,
        default=output_dir
        / "urc_injury_included_dataset_source_corrections_v2_qa_2026-07-23.json",
    )
    parser.add_argument(
        "--workbook-audit",
        type=Path,
        default=output_dir
        / "urc_injury_reviewed_master_successor_v2_audit_2026-07-23.json",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    script_path = Path(__file__).resolve()
    repo_root = script_path.parents[1]
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    result = apply_corrections(
        input_csv=args.input_csv,
        manifest_path=args.manifest,
        previous_audit_path=args.previous_audit,
        successor_workbook=args.successor_workbook,
        backup_csv=args.backup_csv,
        backup_manifest=args.backup_manifest,
        audit_path=args.audit,
        qa_path=args.qa,
        workbook_audit_path=args.workbook_audit,
        script_path=script_path,
        repo_root=repo_root,
        generated_at=generated_at,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
