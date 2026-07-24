#!/usr/bin/env python3
"""Apply accepted Unknown-injury inference rules with row-level provenance."""

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


RULE_VERSION = "unknown_injury_inference_2026-07-24_v1"
EXPECTED_INPUT_HASH = "01d36f73c5da84eecbf635ac37a14bbd6a5fd4caf03237a35d4f39a7505514c3"
EXPECTED_MAPPING_HASH = "9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f"
SURGERY_ROWS = {185, 198, 202, 382, 468, 492, 498, 502, 512, 539, 1764}
POSITIVE_GAMES_MISSED_ROWS = {209}
CORRECTED_FIT_DATE_ROW = 470
UNRESOLVED_ADJUDICATION_ROW = 1735
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
    original_lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if len(original_lines) != len(original) + 1:
        raise ValueError("CSV contains nonstandard line breaks; narrow patch aborted")
    output = [original_lines[0]]
    for before, after, line in zip(
        original, transformed, original_lines[1:], strict=True
    ):
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
    rows: list[dict[str, str]],
    source_rows: list[int],
    source_master: list[dict[str, str]],
) -> tuple[list[dict[str, str]], list[dict[str, Any]], dict[str, Any]]:
    indexed = {source_row: index for index, source_row in enumerate(source_rows)}
    required = (
        SURGERY_ROWS
        | POSITIVE_GAMES_MISSED_ROWS
        | {CORRECTED_FIT_DATE_ROW, UNRESOLVED_ADJUDICATION_ROW}
    )
    if required - set(indexed):
        raise ValueError(f"Required source rows missing: {sorted(required - set(indexed))}")

    transformed = [dict(row) for row in rows]
    audit: list[dict[str, Any]] = []

    def change(
        source_row: int,
        field: str,
        new_value: str,
        action: str,
        reason: str,
        evidence: str,
        origin: str,
    ) -> None:
        index = indexed[source_row]
        row = transformed[index]
        old_value = row[field]
        if field == "TimeLoss vs Medical Attention" and old_value != "Unknown":
            raise ValueError(f"Expected Unknown classification at source row {source_row}")
        if field != "TimeLoss vs Medical Attention" and old_value != "":
            raise ValueError(f"Expected blank {field} at source row {source_row}")
        row[field] = new_value
        audit.append({
            "csv_row": index + 2,
            "source_workbook_row": source_row,
            "team": row["Team"],
            "player_id": row["PlayerID"],
            "field": field,
            "old_value": old_value,
            "new_value": new_value,
            "action": action,
            "reason": reason,
            "rule_version": RULE_VERSION,
            "evidence_origin": evidence,
            "value_origin": origin,
        })

    source_470 = source_master[CORRECTED_FIT_DATE_ROW - 2]
    if (
        source_470["Date Injured"] != "25/01/2025"
        or source_470["Fit For Selection Date"] != "10/02/25q"
    ):
        raise ValueError("Source row 470 date evidence drifted")
    change(
        470, "Confirmed Return Date", "10/02/2025",
        "adjudicated_typo_correction",
        "Remove the uniquely identifiable trailing q from 10/02/25q",
        "Source Fit For Selection Date=10/02/25q and accepted adjudication",
        "adjudicated",
    )
    change(
        470, "Days Injured", "16", "deterministic_derivation",
        "Elapsed calendar days from 25/01/2025 to 10/02/2025, excluding injury day",
        "Corrected Fit For Selection Date and Date Injured",
        "derived",
    )
    change(
        470, "TimeLoss vs Medical Attention", "Time Loss",
        "inferred_classification",
        "Positive derived duration implies Time Loss",
        "Derived Days Injured=16",
        "inferred",
    )

    for source_row in sorted(POSITIVE_GAMES_MISSED_ROWS):
        source = source_master[source_row - 2]
        games_missed = source["Games Missed"].strip()
        if not games_missed or float(games_missed) <= 0:
            raise ValueError(f"Positive Games Missed evidence absent at row {source_row}")
        change(
            source_row, "TimeLoss vs Medical Attention", "Time Loss",
            "inferred_classification",
            "Positive Games Missed establishes lost match availability",
            f"Source Games Missed={games_missed}",
            "inferred",
        )

    for source_row in sorted(SURGERY_ROWS):
        source = source_master[source_row - 2]
        if source["Required Surgery"].strip().lower() != "yes":
            raise ValueError(f"Surgery evidence absent at row {source_row}")
        change(
            source_row, "TimeLoss vs Medical Attention", "Time Loss",
            "inferred_classification",
            "Required Surgery=Yes implies time loss",
            "Source Required Surgery=Yes",
            "inferred",
        )

    source_1735 = source_master[UNRESOLVED_ADJUDICATION_ROW - 2]
    if (
        source_1735["Date Injured"] != "26/07/2024"
        or source_1735["Fit For Selection Date"] != "20/07/2024"
    ):
        raise ValueError("Source row 1735 date evidence drifted")

    unknown_after = sum(
        row["Problem type"] == "Injury"
        and row["TimeLoss vs Medical Attention"] == "Unknown"
        for row in transformed
    )
    qa = {
        "rule_version": RULE_VERSION,
        "unknown_injuries_before": 58,
        "unknown_injuries_after": unknown_after,
        "resolved_unknown_injuries": 13,
        "corrected_fit_date_rows": [470],
        "positive_games_missed_rows": sorted(POSITIVE_GAMES_MISSED_ROWS),
        "required_surgery_rows": sorted(SURGERY_ROWS),
        "unresolved_adjudication_rows": [1735],
        "changes_by_field": dict(
            sorted(Counter(event["field"] for event in audit).items())
        ),
    }
    if unknown_after != 45 or len(audit) != 15:
        raise ValueError("Unexpected inference result")
    return transformed, audit, qa


