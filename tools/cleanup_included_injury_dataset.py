#!/usr/bin/env python3
"""Apply the approved focused cleanup to the included injury CSV."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import tempfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RULE_VERSION = "included_injury_focused_cleanup_2026-07-23_v1"
EXPECTED_ROWS = 2426
EXPECTED_COLUMNS = 28
DATE_FORMAT = "%d/%m/%Y"
MISSING_DAYS_TOKENS = {"", "-"}
TIME_LOSS_TRUE = {"TRUE", "Yes", "Time Loss"}
TIME_LOSS_FALSE = {"FALSE", "No", "Medical Attention"}
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


def display_path(path: Path, repo_root: Path) -> str:
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(repo_root.resolve()))
    except ValueError:
        return str(resolved)


def parse_date(value: str) -> datetime | None:
    text = value.strip()
    if not text:
        return None
    try:
        return datetime.strptime(text, DATE_FORMAT)
    except ValueError:
        return None


def parse_nonnegative_integer(value: str) -> int | None:
    text = value.strip()
    if not text:
        return None
    try:
        parsed = int(text)
    except ValueError:
        return None
    return parsed if parsed >= 0 else None


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"CSV has no header row: {path}")
        headers = list(reader.fieldnames)
        rows = [dict(row) for row in reader]
    return headers, rows


def write_csv_atomic(
    path: Path, headers: list[str], rows: list[dict[str, str]]
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
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
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary_path, path)


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
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
    path.parent.mkdir(parents=True, exist_ok=True)
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
        writer = csv.DictWriter(
            handle, fieldnames=AUDIT_HEADERS, lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary_path, path)


def audit_change(
    *,
    audit_rows: list[dict[str, Any]],
    csv_row: int,
    source_workbook_row: int,
    row: dict[str, str],
    field: str,
    old_value: str,
    new_value: str,
    reason: str,
    evidence_origin: str,
) -> None:
    audit_rows.append(
        {
            "csv_row": csv_row,
            "source_workbook_row": source_workbook_row,
            "team": row["Team"],
            "player_id": row["PlayerID"],
            "field": field,
            "old_value": old_value,
            "new_value": new_value,
            "reason": reason,
            "rule_version": RULE_VERSION,
            "evidence_origin": evidence_origin,
        }
    )


def transform_dataset(
    rows: list[dict[str, str]],
    source_rows: list[int],
) -> tuple[list[dict[str, str]], list[dict[str, Any]], dict[str, Any]]:
    if len(rows) != len(source_rows):
        raise ValueError(
            "CSV data rows and manifest source-row mapping have different lengths"
        )

    transformed = [dict(row) for row in rows]
    audit_rows: list[dict[str, Any]] = []
    days_filled_by_team: Counter[str] = Counter()
    days_missing_token_cleared_by_team: Counter[str] = Counter()
    time_loss_changes_by_team: Counter[str] = Counter()
    recurrence_changes_by_team: Counter[str] = Counter()
    existing_duration_date_mismatches: list[dict[str, Any]] = []

    for index, row in enumerate(transformed):
        csv_row = index + 2
        source_workbook_row = source_rows[index]
        injury_date = parse_date(row["Date Injured"])
        return_date = parse_date(row["Confirmed Return Date"])
        old_days = row["Days Injured"]
        existing_days = parse_nonnegative_integer(old_days)

        if (
            existing_days is not None
            and injury_date is not None
            and return_date is not None
        ):
            date_span = (return_date - injury_date).days
            if date_span >= 0 and existing_days != date_span:
                existing_duration_date_mismatches.append(
                    {
                        "csv_row": csv_row,
                        "source_workbook_row": source_workbook_row,
                        "team": row["Team"],
                        "player_id": row["PlayerID"],
                        "date_injured": row["Date Injured"],
                        "confirmed_return_date": row["Confirmed Return Date"],
                        "existing_days_injured": existing_days,
                        "date_span_days": date_span,
                        "difference": existing_days - date_span,
                    }
                )

        if old_days.strip() in MISSING_DAYS_TOKENS:
            if injury_date is not None and return_date is not None:
                derived_days = (return_date - injury_date).days
                if derived_days >= 0:
                    new_days = str(derived_days)
                    if new_days != old_days:
                        row["Days Injured"] = new_days
                        days_filled_by_team[row["Team"]] += 1
                        audit_change(
                            audit_rows=audit_rows,
                            csv_row=csv_row,
                            source_workbook_row=source_workbook_row,
                            row=row,
                            field="Days Injured",
                            old_value=old_days,
                            new_value=new_days,
                            reason=(
                                "Derived elapsed calendar days from confirmed dates, "
                                "excluding the injury day"
                            ),
                            evidence_origin=(
                                f"Date Injured={row['Date Injured']}; "
                                "Confirmed Return Date="
                                f"{row['Confirmed Return Date']}"
                            ),
                        )
            elif old_days.strip() == "-":
                row["Days Injured"] = ""
                days_missing_token_cleared_by_team[row["Team"]] += 1
                audit_change(
                    audit_rows=audit_rows,
                    csv_row=csv_row,
                    source_workbook_row=source_workbook_row,
                    row=row,
                    field="Days Injured",
                    old_value=old_days,
                    new_value="",
                    reason="Normalized a missing-value token to a true blank",
                    evidence_origin="Existing Days Injured source token '-'",
                )

        old_recurrence = row["Recurrence"]
        if old_recurrence.strip() == "New case":
            row["Recurrence"] = "New injury"
            recurrence_changes_by_team[row["Team"]] += 1
            audit_change(
                audit_rows=audit_rows,
                csv_row=csv_row,
                source_workbook_row=source_workbook_row,
                row=row,
                field="Recurrence",
                old_value=old_recurrence,
                new_value="New injury",
                reason="Normalized synonymous first-episode recurrence labels",
                evidence_origin="Existing Recurrence value 'New case'",
            )

        old_time_loss = row["TimeLoss vs Medical Attention"]
        final_days = parse_nonnegative_integer(row["Days Injured"])
        if final_days is not None:
            new_time_loss = (
                "Medical Attention" if final_days == 0 else "Time Loss"
            )
            time_loss_reason = (
                "Classified from Days Injured: zero is Medical Attention and "
                "greater than zero is Time Loss"
            )
            time_loss_evidence = f"Days Injured={final_days}"
        elif old_time_loss.strip() in TIME_LOSS_TRUE:
            new_time_loss = "Time Loss"
            time_loss_reason = "Normalized an existing affirmative time-loss value"
            time_loss_evidence = (
                f"Existing TimeLoss vs Medical Attention={old_time_loss.strip()}"
            )
        elif old_time_loss.strip() in TIME_LOSS_FALSE:
            new_time_loss = "Medical Attention"
            time_loss_reason = "Normalized an existing negative time-loss value"
            time_loss_evidence = (
                f"Existing TimeLoss vs Medical Attention={old_time_loss.strip()}"
            )
        else:
            new_time_loss = "Unknown"
            time_loss_reason = (
                "Set controlled Unknown because neither a usable duration nor "
                "an existing classification was available"
            )
            time_loss_evidence = (
                "Days Injured is blank or invalid; existing time-loss value is blank"
            )

        if new_time_loss != old_time_loss:
            row["TimeLoss vs Medical Attention"] = new_time_loss
            time_loss_changes_by_team[row["Team"]] += 1
            audit_change(
                audit_rows=audit_rows,
                csv_row=csv_row,
                source_workbook_row=source_workbook_row,
                row=row,
                field="TimeLoss vs Medical Attention",
                old_value=old_time_loss,
                new_value=new_time_loss,
                reason=time_loss_reason,
                evidence_origin=time_loss_evidence,
            )

    remaining_missing_days: list[dict[str, Any]] = []
    duration_outliers: list[dict[str, Any]] = []
    malformed_date_values: list[dict[str, Any]] = []
    occasion_values: Counter[str] = Counter()
    body_values: Counter[str] = Counter()
    contact_values: Counter[str] = Counter()
    recurrence_values: Counter[str] = Counter()
    time_loss_values: Counter[str] = Counter()
    diagnosis_mismatches: list[dict[str, Any]] = []
    exact_duplicate_groups: defaultdict[
        tuple[str, ...], list[dict[str, Any]]
    ] = defaultdict(list)
    candidate_duplicate_groups: defaultdict[
        tuple[str, ...], list[dict[str, Any]]
    ] = defaultdict(list)

    for index, row in enumerate(transformed):
        csv_row = index + 2
        source_workbook_row = source_rows[index]
        parsed_days = parse_nonnegative_integer(row["Days Injured"])
        if parsed_days is None:
            remaining_missing_days.append(
                {
                    "csv_row": csv_row,
                    "source_workbook_row": source_workbook_row,
                    "team": row["Team"],
                    "player_id": row["PlayerID"],
                    "date_injured": row["Date Injured"],
                    "confirmed_return_date": row["Confirmed Return Date"],
                    "days_injured": row["Days Injured"],
                    "time_loss_classification": row[
                        "TimeLoss vs Medical Attention"
                    ],
                }
            )
        elif parsed_days > 300:
            duration_outliers.append(
                {
                    "csv_row": csv_row,
                    "source_workbook_row": source_workbook_row,
                    "team": row["Team"],
                    "player_id": row["PlayerID"],
                    "date_injured": row["Date Injured"],
                    "confirmed_return_date": row["Confirmed Return Date"],
                    "days_injured": parsed_days,
                    "description": row["Description"],
                }
            )

        for field in ("Date Injured", "Confirmed Return Date"):
            value = row[field].strip()
            if value and parse_date(value) is None:
                malformed_date_values.append(
                    {
                        "csv_row": csv_row,
                        "source_workbook_row": source_workbook_row,
                        "team": row["Team"],
                        "player_id": row["PlayerID"],
                        "field": field,
                        "value": value,
                    }
                )

        occasion_values[row["Occasion category"].strip()] += 1
        body_values[row["Body Part"].strip()] += 1
        contact_values[row["Is Contact"].strip()] += 1
        recurrence_values[row["Recurrence"].strip()] += 1
        time_loss_values[row["TimeLoss vs Medical Attention"].strip()] += 1

        expected_diagnosis = (
            f"{row['Body Part'].strip()} - "
            f"{row['Injury Tissue Type/s'].strip()}"
        )
        if row["Diagnosis"].strip() != expected_diagnosis:
            diagnosis_mismatches.append(
                {
                    "csv_row": csv_row,
                    "source_workbook_row": source_workbook_row,
                    "team": row["Team"],
                    "player_id": row["PlayerID"],
                    "diagnosis": row["Diagnosis"],
                    "expected_from_components": expected_diagnosis,
                }
            )

        full_key = tuple(row[header] for header in row)
        exact_duplicate_groups[full_key].append(
            {
                "csv_row": csv_row,
                "source_workbook_row": source_workbook_row,
            }
        )
        candidate_key = (
            row["Team"].strip(),
            row["PlayerID"].strip(),
            row["Date Injured"].strip(),
            row["Diagnosis"].strip(),
        )
        candidate_duplicate_groups[candidate_key].append(
            {
                "csv_row": csv_row,
                "source_workbook_row": source_workbook_row,
            }
        )

    exact_duplicates = [
        {"rows": members}
        for members in exact_duplicate_groups.values()
        if len(members) > 1
    ]
    candidate_duplicates = [
        {
            "team": key[0],
            "player_id": key[1],
            "date_injured": key[2],
            "diagnosis": key[3],
            "rows": members,
        }
        for key, members in candidate_duplicate_groups.items()
        if len(members) > 1
    ]

    qa = {
        "rule_version": RULE_VERSION,
        "rows": len(transformed),
        "changed_cells": len(audit_rows),
        "changed_rows": len({row["csv_row"] for row in audit_rows}),
        "changes_by_field": dict(
            sorted(Counter(row["field"] for row in audit_rows).items())
        ),
        "days_injured": {
            "filled_from_dates": sum(days_filled_by_team.values()),
            "filled_from_dates_by_team": dict(sorted(days_filled_by_team.items())),
            "missing_tokens_cleared": sum(
                days_missing_token_cleared_by_team.values()
            ),
            "missing_tokens_cleared_by_team": dict(
                sorted(days_missing_token_cleared_by_team.items())
            ),
            "remaining_missing_or_invalid": len(remaining_missing_days),
            "remaining_missing_or_invalid_rows": remaining_missing_days,
            "existing_numeric_date_span_mismatches_unchanged": len(
                existing_duration_date_mismatches
            ),
            "existing_numeric_date_span_mismatch_rows": (
                existing_duration_date_mismatches
            ),
            "over_300_days": len(duration_outliers),
            "over_300_day_rows": duration_outliers,
        },
        "time_loss": {
            "changed": sum(time_loss_changes_by_team.values()),
            "changed_by_team": dict(sorted(time_loss_changes_by_team.items())),
            "values_after": dict(sorted(time_loss_values.items())),
        },
        "recurrence": {
            "changed": sum(recurrence_changes_by_team.values()),
            "changed_by_team": dict(sorted(recurrence_changes_by_team.items())),
            "values_after": dict(sorted(recurrence_values.items())),
        },
        "controlled_value_counts": {
            "occasion_category": dict(sorted(occasion_values.items())),
            "body_part": dict(sorted(body_values.items())),
            "is_contact": dict(sorted(contact_values.items())),
        },
        "diagnosis_component_mismatches": {
            "count": len(diagnosis_mismatches),
            "rows": diagnosis_mismatches,
        },
        "date_values_not_in_dd_mm_yyyy": {
            "count": len(malformed_date_values),
            "rows": malformed_date_values,
        },
        "duplicates_for_review": {
            "exact_duplicate_groups": exact_duplicates,
            "candidate_team_player_date_diagnosis_groups": candidate_duplicates,
        },
    }
    return transformed, audit_rows, qa


def apply_cleanup(
    *,
    input_csv: Path,
    manifest_path: Path,
    backup_csv: Path,
    backup_manifest: Path,
    audit_path: Path,
    qa_path: Path,
    script_path: Path,
    repo_root: Path,
    generated_at: str,
    expected_rows: int = EXPECTED_ROWS,
    expected_columns: int = EXPECTED_COLUMNS,
) -> dict[str, Any]:
    output_paths = (backup_csv, backup_manifest, audit_path, qa_path)
    existing_outputs = [str(path) for path in output_paths if path.exists()]
    if existing_outputs:
        raise FileExistsError(
            "Refusing to overwrite existing cleanup artifacts: "
            + ", ".join(existing_outputs)
        )

    headers, rows = read_csv(input_csv)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if len(headers) != expected_columns:
        raise ValueError(
            f"Expected {expected_columns} columns, found {len(headers)}"
        )
    if len(rows) != expected_rows:
        raise ValueError(f"Expected {expected_rows} data rows, found {len(rows)}")
    if headers != manifest["source"]["headers"]:
        raise ValueError("CSV headers do not match the manifest header order")
    source_rows = manifest["selection"]["included_source_rows"]
    if len(source_rows) != len(rows):
        raise ValueError("Manifest source-row mapping does not match CSV row count")
    if manifest["output"]["csv_sha256"] != sha256_file(input_csv):
        raise ValueError("Input CSV hash does not match the manifest")

    input_csv_hash = sha256_file(input_csv)
    input_manifest_hash = sha256_file(manifest_path)
    transformed, audit_rows, qa = transform_dataset(rows, source_rows)

    shutil.copy2(input_csv, backup_csv)
    shutil.copy2(manifest_path, backup_manifest)
    if sha256_file(backup_csv) != input_csv_hash:
        raise ValueError("CSV backup hash does not match the input CSV")
    if sha256_file(backup_manifest) != input_manifest_hash:
        raise ValueError("Manifest backup hash does not match the input manifest")

    write_audit_atomic(audit_path, audit_rows)
    qa["generated_at"] = generated_at
    qa["input_csv_sha256"] = input_csv_hash
    qa["backup_csv_sha256"] = sha256_file(backup_csv)
    write_json_atomic(qa_path, qa)
    write_csv_atomic(input_csv, headers, transformed)

    output_csv_hash = sha256_file(input_csv)
    history_entry = {
        "rule_version": RULE_VERSION,
        "applied_at": generated_at,
        "script": display_path(script_path, repo_root),
        "script_sha256": sha256_file(script_path),
        "input_csv_sha256": input_csv_hash,
        "output_csv_sha256": output_csv_hash,
        "backup_csv": display_path(backup_csv, repo_root),
        "backup_csv_sha256": sha256_file(backup_csv),
        "backup_manifest": display_path(backup_manifest, repo_root),
        "backup_manifest_sha256": sha256_file(backup_manifest),
        "audit": display_path(audit_path, repo_root),
        "audit_sha256": sha256_file(audit_path),
        "qa": display_path(qa_path, repo_root),
        "qa_sha256": sha256_file(qa_path),
        "changed_cells": len(audit_rows),
        "changed_rows": len({row["csv_row"] for row in audit_rows}),
        "changes_by_field": qa["changes_by_field"],
        "source_row_mapping_unchanged": True,
    }
    manifest.setdefault("cleanup_history", []).append(history_entry)
    manifest["generated_at"] = generated_at
    manifest["output"]["csv_sha256"] = output_csv_hash
    manifest["output"]["data_rows"] = len(transformed)
    manifest["output"]["columns"] = len(headers)
    write_json_atomic(manifest_path, manifest)

    return {
        "rows": len(transformed),
        "columns": len(headers),
        "input_csv_sha256": input_csv_hash,
        "output_csv_sha256": output_csv_hash,
        "changed_cells": len(audit_rows),
        "changed_rows": len({row["csv_row"] for row in audit_rows}),
        "changes_by_field": qa["changes_by_field"],
        "days_filled_from_dates": qa["days_injured"]["filled_from_dates"],
        "remaining_missing_days": qa["days_injured"][
            "remaining_missing_or_invalid"
        ],
        "over_300_days": qa["days_injured"]["over_300_days"],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply focused deterministic cleanup to the included injury CSV"
    )
    parser.add_argument("--input-csv", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--backup-csv", type=Path, required=True)
    parser.add_argument("--backup-manifest", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--qa", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--generated-at",
        default=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = apply_cleanup(
        input_csv=args.input_csv,
        manifest_path=args.manifest,
        backup_csv=args.backup_csv,
        backup_manifest=args.backup_manifest,
        audit_path=args.audit,
        qa_path=args.qa,
        script_path=Path(__file__).resolve(),
        repo_root=args.repo_root,
        generated_at=args.generated_at,
    )
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
