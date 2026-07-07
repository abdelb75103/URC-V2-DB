from __future__ import annotations

import argparse
import contextlib
import csv
import difflib
import hashlib
import io
import json
import os
import re
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

EDINBURGH_URC_OPPONENTS = [
    "benetton",
    "bulls",
    "cardiff",
    "connacht",
    "dragons",
    "glasgow",
    "leinster",
    "lions",
    "munster",
    "ospreys",
    "scarlets",
    "sharks",
    "stormers",
    "ulster",
    "zebre",
]
EDINBURGH_EXPOSURE_SCOPE_RULE_VERSION = "edinburgh_exposure_scope_2026-07-07_v2"
EXPOSURE_CANONICAL_SCHEMA_VERSION = "exposure_core_2026-07-07_v1"
INJURY_PROCESSING_RULE_VERSION = "injury_processing_2026-07-07_v1"
EXPOSURE_PROCESSING_RULE_VERSION = "exposure_processing_2026-07-07_v1"
URC_OPPONENT_FUZZY_CUTOFF = 0.78

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
    "Illness Code",
    "Injury Tissue Type/s",
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

INJURY_DIAGNOSIS_TEXT_PATTERNS = [
    ("brain_spinal_cord_injury", ["concussion"]),
    ("tendon_rupture", ["tendon rupture"]),
    ("bone_stress_injury", ["stress fracture", "stress injury", "stress reaction", "shin splints"]),
    ("bone_contusion", ["bone contusion"]),
    ("fracture", ["fractur"]),
    ("peripheral_nerve_injury", ["nerve", "brachial plexus", "burner/stinger"]),
    ("cartilage_injury", ["osteochondral", "cartilage", "labral", "labrum", "meniscal"]),
    ("arthritis", ["osteoarthritis", "arthritis"]),
    ("tendinopathy", ["tendinopathy", "tendon injury", "plantar fasci", "plantar heel pain", "tendon strain"]),
    ("bursitis", ["bursitis"]),
    ("synovitis_capsulitis", ["synovitis", "impingement"]),
    ("chronic_instability", ["instability"]),
    ("joint_sprain", ["sprain", "ligament", "dislocation", "subluxation", "plantar plate disruption", "hyperextension", "acl", "mcl", "pcl", "ucl"]),
    ("muscle_contusion", ["muscle haematoma", "muscle contusion"]),
    ("laceration", ["laceration"]),
    ("abrasion", ["abrasion"]),
    ("contusion_superficial", ["contusion", "haematoma", "bruis", "head impact", "head/neck impact"]),
    ("muscle_injury", ["muscle", "strain", "hamstring", "gastroc", "soleus", "rectus femoris", "quadriceps", "pectoralis"]),
    ("nonspecific", ["disc", "pain/injury", "pain undiagnosed", "not otherwise specified", "functional pain", "spinal injury", "soreness", "overuse injuries", "perforated ear drum"]),
]

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


def sha256_json(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def without_keys(value: object, keys: set[str]) -> object:
    if isinstance(value, dict):
        return {
            key: without_keys(item, keys)
            for key, item in value.items()
            if key not in keys
        }
    if isinstance(value, list):
        return [without_keys(item, keys) for item in value]
    return value


def is_protected_team_alias_value(value: str) -> bool:
    return bool(re.fullmatch(r"Team [A-Z]", clean_text(value)))


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


def write_analysis_source_workbook(
    path: Path,
    rows: list[dict[str, str]],
    fieldnames: list[str],
    excluded_row_numbers: set[str],
    filled_columns_by_row_number: dict[str, set[str]],
) -> None:
    try:
        from openpyxl import Workbook, load_workbook
        from openpyxl.styles import Font
        from openpyxl.utils import get_column_letter
    except ImportError as exc:
        raise SystemExit("openpyxl is required to write analysis source workbooks") from exc

    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))

    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "analysis_source"
    sheet.append(fieldnames)
    sheet.freeze_panes = "A2"
    sheet.auto_filter.ref = f"A1:{get_column_letter(len(fieldnames))}{len(rows) + 1}"
    for cell in sheet[1]:
        cell.font = Font(bold=True)

    red_font = Font(color="C00000")
    green_font = Font(color="008000")
    for output_row_number, row in enumerate(rows, start=2):
        sheet.append([row.get(field, "") for field in fieldnames])
        source_row_number = str(output_row_number)
        excluded = source_row_number in excluded_row_numbers
        filled_columns = filled_columns_by_row_number.get(source_row_number, set())
        for column_index, field in enumerate(fieldnames, start=1):
            cell = sheet.cell(row=output_row_number, column=column_index)
            if field in {"Date Injured", "Confirmed Return Date"}:
                cell.number_format = "@"
            if not clean_text(str(cell.value or "")):
                continue
            if excluded:
                cell.font = red_font
            elif field in filled_columns:
                cell.font = green_font

    for column_index, field in enumerate(fieldnames, start=1):
        width = 14 if field in {"Date Injured", "Confirmed Return Date", "Fit For Selection Date"} else 18
        if field in {"Description", "Mechanism Notes"}:
            width = 28
        sheet.column_dimensions[get_column_letter(column_index)].width = width

    workbook.save(path)
    load_workbook(path, read_only=True).close()


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


def parse_flexible_date(value: object, date_order: str = "month-first") -> datetime | None:
    if isinstance(value, datetime):
        return value
    text = clean_text(str(value) if value is not None else "")
    if not text:
        return None
    slash_formats = (
        ("%d/%m/%Y", "%d/%m/%y", "%m/%d/%Y", "%m/%d/%y")
        if date_order == "day-first"
        else ("%m/%d/%Y", "%m/%d/%y", "%d/%m/%Y", "%d/%m/%y")
    )
    for fmt in (*slash_formats, "%Y-%m-%d"):
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


def parse_minutes(value: object) -> float | None:
    parsed = parse_float(value)
    if parsed is not None:
        return parsed
    text = clean_text(str(value) if value is not None else "")
    parts = text.split(":")
    if len(parts) != 3:
        return None
    try:
        hours, minutes, seconds = (float(part) for part in parts)
    except ValueError:
        return None
    return hours * 60 + minutes + seconds / 60


def effective_days_injured_with_origin(row: dict[str, str]) -> tuple[int | None, str]:
    days = parse_int(clean_text(row.get("Days Injured")))
    if days is not None and days >= 0:
        return days, "preserved_source_days_injured"

    injured_at = parse_date_value(row.get("Date Injured", ""))
    returned_at = parse_date_value(row.get("Confirmed Return Date", ""))
    training_days = parse_int(clean_text(row.get("Training Days Missed")))
    if training_days == -1:
        return 0, "mapped_minus_one_training_days_to_same_day_zero"
    if training_days is not None and training_days >= 0:
        if injured_at and returned_at and returned_at >= injured_at:
            calculated_days = max(0, (returned_at - injured_at).days - 1)
            origin = (
                "mapped_from_training_days_missed_date_consistent"
                if calculated_days == training_days
                else "mapped_from_training_days_missed_date_conflict"
            )
            return training_days, origin
        return training_days, "mapped_from_training_days_missed_without_complete_dates"
    if injured_at and returned_at:
        try:
            corrected_return = returned_at.replace(year=returned_at.year + 1)
        except ValueError:
            corrected_return = None
        corrected_days = max(0, (corrected_return - injured_at).days - 1) if corrected_return else -1
        if training_days is not None and training_days < -1 and 0 <= corrected_days <= 90:
            return corrected_days, "corrected_return_year_then_derived_excluding_injury_day"
        if returned_at >= injured_at:
            return max(0, (returned_at - injured_at).days - 1), "derived_from_dates_excluding_injury_day"
    if clean_text(row.get("TimeLoss vs Medical Attention")).lower() == "medical attention":
        return 0, "inferred_zero_from_medical_attention_with_invalid_or_missing_duration"
    return None, "insufficient_duration_evidence"


def effective_days_injured(row: dict[str, str]) -> int | None:
    return effective_days_injured_with_origin(row)[0]


def effective_confirmed_return_date(
    row: dict[str, str], days: int | None, days_origin: str
) -> tuple[date | None, str]:
    injured_at = parse_date_value(row.get("Date Injured", ""))
    returned_at = parse_date_value(row.get("Confirmed Return Date", ""))
    if (
        injured_at
        and days is not None
        and days_origin == "mapped_from_training_days_missed_date_conflict"
    ):
        if days == 0:
            return injured_at, "derived_same_day_return_from_zero_days_date_conflict"
        return injured_at + timedelta(days=days + 1), "derived_from_training_days_missed_date_conflict"
    if returned_at and (not injured_at or returned_at >= injured_at):
        return returned_at, "preserved_source_confirmed_return_date"
    if injured_at and returned_at and days_origin == "corrected_return_year_then_derived_excluding_injury_day":
        try:
            return returned_at.replace(year=returned_at.year + 1), "corrected_source_confirmed_return_year"
        except ValueError:
            pass
    if injured_at and days == 0 and days_origin in {
        "mapped_minus_one_training_days_to_same_day_zero",
        "inferred_zero_from_medical_attention_with_invalid_or_missing_duration",
    }:
        return injured_at, "inferred_same_day_return"
    if injured_at and days is not None:
        offset = days if days_origin == "preserved_source_days_injured" else days + 1
        return injured_at + timedelta(days=offset), "derived_from_date_injured_and_days_definition"
    return None, "insufficient_return_date_evidence"


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


def injury_cohort_exclusion_reasons(row: dict[str, str], expected_team: str = "") -> list[str]:
    reasons = []
    received_in_team = clean_text(row.get("Received/Injured In Team"))
    if expected_team and not is_missing(received_in_team) and received_in_team.casefold() != expected_team.casefold():
        reasons.append("received_or_injured_in_other_team")

    match_type = clean_text(row.get("Match Type")).casefold()
    non_urc_markers = (
        "academy",
        "club",
        "cup",
        "friendly",
        "international",
        "national",
        "premiership",
        "pro team a",
        "super rugby",
        "top 14",
        "u18",
        "u19",
        "u20",
        "u21",
        "under 18",
        "under 19",
        "under 20",
        "under 21",
    )
    if not is_missing(match_type) and any(marker in match_type for marker in non_urc_markers):
        reasons.append("explicit_non_urc_match_type")
    return reasons


