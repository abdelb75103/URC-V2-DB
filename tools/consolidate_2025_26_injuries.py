#!/usr/bin/env python3
"""Build and finalise the checksum-bound 2025-26 injury consolidation."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import uuid
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path
from typing import Any


CANONICAL_HEADERS = [
    "Team",
    "PlayerID",
    "Reporting At Club",
    "Received/Injured In Team",
    "Problem type",
    "Date Injured",
    "Fit For Selection Date",
    "Confirmed Return Date",
    "Days Injured",
    "Occasion category",
    "Body Part",
    "Orchard Code",
    "Illness Code",
    "Description",
    "Injury Tissue Type/s",
    "Side",
    "Nature of onset",
    "Recurrence",
    "Is Contact",
    "Mechanism of Injury",
    "Mechanism Notes",
    "Injury Surface Type",
    "Match Type",
    "Received At Position",
    "Required Surgery",
    "TimeLoss vs Medical Attention",
    "Diagnosis",
    "Exclusion Reason",
    "Specific Diagnosis",
]
DATE_FIELDS = ("Date Injured", "Fit For Selection Date", "Confirmed Return Date")
CLASSIFICATIONS = {"Time Loss", "Medical Attention", "unclassified"}
ERROR_TOKENS = ("#REF!", "#VALUE!", "#NAME?", "#NUM!", "#DIV/0!", "#N/A")
TEAM_KEYS = {
    "Benetton": "benetton",
    "Bulls": "bulls",
    "Cardiff": "cardiff",
    "Connacht": "connacht",
    "Dragons": "dragons",
    "Edinburgh": "edinburgh",
    "Glasgow Warriors": "glasgow",
    "Leinster": "leinster",
    "Lions": "lions",
    "Munster": "munster",
    "Ospreys": "ospreys",
    "Scarlets": "scarlets",
    "Sharks": "sharks",
    "Stormers": "stormers",
    "Ulster": "ulster",
    "Zebre": "zebre",
}
TEAM_ORDER = list(TEAM_KEYS)
UUID_NAMESPACE = uuid.UUID("cfdd4091-bcf5-56f1-91cc-6ae0ec3a1471")

# Exact non-blank values present in the frozen 2024-25 review workbook. Source
# labels remain available in the immutable source copies and row hashes; the
# consolidated master uses only this frozen reporting vocabulary.
FROZEN_CONTROLLED_VALUES = {
    "Problem type": {"Illness", "Injury"},
    "Occasion category": {"Gym-Based", "Illness", "Match", "Non-Rugby", "Other", "Training"},
    "Body Part": {
        "Abdomen", "Ankle", "Chest", "Elbow", "Foot", "Forearm", "Hand", "Head",
        "Hip/Groin", "Illness", "Knee", "Lower leg", "Lumbosacral", "Multiple",
        "Neck", "Shoulder", "Thigh", "Thoracic spine", "Unknown", "Unspecified",
        "Upper arm", "Wrist", "Wrist/Hand",
    },
    "Injury Tissue Type/s": {
        "Abrasion", "Arthritis", "Bone contusion", "Bone stress injury",
        "Brain/spinal cord injury", "Bursitis", "Cartilage injury", "Chronic instability",
        "Contusion (superficial)", "Fracture", "Illness", "Internal organs (organ trauma)",
        "Joint sprain", "Laceration", "Muscle contusion", "Muscle injury", "Nonspecific",
        "Peripheral nerve injury", "Physis injury", "Stump injury", "Synovitis/capsulitis",
        "Tendinopathy", "Tendon rupture", "Unknown", "Vessels (vascular trauma)",
    },
    "Side": {"Bilateral", "Bilateral/central", "Center", "Central", "Left", "N/A", "Right", "left"},
    "Nature of onset": {
        "Acute", "Conditioning - Non-Weights", "Conditioning - Weights", "Gradual", "N/A",
        "N/A or Unknown", "NA", "Overload", "Rugby - Contact", "Rugby - Non-Contact",
    },
    "Recurrence": {"New case", "New injury", "Recurrence"},
    "Is Contact": {"Contact", "N/A", "Non-contact", "Unknown"},
    "Mechanism of Injury": {
        "-", "Accelerating", "Being Tackled", "Change of direction", "Circuits", "Collision",
        "Contactless Other", "Falling/diving", "Gradual onset", "Gym", "Impact",
        "Insidious (no recognisable mechanism)", "Jumping/landing", "Kicking",
        "Kicking (non contact)", "Lifting weights", "Line outs", "Lineout (contact)",
        "Lineout (non contact)", "Lineout (other)", "Lineouts", "Maul", "Maul (contact)",
        "Maul (non contact)", "Maul (other)", "Medical/Illness", "N/A",
        "Open Play (contact)", "Open Play (non contact)", "Open Play (other)", "Other",
        "Other Contact", "Other acute mechanism", "Overload", "Overuse", "Passing", "Race",
        "Ruck", "Ruck (contact)", "Ruck (non contact)", "Ruck (other)", "Rucks", "Rugby",
        "Running", "Running/decelerating", "Running/sprinting", "S&C (non contact)",
        "Scrum (contact)", "Scrum (non contact)", "Scrum (other)", "Scrums", "Sudden onset",
        "Tackle", "Tackle (contact)", "Tackled by other player", "Tackling carried out",
        "Tackling other player", "Twisting/turning", "Unknown", "Unknown mechanism", "Velocity",
        "impact", "lifting weights",
    },
    "Injury Surface Type": {
        "-", "Artifical", "Artificial", "Grass", "Gym Floor", "N/A", "N/A or Unknown",
        "Partial artificial", "Track", "Turf", "astroturf/hybrid", "grass",
    },
    "Match Type": {
        "-", "6 Nations", "Challenge Cup", "Champions Cup", "Club",
        "Confirmed URC match fixture", "Italian Elite Championship", "N/A", "NA", "NAG U20",
        "November Test Matches", "Other", "Other Club Competition", "Pro first-team game",
        "Test Match", "URC", "United Rugby Championship", "training",
    },
    "Received At Position": {
        "1", "1. Prop", "10", "11", "12", "13", "14", "15", "2", "2. Hooker", "3",
        "3. Second Row", "4", "4. Back Row", "5", "5. Scrum Half", "6", "6. Stand Off",
        "7", "7. Centre", "8", "8. Back 3", "9", "Back Row", "Back Three",
        "Blindside Flanker", "Center", "Centre", "Flanker", "Fly Half", "Fly half", "Fullback",
        "Hooker", "Inside Centre", "Lock", "Loose-head Prop", "N/A", "No. 8",
        "Openside Flanker", "Other", "Out Half", "Outside Centre", "Prop", "Scrum Half",
        "Scrum-half", "Second Row", "Tight-head Prop", "Wing", "Wing/Fullback", "centre",
        "flanker", "fly half", "full-back", "hooker", "lock", "prop", "scrum half", "wing",
    },
    "Required Surgery": {"N/A", "No", "Yes", "no", "yes", "ÃÂÃÂ"},
    "TimeLoss vs Medical Attention": {"FALSE", "Medical Attention", "No", "TRUE", "Time Loss", "Yes"},
}

FROZEN_VALUE_MAP = {
    "Occasion category": {"Unknown": ""},
    "Nature of onset": {
        "Chronic": "N/A or Unknown", "Other": "N/A or Unknown",
        "Overuse": "N/A or Unknown", "Traumatic": "N/A or Unknown",
        "Unknown": "N/A or Unknown",
    },
    "Recurrence": {"First episode": "New injury", "Unknown": ""},
    "Is Contact": {"Non-Contact": "Non-contact"},
    "Mechanism of Injury": {
        "Acceleration": "Accelerating", "Aerial": "Unknown",
        "Aerial Contact (LO / Aerial catch)": "Other Contact", "Aerial Landing": "Jumping/landing",
        "Blocked": "Unknown", "Breakdown": "Unknown", "Breakdown - Poach": "Unknown",
        "Change of Direction": "Change of direction", "Conditioning": "Unknown",
        "Conditioning Based": "Unknown", "Contact with player": "Other Contact",
        "Deceleration": "Unknown", "Fitness testing": "Other",
        "GRadual onset": "Gradual onset", "Gradual Onset": "Gradual onset",
        "Grappling Activity": "Unknown", "Gym Based": "Gym", "Landing": "Jumping/landing",
        "Non-Rugby": "Other", "Other Non Contact": "Contactless Other",
        "Plyo Activity": "Unknown", "Restart": "Unknown",
        "Rugby - Non-Contact": "Contactless Other", "Scrum": "Scrums",
        "Sprinting": "Running/sprinting", "Stretching": "Other", "Tackled": "Being Tackled",
        "Tackling": "Tackling carried out", "Wrestling": "Unknown",
    },
    "Injury Surface Type": {"Astroturf/Hybrid": "astroturf/hybrid", "Other": "N/A or Unknown"},
    "Match Type": {
        "Autumn International": "Other", "Autumn Nations Series": "Other",
        "Emerging Scotland game": "Other", "Junior 6 Nations": "Other",
        "Junior World Cup": "Other", "M6N U18": "Other", "M6N U20": "Other",
        "Pro team A game": "Other", "Rugby World Cup": "Other",
        "Scotland A game": "Other", "Summer Tour": "Other",
    },
    "Received At Position": {
        "0": "", "1.0": "1", "1.Prop": "1. Prop", "10.0": "10", "11.0": "11",
        "12.0": "12", "13.0": "13", "15.0": "15", "2.0": "2", "3.0": "3",
        "4.0": "4", "5.0": "5", "6.0": "6", "7.0": "7", "8.0": "8", "9.0": "9",
        "Stand Off": "Other", "Winger": "Wing",
    },
    "TimeLoss vs Medical Attention": {"Unknown": ""},
}


class ConsolidationError(ValueError):
    """Raised when an input or derived output breaks the ingest contract."""


def clean(value: Any) -> str:
    return "" if value is None else str(value).strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_sha256(value: Any) -> str:
    payload = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def parse_date(value: Any) -> date | None:
    text = clean(value)
    if not text:
        return None
    for pattern in ("%d/%m/%Y", "%Y-%m-%d", "%Y/%m/%d", "%d/%m/%y"):
        try:
            return datetime.strptime(text, pattern).date()
        except ValueError:
            continue
    raise ConsolidationError(f"unrecognised date {text!r}")


def display_date(value: date | None) -> str:
    return value.strftime("%d/%m/%Y") if value else ""


def parse_days(value: Any) -> int | None:
    text = clean(value)
    if not text or text.casefold() in {"na", "n/a"}:
        return None
    if not re.fullmatch(r"\d+(?:\.0+)?", text):
        raise ConsolidationError(f"invalid non-negative whole-day duration {text!r}")
    return int(float(text))


def normalise_classification(value: Any) -> str | None:
    text = clean(value).casefold().replace("_", " ").replace("-", " ")
    text = " ".join(text.split())
    if text in {"time loss", "timeloss", "true", "yes"}:
        return "Time Loss"
    if text in {"medical attention", "medicalattention", "false", "no"}:
        return "Medical Attention"
    if text in {"", "unknown", "unclassified"}:
        return None
    raise ConsolidationError(f"unsupported classification value {value!r}")


def valid_problem_type(row: dict[str, str]) -> bool:
    problem_type = clean(row.get("Problem type"))
    return problem_type in {"Injury", "Illness"} or (
        not problem_type and bool(clean(row.get("Exclusion Reason")))
    )


def apply_frozen_vocabulary(row: dict[str, str], derived_fields: set[str]) -> None:
    """Normalise known source synonyms, then reject reporting-vocabulary drift."""
    for field, replacements in FROZEN_VALUE_MAP.items():
        value = row[field]
        if value in replacements:
            row[field] = replacements[value]
            derived_fields.add(field)
    for field, allowed in FROZEN_CONTROLLED_VALUES.items():
        value = row[field]
        if value and value not in allowed:
            raise ConsolidationError(
                f"unsupported frozen 2024-25 value for {field}: {value!r}"
            )


def is_verified_fixture_addition(row: dict[str, str], excluded: bool) -> bool:
    """Blue marks the derived confirmed-fixture label, not source-labelled URC."""
    return not excluded and row["Match Type"] == "Confirmed URC match fixture"


def source_open(policy: str, row: dict[str, str], extras: dict[str, str]) -> bool:
    if policy == "irfu_restriction":
        status = clean(extras.get("Source Closure Status")).casefold()
        if status in {"false", "0", "open"}:
            return True
        if status in {"true", "1", "closed"}:
            return False
    if policy == "zebre_days_lost":
        provenance = clean(extras.get("Closure Provenance")).casefold()
        if "today()" in provenance or "no confirmed closing date" in provenance:
            return True
        if "static closing date" in provenance:
            return False
    return (
        not clean(row.get("Confirmed Return Date"))
        and not clean(row.get("Fit For Selection Date"))
        and not clean(row.get("Days Injured"))
    )


def sa_restriction(extras: dict[str, str]) -> bool | None:
    text = clean(extras.get("Inference Provenance"))
    if not text:
        return None
    try:
        provenance = json.loads(text)
    except json.JSONDecodeError as error:
        raise ConsolidationError("invalid South African inference provenance") from error
    basis = clean(provenance.get("TimeLoss vs Medical Attention")).casefold()
    if "unavailability_true" in basis or "unavailable_true" in basis:
        return True
    if "unavailability_false" in basis or "unavailable_false" in basis:
        return False
    return None


def derive_row(
    policy: str,
    source_row: dict[str, str],
    extras: dict[str, str],
    supplement: dict[str, Any] | None = None,
    source_group: str = "",
) -> dict[str, Any]:
    row = {header: clean(source_row.get(header)) for header in CANONICAL_HEADERS}
    derived_fields: set[str] = set()
    apply_frozen_vocabulary(row, derived_fields)
    original_class = normalise_classification(row["TimeLoss vs Medical Attention"])
    injury_date = parse_date(row["Date Injured"])
    fit_date = parse_date(row["Fit For Selection Date"])
    return_date = parse_date(row["Confirmed Return Date"])
    reported_days = parse_days(row["Days Injured"])
    excluded = bool(row["Exclusion Reason"])
    source_conflict = False
    review_reasons: list[str] = []

    if return_date:
        return_basis = "source_confirmed_return_date"
    elif fit_date and not excluded:
        return_date = fit_date
        return_basis = "source_fit_for_selection_date"
        row["Confirmed Return Date"] = display_date(return_date)
        derived_fields.add("Confirmed Return Date")
    else:
        return_basis = "missing"

    clinical_days = reported_days
    duration_basis = "source_reported" if reported_days is not None else "missing"
    return_interval_days: int | None = None
    duration_end_date = return_date or (fit_date if excluded else None)
    if injury_date and duration_end_date:
        return_interval_days = (duration_end_date - injury_date).days
        if return_interval_days < 0:
            source_conflict = True
            review_reasons.append("return_date_precedes_injury_date")
        elif excluded:
            if reported_days is not None and reported_days != return_interval_days:
                source_conflict = True
                review_reasons.append("reported_duration_conflicts_with_dates")
        elif reported_days is None:
            clinical_days = return_interval_days
            duration_basis = "derived_from_dates"
            row["Days Injured"] = str(return_interval_days)
            derived_fields.add("Days Injured")
        elif reported_days == 0 and return_interval_days in {0, 1}:
            # The accepted zero-day exception is Medical Attention. A next-day
            # return does not turn a source-reported zero into one day lost.
            pass
        elif reported_days != return_interval_days:
            if source_group == "scotland" and abs(reported_days - return_interval_days) <= 1:
                pass
            else:
                clinical_days = return_interval_days
                duration_basis = "resolved_from_dates"
                row["Days Injured"] = str(return_interval_days)
                derived_fields.add("Days Injured")
                source_conflict = True
                review_reasons.append("reported_duration_resolved_from_dates")

    open_status = source_open(policy, row, extras)
    restriction: bool | None = None
    restriction_basis = "source_participation_restriction"
    unrestricted_participation_evidence = False
    explicit = original_class
    basis: str

    if policy == "irfu_restriction":
        if excluded:
            legacy_days = parse_days(extras.get("Source Modified Days"))
            if legacy_days is not None:
                restriction = legacy_days > 0
        elif reported_days is not None:
            restriction = reported_days > 0
        explicit = None
    elif policy == "sa_provenance":
        restriction = sa_restriction(extras)
        explicit = None
    elif policy == "zebre_days_lost":
        explicit = None
        if reported_days is not None:
            restriction = reported_days > 0
        elif (
            not excluded
            and
            return_date
            and "static closing date" in clean(extras.get("Closure Provenance")).casefold()
        ):
            restriction = True
            restriction_basis = "source_static_closing_date"
    elif policy == "benetton_status":
        if supplement:
            status_classification = normalise_classification(
                supplement.get("time_loss_classification")
            )
            if status_classification == "Time Loss":
                restriction = True
            elif status_classification == "Medical Attention":
                restriction = False
            explicit = None
            medical_status = clean(supplement.get("medical_closure_status")).casefold()
            if medical_status:
                open_status = medical_status == "medically open"
            green = supplement.get("status_timeline", {}).get("green", {})
            unrestricted_participation_evidence = bool(clean(green.get("start")))
    elif policy != "reviewed_explicit":
        raise ConsolidationError(f"unknown classification policy {policy!r}")

    if (
        explicit is None
        and restriction is None
        and not excluded
        and injury_date
        and fit_date
        and fit_date > injury_date
    ):
        restriction = True
        restriction_basis = "source_fit_for_selection_date"

    if restriction is False:
        unrestricted_participation_evidence = True

    zero_day_return = (
        not excluded
        and clinical_days == 0
        and return_interval_days is not None
        and return_interval_days in {0, 1}
    )

    if excluded:
        final = original_class or "unclassified"
        basis = (
            "excluded_source_classification"
            if original_class
            else "excluded_not_adjudicated"
        )
    elif policy == "irfu_restriction" and reported_days == 0:
        final = "Medical Attention"
        basis = "source_reported_zero_days"
    elif explicit == "Medical Attention":
        final = explicit
        basis = "explicit_source_classification"
    elif clinical_days == 0:
        final = "Medical Attention"
        basis = (
            "same_or_next_day_return"
            if zero_day_return and original_class == "Time Loss"
            else "reported_zero_days" if reported_days == 0 else "derived_zero_days"
        )
    elif explicit == "Time Loss":
        final = explicit
        basis = "explicit_source_classification"
    elif restriction is True:
        final = "Time Loss"
        basis = restriction_basis
    elif restriction is False:
        final = "Medical Attention"
        basis = "source_unrestricted_participation"
    elif open_status and not unrestricted_participation_evidence:
        final = "Time Loss"
        basis = "open_record_fallback"
    else:
        final = "unclassified"
        basis = "unclassified_no_qualifying_evidence"

    if (
        not excluded
        and original_class == "Time Loss"
        and final == "Medical Attention"
        and clinical_days == 0
    ):
        source_conflict = True
        review_reasons.append("zero_day_time_loss_resolved_as_medical_attention")
    elif final == "Time Loss" and clinical_days == 0:
        source_conflict = True
        review_reasons.append("time_loss_with_zero_clinical_days")

    if (
        final == "Medical Attention"
        and not excluded
        and policy != "irfu_restriction"
        and not return_date
        and clinical_days == 0
    ):
        if injury_date:
            return_date = injury_date
            return_basis = "derived_zero_day_return"
            row["Confirmed Return Date"] = display_date(return_date)
            derived_fields.add("Confirmed Return Date")
        else:
            review_reasons.append("zero_day_return_not_derivable_without_injury_date")

    if source_conflict:
        review_reasons.append(
            "source_conflict_recorded_after_rule_resolution"
            if "reported_duration_resolved_from_dates" in review_reasons
            or "zero_day_time_loss_resolved_as_medical_attention" in review_reasons
            else "source_conflict_preserved_without_reclassification"
        )

    if original_class is None and final != "unclassified":
        row["TimeLoss vs Medical Attention"] = final
        derived_fields.add("TimeLoss vs Medical Attention")

    for field in DATE_FIELDS:
        if row[field]:
            row[field] = display_date(parse_date(row[field]))
    if clinical_days is not None:
        row["Days Injured"] = str(clinical_days)

    time_loss_days = None
    if final == "Time Loss" and clinical_days is not None and clinical_days > 0:
        time_loss_days = clinical_days
    if (
        open_status
        and final == "Time Loss"
        and not unrestricted_participation_evidence
    ):
        return_date = None
        return_basis = "missing_open_record"
        time_loss_days = None

    return {
        "row_values": row,
        # This field records only evidence allowed to drive the successor.
        # Any non-qualifying display value remains untouched in row_values.
        "qualifying_source_classification": explicit,
        "participation_restriction_evidence": restriction,
        "final_classification": final,
        "classification_basis": basis,
        "clinical_duration_days": clinical_days,
        "clinical_duration_basis": duration_basis,
        "time_loss_days": time_loss_days,
        "return_date": return_date.isoformat() if return_date else None,
        "return_date_basis": return_basis,
        "open_status": open_status,
        "unrestricted_participation_evidence": unrestricted_participation_evidence,
        "source_conflict": source_conflict,
        "review_required": (
            not excluded
            and (
                final == "unclassified"
                or any(reason in {
                    "return_date_precedes_injury_date",
                    "reported_duration_conflicts_with_dates",
                    "time_loss_with_zero_clinical_days",
                    "zero_day_return_not_derivable_without_injury_date",
                } for reason in review_reasons)
            )
        ),
        "review_reasons": review_reasons,
        "derived_fields": sorted(derived_fields),
    }


def read_dict_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        headers = reader.fieldnames or []
        rows = [{key: clean(value) for key, value in row.items()} for row in reader]
    return headers, rows


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    headers, rows = read_dict_csv(path)
    if headers[: len(CANONICAL_HEADERS)] != CANONICAL_HEADERS:
        raise ConsolidationError(f"{path}: canonical header order changed")
    return headers, rows


def write_csv(path: Path, headers: list[str], rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({header: row.get(header, "") for header in headers})


def _source_copy_manifest(config: dict[str, Any], root: Path) -> dict[str, Any]:
    files = []
    for item in config["source_files"]:
        path = root / item["relative_path"]
        if not path.is_file():
            raise ConsolidationError(f"missing copied source artefact {path}")
        digest = sha256_file(path)
        if digest != item["sha256"]:
            raise ConsolidationError(f"copied source hash changed for {path}")
        files.append(
            {
                "group": item["group"],
                "task_id": item["task_id"],
                "role": item["role"],
                "relative_path": item["relative_path"],
                "source_path": item["source_path"],
                "sha256": digest,
                "bytes": path.stat().st_size,
            }
        )
    return {
        "schema_version": "urc_2025_26_source_copy_manifest_v1",
        "consolidation_id": config["consolidation_id"],
        "files": files,
        "bundle_sha256": canonical_sha256(files),
    }


def _supplements(config: dict[str, Any], root: Path) -> dict[str, list[dict[str, Any]]]:
    supplements: dict[str, list[dict[str, Any]]] = {}
    for group in config["groups"]:
        if group["policy"] != "benetton_status":
            continue
        audit = json.loads((root / group["audit_relative_path"]).read_text(encoding="utf-8"))
        supplements[group["name"]] = audit["row_results"]
    return supplements


def build(config_path: Path) -> None:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    root = Path(config["root"])
    root.mkdir(parents=True, exist_ok=True)
    copy_manifest = _source_copy_manifest(config, root)
    (root / "source_copy_manifest.json").write_text(
        json.dumps(copy_manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    supplements = _supplements(config, root)

    input_groups = {item["name"]: item for item in config["groups"]}
    csv_inputs = [item for item in config["source_files"] if item["role"] == "master_csv"]
    by_team: dict[str, list[dict[str, Any]]] = defaultdict(list)
    raw_team_counts: Counter[str] = Counter()
    raw_included_counts: Counter[str] = Counter()

    for item in csv_inputs:
        path = root / item["relative_path"]
        headers, rows = read_csv(path)
        if len(rows) != item["expected_rows"]:
            raise ConsolidationError(f"{path}: expected {item['expected_rows']} rows, found {len(rows)}")
        group = input_groups[item["group"]]
        group_supplements = supplements.get(item["group"], [])
        if group_supplements and len(group_supplements) != len(rows):
            raise ConsolidationError(f"{item['group']}: supplement row count changed")
        for ordinal, source in enumerate(rows, start=2):
            canonical = {header: clean(source.get(header)) for header in CANONICAL_HEADERS}
            for value in canonical.values():
                if any(token.casefold() in value.casefold() for token in ERROR_TOKENS):
                    raise ConsolidationError(f"{path} row {ordinal}: literal spreadsheet error")
            team = canonical["Team"]
            if team not in TEAM_KEYS:
                raise ConsolidationError(f"{path} row {ordinal}: unknown team {team!r}")
            if not re.fullmatch(r"Ath_\d+", canonical["PlayerID"]):
                raise ConsolidationError(f"{path} row {ordinal}: invalid pseudonymous PlayerID")
            if not valid_problem_type(canonical):
                raise ConsolidationError(f"{path} row {ordinal}: invalid Problem type")

            extras = {header: clean(source.get(header)) for header in headers[len(CANONICAL_HEADERS):]}
            supplement = group_supplements[ordinal - 2] if group_supplements else None
            derived = derive_row(
                group["policy"],
                canonical,
                extras,
                supplement,
                source_group=item["group"],
            )
            excluded = bool(derived["row_values"]["Exclusion Reason"])
            state = clean(extras.get("Record Status") or extras.get("Inclusion State")).casefold()
            if state and (state == "excluded") != excluded:
                raise ConsolidationError(f"{path} row {ordinal}: inclusion state conflicts with Exclusion Reason")
            raw_team_counts[team] += 1
            if not excluded:
                raw_included_counts[team] += 1

            source_values = [clean(source.get(header)) for header in headers]
            source_artifact_row_sha256 = canonical_sha256(source_values)
            source_row_number = clean(extras.get("Source Row Number")) or str(ordinal)
            source_locator = (
                clean(extras.get("Source Locator"))
                or clean(extras.get("Authoritative Source Locator"))
                or f"{path.name}#row={ordinal}"
            )
            record = {
                **derived,
                "team": team,
                "team_key": TEAM_KEYS[team],
                "excluded": excluded,
                "exclusion_reason": derived["row_values"]["Exclusion Reason"] or None,
                "source_group": item["group"],
                "source_task_id": item["task_id"],
                "source_file_name": path.name,
                "source_artifact_sha256": item["sha256"],
                "source_row_number": source_row_number,
                "source_locator": source_locator,
                "source_artifact_row_sha256": source_artifact_row_sha256,
                "verified_urc_fixture": is_verified_fixture_addition(
                    derived["row_values"], excluded
                ),
            }
            record["final_master_row_sha256"] = canonical_sha256(
                [record["row_values"][header] for header in CANONICAL_HEADERS]
            )
            by_team[team].append(record)

    if list(config["teams"]) != TEAM_ORDER:
        raise ConsolidationError("config team order must match the frozen 16-team order")
    for team in TEAM_ORDER:
        expected = config["teams"][team]
        if raw_team_counts[team] != expected["genuine_rows"]:
            raise ConsolidationError(f"{team}: genuine row count changed")
        if raw_included_counts[team] != expected["included_rows"]:
            raise ConsolidationError(f"{team}: included row count changed")
        if expected["physical_rows"] != (
            expected["genuine_rows"]
            + expected.get("non_record_rows", 0)
            + expected.get("superseded_rows", 0)
        ):
            raise ConsolidationError(f"{team}: physical row conservation failed")

    records: list[dict[str, Any]] = []
    for team in TEAM_ORDER:
        records.extend(by_team[team])
    for index, record in enumerate(records, start=2):
        record["source_row"] = index

    master_rows = [record["row_values"] for record in records]
    included_records = [record for record in records if not record["excluded"]]
    inclusion_rows = [record["row_values"] for record in included_records]
    write_csv(root / config["outputs"]["master_csv"], CANONICAL_HEADERS, master_rows)
    write_csv(root / config["outputs"]["inclusion_csv"], CANONICAL_HEADERS, inclusion_rows)

    evidence_headers = [
        "Source Row", "Team Key", "Source Group", "Source Task ID", "Source File",
        "Source Artifact SHA-256", "Source Row Number", "Source Locator",
        "Source Artifact Row SHA-256", "Final Master Row SHA-256", "Included",
        "Dashboard Injury Eligible", "Qualifying Source Classification",
        "Participation Restriction Evidence", "Final Classification",
        "Classification Basis", "Clinical Duration Days", "Clinical Duration Basis",
        "Time Loss Days", "Return Date", "Return Date Basis", "Open Status",
        "Unrestricted Participation Evidence",
        "Source Conflict", "Review Required", "Review Reasons", "Derived Fields",
        "Verified URC Fixture",
    ]
    evidence_rows = []
    for record in records:
        evidence_rows.append({
            "Source Row": record["source_row"],
            "Team Key": record["team_key"],
            "Source Group": record["source_group"],
            "Source Task ID": record["source_task_id"],
            "Source File": record["source_file_name"],
            "Source Artifact SHA-256": record["source_artifact_sha256"],
            "Source Row Number": record["source_row_number"],
            "Source Locator": record["source_locator"],
            "Source Artifact Row SHA-256": record["source_artifact_row_sha256"],
            "Final Master Row SHA-256": record["final_master_row_sha256"],
            "Included": str(not record["excluded"]).lower(),
            "Dashboard Injury Eligible": str(not record["excluded"] and record["row_values"]["Problem type"] == "Injury").lower(),
            "Qualifying Source Classification": (
                record["qualifying_source_classification"] or ""
            ),
            "Participation Restriction Evidence": (
                "" if record["participation_restriction_evidence"] is None
                else str(record["participation_restriction_evidence"]).lower()
            ),
            "Final Classification": record["final_classification"],
            "Classification Basis": record["classification_basis"],
            "Clinical Duration Days": "" if record["clinical_duration_days"] is None else record["clinical_duration_days"],
            "Clinical Duration Basis": record["clinical_duration_basis"],
            "Time Loss Days": "" if record["time_loss_days"] is None else record["time_loss_days"],
            "Return Date": record["return_date"] or "",
            "Return Date Basis": record["return_date_basis"],
            "Open Status": str(record["open_status"]).lower(),
            "Unrestricted Participation Evidence": str(
                record["unrestricted_participation_evidence"]
            ).lower(),
            "Source Conflict": str(record["source_conflict"]).lower(),
            "Review Required": str(record["review_required"]).lower(),
            "Review Reasons": "; ".join(record["review_reasons"]),
            "Derived Fields": "; ".join(record["derived_fields"]),
            "Verified URC Fixture": str(record["verified_urc_fixture"]).lower(),
        })
    write_csv(root / config["outputs"]["classification_evidence_csv"], evidence_headers, evidence_rows)

    style_map = {
        str(record["source_row"]): {
            "excluded": record["excluded"],
            "derived_fields": record["derived_fields"],
            "verified_urc_fixture": record["verified_urc_fixture"],
        }
        for record in records
    }
    (root / config["outputs"]["style_map_json"]).write_text(
        json.dumps(style_map, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    dashboard_records = [
        record for record in included_records if record["row_values"]["Problem type"] == "Injury"
    ]
    summary = {
        "schema_version": "urc_2025_26_consolidation_summary_v1",
        "consolidation_id": config["consolidation_id"],
        "master_rows": len(records),
        "included_rows": len(included_records),
        "excluded_rows": len(records) - len(included_records),
        "dashboard_injury_rows": len(dashboard_records),
        "illness_rows_in_inclusion_layer": len(included_records) - len(dashboard_records),
        "teams": {
            team: {
                **config["teams"][team],
                "master_rows_verified": raw_team_counts[team],
                "included_rows_verified": raw_included_counts[team],
            }
            for team in TEAM_ORDER
        },
        "classification_dashboard_injuries": dict(sorted(Counter(
            record["final_classification"] for record in dashboard_records
        ).items())),
        "classification_all_included_records": dict(sorted(Counter(
            record["final_classification"] for record in included_records
        ).items())),
        "open_dashboard_injuries": sum(record["open_status"] for record in dashboard_records),
        "open_time_loss_dashboard_injuries": sum(
            record["open_status"] and record["final_classification"] == "Time Loss"
            for record in dashboard_records
        ),
        "open_time_loss_dashboard_injuries_with_unrestricted_evidence": sum(
            record["open_status"]
            and record["final_classification"] == "Time Loss"
            and record["unrestricted_participation_evidence"]
            for record in dashboard_records
        ),
        "open_time_loss_dashboard_injuries_without_unrestricted_evidence": sum(
            record["open_status"]
            and record["final_classification"] == "Time Loss"
            and not record["unrestricted_participation_evidence"]
            for record in dashboard_records
        ),
        "time_loss_dashboard_injuries_with_null_days": sum(
            record["final_classification"] == "Time Loss" and record["time_loss_days"] is None
            for record in dashboard_records
        ),
        "medical_attention_dashboard_injuries_with_positive_clinical_duration": sum(
            record["final_classification"] == "Medical Attention"
            and (record["clinical_duration_days"] or 0) > 0
            for record in dashboard_records
        ),
        "source_conflicts": sum(record["source_conflict"] for record in records),
        "review_required": sum(record["review_required"] for record in records),
        "duplicate_exclusions": sum(
            "duplicate" in clean(record["exclusion_reason"]).casefold() for record in records
        ),
        "source_copy_manifest_sha256": sha256_file(root / "source_copy_manifest.json"),
        "source_bundle_sha256": copy_manifest["bundle_sha256"],
    }
    (root / config["outputs"]["summary_json"]).write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def _bool(value: str) -> bool:
    if value not in {"true", "false"}:
        raise ConsolidationError(f"invalid boolean {value!r}")
    return value == "true"


def _successor_master_state(
    source_row: int,
    row: dict[str, str],
    evidence: dict[str, str],
) -> dict[str, Any]:
    return {
        "source_row": source_row,
        "team_key": evidence["Team Key"],
        "source_group": evidence["Source Group"],
        "source_task_id": evidence["Source Task ID"],
        "source_file_name": evidence["Source File"],
        "source_artifact_sha256": evidence["Source Artifact SHA-256"],
        "source_row_number": evidence["Source Row Number"],
        "source_locator": evidence["Source Locator"],
        "source_artifact_row_sha256": evidence["Source Artifact Row SHA-256"],
        "final_master_row_sha256": evidence["Final Master Row SHA-256"],
        "row_values": {header: row[header] for header in CANONICAL_HEADERS},
        "excluded": bool(row["Exclusion Reason"]),
        "exclusion_reason": row["Exclusion Reason"] or None,
        "qualifying_source_classification": (
            evidence["Qualifying Source Classification"] or None
        ),
        "final_classification": evidence["Final Classification"],
        "classification_basis": evidence["Classification Basis"],
        "clinical_duration_days": (
            int(evidence["Clinical Duration Days"])
            if evidence["Clinical Duration Days"] else None
        ),
        "clinical_duration_basis": evidence["Clinical Duration Basis"],
        "time_loss_days": (
            int(evidence["Time Loss Days"])
            if evidence["Time Loss Days"] else None
        ),
        "return_date": evidence["Return Date"] or None,
        "return_date_basis": evidence["Return Date Basis"],
        "open_status": _bool(evidence["Open Status"]),
        "participation_restriction_evidence": (
            None
            if not evidence["Participation Restriction Evidence"]
            else _bool(evidence["Participation Restriction Evidence"])
        ),
        "unrestricted_participation_evidence": _bool(
            evidence["Unrestricted Participation Evidence"]
        ),
        "source_conflict": _bool(evidence["Source Conflict"]),
        "review_required": _bool(evidence["Review Required"]),
        "review_reasons": [
            item for item in evidence["Review Reasons"].split("; ") if item
        ],
        "derived_fields": [
            item for item in evidence["Derived Fields"].split("; ") if item
        ],
        "verified_urc_fixture": _bool(evidence["Verified URC Fixture"]),
    }


def finalise_successor(config_path: Path) -> None:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    root = Path(config["root"])
    outputs = config["outputs"]
    successor = config["successor"]
    current_paths = {
        name: root / outputs[name]
        for name in (
            "master_csv", "master_workbook", "inclusion_csv",
            "classification_evidence_csv", "summary_json", "style_map_json",
        )
    }
    current_paths["source_copy_manifest"] = root / "source_copy_manifest.json"
    current_paths["migration"] = Path(successor["migration_path"])
    current_paths["registration_sql"] = Path(successor["registration_sql_path"])
    predecessor_payload_path = Path(successor["predecessor_load_payload_path"])
    predecessor_manifest_path = Path(successor["predecessor_manifest_path"])
    for path in (*current_paths.values(), predecessor_payload_path, predecessor_manifest_path):
        if not path.is_file():
            raise ConsolidationError(f"missing successor artefact {path}")

    hashes = {name: sha256_file(path) for name, path in current_paths.items()}
    for name, expected in successor["accepted_hashes"].items():
        if hashes[name] != expected:
            raise ConsolidationError(f"accepted {name} hash changed")
    if sha256_file(predecessor_payload_path) != successor["predecessor_load_payload_sha256"]:
        raise ConsolidationError("installed predecessor payload hash changed")
    if sha256_file(predecessor_manifest_path) != successor["predecessor_manifest_sha256"]:
        raise ConsolidationError("installed predecessor manifest hash changed")

    summary = json.loads(current_paths["summary_json"].read_text(encoding="utf-8"))
    source_manifest = json.loads(
        current_paths["source_copy_manifest"].read_text(encoding="utf-8")
    )
    predecessor_payload = json.loads(predecessor_payload_path.read_text(encoding="utf-8"))
    predecessor_versions = [item for item in predecessor_payload if item["kind"] == "version"]
    if len(predecessor_versions) != 1:
        raise ConsolidationError("installed predecessor version payload changed")
    predecessor_version = predecessor_versions[0]
    if predecessor_version["id"] != successor["predecessor_version_id"]:
        raise ConsolidationError("installed predecessor version id changed")
    if predecessor_version["source_bundle_sha256"] != source_manifest["bundle_sha256"]:
        raise ConsolidationError("source bundle changed between predecessor and successor")

    predecessor_states = {
        item["source_row"]: {
            key: value for key, value in item.items()
            if key not in {"kind", "version_id"}
        }
        for item in predecessor_payload if item["kind"] == "master_row"
    }
    predecessor_inclusion = {
        item["source_row"] for item in predecessor_payload
        if item["kind"] == "inclusion_row"
    }
    _, master_rows = read_csv(current_paths["master_csv"])
    _, inclusion_rows = read_csv(current_paths["inclusion_csv"])
    _, evidence_rows = read_dict_csv(current_paths["classification_evidence_csv"])
    if len(master_rows) != len(evidence_rows) or len(master_rows) != len(predecessor_states):
        raise ConsolidationError("successor master cardinality changed")
    evidence_by_source = {int(row["Source Row"]): row for row in evidence_rows}
    successor_states = {
        source_row: _successor_master_state(source_row, row, evidence_by_source[source_row])
        for source_row, row in enumerate(master_rows, start=2)
    }
    successor_inclusion = {
        source_row for source_row, state in successor_states.items() if not state["excluded"]
    }
    if successor_inclusion != predecessor_inclusion or len(inclusion_rows) != len(successor_inclusion):
        raise ConsolidationError("successor inclusion membership changed")

    immutable_fields = {
        "source_row", "team_key", "source_group", "source_task_id", "source_file_name",
        "source_artifact_sha256", "source_row_number", "source_locator",
        "source_artifact_row_sha256", "excluded", "exclusion_reason", "open_status",
        "verified_urc_fixture",
    }
    changed_fields: Counter[str] = Counter()
    deltas = []
    changed_master_rows = 0
    changed_classification_rows = 0
    changed_duration_rows = 0
    changed_inclusion_rows = 0
    for source_row, current in successor_states.items():
        predecessor = predecessor_states[source_row]
        if current == predecessor:
            continue
        fields = sorted(key for key in current if current[key] != predecessor[key])
        if immutable_fields.intersection(fields):
            raise ConsolidationError(
                f"source or inclusion identity changed at source row {source_row}"
            )
        changed_fields.update(fields)
        if current["row_values"] != predecessor["row_values"]:
            changed_master_rows += 1
            if source_row in successor_inclusion:
                changed_inclusion_rows += 1
        if current["final_classification"] != predecessor["final_classification"]:
            changed_classification_rows += 1
        if current["clinical_duration_days"] != predecessor["clinical_duration_days"]:
            changed_duration_rows += 1
        deltas.append({
            "kind": "row_delta",
            "source_row": source_row,
            "predecessor": predecessor,
            "successor": current,
            "changed_fields": fields,
        })

    expected = successor["expected_delta"]
    actual = {
        "affected_row_count": len(deltas),
        "changed_master_row_count": changed_master_rows,
        "changed_inclusion_row_count": changed_inclusion_rows,
        "changed_classification_row_count": changed_classification_rows,
        "changed_duration_row_count": changed_duration_rows,
    }
    if actual != expected:
        raise ConsolidationError(f"successor delta changed: {actual!r}")

    version_id = str(uuid.uuid5(
        UUID_NAMESPACE,
        f"{config['consolidation_id']}|{hashes['master_csv']}|{config['classification_rule_version']}|{successor['predecessor_version_id']}",
    ))
    master_json_sha = canonical_sha256([
        {header: row[header] for header in CANONICAL_HEADERS} for row in master_rows
    ])
    inclusion_json_sha = canonical_sha256([
        {header: row[header] for header in CANONICAL_HEADERS} for row in inclusion_rows
    ])
    delta_evidence = {
        "schema_version": "urc_2025_26_injury_successor_delta_v1",
        "predecessor_version_id": successor["predecessor_version_id"],
        "successor_version_id": version_id,
        "classification_rule_version": config["classification_rule_version"],
        **actual,
        "changed_field_counts": dict(sorted(changed_fields.items())),
        "affected_source_rows": [item["source_row"] for item in deltas],
        "master_csv_sha256": hashes["master_csv"],
        "inclusion_csv_sha256": hashes["inclusion_csv"],
        "classification_evidence_sha256": hashes["classification_evidence_csv"],
        "source_bundle_sha256": source_manifest["bundle_sha256"],
        "master_json_sha256": master_json_sha,
        "inclusion_json_sha256": inclusion_json_sha,
        "inclusion_membership_changed": False,
        "source_identity_changed": False,
        "excluded_rows_remain_audit_only": True,
    }
    delta_evidence_path = root / outputs["delta_evidence_json"]
    delta_evidence_path.write_text(
        json.dumps(delta_evidence, indent=2) + "\n", encoding="utf-8"
    )
    delta_evidence_sha = sha256_file(delta_evidence_path)

    manifest = {
        "schema_version": "urc_2025_26_injury_successor_manifest_v1",
        "consolidation_id": config["consolidation_id"],
        "version_id": version_id,
        "version_label": config["version_label"],
        "season": "2025-26",
        "generated_at": config["generated_at"],
        "classification_rule_version": config["classification_rule_version"],
        "classification_contract": config["classification_contract"],
        "predecessor": {
            "version_id": successor["predecessor_version_id"],
            "manifest_sha256": successor["predecessor_manifest_sha256"],
            "load_payload_sha256": successor["predecessor_load_payload_sha256"],
        },
        "summary": summary,
        "delta": {**actual, "sha256": delta_evidence_sha},
        "artefacts": {
            name: {"path": str(path), "sha256": hashes[name], "bytes": path.stat().st_size}
            for name, path in current_paths.items()
        },
        "database_boundary": {
            "project_ref": "eukkvswaxweenovqqgzr",
            "database": "postgres",
            "scope": "additive private injury lineage successor only",
            "excluded": ["exposure", "rates", "dashboard release", "promotion", "deployment"],
        },
        "frozen_2024_25": config["frozen_2024_25"],
    }
    manifest_path = root / outputs["manifest_json"]
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    manifest_sha = sha256_file(manifest_path)

    payload = [{
        "kind": "version",
        "id": version_id,
        "predecessor_version_id": successor["predecessor_version_id"],
        "season": "2025-26",
        "version_label": config["version_label"],
        "classification_rule_version": config["classification_rule_version"],
        "migration_version": successor["migration_version"],
        "migration_sha256": hashes["migration"],
        "master_csv_sha256": hashes["master_csv"],
        "master_workbook_sha256": hashes["master_workbook"],
        "inclusion_csv_sha256": hashes["inclusion_csv"],
        "classification_evidence_sha256": hashes["classification_evidence_csv"],
        "manifest_sha256": manifest_sha,
        "source_bundle_sha256": source_manifest["bundle_sha256"],
        "master_json_sha256": master_json_sha,
        "inclusion_json_sha256": inclusion_json_sha,
        "delta_evidence_sha256": delta_evidence_sha,
        "master_row_count": summary["master_rows"],
        "included_row_count": summary["included_rows"],
        "excluded_row_count": summary["excluded_rows"],
        "dashboard_injury_row_count": summary["dashboard_injury_rows"],
        "team_count": len(summary["teams"]),
        **{key: actual[key] for key in (
            "affected_row_count", "changed_master_row_count",
            "changed_classification_row_count", "changed_duration_row_count",
        )},
        "classification_contract": config["classification_contract"],
        "summary": summary,
    }, *deltas]
    payload_path = root / outputs["delta_payload_json"]
    payload_path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    finalisation = {
        "manifest_path": str(manifest_path),
        "manifest_sha256": manifest_sha,
        "delta_payload_path": str(payload_path),
        "delta_payload_sha256": sha256_file(payload_path),
        "delta_evidence_path": str(delta_evidence_path),
        "delta_evidence_sha256": delta_evidence_sha,
        "version_id": version_id,
        "predecessor_version_id": successor["predecessor_version_id"],
        "master_json_sha256": master_json_sha,
        "inclusion_json_sha256": inclusion_json_sha,
        **actual,
    }
    (root / outputs["finalisation_evidence_json"]).write_text(
        json.dumps(finalisation, indent=2) + "\n", encoding="utf-8"
    )


def finalise(config_path: Path) -> None:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    root = Path(config["root"])
    outputs = config["outputs"]
    required = {
        name: root / outputs[name]
        for name in (
            "master_csv", "master_workbook", "inclusion_csv",
            "classification_evidence_csv", "summary_json", "style_map_json",
        )
    }
    required["source_copy_manifest"] = root / "source_copy_manifest.json"
    required["migration"] = Path(config["migration_path"])
    required["registration_sql"] = Path(config["registration_sql_path"])
    for path in required.values():
        if not path.is_file():
            raise ConsolidationError(f"missing final artefact {path}")
    hashes = {name: sha256_file(path) for name, path in required.items()}
    if hashes["migration"] != config["migration_sha256"]:
        raise ConsolidationError("migration hash changed after review binding")

    summary = json.loads(required["summary_json"].read_text(encoding="utf-8"))
    source_manifest = json.loads(required["source_copy_manifest"].read_text(encoding="utf-8"))
    fixture_path = root / config["fixtures_relative_path"]
    fixtures = json.loads(fixture_path.read_text(encoding="utf-8"))
    if len(fixtures) != 151:
        raise ConsolidationError("accepted fixture count changed")
    version_id = str(uuid.uuid5(
        UUID_NAMESPACE,
        f"{config['consolidation_id']}|{hashes['master_csv']}|{config['classification_rule_version']}",
    ))
    manifest = {
        "schema_version": "urc_2025_26_injury_ingest_manifest_v1",
        "consolidation_id": config["consolidation_id"],
        "version_id": version_id,
        "version_label": config["version_label"],
        "season": "2025-26",
        "generated_at": config["generated_at"],
        "classification_rule_version": config["classification_rule_version"],
        "classification_contract": config["classification_contract"],
        "source_copy_manifest": source_manifest,
        "summary": summary,
        "fixture_evidence": {
            "rows": len(fixtures),
            "sha256": sha256_file(fixture_path),
            "source": "live analysis.accepted_urc_fixtures_v6 from the approved target",
        },
        "artefacts": {
            name: {"path": str(path), "sha256": hashes[name], "bytes": path.stat().st_size}
            for name, path in required.items()
        },
        "database_boundary": {
            "project_ref": "eukkvswaxweenovqqgzr",
            "database": "postgres",
            "scope": "additive private injury lineage ingest only",
            "excluded": ["exposure", "rates", "dashboard release", "promotion", "deployment"],
        },
        "frozen_2024_25": config["frozen_2024_25"],
    }
    manifest_path = root / outputs["manifest_json"]
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    manifest_sha = sha256_file(manifest_path)
    database_source_manifest = {
        "schema_version": source_manifest["schema_version"],
        "consolidation_id": source_manifest["consolidation_id"],
        "bundle_sha256": source_manifest["bundle_sha256"],
        "files": [
            {
                key: item[key]
                for key in (
                    "group", "task_id", "role", "relative_path", "sha256", "bytes"
                )
            }
            for item in source_manifest["files"]
        ],
    }

    _, master_rows = read_csv(required["master_csv"])
    _, inclusion_rows = read_csv(required["inclusion_csv"])
    _, evidence_rows = read_dict_csv(required["classification_evidence_csv"])
    if len(master_rows) != len(evidence_rows):
        raise ConsolidationError("classification evidence row count changed")
    evidence_by_source = {int(row["Source Row"]): row for row in evidence_rows}
    master_json_sha = canonical_sha256([
        {header: row[header] for header in CANONICAL_HEADERS} for row in master_rows
    ])
    inclusion_json_sha = canonical_sha256([
        {header: row[header] for header in CANONICAL_HEADERS} for row in inclusion_rows
    ])

    payload: list[dict[str, Any]] = [{
        "kind": "version",
        "id": version_id,
        "season": "2025-26",
        "version_label": config["version_label"],
        "classification_rule_version": config["classification_rule_version"],
        "migration_version": config["migration_version"],
        "migration_sha256": hashes["migration"],
        "master_csv_sha256": hashes["master_csv"],
        "master_workbook_sha256": hashes["master_workbook"],
        "inclusion_csv_sha256": hashes["inclusion_csv"],
        "classification_evidence_sha256": hashes["classification_evidence_csv"],
        "manifest_sha256": manifest_sha,
        "source_bundle_sha256": source_manifest["bundle_sha256"],
        "master_json_sha256": master_json_sha,
        "inclusion_json_sha256": inclusion_json_sha,
        "master_row_count": summary["master_rows"],
        "included_row_count": summary["included_rows"],
        "excluded_row_count": summary["excluded_rows"],
        "dashboard_injury_row_count": summary["dashboard_injury_rows"],
        "team_count": len(summary["teams"]),
        "source_manifest": database_source_manifest,
        "classification_contract": config["classification_contract"],
        "summary": summary,
    }]
    inclusion_source_rows = []
    inclusion_index = 2
    for source_row, row in enumerate(master_rows, start=2):
        evidence = evidence_by_source[source_row]
        excluded = bool(row["Exclusion Reason"])
        payload.append({
            "kind": "master_row",
            "version_id": version_id,
            "source_row": source_row,
            "team_key": evidence["Team Key"],
            "source_group": evidence["Source Group"],
            "source_task_id": evidence["Source Task ID"],
            "source_file_name": evidence["Source File"],
            "source_artifact_sha256": evidence["Source Artifact SHA-256"],
            "source_row_number": evidence["Source Row Number"],
            "source_locator": evidence["Source Locator"],
            "source_artifact_row_sha256": evidence["Source Artifact Row SHA-256"],
            "final_master_row_sha256": evidence["Final Master Row SHA-256"],
            "row_values": {header: row[header] for header in CANONICAL_HEADERS},
            "excluded": excluded,
            "exclusion_reason": row["Exclusion Reason"] or None,
            "qualifying_source_classification": (
                evidence["Qualifying Source Classification"] or None
            ),
            "participation_restriction_evidence": (
                None
                if not evidence["Participation Restriction Evidence"]
                else _bool(evidence["Participation Restriction Evidence"])
            ),
            "final_classification": evidence["Final Classification"],
            "classification_basis": evidence["Classification Basis"],
            "clinical_duration_days": int(evidence["Clinical Duration Days"]) if evidence["Clinical Duration Days"] else None,
            "clinical_duration_basis": evidence["Clinical Duration Basis"],
            "time_loss_days": int(evidence["Time Loss Days"]) if evidence["Time Loss Days"] else None,
            "return_date": evidence["Return Date"] or None,
            "return_date_basis": evidence["Return Date Basis"],
            "open_status": _bool(evidence["Open Status"]),
            "unrestricted_participation_evidence": _bool(
                evidence["Unrestricted Participation Evidence"]
            ),
            "source_conflict": _bool(evidence["Source Conflict"]),
            "review_required": _bool(evidence["Review Required"]),
            "review_reasons": [item for item in evidence["Review Reasons"].split("; ") if item],
            "derived_fields": [item for item in evidence["Derived Fields"].split("; ") if item],
            "verified_urc_fixture": _bool(evidence["Verified URC Fixture"]),
        })
        if not excluded:
            inclusion_source_rows.append(source_row)
            payload.append({
                "kind": "inclusion_row",
                "version_id": version_id,
                "inclusion_row": inclusion_index,
                "source_row": source_row,
                "team_key": evidence["Team Key"],
                "row_values": {header: row[header] for header in CANONICAL_HEADERS},
                "row_sha256": evidence["Final Master Row SHA-256"],
                "dashboard_eligible": row["Problem type"] == "Injury",
                "dashboard_eligibility_reason": (
                    "injury_record" if row["Problem type"] == "Injury"
                    else "illness_record_not_in_injury_cohort"
                ),
            })
            inclusion_index += 1
    if len(inclusion_source_rows) != len(inclusion_rows):
        raise ConsolidationError("inclusion payload count changed")
    payload_path = root / outputs["load_payload_json"]
    payload_path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    evidence = {
        "manifest_path": str(manifest_path),
        "manifest_sha256": manifest_sha,
        "load_payload_path": str(payload_path),
        "load_payload_sha256": sha256_file(payload_path),
        "version_id": version_id,
        "master_json_sha256": master_json_sha,
        "inclusion_json_sha256": inclusion_json_sha,
    }
    (root / outputs["finalisation_evidence_json"]).write_text(
        json.dumps(evidence, indent=2) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("build", "finalise", "finalise-successor"))
    parser.add_argument("config", type=Path)
    args = parser.parse_args()
    if args.command == "build":
        build(args.config)
    elif args.command == "finalise":
        finalise(args.config)
    else:
        finalise_successor(args.config)


if __name__ == "__main__":
    main()
