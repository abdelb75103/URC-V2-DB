#!/usr/bin/env python3
"""Apply the accepted Fit For Selection Date rule to Unknown injuries."""

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


RULE_VERSION = "unknown_injury_fit_for_selection_2026-07-24_v1"
EXPECTED_ROWS = 2301
EXPECTED_COLUMNS = 28
EXPECTED_INPUT_HASH = "5a01bcbca75c8902353d09557d1a3d579153fe05a9d903005eaf35399b57f0bc"
EXPECTED_MAPPING_HASH = "9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f"
EXPECTED_CHANGES = {
    210: {"Confirmed Return Date": ("", "10/02/2025")},
    359: {
        "Confirmed Return Date": ("", "19/08/2025"),
        "Days Injured": ("", "397"),
        "TimeLoss vs Medical Attention": ("Unknown", "Time Loss"),
    },
    505: {
        "Confirmed Return Date": ("", "04/04/2025"),
        "Days Injured": ("", "0"),
        "TimeLoss vs Medical Attention": ("Unknown", "Medical Attention"),
    },
}
EXPECTED_SOURCE_VALUES = {
    210: {"Date Injured": "", "Fit For Selection Date": "10/02/25"},
    359: {"Date Injured": "18/07/2024", "Fit For Selection Date": "19/08/2025"},
    470: {"Date Injured": "25/01/2025", "Fit For Selection Date": "10/02/25q"},
    505: {"Date Injured": "04/04/2025", "Fit For Selection Date": "04/04/2025"},
    1735: {"Date Injured": "26/07/2024", "Fit For Selection Date": "20/07/2024"},
}
AUDIT_HEADERS = [
    "csv_row",
    "source_workbook_row",
    "team",
    "player_id",
    "field",
    "old_value",
    "new_value",
    "reason",
    "rule_version",
    "evidence_origin",
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


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        delete=False,
        prefix=f".{path.name}.",
        suffix=".tmp",
    ) as handle:
        temporary_path = Path(handle.name)
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary_path, path)


def write_csv_atomic(
    path: Path, headers: list[str], rows: list[dict[str, Any]]
) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="",
        dir=path.parent,
        delete=False,
        prefix=f".{path.name}.",
        suffix=".tmp",
    ) as handle:
        temporary_path = Path(handle.name)
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary_path, path)


def patch_csv_atomic(
    path: Path,
    headers: list[str],
    original_rows: list[dict[str, str]],
    transformed_rows: list[dict[str, str]],
) -> None:
    original_lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    if len(original_lines) != len(original_rows) + 1:
        raise ValueError("CSV contains nonstandard line breaks; narrow patch aborted")
    output_lines = [original_lines[0]]
    for original, transformed, original_line in zip(
        original_rows, transformed_rows, original_lines[1:], strict=True
    ):
        if original == transformed:
            output_lines.append(original_line)
            continue
        buffer = io.StringIO(newline="")
        csv.DictWriter(
            buffer, fieldnames=headers, lineterminator="\n"
        ).writerow(transformed)
        output_lines.append(buffer.getvalue())
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="",
        dir=path.parent,
        delete=False,
        prefix=f".{path.name}.",
        suffix=".tmp",
    ) as handle:
        temporary_path = Path(handle.name)
        handle.writelines(output_lines)
    os.replace(temporary_path, path)


def parse_date(value: str) -> datetime:
    for date_format in ("%d/%m/%Y", "%d/%m/%y"):
        try:
            return datetime.strptime(value, date_format)
        except ValueError:
            continue
    raise ValueError(f"Unparseable date: {value!r}")


