#!/usr/bin/env python3
"""Standing, season-keyed comparability checks for a canonical master table."""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path
from typing import Any


MASTER_SHEET = "Injury Master"
INVENTORY_FIELDS = (
    "Problem type",
    "Occasion category",
    "Match Type",
    "Recurrence",
    "Required Surgery",
    "TimeLoss vs Medical Attention",
)
DATE_FIELDS = (
    "Date Injured",
    "Fit For Selection Date",
    "Confirmed Return Date",
)


class CheckError(ValueError):
    """Raised when the master cannot be checked."""


def injury_sheet(payload: dict[str, Any]) -> dict[str, Any]:
    for sheet in payload.get("sheets", []):
        if sheet.get("name") == MASTER_SHEET:
            return sheet
    raise CheckError(f"Master JSON has no {MASTER_SHEET!r} sheet")


def load_headers_and_rows(path: Path) -> tuple[list[str], list[list[Any]]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    values = injury_sheet(payload).get("values", [])
    if not values:
        return [], []
    return values[0], values[1:]


def canonical_headers(root: Path) -> list[str]:
    baseline = (
        root / "data" / "2024-25" / "master" / "master_2024-25_v5.json"
    )
    if not baseline.exists():
        raise CheckError(f"Canonical 2024-25 baseline not found: {baseline}")
    headers, _ = load_headers_and_rows(baseline)
    return headers


def is_blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


def display(value: Any) -> str:
    if is_blank(value):
        return ""
    if isinstance(value, dict) and value.get("$type") in {"date", "datetime"}:
        return str(value.get("value", ""))
    return str(value).strip()


def parse_date(value: Any) -> date | None:
    if is_blank(value):
        return None
    if isinstance(value, dict) and value.get("$type") in {"date", "datetime"}:
        try:
            return datetime.fromisoformat(str(value["value"])).date()
        except (KeyError, TypeError, ValueError):
            return None
    text = str(value).strip()
    for date_format in (
        "%d/%m/%Y",
        "%Y-%m-%d",
        "%d-%m-%Y",
        "%Y/%m/%d",
        "%d/%m/%Y %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
    ):
        try:
            return datetime.strptime(text, date_format).date()
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text).date()
    except ValueError:
        return None


def season_window(season: str) -> tuple[date, date]:
    try:
        start_text, end_text = season.split("-", 1)
        start_year = int(start_text)
        end_year = int(end_text)
    except (TypeError, ValueError) as error:
        raise CheckError(
            f"Season must look like 2024-25, received {season!r}"
        ) from error
    if end_year != (start_year + 1) % 100:
        raise CheckError(f"Season years are not consecutive: {season!r}")
    return date(start_year, 7, 1), date(start_year + 1, 6, 30)


def row_signature(row: list[Any]) -> str:
    return json.dumps(row, sort_keys=True, ensure_ascii=False)


