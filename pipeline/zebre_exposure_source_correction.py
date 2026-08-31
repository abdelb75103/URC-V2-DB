"""Checksum-bound repair for the 2025-26 Zebre October and November CSVs.

The source exports use semicolon delimiters and decimal commas.  This module
repairs only those two files by joining their physical data-row numbers to the
approved V14 candidate.  It never copies source player labels into the
candidate and never appends rows.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from contextlib import redirect_stdout
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, InvalidOperation
import hashlib
from io import StringIO
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Iterable

from argparse import Namespace

from pipeline.__main__ import clean_exposure


TARGET_FILES = {"OCT-2025.csv", "NOV-2025.csv"}
LOCATOR_FIELDS = ("source_file_sha256", "source_row_number")
IDENTITY_FIELDS = (
    "player_uid",
    "source_archive_path",
    "source_file_sha256",
    "source_sheet",
    "source_row_number",
    "source_row_sha256",
    "standardised_file_sha256",
    "standardised_row_number",
)
CLEANER_FIELDS = (
    "exposure_grain",
    "scope_status",
    "scope_reason",
    "cleaned_date",
    "week_start_date",
    "session_date_clean",
    "minutes_total_clean",
    "distance_total_m_clean",
    "cleaning_action",
    "exclusion_reason",
)
REPLAY_FIELDS = tuple(field for field in CLEANER_FIELDS if field not in {"scope_status", "scope_reason"})
SCOPE_REASONS = frozenset(
    {
        "explicit_rehab_or_rtp",
        "explicit_international_exposure",
        "academy_game",
        "non_urc_or_unspecified_game",
    }
)


@dataclass(frozen=True)
class CorrectionSummary:
    predecessor_rows: int
    matched_locators: int
    duplicate_locators: int
    patched_rows: int
    recovered_rows: int
    retained_exclusions: int
    recovered_hours: Decimal
    recovered_distance_km: Decimal
    corrected_season_hours: Decimal
    corrected_season_distance_km: Decimal
    impossible_source_distance_rows: int
    exclusion_reason_counts: dict[str, int]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_decimal_comma_metres(value: object) -> Decimal:
    """Parse one source distance without silently changing its scale."""

    text = str(value if value is not None else "").strip()
    if not text or "," not in text or "." in text:
        raise ValueError("source distance must use one decimal comma")
    if text.count(",") != 1:
        raise ValueError("source distance has an invalid decimal-comma form")
    try:
        distance = Decimal(text.replace(",", "."))
    except InvalidOperation as exc:
        raise ValueError("source distance is not numeric") from exc
    if not distance.is_finite() or distance < 0:
        raise ValueError("source distance must be finite and non-negative")
    return distance.quantize(Decimal("0.000001"))


def _profile_source(profile: dict[str, object], file_name: str) -> dict[str, object]:
    for item in profile.get("inputs", []):
        if isinstance(item, dict) and item.get("file") == file_name:
            return item
    raise ValueError(f"profile does not bind source file {file_name}")


def _load_source_distances(
    path: Path, profile: dict[str, object]
) -> tuple[dict[tuple[str, str], Decimal], dict[str, object]]:
    file_name = path.name
    if file_name not in TARGET_FILES:
        raise ValueError(f"unexpected Zebre source file {file_name}")
    bound = _profile_source(profile, file_name)
    actual_sha = sha256_file(path)
    expected_sha = str(bound.get("sha256", ""))
    if actual_sha != expected_sha:
        raise ValueError(f"checksum mismatch for {file_name}")
    expected_rows = int(bound.get("data_rows", 0))
    distances: dict[tuple[str, str], Decimal] = {}
    dates: list[datetime] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        headers = reader.fieldnames or []
        if "Total Distance (m)" not in headers or "Date" not in headers:
            raise ValueError(f"required source columns are missing from {file_name}")
        for source_row_number, row in enumerate(reader, start=2):
            if None in row:
                raise ValueError(f"source row has an unexpected delimiter shape in {file_name}")
            date_text = str(row.get("Date") or "").strip()
            try:
                dates.append(datetime.strptime(date_text, "%d/%m/%Y"))
            except ValueError as exc:
                raise ValueError(f"unparseable source date in {file_name}") from exc
            distances[(actual_sha, str(source_row_number))] = parse_decimal_comma_metres(
                row.get("Total Distance (m)")
            )
    if len(distances) != expected_rows:
        raise ValueError(f"row-count mismatch for {file_name}")
    if not dates:
        raise ValueError(f"source file {file_name} is empty")
    if min(dates).date().isoformat() != str(bound.get("date_start")) or max(dates).date().isoformat() != str(bound.get("date_end")):
        raise ValueError(f"date range mismatch for {file_name}")
    metadata = {
        "file": file_name,
        "sha256": actual_sha,
        "rows": len(distances),
        "date_min": min(dates).date().isoformat(),
        "date_max": max(dates).date().isoformat(),
    }
    return distances, metadata


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        if not reader.fieldnames or None in reader.fieldnames:
            raise ValueError("candidate CSV has an invalid header")
        if any(None in row for row in rows):
            raise ValueError("candidate CSV has an invalid row shape")
        return reader.fieldnames, rows


def _reason_list(value: str) -> list[str]:
    return [reason for reason in value.split(";") if reason]


def _matching_indices(
    predecessor_rows: list[dict[str, str]],
    source_distances: dict[tuple[str, str], Decimal],
) -> tuple[dict[tuple[str, str], int], int]:
    if not predecessor_rows:
        raise ValueError("approved predecessor is empty")
    required = {"distance total", "minutes total", *LOCATOR_FIELDS}
    missing = required - set(predecessor_rows[0])
    if missing:
        raise ValueError("approved predecessor is missing required canonical fields")

    matching_indices: dict[tuple[str, str], int] = {}
    duplicate_locators = 0
    for index, row in enumerate(predecessor_rows):
        key = (row.get("source_file_sha256", ""), row.get("source_row_number", ""))
        if key in source_distances:
            if key in matching_indices:
                duplicate_locators += 1
            else:
                matching_indices[key] = index
    missing_locators = set(source_distances) - set(matching_indices)
    if missing_locators:
        raise ValueError(f"approved predecessor is missing {len(missing_locators)} bound locators")
    return matching_indices, duplicate_locators


def _build_cleaner_input(
    predecessor_rows: list[dict[str, str]],
    source_distances: dict[tuple[str, str], Decimal],
    matching_indices: dict[tuple[str, str], int],
) -> tuple[list[str], list[dict[str, str]]]:
    """Prepare transient cleaner input while retaining approved scope decisions."""

    fieldnames = [field for field in predecessor_rows[0] if field not in CLEANER_FIELDS]
    if "Training Type" not in fieldnames:
        raise ValueError("approved predecessor is missing Training Type")
    target_indices = set(matching_indices.values())
    cleaner_rows: list[dict[str, str]] = []
    for index, row in enumerate(predecessor_rows):
        cleaner_row = {field: row.get(field, "") for field in fieldnames}
        if index in target_indices:
            key = (row.get("source_file_sha256", ""), row.get("source_row_number", ""))
            cleaner_row["distance total"] = f"{source_distances[key]:.6f}"
        if row.get("scope_status") == "out_of_scope_explicit":
            # The unchanged cleaner has no adjudication-input hook. Replaying
            # its controlled international marker preserves approved scope;
            # the synthetic value is removed during the merge.
            cleaner_row["Training Type"] = "International"
        cleaner_rows.append(cleaner_row)
    return fieldnames, cleaner_rows


def _run_cleaner(
    fieldnames: list[str], rows: list[dict[str, str]]
) -> tuple[list[str], list[dict[str, str]], dict[str, object]]:
    with TemporaryDirectory(prefix="zebre-exposure-cleaner-") as directory:
        directory_path = Path(directory)
        cleaner_input = directory_path / "candidate_input.csv"
        cleaner_output = directory_path / "candidate_clean.csv"
        cleaner_qc = directory_path / "candidate_clean_qc.json"
        _write_csv(cleaner_input, fieldnames, rows)
        args = Namespace(
            file=cleaner_input,
            output=cleaner_output,
            qc_output=cleaner_qc,
            manifest=None,
            reporting_grain="session",
            date_order="month-first",
            window_start="2025-09-01",
            window_end="2026-06-30",
            team="Zebre",
            season="2025-26",
        )
        with redirect_stdout(StringIO()):
            clean_exposure(args)
        cleaner_fieldnames, cleaner_rows = _read_csv(cleaner_output)
        cleaner_qc_payload = json.loads(cleaner_qc.read_text(encoding="utf-8"))
        cleaner_qc_payload.pop("file", None)
        cleaner_qc_payload.pop("source_file", None)
        cleaner_qc_payload.pop("qc", None)
        return cleaner_fieldnames, cleaner_rows, cleaner_qc_payload


def _merged_exclusion_reason(
    predecessor_row: dict[str, str], cleaner_row: dict[str, str]
) -> str:
    reasons = [
        reason
        for reason in _reason_list(cleaner_row.get("exclusion_reason", ""))
        if reason not in SCOPE_REASONS
    ]
    if predecessor_row.get("scope_status") == "out_of_scope_explicit":
        original_scope_reason = predecessor_row.get("scope_reason", "")
        if original_scope_reason:
            reasons.insert(0, original_scope_reason)
    return ";".join(dict.fromkeys(reasons))


def _merge_cleaner_rows(
    predecessor_rows: list[dict[str, str]],
    cleaner_rows: list[dict[str, str]],
    matching_indices: dict[tuple[str, str], int],
) -> list[dict[str, str]]:
    if len(predecessor_rows) != len(cleaner_rows):
        raise ValueError("cleaner replay changed the predecessor row count")
    target_indices = set(matching_indices.values())
    merged_rows: list[dict[str, str]] = []
    for index, (predecessor_row, cleaner_row) in enumerate(
        zip(predecessor_rows, cleaner_rows, strict=True)
    ):
        locator = (predecessor_row.get("source_file_sha256"), predecessor_row.get("source_row_number"))
        cleaner_locator = (cleaner_row.get("source_file_sha256"), cleaner_row.get("source_row_number"))
        if locator != cleaner_locator:
            raise ValueError("cleaner replay changed source locator order")
        merged = dict(predecessor_row)
        if index in target_indices:
            merged["distance total"] = cleaner_row["distance total"]
            for field in REPLAY_FIELDS:
                merged[field] = cleaner_row[field]
            merged["exclusion_reason"] = _merged_exclusion_reason(predecessor_row, cleaner_row)
            if any(merged[field] != predecessor_row[field] for field in IDENTITY_FIELDS):
                raise ValueError("source correction changed an identity or locator field")
        merged_rows.append(merged)
    return merged_rows


def _summarise(
    rows: list[dict[str, str]],
    matching_indices: dict[tuple[str, str], int],
    duplicate_locators: int,
) -> CorrectionSummary:
    target_rows = [rows[index] for index in matching_indices.values()]
    recovered = [row for row in target_rows if row.get("cleaning_action") == "include"]
    included = [row for row in rows if row.get("cleaning_action") == "include"]
    reasons = Counter(
        reason
        for row in target_rows
        for reason in _reason_list(row.get("exclusion_reason", ""))
    )
    recovered_hours = sum((Decimal(row["minutes_total_clean"]) for row in recovered), Decimal()) / Decimal("60")
    recovered_distance_km = sum(
        (Decimal(row["distance_total_m_clean"]) for row in recovered), Decimal()
    ) / Decimal("1000")
    corrected_season_hours = sum(
        (Decimal(row["minutes_total_clean"]) for row in included), Decimal()
    ) / Decimal("60")
    corrected_season_distance_km = sum(
        (Decimal(row["distance_total_m_clean"]) for row in included), Decimal()
    ) / Decimal("1000")
    return CorrectionSummary(
        predecessor_rows=len(rows),
        matched_locators=len(matching_indices),
        duplicate_locators=duplicate_locators,
        patched_rows=len(matching_indices),
        recovered_rows=len(recovered),
        retained_exclusions=len(target_rows) - len(recovered),
        recovered_hours=recovered_hours,
        recovered_distance_km=recovered_distance_km,
        corrected_season_hours=corrected_season_hours,
        corrected_season_distance_km=corrected_season_distance_km,
        impossible_source_distance_rows=reasons.get("session_impossible_distance_per_minute", 0),
        exclusion_reason_counts=dict(reasons),
    )


def _profile_reconciliation_status(
    profile: dict[str, object], summary: CorrectionSummary
) -> dict[str, object]:
    """Record profile drift without editing or silently trusting stale values."""

    expected = profile.get("reconciliation")
    if not isinstance(expected, dict):
        raise ValueError("profile reconciliation is missing")
    actual = {
        "rows_requiring_distance_reparse": summary.matched_locators,
        "expected_new_inclusions_after_reparse": summary.recovered_rows,
        "expected_existing_qc_exclusions_after_reparse": summary.retained_exclusions,
        "expected_recovered_hours": str(summary.recovered_hours),
        "expected_recovered_distance_km": str(summary.recovered_distance_km),
        "expected_corrected_season_hours": str(summary.corrected_season_hours),
        "expected_corrected_season_distance_km": str(summary.corrected_season_distance_km),
    }
    mismatches: dict[str, dict[str, object]] = {}
    for key, value in actual.items():
        if key not in expected:
            mismatches[key] = {"profile": None, "computed": value}
            continue
        if key.startswith("expected_") and key != "expected_existing_qc_exclusions_after_reparse":
            matches = Decimal(str(expected[key])).quantize(Decimal("0.00000001")) == Decimal(str(value)).quantize(Decimal("0.00000001"))
        else:
            matches = int(expected[key]) == int(value)
        if not matches:
            mismatches[key] = {"profile": expected[key], "computed": value}
    if summary.duplicate_locators != 0 or summary.impossible_source_distance_rows != 1:
        raise ValueError("source correction locator or impossible-distance reconciliation failed")
    return {
        "status": "matched" if not mismatches else "profile_values_do_not_match_cleaner_replay",
        "profile": {key: expected.get(key) for key in actual},
        "computed": actual,
        "mismatches": mismatches,
    }


def _write_csv(path: Path, fieldnames: list[str], rows: Iterable[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def repair_zebre_exposure(
    *,
    profile_path: Path,
    mapping_path: Path,
    oct_source: Path,
    nov_source: Path,
    predecessor_path: Path,
    output_path: Path,
    qc_path: Path,
    manifest_path: Path,
) -> CorrectionSummary:
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    mapping = json.loads(mapping_path.read_text(encoding="utf-8"))
    if profile.get("team_key") != "zebre" or profile.get("season") != "2025-26":
        raise ValueError("source correction profile is not for Zebre 2025-26")
    if not profile.get("approval_ready") or not profile.get("approved_by") or not profile.get("approved_at"):
        raise ValueError("source correction profile is not approved")
    mapping_sha = sha256_file(mapping_path)
    if mapping_sha != profile.get("mapping_sha256"):
        raise ValueError("mapping checksum does not match approved profile")
    if mapping.get("mapping_version") != profile.get("mapping_version"):
        raise ValueError("mapping version does not match approved profile")
    expected_source_scope = {
        str(item.get("sha256"))
        for item in profile.get("inputs", [])
        if isinstance(item, dict) and item.get("file") in TARGET_FILES
    }
    mapping_source_scope = mapping.get("source_scope", {})
    if set(mapping_source_scope.get("file_sha256s", [])) != expected_source_scope:
        raise ValueError("mapping source scope does not match approved profile")
    predecessor_sha = sha256_file(predecessor_path)
    approved_inputs = set(profile.get("approved_input_sha256s", []))
    if predecessor_sha not in approved_inputs:
        raise ValueError("predecessor checksum is not approved")

    source_distances: dict[tuple[str, str], Decimal] = {}
    source_metadata = []
    for source_path in (oct_source, nov_source):
        distances, metadata = _load_source_distances(source_path, profile)
        overlap = source_distances.keys() & distances.keys()
        if overlap:
            raise ValueError("source locator appears in both repair inputs")
        source_distances.update(distances)
        source_metadata.append(metadata)
        if metadata["sha256"] not in approved_inputs:
            raise ValueError("source checksum is not approved")

    fieldnames, predecessor_rows = _read_csv(predecessor_path)
    matching_indices, duplicate_locators = _matching_indices(predecessor_rows, source_distances)
    cleaner_input_fields, cleaner_input_rows = _build_cleaner_input(
        predecessor_rows, source_distances, matching_indices
    )
    cleaner_fields, cleaner_rows, cleaner_qc = _run_cleaner(
        cleaner_input_fields, cleaner_input_rows
    )
    if any(field not in cleaner_fields for field in CLEANER_FIELDS):
        raise ValueError("unchanged cleaner did not emit the canonical cleaning fields")
    repaired_rows = _merge_cleaner_rows(predecessor_rows, cleaner_rows, matching_indices)
    summary = _summarise(repaired_rows, matching_indices, duplicate_locators)
    profile_reconciliation = _profile_reconciliation_status(profile, summary)
    _write_csv(output_path, fieldnames, repaired_rows)

    qc = {
        "schema": "urc_2025_26_zebre_exposure_source_correction_qc_v1",
        "team": "Zebre",
        "team_key": "zebre",
        "season": "2025-26",
        "profile_sha256": sha256_file(profile_path),
        "mapping_sha256": mapping_sha,
        "predecessor_sha256": predecessor_sha,
        "output_sha256": sha256_file(output_path),
        "source_files": source_metadata,
        "predecessor_rows": summary.predecessor_rows,
        "matched_locators": summary.matched_locators,
        "duplicate_locators": summary.duplicate_locators,
        "patched_rows": summary.patched_rows,
        "recovered_rows": summary.recovered_rows,
        "retained_exclusions": summary.retained_exclusions,
        "impossible_source_distance_rows": summary.impossible_source_distance_rows,
        "exclusion_reason_counts": summary.exclusion_reason_counts,
        "recovered_hours": float(summary.recovered_hours),
        "recovered_distance_km": float(summary.recovered_distance_km),
        "corrected_season_hours": float(summary.corrected_season_hours),
        "corrected_season_distance_km": float(summary.corrected_season_distance_km),
        "cleaner_replay": {
            "rule_source": "pipeline.__main__.clean_exposure",
            "qc": cleaner_qc,
        },
        "profile_reconciliation": profile_reconciliation,
        "replacement_policy": "full_candidate_replacement_no_append",
        "database_accessed": False,
    }
    qc_path.parent.mkdir(parents=True, exist_ok=True)
    qc_path.write_text(json.dumps(qc, indent=2) + "\n", encoding="utf-8")
    manifest = {
        "schema": "urc_2025_26_zebre_exposure_source_correction_manifest_v1",
        "profile_path": str(profile_path),
        "profile_sha256": qc["profile_sha256"],
        "mapping_path": str(mapping_path),
        "mapping_sha256": mapping_sha,
        "predecessor_path": str(predecessor_path),
        "predecessor_sha256": predecessor_sha,
        "candidate_path": str(output_path),
        "candidate_sha256": qc["output_sha256"],
        "qc_path": str(qc_path),
        "qc_sha256": sha256_file(qc_path),
        "source_files": source_metadata,
        "matched_locators": summary.matched_locators,
        "duplicate_locators": summary.duplicate_locators,
        "recovered_rows": summary.recovered_rows,
        "retained_exclusions": summary.retained_exclusions,
        "recovered_hours": qc["recovered_hours"],
        "recovered_distance_km": qc["recovered_distance_km"],
        "corrected_season_hours": qc["corrected_season_hours"],
        "corrected_season_distance_km": qc["corrected_season_distance_km"],
        "database_accessed": False,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return summary


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--mapping", type=Path, required=True)
    parser.add_argument("--oct-source", type=Path, required=True)
    parser.add_argument("--nov-source", type=Path, required=True)
    parser.add_argument("--predecessor", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--qc-output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    return parser


def main() -> None:
    args = _parser().parse_args()
    summary = repair_zebre_exposure(
        profile_path=args.profile,
        mapping_path=args.mapping,
        oct_source=args.oct_source,
        nov_source=args.nov_source,
        predecessor_path=args.predecessor,
        output_path=args.output,
        qc_path=args.qc_output,
        manifest_path=args.manifest,
    )
    print(
        json.dumps(
            {
                "candidate": str(args.output),
                "matched_locators": summary.matched_locators,
                "duplicate_locators": summary.duplicate_locators,
                "recovered_rows": summary.recovered_rows,
                "retained_exclusions": summary.retained_exclusions,
                "recovered_hours": float(summary.recovered_hours),
                "recovered_distance_km": float(summary.recovered_distance_km),
                "corrected_season_hours": float(summary.corrected_season_hours),
                "corrected_season_distance_km": float(summary.corrected_season_distance_km),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