def transform_dataset(
    rows: list[dict[str, str]],
    source_rows: list[int],
    source_master_rows: list[dict[str, str]],
) -> tuple[list[dict[str, str]], list[dict[str, Any]], dict[str, Any]]:
    if len(rows) != len(source_rows):
        raise ValueError("CSV and manifest source-row mapping lengths differ")
    indexed = {source_row: index for index, source_row in enumerate(source_rows)}
    if len(indexed) != len(source_rows):
        raise ValueError("Manifest source-row mapping contains duplicates")

    unknown = [
        source_row
        for source_row, row in zip(source_rows, rows, strict=True)
        if row["Problem type"].strip() == "Injury"
        and row["TimeLoss vs Medical Attention"].strip() == "Unknown"
    ]
    if len(unknown) != 60:
        raise ValueError(f"Expected 60 Unknown injuries, found {len(unknown)}")

    for source_row, expected in EXPECTED_SOURCE_VALUES.items():
        if source_row not in indexed:
            raise ValueError(f"Required source row is absent: {source_row}")
        source = source_master_rows[source_row - 2]
        current = rows[indexed[source_row]]
        if source["Team"] != current["Team"] or source["PlayerID"] != current["PlayerID"]:
            raise ValueError(f"Source binding mismatch at row {source_row}")
        for field, expected_value in expected.items():
            if source[field] != expected_value:
                raise ValueError(
                    f"Unexpected source {field} at row {source_row}: {source[field]!r}"
                )

    if (parse_date("19/08/2025") - parse_date("18/07/2024")).days != 397:
        raise AssertionError("Elapsed-day calculation drifted")
    if (parse_date("04/04/2025") - parse_date("04/04/2025")).days != 0:
        raise AssertionError("Same-day calculation drifted")

    transformed = [dict(row) for row in rows]
    audit: list[dict[str, Any]] = []
    for source_row, changes in EXPECTED_CHANGES.items():
        index = indexed[source_row]
        row = transformed[index]
        for field, (old_value, new_value) in changes.items():
            if row[field] != old_value:
                raise ValueError(
                    f"Unexpected {field} at source row {source_row}: {row[field]!r}"
                )
            row[field] = new_value
            audit.append(
                {
                    "csv_row": index + 2,
                    "source_workbook_row": source_row,
                    "team": row["Team"],
                    "player_id": row["PlayerID"],
                    "field": field,
                    "old_value": old_value,
                    "new_value": new_value,
                    "reason": "Accepted valid Fit For Selection Date rule",
                    "rule_version": RULE_VERSION,
                    "evidence_origin": (
                        "injury_master_2024-25.csv Fit For Selection Date, "
                        "bound through manifest included_source_rows"
                    ),
                }
            )

    values_after = Counter(
        row["TimeLoss vs Medical Attention"]
        for row in transformed
        if row["Problem type"] == "Injury"
    )
    qa = {
        "rule_version": RULE_VERSION,
        "unknown_injuries_before": 60,
        "unknown_injuries_after": values_after["Unknown"],
        "resolved_unknown_injuries": 2,
        "return_date_only_rows": [210],
        "classified_rows": [359, 505],
        "unresolved_fit_date_rows": {
            "470": "malformed Fit For Selection Date",
            "1735": "Fit For Selection Date precedes Date Injured",
        },
        "changes_by_field": dict(
            sorted(Counter(event["field"] for event in audit).items())
        ),
        "injury_classification_counts_after": dict(sorted(values_after.items())),
    }
    return transformed, audit, qa