def numeric(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        result = float(value)
        return result if math.isfinite(result) else None
    try:
        result = float(str(value).strip())
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def run_checks(root: Path, season: str) -> dict[str, Any]:
    preferred = root / "data" / season / "master" / f"master_{season}_v5.json"
    fallback = root / "data" / season / "master" / f"master_{season}.json"
    master_path = preferred if preferred.exists() else fallback
    if not master_path.exists():
        raise CheckError(f"Season master does not exist: {master_path}")
    headers, rows = load_headers_and_rows(master_path)
    expected_headers = canonical_headers(root)
    failures: list[dict[str, Any]] = []
    info: list[dict[str, Any]] = []

    if headers != expected_headers:
        failures.append(
            {
                "check": "canonical_header_order",
                "expected": expected_headers,
                "actual": headers,
            }
        )
    if not rows:
        failures.append({"check": "row_count_zero"})
    if headers != expected_headers:
        return {
            "status": "FAIL",
            "season": season,
            "master_path": str(master_path),
            "row_count": len(rows),
            "team_count": 0,
            "excluded_row_count": 0,
            "failures": failures,
            "flags": {},
            "info": info,
            "team_summary": [],
        }
    malformed_rows = [
        {"row": row_number, "columns": len(row)}
        for row_number, row in enumerate(rows, start=2)
        if len(row) != len(headers)
    ]
    failures.extend(
        {
            "check": "row_column_count",
            **item,
            "expected_columns": len(headers),
        }
        for item in malformed_rows
    )
    if malformed_rows:
        return {
            "status": "FAIL",
            "season": season,
            "master_path": str(master_path),
            "row_count": len(rows),
            "team_count": 0,
            "excluded_row_count": 0,
            "failures": failures,
            "flags": {},
            "info": info,
            "team_summary": [],
        }

    index = {header: position for position, header in enumerate(headers)}
    exclusion_index = index["Exclusion Reason"]
    signature_rows: dict[str, list[int]] = defaultdict(list)
    for row_number, row in enumerate(rows, start=2):
        signature_rows[row_signature(row)].append(row_number)
        exclusion = row[exclusion_index]
        if not is_blank(exclusion) and not isinstance(exclusion, str):
            failures.append(
                {
                    "check": "non_text_exclusion_reason",
                    "row": row_number,
                    "value_type": type(exclusion).__name__,
                }
            )
    for duplicate_rows in signature_rows.values():
        if len(duplicate_rows) < 2:
            continue
        first_row = rows[duplicate_rows[0] - 2]
        item = {
            "check": "identical_full_rows",
            "rows": duplicate_rows,
        }
        if not is_blank(first_row[exclusion_index]):
            item["classification"] = "excluded_duplicate_info"
            info.append(item)
        else:
            failures.append(item)

    start, end = season_window(season)
    date_parse = {}
    for field in DATE_FIELDS:
        field_index = index[field]
        populated = 0
        parsed = 0
        unparseable = []
        for row_number, row in enumerate(rows, start=2):
            value = row[field_index]
            if is_blank(value):
                continue
            populated += 1
            if parse_date(value) is None:
                unparseable.append(
                    {"row": row_number, "value": display(value)}
                )
            else:
                parsed += 1
        date_parse[field] = {
            "populated": populated,
            "parsed": parsed,
            "parse_rate": parsed / populated if populated else 1.0,
            "unparseable": unparseable,
        }

    out_of_window = []
    injury_index = index["Date Injured"]
    for row_number, row in enumerate(rows, start=2):
        parsed = parse_date(row[injury_index])
        if parsed is not None and not start <= parsed <= end:
            out_of_window.append(
                {"row": row_number, "date": parsed.isoformat()}
            )

    invalid_days = []
    negative_days = []
    days_index = index["Days Injured"]
    for row_number, row in enumerate(rows, start=2):
        value = row[days_index]
        if is_blank(value):
            continue
        parsed = numeric(value)
        if parsed is None:
            invalid_days.append(
                {"row": row_number, "value": display(value)}
            )
        elif parsed < 0:
            negative_days.append(
                {"row": row_number, "value": parsed}
            )

    date_order = []
    for row_number, row in enumerate(rows, start=2):
        injured = parse_date(row[index["Date Injured"]])
        if injured is None:
            continue
        for field in ("Fit For Selection Date", "Confirmed Return Date"):
            later = parse_date(row[index[field]])
            if later is not None and later < injured:
                date_order.append(
                    {
                        "row": row_number,
                        "field": field,
                        "date_injured": injured.isoformat(),
                        "later_date": later.isoformat(),
                    }
                )

    inventories = {}
    for field in INVENTORY_FIELDS:
        counts = Counter(
            display(row[index[field]])
            for row in rows
            if not is_blank(row[index[field]])
        )
        inventories[field] = dict(sorted(counts.items()))
    exclusion_counts = Counter(
        display(row[exclusion_index])
        for row in rows
        if not is_blank(row[exclusion_index])
    )

    team_counts = Counter(
        display(row[index["Team"]])
        for row in rows
        if not is_blank(row[index["Team"]])
    )
    team_excluded = Counter(
        display(row[index["Team"]])
        for row in rows
        if not is_blank(row[index["Team"]])
        and not is_blank(row[exclusion_index])
    )
    team_summary = [
        {
            "team": team,
            "rows": count,
            "excluded": team_excluded[team],
        }
        for team, count in sorted(team_counts.items())
    ]
    blank_rates = {
        header: (
            sum(is_blank(row[position]) for row in rows) / len(rows)
            if rows
            else 0.0
        )
        for position, header in enumerate(headers)
    }
    flags = {
        "date_parse": date_parse,
        "dates_outside_season_window": out_of_window,
        "non_numeric_days_injured": invalid_days,
        "negative_days_injured": negative_days,
        "date_order": date_order,
    }
    return {
        "status": "FAIL" if failures else "PASS_WITH_FLAGS",
        "season": season,
        "analysis_window": {
            "start": start.isoformat(),
            "end": end.isoformat(),
        },
        "master_path": str(master_path),
        "row_count": len(rows),
        "team_count": len(team_counts),
        "excluded_row_count": sum(exclusion_counts.values()),
        "failures": failures,
        "flags": flags,
        "info": info,
        "team_summary": team_summary,
        "blank_rates": blank_rates,
        "value_inventories": inventories,
        "exclusion_reason_vocabulary": dict(sorted(exclusion_counts.items())),
    }


def print_summary(report: dict[str, Any]) -> None:
    print(
        f"Season {report['season']}: {report['status']} | "
        f"{report['row_count']} rows | {report['team_count']} teams | "
        f"{report['excluded_row_count']} excluded"
    )
    if report["team_summary"]:
        print(f"{'Team':<22} {'Rows':>6} {'Excluded':>9}")
        for item in report["team_summary"]:
            print(
                f"{item['team']:<22} {item['rows']:>6} "
                f"{item['excluded']:>9}"
            )
    flags = report.get("flags", {})
    print(
        "Flags: "
        f"out-of-window={len(flags.get('dates_outside_season_window', []))}, "
        f"non-numeric-days={len(flags.get('non_numeric_days_injured', []))}, "
        f"negative-days={len(flags.get('negative_days_injured', []))}, "
        f"date-order={len(flags.get('date_order', []))}"
    )
    for item in flags.get("date_order", []):
        print(f"FLAG row {item['row']}: {item['field']} before Date Injured")
    for failure in report.get("failures", []):
        print(f"FAIL {failure['check']}: {failure}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run standing comparability checks on a season master"
    )
    parser.add_argument("--season", required=True)
    parser.add_argument("--report", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path.cwd()
    try:
        report = run_checks(root, args.season)
    except (OSError, json.JSONDecodeError, CheckError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    report_path = args.report
    if report_path:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    print_summary(report)
    if report_path:
        print(f"Report: {report_path}")
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