def activity_context(row: dict[str, str]) -> tuple[str, str]:
    occasion = clean_text(row.get("Occasion category")).lower()
    match_type = clean_text(row.get("Match Type")).lower()
    if occasion in {"game", "match"} and match_type in {"united rugby championship", "urc"}:
        return "urc_match", "mapped_from_occasion_and_match_type"
    if occasion == "training" or match_type == "training":
        return "training", "mapped_from_occasion_category"
    if occasion in {"game", "match"}:
        return "match", "mapped_from_occasion_category_non_urc_match"
    return "unknown", "insufficient_direct_evidence"


def contact_context(row: dict[str, str]) -> tuple[str, str]:
    value = clean_text(row.get("Is Contact")).lower()
    if value == "contact" or value.startswith("contact ("):
        return "contact", "mapped_from_is_contact"
    if value in {"non-contact", "non-contact trauma", "overuse (gradual onset)", "overuse (sudden onset)"}:
        return "non_contact", "mapped_from_is_contact"
    tissue = clean_text(row.get("Injury Tissue Type/s")).lower()
    onset = clean_text(row.get("Nature of onset")).lower()
    if is_missing(value) and tissue == "muscle strain/spasm" and onset == "acute":
        return "non_contact", "inferred_from_acute_muscle_strain"
    return "unknown", "source_missing_or_unknown"


def recurrence_status(row: dict[str, str]) -> tuple[str, str]:
    value = clean_text(row.get("Recurrence")).lower()
    if value in {"first episode", "new injury (not recurrent)"}:
        return "first_episode", "mapped_from_recurrence"
    if value == "recurrence" or value.endswith(" recurrence"):
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
    if parse_date_value(clean_text(row.get("Confirmed Return Date"))) is not None:
        return True, "mapped_from_confirmed_return_date"
    time_loss = clean_text(row.get("TimeLoss vs Medical Attention")).lower()
    if time_loss == "time loss":
        return False, "unclosed_time_loss_without_return_date"
    if time_loss == "medical attention":
        return True, "mapped_from_medical_attention_only"
    return None, "source_missing_or_unknown"


def effective_orchard_code(row: dict[str, str]) -> str:
    source = clean_text(row.get("Orchard Code"))
    if source:
        return source
    if clean_text(row.get("Problem type")).lower() == "injury":
        return clean_text(row.get("Illness Code"))
    return ""


def body_location(row: dict[str, str]) -> tuple[str, str]:
    orchard_code = effective_orchard_code(row)
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
    source = clean_text(row.get("Problem type")).lower()
    if source in {"injury", "illness"}:
        return source, "mapped_from_problem_type"
    if not is_missing(row.get("Orchard Code")) or not is_missing(row.get("Injury Tissue Type/s")):
        return "injury", "inferred_from_orchard_code_or_injury_type"
    if not is_missing(row.get("Illness Code")):
        return "illness", "inferred_from_illness_code"
    return "unknown", "source_missing_or_unknown"


def injury_type(row: dict[str, str]) -> tuple[str, str]:
    if clean_text(row.get("Problem type")).lower() == "illness":
        return "unknown", "not_applicable_to_illness"
    value = clean_text(row.get("Injury Tissue Type/s")).lower()
    controlled = INJURY_TYPE_LABEL_TO_KEY.get(value)
    if controlled:
        return controlled, "preserved_controlled_injury_tissue_type"
    orchard_code = effective_orchard_code(row).upper()
    if (is_missing(value) or value in {"other pain/ unspecified", "unspecified/crossing"}) and len(orchard_code) >= 2:
        mapped_from_code = ORCHARD_PATHOLOGY_TYPE_MAP.get(orchard_code[1])
        if mapped_from_code:
            return mapped_from_code, "mapped_from_orchard_code_ioc_pathology"
    mapped = INJURY_TYPE_MAP.get(value)
    if mapped:
        return mapped, "mapped_from_injury_tissue_type"
    if "not concussion" in value or "not diagnosed as concussion" in value:
        return "contusion_superficial", "mapped_from_explicit_diagnosis_text_ioc_pathology"
    if "lumbar pain" in value:
        return "nonspecific", "mapped_from_explicit_diagnosis_text_ioc_pathology"
    for injury_key, patterns in INJURY_DIAGNOSIS_TEXT_PATTERNS:
        if any(pattern in value for pattern in patterns):
            return injury_key, "mapped_from_explicit_diagnosis_text_ioc_pathology"
    if len(orchard_code) >= 2:
        mapped_from_code = ORCHARD_PATHOLOGY_TYPE_MAP.get(orchard_code[1])
        if mapped_from_code:
            return mapped_from_code, "mapped_from_orchard_code_ioc_pathology"
    return "unknown", "source_missing_or_unknown"


