"""Deterministic preparation of the official URC 2025-26 fixture response.

The official response is retained outside the repository.  This module emits
only the narrow, public fixture CSV required by ``load-curated-fixtures`` and
never emits the response's event, score, venue, or team-ID fields.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any

try:  # Supports both ``python -m pipeline.fixture_preparation`` and direct use.
    from pipeline.season_contracts import validate_fixture_rows
except ModuleNotFoundError:  # pragma: no cover - exercised by the direct CLI
    from season_contracts import validate_fixture_rows


SEASON = "2025-26"
OFFICIAL_URC_2025_26_RESPONSE_SHA256 = "411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6"
OUTPUT_FIELDS = (
    "season",
    "match_id",
    "stage",
    "round",
    "source_date",
    "corrected_date",
    "date_status",
    "home_team",
    "away_team",
    "source_file_sha256",
    "source_row_number",
    "source_locator",
    "source_request_sha256",
    "source_response_sha256",
    "retrieved_at",
)
STAGES = {
    **{round_value: "Regular season" for round_value in range(1, 19)},
    19: "Quarter-final",
    20: "Semi-final",
    21: "Final",
}
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
EXPECTED_STAGE_COUNTS = {
    "Regular season": 144,
    "Quarter-final": 4,
    "Semi-final": 2,
    "Final": 1,
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _text(value: object) -> str:
    return str(value).strip() if value is not None else ""


def _date(value: object, locator: str) -> str:
    text = _text(value)
    try:
        return datetime.strptime(text, "%Y-%m-%d %H:%M:%S").date().isoformat()
    except ValueError as error:
        raise ValueError(f"unparseable match datetime at {locator}: {text!r}") from error


def _row(
    match: dict[str, Any], index: int, source_sha256: str, *, source_url: str,
    source_request_sha256: str, retrieved_at: str,
) -> dict[str, str]:
    locator = f"{source_url}#data.matchstats[{index}]"
    stats = match.get("stats_data")
    if not isinstance(stats, dict):
        raise ValueError(f"missing stats_data at {locator}")
    match_id = _text(match.get("match_id"))
    stats_match_id = _text(stats.get("id"))
    if not match_id or match_id != stats_match_id:
        raise ValueError(f"missing or inconsistent match ID at {locator}")
    round_value = stats.get("round")
    if not isinstance(round_value, int) or round_value not in STAGES:
        raise ValueError(f"unexpected round at {locator}: {round_value!r}")
    season_id = stats.get("season", {}).get("id") if isinstance(stats.get("season"), dict) else None
    if season_id != 202501:
        raise ValueError(f"unexpected official season ID at {locator}: {season_id!r}")
    home = stats.get("homeTeam", {}).get("team", {}) if isinstance(stats.get("homeTeam"), dict) else {}
    away = stats.get("awayTeam", {}).get("team", {}) if isinstance(stats.get("awayTeam"), dict) else {}
    home_name = _text(home.get("name") if isinstance(home, dict) else "")
    away_name = _text(away.get("name") if isinstance(away, dict) else "")
    if not home_name or not away_name:
        raise ValueError(f"missing opponent at {locator}")
    if home_name.casefold() == away_name.casefold():
        raise ValueError(f"self-match at {locator}: {home_name!r}")
    source_date = _date(match.get("match_datetime"), locator)
    return {
        "season": SEASON,
        "match_id": match_id,
        "stage": STAGES[round_value],
        "round": str(round_value),
        "source_date": source_date,
        "corrected_date": source_date,
        "date_status": "source_confirmed",
        "home_team": home_name,
        "away_team": away_name,
        "source_file_sha256": source_sha256,
        "source_row_number": str(index + 2),
        "source_locator": locator,
        "source_request_sha256": source_request_sha256,
        "source_response_sha256": source_sha256,
        "retrieved_at": retrieved_at,
    }


def _validate(rows: list[dict[str, str]]) -> None:
    validate_fixture_rows(SEASON, rows)


def _validate_provenance(
    *, source_url: str, source_request_sha256: str, retrieved_at: str,
) -> tuple[str, str, str]:
    source_url = _text(source_url)
    source_request_sha256 = _text(source_request_sha256).lower()
    retrieved_at = _text(retrieved_at)
    if not source_url.startswith("https://"):
        raise ValueError("fixture source URL must use https")
    if not re.fullmatch(r"[0-9a-f]{64}", source_request_sha256):
        raise ValueError("fixture source request checksum must be a SHA-256 hex digest")
    try:
        parsed = datetime.fromisoformat(retrieved_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("fixture retrieval timestamp must be ISO-8601") from error
    if parsed.tzinfo is None:
        raise ValueError("fixture retrieval timestamp must include a timezone")
    return source_url.rstrip("/"), source_request_sha256, retrieved_at


def prepare_urc_2025_26_fixtures(
    source: Path, output: Path, *, expected_source_sha256: str | None = None,
    source_url: str, source_request_sha256: str, retrieved_at: str,
) -> dict[str, object]:
    """Validate an official response and write its public loader-contract CSV."""
    resolved_output = output.resolve()
    if resolved_output.is_relative_to(REPOSITORY_ROOT):
        raise ValueError("prepared fixture output must remain outside the repository")
    source_url, source_request_sha256, retrieved_at = _validate_provenance(
        source_url=source_url,
        source_request_sha256=source_request_sha256,
        retrieved_at=retrieved_at,
    )
    source_sha256 = sha256_file(source)
    if expected_source_sha256 and source_sha256 != expected_source_sha256:
        raise ValueError(
            f"official fixture response checksum mismatch: expected {expected_source_sha256}, got {source_sha256}"
        )
    try:
        payload = json.loads(source.read_text(encoding="utf-8"))
        matches = payload["data"]["matchstats"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise ValueError(f"invalid official fixture response: {source}") from error
    if not isinstance(matches, list):
        raise ValueError("official fixture response matchstats must be an array")
    rows = [
        _row(
            match,
            index,
            source_sha256,
            source_url=source_url,
            source_request_sha256=source_request_sha256,
            retrieved_at=retrieved_at,
        )
        for index, match in enumerate(matches)
        if isinstance(match, dict)
    ]
    if len(rows) != len(matches):
        raise ValueError("official fixture response contains a non-object fixture")
    _validate(rows)
    resolved_output.parent.mkdir(parents=True, exist_ok=True)
    with resolved_output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return {
        "season": SEASON,
        "source_sha256": source_sha256,
        "fixture_count": len(rows),
        "stage_counts": dict(Counter(row["stage"] for row in rows)),
        "team_count": len({row[side] for row in rows for side in ("home_team", "away_team")}),
        "regular_matches_per_team": 18,
        "output_sha256": sha256_file(resolved_output),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare official URC 2025-26 fixtures for the curated loader")
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-source-sha256", default=OFFICIAL_URC_2025_26_RESPONSE_SHA256)
    parser.add_argument("--source-url", default="https://www.unitedrugby.com/graphql")
    parser.add_argument("--source-request-sha256", required=True)
    parser.add_argument("--retrieved-at", required=True)
    args = parser.parse_args()
    print(json.dumps(prepare_urc_2025_26_fixtures(
        args.source,
        args.output,
        expected_source_sha256=args.expected_source_sha256,
        source_url=args.source_url,
        source_request_sha256=args.source_request_sha256,
        retrieved_at=args.retrieved_at,
    ), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
