#!/usr/bin/env python3
"""Apply Abdel's reviewed Bulls/Cardiff Unknown injury adjudications."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RULE_VERSION = "bulls_cardiff_unknown_adjudication_2026-07-24_v1"
EXPECTED_INPUT_HASH = "20c95c0fc25f30045debb5e18c7c8f7f315ce1805c1c5f5283435b9bb655f4e1"
EXPECTED_MAPPING_HASH = "9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f"
TARGET_CSV_ROWS = [74, 76, 88, 92, 98, 100, 104, 115, 116, 135, 137]
EXCLUDED_CSV_ROWS = [35, 99, 111, 134, 140, 142]
MANUAL_EDITS = {
    138: {"TimeLoss vs Medical Attention": ("Unknown", "Time Loss")},
    1264: {
        "Confirmed Return Date": ("", "21/10/2024"),
        "Days Injured": ("", "8"),
    },
}
AUDIT_HEADERS = [
    "csv_row", "source_workbook_row", "team", "player_id", "field",
    "old_value", "new_value", "action", "reason", "rule_version",
    "evidence_origin", "value_origin",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def mapping_sha256(source_rows: list[int]) -> str:
    return hashlib.sha256(
        ("\n".join(map(str, source_rows)) + "\n").encode()
    ).hexdigest()


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"CSV has no header: {path}")
        return list(reader.fieldnames), [dict(row) for row in reader]


def write_json_atomic(path: Path, payload: Any) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False,
        prefix=f".{path.name}.", suffix=".tmp",
    ) as handle:
        temporary = Path(handle.name)
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary, path)


def write_csv_atomic(
    path: Path, headers: list[str], rows: list[dict[str, Any]]
) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", newline="", dir=path.parent, delete=False,
        prefix=f".{path.name}.", suffix=".tmp",
    ) as handle:
        temporary = Path(handle.name)
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def patch_csv_atomic(
    path: Path,
    headers: list[str],
    original: list[dict[str, str]],
    transformed: list[dict[str, str]],
) -> None:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if len(lines) != len(original) + 1:
        raise ValueError("CSV contains nonstandard line breaks")
    output = [lines[0]]
    for before, after, line in zip(original, transformed, lines[1:], strict=True):
        if before == after:
            output.append(line)
        else:
            buffer = io.StringIO(newline="")
            csv.DictWriter(
                buffer, fieldnames=headers, lineterminator="\n"
            ).writerow(after)
            output.append(buffer.getvalue())
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", newline="", dir=path.parent, delete=False,
        prefix=f".{path.name}.", suffix=".tmp",
    ) as handle:
        temporary = Path(handle.name)
        handle.writelines(output)
    os.replace(temporary, path)


def transform_dataset(
    rows: list[dict[str, str]], source_rows: list[int]
) -> tuple[list[dict[str, str]], list[dict[str, Any]], dict[str, Any]]:
    transformed = [dict(row) for row in rows]
    audit: list[dict[str, Any]] = []

    for csv_row in TARGET_CSV_ROWS:
        index = csv_row - 2
        row = transformed[index]
        if row["Team"] not in {"Bulls", "Cardiff"}:
            raise ValueError(f"Unexpected team at CSV row {csv_row}")
        if row["Problem type"] != "Injury":
            raise ValueError(f"Expected Injury at CSV row {csv_row}")
        if row["TimeLoss vs Medical Attention"] != "Unknown":
            raise ValueError(f"Expected Unknown at CSV row {csv_row}")
        row["TimeLoss vs Medical Attention"] = "Time Loss"
        audit.append({
            "csv_row": csv_row,
            "source_workbook_row": source_rows[index],
            "team": row["Team"],
            "player_id": row["PlayerID"],
            "field": "TimeLoss vs Medical Attention",
            "old_value": "Unknown",
            "new_value": "Time Loss",
            "action": "human_adjudicated_classification",
            "reason": "Abdel reviewed the recorded diagnosis and adjudicated Time Loss",
            "rule_version": RULE_VERSION,
            "evidence_origin": (
                f"CSV diagnosis={row['Diagnosis']}; description={row['Description']}"
            ),
            "value_origin": "adjudicated",
        })

    for csv_row in EXCLUDED_CSV_ROWS:
        row = transformed[csv_row - 2]
        if row["TimeLoss vs Medical Attention"] != "Unknown":
            raise ValueError(f"Excluded CSV row {csv_row} no longer remains Unknown")

    unknown_after = sum(
        row["Problem type"] == "Injury"
        and row["TimeLoss vs Medical Attention"] == "Unknown"
        for row in transformed
    )
    if unknown_after != 33:
        raise ValueError(f"Expected 33 Unknown injuries after adjudication, found {unknown_after}")
    qa = {
        "rule_version": RULE_VERSION,
        "unknown_injuries_before_current_file": 44,
        "unknown_injuries_after": 33,
        "newly_adjudicated_time_loss_rows": TARGET_CSV_ROWS,
        "explicitly_retained_unknown_rows": EXCLUDED_CSV_ROWS,
        "manual_edits_already_present": MANUAL_EDITS,
        "row_count_unchanged": True,
        "source_row_mapping_unchanged": True,
    }
    return transformed, audit, qa


def apply_adjudications(
    *,
    input_csv: Path,
    manifest_path: Path,
    backup_csv: Path,
    backup_manifest: Path,
    audit_path: Path,
    qa_path: Path,
    decision_path: Path,
    script_path: Path,
    repo_root: Path,
    generated_at: str,
) -> dict[str, Any]:
    artifacts = (backup_csv, backup_manifest, audit_path, qa_path, decision_path)
    existing = [str(path) for path in artifacts if path.exists()]
    if existing:
        raise FileExistsError("Refusing to overwrite artifacts: " + ", ".join(existing))

    headers, rows = read_csv(input_csv)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_rows = [int(value) for value in manifest["selection"]["included_source_rows"]]
    input_hash = sha256_file(input_csv)
    manifest_hash = sha256_file(manifest_path)
    if len(rows) != 2301 or len(headers) != 28:
        raise ValueError("CSV shape drifted")
    if input_hash != EXPECTED_INPUT_HASH:
        raise ValueError("Input CSV differs from the reviewed manual-edit state")
    if mapping_sha256(source_rows) != EXPECTED_MAPPING_HASH:
        raise ValueError("Source-row mapping drifted")

    transformed, audit, qa = transform_dataset(rows, source_rows)
    shutil.copy2(input_csv, backup_csv)
    shutil.copy2(manifest_path, backup_manifest)
    if sha256_file(backup_csv) != input_hash or sha256_file(backup_manifest) != manifest_hash:
        raise ValueError("Backup verification failed")

    patch_csv_atomic(input_csv, headers, rows, transformed)
    output_hash = sha256_file(input_csv)

    manual_audit = []
    for csv_row, changes in MANUAL_EDITS.items():
        row = rows[csv_row - 2]
        for field, (old_value, new_value) in changes.items():
            if row[field] != new_value:
                raise ValueError(f"Expected manual edit absent at CSV row {csv_row}, field {field}")
            manual_audit.append({
                "csv_row": csv_row,
                "source_workbook_row": source_rows[csv_row - 2],
                "team": row["Team"],
                "player_id": row["PlayerID"],
                "field": field,
                "old_value": old_value,
                "new_value": new_value,
                "action": "user_applied_manual_edit_recorded",
                "reason": "Manual CSV edit confirmed by Abdel and reconciled against prior accepted state",
                "rule_version": RULE_VERSION,
                "evidence_origin": "Abdel manual review, 24 July 2026",
                "value_origin": "adjudicated",
            })
    write_csv_atomic(audit_path, AUDIT_HEADERS, manual_audit + audit)

    qa.update({
        "generated_at": generated_at,
        "rows": len(transformed),
        "columns": len(headers),
        "input_csv_sha256": input_hash,
        "output_csv_sha256": output_hash,
        "source_row_mapping_sha256": EXPECTED_MAPPING_HASH,
        "new_changes": len(audit),
        "recorded_prior_manual_changes": len(manual_audit),
        "unaffected_rows_equal": sum(
            before == after for before, after in zip(rows, transformed, strict=True)
        ) == len(rows) - len(TARGET_CSV_ROWS),
    })
    write_json_atomic(qa_path, qa)
    decision = {
        "rule_version": RULE_VERSION,
        "accepted_by": "Abdel Babiker",
        "accepted_at": generated_at,
        "scope": "2024-25 included injury CSV, season-specific row adjudications",
        "decision": (
            "Classify the listed Bulls and Cardiff Unknown injuries as Time Loss "
            "after diagnosis review; retain the six listed rows as Unknown."
        ),
        "adjudicated_csv_rows": TARGET_CSV_ROWS,
        "retained_unknown_csv_rows": EXCLUDED_CSV_ROWS,
        "methodological_limit": (
            "Diagnosis evidence supports these human decisions but does not create "
            "a general diagnosis-to-Time-Loss rule for other rows or seasons."
        ),
        "manual_edits_reconciled": MANUAL_EDITS,
    }
    write_json_atomic(decision_path, decision)

    def display(path: Path) -> str:
        try:
            return str(path.resolve().relative_to(repo_root.resolve()))
        except ValueError:
            return str(path.resolve())

    manifest["generated_at"] = generated_at
    manifest["output"]["csv_sha256"] = output_hash
    manifest.setdefault("cleanup_history", []).append({
        "rule_version": RULE_VERSION,
        "applied_at": generated_at,
        "script": display(script_path),
        "script_sha256": sha256_file(script_path),
        "input_csv_sha256": input_hash,
        "output_csv_sha256": output_hash,
        "backup_csv": display(backup_csv),
        "backup_csv_sha256": sha256_file(backup_csv),
        "backup_manifest": display(backup_manifest),
        "backup_manifest_sha256": sha256_file(backup_manifest),
        "audit": display(audit_path),
        "audit_sha256": sha256_file(audit_path),
        "qa": display(qa_path),
        "qa_sha256": sha256_file(qa_path),
        "decision": display(decision_path),
        "decision_sha256": sha256_file(decision_path),
        "adjudicated_csv_rows": TARGET_CSV_ROWS,
        "retained_unknown_csv_rows": EXCLUDED_CSV_ROWS,
        "manual_edits_reconciled": [138, 1264],
        "source_row_mapping_unchanged": True,
        "row_count_unchanged": True,
    })
    write_json_atomic(manifest_path, manifest)
    return {
        "rows": len(transformed),
        "columns": len(headers),
        "new_time_loss_adjudications": len(TARGET_CSV_ROWS),
        "unknown_injuries_after": 33,
        "output_csv_sha256": output_hash,
    }


def parse_args() -> argparse.Namespace:
    output = Path("outputs/urc_final_human_review_2024-25")
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-csv", type=Path, default=output / "urc_injury_included_dataset_2024-25.csv")
    parser.add_argument("--manifest", type=Path, default=output / "urc_injury_included_dataset_2024-25.manifest.json")
    parser.add_argument("--backup-csv", type=Path, default=output / "urc_injury_included_dataset_2024-25.pre_bulls_cardiff_adjudication_2026-07-24.csv")
    parser.add_argument("--backup-manifest", type=Path, default=output / "urc_injury_included_dataset_2024-25.pre_bulls_cardiff_adjudication_2026-07-24.manifest.json")
    parser.add_argument("--audit", type=Path, default=output / "urc_injury_bulls_cardiff_unknown_adjudication_audit_2026-07-24.csv")
    parser.add_argument("--qa", type=Path, default=output / "urc_injury_bulls_cardiff_unknown_adjudication_qa_2026-07-24.json")
    parser.add_argument("--decision", type=Path, default=output / "urc_injury_bulls_cardiff_unknown_adjudication_decision_2026-07-24.json")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    script = Path(__file__).resolve()
    result = apply_adjudications(
        input_csv=args.input_csv,
        manifest_path=args.manifest,
        backup_csv=args.backup_csv,
        backup_manifest=args.backup_manifest,
        audit_path=args.audit,
        qa_path=args.qa,
        decision_path=args.decision,
        script_path=script,
        repo_root=script.parents[1],
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
