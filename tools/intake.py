#!/usr/bin/env python3
"""Append canonical team injury CSVs or validate them against a frozen baseline."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any


DATE_FIELDS = (
    "Date Injured",
    "Fit For Selection Date",
    "Confirmed Return Date",
)
EXCLUSION_FIELD = "Exclusion Reason"
TEAM_FIELD = "Team"
# Columns that legitimately do not exist upstream of the human review:
# Team is implicit in a single-team file (filled from the team's display
# name), Diagnosis and Exclusion Reason are review-era columns (blank).
ABSENT_ALLOWED_FIELDS = frozenset({TEAM_FIELD, "Diagnosis", EXCLUSION_FIELD})
MASTER_SHEET = "Injury Master"
FORMAT = "urc-master-workbook"
FORMAT_VERSION = 1
DATE_FORMATS = (
    "%d/%m/%Y",
    "%Y-%m-%d",
    "%d-%m-%Y",
    "%Y/%m/%d",
    "%d/%m/%Y %H:%M:%S",
    "%Y-%m-%d %H:%M:%S",
)


class IntakeError(ValueError):
    """Raised when an intake file cannot meet the canonical contract."""


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def injury_sheet(payload: dict[str, Any]) -> dict[str, Any]:
    for sheet in payload.get("sheets", []):
        if sheet.get("name") == MASTER_SHEET:
            return sheet
    raise IntakeError(f"Master JSON has no {MASTER_SHEET!r} sheet")


def canonical_headers(root: Path, season: str) -> list[str]:
    source = (
        root
        / "data"
        / "2024-25"
        / "master"
        / "master_2024-25_v5.json"
    )
    if not source.exists():
        preferred = root / "data" / season / "master" / f"master_{season}_v5.json"
        fallback = root / "data" / season / "master" / f"master_{season}.json"
        source = preferred if preferred.exists() else fallback
    if not source.exists():
        raise IntakeError(
            "Cannot determine the canonical headers: no season master or "
            "2024-25 v5 baseline exists"
        )
    payload = json.loads(source.read_text(encoding="utf-8"))
    values = injury_sheet(payload).get("values", [])
    if not values:
        raise IntakeError(f"Canonical master has no header row: {source}")
    return values[0]


def parse_date(value: str) -> datetime | None:
    for date_format in DATE_FORMATS:
        try:
            return datetime.strptime(value, date_format)
        except ValueError:
            continue
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed


def normalize_value(field: str, value: Any) -> Any:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if field in DATE_FIELDS:
        parsed = parse_date(text)
        if parsed is not None:
            return {"$type": "datetime", "value": parsed.isoformat()}
    return text


def read_intake_csv(
    path: Path, headers: list[str], team_display: str | None = None
) -> tuple[list[list[Any]], list[str], list[str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        supplied = reader.fieldnames
        if supplied is None:
            raise IntakeError("CSV has no header row")
        duplicate_headers = sorted(
            {name for name in supplied if supplied.count(name) > 1}
        )
        if duplicate_headers:
            raise IntakeError(f"Duplicate CSV headers: {duplicate_headers}")
        missing = [
            name
            for name in headers
            if name not in supplied and name not in ABSENT_ALLOWED_FIELDS
        ]
        if missing:
            raise IntakeError(
                "Missing canonical columns: " + ", ".join(missing)
            )
        if TEAM_FIELD not in supplied and team_display is None:
            raise IntakeError(
                "Intake file has no Team column and no team display name "
                "is available to fill it"
            )
        absent_filled = sorted(
            name for name in ABSENT_ALLOWED_FIELDS if name not in supplied
        )
        dropped = [name for name in supplied if name not in headers]
        rows = []
        for source_row in reader:
            normalized = []
            for field in headers:
                if field in supplied:
                    raw = source_row.get(field)
                elif field == TEAM_FIELD:
                    raw = team_display
                else:
                    raw = ""
                normalized.append(normalize_value(field, raw))
            rows.append(normalized)
    return rows, dropped, absent_filled


def blank_rates(headers: list[str], rows: list[list[Any]]) -> dict[str, float]:
    count = len(rows)
    return {
        header: (
            sum(row[index] is None for row in rows) / count if count else 0.0
        )
        for index, header in enumerate(headers)
    }


def new_master(headers: list[str], source: Path) -> dict[str, Any]:
    return {
        "format": FORMAT,
        "format_version": FORMAT_VERSION,
        "source": {
            "path": str(source),
            "sha256": sha256_file(source),
        },
        "sheets": [
            {
                "name": MASTER_SHEET,
                "max_row": 1,
                "max_column": len(headers),
                "values": [headers],
                "styles": {},
                "column_widths": {},
                "row_heights": {},
                "merged_ranges": [],
                "tables": [],
            }
        ],
    }


def comparable(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, dict) and value.get("$type") in {"date", "datetime"}:
        parsed = datetime.fromisoformat(str(value["value"]))
        return parsed.date().isoformat()
    return str(value).strip()


def alignment_key(
    row: list[Any], index: dict[str, int]
) -> tuple[str, str]:
    return (
        comparable(row[index["PlayerID"]]),
        comparable(row[index["Date Injured"]]),
    )


def third_discriminator(
    row: list[Any], index: dict[str, int]
) -> tuple[str, ...]:
    return tuple(
        comparable(row[index[field]])
        for field in (
            "Description",
            "Body Part",
            "Problem type",
            "Occasion category",
        )
    )


def evidence_fields(record: dict[str, Any], headers: list[str]) -> set[str]:
    covered = set(
        record.get("value_change_summary", {}).get("by_field", {}).keys()
    )

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key in headers:
                    covered.add(key)
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
        elif isinstance(value, str):
            for header in headers:
                if re.search(rf"(?<!\w){re.escape(header)}(?!\w)", value):
                    covered.add(header)

    visit(record.get("steps_applied", []))
    visit(record.get("value_change_summary", {}).get("evidence", []))
    return covered


def baseline_team_rows(
    baseline: dict[str, Any],
    record: dict[str, Any],
    headers: list[str],
) -> list[tuple[int, list[Any]]]:
    sheet = injury_sheet(baseline)
    if sheet.get("values", [[]])[0] != headers:
        raise IntakeError("Baseline canonical header order does not match")
    team_index = headers.index("Team")
    team_name = record["team"]
    physical_range = record.get("row_reconciliation", {}).get(
        "physical_row_range_in_master"
    )
    if physical_range:
        start, end = physical_range
        selected = [
            (row_number, sheet["values"][row_number - 1])
            for row_number in range(start, end + 1)
        ]
        wrong = [
            row_number
            for row_number, row in selected
            if comparable(row[team_index]) != team_name
        ]
        if wrong:
            raise IntakeError(
                "Standardization Record physical range contains rows for a "
                f"different team: {wrong}"
            )
        return selected
    return [
        (row_number, row)
        for row_number, row in enumerate(sheet["values"][1:], start=2)
        if comparable(row[team_index]) == team_name
    ]


def validate_against_baseline(
    root: Path,
    team_key: str,
    season: str,
    source: Path,
    headers: list[str],
    intake_rows: list[list[Any]],
    dropped: list[str],
) -> dict[str, Any]:
    baseline_path = (
        root / "data" / season / "master" / f"master_{season}_v5.json"
    )
    record_path = (
        root
        / "data"
        / season
        / "intake"
        / "standardization_records"
        / f"{team_key}.json"
    )
    if not baseline_path.exists():
        raise IntakeError(f"Validation baseline does not exist: {baseline_path}")
    if not record_path.exists():
        raise IntakeError(
            f"Standardization Record does not exist: {record_path}"
        )
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    record = json.loads(record_path.read_text(encoding="utf-8"))
    master_rows = baseline_team_rows(baseline, record, headers)
    index = {header: position for position, header in enumerate(headers)}

    master_groups: dict[tuple[str, str], list[tuple[int, list[Any]]]] = defaultdict(list)
    for item in master_rows:
        master_groups[alignment_key(item[1], index)].append(item)

    aligned: list[tuple[int, int, list[Any], list[Any], str]] = []
    unalignable: list[dict[str, Any]] = []
    used_master_rows: set[int] = set()
    for intake_number, intake_row in enumerate(intake_rows, start=2):
        key = alignment_key(intake_row, index)
        candidates = [
            item for item in master_groups.get(key, [])
            if item[0] not in used_master_rows
        ]
        method = "player_date"
        if len(candidates) > 1:
            discriminator = third_discriminator(intake_row, index)
            candidates = [
                item
                for item in candidates
                if third_discriminator(item[1], index) == discriminator
            ]
            method = "player_date_third_discriminator"
        if len(candidates) != 1:
            unalignable.append(
                {
                    "intake_row": intake_number,
                    "reason": (
                        "no_match" if not candidates else "ambiguous_match"
                    ),
                    "candidate_master_rows": [item[0] for item in candidates],
                }
            )
            continue
        master_number, master_row = candidates[0]
        used_master_rows.add(master_number)
        aligned.append(
            (intake_number, master_number, intake_row, master_row, method)
        )

    covered_fields = evidence_fields(record, headers)
    covered_differences = []
    unexplained_differences = []
    for intake_number, master_number, intake_row, master_row, _ in aligned:
        for position, field in enumerate(headers):
            intake_value = comparable(intake_row[position])
            master_value = comparable(master_row[position])
            if intake_value == master_value:
                continue
            difference = {
                "field": field,
                "intake_row": intake_number,
                "master_row": master_number,
                "intake_value": intake_value,
                "master_value": master_value,
            }
            if field in covered_fields:
                covered_differences.append(difference)
            else:
                unexplained_differences.append(difference)

    unmatched_master = [
        row_number
        for row_number, _ in master_rows
        if row_number not in used_master_rows
    ]
    method_counts: dict[str, int] = defaultdict(int)
    for *_, method in aligned:
        method_counts[method] += 1
    return {
        "mode": "validate_against_baseline",
        "team_key": team_key,
        "team": record["team"],
        "season": season,
        "source_file": str(source),
        "source_sha256": sha256_file(source),
        "source_row_count": len(intake_rows),
        "dropped_columns": dropped,
        "blank_rates": blank_rates(headers, intake_rows),
        "alignment": {
            "intake_rows": len(intake_rows),
            "master_rows": len(master_rows),
            "aligned_rows": len(aligned),
            "unalignable_rows": unalignable,
            "unmatched_master_rows": unmatched_master,
            "method_counts": dict(sorted(method_counts.items())),
        },
        "covered_fields": sorted(covered_fields),
        "coverage_granularity": (
            "field_level: a difference counts as covered when its field "
            "appears in the team's recorded change evidence; row-level "
            "evidence does not exist for the documented-not-reexecuted era"
        ),
        "difference_counts": {
            "covered_field_level": len(covered_differences),
            "unexplained": len(unexplained_differences),
            "total": len(covered_differences) + len(unexplained_differences),
        },
        "covered_differences": covered_differences,
        "unexplained_differences": unexplained_differences,
    }


def append_intake(
    root: Path,
    team_key: str,
    season: str,
    source: Path,
    headers: list[str],
    rows: list[list[Any]],
    dropped: list[str],
    force_append: bool,
    out_report: Path | None,
) -> dict[str, Any]:
    master_dir = root / "data" / season / "master"
    baseline_record = master_dir / "baseline_record.json"
    if baseline_record.exists() and not force_append:
        raise IntakeError(
            f"Refusing to append to frozen season {season}: "
            f"{baseline_record} exists. Use --force-append only after a "
            "recorded decision authorizes that exact append."
        )
    master_path = master_dir / f"master_{season}.json"
    source_sha256 = sha256_file(source)
    if master_path.exists():
        payload = json.loads(master_path.read_text(encoding="utf-8"))
    else:
        payload = new_master(headers, source)
    appended_sources = payload.setdefault("appended_sources", [])
    if any(item.get("sha256") == source_sha256 for item in appended_sources):
        raise IntakeError(
            f"Source file already appended to this master (sha256 "
            f"{source_sha256}); appends are idempotent by source hash"
        )
    sheet = injury_sheet(payload)
    if sheet.get("values", [[]])[0] != headers:
        raise IntakeError("Existing master canonical header order does not match")
    team_index = headers.index(TEAM_FIELD)
    supplied_teams = sorted(
        {str(row[team_index]) for row in rows if row[team_index] is not None}
    )
    if len(supplied_teams) > 1:
        raise IntakeError(
            f"Intake file mixes teams {supplied_teams}; one team per intake"
        )
    previous_rows = len(sheet["values"]) - 1
    sheet["values"].extend(rows)
    sheet["max_row"] = len(sheet["values"])
    sheet["max_column"] = len(headers)
    appended_sources.append(
        {
            "team_key": team_key,
            "path": str(source),
            "sha256": source_sha256,
            "rows": len(rows),
        }
    )

    report = {
        "mode": "append",
        "team_key": team_key,
        "season": season,
        "source_file": str(source),
        "source_sha256": source_sha256,
        "source_row_count": len(rows),
        "team_values_in_rows": supplied_teams,
        "dropped_columns": dropped,
        "blank_rates": blank_rates(headers, rows),
        "master_path": str(master_path),
        "previous_master_rows": previous_rows,
        "appended_rows": len(rows),
        "master_rows_after": previous_rows + len(rows),
        "force_append": force_append,
    }
    report_path = out_report or master_dir / (
        f"intake_{team_key}_{season}_{report['source_sha256'][:12]}.json"
    )
    # Write the report first, then the master, so a crash between the two
    # leaves evidence of the attempt rather than an unexplained master change.
    write_json(report_path, report)
    write_json(master_path, payload)
    report["report_path"] = str(report_path)
    return report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Append or validate a canonical team injury intake CSV"
    )
    parser.add_argument("--team", required=True)
    parser.add_argument("--season", required=True)
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--validate-against-baseline", action="store_true")
    parser.add_argument(
        "--strict",
        action="store_true",
        help=(
            "Exit nonzero when validation finds unexplained differences or "
            "unalignable rows (the Year 2 gate posture; 2024-25 archaeology "
            "runs report-only by recorded design)"
        ),
    )
    parser.add_argument("--force-append", action="store_true")
    parser.add_argument("--out-report", type=Path)
    parser.add_argument(
        "--team-display",
        help=(
            "Display name used to fill an absent Team column; defaults to "
            "the team's Standardization Record 'team' value when present"
        ),
    )
    return parser


def team_display_name(root: Path, season: str, team_key: str) -> str | None:
    record_path = (
        root
        / "data"
        / season
        / "intake"
        / "standardization_records"
        / f"{team_key}.json"
    )
    if not record_path.exists():
        return None
    record = json.loads(record_path.read_text(encoding="utf-8"))
    team = record.get("team")
    return str(team) if team else None


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path.cwd()
    try:
        headers = canonical_headers(root, args.season)
        display = args.team_display or team_display_name(
            root, args.season, args.team
        )
        rows, dropped, absent_filled = read_intake_csv(
            args.file, headers, display
        )
        if absent_filled:
            print(
                "Canonical columns absent from the intake file: "
                + ", ".join(absent_filled)
                + f" (Team filled as {display!r}; others blank)"
            )
        if args.validate_against_baseline:
            report = validate_against_baseline(
                root,
                args.team,
                args.season,
                args.file,
                headers,
                rows,
                dropped,
            )
            report_path = args.out_report or (
                root
                / "data"
                / args.season
                / "intake"
                / "validation"
                / f"{args.team}_{args.season}_validation.json"
            )
            write_json(report_path, report)
            unexplained = report["difference_counts"]["unexplained"]
            unalignable = len(report["alignment"]["unalignable_rows"])
            print(
                f"{args.team}: aligned {report['alignment']['aligned_rows']}/"
                f"{report['alignment']['intake_rows']}, "
                "covered (field-level) "
                f"{report['difference_counts']['covered_field_level']}, "
                f"unexplained {unexplained}"
            )
            if unalignable:
                print(f"Unalignable intake rows: {unalignable}")
            print(f"Report: {report_path}")
            if args.strict and (unexplained or unalignable):
                print(
                    "STRICT: validation failed with "
                    f"{unexplained} unexplained differences and "
                    f"{unalignable} unalignable rows"
                )
                return 1
            return 0
        report = append_intake(
            root,
            args.team,
            args.season,
            args.file,
            headers,
            rows,
            dropped,
            args.force_append,
            args.out_report,
        )
        print(
            f"{args.team}: appended {report['appended_rows']} rows; "
            f"master now has {report['master_rows_after']} rows"
        )
        print(f"Report: {report['report_path']}")
        return 0
    except (OSError, csv.Error, json.JSONDecodeError, IntakeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