def apply_rule(
    *,
    input_csv: Path,
    manifest_path: Path,
    source_master: Path,
    backup_csv: Path,
    backup_manifest: Path,
    audit_path: Path,
    qa_path: Path,
    script_path: Path,
    repo_root: Path,
    generated_at: str,
    expected_rows: int = EXPECTED_ROWS,
    expected_columns: int = EXPECTED_COLUMNS,
    expected_input_hash: str | None = EXPECTED_INPUT_HASH,
    expected_mapping_hash: str | None = EXPECTED_MAPPING_HASH,
) -> dict[str, Any]:
    outputs = (backup_csv, backup_manifest, audit_path, qa_path)
    existing = [str(path) for path in outputs if path.exists()]
    if existing:
        raise FileExistsError("Refusing to overwrite artifacts: " + ", ".join(existing))

    headers, rows = read_csv(input_csv)
    _, source_rows_data = read_csv(source_master)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_rows = [int(value) for value in manifest["selection"]["included_source_rows"]]
    input_hash = sha256_file(input_csv)
    input_manifest_hash = sha256_file(manifest_path)

    if len(rows) != expected_rows or len(headers) != expected_columns:
        raise ValueError("CSV shape does not match the expected contract")
    if headers != manifest["source"]["headers"]:
        raise ValueError("CSV headers do not match the manifest")
    if manifest["output"]["csv_sha256"] != input_hash:
        raise ValueError("CSV hash does not match the manifest")
    if expected_input_hash and input_hash != expected_input_hash:
        raise ValueError("Input CSV hash differs from the accepted starting point")
    current_mapping_hash = mapping_sha256(source_rows)
    if expected_mapping_hash and current_mapping_hash != expected_mapping_hash:
        raise ValueError("Source-row mapping hash differs from the accepted starting point")

    transformed, audit, qa = transform_dataset(rows, source_rows, source_rows_data)
    shutil.copy2(input_csv, backup_csv)
    shutil.copy2(manifest_path, backup_manifest)
    if sha256_file(backup_csv) != input_hash:
        raise ValueError("CSV backup verification failed")
    if sha256_file(backup_manifest) != input_manifest_hash:
        raise ValueError("Manifest backup verification failed")

    patch_csv_atomic(input_csv, headers, rows, transformed)
    output_hash = sha256_file(input_csv)
    write_csv_atomic(audit_path, AUDIT_HEADERS, audit)
    qa.update(
        {
            "generated_at": generated_at,
            "rows": len(transformed),
            "columns": len(headers),
            "input_csv_sha256": input_hash,
            "output_csv_sha256": output_hash,
            "source_row_mapping_sha256": current_mapping_hash,
            "unaffected_rows_equal": sum(a == b for a, b in zip(rows, transformed, strict=True))
            == len(rows) - len(EXPECTED_CHANGES),
        }
    )
    write_json_atomic(qa_path, qa)

    def display(path: Path) -> str:
        try:
            return str(path.resolve().relative_to(repo_root.resolve()))
        except ValueError:
            return str(path.resolve())

    manifest["generated_at"] = generated_at
    manifest["output"]["csv_sha256"] = output_hash
    manifest["output"]["data_rows"] = len(transformed)
    manifest["output"]["columns"] = len(headers)
    manifest.setdefault("cleanup_history", []).append(
        {
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
            "changed_source_workbook_rows": sorted(EXPECTED_CHANGES),
            "classified_source_workbook_rows": [359, 505],
            "return_date_only_source_workbook_rows": [210],
            "source_row_mapping_unchanged": True,
            "row_count_unchanged": True,
        }
    )
    write_json_atomic(manifest_path, manifest)
    return {
        "rows": len(transformed),
        "columns": len(headers),
        "changed_rows": len(EXPECTED_CHANGES),
        "classified_rows": 2,
        "unknown_injuries_after": qa["unknown_injuries_after"],
        "output_csv_sha256": output_hash,
    }


def parse_args() -> argparse.Namespace:
    output = Path("outputs/urc_final_human_review_2024-25")
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-csv", type=Path, default=output / "urc_injury_included_dataset_2024-25.csv")
    parser.add_argument("--manifest", type=Path, default=output / "urc_injury_included_dataset_2024-25.manifest.json")
    parser.add_argument("--source-master", type=Path, default=output / "injury_master_2024-25.csv")
    parser.add_argument("--backup-csv", type=Path, default=output / "urc_injury_included_dataset_2024-25.pre_unknown_fit_resolution_2026-07-24.csv")
    parser.add_argument("--backup-manifest", type=Path, default=output / "urc_injury_included_dataset_2024-25.pre_unknown_fit_resolution_2026-07-24.manifest.json")
    parser.add_argument("--audit", type=Path, default=output / "urc_injury_unknown_fit_resolution_audit_2026-07-24.csv")
    parser.add_argument("--qa", type=Path, default=output / "urc_injury_unknown_fit_resolution_qa_2026-07-24.json")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    script_path = Path(__file__).resolve()
    result = apply_rule(
        input_csv=args.input_csv,
        manifest_path=args.manifest,
        source_master=args.source_master,
        backup_csv=args.backup_csv,
        backup_manifest=args.backup_manifest,
        audit_path=args.audit,
        qa_path=args.qa,
        script_path=script_path,
        repo_root=script_path.parents[1],
        generated_at=datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
