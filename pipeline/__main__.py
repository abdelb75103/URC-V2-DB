from __future__ import annotations

import argparse
import contextlib
import csv
import hashlib
import io
import json
import os
import shutil
import subprocess
import tempfile
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any


LOCATOR_FIELDS = [
    "source_archive_path",
    "source_file_sha256",
    "source_sheet",
    "source_row_number",
    "standardised_file_sha256",
    "standardised_row_number",
    "source_locator_status",
]

UID_FIELDS = ["player_uid", "injury_uid"]

EXPOSURE_LOCATOR_FIELDS = [
    "source_archive_path",
    "source_file_sha256",
    "source_sheet",
    "source_row_number",
    "source_row_sha256",
    "standardised_file_sha256",
    "standardised_row_number",
    "source_locator_status",
]

EXPOSURE_WEEKLY_TEAM_ALIASES = ["Team I", "Team J", "Team K", "Team L"]

# The team-name to league-alias map is protected research metadata. It lives in a
# Git-ignored local file (backed up in UCD-managed storage), never in code or Git.
TEAM_ALIAS_MAP_PATH = Path(__file__).resolve().parent.parent / "data" / "intake" / "team_alias_map.json"
TEAM_ALIAS_CODEBOOK_PATH = Path("/Users/abdelbabiker/Desktop/URC/codebook- Teams URC.csv")


def load_fixture_team_aliases() -> dict[str, str]:
    if not TEAM_ALIAS_MAP_PATH.exists():
        raise SystemExit(
            f"protected team alias map not found: {TEAM_ALIAS_MAP_PATH}; "
            "restore it from UCD-managed storage (it is intentionally excluded from Git)"
        )
    data = json.loads(TEAM_ALIAS_MAP_PATH.read_text())
    aliases = data.get("fixture_team_aliases")
    if not isinstance(aliases, dict) or not aliases:
        raise SystemExit(
            f"invalid team alias map (expected non-empty 'fixture_team_aliases' object): {TEAM_ALIAS_MAP_PATH}"
        )
    return {str(name): str(alias) for name, alias in aliases.items()}

FIXTURE_DATE_CORRECTIONS = {
    "DHL Stormers v Vodacom Bulls": "2025-02-08",
    "Hollywoodbets Sharks v Emirates Lions": "2025-03-08",
    "Glasgow Warriors v Edinburgh Rugby": "2024-12-22",
    "Leinster v Connacht": "2024-12-21",
    "Ospreys v Scarlets": "2024-12-21",
    "Ulster v Munster": "2024-12-20",
    "Connacht v Ulster": "2024-12-28",
    "Munster v Leinster": "2024-12-27",
    "Vodacom Bulls v Emirates Lions": "2025-02-22",
    "Glasgow Warriors v Connacht": "2025-01-26",
    "Dragons RFC v Glasgow Warriors": "2025-02-16",
    "Zebre Parma v Edinburgh Rugby": "2025-04-25",
}

DUPLICATE_SIGNATURE_FIELDS = [
    "PlayerID",
    "Date Injured",
    "Body Part",
    "Orchard Code",
    "Side",
    "Description",
    "Nature of onset",
]

MISSING_VALUES = {"", "na", "n/a", "null", "none", "unknown", "unspecified/crossing"}

BODY_LOCATION_MAP = {
    "ankle": "ankle",
    "buttock/pelvis": "lumbosacral",
    "chest": "chest",
    "elbow": "elbow",
    "foot": "foot",
    "head": "head",
    "hip/groin": "hip_groin",
    "knee": "knee",
    "lower leg": "lower_leg",
    "lumbar spine": "lumbosacral",
    "neck": "neck",
    "shoulder": "shoulder",
    "thigh": "thigh",
    "thoracic spine": "thoracic_spine",
    "trunk/abdominal": "abdomen",
    "wrist/hand": "unspecified",
}

INJURY_TYPE_MAP = {
    "bruising/ haematoma": "contusion_superficial",
    "concussion/ brain injury": "brain_spinal_cord_injury",
    "disc": "nonspecific",
    "dislocation": "joint_sprain",
    "fracture": "fracture",
    "instability": "chronic_instability",
    "laceration/ abrasion": "laceration",
    "ligament": "joint_sprain",
    "muscle strain/spasm": "muscle_injury",
    "nerve": "peripheral_nerve_injury",
    "organ damage": "internal_organ_trauma",
    "osteoarthritis": "arthritis",
    "osteochondral": "cartilage_injury",
    "other pain/ unspecified": "nonspecific",
    "post surgery": "nonspecific",
    "synovitis/ impingement/ bursitis": "synovitis_capsulitis",
    "tendon": "tendinopathy",
    "unspecified/crossing": "nonspecific",
}

ORCHARD_PATHOLOGY_TYPE_MAP = {
    "M": "muscle_injury",
    "T": "tendinopathy",
    "F": "fracture",
    "J": "joint_sprain",
    "N": "peripheral_nerve_injury",
    "H": "contusion_superficial",
    "K": "laceration",
    "O": "internal_organ_trauma",
    "G": "synovitis_capsulitis",
    "A": "arthritis",
    "U": "chronic_instability",
    "D": "joint_sprain",
}