def apply_rules(
    *,
    input_csv: Path,
    manifest_path: Path,
    source_master_path: Path,
    backup_csv: Path,
    backup_manifest: Path,
    audit_path: Path,
    qa_path: Path,
    adjudication_path: Path,
    script_path: Path,
    repo_root: Path,
    generated_at: str,
    expected_input_hash: str | None = EXPECTED_INPUT_HASH,
    expected_mapping_hash: str | None = EXPECTED_MAPPING_HASH,
) -> dict[str, Any]:
    artifacts = (
        backup_csv, backup_manifest, audit_path, qa_path, adjudication_path
    )
    existing = [str(path) for path in artifacts if path.exists()]
    if existing:
        raise FileExistsError("Refusing to overwrite artifacts: " + ", ".join(existing))

    headers, rows = read_csv(input_csv)
    _, source_master = read_csv(source_master_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_rows = [int(value) for value in manifest["selection"]["included_source_rows"]]
    input_hash = sha256_file(input_csv)
    input_manifest_hash = sha256_file(manifest_path)
    if len(rows) != 2301 or len(headers) != 28:
        raise ValueError("CSV shape drifted")
    if manifest["output"]["csv_sha256"] != input_hash:
        raise ValueError("CSV hash does not match manifest")
    if expected_input_hash and input_hash != expected_input_hash:
        raise ValueError("CSV input hash differs from accepted starting point")
    current_mapping_hash = mapping_sha256(source_rows)
    if expected_mapping_hash and current_mapping_hash != expected_mapping_hash:
        raise ValueError("Source-row mapping hash drifted")

    transformed, audit, qa = transform_dataset(rows, source_rows, source_master)
    shutil.copy2(input_csv, backup_csv)
    shutil.copy2(manifest_path, backup_manifest)
    if sha256_file(backup_csv) != input_hash or sha256_file(backup_manifest) != input_manifest_hash:
        raise ValueError("Backup verification failed")

    patch_csv_atomic(input_csv, headers, rows, transformed)
    output_hash = sha256_file(input_csv)
    write_csv_atomic(audit_path, AUDIT_HEADERS, audit)
    adjudication = {
        "rule_version": RULE_VERSION,
        "accepted_by": "Abdel Babiker",
        "accepted_at": generated_at,
        "scope": "2024-25 included injury CSV only",
        "accepted_rules": [
            {
                "rule": "A uniquely identifiable trailing q in 10/02/25q is removed",
                "application": "source row 470",
                "origin": "adjudicated",
            },
            {
                "rule": "Positive Games Missed implies Time Loss",
                "application": "source row 209",
                "origin": "inferred",
            },
            {
                "rule": "Required Surgery=Yes implies Time Loss",
                "application": "11 listed source rows",
                "origin": "inferred",
            },
        ],
        "unresolved": [
            {
                "source_workbook_row": 1735,
                "reason": "Fit For Selection Date 20/07/2024 precedes Date Injured 26/07/2024",
                "clinical_context": "Ospreys; right anterior thigh muscle injury; training; gradual non-contact onset; no surgery",
                "status": "requires_adjudication",
            }
        ],
    }
    write_json_atomic(adjudication_path, adjudication)
    qa.update({
        "generated_at": generated_at,
        "rows": len(transformed),
        "columns": len(headers),
        "input_csv_sha256": input_hash,
        "output_csv_sha256": output_hash,
        "source_row_mapping_sha256": current_mapping_hash,
        "unaffected_rows_equal": sum(
            before == after
            for before, after in zip(rows, transformed, strict=True)
        ) == len(rows) - 13,
    })
    write_json_atomic(qa_path, qa)

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
        "adjudication": display(adjudication_path),
        "adjudication_sha256": sha256_file(adjudication_path),
        "changed_source_workbook_rows": sorted(
            SURGERY_ROWS | POSITIVE_GAMES_MISSED_ROWS | {470}
        ),
        "unresolved_adjudication_rows": [1735],
        "source_row_mapping_unchanged": True,
        "row_count_unchanged": True,
    })
    write_json_atomic(manifest_path, manifest)
    return {
        "rows": len(transformed),
        "columns": len(headers),
        "resolved_unknown_injuries": 13,
        "unknown_injuries_after": 45,
        "output_csv_sha256": output_hash,
    }


