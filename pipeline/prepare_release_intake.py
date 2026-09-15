#!/usr/bin/env python3
"""Package the reviewed IRFU 2025-26 source rows for a local release candidate.

This reads the already-reviewed master and audit outputs. It does not clean,
classify, promote, or write to a database.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from pipeline.__main__ import INJURY_TYPE_LABEL_TO_KEY, body_location


TEAM_ORDER = ("leinster", "munster", "ulster", "connacht")
SEASON = "2025-26"
SOURCE_MASTER = "{team}/{team}_master_ready_2025-26.csv"
SOURCE_STANDARDISED = "{team}/{team}_{kind}_standardised_2025-26.csv"
SOURCE_PROVENANCE = "{team}/standardised_row_provenance.csv"
LEDGER_FILE = "combined_decision_ledger.csv"
DATE_AUDIT_FILE = "combined_date_conversion_audit.csv"
CLINICAL_AUDIT_FILE = "combined_clinical_code_audit.csv"

CANONICAL_COLUMNS = (
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
)

PROVENANCE_COLUMNS = (
    "source_uid",
    "source_uid_origin",
    "source_file_sha256",
    "source_sheet",
    "source_row_number",
    "source_locator",
    "source_cell_locator",
    "source_event_id",
    "source_occurrence_id",
    "source_type",
    "team_master_row",
    "candidate_source_row",
    "candidate_disposition",
    "exclusion_reason",
    "identity_review_required",
    "clinical_tissue_review_required",
    "approval_status",
    "live_action_authorised",
)

INJURY_COLUMNS = (
    "season",
    "team_key",
    "source_row",
    "injury_date",
    "is_time_loss",
    "days_lost",
    "setting_code",
    "contact_context",
    "body_location_code",
    "body_location_label",
    "injury_type_code",
    "injury_type_label",
    "diagnosis_code",
    "diagnosis_label",
    "severity_code",
)

ILLNESS_COLUMNS = (
    "season",
    "team_key",
    "source_row",
    "illness_code",
    "illness_label",
    "duration_known",
    "days_lost",
)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean(value: object) -> str:
    return str(value or "").strip()


def code(value: object) -> str:
    value = clean(value).lower()
    return re.sub(r"[^a-z0-9]+", "_", value).strip("_") or "unknown"


def optional_int(value: object) -> int | None:
    value = clean(value)
    if not value:
        return None
    if not re.fullmatch(r"[-+]?\d+", value):
        raise ValueError(f"expected integer, got {value!r}")
    return int(value)


def source_metadata(
    master_row: dict[str, str],
    standardised_row: dict[str, str],
    provenance_row: dict[str, str],
    date_row: dict[str, str],
    team: str,
    master_row_number: int,
) -> dict[str, object]:
    """Combine preserved source locators without changing source values."""

    def first(*keys: str) -> str:
        for key in keys:
            value = clean(standardised_row.get(key)) or clean(provenance_row.get(key))
            if value:
                return value
        return ""

    source_type = first("Source Type") or clean(date_row.get("source_type"))
    if not source_type:
        source_type = "injury" if master_row["Problem type"] == "Injury" else "illness"
    source_sha = first("Source File SHA-256") or clean(date_row.get("source_file_sha256"))
    source_number_text = (
        first("Source Row Number")
        or clean(date_row.get("source_row_number"))
    )
    source_number = optional_int(source_number_text)
    if source_number is None:
        # The date audit has no source row number for one legacy source, while
        # its preserved cell locator still identifies the original row.
        cell = clean(date_row.get("source_cell_locator"))
        match = re.search(r"(\d+)$", cell)
        source_number = int(match.group(1)) if match else None

    source_sheet = (
        first("Source Sheet")
        or clean(date_row.get("source_sheet_or_table"))
        or clean(date_row.get("sheet_or_table"))
    )
    source_cell = clean(date_row.get("source_cell_locator"))
    source_locator = clean(date_row.get("source_row_locator"))
    if not source_locator and source_sheet and source_number is not None:
        source_locator = f"{source_sheet}!row-{source_number}"
    if not source_locator and source_sha and source_number is not None:
        source_locator = f"{source_sha}#row-{source_number}"
    if not source_locator and source_cell:
        source_locator = source_cell
    if not source_locator:
        source_locator = f"master-row-{master_row_number}"

    source_uid = first("Source Row ID")
    source_uid_origin = "source_row_id"
    if not source_uid and source_sha and source_number is not None:
        source_uid = f"{team}:{source_type}:{source_sha}:row-{source_number}"
        source_uid_origin = "derived_from_source_file_and_row"
    if not source_uid:
        raise ValueError(f"missing source UID for {team} master row {master_row_number}")

    return {
        "source_uid": source_uid,
        "source_uid_origin": source_uid_origin,
        "source_file_sha256": source_sha,
        "source_sheet": source_sheet,
        "source_row_number": source_number,
        "source_locator": source_locator,
        "source_cell_locator": source_cell,
        "source_event_id": first("Source Event ID"),
        "source_occurrence_id": first("Source Occurrence ID"),
        "source_type": source_type,
    }


def injury_typed_row(row: dict[str, str], source_row: int) -> dict[str, object]:
    final_classification = clean(row.get("TimeLoss vs Medical Attention"))
    is_time_loss = final_classification == "Time Loss"
    days = optional_int(row.get("Days Injured"))
    days_lost = days if is_time_loss and days is not None and days > 0 else None
    if final_classification == "Medical Attention":
        severity = "zero_days_medical_attention_only"
    elif days_lost is None:
        severity = "unknown_or_censored"
    elif days_lost == 1:
        severity = "one_day"
    elif days_lost <= 3:
        severity = "two_to_three_days"
    elif days_lost <= 7:
        severity = "four_to_seven_days"
    elif days_lost <= 28:
        severity = "eight_to_twenty_eight_days"
    else:
        severity = "greater_than_twenty_eight_days"

    occasion = clean(row.get("Occasion category")).lower()
    if "match" in occasion:
        setting = "match"
    elif "training" in occasion:
        setting = "training"
    else:
        setting = "unknown"
    contact = clean(row.get("Is Contact")).lower()
    if contact == "contact":
        contact_context = "contact"
    elif contact in {"non-contact", "non contact"}:
        contact_context = "non_contact"
    else:
        contact_context = "unknown"

    body_label = clean(row.get("Body Part")) or "Unknown"
    tissue_label = clean(row.get("Injury Tissue Type/s")) or "Unknown"
    diagnosis_label = clean(row.get("Specific Diagnosis")) or "Unknown"
    # Call the shared mapper with Orchard blank so an inconsistent code cannot
    # override the reviewed source body label.
    body_code, _ = body_location({"Body Part": body_label, "Orchard Code": ""})
    return {
        "season": SEASON,
        "team_key": clean(row.get("Team")).lower(),
        "source_row": source_row,
        "injury_date": clean(row.get("Date Injured")) or None,
        "is_time_loss": is_time_loss,
        "days_lost": days_lost,
        "setting_code": setting,
        "contact_context": contact_context,
        "body_location_code": body_code,
        "body_location_label": body_label,
        "injury_type_code": INJURY_TYPE_LABEL_TO_KEY.get(tissue_label.lower(), "unknown"),
        "injury_type_label": tissue_label,
        "diagnosis_code": code(diagnosis_label),
        "diagnosis_label": diagnosis_label,
        "severity_code": severity,
    }


def illness_typed_row(row: dict[str, str], source_row: int) -> dict[str, object]:
    label = clean(row.get("Specific Diagnosis")) or clean(row.get("Diagnosis")) or "Unknown"
    raw_days = clean(row.get("Days Injured"))
    days = optional_int(raw_days)
    duration_known = bool(raw_days)
    return {
        "season": SEASON,
        "team_key": clean(row.get("Team")).lower(),
        "source_row": source_row,
        "illness_code": clean(row.get("Illness Code")) or "illness_identity_" + hashlib.sha256(label.encode()).hexdigest(),
        "illness_label": label,
        "duration_known": duration_known,
        "days_lost": days if duration_known else None,
    }


def write_csv(path: Path, rows: Iterable[dict[str, object]], columns: tuple[str, ...]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(columns), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--private-root",
        type=Path,
        default=Path("/Users/abdelbabiker/Desktop/URC-V2-DB-private/2025-26/irfu_rebuild_20260914_v1"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "outputs/intake_release_20260915/intake",
    )
    args = parser.parse_args()
    private_root = args.private_root.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    ledger_rows = read_csv(private_root / LEDGER_FILE)
    ledger = {}
    for item in ledger_rows:
        key = (clean(item["team"]).lower(), int(item["team_master_row"]))
        if key in ledger:
            raise ValueError(f"duplicate ledger key {key}")
        ledger[key] = item
    if len(ledger) != 842:
        raise ValueError(f"expected 842 reviewed ledger rows, got {len(ledger)}")

    date_rows = read_csv(private_root / DATE_AUDIT_FILE)
    date_by_master = {
        (clean(row["Package Team"]).lower(), int(row["Package Audit Row"])): row
        for row in date_rows
    }
    clinical_rows = read_csv(private_root / CLINICAL_AUDIT_FILE)
    clinical_by_std_row = {
        (clean(row["team"]).lower(), int(row["standardised_injury_row"])): row
        for row in clinical_rows
    }

    all_source_rows: list[dict[str, object]] = []
    bridge: list[dict[str, object]] = []
    typed_injuries: list[dict[str, object]] = []
    typed_illnesses: list[dict[str, object]] = []
    team_stats: dict[str, Counter] = defaultdict(Counter)
    global_ordinal = 0

    for team in TEAM_ORDER:
        master_path = private_root / SOURCE_MASTER.format(team=team)
        master_rows = read_csv(master_path)
        injury_std = read_csv(private_root / SOURCE_STANDARDISED.format(team=team, kind="injury"))
        illness_std = read_csv(private_root / SOURCE_STANDARDISED.format(team=team, kind="illness"))
        standardised_rows = injury_std + illness_std
        provenance_path = private_root / SOURCE_PROVENANCE.format(team=team)
        provenance_rows = read_csv(provenance_path) if provenance_path.exists() else [{} for _ in master_rows]
        if len(master_rows) != len(standardised_rows) or len(master_rows) != len(provenance_rows):
            raise ValueError(f"row alignment mismatch for {team}")
        if [clean(row.get("Problem type")) for row in master_rows] != [clean(row.get("Problem type")) for row in standardised_rows]:
            raise ValueError(f"problem type alignment mismatch for {team}")

        source_rows_for_csv: list[dict[str, object]] = []
        for index, (master_row, std_row, provenance_row) in enumerate(
            zip(master_rows, standardised_rows, provenance_rows), start=1
        ):
            global_ordinal += 1
            master_row_number = index + 1
            ledger_row = ledger.get((team, master_row_number))
            if ledger_row is None:
                raise ValueError(f"missing ledger row for {team} master row {master_row_number}")
            if clean(master_row.get("Team")).lower() != team:
                raise ValueError(f"team column mismatch at {team} master row {master_row_number}")
            if clean(ledger_row["problem_type"]) != clean(master_row["Problem type"]):
                raise ValueError(f"problem type differs from ledger at {team} row {master_row_number}")
            date_row = date_by_master.get((team, master_row_number))
            if date_row is None:
                raise ValueError(f"missing date locator for {team} master row {master_row_number}")
            meta = source_metadata(master_row, std_row, provenance_row, date_row, team, master_row_number)
            candidate_source_row = 100000 + global_ordinal
            disposition = clean(ledger_row["candidate_disposition"])
            source_record = dict(master_row)
            source_record.update(meta)
            source_record.update(
                {
                    "team_master_row": master_row_number,
                    "candidate_source_row": candidate_source_row,
                    "candidate_disposition": disposition,
                    "exclusion_reason": clean(ledger_row["exclusion_reason"]),
                    "identity_review_required": clean(ledger_row["identity_review_required"]).lower() == "true",
                    "clinical_tissue_review_required": clean(ledger_row["clinical_tissue_review_required"]).lower() == "true",
                    "approval_status": clean(ledger_row["approval_status"]),
                    "live_action_authorised": clean(ledger_row["live_action_authorised"]).lower() == "true",
                }
            )
            source_rows_for_csv.append(source_record)
            all_source_rows.append(source_record)
            typed = disposition == "candidate_included_pending_profile_approval"
            if typed and master_row["Problem type"] == "Injury":
                clinical = clinical_by_std_row.get((team, index + 1))
                if clinical is None:
                    raise ValueError(f"missing clinical audit for {team} injury row {index + 1}")
                if clean(clinical["final_diagnosis"]) != clean(master_row["Diagnosis"]):
                    raise ValueError(f"clinical diagnosis mismatch for {team} injury row {index + 1}")
                if clean(clinical["final_tissue"]) != clean(master_row["Injury Tissue Type/s"]):
                    raise ValueError(f"clinical tissue mismatch for {team} injury row {index + 1}")
                typed_injuries.append(injury_typed_row(master_row, candidate_source_row))
                kind = "injury"
            elif typed and master_row["Problem type"] == "Illness":
                typed_illnesses.append(illness_typed_row(master_row, candidate_source_row))
                kind = "illness"
            else:
                kind = ""
            bridge.append(
                {
                    "source_uid": meta["source_uid"],
                    "source_uid_origin": meta["source_uid_origin"],
                    "source_file_sha256": meta["source_file_sha256"],
                    "source_sheet": meta["source_sheet"],
                    "source_row_number": meta["source_row_number"],
                    "source_locator": meta["source_locator"],
                    "source_cell_locator": meta["source_cell_locator"],
                    "source_event_id": meta["source_event_id"],
                    "source_occurrence_id": meta["source_occurrence_id"],
                    "source_type": meta["source_type"],
                    "team": team,
                    "team_master_row": master_row_number,
                    "candidate_source_row": candidate_source_row,
                    "problem_type": master_row["Problem type"],
                    "candidate_disposition": disposition,
                    "typed_kind": kind,
                    "exclusion_reason": clean(ledger_row["exclusion_reason"]),
                }
            )
            team_stats[team]["source_rows"] += 1
            team_stats[team]["included_rows"] += int(typed)
            team_stats[team]["included_injuries"] += int(typed and master_row["Problem type"] == "Injury")
            team_stats[team]["included_illnesses"] += int(typed and master_row["Problem type"] == "Illness")
            team_stats[team]["excluded_rows"] += int(not typed)
        output_name = f"{team}_injury_canonical_source.csv"
        write_csv(output_dir / output_name, source_rows_for_csv, CANONICAL_COLUMNS + PROVENANCE_COLUMNS)

    expected_source_rows = sum(stats["source_rows"] for stats in team_stats.values())
    expected_included = sum(stats["included_rows"] for stats in team_stats.values())
    if expected_source_rows != 842 or expected_included != 478:
        raise ValueError(f"unexpected source/included totals: {expected_source_rows}/{expected_included}")
    if len(typed_injuries) != 402 or len(typed_illnesses) != 76:
        raise ValueError(f"unexpected typed totals: {len(typed_injuries)}/{len(typed_illnesses)}")
    if len({int(row["candidate_source_row"]) for row in bridge}) != 842:
        raise ValueError("candidate source rows are not unique")
    if len({int(row["source_row"]) for row in typed_injuries + typed_illnesses}) != expected_included:
        raise ValueError("typed source rows are not unique")
    if any(not row["body_location_code"] for row in typed_injuries):
        raise ValueError("body-location codes must use the shared label mapper")

    source_names = [f"{team}_injury_canonical_source.csv" for team in TEAM_ORDER]
    summary = {
        "package_version": "irfu_release_intake_20260915_v1",
        "season": SEASON,
        "status": "local_candidate_not_approved_for_ingest_or_release",
        "source_package": str(private_root),
        "source_master_sha256": {
            team: sha256(private_root / SOURCE_MASTER.format(team=team))
            for team in TEAM_ORDER
        },
        "source_csvs": source_names,
        "source_row_count": len(all_source_rows),
        "typed_injury_count": len(typed_injuries),
        "typed_illness_count": len(typed_illnesses),
        "bridge_row_count": len(bridge),
        "counts_by_team": {team: dict(team_stats[team]) for team in TEAM_ORDER},
        "counts_by_disposition": dict(Counter(clean(row["candidate_disposition"]) for row in ledger_rows)),
        "counts_by_problem_type": dict(Counter(clean(row["problem_type"]) for row in ledger_rows)),
        "source_row_scheme": "100000 plus fixed-order combined master ordinal, 1-based",
        "source_row_order": list(TEAM_ORDER),
        "body_location_code_policy": "shared body_location mapper receives source label with Orchard code blank; source label controls the code",
        "diagnosis_policy": "Specific Diagnosis is trimmed only for typed view label/code; source CSV preserves exact master text",
        "illness_code_policy": "preserve supplied Illness Code, otherwise illness_identity plus SHA-256 of exact typed label",
        "typed_schema": {
            "injuries": list(INJURY_COLUMNS),
            "illnesses": list(ILLNESS_COLUMNS),
            "bridge": [
                "source_uid", "source_uid_origin", "source_file_sha256", "source_sheet",
                "source_row_number", "source_locator", "source_cell_locator",
                "source_event_id", "source_occurrence_id", "source_type", "team",
                "team_master_row", "candidate_source_row", "problem_type",
                "candidate_disposition", "typed_kind", "exclusion_reason",
            ],
        },
        "checks": {
            "ledger_rows_joined": True,
            "source_rows_retained": True,
            "clinical_audit_joined_for_typed_injuries": True,
            "typed_rows_are_ledger_included_only": True,
            "body_location_codes_from_label_only": True,
            "live_action_authorised": False,
        },
    }
    payload = {
        "injuries": typed_injuries,
        "illnesses": typed_illnesses,
        "bridge": bridge,
        "summary": summary,
    }
    json_path = output_dir / "irfu_typed_rows.json"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print(json.dumps({"output_dir": str(output_dir), "source_rows": 842, "typed_injuries": 402, "typed_illnesses": 76, "bridge_rows": 842}, sort_keys=True))


if __name__ == "__main__":
    main()