IOC_BODY_CODE_MAP = {
    "H": "head",
    "N": "neck",
    "S": "shoulder",
    "U": "upper_arm",
    "E": "elbow",
    "R": "forearm",
    "W": "wrist",
    "P": "hand",
    "C": "chest",
    "D": "thoracic_spine",
    "L": "lumbosacral",
    "O": "abdomen",
    "G": "hip_groin",
    "T": "thigh",
    "K": "knee",
    "Q": "lower_leg",
    "A": "ankle",
    "F": "foot",
    "Z": "unspecified",
    "X": "multiple",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class SqlParams:
    # Multi-statement SQL batches read values from a transaction-local table
    # because pg bind parameters apply to a single prepared statement.
    def __init__(self) -> None:
        self.values: list[object] = []

    def add(self, value: object) -> int:
        self.values.append(value)
        return len(self.values)

    def text(self, value: object) -> str:
        return f"(select value #>> '{{}}' from _pipeline_params where idx = {self.add(value)})"

    def jsonb(self, value: object) -> str:
        return f"(select value from _pipeline_params where idx = {self.add(value)})"


def run_sql(sql: str, params: list[object] | None = None) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as handle:
        handle.write(sql)
        sql_path = handle.name
    params_path = None
    if params is not None:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(params, handle, sort_keys=True)
            params_path = handle.name

    try:
        db_url = os.environ.get("SUPABASE_DB_URL")
        if not db_url:
            raise SystemExit("SUPABASE_DB_URL is required; load .env.local before DB writes")
        command = ["node", str(Path(__file__).with_name("sql_exec.mjs")), sql_path]
        if params_path:
            command.append(params_path)
        subprocess.run(command, check=True)
    finally:
        Path(sql_path).unlink(missing_ok=True)
        if params_path:
            Path(params_path).unlink(missing_ok=True)


def read_rows(path: Path) -> list[dict[str, str]]:
    if path.suffix.lower() != ".csv":
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def validate_alias_map(args: argparse.Namespace) -> None:
    alias_map = load_fixture_team_aliases()
    codebook_path = Path(args.codebook)
    codebook_rows = read_rows(codebook_path)
    if not codebook_rows:
        raise SystemExit(f"no team codebook rows found: {codebook_path}")
    missing_columns = [column for column in ["original_id", "new_id"] if column not in codebook_rows[0]]
    if missing_columns:
        raise SystemExit(f"team codebook missing column(s): {', '.join(missing_columns)}")

    codebook_aliases = {clean_text(row.get("new_id")) for row in codebook_rows if clean_text(row.get("new_id"))}
    local_aliases = {clean_text(alias) for alias in alias_map.values() if clean_text(alias)}
    missing_aliases = sorted(local_aliases - codebook_aliases)
    if missing_aliases:
        raise SystemExit(
            f"alias map uses {len(missing_aliases)} codebook alias code(s) absent from {codebook_path.name}"
        )

    print(
        json.dumps(
            {
                "alias_map": str(TEAM_ALIAS_MAP_PATH),
                "alias_map_sha256": sha256_file(TEAM_ALIAS_MAP_PATH),
                "codebook": str(codebook_path),
                "codebook_sha256": sha256_file(codebook_path),
                "fixture_names": len(alias_map),
                "fixture_alias_codes": len(local_aliases),
                "codebook_alias_codes": len(codebook_aliases),
                "status": "valid",
            },
            indent=2,
        )
    )


def stable_uid(prefix: str, *parts: object) -> str:
    text = "\x1f".join(str(part) for part in parts)
    return f"{prefix}_{hashlib.sha256(text.encode()).hexdigest()[:24]}"


def raw_record_id(team: str, season: str, file_hash: str, source_row_number: int) -> str:
    return f"{team}:{season}:{file_hash[:12]}:{source_row_number}"


def parse_uk_date(value: str) -> datetime | None:
    value = value.strip()
    if not value:
        return None
    for fmt in ("%d/%m/%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    return None


def parse_flexible_date(value: object) -> datetime | None:
    if isinstance(value, datetime):
        return value
    text = clean_text(str(value) if value is not None else "")
    if not text:
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%d/%m/%Y", "%d/%m/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            pass
    return None


def parse_int(value: str) -> int | None:
    value = value.strip()
    if not value:
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def parse_float(value: object) -> float | None:
    text = clean_text(str(value) if value is not None else "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def clean_text(value: str | None) -> str:
    return (value or "").strip()


def clean_cell(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.date().isoformat()
    return str(value).strip()


def is_missing(value: str | None) -> bool:
    return clean_text(value).lower() in MISSING_VALUES


def activity_context(row: dict[str, str]) -> tuple[str, str]:
    occasion = clean_text(row.get("Occasion category")).lower()
    match_type = clean_text(row.get("Match Type")).lower()
    if occasion in {"game", "match"} and match_type in {"united rugby championship", "urc"}:
        return "urc_match", "mapped_from_occasion_and_match_type"
    if occasion == "training" or match_type == "training":
        return "training", "mapped_from_occasion_category"
    return "unknown", "insufficient_direct_evidence"


def contact_context(row: dict[str, str]) -> tuple[str, str]:
    value = clean_text(row.get("Is Contact")).lower()
    if value == "contact":
        return "contact", "mapped_from_is_contact"
    if value == "non-contact":
        return "non_contact", "mapped_from_is_contact"
    tissue = clean_text(row.get("Injury Tissue Type/s")).lower()
    onset = clean_text(row.get("Nature of onset")).lower()
    if is_missing(value) and tissue == "muscle strain/spasm" and onset == "acute":
        return "non_contact", "inferred_from_acute_muscle_strain"
    return "unknown", "source_missing_or_unknown"


def recurrence_status(row: dict[str, str]) -> tuple[str, str]:
    value = clean_text(row.get("Recurrence")).lower()
    if value == "first episode":
        return "first_episode", "mapped_from_recurrence"
    if value == "recurrence":
        return "recurrence", "mapped_from_recurrence"
    return "unknown", "source_missing_or_unknown"


def severity_category(days_injured: int | None, is_closed: bool | None) -> tuple[str, str]:
    if days_injured is None or is_closed is False:
        return "unknown_or_censored", "missing_days_or_unclosed_injury"
    if days_injured == 0:
        return "zero_days_medical_attention_only", "derived_from_days_injured"
    if days_injured == 1:
        return "one_day", "derived_from_days_injured"
    if 2 <= days_injured <= 3:
        return "two_to_three_days", "derived_from_days_injured"
    if 4 <= days_injured <= 7:
        return "four_to_seven_days", "derived_from_days_injured"
    if 8 <= days_injured <= 28:
        return "eight_to_twenty_eight_days", "derived_from_days_injured"
    return "greater_than_twenty_eight_days", "derived_from_days_injured"


def injury_closed(row: dict[str, str]) -> tuple[bool | None, str]:
    value = clean_text(row.get("is_injury_closed"))
    if value == "1":
        return True, "mapped_from_is_injury_closed"
    if value == "0":
        return False, "mapped_from_is_injury_closed"
    return None, "source_missing_or_unknown"


def body_location(row: dict[str, str]) -> tuple[str, str]:
    orchard_code = clean_text(row.get("Orchard Code"))
    if orchard_code:
        mapped_from_code = IOC_BODY_CODE_MAP.get(orchard_code[0].upper())
        if mapped_from_code:
            return mapped_from_code, "mapped_from_orchard_code_ioc_body_area"
    source = clean_text(row.get("Body Part"))
    controlled = BODY_LOCATION_LABEL_TO_KEY.get(source.lower())
    if controlled:
        return controlled, "preserved_controlled_body_part"
    mapped = BODY_LOCATION_MAP.get(source.lower())
    if mapped:
        return mapped, "mapped_from_body_part_ioc_body_area"
    evidence = " ".join(
        clean_text(row.get(field)).lower()
        for field in ["Description", "Orchard Code", "Injury Tissue Type/s"]
    )
    if "concussion" in evidence or "brain injury" in evidence:
        return "head", "inferred_from_concussion_evidence"
    return "unknown", "source_missing_or_unknown"


def problem_type(row: dict[str, str]) -> tuple[str, str]:
    if not is_missing(row.get("Orchard Code")) or not is_missing(row.get("Injury Tissue Type/s")):
        return "injury", "inferred_from_orchard_code_or_injury_type"
    if not is_missing(row.get("Illness Code")):
        return "illness", "inferred_from_illness_code"
    return "unknown", "source_missing_or_unknown"


def injury_type(row: dict[str, str]) -> tuple[str, str]:
    value = clean_text(row.get("Injury Tissue Type/s")).lower()
    controlled = INJURY_TYPE_LABEL_TO_KEY.get(value)
    if controlled:
        return controlled, "preserved_controlled_injury_tissue_type"
    orchard_code = clean_text(row.get("Orchard Code")).upper()
    if value in {"", "na", "n/a", "unknown", "other pain/ unspecified", "unspecified/crossing"} and len(orchard_code) >= 2:
        mapped_from_code = ORCHARD_PATHOLOGY_TYPE_MAP.get(orchard_code[1])
        if mapped_from_code:
            return mapped_from_code, "mapped_from_orchard_code_ioc_pathology"
    mapped = INJURY_TYPE_MAP.get(value)
    if mapped:
        return mapped, "mapped_from_injury_tissue_type"
    return "unknown", "source_missing_or_unknown"


def prepare_intake(args: argparse.Namespace) -> None:
    standardised_path = Path(args.file)
    source_path = Path(args.source_file)
    output_path = Path(args.output)
    rows = read_rows(standardised_path)
    if source_path.suffix.lower() == ".xlsx":
        _, source_rows = read_xlsx_rows(source_path, args.source_sheet)
    else:
        source_rows = read_rows(source_path)
    if not rows:
        raise SystemExit(f"no standardised rows found: {standardised_path}")
    if args.player_id_column not in rows[0]:
        raise SystemExit(f"missing player ID column: {args.player_id_column}")
    if len(rows) != len(source_rows):
        raise SystemExit(
            f"row-count mismatch: standardised={len(rows)} source={len(source_rows)}"
        )

    original_hash = sha256_file(standardised_path)
    source_hash = sha256_file(source_path)
    prepared_rows = []
    for offset, row in enumerate(rows, start=2):
        prepared = dict(row)
        prepared.update(
            {
                "source_archive_path": str(source_path),
                "source_file_sha256": source_hash,
                "source_sheet": args.source_sheet,
                "source_row_number": str(offset),
                "standardised_file_sha256": original_hash,
                "standardised_row_number": str(offset),
                "source_locator_status": "provisional_reference_locator",
                "player_uid": stable_uid("ply", args.team, row[args.player_id_column]),
                "injury_uid": stable_uid("inj", args.team, args.season, original_hash, offset),
            }
        )
        prepared_rows.append(prepared)

    fieldnames = list(rows[0].keys()) + LOCATOR_FIELDS + UID_FIELDS
    write_rows(output_path, prepared_rows, fieldnames)

    output_hash = sha256_file(output_path)
    if args.manifest:
        manifest_path = Path(args.manifest)
        manifest = json.loads(manifest_path.read_text())
        manifest.update(
            {
                "locator_enriched_intake_file": str(output_path),
                "locator_enriched_file_sha256": output_hash,
                "locator_enriched_row_count": len(prepared_rows),
                "locator_fields": LOCATOR_FIELDS,
                "uid_fields": UID_FIELDS,
                "source_locator_status": "provisional_reference_locator",
            }
        )
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"prepared {output_path} sha256={output_hash} rows={len(prepared_rows)}")


def export_xlsx_sheet(args: argparse.Namespace) -> None:
    headers, rows = read_xlsx_rows(Path(args.file), args.sheet)
    output_path = Path(args.output)
    write_rows(
        output_path,
        [{header: clean_cell(row.get(header)) for header in headers if header} for row in rows],
        [header for header in headers if header],
    )
    print(
        json.dumps(
            {
                "exported": str(output_path),
                "rows": len(rows),
                "columns": len([header for header in headers if header]),
                "sha256": sha256_file(output_path),
            },
            indent=2,
        )
    )


def read_xlsx_rows(path: Path, sheet_name: str) -> tuple[list[str], list[dict[str, Any]]]:
    try:
        from openpyxl import load_workbook
    except ImportError as exc:
        raise SystemExit("openpyxl is required to read exposure workbooks") from exc

    workbook = load_workbook(path, read_only=True, data_only=True)
    if sheet_name not in workbook.sheetnames:
        raise SystemExit(f"sheet not found: {sheet_name}")
    worksheet = workbook[sheet_name]
    values = worksheet.iter_rows(values_only=True)
    try:
        headers = [clean_cell(value) for value in next(values)]
    except StopIteration as exc:
        raise SystemExit(f"empty workbook sheet: {sheet_name}") from exc

    rows: list[dict[str, Any]] = []
    for source_row_number, raw_values in enumerate(values, start=2):
        row = {
            header: raw_values[index] if index < len(raw_values) else None
            for index, header in enumerate(headers)
            if header
        }
        if any(clean_cell(value) for value in row.values()):
            row["_source_row_number"] = source_row_number
            rows.append(row)
    workbook.close()
    return headers, rows


def prepare_exposure(args: argparse.Namespace) -> None:
    workbook_path = Path(args.file)
    output_path = Path(args.output)
    qc_path = Path(args.qc_output)
    headers, rows = read_xlsx_rows(workbook_path, args.sheet)
    if not rows:
        raise SystemExit(f"no exposure rows found: {workbook_path}")
    if args.player_column not in headers:
        raise SystemExit(f"missing player column: {args.player_column}")

    source_hash = sha256_file(workbook_path)
    source_columns = list(headers)
    prepared_rows: list[dict[str, str]] = []
    dates: list[datetime] = []
    date_parse_failures: list[int] = []
    missing_player_rows: list[int] = []
    missing_date_rows: list[int] = []
    negative_minutes_rows: list[int] = []
    negative_distance_rows: list[int] = []
    exact_hashes: set[str] = set()
    exact_duplicate_rows = 0
    player_date_counts: dict[str, list[int]] = {}

    for output_row_number, row in enumerate(rows, start=2):
        source_row_number = int(row["_source_row_number"])
        source_payload = {
            header: clean_cell(row.get(header))
            for header in headers
            if header
        }
        source_row_hash = hashlib.sha256(
            json.dumps(source_payload, sort_keys=True).encode()
        ).hexdigest()
        if source_row_hash in exact_hashes:
            exact_duplicate_rows += 1
        exact_hashes.add(source_row_hash)

        player_value = clean_cell(row.get(args.player_column))
        if not player_value:
            missing_player_rows.append(source_row_number)
        player_uid = stable_uid("ply", args.team, player_value)

        parsed_date = parse_flexible_date(row.get(args.date_column))
        if parsed_date is None:
            missing_date_rows.append(source_row_number)
            if clean_cell(row.get(args.date_column)):
                date_parse_failures.append(source_row_number)
        else:
            dates.append(parsed_date)

        minutes = parse_float(row.get(args.minutes_column))
        distance = parse_float(row.get(args.distance_column))
        if minutes is not None and minutes < 0:
            negative_minutes_rows.append(source_row_number)
        if distance is not None and distance < 0:
            negative_distance_rows.append(source_row_number)

        if player_value and parsed_date:
            key = stable_uid("key", args.team, player_value, parsed_date.date().isoformat())
            player_date_counts.setdefault(key, []).append(source_row_number)

        prepared = {
            header: clean_cell(row.get(header))
            for header in source_columns
        }
        prepared.update(
            {
                "source_archive_path": str(workbook_path),
                "source_file_sha256": source_hash,
                "source_sheet": args.sheet,
                "source_row_number": str(source_row_number),
                "source_row_sha256": source_row_hash,
                "standardised_file_sha256": source_hash,
                "standardised_row_number": str(output_row_number),
                "source_locator_status": "provisional_reference_locator",
                "player_uid": player_uid,
            }
        )
        prepared_rows.append(prepared)

    fieldnames = source_columns + EXPOSURE_LOCATOR_FIELDS + ["player_uid"]
    write_rows(output_path, prepared_rows, fieldnames)
    output_hash = sha256_file(output_path)

    blank_columns = [
        header for header in source_columns
        if all(not clean_cell(row.get(header)) for row in rows)
    ]
    populated_columns = [
        header for header in source_columns
        if header not in blank_columns
    ]
    expected_columns: list[str] = []
    if args.codebook:
        codebook_rows = read_rows(Path(args.codebook))
        expected_columns = [
            clean_text(row.get("Standard_Column_Name"))
            for row in codebook_rows
            if clean_text(row.get("Standard_Column_Name"))
        ]
    normalized_headers = {header.strip() for header in headers}
    missing_codebook_columns = [
        column for column in expected_columns
        if column.strip() not in normalized_headers
    ]
    duplicate_player_date_groups = [
        {"key_hash": key, "rows": row_numbers}
        for key, row_numbers in player_date_counts.items()
        if len(row_numbers) > 1
    ]
    team_aliases = sorted(
        {
            clean_cell(row.get("Team"))
            for row in rows
            if clean_cell(row.get("Team"))
        }
    )
    exposure_reporting_grain = {
        "weekly_team_aliases": EXPOSURE_WEEKLY_TEAM_ALIASES,
        "per_session_reporting": "all_other_teams",
        "current_file_team_aliases": team_aliases,
        "current_file_reporting_grain": (
            "weekly"
            if team_aliases and all(alias in EXPOSURE_WEEKLY_TEAM_ALIASES for alias in team_aliases)
            else "per_session_or_mixed"
        ),
        "note": "Teams I, J, K, and L reported exposure weekly; all other teams reported exposure per session.",
    }

    qc = {
        "file": str(output_path),
        "file_sha256": output_hash,
        "source_workbook": str(workbook_path),
        "source_workbook_sha256": source_hash,
        "source_sheet": args.sheet,
        "row_count": len(prepared_rows),
        "column_count": len(fieldnames),
        "source_column_count": len(headers),
        "deidentified_source_label_columns_preserved": [args.player_column],
        "exposure_reporting_grain": exposure_reporting_grain,
        "player_uid_count": len({row["player_uid"] for row in prepared_rows}),
        "date_column": args.date_column,
        "date_parseable_rows": len(dates),
        "date_parse_failure_rows": date_parse_failures,
        "date_min": min(dates).date().isoformat() if dates else None,
        "date_max": max(dates).date().isoformat() if dates else None,
        "blank_columns": blank_columns,
        "populated_columns": populated_columns,
        "missing_codebook_columns": missing_codebook_columns,
        "exact_duplicate_source_rows": exact_duplicate_rows,
        "duplicate_player_date_groups": duplicate_player_date_groups,
        "anomalies": {
            "missing_player_rows": missing_player_rows,
            "missing_date_rows": missing_date_rows,
            "negative_minutes_rows": negative_minutes_rows,
            "negative_distance_rows": negative_distance_rows,
        },
        "notes": [
            "The source player label column is already de-identified, is preserved, and is also used to derive player_uid.",
            "Rows are locator-enriched for local review only; this command does not ingest exposure into Supabase.",
        ],
    }
    qc_path.parent.mkdir(parents=True, exist_ok=True)
    qc_path.write_text(json.dumps(qc, indent=2) + "\n")

    if args.manifest:
        manifest_path = Path(args.manifest)
        manifest = json.loads(manifest_path.read_text())
        manifest["exposure_intake"] = {
            "source_workbook": str(workbook_path),
            "source_workbook_sha256": source_hash,
            "source_sheet": args.sheet,
            "locator_enriched_intake_file": str(output_path),
            "locator_enriched_file_sha256": output_hash,
            "locator_enriched_row_count": len(prepared_rows),
            "qc_file": str(qc_path),
            "qc_file_sha256": sha256_file(qc_path),
            "locator_fields": EXPOSURE_LOCATOR_FIELDS,
            "uid_fields": ["player_uid"],
            "deidentified_source_label_columns_preserved": [args.player_column],
            "exposure_reporting_grain": exposure_reporting_grain,
            "source_locator_status": "provisional_reference_locator",
        }
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    print(
        json.dumps(
            {
                "prepared": str(output_path),
                "rows": len(prepared_rows),
                "sha256": output_hash,
                "qc": str(qc_path),
                "date_min": qc["date_min"],
                "date_max": qc["date_max"],
                "player_uid_count": qc["player_uid_count"],
            },
            indent=2,
        )
    )


def exposure_scope_status(row: dict[str, str]) -> tuple[str, str]:
    fields = ["Competition", "session type", "If match, surface?"]
    text = " ".join(clean_text(row.get(field)).lower() for field in fields).strip()
    if not text:
        return "scope_unknown_included", "blank_scope_fields_retained"
    out_of_scope_terms = [
        "academy",
        "international",
        "national",
        "rehab",
        "return to play",
        "rtp",
    ]
    if any(term in text for term in out_of_scope_terms):
        return "out_of_scope_explicit", "explicit_non_urc_or_non_squad_context"
    return "in_scope_explicit", "explicit_scope_context_not_excluded"


def clean_exposure(args: argparse.Namespace) -> None:
    path = Path(args.file)
    output_path = Path(args.output)
    qc_path = Path(args.qc_output)
    rows = read_rows(path)
    if not rows:
        raise SystemExit("no exposure rows found")

    exact_seen: dict[str, int] = {}
    cleaned_rows: list[dict[str, str]] = []
    counts: dict[str, int] = {}
    reasons: dict[str, int] = {}
    grain_counts: dict[str, int] = {}
    included_minutes = 0.0
    included_distance = 0.0
    dates: list[datetime] = []

    for row in rows:
        team_alias = clean_text(row.get("Team"))
        grain = "weekly" if team_alias in EXPOSURE_WEEKLY_TEAM_ALIASES else "session"
        grain_counts[grain] = grain_counts.get(grain, 0) + 1
        minutes = parse_float(row.get("minutes total"))
        distance = parse_float(row.get("distance total"))
        parsed_date = parse_flexible_date(row.get("session date"))
        if parsed_date:
            dates.append(parsed_date)
        scope_status, scope_reason = exposure_scope_status(row)
        source_hash = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
        duplicate_copy = source_hash in exact_seen
        exact_seen.setdefault(source_hash, int(row.get("source_row_number", "0") or 0))

        exclusion_reasons: list[str] = []
        if duplicate_copy:
            exclusion_reasons.append("exact_duplicate_copy")
        if not clean_text(row.get("name")):
            exclusion_reasons.append("missing_player_label")
        if parsed_date is None:
            exclusion_reasons.append("missing_or_unparseable_date")
        if minutes is None:
            exclusion_reasons.append("missing_or_unparseable_minutes")
        if distance is None:
            exclusion_reasons.append("missing_or_unparseable_distance")
        if minutes is not None and distance is not None:
            if minutes < 0 or distance < 0:
                exclusion_reasons.append("negative_minutes_or_distance")
            if minutes == 0 and distance == 0:
                exclusion_reasons.append("zero_minutes_and_zero_distance")
            if grain == "weekly":
                if minutes < 5:
                    exclusion_reasons.append("weekly_minutes_below_5")
                if minutes > 1100:
                    exclusion_reasons.append("weekly_minutes_above_1100")
                if distance > 40000:
                    exclusion_reasons.append("weekly_distance_above_40000m")
            else:
                if minutes < 5:
                    exclusion_reasons.append("session_minutes_below_5")
                if distance < 200:
                    exclusion_reasons.append("session_distance_below_200m")
                if minutes > 220:
                    exclusion_reasons.append("session_minutes_above_220")
                if distance > 20000:
                    exclusion_reasons.append("session_distance_above_20000m")
                if minutes > 0 and (distance / minutes) > 1000:
                    exclusion_reasons.append("session_impossible_distance_per_minute")
        if scope_status == "out_of_scope_explicit":
            exclusion_reasons.append(scope_reason)

        action = "exclude_from_primary" if exclusion_reasons else "include"
        counts[action] = counts.get(action, 0) + 1
        for reason in exclusion_reasons:
            reasons[reason] = reasons.get(reason, 0) + 1
        if action == "include":
            included_minutes += minutes or 0.0
            included_distance += distance or 0.0

        cleaned = dict(row)
        cleaned.update(
            {
                "exposure_grain": grain,
                "scope_status": scope_status,
                "scope_reason": scope_reason,
                "cleaned_date": parsed_date.date().isoformat() if parsed_date else "",
                "week_start_date": parsed_date.date().isoformat() if parsed_date and grain == "weekly" else "",
                "session_date_clean": parsed_date.date().isoformat() if parsed_date and grain == "session" else "",
                "minutes_total_clean": "" if minutes is None else f"{minutes:.6f}",
                "distance_total_m_clean": "" if distance is None else f"{distance:.6f}",
                "cleaning_action": action,
                "exclusion_reason": ";".join(exclusion_reasons),
            }
        )
        cleaned_rows.append(cleaned)

    added_fields = [
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
    ]
    fieldnames = list(rows[0].keys()) + added_fields
    write_rows(output_path, cleaned_rows, fieldnames)
    output_hash = sha256_file(output_path)
    qc = {
        "file": str(output_path),
        "file_sha256": output_hash,
        "source_file": str(path),
        "source_file_sha256": sha256_file(path),
        "row_count": len(cleaned_rows),
        "action_counts": counts,
        "exclusion_reason_counts": reasons,
        "exposure_grain_counts": grain_counts,
        "date_min": min(dates).date().isoformat() if dates else None,
        "date_max": max(dates).date().isoformat() if dates else None,
        "included_minutes_total": round(included_minutes, 6),
        "included_distance_total_m": round(included_distance, 6),
        "rules": {
            "scope": "Only explicitly academy, international/national-team, rehab, RTP/return-to-play, or other named non-cohort contexts are excluded; blank scope fields are retained as scope_unknown_included.",
            "weekly_teams": EXPOSURE_WEEKLY_TEAM_ALIASES,
            "weekly_exclusions": ["minutes < 5", "minutes > 1100", "distance > 40000m"],
            "session_exclusions": ["minutes < 5", "distance < 200m", "minutes > 220", "distance > 20000m", "distance/minute > 1000"],
            "global_exclusions": ["exact duplicate copy", "missing player/date/minutes/distance", "negative minutes/distance", "minutes = 0 and distance = 0"],
        },
    }
    qc_path.parent.mkdir(parents=True, exist_ok=True)
    qc_path.write_text(json.dumps(qc, indent=2) + "\n")
    if args.manifest:
        manifest_path = Path(args.manifest)
        manifest = json.loads(manifest_path.read_text())
        manifest["exposure_cleaning"] = {
            "cleaned_file": str(output_path),
            "cleaned_file_sha256": output_hash,
            "qc_file": str(qc_path),
            "qc_file_sha256": sha256_file(qc_path),
            "protocol_document": "docs/EXPOSURE_CLEANING_PROTOCOL.md",
            "row_count": len(cleaned_rows),
            "action_counts": counts,
            "exclusion_reason_counts": reasons,
            "exposure_grain_counts": grain_counts,
        }
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        json.dumps(
            {
                "cleaned": str(output_path),
                "rows": len(cleaned_rows),
                "action_counts": counts,
                "exclusion_reason_counts": reasons,
                "qc": str(qc_path),
                "sha256": output_hash,
            },
            indent=2,
        )
    )


def process_exposure(args: argparse.Namespace) -> None:
    path = Path(args.file)
    rows = read_rows(path)
    if not rows:
        raise SystemExit("no cleaned exposure rows found")
    file_hash = sha256_file(path)
    version_number = args.version_number
    included_rows = sum(1 for row in rows if row.get("cleaning_action") == "include")
    excluded_rows = sum(1 for row in rows if row.get("cleaning_action") == "exclude_from_primary")
    reason_counts: dict[str, int] = {}
    grain_counts: dict[str, int] = {}
    scope_counts: dict[str, int] = {}
    record_sql = []
    event_sql = []
    params = SqlParams()

    for index, row in enumerate(rows, start=2):
        raw_id = raw_record_id(args.team, args.season, file_hash, index)
        exclusion_reasons = [
            reason for reason in row.get("exclusion_reason", "").split(";") if reason
        ]
        for reason in exclusion_reasons:
            reason_counts[reason] = reason_counts.get(reason, 0) + 1
        grain = row.get("exposure_grain", "")
        scope = row.get("scope_status", "")
        if grain:
            grain_counts[grain] = grain_counts.get(grain, 0) + 1
        if scope:
            scope_counts[scope] = scope_counts.get(scope, 0) + 1
        action = row.get("cleaning_action", "")
        eligibility = "included_pending_protocol" if action == "include" else "excluded_from_primary"
        state = {
            "player_uid": row.get("player_uid") or None,
            "source_player_label": row.get("name") or None,
            "team_alias": row.get("Team") or None,
            "exposure_grain": grain or None,
            "scope_status": scope or None,
            "scope_reason": row.get("scope_reason") or None,
            "cleaned_date": row.get("cleaned_date") or None,
            "week_start_date": row.get("week_start_date") or None,
            "session_date": row.get("session_date_clean") or None,
            "minutes_total_clean": parse_float(row.get("minutes_total_clean")),
            "distance_total_m_clean": parse_float(row.get("distance_total_m_clean")),
            "cleaning_action": action or None,
            "exclusion_reasons": exclusion_reasons,
            "analysis_eligibility_status": eligibility,
            "source_locator": {
                field: row.get(field)
                for field in EXPOSURE_LOCATOR_FIELDS
                if field in row
            },
        }
        record_sql.append(
            f"""
            insert into processing.record_versions
              (source_row_id, step_run_id, version_number, record_state, eligibility_status)
            select sr.id, step.id, {version_number}, {params.jsonb(state)},
              {params.text(eligibility)}
            from ingestion.source_rows sr, current_step step
            where sr.raw_record_id = {params.text(raw_id)}
            on conflict (source_row_id, version_number) do update
              set step_run_id = excluded.step_run_id,
                  record_state = excluded.record_state,
                  eligibility_status = excluded.eligibility_status;
            """
        )
        event_sql.append(
            f"""
            insert into audit.record_events
              (step_run_id, source_row_id, field_name, old_value, new_value, action, reason_code, rationale, rule_version, review_status)
            select step.id, sr.id, 'cleaning_action', null,
              {params.jsonb(action)}, 'classify', 'exposure_cleaning_applied',
              {params.text('Exposure cleaning protocol applied; rows retained in lineage and primary denominator eligibility recorded.')},
              {params.text(args.step_version)}, 'not_required'
            from ingestion.source_rows sr, current_step step
            where sr.raw_record_id = {params.text(raw_id)};
            """
        )

    sql = f"""
      insert into audit.reason_codes (code, description) values
        ('exposure_cleaning_applied', 'Exposure cleaning protocol applied and analysis eligibility recorded.'),
        ('exposure_no_exclusions', 'Exposure cleaning protocol produced zero exclusions for this file.'),
        ('exposure_exclusion', 'Exposure row excluded from the primary denominator by a protocol-defined rule.')
      on conflict (code) do update set description = excluded.description;

      create temp table current_step on commit drop as
      with run as (
        insert into audit.pipeline_runs
          (command, team, season, status, input_hash, parameters, ended_at)
        values (
          'process-exposure', {params.text(args.team)}, {params.text(args.season)}, 'succeeded',
          {params.text(file_hash)},
          {params.jsonb({
            'file': path.name,
            'step': args.step_name,
            'step_version': args.step_version,
            'version_number': version_number,
          })},
          now()
        )
        returning id
      ),
      step as (
        insert into audit.step_runs
          (pipeline_run_id, step_name, step_version, reason_code, input_count, output_count, counts_by_team, input_hash, ended_at)
        select id, {params.text(args.step_name)}, {params.text(args.step_version)},
          {params.text('exposure_no_exclusions' if excluded_rows == 0 else 'exposure_exclusion')},
          {len(rows)}, {included_rows},
          {params.jsonb({
            args.team: {
              'rows': len(rows),
              'included_rows': included_rows,
              'excluded_from_primary_rows': excluded_rows,
              'exclusion_reason_counts': reason_counts,
              'exposure_grain_counts': grain_counts,
              'scope_status_counts': scope_counts,
            }
          })},
          {params.text(file_hash)}, now()
        from run
        returning id
      )
      select id from step;

      {"".join(record_sql)}
      {"".join(event_sql)}
    """
    run_sql(sql, params.values)
    print(
        json.dumps(
            {
                "processed": str(path),
                "rows": len(rows),
                "included_rows": included_rows,
                "excluded_from_primary_rows": excluded_rows,
                "exclusion_reason_counts": reason_counts,
                "exposure_grain_counts": grain_counts,
                "scope_status_counts": scope_counts,
                "record_events": len(event_sql),
            },
            indent=2,
        )
    )


def split_fixture(fixture: str) -> tuple[str, str]:
    parts = fixture.split(" v ")
    if len(parts) != 2:
        raise SystemExit(f"fixture must contain one ' v ': {fixture}")
    return parts[0].strip(), parts[1].strip()


def read_total_exposure_hours(path: Path, team_column: str, hours_column: str) -> dict[str, float]:
    if not path.exists():
        return {}
    rows = read_rows(path)
    if not rows:
        return {}
    missing = [column for column in [team_column, hours_column] if column not in rows[0]]
    if missing:
        raise SystemExit(f"missing total exposure column(s) in {path}: {', '.join(missing)}")
    totals: dict[str, float] = {}
    for row in rows:
        team = clean_text(row.get(team_column))
        hours = parse_float(row.get(hours_column))
        if team and hours is not None:
            totals[team] = hours
    return totals


def build_fixture_exposure(args: argparse.Namespace) -> None:
    source_path = Path(args.file)
    preserved_path = Path(args.preserved_output)
    fixture_output = Path(args.fixture_output)
    exposure_output = Path(args.exposure_output)
    qc_output = Path(args.qc_output)
    rows = read_rows(source_path)
    if not rows:
        raise SystemExit(f"no fixture rows found: {source_path}")

    preserved_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source_path, preserved_path)

    source_hash = sha256_file(source_path)
    fixture_team_aliases = load_fixture_team_aliases()
    corrected_rows: list[dict[str, str]] = []
    team_matches: dict[str, int] = defaultdict(int)
    corrections_applied = 0
    unresolved_teams: list[str] = []

    for source_row_number, row in enumerate(rows, start=2):
        fixture = clean_text(row.get("fixture"))
        home, away = split_fixture(fixture)
        home_alias = fixture_team_aliases.get(home, "")
        away_alias = fixture_team_aliases.get(away, "")
        if not home_alias:
            unresolved_teams.append(home)
        if not away_alias:
            unresolved_teams.append(away)

        source_date = parse_flexible_date(row.get("date"))
        if source_date is None:
            raise SystemExit(f"unparseable fixture date on source row {source_row_number}: {row.get('date')}")
        corrected_date = FIXTURE_DATE_CORRECTIONS.get(fixture, source_date.date().isoformat())
        if corrected_date != source_date.date().isoformat():
            corrections_applied += 1
        if home_alias:
            team_matches[home_alias] += 1
        if away_alias:
            team_matches[away_alias] += 1

        corrected_rows.append(
            {
                **row,
                "source_date": source_date.date().isoformat(),
                "corrected_date": corrected_date,
                "date_status": "corrected" if fixture in FIXTURE_DATE_CORRECTIONS else "source_confirmed",
                "home_team": home,
                "away_team": away,
                "home_team_alias": home_alias,
                "away_team_alias": away_alias,
                "match_hours_per_team": f"{args.player_hours_per_team_match:.6f}",
                "source_file_sha256": source_hash,
                "source_row_number": str(source_row_number),
            }
        )

    unresolved_unique = sorted(set(unresolved_teams))
    if unresolved_unique:
        raise SystemExit(f"unmapped fixture team(s): {', '.join(unresolved_unique)}")

    total_hours = read_total_exposure_hours(
        Path(args.total_exposure_file), args.total_team_column, args.total_hours_column
    )
    exposure_rows = []
    for team_alias in sorted(team_matches):
        matches = team_matches[team_alias]
        match_hours = matches * args.player_hours_per_team_match
        total = total_hours.get(team_alias)
        exposure_rows.append(
            {
                "team_alias": team_alias,
                "matches": str(matches),
                "match_hours": f"{match_hours:.2f}",
                "total_hours": "" if total is None else f"{total:.2f}",
                "training_hours": "" if total is None else f"{total - match_hours:.2f}",
                "training_formula": "total_hours - match_hours",
            }
        )

    stage_counts: dict[str, int] = {}
    for row in corrected_rows:
        stage = clean_text(row.get("stage"))
        stage_counts[stage] = stage_counts.get(stage, 0) + 1

    fixture_fields = list(rows[0].keys()) + [
        "source_date",
        "corrected_date",
        "date_status",
        "home_team",
        "away_team",
        "home_team_alias",
        "away_team_alias",
        "match_hours_per_team",
        "source_file_sha256",
        "source_row_number",
    ]
    write_rows(fixture_output, corrected_rows, fixture_fields)
    write_rows(
        exposure_output,
        exposure_rows,
        ["team_alias", "matches", "match_hours", "total_hours", "training_hours", "training_formula"],
    )

    qc = {
        "source_file": str(source_path),
        "source_file_sha256": source_hash,
        "preserved_source_file": str(preserved_path),
        "preserved_source_file_sha256": sha256_file(preserved_path),
        "corrected_fixture_file": str(fixture_output),
        "corrected_fixture_file_sha256": sha256_file(fixture_output),
        "team_exposure_file": str(exposure_output),
        "team_exposure_file_sha256": sha256_file(exposure_output),
        "fixture_rows": len(rows),
        "stage_counts": stage_counts,
        "date_corrections_applied": corrections_applied,
        "date_corrections_expected": len(FIXTURE_DATE_CORRECTIONS),
        "player_hours_per_team_match": args.player_hours_per_team_match,
        "training_exposure_rule": "always total_hours - match_hours",
        "total_exposure_file": str(args.total_exposure_file),
        "total_exposure_file_sha256": (
            sha256_file(Path(args.total_exposure_file))
            if Path(args.total_exposure_file).exists()
            else None
        ),
    }
    qc_output.parent.mkdir(parents=True, exist_ok=True)
    qc_output.write_text(json.dumps(qc, indent=2) + "\n")
    playoff_rows = len(rows) - stage_counts.get("Regular season", 0)
    if len(rows) != 151 or stage_counts.get("Regular season") != 144 or playoff_rows != 7:
        raise SystemExit(f"unexpected fixture structure: rows={len(rows)} stage_counts={stage_counts}")
    if corrections_applied != len(FIXTURE_DATE_CORRECTIONS):
        raise SystemExit(
            f"date corrections mismatch: applied={corrections_applied} expected={len(FIXTURE_DATE_CORRECTIONS)}"
        )
    print(
        json.dumps(
            {
                "preserved": str(preserved_path),
                "fixtures": str(fixture_output),
                "team_exposure": str(exposure_output),
                "qc": str(qc_output),
                "fixture_rows": len(rows),
                "stage_counts": stage_counts,
                "date_corrections_applied": corrections_applied,
            },
            indent=2,
        )
    )


def qa_intake(args: argparse.Namespace) -> None:
    path = Path(args.file)
    rows = read_rows(path)
    if not rows:
        raise SystemExit("no rows found")
    missing_locator_fields = [field for field in LOCATOR_FIELDS + UID_FIELDS if field not in rows[0]]
    if missing_locator_fields:
        raise SystemExit(f"missing locator fields: {', '.join(missing_locator_fields)}")

    def value(row: dict[str, str], key: str) -> str:
        return row.get(key, "").strip()

    exact_seen: set[str] = set()
    exact_duplicates = 0
    key_counts: dict[str, dict[str, list[int]]] = {"injury_signature": {}}
    outside_window: list[int] = []
    unparseable_dates: list[int] = []
    derived_return_dates = 0

    window_start = datetime.strptime(args.window_start, "%Y-%m-%d")
    window_end = datetime.strptime(args.window_end, "%Y-%m-%d")

    for index, row in enumerate(rows, start=2):
        row_hash = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
        if row_hash in exact_seen:
            exact_duplicates += 1
        exact_seen.add(row_hash)

        keys = {"injury_signature": "|".join(value(row, field) for field in DUPLICATE_SIGNATURE_FIELDS)}
        for name, key in keys.items():
            key_counts[name].setdefault(key, []).append(index)

        injured_at = parse_uk_date(value(row, "Date Injured"))
        if injured_at is None:
            unparseable_dates.append(index)
        elif injured_at < window_start or injured_at > window_end:
            outside_window.append(index)

        days = parse_int(value(row, "Days Injured"))
        if injured_at and days is not None:
            _ = injured_at + timedelta(days=days)
            derived_return_dates += 1

    duplicate_keys = {
        name: [
            {"key_hash": stable_uid("key", name, key), "rows": indices}
            for key, indices in counts.items()
            if key and len(indices) > 1
        ]
        for name, counts in key_counts.items()
    }

    report = {
        "file": str(path),
        "file_sha256": sha256_file(path),
        "row_count": len(rows),
        "exact_duplicate_rows": exact_duplicates,
        "duplicate_key_groups": duplicate_keys,
        "date_injured_unparseable_rows": unparseable_dates,
        "outside_provisional_qc_window_rows": outside_window,
        "provisional_qc_window": {
            "start": args.window_start,
            "end": args.window_end,
        },
        "derived_return_date_rows": derived_return_dates,
        "return_date_rule": "Date Injured + Days Injured",
        "notes": [
            "Rows are flagged for review or analysis exclusion; source rows are not deleted.",
            "Duplicate keys are hashed in this report to avoid printing player or injury identifiers.",
        ],
    }
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


def build_processing_state(
    row: dict[str, str],
    *,
    window_start: datetime,
    window_end: datetime,
    duplicate_signature_rows: set[int],
) -> tuple[dict[str, object], list[dict[str, object]]]:
    source_row_number = int(row["standardised_row_number"])
    injured_at = parse_uk_date(row.get("Date Injured", ""))
    days_injured = parse_int(row.get("Days Injured", ""))
    is_closed, is_closed_origin = injury_closed(row)
    derived_return_date = None
    if injured_at is not None and days_injured is not None:
        derived_return_date = (injured_at + timedelta(days=days_injured)).date().isoformat()

    activity, activity_origin = activity_context(row)
    contact, contact_origin = contact_context(row)
    recurrence, recurrence_origin = recurrence_status(row)
    severity, severity_origin = severity_category(days_injured, is_closed)
    body, body_origin = body_location(row)
    problem, problem_origin = problem_type(row)
    injury, injury_origin = injury_type(row)
    return_date_origin = None
    if derived_return_date and is_closed is False:
        return_date_origin = "derived_from_days_injured_unclosed_censored"
    elif derived_return_date:
        return_date_origin = "derived_from_days_injured"

    outside_window = injured_at is None or injured_at < window_start or injured_at > window_end
    duplicate_flags = {
        "candidate_duplicate_injury_signature": source_row_number in duplicate_signature_rows,
    }
    review_required = any(duplicate_flags.values()) or outside_window or injured_at is None
    state = {
        "player_uid": row["player_uid"],
        "injury_uid": row["injury_uid"],
        "date_injured": injured_at.date().isoformat() if injured_at else None,
        "days_injured_source": days_injured,
        "source_confirmed_return_date": row.get("Confirmed Return Date", "").strip() or None,
        "derived_return_date": derived_return_date,
        "return_date_origin": return_date_origin,
        "is_closed": is_closed,
        "activity_context": activity,
        "contact_context": contact,
        "recurrence_status": recurrence,
        "severity_category": severity,
        "body_location": body,
        "problem_type": problem,
        "injury_type": injury,
        "field_origins": {
            "is_closed": is_closed_origin,
            "activity_context": activity_origin,
            "contact_context": contact_origin,
            "recurrence_status": recurrence_origin,
            "severity_category": severity_origin,
            "body_location": body_origin,
            "problem_type": problem_origin,
            "injury_type": injury_origin,
        },
        "provisional_qc_window": {
            "start": window_start.date().isoformat(),
            "end": window_end.date().isoformat(),
        },
        "season_window_status": "outside_provisional_qc_window" if outside_window else "inside_provisional_qc_window",
        "analysis_eligibility_status": "review_required" if review_required else "included_pending_protocol",
        "duplicate_flags": duplicate_flags,
        "source_locator": {
            field: row[field]
            for field in LOCATOR_FIELDS
        },
    }

    events: list[dict[str, object]] = []
    if derived_return_date:
        events.append(
            {
                "field_name": "derived_return_date",
                "old_value": None,
                "new_value": derived_return_date,
                "action": "derive",
                "reason_code": "derived_return_date",
                "rationale": "Derived from Date Injured + Days Injured; source Confirmed Return Date is preserved separately.",
                "review_status": "not_required",
            }
        )
    for field_name in [
        "activity_context",
        "contact_context",
        "recurrence_status",
        "severity_category",
        "body_location",
        "is_closed",
        "problem_type",
        "injury_type",
    ]:
        origin = state["field_origins"][field_name]
        action = "infer" if str(origin).startswith("inferred_") else "map"
        events.append(
            {
                "field_name": field_name,
                "old_value": None,
                "new_value": state[field_name],
                "action": action,
                "reason_code": "controlled_inference" if action == "infer" else "canonical_mapping",
                "rationale": f"{field_name} set by {origin}; source value preserved.",
                "review_status": "needs_review" if action == "infer" else "not_required",
            }
        )
    if duplicate_flags["candidate_duplicate_injury_signature"]:
        events.append(
            {
                "field_name": "candidate_duplicate_injury_signature",
                "old_value": None,
                "new_value": True,
                "action": "flag",
                "reason_code": "candidate_duplicate",
                "rationale": "Same player, date, body part, Orchard code, side, description, and onset appear on more than one ingested row; row retained for review.",
                "review_status": "needs_review",
            }
        )
    if outside_window:
        events.append(
            {
                "field_name": "season_window_status",
                "old_value": None,
                "new_value": state["season_window_status"],
                "action": "flag",
                "reason_code": "outside_provisional_window",
                "rationale": "Date Injured falls outside the provisional July-to-June QC window or is unparseable; row retained.",
                "review_status": "needs_review",
            }
        )
    return state, events


def process_intake(args: argparse.Namespace) -> None:
    path = Path(args.file)
    rows = read_rows(path)
    if not rows:
        raise SystemExit("no rows found")
    missing_locator_fields = [field for field in LOCATOR_FIELDS + UID_FIELDS if field not in rows[0]]
    if missing_locator_fields:
        raise SystemExit(f"missing locator fields: {', '.join(missing_locator_fields)}")

    window_start = datetime.strptime(args.window_start, "%Y-%m-%d")
    window_end = datetime.strptime(args.window_end, "%Y-%m-%d")
    file_hash = sha256_file(path)

    def duplicate_rows_for(columns: list[str]) -> set[int]:
        counts: dict[str, list[int]] = {}
        for row in rows:
            key = "|".join(row.get(column, "").strip() for column in columns)
            counts.setdefault(key, []).append(int(row["standardised_row_number"]))
        return {
            row_number
            for key, row_numbers in counts.items()
            if key and len(row_numbers) > 1
            for row_number in row_numbers
        }

    duplicate_signature_rows = duplicate_rows_for(DUPLICATE_SIGNATURE_FIELDS)

    record_sql = []
    event_sql = []
    params = SqlParams()
    changed_rows = 0
    event_count = 0
    review_required_rows = 0
    for row in rows:
        source_row_number = int(row["standardised_row_number"])
        state, events = build_processing_state(
            row,
            window_start=window_start,
            window_end=window_end,
            duplicate_signature_rows=duplicate_signature_rows,
        )
        if state["analysis_eligibility_status"] == "review_required":
            review_required_rows += 1
        if events:
            changed_rows += 1
        raw_id = raw_record_id(args.team, args.season, file_hash, source_row_number)
        record_sql.append(
            f"""
            insert into processing.record_versions
              (source_row_id, step_run_id, version_number, record_state, eligibility_status)
            select sr.id, step.id, {args.version_number}, {params.jsonb(state)},
              {params.text(state["analysis_eligibility_status"])}
            from ingestion.source_rows sr, current_step step
            where sr.raw_record_id = {params.text(raw_id)}
            on conflict (source_row_id, version_number) do update
              set step_run_id = excluded.step_run_id,
                  record_state = excluded.record_state,
                  eligibility_status = excluded.eligibility_status;
            """
        )
        for event in events:
            event_count += 1
            event_sql.append(
                f"""
                insert into audit.record_events
                  (step_run_id, source_row_id, field_name, old_value, new_value, action, reason_code, rationale, rule_version, review_status)
                select step.id, sr.id, {params.text(event["field_name"])}, {params.jsonb(event["old_value"])},
                  {params.jsonb(event["new_value"])}, {params.text(event["action"])},
                  {params.text(event["reason_code"])}, {params.text(event["rationale"])},
                  {params.text(args.step_version)}, {params.text(event["review_status"])}
                from ingestion.source_rows sr, current_step step
                where sr.raw_record_id = {params.text(raw_id)};
                """
            )

    sql = f"""
      insert into audit.reason_codes (code, description) values
        ('locator_enriched_intake', 'Intake row includes provisional source row locator and stable opaque UIDs.'),
        ('derived_return_date', 'Return date derived from Date Injured plus Days Injured; source value preserved.'),
        ('canonical_mapping', 'Canonical analysis field mapped from source field without overwriting the source value.'),
        ('controlled_inference', 'Canonical analysis field inferred from explicit high-confidence source evidence and marked with origin metadata.'),
        ('candidate_duplicate', 'Candidate duplicate flagged for review; source row retained.'),
        ('outside_provisional_window', 'Row falls outside provisional QC season window or has unparseable injury date; source row retained.')
      on conflict (code) do update set description = excluded.description;

      create temp table current_step on commit drop as
      with run as (
        insert into audit.pipeline_runs
          (command, team, season, status, input_hash, parameters, ended_at)
        values (
          'process-intake', {params.text(args.team)}, {params.text(args.season)}, 'succeeded',
          {params.text(file_hash)},
          {params.jsonb({
            'file': path.name,
            'step': args.step_name,
            'step_version': args.step_version,
            'window_start': args.window_start,
            'window_end': args.window_end,
          })},
          now()
        )
        returning id
      ),
      step as (
        insert into audit.step_runs
          (pipeline_run_id, step_name, step_version, reason_code, input_count, output_count, counts_by_team, input_hash, ended_at)
        select id, {params.text(args.step_name)}, {params.text(args.step_version)}, 'locator_enriched_intake',
          {len(rows)}, {len(rows)},
          {params.jsonb({
            args.team: {
              'rows': len(rows),
              'changed_or_flagged_rows': changed_rows,
              'review_required_rows': review_required_rows,
              'record_events': event_count,
              'duplicate_signature_rows': len(duplicate_signature_rows),
            }
          })},
          {params.text(file_hash)}, now()
        from run
        returning id
      )
      select id from step;

      {"".join(record_sql)}
      {"".join(event_sql)}
    """
    run_sql(sql, params.values)
    print(
        json.dumps(
            {
                "processed": str(path),
                "rows": len(rows),
                "changed_or_flagged_rows": changed_rows,
                "review_required_rows": review_required_rows,
                "record_events": event_count,
                "duplicate_signature_rows": len(duplicate_signature_rows),
            },
            indent=2,
        )
    )


def trace_row(args: argparse.Namespace) -> None:
    intake_rows = read_rows(Path(args.file))
    row = next(
        (item for item in intake_rows if item.get("standardised_row_number") == str(args.row_number)),
        None,
    )
    if row is None:
        raise SystemExit(f"standardised row {args.row_number} not found")

    result = {"standardised_row": row}
    if args.include_source:
        source_rows = read_rows(Path(row["source_archive_path"]))
        source_index = int(row["source_row_number"]) - 2
        if source_index < 0 or source_index >= len(source_rows):
            raise SystemExit(f"source row {row['source_row_number']} not found")
        result["source_row"] = source_rows[source_index]
    print(json.dumps(result, indent=2))


def ingest(args: argparse.Namespace) -> None:
    path = Path(args.file)
    file_hash = sha256_file(path)
    rows = read_rows(path)
    manifest = {
        "manifest": json.loads(Path(args.manifest).read_text()) if args.manifest else {},
        "original_path": str(path),
    }

    row_sql = []
    params = SqlParams()
    for index, row in enumerate(rows, start=2):
        row_hash = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
        raw_record_id = f"{args.team}:{args.season}:{file_hash[:12]}:{index}"
        row_sql.append(
            f"""
            insert into ingestion.source_rows
              (source_file_id, source_row_number, raw_record_id, row_sha256, source_values)
            select id, {index}, {params.text(raw_record_id)}, {params.text(row_hash)}, {params.jsonb(row)}
            from ingestion.source_files
            where team = {params.text(args.team)}
              and season = {params.text(args.season)}
              and file_sha256 = {params.text(file_hash)}
            on conflict (source_file_id, sheet_name, source_row_number) do nothing;
            """
        )

    sql = f"""
      with source_file as (
        insert into ingestion.source_files
          (team, season, file_name, file_sha256, file_size_bytes, intake_manifest, row_count)
        values (
          {params.text(args.team)}, {params.text(args.season)}, {params.text(path.name)},
          {params.text(file_hash)}, {path.stat().st_size}, {params.jsonb(manifest)}, {len(rows) if rows else 'null'}
        )
        on conflict (team, season, file_sha256) do update
          set intake_manifest = excluded.intake_manifest
        returning id
      )
      insert into audit.pipeline_runs (command, team, season, status, input_hash, parameters, ended_at)
      values ('ingest', {params.text(args.team)}, {params.text(args.season)}, 'succeeded', {params.text(file_hash)}, {params.jsonb({'file': path.name})}, now());
      {"".join(row_sql)}
    """
    run_sql(sql, params.values)
    print(f"registered {path.name} sha256={file_hash} rows={len(rows) if rows else 'not-loaded'}")


def run_step(args: argparse.Namespace) -> None:
    params = SqlParams()
    sql = f"""
      with run as (
        insert into audit.pipeline_runs (command, team, season, status, parameters, ended_at)
        values ('run', {params.text(args.team)}, {params.text(args.season)}, 'succeeded', {params.jsonb({'step': args.step})}, now())
        returning id
      )
      insert into audit.step_runs (pipeline_run_id, step_name, step_version, reason_code, input_count, output_count, ended_at)
      select id, {params.text(args.step)}, '0.1.0', 'placeholder_step', 0, 0, now()
      from run;
    """
    run_sql(sql, params.values)
    print(f"recorded step {args.step}")


def release(args: argparse.Namespace) -> None:
    label = f"{args.team}-{args.season}-local-smoke"
    dashboard_path = Path(args.dashboard_file) if args.dashboard_file else (
        Path("content") / "reporting" / f"{args.team.lower()}_dashboard_{args.season}.json"
    )
    dashboard_metrics: list[dict[str, object]] = []
    if dashboard_path.exists():
        dashboard = json.loads(dashboard_path.read_text())
        dashboard_metrics = [
            {
                "metric_key": metric["key"],
                "metric_label": metric["label"],
                "value": metric.get("value"),
                "numerator": metric.get("numerator"),
                "denominator": metric.get("denominator"),
                "unit": metric.get("unit"),
                "coverage_note": f"Dashboard headline metric from {dashboard_path}",
            }
            for metric in dashboard.get("headline", [])
        ]
    params = SqlParams()
    metric_insert = ""
    if dashboard_metrics:
        metric_insert = f"""
          insert into reporting.team_metric_aggregates
            (release_id, team, season, metric_key, metric_label, value, numerator, denominator, unit, coverage_note)
          select current_release.id, {params.text(args.team)}, {params.text(args.season)},
            metric_key, metric_label, value, numerator, denominator, unit, coverage_note
          from current_release,
            jsonb_to_recordset({params.jsonb(dashboard_metrics)}) as metric(
              metric_key text,
              metric_label text,
              value numeric,
              numerator numeric,
              denominator numeric,
              unit text,
              coverage_note text
            )
          on conflict (release_id, team, season, metric_key, scope) do update
            set metric_label = excluded.metric_label,
                value = excluded.value,
                numerator = excluded.numerator,
                denominator = excluded.denominator,
                unit = excluded.unit,
                coverage_note = excluded.coverage_note,
                suppressed = false;
        """
    sql = f"""
      create temp table current_release on commit drop as
      with run as (
        insert into audit.pipeline_runs (command, team, season, status, parameters, ended_at)
        values ('release', {params.text(args.team)}, {params.text(args.season)}, 'succeeded', {params.jsonb({'release': label, 'dashboard_file': str(dashboard_path) if dashboard_metrics else None})}, now())
        returning id
      ),
      release as (
        insert into reporting.aggregate_releases (release_label, status, pipeline_run_id, approved_at)
        select {params.text(label)}, 'approved', id, now()
        from run
        on conflict (release_label) do update
          set status = 'approved',
              pipeline_run_id = excluded.pipeline_run_id,
              approved_at = now()
        returning id
      )
      select id from release;

      insert into reporting.team_metric_aggregates
        (release_id, team, season, metric_key, metric_label, value, numerator, denominator, unit, coverage_note)
      select current_release.id, {params.text(args.team)}, {params.text(args.season)}, 'registered_source_files',
        'Registered source files', count(*), count(*), null, 'files', 'Local smoke aggregate only'
      from current_release, ingestion.source_files
      where team = {params.text(args.team)} and season = {params.text(args.season)}
      group by current_release.id
      on conflict (release_id, team, season, metric_key, scope) do update
        set value = excluded.value, numerator = excluded.numerator, coverage_note = excluded.coverage_note;

      {metric_insert}
    """
    run_sql(sql, params.values)
    print(f"released {label} metrics={len(dashboard_metrics) + 1}")


def adjudicate_duplicate_exclusion(args: argparse.Namespace) -> None:
    path = Path(args.file)
    file_hash = sha256_file(path)
    raw_id = raw_record_id(args.team, args.season, file_hash, args.row_number)
    params = SqlParams()
    state = {
        "analysis_eligibility_status": "excluded_duplicate_adjudicated",
        "excluded_standardised_row_number": args.row_number,
        "duplicate_of_standardised_row_number": args.duplicate_of,
        "decision": "exclude_duplicate",
        "rationale": args.rationale,
    }
    sql = f"""
      insert into audit.reason_codes (code, description) values
        ('duplicate_adjudicated_exclusion', 'Manual review adjudicated a candidate duplicate and excluded it from analysis.')
      on conflict (code) do update set description = excluded.description;

      create temp table current_step on commit drop as
      with run as (
        insert into audit.pipeline_runs
          (command, team, season, status, input_hash, parameters, ended_at)
        values (
          'adjudicate-duplicate-exclusion', {params.text(args.team)}, {params.text(args.season)}, 'succeeded',
          {params.text(file_hash)},
          {params.jsonb({
            'file': path.name,
            'row_number': args.row_number,
            'duplicate_of': args.duplicate_of,
            'step_version': args.step_version,
            'version_number': args.version_number,
          })},
          now()
        )
        returning id
      ),
      step as (
        insert into audit.step_runs
          (pipeline_run_id, step_name, step_version, reason_code, input_count, output_count, counts_by_team, input_hash, ended_at)
        select id, 'duplicate_adjudication', {params.text(args.step_version)},
          'duplicate_adjudicated_exclusion', 1, 0,
          {params.jsonb({args.team: {'excluded_duplicate_rows': [args.row_number]}})},
          {params.text(file_hash)}, now()
        from run
        returning id
      )
      select id from step;

      insert into processing.record_versions
        (source_row_id, step_run_id, version_number, record_state, eligibility_status)
      select sr.id, step.id, {args.version_number}, {params.jsonb(state)}, 'excluded_duplicate_adjudicated'
      from ingestion.source_rows sr, current_step step
      where sr.raw_record_id = {params.text(raw_id)}
      on conflict (source_row_id, version_number) do update
        set step_run_id = excluded.step_run_id,
            record_state = excluded.record_state,
            eligibility_status = excluded.eligibility_status;

      insert into audit.record_events
        (step_run_id, source_row_id, field_name, old_value, new_value, action, reason_code, rationale, rule_version, review_status)
      select step.id, sr.id, 'analysis_eligibility_status', null,
        {params.jsonb('excluded_duplicate_adjudicated')}, 'exclude',
        'duplicate_adjudicated_exclusion', {params.text(args.rationale)},
        {params.text(args.step_version)}, 'adjudicated'
      from ingestion.source_rows sr, current_step step
      where sr.raw_record_id = {params.text(raw_id)};
    """
    run_sql(sql, params.values)
    print(json.dumps({"team": args.team, "excluded_row": args.row_number, "raw_record_id": raw_id}, indent=2))


def parse_date_value(value: str) -> date | None:
    text = clean_text(value)
    if not text:
        return None
    for fmt in ("%d/%m/%Y", "%Y-%m-%d", "%m/%d/%Y"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            pass
    return None


def month_label(value: date) -> str:
    return value.strftime("%b %Y")


def severity_band(days: int | None, closed: bool) -> tuple[str, str]:
    if days is None or not closed:
        return "unknown_or_censored", "Unknown or censored"
    if days == 0:
        return "zero_days_medical_attention_only", "Medical attention"
    if days == 1:
        return "one_day", "1 day"
    if 2 <= days <= 3:
        return "two_to_three_days", "2-3 days"
    if 4 <= days <= 7:
        return "four_to_seven_days", "4-7 days"
    if 8 <= days <= 28:
        return "eight_to_twenty_eight_days", "8-28 days"
    return "greater_than_twenty_eight_days", ">28 days"


BODY_LOCATION_LABELS = {
    "abdomen": "Abdomen",
    "ankle": "Ankle",
    "chest": "Chest",
    "elbow": "Elbow",
    "forearm": "Forearm",
    "foot": "Foot",
    "hand": "Hand",
    "head": "Head",
    "hip_groin": "Hip/Groin",
    "knee": "Knee",
    "lower_leg": "Lower leg",
    "lumbosacral": "Lumbosacral",
    "multiple": "Multiple",
    "neck": "Neck",
    "shoulder": "Shoulder",
    "thigh": "Thigh",
    "thoracic_spine": "Thoracic spine",
    "unspecified": "Unspecified",
    "upper_arm": "Upper arm",
    "wrist": "Wrist",
    "unknown": "Unknown",
}

INJURY_TYPE_LABELS = {
    "arthritis": "Arthritis",
    "avascular_necrosis": "Avascular necrosis",
    "bone_contusion": "Bone contusion",
    "bone_stress_injury": "Bone stress injury",
    "brain_spinal_cord_injury": "Brain/spinal cord injury",
    "bursitis": "Bursitis",
    "cartilage_injury": "Cartilage injury",
    "chronic_instability": "Chronic instability",
    "contusion_superficial": "Contusion (superficial)",
    "fracture": "Fracture",
    "internal_organ_trauma": "Internal organs (organ trauma)",
    "joint_sprain": "Joint sprain",
    "laceration": "Laceration",
    "muscle_injury": "Muscle injury",
    "nonspecific": "Nonspecific",
    "peripheral_nerve_injury": "Peripheral nerve injury",
    "physis_injury": "Physis injury",
    "synovitis_capsulitis": "Synovitis/capsulitis",
    "tendon_rupture": "Tendon rupture",
    "tendinopathy": "Tendinopathy",
    "unknown": "Unknown",
}

CONTROLLED_BODY_LOCATION_LABELS = set(BODY_LOCATION_LABELS.values())
CONTROLLED_INJURY_TYPE_LABELS = set(INJURY_TYPE_LABELS.values())
BODY_LOCATION_LABEL_TO_KEY = {label.lower(): key for key, label in BODY_LOCATION_LABELS.items()}
INJURY_TYPE_LABEL_TO_KEY = {label.lower(): key for key, label in INJURY_TYPE_LABELS.items()}

SEVERITY_LABELS = {
    "zero_days_medical_attention_only": "Medical Attention",
    "one_day": "1 day",
    "two_to_three_days": "2-3 days",
    "four_to_seven_days": "4-7 days",
    "eight_to_twenty_eight_days": "8-28 days",
    "greater_than_twenty_eight_days": ">28 days",
    "unknown_or_censored": "Unknown",
}

ANALYSIS_EXPORT_ORIGIN_FIELDS = [
    "Problem type origin",
    "Injury Status origin",
    "Fit for selection origin",
    "Confirmed Return Date origin",
    "Occasion category origin",
    "Match Type origin",
    "Body Part origin",
    "Injury Tissue Type/s origin",
    "Injury Grade origin",
    "Recurrence origin",
    "Is Contact origin",
    "TimeLoss vs Medical Attention origin",
]


def format_uk_date(value: date | None) -> str:
    return value.strftime("%d/%m/%Y") if value else ""


def filled_injury_export_row(row: dict[str, str]) -> dict[str, str]:
    output = dict(row)
    injured_at = parse_date_value(row.get("Date Injured", ""))
    days = parse_int(row.get("Days Injured", ""))
    is_closed, is_closed_origin = injury_closed(row)
    activity, activity_origin = activity_context(row)
    contact, contact_origin = contact_context(row)
    recurrence, recurrence_origin = recurrence_status(row)
    severity, severity_origin = severity_category(days, is_closed)
    body, body_origin = body_location(row)
    problem, problem_origin = problem_type(row)
    injury, injury_origin = injury_type(row)
    return_date = injured_at + timedelta(days=days) if injured_at and days is not None else None

    output["Problem type"] = {"injury": "Injury", "illness": "Illness"}.get(problem, "Unknown")
    output["Injury Status"] = {True: "Closed", False: "Open/Ongoing"}.get(is_closed, "Unknown")
    output["Fit for selection"] = {True: "Yes", False: "No"}.get(is_closed, "Unknown")
    output["Fit For Selection Date"] = ""
    output["Confirmed Return Date"] = format_uk_date(return_date) if is_closed is True else ""
    output["Occasion category"] = {"urc_match": "match", "training": "training"}.get(activity, "unknown")
    output["Match Type"] = {"urc_match": "URC", "training": "training"}.get(activity, "unknown")
    output["Body Part"] = BODY_LOCATION_LABELS.get(body, "Unknown")
    output["Injury Tissue Type/s"] = INJURY_TYPE_LABELS.get(injury, "Unknown")
    output["Injury Grade"] = SEVERITY_LABELS.get(severity, "Unknown")
    output["Recurrence"] = {"first_episode": "First episode", "recurrence": "Recurrence"}.get(
        recurrence, "Unknown"
    )
    output["Is Contact"] = {"contact": "Contact", "non_contact": "Non-Contact"}.get(contact, "Unknown")
    output["TimeLoss vs Medical Attention"] = (
        "Unknown" if days is None else "Time Loss" if days > 0 else "Medical Attention"
    )
    output["Problem type origin"] = problem_origin
    output["Injury Status origin"] = is_closed_origin
    output["Fit for selection origin"] = is_closed_origin
    output["Confirmed Return Date origin"] = (
        "derived_from_date_injured_plus_days" if is_closed is True and return_date else ""
    )
    output["Occasion category origin"] = activity_origin
    output["Match Type origin"] = activity_origin
    output["Body Part origin"] = body_origin
    output["Injury Tissue Type/s origin"] = injury_origin
    output["Injury Grade origin"] = severity_origin
    output["Recurrence origin"] = recurrence_origin
    output["Is Contact origin"] = contact_origin
    output["TimeLoss vs Medical Attention origin"] = "derived_from_days_injured"
    return output


def rate_per_1000(count: float, hours: float) -> float | None:
    if hours <= 0:
        return None
    return count / hours * 1000


def rounded(value: float | None, digits: int = 1) -> float | None:
    if value is None:
        return None
    return round(value, digits)


def build_group_rows(
    rows: list[dict[str, Any]], field: str, hours: float, limit: int | None = None
) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"label": "Unknown", "time_loss_injuries": 0, "days_lost": 0}
    )
    for row in rows:
        label = clean_text(row.get(field)) or "Unknown"
        grouped[label]["label"] = label
        grouped[label]["time_loss_injuries"] += 1
        grouped[label]["days_lost"] += row["days_lost"]

    result = sorted(
        (
            {
                **item,
                "incidence_per_1000h": rounded(rate_per_1000(item["time_loss_injuries"], hours)),
                "burden_per_1000h": rounded(rate_per_1000(item["days_lost"], hours)),
                "mean_severity_days": rounded(
                    item["days_lost"] / item["time_loss_injuries"]
                    if item["time_loss_injuries"]
                    else None
                ),
            }
            for item in grouped.values()
        ),
        key=lambda item: (-item["time_loss_injuries"], -item["days_lost"], item["label"]),
    )
    return result[:limit] if limit else result


