#!/usr/bin/env python3
"""Build an ignored, aggregate-only exposure preview for Abdel's private review."""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


SEASON_START = datetime(2024, 7, 1)
SEASON_END = datetime(2025, 6, 30)
HSR_FIELD = "high speed running distance"


def number(value: str | None) -> float | None:
    text = (value or "").strip().replace(",", "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def row_date(row: dict[str, str]) -> datetime | None:
    value = (row.get("session_date_clean") or row.get("cleaned_date") or row.get("week_start_date") or "").strip()
    if not value:
        return None
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(value[:19], fmt)
        except ValueError:
            continue
    return None


def load_aliases(env_file: Path) -> dict[str, str]:
    for line in env_file.read_text(encoding="utf-8").splitlines():
        if not line.startswith("TEAM_DISPLAY_ALIAS_JSON="):
            continue
        raw = line.split("=", 1)[1].strip()
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "'\"":
            raw = raw[1:-1]
        aliases = json.loads(raw)
        if not isinstance(aliases, dict):
            break
        return {str(key): str(value) for key, value in aliases.items()}
    raise SystemExit("TEAM_DISPLAY_ALIAS_JSON is missing or invalid")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-root", type=Path, default=Path("data/intake/2024-25"))
    parser.add_argument("--env-file", type=Path, default=Path(".env.local"))
    parser.add_argument("--fixtures", type=Path, default=Path("data/intake/2024-25/fixtures/urc_fixtures_2024_25.corrected.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/reporting/exposure_review_preview_2024-25.json"))
    args = parser.parse_args()

    aliases = load_aliases(args.env_file)
    monthly: dict[str, dict[str, object]] = defaultdict(lambda: {
        "additional_hours": 0.0,
        "additional_distance_km": 0.0,
        "hsr_distance_km": 0.0,
        "hsr_distance_denominator_km": 0.0,
        "hsr_reporting_teams": set(),
        "match_hours": 0.0,
    })
    teams: dict[str, dict[str, float | None]] = defaultdict(lambda: {
        "additional_hours": 0.0,
        "additional_distance_km": 0.0,
        "hsr_distance_km": None,
        "hsr_distance_denominator_km": 0.0,
    })
    for alias in aliases.values():
        teams[alias]
    source_files: list[str] = []

    for path in sorted(args.input_root.glob("*/*_exposure_cleaned_2024-25.csv")):
        team_key = path.parent.name
        alias = aliases.get(team_key)
        if not alias:
            raise SystemExit(f"missing protected display alias for {team_key}")
        source_files.append(str(path))
        with path.open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                date = row_date(row)
                if date is None or date < SEASON_START or date > SEASON_END:
                    continue
                action = (row.get("cleaning_action") or "").strip()
                reason = (row.get("exclusion_reason") or "").strip()
                if "exact_duplicate_copy" in {token.strip() for token in reason.split(";")}:
                    continue

                minutes = number(row.get("minutes_total_clean")) or 0.0
                distance_m = number(row.get("distance_total_m_clean")) or 0.0

                month = date.strftime("%b %Y")
                hsr_m = number(row.get(HSR_FIELD))
                if hsr_m is not None:
                    monthly[month]["hsr_distance_km"] = float(monthly[month]["hsr_distance_km"]) + hsr_m / 1000
                    monthly[month]["hsr_distance_denominator_km"] = float(monthly[month]["hsr_distance_denominator_km"]) + distance_m / 1000
                    cast_teams = monthly[month]["hsr_reporting_teams"]
                    assert isinstance(cast_teams, set)
                    cast_teams.add(alias)
                    teams[alias]["hsr_distance_km"] = float(teams[alias]["hsr_distance_km"] or 0.0) + hsr_m / 1000
                    teams[alias]["hsr_distance_denominator_km"] = float(teams[alias]["hsr_distance_denominator_km"] or 0.0) + distance_m / 1000

                if action == "include":
                    continue
                monthly[month]["additional_hours"] = float(monthly[month]["additional_hours"]) + minutes / 60
                monthly[month]["additional_distance_km"] = float(monthly[month]["additional_distance_km"]) + distance_m / 1000
                teams[alias]["additional_hours"] += minutes / 60
                teams[alias]["additional_distance_km"] += distance_m / 1000

    with args.fixtures.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            date = row_date({"cleaned_date": row.get("corrected_date") or row.get("source_date") or row.get("date") or ""})
            if date is None or date < SEASON_START or date > SEASON_END:
                continue
            match_hours = number(row.get("match_hours_per_team")) or 0.0
            monthly[date.strftime("%b %Y")]["match_hours"] = float(monthly[date.strftime("%b %Y")]["match_hours"]) + match_hours * 2

    month_order = {datetime(2024 + (index + 6) // 12, (index + 6) % 12 + 1, 1).strftime("%b %Y"): index for index in range(12)}
    monthly_rows = []
    for month, values in sorted(monthly.items(), key=lambda item: month_order[item[0]]):
        reporting_teams = values.pop("hsr_reporting_teams")
        assert isinstance(reporting_teams, set)
        monthly_rows.append({
            "month": month,
            "additional_hours": round(float(values["additional_hours"]), 6),
            "additional_distance_km": round(float(values["additional_distance_km"]), 6),
            "hsr_distance_km": round(float(values["hsr_distance_km"]), 6),
            "hsr_distance_denominator_km": round(float(values["hsr_distance_denominator_km"]), 6),
            "hsr_reporting_teams": len(reporting_teams),
            "match_hours": round(float(values["match_hours"]), 6),
        })

    team_rows = [
        {
            "team_alias": alias,
            "additional_hours": round(float(values["additional_hours"]), 6),
            "additional_distance_km": round(float(values["additional_distance_km"]), 6),
            "hsr_distance_km": round(float(values["hsr_distance_km"]), 6) if values["hsr_distance_km"] is not None else None,
            "hsr_distance_denominator_km": round(float(values["hsr_distance_denominator_km"]), 6),
        }
        for alias, values in sorted(teams.items())
    ]
    payload = {
        "status": "private_review_override",
        "season": "2024-25",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "all cleaned exposure rows inside the private July-to-June review window plus the retained corrected fixture list",
        "hsr_field": HSR_FIELD,
        "source_file_count": len(source_files),
        "monthly": monthly_rows,
        "teams": team_rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.output),
        "source_files": len(source_files),
        "months": len(monthly_rows),
        "teams_with_hsr": sum((row["hsr_distance_km"] or 0) > 0 for row in team_rows),
    }))


if __name__ == "__main__":
    main()
