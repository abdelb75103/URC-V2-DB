#!/usr/bin/env python3
"""Reproduce V5 exposure and emit the reviewed explicit-context successor evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW_START = date(2024, 9, 1)
WINDOW_END = date(2025, 6, 30)
EXPECTED_V5_ROWS = 64_511
EXPECTED_V5_HOURS = Decimal("81352.919497")
EXPECTED_EXCLUDED_ROWS = 1_238
EXPECTED_EXCLUDED_HOURS = Decimal("1444.576389")

SOURCE_HASHES = {
    "benetton": "60b2263beb4bc12ad9ed4990cfb6fdb908ed90190eeed29a6a6b7e4df2eb694e",
    "bulls": "75a04f73bb169fce594789fb7d975727c254eceb4158ecaa0db9e1b3b5f811d0",
    "cardiff": "9c24c5a223f7d4bc31914c709a22621965057c645e0993036c624c99c1d24e86",
    "connacht": "7db203843198afd4fa90fb4ab59716bf9d6e5a4c94043326823f8306f848aa84",
    "dragons": "dc88dc7416a9f2dcdc46575132c89f2393fb26e891e09c37084e8e0dc8a5e92e",
    "edinburgh": "f2dae263947036980ec64a42e47467a872b9f4d8c946c3a7fe31f1a8f90f5cd0",
    "glasgow": "1a7d31c7bdcce84846817bf4eb62c74bea1f8bb9b1e65410d5fdf270a0ea74fb",
    "leinster": "b15de4026e70a1cd5de75eb08161d30fcf9854fcd4e9bb07fd257e1c454f8a9f",
    "lions": "3667c5af1e3c237bf49289bc9f97cb6a710820a37b2dfa26c53cca851d551967",
    "munster": "c8a09d4dfc1a14cb469c5929a563af3fd5f61f5700578478fe1553268084adc1",
    "ospreys": "83ee7c20d90bfbe12f643ee1e95fa8d9cb631eea5133463455f65efb082eb7fa",
    "scarlets": "a457a26a79f7490f57fffba28ceb26e461fefd669515b7be2c914fdf4b17cd71",
    "sharks": "4c9c7aed6b6006d385b7ce4dc2031787d7c5b987fb6ca1d5c0dfd12abef9f669",
    "stormers": "c1ddb4fcc9a6aa16e29bbe720af16ebf7a696d91830bac1e7f1b52105fe2b169",
    "ulster": "447d290f6caec3f2d7928f32151434020bd8c42b69557482516248d99961677e",
    "zebre": "522e97f0785c355f3f563b28533a3af382dc8cc3b9cd9c5baceec6d44af4d66c",
}

EXPECTED_BY_TEAM = {
    "cardiff": (341, Decimal("363.778333")),
    "dragons": (91, Decimal("96.833333")),
    "edinburgh": (391, Decimal("524.938611")),
    "glasgow": (40, Decimal("60.797778")),
    "ospreys": (235, Decimal("254.391667")),
    "scarlets": (140, Decimal("143.836667")),
}


def parse_date(value: str) -> date | None:
    value = value.strip()
    if not value:
        return None
    for pattern in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(value[:10], pattern).date()
        except ValueError:
            pass
    raise ValueError(f"unrecognised cleaned date {value!r}")


def decimal(value: str) -> Decimal:
    return Decimal(value.strip() or "0")


def source_scope_text(row: dict[str, str]) -> str:
    fields = (
        "Competition", "session type", "Session Type", "Training Type",
        "Training With", "If match, surface?", "Description", "Notes",
    )
    return " ".join(row.get(field, "").strip() for field in fields if row.get(field, "").strip()).lower()


def is_definite_pre_urc_match(team: str, period_start: date, text: str) -> bool:
    token = r"(^|[^a-z0-9])(friendly|fixture|opposition|opponent|vs|versus|currie[ -]*cup)([^a-z0-9]|$)"
    match = re.search(r"(^|[^a-z0-9])match([^a-z0-9]|$)", text)
    excluded_match_context = re.search(r"(warm[ -]*up|top[ -]*up|captain.?s[ -]*run|game[ ]*[0-9]+)", text)
    named_game = re.search(r"(^|[^a-z0-9])game[ ]*\([^)]*[a-z][^)]*\)", text)
    return bool(re.search(token, text) or (match and not excluded_match_context) or named_game or (team == "sharks" and period_start in {date(2024, 9, 8), date(2024, 9, 14)}))


def in_v5(team: str, row: dict[str, str]) -> bool:
    start = parse_date(row.get("session_date_clean", "") or row.get("week_start_date", ""))
    if start is None:
        return False
    grain = row.get("exposure_grain", "session").strip()
    end = start + timedelta(days=6 if grain == "weekly" else 0)
    if start > WINDOW_END or end < WINDOW_START:
        return False
    reasons = [part for part in row.get("exclusion_reason", "").split(";") if part]
    included = row.get("cleaning_action", "").strip() == "include"
    sole_window = reasons == ["outside_official_analysis_window"]
    if not included and not sole_window:
        return False
    overlaps_pre_urc = start <= date(2024, 9, 19) and end >= WINDOW_START
    return not (sole_window and overlaps_pre_urc and is_definite_pre_urc_match(team, start, source_scope_text(row)))


def successor_reason(team: str, row: dict[str, str]) -> str | None:
    competition = row.get("Competition", "").strip()
    session_type = row.get("session type", "").strip()
    if team == "cardiff" and competition == "Age Grade":
        return "academy_or_age_grade"
    if team == "edinburgh" and session_type in {"Academy Training", "Academy Units", "Academy Units & Training"}:
        return "academy_or_age_grade"
    if team == "glasgow" and row.get("Training With", "").strip() == "Scottish Prem":
        return "other_named_non_cohort"
    match_competitions = {
        "cardiff": {"Europe Challenge Cup", "Pro 14", "SRC"},
        "dragons": {"Europe Challenge Cup"},
        "ospreys": {"Europe Challenge Cup", "Friendly"},
        "scarlets": {"Europe Challenge Cup", "Friendly"},
    }
    if team == "ospreys" and session_type == "SRC Match":
        return "explicit_non_urc_match"
    if session_type == "Match" and competition in match_competitions.get(team, set()):
        return "explicit_non_urc_match"
    return None


def canonical_sha(rows: list[str]) -> str:
    return hashlib.sha256(("\n".join(sorted(rows)) + "\n").encode()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/evidence/urc_2024-25_exposure_scope_successor_2026-08-30.json")
    args = parser.parse_args()

    v5_rows: list[tuple[str, dict[str, str]]] = []
    decisions: list[tuple[str, dict[str, str], str]] = []
    files: dict[str, dict[str, str]] = {}
    for team, expected_sha in SOURCE_HASHES.items():
        path = next((args.input_root / team).glob("*_exposure_cleaned_2024-25.csv"))
        actual_sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual_sha != expected_sha:
            raise SystemExit(f"{team} source SHA-256 drift: {actual_sha}")
        files[team] = {"sha256": actual_sha, "path": f"data/intake/2024-25/{team}/{path.name}"}
        with path.open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                if not in_v5(team, row):
                    continue
                v5_rows.append((team, row))
                reason = successor_reason(team, row)
                if reason:
                    decisions.append((team, row, reason))

    v5_hours = sum((decimal(row["minutes_total_clean"]) for _, row in v5_rows), Decimal()) / 60
    excluded_hours = sum((decimal(row["minutes_total_clean"]) for _, row, _ in decisions), Decimal()) / 60
    if len(v5_rows) != EXPECTED_V5_ROWS or v5_hours.quantize(Decimal(".000001")) != EXPECTED_V5_HOURS:
        raise SystemExit(f"V5 replay drift: rows={len(v5_rows)} hours={v5_hours}")
    if len(decisions) != EXPECTED_EXCLUDED_ROWS or excluded_hours.quantize(Decimal(".000001")) != EXPECTED_EXCLUDED_HOURS:
        raise SystemExit(f"successor drift: rows={len(decisions)} hours={excluded_hours}")

    by_team: dict[str, dict[str, Decimal | int]] = defaultdict(lambda: {"rows": 0, "hours": Decimal()})
    by_reason: dict[str, dict[str, Decimal | int]] = defaultdict(lambda: {"rows": 0, "hours": Decimal()})
    decision_keys: list[str] = []
    for team, row, reason in decisions:
        hours = decimal(row["minutes_total_clean"]) / 60
        by_team[team]["rows"] = int(by_team[team]["rows"]) + 1
        by_team[team]["hours"] = Decimal(by_team[team]["hours"]) + hours
        by_reason[reason]["rows"] = int(by_reason[reason]["rows"]) + 1
        by_reason[reason]["hours"] = Decimal(by_reason[reason]["hours"]) + hours
        decision_keys.append("|".join((team, row["source_row_sha256"], reason)))
    for team, (rows, hours) in EXPECTED_BY_TEAM.items():
        actual = by_team[team]
        if int(actual["rows"]) != rows or Decimal(actual["hours"]).quantize(Decimal(".000001")) != hours:
            raise SystemExit(f"{team} reconciliation drift: {actual}")

    retained_keys = [f"{team}|{row['source_row_sha256']}" for team, row in v5_rows if successor_reason(team, row) is None]
    payload = {
        "evidence_version": "exposure_scope_2024-25_2026-08-30_v1",
        "predecessor": {
            "cohort_view_version": "analysis_window_2024-25_2026-07-25_v1",
            "release_id": "20f2b6ed-d3d3-4349-88b9-fc5c9f143eed",
            "bundle_sha256": "0445139ad3a36236eeb047b9f94a3188f55906b2dd76624585111030d3143288",
        },
        "source_files": files,
        "v5_replay": {"rows": len(v5_rows), "hours": format(v5_hours.quantize(Decimal(".000001")), "f")},
        "successor": {
            "cohort_view_version": "analysis_window_2024-25_2026-08-30_v2",
            "included_rows": len(v5_rows) - len(decisions),
            "included_hours": format((v5_hours - excluded_hours).quantize(Decimal(".000001")), "f"),
            "excluded_rows": len(decisions),
            "excluded_hours": format(excluded_hours.quantize(Decimal(".000001")), "f"),
            "decision_rowset_sha256": canonical_sha(decision_keys),
            "retained_rowset_sha256": canonical_sha(retained_keys),
            "excluded_by_team": {team: {"rows": int(value["rows"]), "hours": format(Decimal(value["hours"]).quantize(Decimal(".000001")), "f")} for team, value in sorted(by_team.items())},
            "excluded_by_reason": {reason: {"rows": int(value["rows"]), "hours": format(Decimal(value["hours"]).quantize(Decimal(".000001")), "f")} for reason, value in sorted(by_reason.items())},
        },
        "rule": "Exclude only source rows with exact reviewed academy, age-grade, named non-cohort or explicit non-URC match context. Preserve source and curated rows.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload["successor"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