def exposure_analysis_date(row: dict[str, str], grain: str) -> date | None:
    if grain == "weekly":
        return parse_date_value(
            row.get("week_start_date", "")
            or row.get("cleaned_date", "")
            or row.get("session_date_clean", "")
        )
    return parse_date_value(
        row.get("session_date_clean", "")
        or row.get("cleaned_date", "")
        or row.get("week_start_date", "")
    )


def build_team_dashboard(args: argparse.Namespace) -> None:
    excluded_injury_rows = {
        clean_text(item)
        for item in clean_text(getattr(args, "exclude_injury_rows", "")).split(",")
        if clean_text(item)
    }
    exposure_rows = [
        row
        for row in read_rows(Path(args.exposure_file))
        if clean_text(row.get("cleaning_action")) == "include"
    ]
    if not exposure_rows:
        raise SystemExit("no included exposure rows found")

    grains = {
        clean_text(row.get("exposure_grain")) or "unknown"
        for row in exposure_rows
    }
    primary_grain = grains.pop() if len(grains) == 1 else "mixed"
    exposure_dates = [
        parsed
        for row in exposure_rows
        if (parsed := exposure_analysis_date(row, primary_grain)) is not None
    ]
    if not exposure_dates:
        raise SystemExit("no valid exposure date values found")

    coverage_start = min(exposure_dates)
    coverage_end = max(exposure_dates) + (timedelta(days=6) if primary_grain == "weekly" else timedelta())
    hours = sum(parse_float(row.get("minutes_total_clean")) or 0 for row in exposure_rows) / 60
    distance_m = sum(parse_float(row.get("distance_total_m_clean")) or 0 for row in exposure_rows)
    players = {row.get("player_uid") for row in exposure_rows if clean_text(row.get("player_uid"))}
    exposure_periods = sorted({date.isoformat() for date in exposure_dates})

    exposure_by_month: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"month": "", "exposure_hours": 0.0, "distance_km": 0.0}
    )
    for row in exposure_rows:
        exposure_date = exposure_analysis_date(row, primary_grain)
        if exposure_date is None:
            continue
        key = exposure_date.strftime("%Y-%m")
        exposure_by_month[key]["month"] = month_label(exposure_date)
        exposure_by_month[key]["exposure_hours"] += (parse_float(row.get("minutes_total_clean")) or 0) / 60
        exposure_by_month[key]["distance_km"] += (parse_float(row.get("distance_total_m_clean")) or 0) / 1000

    injury_source_rows = read_rows(Path(args.injury_file))
    included_injury_source_rows = []
    injury_rows = []
    for index, row in enumerate(injury_source_rows, start=2):
        if str(index) in excluded_injury_rows:
            continue
        injured_at = parse_date_value(row.get("Date Injured", ""))
        if injured_at is None or injured_at < coverage_start or injured_at > coverage_end:
            continue
        days_lost = parse_int(row.get("Days Injured", ""))
        closed = clean_text(row.get("is_injury_closed")) != "0"
        band_key, band_label = severity_band(days_lost, closed)
        filled_row = filled_injury_export_row(row)
        included_injury_source_rows.append(row)
        injury_rows.append(
            {
                **row,
                "Occasion category": filled_row["Occasion category"],
                "Match Type": filled_row["Match Type"],
                "Body Part": filled_row["Body Part"],
                "Injury Tissue Type/s": filled_row["Injury Tissue Type/s"],
                "injured_at": injured_at,
                "days_lost": days_lost or 0,
                "is_time_loss": (days_lost or 0) > 0,
                "severity_band_key": band_key,
                "severity_band_label": band_label,
            }
        )

    time_loss_rows = [row for row in injury_rows if row["is_time_loss"]]
    days_lost_total = sum(row["days_lost"] for row in time_loss_rows)
    mean_severity = days_lost_total / len(time_loss_rows) if time_loss_rows else None
    sorted_days = sorted(row["days_lost"] for row in time_loss_rows)
    median_severity = None
    if sorted_days:
        midpoint = len(sorted_days) // 2
        median_severity = (
            sorted_days[midpoint]
            if len(sorted_days) % 2
            else (sorted_days[midpoint - 1] + sorted_days[midpoint]) / 2
        )

    injuries_by_month: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"time_loss_injuries": 0, "days_lost": 0}
    )
    for row in time_loss_rows:
        key = row["injured_at"].strftime("%Y-%m")
        injuries_by_month[key]["time_loss_injuries"] += 1
        injuries_by_month[key]["days_lost"] += row["days_lost"]

    monthly = []
    for key in sorted(set(exposure_by_month) | set(injuries_by_month)):
        exposure = exposure_by_month[key]
        injuries = injuries_by_month[key]
        month_hours = exposure["exposure_hours"]
        monthly.append(
            {
                "month": exposure.get("month") or month_label(datetime.strptime(key, "%Y-%m").date()),
                "exposure_hours": rounded(month_hours),
                "distance_km": rounded(exposure["distance_km"]),
                "time_loss_injuries": injuries["time_loss_injuries"],
                "days_lost": injuries["days_lost"],
                "incidence_per_1000h": rounded(
                    rate_per_1000(injuries["time_loss_injuries"], month_hours)
                ),
                "burden_per_1000h": rounded(rate_per_1000(injuries["days_lost"], month_hours)),
            }
        )

    severity_groups: dict[str, dict[str, Any]] = {}
    for row in injury_rows:
        key = row["severity_band_key"]
        group = severity_groups.setdefault(
            key,
            {
                "key": key,
                "label": row["severity_band_label"],
                "recorded_injuries": 0,
                "time_loss_injuries": 0,
                "days_lost": 0,
            },
        )
        group["recorded_injuries"] += 1
        if row["is_time_loss"]:
            group["time_loss_injuries"] += 1
            group["days_lost"] += row["days_lost"]

    setting_split = [
        {
            "label": item["label"],
            "time_loss_injuries": item["time_loss_injuries"],
            "days_lost": item["days_lost"],
            "mean_severity_days": item["mean_severity_days"],
        }
        for item in build_group_rows(time_loss_rows, "Occasion category", hours)
    ]

    grain_label = {
        "weekly": "weekly",
        "session": "session-level",
        "mixed": "mixed-grain",
    }.get(primary_grain, "unknown-grain")
    monthly_basis = (
        f"Monthly exposure is assigned to the week-start month because {args.team} reports weekly exposure."
        if primary_grain == "weekly"
        else "Monthly exposure is assigned to the cleaned exposure-date month."
    )
    setting_limitation = (
        f"{args.team} exposure is weekly, so match and training incidence cannot be split until setting-specific exposure denominators are approved."
        if primary_grain == "weekly"
        else "Setting-specific rates are not split until setting-specific exposure denominators are approved."
    )

    dashboard = {
        "generated_at": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "team": args.team,
        "season": args.season,
        "analysis_window": {
            "start": coverage_start.isoformat(),
            "end": coverage_end.isoformat(),
            "basis": f"{args.team} exposure coverage window from included {grain_label} exposure rows",
        },
        "source_files": {
            "injury": str(args.injury_file),
            "exposure": str(args.exposure_file),
        },
        "method": [
            "Headline injury metrics use time-loss injuries only: Days Injured > 0.",
            "Incidence = time-loss injuries / exposure hours * 1000.",
            "Severity = mean and median days lost per time-loss injury.",
            "Burden = days lost / exposure hours * 1000.",
            f"Exposure hours = sum(minutes_total_clean) / 60 for included {grain_label} exposure rows.",
            monthly_basis,
            "IOC-aligned body-location, tissue/pathology, and severity labels come from the accepted V2 mapping.",
            f"Adjudicated duplicate standardised rows excluded from this aggregate: {', '.join(sorted(excluded_injury_rows))}."
            if excluded_injury_rows
            else "No adjudicated duplicate injury rows were excluded from this aggregate.",
        ],
        "coverage": {
            "exposure_rows": len(exposure_rows),
            "exposed_players": len(players),
            "weeks": len(exposure_periods) if primary_grain == "weekly" else 0,
            "exposure_periods": len(exposure_periods),
            "exposure_grain": primary_grain,
            "hours": rounded(hours),
            "distance_km": rounded(distance_m / 1000),
            "included_exposure_status": "included",
            "scope_status": "scope_unknown_included",
        },
        "headline": [
            {
                "key": "recorded_injuries",
                "label": "Recorded injuries in coverage window",
                "value": len(injury_rows),
                "unit": "injuries",
                "formula": "count(injury rows with Date Injured inside exposure coverage window)",
            },
            {
                "key": "time_loss_injuries",
                "label": "Time-loss injuries",
                "value": len(time_loss_rows),
                "unit": "injuries",
                "formula": "count(injury rows where Days Injured > 0)",
            },
            {
                "key": "incidence_per_1000h",
                "label": "Incidence",
                "value": rounded(rate_per_1000(len(time_loss_rows), hours)),
                "unit": "per 1,000 player-hours",
                "numerator": len(time_loss_rows),
                "denominator": rounded(hours),
                "formula": "time-loss injuries / exposure hours * 1000",
            },
            {
                "key": "severity_mean_days",
                "label": "Mean severity",
                "value": rounded(mean_severity),
                "unit": "days lost per injury",
                "numerator": days_lost_total,
                "denominator": len(time_loss_rows),
                "formula": "days lost / time-loss injuries",
            },
            {
                "key": "severity_median_days",
                "label": "Median severity",
                "value": rounded(median_severity),
                "unit": "days lost per injury",
                "formula": "median(Days Injured) for time-loss injuries",
            },
            {
                "key": "burden_per_1000h",
                "label": "Burden",
                "value": rounded(rate_per_1000(days_lost_total, hours)),
                "unit": "days lost per 1,000 player-hours",
                "numerator": days_lost_total,
                "denominator": rounded(hours),
                "formula": "days lost / exposure hours * 1000",
            },
        ],
        "setting_split": setting_split,
        "monthly": monthly,
        "body_locations": build_group_rows(time_loss_rows, "Body Part", hours, limit=10),
        "injury_types": build_group_rows(time_loss_rows, "Injury Tissue Type/s", hours, limit=10),
        "severity_distribution": sorted(
            severity_groups.values(),
            key=lambda item: [
                "zero_days_medical_attention_only",
                "one_day",
                "two_to_three_days",
                "four_to_seven_days",
                "eight_to_twenty_eight_days",
                "greater_than_twenty_eight_days",
                "unknown_or_censored",
            ].index(item["key"]),
        ),
        "prior_season": {
            "season": "2023-24",
            "status": "not_loaded_in_v2",
            "note": f"No {args.team} prior-season injury and exposure denominator pair exists in this V2 workspace, so the dashboard leaves comparison blank rather than mixing in legacy report figures.",
        },
        "limitations": [
            setting_limitation,
            f"Adjudicated duplicate standardised row exclusions applied: {', '.join(sorted(excluded_injury_rows))}."
            if excluded_injury_rows
            else "No adjudicated duplicate injury row exclusions applied.",
            "This aggregate artifact is local and draft; a hosted reporting table or view should be created only after explicit approval of the live Supabase target.",
        ],
    }

    if dashboard["coverage"]["hours"] <= 0:
        raise SystemExit("exposure hours must be positive")
    if dashboard["headline"][2]["value"] is None or dashboard["headline"][5]["value"] is None:
        raise SystemExit("headline rates were not calculated")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(dashboard, indent=2) + "\n")
    analysis_output = clean_text(getattr(args, "analysis_output", ""))
    if analysis_output:
        fieldnames = (list(injury_source_rows[0]) if injury_source_rows else []) + [
            field for field in ANALYSIS_EXPORT_ORIGIN_FIELDS if not injury_source_rows or field not in injury_source_rows[0]
        ]
        write_rows(
            Path(analysis_output),
            [filled_injury_export_row(row) for row in included_injury_source_rows],
            fieldnames,
        )
    print(
        json.dumps(
            {
                "output": str(output),
                "analysis_output": analysis_output or None,
                "team": args.team,
                "season": args.season,
            },
            indent=2,
        )
    )