def parse_args() -> argparse.Namespace:
    output = Path("outputs/urc_final_human_review_2024-25")
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-csv", type=Path, default=output / "urc_injury_included_dataset_2024-25.csv")
    parser.add_argument("--manifest", type=Path, default=output / "urc_injury_included_dataset_2024-25.manifest.json")
    parser.add_argument("--source-master", type=Path, default=output / "injury_master_2024-25.csv")
    parser.add_argument("--backup-csv", type=Path, default=output / "urc_injury_included_dataset_2024-25.pre_unknown_inference_2026-07-24.csv")
    parser.add_argument("--backup-manifest", type=Path, default=output / "urc_injury_included_dataset_2024-25.pre_unknown_inference_2026-07-24.manifest.json")
    parser.add_argument("--audit", type=Path, default=output / "urc_injury_unknown_inference_audit_2026-07-24.csv")
    parser.add_argument("--qa", type=Path, default=output / "urc_injury_unknown_inference_qa_2026-07-24.json")
    parser.add_argument("--adjudication", type=Path, default=output / "urc_injury_unknown_inference_adjudication_2026-07-24.json")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    script_path = Path(__file__).resolve()
    result = apply_rules(
        input_csv=args.input_csv,
        manifest_path=args.manifest,
        source_master_path=args.source_master,
        backup_csv=args.backup_csv,
        backup_manifest=args.backup_manifest,
        audit_path=args.audit,
        qa_path=args.qa,
        adjudication_path=args.adjudication,
        script_path=script_path,
        repo_root=script_path.parents[1],
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