def prepare_intake(args: argparse.Namespace) -> None:
    standardised_path = Path(args.file)
    source_path = Path(args.source_file)
    output_path = Path(args.output)
    rows = read_rows(standardised_path)
    if source_path.suffix.lower() in {".xlsx", ".xlsm"}:
        _, source_rows = read_xlsx_rows(source_path, args.source_sheet)
        source_row_numbers = [int(row["_source_row_number"]) for row in source_rows]
    else:
        source_rows = read_rows(source_path)
        source_row_numbers = list(range(2, len(source_rows) + 2))
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
    for index, row in enumerate(rows):
        offset = index + 2
        prepared = dict(row)
        prepared.update(
            {
                "source_archive_path": str(source_path),
                "source_file_sha256": source_hash,
                "source_sheet": args.source_sheet,
                "source_row_number": str(source_row_numbers[index]),
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

        parsed_date = parse_flexible_date(row.get(args.date_column), args.date_order)
        if parsed_date is None:
            missing_date_rows.append(source_row_number)
            if clean_cell(row.get(args.date_column)):
                date_parse_failures.append(source_row_number)
        else:
            dates.append(parsed_date)

        minutes = parse_minutes(row.get(args.minutes_column))
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
        "date_order": args.date_order,
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
            "date_order": args.date_order,
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


def urc_game_opponent(description: str) -> str | None:
    bracket = re.search(r"\(([^()]*)\)", description)
    if bracket is None:
        return None
    candidate = re.sub(r"\b(home|away|h|a)\b", "", bracket.group(1).lower())
    candidate = re.sub(r"[^a-z]+", " ", candidate).strip()
    matches = difflib.get_close_matches(
        candidate,
        EDINBURGH_URC_OPPONENTS,
        n=1,
        cutoff=URC_OPPONENT_FUZZY_CUTOFF,
    )
    return matches[0] if matches else None


def exposure_scope_status(row: dict[str, str], team: str = "") -> tuple[str, str]:
    fields = ["Competition", "session type", "If match, surface?", "Training With", "Training Type"]
    text = " ".join(clean_text(row.get(field)).lower() for field in fields).strip()
    if not text:
        return "scope_unknown_included", "blank_scope_fields_retained"
    if any(term in text for term in ["rehab", "return to play", "rtp"]):
        return "out_of_scope_explicit", "explicit_rehab_or_rtp"
    if any(term in text for term in ["international", "national", "scotland"]):
        return "out_of_scope_explicit", "explicit_international_exposure"
    edinburgh = clean_text(team).lower() == "edinburgh"
    if "academy" in text and (not edinburgh or "game" in text):
        return "out_of_scope_explicit", "academy_game"
    if edinburgh and ("warm" in text or "top up" in text):
        return "in_scope_explicit", "warmup_or_topup_retained"
    if edinburgh and re.search(r"\bgame\b", text):
        if urc_game_opponent(text):
            return "in_scope_explicit", "urc_opponent_game"
        return "out_of_scope_explicit", "non_urc_or_unspecified_game"
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
    window_start = parse_date_value(clean_text(getattr(args, "window_start", "")))
    window_end = parse_date_value(clean_text(getattr(args, "window_end", "")))
    if bool(window_start) != bool(window_end):
        raise SystemExit("exposure analysis window requires both --window-start and --window-end")
    if window_start and window_end and window_start > window_end:
        raise SystemExit("exposure analysis window start must not be after its end")

    for row in rows:
        team_alias = clean_text(row.get("Team"))
        grain = "weekly" if team_alias in EXPOSURE_WEEKLY_TEAM_ALIASES else "session"
        grain_counts[grain] = grain_counts.get(grain, 0) + 1
        minutes = parse_minutes(row.get("minutes total"))
        distance = parse_float(row.get("distance total"))
        parsed_date = parse_flexible_date(row.get("session date"), args.date_order)
        if parsed_date:
            dates.append(parsed_date)
        scope_status, scope_reason = exposure_scope_status(row, getattr(args, "team", ""))
        source_hash = row.get("source_row_sha256") or hashlib.sha256(
            json.dumps(
                {
                    key: value
                    for key, value in row.items()
                    if key not in EXPOSURE_LOCATOR_FIELDS + ["player_uid"]
                },
                sort_keys=True,
            ).encode()
        ).hexdigest()
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
        if parsed_date and window_start and window_end:
            period_start = parsed_date.date()
            period_end = period_start + (timedelta(days=6) if grain == "weekly" else timedelta())
            if period_end < window_start or period_start > window_end:
                exclusion_reasons.append("outside_official_analysis_window")

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
        "date_order": args.date_order,
        "team": getattr(args, "team", ""),
        "analysis_window": {
            "start": window_start.isoformat() if window_start else None,
            "end": window_end.isoformat() if window_end else None,
            "weekly_rule": "retain a weekly row when its seven-day period overlaps the analysis window",
        },
        "included_minutes_total": round(included_minutes, 6),
        "included_distance_total_m": round(included_distance, 6),
        "rules": {
            "canonical_schema_version": EXPOSURE_CANONICAL_SCHEMA_VERSION,
            "canonical_columns": {
                "cleaned_date": "ISO date",
                "exposure_grain": "session or weekly",
                "minutes_total_clean": "minutes",
                "distance_total_m_clean": "metres",
                "scope_status": "scope eligibility",
                "scope_reason": "scope rule outcome",
                "cleaning_action": "primary-analysis eligibility",
                "exclusion_reason": "semicolon-delimited controlled reasons",
            },
            "scope_rule_version": (
                EDINBURGH_EXPOSURE_SCOPE_RULE_VERSION
                if clean_text(getattr(args, "team", "")).lower() == "edinburgh"
                else "global_exposure_scope_v0.1.0"
            ),
            "scope": "Exclude explicit international/national-team exposure, academy, and rehab/RTP. Edinburgh additionally excludes game-labelled sessions without a fuzzy-matched URC opponent, except warm-ups and top-ups are retained; blank scope fields are retained as scope_unknown_included.",
            "edinburgh_urc_opponents": EDINBURGH_URC_OPPONENTS if clean_text(getattr(args, "team", "")).lower() == "edinburgh" else [],
            "urc_opponent_fuzzy_cutoff": URC_OPPONENT_FUZZY_CUTOFF,
            "edinburgh_scope_decisions": [
                "exclude all international and national-team exposure",
                "exclude rehab and RTP exposure",
                "exclude all academy games",
                "retain warm-up and top-up exposure",
                "retain game-labelled exposure only when the bracketed opponent fuzzy-matches one of the other 15 URC teams",
            ] if clean_text(getattr(args, "team", "")).lower() == "edinburgh" else [],
            "weekly_teams": EXPOSURE_WEEKLY_TEAM_ALIASES,
            "weekly_exclusions": ["minutes < 5", "minutes > 1100", "distance > 40000m"],
            "session_exclusions": ["minutes < 5", "distance < 200m", "minutes > 220", "distance > 20000m", "distance/minute > 1000"],
            "global_exclusions": ["exact duplicate copy", "missing player/date/minutes/distance", "negative minutes/distance", "minutes = 0 and distance = 0", "outside official analysis window"],
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
            "scope_rule_version": qc["rules"]["scope_rule_version"],
            "canonical_schema_version": qc["rules"]["canonical_schema_version"],
            "analysis_window": qc["analysis_window"],
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
    output_states: list[dict[str, object]] = []
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
        output_states.append(state)
        record_sql.append(
            f"""
            insert into processing.record_versions
              (source_row_id, step_run_id, version_number, record_state, eligibility_status)
            select sr.id, step.id, {version_number}, {params.jsonb(state)},
              {params.text(eligibility)}
            from ingestion.source_rows sr, current_step step
            where sr.raw_record_id = {params.text(raw_id)}
            ;
            """
        )
        audit_reasons = exclusion_reasons or ["exposure_cleaning_applied"]
        for reason in audit_reasons:
            event_sql.append(
                f"""
                insert into audit.record_events
                  (step_run_id, source_row_id, field_name, old_value, new_value, action, reason_code, rationale, rule_version, review_status)
                select step.id, sr.id, 'analysis_eligibility_status', null,
                  {params.jsonb(eligibility)}, {params.text('exclude' if exclusion_reasons else 'classify')},
                  {params.text(reason)},
                  {params.text(f'Exposure eligibility set by controlled reason: {reason}. Source values are preserved.')},
                  {params.text(args.step_version)}, 'not_required'
                from ingestion.source_rows sr, current_step step
                where sr.raw_record_id = {params.text(raw_id)};
                """
            )

    output_hash = sha256_json(output_states)
    exposure_reason_codes = sorted(reason_counts)
    reason_code_sql = "".join(
        f"insert into audit.reason_codes (code, description) values ({params.text(reason)}, {params.text('Exposure exclusion reason emitted by the versioned cleaning protocol.')}) on conflict (code) do update set description = excluded.description;"
        for reason in exposure_reason_codes
    )

    sql = f"""
      insert into audit.reason_codes (code, description) values
        ('exposure_cleaning_applied', 'Exposure cleaning protocol applied and analysis eligibility recorded.'),
        ('exposure_no_exclusions', 'Exposure cleaning protocol produced zero exclusions for this file.'),
        ('exposure_exclusion', 'Exposure row excluded from the primary denominator by a protocol-defined rule.')
      on conflict (code) do update set description = excluded.description;

      {reason_code_sql}

      do $$
      begin
        if (select count(*) from ingestion.source_rows sr join ingestion.source_files sf on sf.id = sr.source_file_id where sf.team = {params.text(args.team)} and sf.season = {params.text(args.season)} and sf.file_sha256 = {params.text(file_hash)}) <> {len(rows)} then
          raise exception 'process-exposure requires every source row to be registered';
        end if;
        if exists (select 1 from processing.record_versions rv join ingestion.source_rows sr on sr.id = rv.source_row_id join ingestion.source_files sf on sf.id = sr.source_file_id where sf.team = {params.text(args.team)} and sf.season = {params.text(args.season)} and sf.file_sha256 = {params.text(file_hash)} and rv.version_number = {version_number}) then
          raise exception 'process-exposure version already exists';
        end if;
      end $$;

      create temp table current_step on commit drop as
      with run as (
        insert into audit.pipeline_runs
          (command, team, season, status, input_hash, output_hash, parameters, ended_at)
        values (
          'process-exposure', {params.text(args.team)}, {params.text(args.season)}, 'succeeded',
          {params.text(file_hash)}, {params.text(output_hash)},
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
          (pipeline_run_id, step_name, step_version, reason_code, input_count, output_count, counts_by_team, input_hash, output_hash, ended_at)
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
          {params.text(file_hash)}, {params.text(output_hash)}, now()
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

        source_date = parse_flexible_date(row.get("date"), args.date_order)
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
        "date_order": args.date_order,
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

        days = effective_days_injured(row)
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
        "return_date_rule": "For Scottish-team rows, Days Injured comes from Training Days Missed and excludes the injury day; source return dates are preserved or corrected only with recorded evidence.",
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
    days_injured, days_injured_origin = effective_days_injured_with_origin(row)
    is_closed, is_closed_origin = injury_closed(row)
    effective_return_date, return_date_origin = effective_confirmed_return_date(
        row, days_injured, days_injured_origin
    )
    derived_return_date = effective_return_date.isoformat() if effective_return_date else None

    activity, activity_origin = activity_context(row)
    contact, contact_origin = contact_context(row)
    recurrence, recurrence_origin = recurrence_status(row)
    severity, severity_origin = severity_category(days_injured, is_closed)
    body, body_origin = body_location(row)
    problem, problem_origin = problem_type(row)
    injury, injury_origin = injury_type(row)
    if derived_return_date and is_closed is False:
        return_date_origin = f"{return_date_origin}_unclosed_censored"

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
            "days_injured": days_injured_origin,
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
    if days_injured is not None:
        events.append(
            {
                "field_name": "days_injured",
                "old_value": row.get("Days Injured", "").strip() or None,
                "new_value": days_injured,
                "action": "infer" if days_injured_origin.startswith("inferred_") else "derive",
                "reason_code": "controlled_inference" if days_injured_origin.startswith("inferred_") else "deterministic_derivation",
                "rationale": f"Effective days injured set by {days_injured_origin}; source duration fields preserved.",
                "review_status": "needs_review" if days_injured_origin.startswith("inferred_") else "not_required",
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
                "rationale": "Same player, date, diagnostic evidence, body part, side, description, and onset appear on more than one ingested row; row retained for review.",
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
    analysis_audit_file = clean_text(getattr(args, "analysis_audit_file", ""))
    analysis_audit_path = Path(analysis_audit_file) if analysis_audit_file else None
    analysis_audit_rows = read_rows(analysis_audit_path) if analysis_audit_path else []
    analysis_exclusions: dict[int, list[dict[str, str]]] = defaultdict(list)
    for event in analysis_audit_rows:
        if event.get("field") != "analysis_eligibility" or event.get("action") != "exclude":
            continue
        try:
            row_number = int(event["standardised_row_number"])
        except (KeyError, ValueError) as exc:
            raise SystemExit("analysis audit contains an invalid standardised row number") from exc
        analysis_exclusions[row_number].append(event)
    known_row_numbers = {int(row["standardised_row_number"]) for row in rows}
    unknown_audit_rows = sorted(set(analysis_exclusions) - known_row_numbers)
    if unknown_audit_rows:
        raise SystemExit(f"analysis audit references unknown rows: {unknown_audit_rows[:20]}")

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
    output_states: list[dict[str, object]] = []
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
        for exclusion in analysis_exclusions.get(source_row_number, []):
            reason = clean_text(exclusion.get("reason"))
            if not reason:
                raise SystemExit(f"analysis audit exclusion on row {source_row_number} has no reason")
            state["analysis_eligibility_status"] = "excluded_from_analysis"
            events.append(
                {
                    "field_name": "analysis_eligibility_status",
                    "old_value": "included_pending_protocol",
                    "new_value": "excluded_from_analysis",
                    "action": "exclude",
                    "reason_code": reason,
                    "rationale": f"Final analysis cohort exclusion: {reason}.",
                    "review_status": exclusion.get("review_status") or "pipeline_decision",
                }
            )
        output_states.append(state)
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
            ;
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

    output_hash = sha256_json(output_states)
    analysis_reason_codes = sorted(
        {
            clean_text(event.get("reason"))
            for events in analysis_exclusions.values()
            for event in events
            if clean_text(event.get("reason"))
        }
    )
    reason_code_sql = "".join(
        f"insert into audit.reason_codes (code, description) values ({params.text(reason)}, {params.text('Final team analysis cohort exclusion emitted by the versioned dashboard pipeline.')}) on conflict (code) do update set description = excluded.description;"
        for reason in analysis_reason_codes
    )
    sql = f"""
      insert into audit.reason_codes (code, description) values
        ('locator_enriched_intake', 'Intake row includes provisional source row locator and stable opaque UIDs.'),
        ('derived_return_date', 'Return date derived from Date Injured plus Days Injured; source value preserved.'),
        ('deterministic_derivation', 'Canonical value derived deterministically from preserved source fields.'),
        ('canonical_mapping', 'Canonical analysis field mapped from source field without overwriting the source value.'),
        ('controlled_inference', 'Canonical analysis field inferred from explicit high-confidence source evidence and marked with origin metadata.'),
        ('candidate_duplicate', 'Candidate duplicate flagged for review; source row retained.'),
        ('outside_provisional_window', 'Row falls outside provisional QC season window or has unparseable injury date; source row retained.')
      on conflict (code) do update set description = excluded.description;

      {reason_code_sql}

      do $$
      begin
        if (select count(*) from ingestion.source_rows sr join ingestion.source_files sf on sf.id = sr.source_file_id where sf.team = {params.text(args.team)} and sf.season = {params.text(args.season)} and sf.file_sha256 = {params.text(file_hash)}) <> {len(rows)} then
          raise exception 'process-intake requires every source row to be registered';
        end if;
        if exists (select 1 from processing.record_versions rv join ingestion.source_rows sr on sr.id = rv.source_row_id join ingestion.source_files sf on sf.id = sr.source_file_id where sf.team = {params.text(args.team)} and sf.season = {params.text(args.season)} and sf.file_sha256 = {params.text(file_hash)} and rv.version_number = {args.version_number}) then
          raise exception 'process-intake version already exists';
        end if;
      end $$;

      create temp table current_step on commit drop as
      with run as (
        insert into audit.pipeline_runs
          (command, team, season, status, input_hash, output_hash, parameters, ended_at)
        values (
          'process-intake', {params.text(args.team)}, {params.text(args.season)}, 'succeeded',
          {params.text(file_hash)}, {params.text(output_hash)},
          {params.jsonb({
            'file': path.name,
            'analysis_audit_file': str(analysis_audit_path) if analysis_audit_path else None,
            'analysis_audit_hash': sha256_file(analysis_audit_path) if analysis_audit_path else None,
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
          (pipeline_run_id, step_name, step_version, reason_code, input_count, output_count, counts_by_team, input_hash, output_hash, ended_at)
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
          {params.text(file_hash)}, {params.text(output_hash)}, now()
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
    excluded_source_fields = {
        clean_text(field)
        for field in clean_text(getattr(args, "exclude_source_fields", "")).split(",")
        if clean_text(field)
    }
    redacted_manifest_keys = {
        clean_text(key)
        for key in clean_text(getattr(args, "redact_manifest_keys", "")).split(",")
        if clean_text(key)
    } | {"current_file_team_aliases", "weekly_team_aliases"}
    redacted_source_value_keys = {
        clean_text(value).casefold()
        for value in clean_text(getattr(args, "redact_source_values", "")).split(",")
        if clean_text(value)
    }
    redacted_source_value_keys.update(
        clean_text(value).casefold() for value in load_fixture_team_aliases().values()
    )
    source_manifest = json.loads(Path(args.manifest).read_text()) if args.manifest else {}
    manifest = {
        "manifest": without_keys(source_manifest, redacted_manifest_keys),
        "original_path": str(path),
        "database_redactions": {
            "excluded_source_fields": sorted(excluded_source_fields),
            "redacted_manifest_keys": sorted(redacted_manifest_keys),
        },
    }

    row_sql = []
    redacted_source_value_count = 0
    params = SqlParams()
    for index, row in enumerate(rows, start=2):
        row_hash = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
        database_values = {}
        for field, value in row.items():
            if field in excluded_source_fields:
                continue
            if (
                clean_text(value).casefold() in redacted_source_value_keys
                or is_protected_team_alias_value(value)
            ):
                database_values[field] = "[REDACTED_PROTECTED_METADATA]"
                redacted_source_value_count += 1
            else:
                database_values[field] = value
        raw_record_id = f"{args.team}:{args.season}:{file_hash[:12]}:{index}"
        row_sql.append(
            f"""
            insert into ingestion.source_rows
              (source_file_id, source_row_number, raw_record_id, row_sha256, source_values)
            select id, {index}, {params.text(raw_record_id)}, {params.text(row_hash)}, {params.jsonb(database_values)}
            from ingestion.source_files
            where team = {params.text(args.team)}
              and season = {params.text(args.season)}
              and file_sha256 = {params.text(file_hash)}
            ;
            """
        )

    manifest["database_redactions"]["redacted_source_value_count"] = redacted_source_value_count
    sql = f"""
      do $$
      begin
        if exists (select 1 from ingestion.source_files where team = {params.text(args.team)} and season = {params.text(args.season)} and file_sha256 = {params.text(file_hash)}) then
          raise exception 'source file is already registered';
        end if;
      end $$;

      with source_file as (
        insert into ingestion.source_files
          (team, season, file_name, file_sha256, file_size_bytes, intake_manifest, row_count)
        values (
          {params.text(args.team)}, {params.text(args.season)}, {params.text(path.name)},
          {params.text(file_hash)}, {path.stat().st_size}, {params.jsonb(manifest)}, {len(rows) if rows else 'null'}
        )
        returning id
      )
      insert into audit.pipeline_runs (command, team, season, status, input_hash, parameters, ended_at)
      values ('ingest', {params.text(args.team)}, {params.text(args.season)}, 'succeeded', {params.text(file_hash)}, {params.jsonb({'file': path.name, 'excluded_source_fields': sorted(excluded_source_fields), 'redacted_manifest_keys': sorted(redacted_manifest_keys), 'redacted_source_value_count': redacted_source_value_count})}, now());
      {"".join(row_sql)}
      do $$
      begin
        if (select count(*) from ingestion.source_rows sr join ingestion.source_files sf on sf.id = sr.source_file_id where sf.team = {params.text(args.team)} and sf.season = {params.text(args.season)} and sf.file_sha256 = {params.text(file_hash)}) <> {len(rows)} then
          raise exception 'ingest row cardinality mismatch';
        end if;
      end $$;
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
    dashboard_path = Path(args.dashboard_file) if args.dashboard_file else (
        Path("content") / "reporting" / f"{args.team.lower()}_dashboard_{args.season}.json"
    )
    if not dashboard_path.exists():
        raise SystemExit(f"dashboard file is required for release: {dashboard_path}")
    dashboard = json.loads(dashboard_path.read_text())
    dashboard_team = clean_text(str(dashboard.get("team", "")))
    expected_team = clean_text(args.team)
    if not (
        dashboard_team.casefold() == expected_team.casefold()
        or dashboard_team.casefold().startswith(expected_team.casefold() + " ")
    ):
        raise SystemExit(
            f"dashboard team mismatch: expected {expected_team!r}, found {dashboard_team!r}"
        )
    if clean_text(str(dashboard.get("season", ""))) != args.season:
        raise SystemExit(
            f"dashboard season mismatch: expected {args.season!r}, found {dashboard.get('season')!r}"
        )
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
    if not dashboard_metrics:
        raise SystemExit("dashboard has no headline metrics")
    source_files = dashboard.get("source_files", {})
    injury_path = Path(str(source_files.get("injury", "")))
    exposure_path = Path(str(source_files.get("exposure", "")))
    if not injury_path.exists() or not exposure_path.exists():
        raise SystemExit("dashboard source files are missing")
    pipeline_evidence = dashboard.get("pipeline_evidence", {})
    injury_hash = clean_text(str(pipeline_evidence.get("injury_file_sha256", "")))
    exposure_hash = clean_text(str(pipeline_evidence.get("exposure_file_sha256", "")))
    audit_hash = clean_text(str(pipeline_evidence.get("standardisation_audit_sha256", "")))
    injury_rule_version = clean_text(
        str(pipeline_evidence.get("injury_processing_rule_version", ""))
    )
    exposure_rule_version = clean_text(
        str(pipeline_evidence.get("exposure_processing_rule_version", ""))
    )
    if not all([injury_hash, exposure_hash, audit_hash, injury_rule_version, exposure_rule_version]):
        raise SystemExit("dashboard pipeline evidence is incomplete")
    if sha256_file(injury_path) != injury_hash or sha256_file(exposure_path) != exposure_hash:
        raise SystemExit("dashboard source file hash mismatch")
    audit_path = Path(str(pipeline_evidence.get("standardisation_audit_file", "")))
    if not audit_path.exists() or sha256_file(audit_path) != audit_hash:
        raise SystemExit("dashboard standardisation audit hash mismatch")
    requires_adjudication = bool(
        dashboard.get("coverage", {})
        .get("injury_cohort_filters", {})
        .get("exclusion_reason_counts", {})
        .get("adjudicated_duplicate", 0)
    )
    adjudicated_duplicate_rows = sorted(
        int(row_number)
        for row_number in dashboard.get("pipeline_evidence", {}).get(
            "adjudicated_duplicate_rows", []
        )
    )
    dashboard_hash = sha256_file(dashboard_path)
    release_metrics = [
        {
            "metric_key": "registered_source_files",
            "metric_label": "Registered source files",
            "value": 2,
            "numerator": 2,
            "denominator": None,
            "unit": "files",
            "coverage_note": "Exact pseudonymised injury and exposure files bound to this approved release",
        },
        *dashboard_metrics,
    ]
    release_hash = sha256_json(release_metrics)
    label = f"{args.team}-{args.season}-{dashboard_hash[:12]}-approved"
    params = SqlParams()
    metric_insert = f"""
      insert into reporting.team_metric_aggregates
        (release_id, team, season, metric_key, metric_label, value, numerator, denominator, unit, coverage_note)
      select current_release.id, {params.text(args.team)}, {params.text(args.season)},
        metric_key, metric_label, value, numerator, denominator, unit, coverage_note
      from current_release,
        jsonb_to_recordset({params.jsonb(release_metrics)}) as metric(
          metric_key text,
          metric_label text,
          value numeric,
          numerator numeric,
          denominator numeric,
          unit text,
          coverage_note text
        );
    """
    sql = f"""
      do $$
      begin
        if not exists (select 1 from supabase_migrations.schema_migrations where version = '20260707110832') then
          raise exception 'release requires migration 20260707110832_latest_release_per_team';
        end if;
        if exists (select 1 from reporting.aggregate_releases where release_label = {params.text(label)}) then
          raise exception 'immutable release already exists';
        end if;
        if (select count(*) from ingestion.source_files where team = {params.text(args.team)} and season = {params.text(args.season)} and file_sha256 in ({params.text(injury_hash)}, {params.text(exposure_hash)})) <> 2 then
          raise exception 'release requires the exact dashboard injury and exposure source files';
        end if;
        if not exists (select 1 from audit.pipeline_runs where team = {params.text(args.team)} and season = {params.text(args.season)} and command = 'process-intake' and status = 'succeeded' and input_hash = {params.text(injury_hash)} and parameters->>'analysis_audit_hash' = {params.text(audit_hash)} and parameters->>'step_version' = {params.text(injury_rule_version)}) then
          raise exception 'release requires a successful process-intake run for the dashboard injury file';
        end if;
        if not exists (select 1 from audit.pipeline_runs where team = {params.text(args.team)} and season = {params.text(args.season)} and command = 'process-exposure' and status = 'succeeded' and input_hash = {params.text(exposure_hash)} and parameters->>'step_version' = {params.text(exposure_rule_version)}) then
          raise exception 'release requires a successful process-exposure run for the dashboard exposure file';
        end if;
        if {str(requires_adjudication).lower()} and not exists (select 1 from audit.pipeline_runs where team = {params.text(args.team)} and season = {params.text(args.season)} and command = 'adjudicate-duplicate-exclusion' and status = 'succeeded' and input_hash = {params.text(injury_hash)}) then
          raise exception 'release requires the dashboard duplicate adjudication run';
        end if;
        if exists (
          select 1
          from jsonb_array_elements_text({params.jsonb(adjudicated_duplicate_rows)}) expected(row_number)
          where not exists (
            select 1
            from audit.adjudications decision
            join ingestion.source_rows sr on sr.id = decision.source_row_id
            join ingestion.source_files sf on sf.id = sr.source_file_id
            where sf.team = {params.text(args.team)}
              and sf.season = {params.text(args.season)}
              and sf.file_sha256 = {params.text(injury_hash)}
              and sr.source_row_number = expected.row_number::integer
              and decision.decision->>'decision' = 'exclude_duplicate'
          )
        ) then
          raise exception 'release requires every dashboard duplicate adjudication decision';
        end if;
      end $$;

      create temp table current_release on commit drop as
      with run as (
        insert into audit.pipeline_runs (command, team, season, status, input_hash, output_hash, parameters, ended_at)
        values ('release', {params.text(args.team)}, {params.text(args.season)}, 'succeeded',
          {params.text(dashboard_hash)}, {params.text(release_hash)},
          {params.jsonb({'release': label, 'dashboard_file': str(dashboard_path), 'dashboard_sha256': dashboard_hash, 'injury_sha256': injury_hash, 'exposure_sha256': exposure_hash, 'standardisation_audit_sha256': audit_hash, 'injury_processing_rule_version': injury_rule_version, 'exposure_processing_rule_version': exposure_rule_version})}, now())
        returning id
      ),
      release as (
        insert into reporting.aggregate_releases (release_label, status, pipeline_run_id, approved_at)
        select {params.text(label)}, 'approved', id, now()
        from run
        returning id
      )
      select id from release;

      {metric_insert}
    """
    run_sql(sql, params.values)
    print(f"released {label} metrics={len(release_metrics)}")


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
    output_hash = sha256_json(state)
    sql = f"""
      insert into audit.reason_codes (code, description) values
        ('duplicate_adjudicated_exclusion', 'Manual review adjudicated a candidate duplicate and excluded it from analysis.')
      on conflict (code) do update set description = excluded.description;

      do $$
      begin
        if not exists (select 1 from ingestion.source_rows where raw_record_id = {params.text(raw_id)}) then
          raise exception 'adjudication source row is not registered';
        end if;
        if not exists (select 1 from processing.record_versions rv join ingestion.source_rows sr on sr.id = rv.source_row_id where sr.raw_record_id = {params.text(raw_id)} and rv.version_number < {args.version_number}) then
          raise exception 'adjudication requires a prior processed record version';
        end if;
        if exists (select 1 from processing.record_versions rv join ingestion.source_rows sr on sr.id = rv.source_row_id where sr.raw_record_id = {params.text(raw_id)} and rv.version_number = {args.version_number}) then
          raise exception 'adjudication version already exists';
        end if;
      end $$;

      create temp table current_step on commit drop as
      with run as (
        insert into audit.pipeline_runs
          (command, team, season, status, input_hash, output_hash, parameters, ended_at)
        values (
          'adjudicate-duplicate-exclusion', {params.text(args.team)}, {params.text(args.season)}, 'succeeded',
          {params.text(file_hash)}, {params.text(output_hash)},
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
          (pipeline_run_id, step_name, step_version, reason_code, input_count, output_count, counts_by_team, input_hash, output_hash, ended_at)
        select id, 'duplicate_adjudication', {params.text(args.step_version)},
          'duplicate_adjudicated_exclusion', 1, 1,
          {params.jsonb({args.team: {'excluded_duplicate_rows': [args.row_number]}})},
          {params.text(file_hash)}, {params.text(output_hash)}, now()
        from run
        returning id
      )
      select id from step;

      insert into processing.record_versions
        (source_row_id, step_run_id, version_number, record_state, eligibility_status)
      select sr.id, step.id, {args.version_number},
        coalesce(previous.record_state, '{{}}'::jsonb) || {params.jsonb(state)},
        'excluded_duplicate_adjudicated'
      from ingestion.source_rows sr
      cross join current_step step
      left join lateral (
        select rv.record_state
        from processing.record_versions rv
        where rv.source_row_id = sr.id and rv.version_number < {args.version_number}
        order by rv.version_number desc
        limit 1
      ) previous on true
      where sr.raw_record_id = {params.text(raw_id)}
      ;

      insert into audit.record_events
        (step_run_id, source_row_id, field_name, old_value, new_value, action, reason_code, rationale, rule_version, review_status)
      select step.id, sr.id, 'analysis_eligibility_status', null,
        {params.jsonb('excluded_duplicate_adjudicated')}, 'exclude',
        'duplicate_adjudicated_exclusion', {params.text(args.rationale)},
        {params.text(args.step_version)}, 'adjudicated'
      from ingestion.source_rows sr, current_step step
      where sr.raw_record_id = {params.text(raw_id)};

      insert into audit.adjudications
        (source_row_id, field_name, decision, rationale, reviewer, consumed_by_step_run_id)
      select sr.id, 'analysis_eligibility_status', {params.jsonb(state)},
        {params.text(args.rationale)}, {params.text(args.reviewer)}, step.id
      from ingestion.source_rows sr, current_step step
      where sr.raw_record_id = {params.text(raw_id)}
        and not exists (
          select 1 from audit.adjudications existing
          where existing.source_row_id = sr.id
            and existing.field_name = 'analysis_eligibility_status'
            and existing.decision = {params.jsonb(state)}
        );
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
    "abrasion": "Abrasion",
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
    "muscle_compartment_syndrome": "Muscle compartment syndrome",
    "muscle_contusion": "Muscle contusion",
    "muscle_injury": "Muscle injury",
    "nonspecific": "Nonspecific",
    "peripheral_nerve_injury": "Peripheral nerve injury",
    "physis_injury": "Physis injury",
    "synovitis_capsulitis": "Synovitis/capsulitis",
    "tendon_rupture": "Tendon rupture",
    "tendinopathy": "Tendinopathy",
    "unknown": "Unknown",
    "vascular_trauma": "Vessels (vascular trauma)",
    "stump_injury": "Stump injury",
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

def format_uk_date(value: date | None) -> str:
    return value.strftime("%d/%m/%Y") if value else ""


def filled_injury_export_row(row: dict[str, str]) -> dict[str, str]:
    output = dict(row)
    injured_at = parse_date_value(row.get("Date Injured", ""))
    days, days_origin = effective_days_injured_with_origin(row)
    is_closed, is_closed_origin = injury_closed(row)
    activity, activity_origin = activity_context(row)
    contact, contact_origin = contact_context(row)
    recurrence, recurrence_origin = recurrence_status(row)
    severity, severity_origin = severity_category(days, is_closed)
    body, body_origin = body_location(row)
    problem, problem_origin = problem_type(row)
    injury, injury_origin = injury_type(row)
    return_date, return_date_origin = effective_confirmed_return_date(row, days, days_origin)

    output["Date Injured"] = format_uk_date(injured_at) or clean_text(row.get("Date Injured", ""))
    if days is not None and not clean_text(row.get("Days Injured")):
        output["Days Injured"] = str(days)
    output["Days Injured origin"] = days_origin
    if clean_text(row.get("Training Days Missed")):
        output["Training Days Missed"] = ""
        output["Training Days Missed origin"] = "moved_to_days_injured_source_preserved_in_intake"
    source_diagnosis = clean_text(row.get("Injury Tissue Type/s"))
    source_diagnosis_key = source_diagnosis.lower()
    if (
        source_diagnosis
        and not clean_text(row.get("Description"))
        and source_diagnosis_key not in INJURY_TYPE_MAP
        and source_diagnosis_key not in INJURY_TYPE_LABEL_TO_KEY
    ):
        output["Description"] = source_diagnosis
        output["Description origin"] = "copied_from_source_diagnosis_before_ioc_bucketing"
    source_recurrence = clean_text(row.get("Recurrence"))
    if "recurrence" in source_recurrence.lower() and not clean_text(row.get("Recurrence Stage")):
        output["Recurrence Stage"] = source_recurrence
        output["Recurrence Stage origin"] = "copied_from_source_recurrence_subtype"
    orchard_code = effective_orchard_code(row)
    if orchard_code and not clean_text(row.get("Orchard Code")):
        output["Orchard Code"] = orchard_code
    output["Problem type"] = {"injury": "Injury", "illness": "Illness"}.get(problem, "Unknown")
    output["Injury Status"] = {True: "Closed", False: "Open/Ongoing"}.get(is_closed, "Unknown")
    output["Fit for selection"] = {True: "Yes", False: "No"}.get(is_closed, "Unknown")
    output["Fit For Selection Date"] = ""
    output["Confirmed Return Date"] = format_uk_date(return_date) if is_closed is True else ""
    output["Occasion category"] = {"urc_match": "match", "match": "match", "training": "training"}.get(activity, "unknown")
    output["Match Type"] = {"urc_match": "URC", "training": "training"}.get(activity, "unknown")
    output["Body Part"] = BODY_LOCATION_LABELS.get(body, "Unknown")
    output["Injury Tissue Type/s"] = INJURY_TYPE_LABELS.get(injury, "Unknown")
    output["Injury Grade"] = SEVERITY_LABELS.get(severity, "Unknown")
    output["Recurrence"] = {"first_episode": "First episode", "recurrence": "Recurrence"}.get(
        recurrence, "Unknown"
    )
    output["Is Contact"] = {"contact": "Contact", "non_contact": "Non-Contact"}.get(contact, "Unknown")
    source_time_loss = clean_text(row.get("TimeLoss vs Medical Attention"))
    output["TimeLoss vs Medical Attention"] = (
        source_time_loss
        if days is None and source_time_loss in {"Time Loss", "Medical Attention"}
        else "Unknown"
        if days is None
        else "Time Loss"
        if days > 0
        else "Medical Attention"
    )
    output["Problem type origin"] = problem_origin
    output["Injury Status origin"] = is_closed_origin
    output["Fit for selection origin"] = is_closed_origin
    output["Confirmed Return Date origin"] = return_date_origin if is_closed is True and return_date else ""
    output["Occasion category origin"] = activity_origin
    output["Match Type origin"] = activity_origin
    output["Body Part origin"] = body_origin
    output["Injury Tissue Type/s origin"] = injury_origin
    output["Injury Grade origin"] = severity_origin
    output["Recurrence origin"] = recurrence_origin
    output["Is Contact origin"] = contact_origin
    output["TimeLoss vs Medical Attention origin"] = (
        "preserved_source_classification_for_censored_injury"
        if days is None and source_time_loss in {"Time Loss", "Medical Attention"}
        else "derived_from_days_injured"
    )
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
    injured_in_team = clean_text(getattr(args, "injured_in_team", ""))
    exposure_rows = [
        row
        for row in read_rows(Path(args.exposure_file))
        if clean_text(row.get("cleaning_action")) == "include"
    ]
    if not exposure_rows:
        raise SystemExit("no included exposure rows found")
    scope_status_counts: dict[str, int] = {}
    for row in exposure_rows:
        scope_status = clean_text(row.get("scope_status")) or "unknown"
        scope_status_counts[scope_status] = scope_status_counts.get(scope_status, 0) + 1

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
    analysis_source_rows = []
    analysis_excluded_row_numbers: set[str] = set()
    analysis_filled_columns: dict[str, set[str]] = {}
    standardisation_events: list[dict[str, str]] = []
    standardisation_errors: list[str] = []
    injury_scope_exclusion_counts: dict[str, int] = defaultdict(int)
    injury_rows = []
    for index, row in enumerate(injury_source_rows, start=2):
        source_row_number = str(index)
        injured_at = parse_date_value(row.get("Date Injured", ""))
        filled_row = filled_injury_export_row(row)
        protected_alias_replaced_fields = set()
        if injured_in_team:
            for field, value in filled_row.items():
                if clean_text(value).casefold() == injured_in_team.casefold():
                    filled_row[field] = args.team
                    protected_alias_replaced_fields.add(field)
        source_tissue = clean_text(row.get("Injury Tissue Type/s"))
        source_contact = clean_text(row.get("Is Contact")).lower()
        source_recurrence = clean_text(row.get("Recurrence")).lower()
        source_occasion = clean_text(row.get("Occasion category")).lower()
        if (
            clean_text(row.get("Problem type")).lower() == "injury"
            and source_tissue
            and not is_missing(source_tissue)
            and filled_row.get("Injury Tissue Type/s") == "Unknown"
        ):
            standardisation_errors.append(f"row {source_row_number}: explicit injury diagnosis mapped to Unknown")
        if (
            source_contact not in {"", "na", "n/a", "unknown", "other - non-rugby"}
            and filled_row.get("Is Contact") == "Unknown"
        ):
            standardisation_errors.append(f"row {source_row_number}: explicit contact value mapped to Unknown")
        if (
            source_recurrence not in {"", "na", "n/a", "unknown"}
            and not any(marker in source_recurrence for marker in {"ã", "â"})
            and filled_row.get("Recurrence") == "Unknown"
        ):
            standardisation_errors.append(f"row {source_row_number}: explicit recurrence value mapped to Unknown")
        if source_occasion in {"match", "game", "training"} and filled_row.get("Occasion category") == "unknown":
            standardisation_errors.append(f"row {source_row_number}: explicit occasion mapped to unknown")
        analysis_source_rows.append(filled_row)
        analysis_filled_columns[source_row_number] = {
            field
            for field, value in filled_row.items()
            if clean_text(value) and not clean_text(row.get(field, ""))
        }
        origin_fields = {
            "Days Injured": "Days Injured origin",
            "Training Days Missed": "Training Days Missed origin",
            "Description": "Description origin",
            "Problem type": "Problem type origin",
            "Injury Status": "Injury Status origin",
            "Fit for selection": "Fit for selection origin",
            "Confirmed Return Date": "Confirmed Return Date origin",
            "Occasion category": "Occasion category origin",
            "Match Type": "Match Type origin",
            "Body Part": "Body Part origin",
            "Injury Tissue Type/s": "Injury Tissue Type/s origin",
            "Injury Grade": "Injury Grade origin",
            "Recurrence": "Recurrence origin",
            "Recurrence Stage": "Recurrence Stage origin",
            "Is Contact": "Is Contact origin",
            "TimeLoss vs Medical Attention": "TimeLoss vs Medical Attention origin",
        }
        for field, origin_field in origin_fields.items():
            old_value = clean_text(row.get(field, ""))
            new_value = clean_text(filled_row.get(field, ""))
            if old_value == new_value:
                continue
            standardisation_events.append(
                {
                    "standardised_row_number": source_row_number,
                    "field": field,
                    "old_value": old_value,
                    "new_value": new_value,
                    "action": "fill" if not old_value else "standardise",
                    "reason": (
                        "protected_team_alias_replaced_in_team_scoped_export"
                        if field in protected_alias_replaced_fields
                        else clean_text(filled_row.get(origin_field, ""))
                    ),
                    "review_status": "pipeline_decision",
                }
            )
        cohort_exclusion_reasons = injury_cohort_exclusion_reasons(row, injured_in_team)
        if source_row_number in excluded_injury_rows:
            cohort_exclusion_reasons.append("adjudicated_duplicate")
        if injured_at is None or injured_at < coverage_start or injured_at > coverage_end:
            cohort_exclusion_reasons.append("injury_date_missing_or_outside_exposure_coverage")
        if filled_row.get("Problem type") != "Injury":
            cohort_exclusion_reasons.append("non_injury_problem_type")
        for reason in cohort_exclusion_reasons:
            injury_scope_exclusion_counts[reason] += 1
            standardisation_events.append(
                {
                    "standardised_row_number": source_row_number,
                    "field": "analysis_eligibility",
                    "old_value": "",
                    "new_value": "excluded",
                    "action": "exclude",
                    "reason": reason,
                    "review_status": "user_adjudicated" if reason == "adjudicated_duplicate" else "pipeline_decision",
                }
            )
        if (
            cohort_exclusion_reasons
        ):
            analysis_excluded_row_numbers.add(source_row_number)
            continue
        days_lost = effective_days_injured(filled_row)
        closed, _ = injury_closed(filled_row)
        band_key, band_label = severity_band(days_lost, closed is True)
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

    if standardisation_errors:
        raise SystemExit("standardisation coverage failed: " + "; ".join(standardisation_errors[:20]))

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
        "pipeline_evidence": {
            "injury_file_sha256": sha256_file(Path(args.injury_file)),
            "exposure_file_sha256": sha256_file(Path(args.exposure_file)),
            "injury_processing_rule_version": INJURY_PROCESSING_RULE_VERSION,
            "exposure_processing_rule_version": EXPOSURE_PROCESSING_RULE_VERSION,
            "adjudicated_duplicate_rows": sorted(int(row) for row in excluded_injury_rows),
            "standardisation_audit_file": None,
            "standardisation_audit_sha256": None,
        },
        "method": [
            "Headline injury metrics use time-loss injuries only: Days Injured > 0.",
            "Incidence = time-loss injuries / exposure hours * 1000.",
            "Severity = mean and median days lost per time-loss injury.",
            "Burden = days lost / exposure hours * 1000.",
            f"Exposure hours = sum(minutes_total_clean) / 60 for included {grain_label} exposure rows.",
            monthly_basis,
            "IOC-aligned body-location, tissue/pathology, and severity labels come from the accepted V2 mapping.",
            "Received/Injured In Team retains the approved team plus blank/N/A values; explicit other-team or Club values are excluded."
            if injured_in_team
            else "No Received/Injured In Team cohort filter applied.",
            "Match Type retains URC, training, Other, blank/N/A, and generic match/game values; explicit non-URC competitions and teams are excluded.",
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
            "scope_status_counts": scope_status_counts,
            "injury_cohort_filters": {
                "injured_in_team_applied": bool(injured_in_team),
                "explicit_non_urc_match_type_applied": True,
                "exclusion_reason_counts": dict(sorted(injury_scope_exclusion_counts.items())),
            },
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
            "Aggregate release is approved only after explicit confirmation of the live Supabase target; the dashboard reports aggregate values only.",
        ],
    }

    if dashboard["coverage"]["hours"] <= 0:
        raise SystemExit("exposure hours must be positive")
    if dashboard["headline"][2]["value"] is None or dashboard["headline"][5]["value"] is None:
        raise SystemExit("headline rates were not calculated")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    analysis_source_output = clean_text(getattr(args, "analysis_source_output", ""))
    analysis_source_workbook = ""
    if analysis_source_output:
        export_excluded_fields = set(LOCATOR_FIELDS + UID_FIELDS)
        fieldnames = [
            field
            for field in (list(injury_source_rows[0]) if injury_source_rows else [])
            if field not in export_excluded_fields
        ]
        exported_rows = [{field: row.get(field, "") for field in fieldnames} for row in analysis_source_rows]
        analysis_source_path = Path(analysis_source_output)
        if analysis_source_path.suffix.lower() == ".xlsx":
            write_rows(analysis_source_path.with_suffix(".csv"), exported_rows, fieldnames)
            write_analysis_source_workbook(
                analysis_source_path,
                exported_rows,
                fieldnames,
                analysis_excluded_row_numbers,
                analysis_filled_columns,
            )
            analysis_source_workbook = str(analysis_source_path)
        else:
            write_rows(analysis_source_path, exported_rows, fieldnames)
            xlsx_path = analysis_source_path.with_suffix(".xlsx")
            write_analysis_source_workbook(
                xlsx_path,
                exported_rows,
                fieldnames,
                analysis_excluded_row_numbers,
                analysis_filled_columns,
            )
            analysis_source_workbook = str(xlsx_path)
    standardisation_audit_output = clean_text(getattr(args, "standardisation_audit_output", ""))
    if standardisation_audit_output:
        standardisation_audit_path = Path(standardisation_audit_output)
        write_rows(
            standardisation_audit_path,
            standardisation_events,
            [
                "standardised_row_number",
                "field",
                "old_value",
                "new_value",
                "action",
                "reason",
                "review_status",
            ],
        )
        dashboard["pipeline_evidence"]["standardisation_audit_file"] = str(
            standardisation_audit_path
        )
        dashboard["pipeline_evidence"]["standardisation_audit_sha256"] = sha256_file(
            standardisation_audit_path
        )
    output.write_text(json.dumps(dashboard, indent=2) + "\n")
    print(
        json.dumps(
            {
                "output": str(output),
                "analysis_source_output": analysis_source_output or None,
                "analysis_source_workbook": analysis_source_workbook or None,
                "standardisation_audit_output": standardisation_audit_output or None,
                "standardisation_events": len(standardisation_events),
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
    assert sha256_json({"b": 2, "a": 1}) == sha256_json({"a": 1, "b": 2})
    assert without_keys(
        {"keep": 1, "nested": {"protected": 2}, "items": [{"protected": 3}]},
        {"protected"},
    ) == {"keep": 1, "nested": {}, "items": [{}]}
    assert is_protected_team_alias_value("Team N")
    assert not is_protected_team_alias_value("Glasgow Warriors")
    params = SqlParams()
    assert params.text("value") == "(select value #>> '{}' from _pipeline_params where idx = 1)"
    assert params.jsonb({"key": "value"}) == "(select value from _pipeline_params where idx = 2)"
    assert params.values == ["value", {"key": "value"}]

    assert parse_flexible_date("10/7/24").date().isoformat() == "2024-10-07"
    assert parse_flexible_date("10/7/24", "day-first").date().isoformat() == "2024-07-10"
    assert parse_minutes("01:30:30") == 90.5
    assert effective_days_injured({"Days Injured": "", "Training Days Missed": "12"}) == 12
    assert effective_days_injured({"Date Injured": "01/07/2024", "Confirmed Return Date": "01/07/2024", "Training Days Missed": "-1"}) == 0
    assert effective_days_injured({"Date Injured": "13/12/2024", "Confirmed Return Date": "06/01/2024", "Training Days Missed": "-343"}) == 23
    assert effective_days_injured({"Date Injured": "30/12/2024", "Confirmed Return Date": "07/12/2024", "Training Days Missed": "-24", "TimeLoss vs Medical Attention": "Medical Attention"}) == 0
    assert effective_days_injured({"Training Days Missed": "-1", "TimeLoss vs Medical Attention": "Time Loss"}) == 0
    assert effective_confirmed_return_date(
        {"Date Injured": "02/10/2024", "Confirmed Return Date": "03/10/2024"},
        1,
        "mapped_from_training_days_missed_date_conflict",
    ) == (date(2024, 10, 4), "derived_from_training_days_missed_date_conflict")
    assert effective_confirmed_return_date(
        {"Date Injured": "10/05/2025", "Confirmed Return Date": "05/10/2025"},
        0,
        "mapped_from_training_days_missed_date_conflict",
    ) == (date(2025, 5, 10), "derived_same_day_return_from_zero_days_date_conflict")
    assert effective_orchard_code({"Problem type": "Injury", "Illness Code": "TMXX"}) == "TMXX"
    assert effective_orchard_code({"Problem type": "Illness", "Illness Code": "R05"}) == ""
    assert problem_type({"Problem type": "Illness", "Injury Tissue Type/s": "Respiratory"}) == (
        "illness",
        "mapped_from_problem_type",
    )
    assert exposure_scope_status({}) == ("scope_unknown_included", "blank_scope_fields_retained")
    assert exposure_scope_status({"Competition": "academy"}, "Edinburgh")[0] == "in_scope_explicit"
    assert exposure_scope_status({"session type": "Scotland U20"})[0] == "out_of_scope_explicit"
    assert exposure_scope_status({"session type": "National Academy"})[0] == "out_of_scope_explicit"
    assert exposure_scope_status({"session type": "Academy Training"}, "Edinburgh")[0] == "in_scope_explicit"
    assert exposure_scope_status({"session type": "Academy Game (Glasgow A)"}, "Edinburgh") == (
        "out_of_scope_explicit",
        "academy_game",
    )
    assert exposure_scope_status({"session type": "Game (Connacht A)"}, "Edinburgh") == (
        "in_scope_explicit",
        "urc_opponent_game",
    )
    assert exposure_scope_status({"session type": "Game (Benneton H)"}, "Edinburgh") == (
        "in_scope_explicit",
        "urc_opponent_game",
    )
    assert exposure_scope_status({"session type": "Game (Bath H)"}, "Edinburgh") == (
        "out_of_scope_explicit",
        "non_urc_or_unspecified_game",
    )
    assert exposure_scope_status({"session type": "Game Warm Up"}, "Edinburgh") == (
        "in_scope_explicit",
        "warmup_or_topup_retained",
    )
    assert exposure_scope_status({"session type": "Game Top Up"}, "Edinburgh") == (
        "in_scope_explicit",
        "warmup_or_topup_retained",
    )
    assert exposure_scope_status({"Training With": "Academy Squad"}) == (
        "out_of_scope_explicit",
        "academy_game",
    )
    assert exposure_scope_status({"Training Type": "RTP"}) == (
        "out_of_scope_explicit",
        "explicit_rehab_or_rtp",
    )
    assert exposure_scope_status({"session type": "Club Training"})[0] == "in_scope_explicit"
    assert injury_cohort_exclusion_reasons(
        {"Received/Injured In Team": "Team M", "Match Type": "URC"}, "Team M"
    ) == []
    assert injury_cohort_exclusion_reasons(
        {"Received/Injured In Team": "N/A", "Match Type": "Other"}, "Team M"
    ) == []
    assert injury_cohort_exclusion_reasons(
        {"Received/Injured In Team": "Club", "Match Type": "Champions Cup"}, "Team M"
    ) == ["received_or_injured_in_other_team", "explicit_non_urc_match_type"]
    assert injury_cohort_exclusion_reasons({"Match Type": "Pro team A game"}) == [
        "explicit_non_urc_match_type"
    ]
    assert injury_cohort_exclusion_reasons({"Match Type": "Unclear competition label"}) == []
    assert severity_category(10, True)[0] == "eight_to_twenty_eight_days"
    assert contact_context({"Is Contact": "NA", "Injury Tissue Type/s": "Muscle Strain/Spasm", "Nature of onset": "Acute"}) == (
        "non_contact",
        "inferred_from_acute_muscle_strain",
    )
    assert activity_context({"Occasion category": "match", "Match Type": "URC"}) == (
        "urc_match",
        "mapped_from_occasion_and_match_type",
    )
    assert activity_context({"Occasion category": "Match", "Match Type": "Challenge Cup"}) == (
        "match",
        "mapped_from_occasion_category_non_urc_match",
    )
    assert contact_context({"Is Contact": "Contact (with other player)"})[0] == "contact"
    assert contact_context({"Is Contact": "Overuse (gradual onset)"})[0] == "non_contact"
    assert recurrence_status({"Recurrence": "New injury (not recurrent)"})[0] == "first_episode"
    assert recurrence_status({"Recurrence": "Delayed recurrence"})[0] == "recurrence"
    assert injury_type({"Injury Tissue Type/s": "Other Pain/ unspecified", "Orchard Code": "NJPX"}) == (
        "joint_sprain",
        "mapped_from_orchard_code_ioc_pathology",
    )
    assert body_location({"Body Part": "Lower leg"}) == ("lower_leg", "preserved_controlled_body_part")
    assert injury_type({"Injury Tissue Type/s": "Muscle injury"}) == (
        "muscle_injury",
        "preserved_controlled_injury_tissue_type",
    )
    assert injury_type({"Problem type": "Injury", "Injury Tissue Type/s": "Biceps femoris strain grade 1 - 2"})[0] == "muscle_injury"
    detailed_export = filled_injury_export_row(
        {
            "Problem type": "Injury",
            "Injury Tissue Type/s": "Anterior talofibular ligament sprain",
            "Recurrence": "Early recurrence",
            "Training Days Missed": "5",
        }
    )
    assert detailed_export["Description"] == "Anterior talofibular ligament sprain"
    assert detailed_export["Injury Tissue Type/s"] == "Joint sprain"
    assert detailed_export["Recurrence"] == "Recurrence"
    assert detailed_export["Recurrence Stage"] == "Early recurrence"
    assert detailed_export["Days Injured"] == "5"
    assert detailed_export["Training Days Missed"] == ""
    assert set(BODY_LOCATION_LABELS.values()) == CONTROLLED_BODY_LOCATION_LABELS
    assert set(INJURY_TYPE_LABELS.values()) == CONTROLLED_INJURY_TYPE_LABELS
    unknown_export = filled_injury_export_row({"Date Injured": "02/07/2024", "Days Injured": "0"})
    assert unknown_export["Body Part"] == "Unknown"
    assert unknown_export["Injury Tissue Type/s"] == "Unknown"
    assert unknown_export["Fit for selection"] == "Unknown"
    assert filled_injury_export_row({"TimeLoss vs Medical Attention": "Time Loss"})[
        "TimeLoss vs Medical Attention"
    ] == "Time Loss"
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
        from openpyxl import Workbook

        standardised_source = tmp_path / "standardised.xlsx"
        source_workbook = Workbook()
        source_sheet = source_workbook.active
        source_sheet.title = "Standardized Data"
        source_sheet.append(["PlayerID"])
        source_sheet.append(["player_1"])
        source_sheet.append([])
        source_sheet.append(["player_2"])
        source_workbook.save(standardised_source)
        standardised_csv = tmp_path / "standardised.csv"
        prepared_csv = tmp_path / "prepared.csv"
        write_rows(standardised_csv, [{"PlayerID": "player_1"}, {"PlayerID": "player_2"}], ["PlayerID"])
        quiet_call(
            prepare_intake,
            argparse.Namespace(
                team="Self Check",
                season="2024-25",
                file=str(standardised_csv),
                source_file=str(standardised_source),
                output=str(prepared_csv),
                manifest=None,
                source_sheet="Standardized Data",
                player_id_column="PlayerID",
            ),
        )
        assert [row["source_row_number"] for row in read_rows(prepared_csv)] == ["2", "4"]

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
                    "source_row_sha256": "row_a",
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
                    "source_row_sha256": "row_b",
                },
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
                    "source_row_number": "4",
                    "source_row_sha256": "row_a",
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
                "source_row_sha256",
            ],
        )
        quiet_call(
            clean_exposure,
            argparse.Namespace(
                file=str(exposure_source),
                output=str(exposure_clean),
                qc_output=str(exposure_qc),
                manifest=None,
                date_order="month-first",
                team="Edinburgh",
                window_start="2024-07-06",
                window_end="2024-07-10",
            ),
        )
        cleaned = read_rows(exposure_clean)
        cleaning_actions = [row["cleaning_action"] for row in cleaned]
        assert cleaning_actions == [
            "include",
            "include",
            "exclude_from_primary",
        ], cleaning_actions
        assert cleaned[2]["exclusion_reason"] == "exact_duplicate_copy"
        assert cleaned[0]["week_start_date"] == "2024-07-01"
        assert json.loads(exposure_qc.read_text())["included_minutes_total"] == 240.0
        assert json.loads(exposure_qc.read_text())["analysis_window"]["start"] == "2024-07-06"

        injury_source = tmp_path / "injury.csv"
        dashboard_output = tmp_path / "dashboard.json"
        analysis_source_output = tmp_path / "analysis_source.csv"
        analysis_audit_output = tmp_path / "analysis_audit.csv"
        write_rows(
            injury_source,
            [
                {
                    "Date Injured": "2024-07-02",
                    "Confirmed Return Date": "",
                    "Days Injured": "10",
                    "is_injury_closed": "1",
                    "Occasion category": "Game",
                    "Body Part": "Ankle",
                    "Injury Tissue Type/s": "Muscle",
                    "Received/Injured In Team": "Team Z",
                },
                {
                    "Date Injured": "01/01/2026",
                    "Confirmed Return Date": "",
                    "Days Injured": "5",
                    "is_injury_closed": "1",
                    "Occasion category": "Game",
                    "Body Part": "Ankle",
                    "Injury Tissue Type/s": "Unknown",
                    "Received/Injured In Team": "",
                }
            ],
            [
                "Date Injured",
                "Confirmed Return Date",
                "Days Injured",
                "is_injury_closed",
                "Occasion category",
                "Body Part",
                "Injury Tissue Type/s",
                "Received/Injured In Team",
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
                analysis_source_output=str(analysis_source_output),
                standardisation_audit_output=str(analysis_audit_output),
                injured_in_team="Team Z",
            ),
        )
        dashboard = json.loads(dashboard_output.read_text())
        assert dashboard["coverage"]["hours"] == 4.0
        assert dashboard["headline"][0]["value"] == 1
        assert dashboard["headline"][2]["value"] == 250.0
        assert dashboard["headline"][5]["value"] == 2500.0
        analysis_rows = read_rows(analysis_source_output)
        assert len(analysis_rows) == 2
        assert list(analysis_rows[0]) == [
            "Date Injured",
            "Confirmed Return Date",
            "Days Injured",
            "is_injury_closed",
            "Occasion category",
            "Body Part",
            "Injury Tissue Type/s",
            "Received/Injured In Team",
        ]
        assert analysis_rows[0]["Date Injured"] == "02/07/2024"
        assert analysis_rows[0]["Confirmed Return Date"] == "12/07/2024"
        assert analysis_rows[0]["Received/Injured In Team"] == "Self Check"
        assert all("Team Z" not in row.values() for row in analysis_rows)
        assert "Problem type origin" not in analysis_rows[0]
        assert any(
            row["standardised_row_number"] == "3"
            and row["reason"] == "injury_date_missing_or_outside_exposure_coverage"
            for row in read_rows(analysis_audit_output)
        )
        from openpyxl import load_workbook

        analysis_workbook = load_workbook(analysis_source_output.with_suffix(".xlsx"))
        analysis_sheet = analysis_workbook.active
        def font_rgb(cell: Any) -> str:
            color = cell.font.color
            return color.rgb if color and color.type == "rgb" else ""

        assert not font_rgb(analysis_sheet["A2"]).endswith(("008000", "C00000"))
        assert font_rgb(analysis_sheet["B2"]).endswith("008000")
        assert font_rgb(analysis_sheet["A3"]).endswith("C00000")
        analysis_workbook.close()
        xlsx_only_output = tmp_path / "analysis_source_direct.xlsx"
        quiet_call(
            build_team_dashboard,
            argparse.Namespace(
                team="Self Check",
                season="2024-25",
                injury_file=str(injury_source),
                exposure_file=str(exposure_clean),
                output=str(tmp_path / "dashboard_direct_xlsx.json"),
                analysis_source_output=str(xlsx_only_output),
                injured_in_team="Team Z",
            ),
        )
        assert xlsx_only_output.exists()
        assert read_rows(xlsx_only_output.with_suffix(".csv")) == analysis_rows
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
                date_order="month-first",
                team="Edinburgh",
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
    ingest_parser.add_argument("--exclude-source-fields", default="")
    ingest_parser.add_argument("--redact-manifest-keys", default="")
    ingest_parser.add_argument("--redact-source-values", default="")
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
    exposure_parser.add_argument("--date-order", choices=["month-first", "day-first"], default="month-first")
    exposure_parser.set_defaults(func=prepare_exposure)

    clean_exposure_parser = subcommands.add_parser("clean-exposure")
    clean_exposure_parser.add_argument(
        "--file",
        default="data/intake/2024-25/munster/munster_exposure_intake_locator_enriched_2024-25.csv",
    )
    clean_exposure_parser.add_argument("--team", default="Munster")
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
    clean_exposure_parser.add_argument("--date-order", choices=["month-first", "day-first"], default="month-first")
    clean_exposure_parser.add_argument("--window-start", default="")
    clean_exposure_parser.add_argument("--window-end", default="")
    clean_exposure_parser.set_defaults(func=clean_exposure)

    process_exposure_parser = subcommands.add_parser("process-exposure")
    process_exposure_parser.add_argument("--team", default="Munster")
    process_exposure_parser.add_argument("--season", default="2024-25")
    process_exposure_parser.add_argument(
        "--file",
        default="data/intake/2024-25/munster/munster_exposure_cleaned_2024-25.csv",
    )
    process_exposure_parser.add_argument("--step-name", default="exposure_cleaning")
    process_exposure_parser.add_argument("--step-version", default=EXPOSURE_PROCESSING_RULE_VERSION)
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
    fixture_exposure_parser.add_argument("--date-order", choices=["month-first", "day-first"], default="day-first")
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
    process_parser.add_argument("--step-version", default=INJURY_PROCESSING_RULE_VERSION)
    process_parser.add_argument("--version-number", type=int, default=1)
    process_parser.add_argument("--analysis-audit-file", default="")
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
    adjudicate_duplicate_parser.add_argument("--reviewer", required=True)
    adjudicate_duplicate_parser.add_argument("--step-version", default=INJURY_PROCESSING_RULE_VERSION)
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
        command.add_argument("--injured-in-team", default="")
        command.add_argument("--analysis-source-output", default="")
        command.add_argument("--standardisation-audit-output", default="")

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