def build_munster_dashboard(args: argparse.Namespace) -> None:
    build_team_dashboard(args)


def quiet_call(func: Any, args: argparse.Namespace) -> None:
    with contextlib.redirect_stdout(io.StringIO()):
        func(args)


def self_check(args: argparse.Namespace) -> None:
    params = SqlParams()
    assert params.text("value") == "(select value #>> '{}' from _pipeline_params where idx = 1)"
    assert params.jsonb({"key": "value"}) == "(select value from _pipeline_params where idx = 2)"
    assert params.values == ["value", {"key": "value"}]

    assert parse_flexible_date("10/7/24").date().isoformat() == "2024-10-07"
    assert exposure_scope_status({}) == ("scope_unknown_included", "blank_scope_fields_retained")
    assert exposure_scope_status({"Competition": "academy"})[0] == "out_of_scope_explicit"
    assert severity_category(10, True)[0] == "eight_to_twenty_eight_days"
    assert contact_context({"Is Contact": "NA", "Injury Tissue Type/s": "Muscle Strain/Spasm", "Nature of onset": "Acute"}) == (
        "non_contact",
        "inferred_from_acute_muscle_strain",
    )
    assert activity_context({"Occasion category": "match", "Match Type": "URC"}) == (
        "urc_match",
        "mapped_from_occasion_and_match_type",
    )
    assert injury_type({"Injury Tissue Type/s": "Other Pain/ unspecified", "Orchard Code": "NJPX"}) == (
        "joint_sprain",
        "mapped_from_orchard_code_ioc_pathology",
    )
    assert body_location({"Body Part": "Lower leg"}) == ("lower_leg", "preserved_controlled_body_part")
    assert injury_type({"Injury Tissue Type/s": "Muscle injury"}) == (
        "muscle_injury",
        "preserved_controlled_injury_tissue_type",
    )
    assert set(BODY_LOCATION_LABELS.values()) == CONTROLLED_BODY_LOCATION_LABELS
    assert set(INJURY_TYPE_LABELS.values()) == CONTROLLED_INJURY_TYPE_LABELS
    unknown_export = filled_injury_export_row({"Date Injured": "02/07/2024", "Days Injured": "0"})
    assert unknown_export["Body Part"] == "Unknown"
    assert unknown_export["Injury Tissue Type/s"] == "Unknown"
    assert unknown_export["Fit for selection"] == "Unknown"
    assert rate_per_1000(1, 2) == 500

    locator = {field: "fixture" for field in LOCATOR_FIELDS}
    locator["standardised_row_number"] = "2"
    state, events = build_processing_state(
        {
            **locator,
            "player_uid": "player_1",
            "injury_uid": "injury_1",
            "Date Injured": "02/07/2024",
            "Days Injured": "10",
            "Confirmed Return Date": "",
            "is_injury_closed": "1",
            "Occasion category": "Game",
            "Match Type": "United Rugby Championship",
            "Is Contact": "Contact",
            "Recurrence": "First Episode",
            "Body Part": "Ankle",
            "Orchard Code": "",
            "Injury Tissue Type/s": "Muscle",
            "Illness Code": "",
            "Description": "",
        },
        window_start=datetime(2024, 7, 1),
        window_end=datetime(2025, 6, 30),
        duplicate_signature_rows=set(),
    )
    assert state["analysis_eligibility_status"] == "included_pending_protocol"
    assert state["derived_return_date"] == "2024-07-12"
    assert state["activity_context"] == "urc_match"
    assert state["body_location"] == "ankle"
    assert any(event["field_name"] == "derived_return_date" for event in events)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        exposure_source = tmp_path / "exposure.csv"
        exposure_clean = tmp_path / "exposure_clean.csv"
        exposure_qc = tmp_path / "exposure_qc.json"
        write_rows(
            exposure_source,
            [
                {
                    "Team": "Team I",
                    "Competition": "",
                    "session type": "",
                    "If match, surface?": "",
                    "name": "player",
                    "session date": "07/01/2024",
                    "minutes total": "120",
                    "distance total": "10000",
                    "player_uid": "player_1",
                    "source_row_number": "2",
                },
                {
                    "Team": "Team I",
                    "Competition": "academy",
                    "session type": "",
                    "If match, surface?": "",
                    "name": "player",
                    "session date": "07/08/2024",
                    "minutes total": "120",
                    "distance total": "10000",
                    "player_uid": "player_1",
                    "source_row_number": "3",
                },
            ],
            [
                "Team",
                "Competition",
                "session type",
                "If match, surface?",
                "name",
                "session date",
                "minutes total",
                "distance total",
                "player_uid",
                "source_row_number",
            ],
        )
        quiet_call(
            clean_exposure,
            argparse.Namespace(
                file=str(exposure_source),
                output=str(exposure_clean),
                qc_output=str(exposure_qc),
                manifest=None,
            ),
        )
        cleaned = read_rows(exposure_clean)
        assert [row["cleaning_action"] for row in cleaned] == ["include", "exclude_from_primary"]
        assert cleaned[0]["week_start_date"] == "2024-07-01"
        assert json.loads(exposure_qc.read_text())["included_minutes_total"] == 120.0

        injury_source = tmp_path / "injury.csv"
        dashboard_output = tmp_path / "dashboard.json"
        write_rows(
            injury_source,
            [
                {
                    "Date Injured": "02/07/2024",
                    "Days Injured": "10",
                    "is_injury_closed": "1",
                    "Occasion category": "Game",
                    "Body Part": "Ankle",
                    "Injury Tissue Type/s": "Muscle",
                }
            ],
            [
                "Date Injured",
                "Days Injured",
                "is_injury_closed",
                "Occasion category",
                "Body Part",
                "Injury Tissue Type/s",
            ],
        )
        quiet_call(
            build_team_dashboard,
            argparse.Namespace(
                team="Self Check",
                season="2024-25",
                injury_file=str(injury_source),
                exposure_file=str(exposure_clean),
                output=str(dashboard_output),
            ),
        )
        dashboard = json.loads(dashboard_output.read_text())
        assert dashboard["coverage"]["hours"] == 2.0
        assert dashboard["headline"][2]["value"] == 500.0
        assert dashboard["headline"][5]["value"] == 5000.0
        session_exposure_source = tmp_path / "session_exposure.csv"
        session_exposure_clean = tmp_path / "session_exposure_clean.csv"
        session_exposure_qc = tmp_path / "session_exposure_qc.json"
        write_rows(
            session_exposure_source,
            [
                {
                    "Team": "Team A",
                    "Competition": "",
                    "session type": "",
                    "If match, surface?": "",
                    "name": "player",
                    "session date": "07/02/2024",
                    "minutes total": "60",
                    "distance total": "8000",
                    "player_uid": "player_1",
                    "source_row_number": "2",
                }
            ],
            [
                "Team",
                "Competition",
                "session type",
                "If match, surface?",
                "name",
                "session date",
                "minutes total",
                "distance total",
                "player_uid",
                "source_row_number",
            ],
        )
        quiet_call(
            clean_exposure,
            argparse.Namespace(
                file=str(session_exposure_source),
                output=str(session_exposure_clean),
                qc_output=str(session_exposure_qc),
                manifest=None,
            ),
        )
        quiet_call(
            build_team_dashboard,
            argparse.Namespace(
                team="Session Check",
                season="2024-25",
                injury_file=str(injury_source),
                exposure_file=str(session_exposure_clean),
                output=str(dashboard_output),
            ),
        )
        session_dashboard = json.loads(dashboard_output.read_text())
        assert session_dashboard["coverage"]["exposure_grain"] == "session"
        assert session_dashboard["coverage"]["weeks"] == 0
        assert session_dashboard["analysis_window"]["end"] == "2024-07-02"

    print("self-check passed")


def main() -> None:
    parser = argparse.ArgumentParser(prog="pipeline")
    subcommands = parser.add_subparsers(required=True)

    ingest_parser = subcommands.add_parser("ingest")
    ingest_parser.add_argument("--team", required=True)
    ingest_parser.add_argument("--season", required=True)
    ingest_parser.add_argument("--file", required=True)
    ingest_parser.add_argument("--manifest")
    ingest_parser.set_defaults(func=ingest)

    prepare_parser = subcommands.add_parser("prepare-intake")
    prepare_parser.add_argument("--team", required=True)
    prepare_parser.add_argument("--season", required=True)
    prepare_parser.add_argument("--file", required=True)
    prepare_parser.add_argument("--source-file", required=True)
    prepare_parser.add_argument("--output", required=True)
    prepare_parser.add_argument("--manifest")
    prepare_parser.add_argument("--source-sheet", default="file")
    prepare_parser.add_argument("--player-id-column", default="PlayerID")
    prepare_parser.set_defaults(func=prepare_intake)

    export_parser = subcommands.add_parser("export-xlsx-sheet")
    export_parser.add_argument("--file", required=True)
    export_parser.add_argument("--sheet", default="Standardized Data")
    export_parser.add_argument("--output", required=True)
    export_parser.set_defaults(func=export_xlsx_sheet)

    exposure_parser = subcommands.add_parser("prepare-exposure")
    exposure_parser.add_argument("--team", default="Munster")
    exposure_parser.add_argument("--season", default="2024-25")
    exposure_parser.add_argument(
        "--file",
        default="/Users/abdelbabiker/Desktop/URC/Munster/Munster standardised_Exposure data.xlsx",
    )
    exposure_parser.add_argument("--sheet", default="Standardized Data")
    exposure_parser.add_argument(
        "--codebook",
        default="/Users/abdelbabiker/Desktop/URC/Munster/mapping-codebook-Munster Exp.csv",
    )
    exposure_parser.add_argument(
        "--output",
        default="data/intake/2024-25/munster/munster_exposure_intake_locator_enriched_2024-25.csv",
    )
    exposure_parser.add_argument(
        "--qc-output",
        default="data/intake/2024-25/munster/munster_exposure_qc_2024-25.json",
    )
    exposure_parser.add_argument(
        "--manifest",
        default="data/intake/2024-25/munster/intake_manifest.draft.json",
    )
    exposure_parser.add_argument("--player-column", default="name")
    exposure_parser.add_argument("--date-column", default="session date")
    exposure_parser.add_argument("--minutes-column", default="minutes total")
    exposure_parser.add_argument("--distance-column", default="distance total")
    exposure_parser.set_defaults(func=prepare_exposure)

    clean_exposure_parser = subcommands.add_parser("clean-exposure")
    clean_exposure_parser.add_argument(
        "--file",
        default="data/intake/2024-25/munster/munster_exposure_intake_locator_enriched_2024-25.csv",
    )
    clean_exposure_parser.add_argument(
        "--output",
        default="data/intake/2024-25/munster/munster_exposure_cleaned_2024-25.csv",
    )
    clean_exposure_parser.add_argument(
        "--qc-output",
        default="data/intake/2024-25/munster/munster_exposure_cleaning_qc_2024-25.json",
    )
    clean_exposure_parser.add_argument(
        "--manifest",
        default="data/intake/2024-25/munster/intake_manifest.draft.json",
    )
    clean_exposure_parser.set_defaults(func=clean_exposure)

    process_exposure_parser = subcommands.add_parser("process-exposure")
    process_exposure_parser.add_argument("--team", default="Munster")
    process_exposure_parser.add_argument("--season", default="2024-25")
    process_exposure_parser.add_argument(
        "--file",
        default="data/intake/2024-25/munster/munster_exposure_cleaned_2024-25.csv",
    )
    process_exposure_parser.add_argument("--step-name", default="exposure_cleaning")
    process_exposure_parser.add_argument("--step-version", default="0.1.0")
    process_exposure_parser.add_argument("--version-number", type=int, default=101)
    process_exposure_parser.set_defaults(func=process_exposure)

    fixture_exposure_parser = subcommands.add_parser("build-fixture-exposure")
    fixture_exposure_parser.add_argument(
        "--file",
        default="/Users/abdelbabiker/Downloads/Injury & Exposure Data Master Sheet - Analysis - Fixtures.csv",
    )
    fixture_exposure_parser.add_argument(
        "--preserved-output",
        default="data/intake/2024-25/fixtures/urc_fixtures_2024_25.downloaded.csv",
    )
    fixture_exposure_parser.add_argument(
        "--fixture-output",
        default="data/intake/2024-25/fixtures/urc_fixtures_2024_25.corrected.csv",
    )
    fixture_exposure_parser.add_argument(
        "--exposure-output",
        default="data/reporting/urc_team_exposure_2024-25.csv",
    )
    fixture_exposure_parser.add_argument(
        "--qc-output",
        default="data/reporting/urc_fixture_exposure_qc_2024-25.json",
    )
    fixture_exposure_parser.add_argument(
        "--total-exposure-file",
        default="/Users/abdelbabiker/Downloads/Exposure_metrics___by_team.csv",
    )
    fixture_exposure_parser.add_argument("--total-team-column", default="Team")
    fixture_exposure_parser.add_argument("--total-hours-column", default="hours_total")
    fixture_exposure_parser.add_argument("--player-hours-per-team-match", type=float, default=20.0)
    fixture_exposure_parser.set_defaults(func=build_fixture_exposure)

    qa_parser = subcommands.add_parser("qa-intake")
    qa_parser.add_argument("--file", required=True)
    qa_parser.add_argument("--output")
    qa_parser.add_argument("--window-start", default="2024-07-01")
    qa_parser.add_argument("--window-end", default="2025-06-30")
    qa_parser.set_defaults(func=qa_intake)

    process_parser = subcommands.add_parser("process-intake")
    process_parser.add_argument("--team", required=True)
    process_parser.add_argument("--season", required=True)
    process_parser.add_argument("--file", required=True)
    process_parser.add_argument("--window-start", default="2024-07-01")
    process_parser.add_argument("--window-end", default="2025-06-30")
    process_parser.add_argument("--step-name", default="intake_first_pass")
    process_parser.add_argument("--step-version", default="0.1.0")
    process_parser.add_argument("--version-number", type=int, default=1)
    process_parser.set_defaults(func=process_intake)

    trace_parser = subcommands.add_parser("trace-row")
    trace_parser.add_argument("--file", required=True)
    trace_parser.add_argument("--row-number", type=int, required=True)
    trace_parser.add_argument("--include-source", action="store_true")
    trace_parser.set_defaults(func=trace_row)

    run_parser = subcommands.add_parser("run")
    run_parser.add_argument("--team", required=True)
    run_parser.add_argument("--season", required=True)
    run_parser.add_argument("--step", required=True)
    run_parser.set_defaults(func=run_step)

    release_parser = subcommands.add_parser("release")
    release_parser.add_argument("--team", required=True)
    release_parser.add_argument("--season", required=True)
    release_parser.add_argument("--dashboard-file")
    release_parser.set_defaults(func=release)

    adjudicate_duplicate_parser = subcommands.add_parser("adjudicate-duplicate-exclusion")
    adjudicate_duplicate_parser.add_argument("--team", required=True)
    adjudicate_duplicate_parser.add_argument("--season", required=True)
    adjudicate_duplicate_parser.add_argument("--file", required=True)
    adjudicate_duplicate_parser.add_argument("--row-number", type=int, required=True)
    adjudicate_duplicate_parser.add_argument("--duplicate-of", type=int, required=True)
    adjudicate_duplicate_parser.add_argument("--rationale", required=True)
    adjudicate_duplicate_parser.add_argument("--step-version", default="0.1.0")
    adjudicate_duplicate_parser.add_argument("--version-number", type=int, default=2)
    adjudicate_duplicate_parser.set_defaults(func=adjudicate_duplicate_exclusion)

    def add_team_dashboard_args(command: argparse.ArgumentParser) -> None:
        command.add_argument("--team", default="Munster")
        command.add_argument("--season", default="2024-25")
        command.add_argument(
            "--injury-file",
            default="data/intake/2024-25/munster/munster_filled_standardised_2024-25.csv",
        )
        command.add_argument(
            "--exposure-file",
            default="data/intake/2024-25/munster/munster_exposure_cleaned_2024-25.csv",
        )
        command.add_argument(
            "--output",
            default="data/reporting/munster_dashboard_2024-25.json",
        )
        command.add_argument("--exclude-injury-rows", default="")
        command.add_argument("--analysis-output", default="")

    team_dashboard_parser = subcommands.add_parser("build-team-dashboard")
    add_team_dashboard_args(team_dashboard_parser)
    team_dashboard_parser.set_defaults(func=build_team_dashboard)

    dashboard_parser = subcommands.add_parser("build-munster-dashboard")
    add_team_dashboard_args(dashboard_parser)
    dashboard_parser.set_defaults(func=build_munster_dashboard)

    check_parser = subcommands.add_parser("self-check")
    check_parser.set_defaults(func=self_check)

    alias_parser = subcommands.add_parser("validate-alias-map")
    alias_parser.add_argument("--codebook", default=str(TEAM_ALIAS_CODEBOOK_PATH))
    alias_parser.set_defaults(func=validate_alias_map)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
