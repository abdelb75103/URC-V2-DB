#!/usr/bin/env python3
"""Build and reconcile the local 2024-25 classification successor.

This command only reads retained local artefacts.  It never imports the
database helpers and never opens a network connection.  The candidate is
written last, through an atomic rename, after every source, row and payload
contract has passed.
"""

from __future__ import annotations

import argparse
import copy
import csv
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
import hashlib
import json
import os
from pathlib import Path
import tempfile
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PREDECESSOR = ROOT / "outputs/dragons_type_diagnosis_20260825/.work/served_baseline_after_dragons_type_diagnosis.json"
DEFAULT_SOURCE = ROOT / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.csv"
DEFAULT_SOURCE_MANIFEST = ROOT / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.manifest.json"
DEFAULT_MASTER = ROOT / "data/2024-25/master/master_2024-25_v5.json"
DEFAULT_REVIEW_WORKBOOK = ROOT / "data/2024-25/review/urc_injury_master_review_2024-25.xlsx"
DEFAULT_DECISIONS = ROOT / "outputs/urc_2024-25_timeline_review_2026-08-26/decisions.json"
DEFAULT_EVIDENCE = ROOT / "docs/evidence/urc_2024-25_classification_monthly_successor_2026-08-26.json"
DEFAULT_DIAGNOSIS_EVIDENCE = ROOT / "docs/evidence/urc_2024-25_specific_diagnosis_evidence.json"
DEFAULT_OUTPUT = ROOT / "data/reporting/urc_dashboard_2024-25_timeline_successor_local.json"

SEASON = "2024-25"
WINDOW_START = date(2024, 9, 1)
WINDOW_END = date(2025, 6, 30)
EXPECTED_TEAM_COUNT = 16
EXPECTED_SOURCE_SHA256 = "7203b83954becb1c2232ff7e7efa73eac1da41d7533afce865fa325041d74d71"
EXPECTED_SOURCE_ROW_MAPPING_SHA256 = "5409e641ad5d9b0159a94fc141899b1345149e5d3220cb734ca7a8da2c6ae470"
EXPECTED_MASTER_SHA256 = "15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63"
EXPECTED_PREDECESSOR_FIXTURE_SHA256 = "06a51c1e880f2a3b9b227e990b80b491005cf827fd12bb81c6cbb06856d5d503"
EXPECTED_PREDECESSOR_BUNDLE_SHA256 = "93fdd34371aac097c4364d3c64c32135fba7e3f235747b9daeb285335b330a8f"
EXPECTED_PREDECESSOR_RELEASE_ID = "8b50b9e2-023b-4f99-b6ae-e53d8e21706e"
EXPECTED_PREDECESSOR_RELEASE_LABEL = "urc-2024-25-dragons-type-diagnosis-20260826-b1"
EXPECTED_CORRECTION_SET_HASH = "b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051"
EXPECTED_ADJUDICATION_ROWS = 32
EXPECTED_ADJUDICATION_SHA256 = "cd5bed8cd5a98a6b5290194371fb92f01020ed8020ff3ddb859251741f349835"
EXPECTED_EVIDENCE_FILE_SHA256 = "0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833"
EXPECTED_ACCEPTED_WORKBOOK_SHA256 = "4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73"
EXPECTED_ADJUDICATION_WORKBOOK_SHA256 = "87ebb569afc45ef28116df98dc83c2d8799139eaecd1c249372c209fa783f155"
EXPECTED_DIAGNOSIS_WORKBOOK_SHA256 = "4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73"
EXPECTED_DIAGNOSIS_SUMMARY_SHA256 = "158cc822298c7478360c2a2f7c39fd85712398ad47a24e8848653ba686ad3c00"
EXPECTED_CORRECTED_TIME_LOSS_DAYS = {1120: 1, 1121: 1}

SUCCESSOR_METHOD = (
    "Overall incidence includes all eligible injury records; TL incidence includes final Time Loss injuries, including open or ongoing cases with null duration. Both use pooled exposure hours x 1,000.",
    "Severity mean, severity median and burden use known-duration Time Loss injuries only; null-duration Time Loss contributes no days until duration is known.",
    "Explicit Medical Attention and zero-day cases are closed Medical Attention on Date Injured and are excluded from Time Loss, incidence and burden.",
    "Unclassified eligible injuries count as recorded injuries only and are excluded from Time Loss, Medical Attention, severity, burden and dashboard unknown categories.",
    "Monthly assignment uses Date Injured only; undated eligible injuries remain in season totals and are excluded from monthly series.",
    "Diagnosis metrics use reviewed specific-diagnosis groups for injuries only; illnesses are excluded.",
    "IOC-aligned body-location and tissue/pathology categories remain separate accepted mappings.",
    "Exposure and rate calculations retain full stored precision; display formatting may round hours.",
)
SUCCESSOR_LIMITATIONS = (
    "Open or ongoing Time Loss cases are counted for incidence but cannot contribute severity or burden until duration is known.",
    "Medical Attention and zero-day cases are recorded and closed on Date Injured, but never contribute to Time Loss, incidence or burden.",
    "Unclassified eligible cases are recorded only; no Time Loss, Medical Attention, severity, burden or front-facing unknown category is assigned.",
    "Only dated cases are plotted monthly from Date Injured; undated cases remain season totals only.",
    "The immutable reporting window defines numerator and denominator eligibility.",
    "Historical exposure state is retained; correction overlays do not mutate curated rows.",
    "Unknown-setting injuries are included in all-setting metrics but have no setting-specific rate.",
    "Specific diagnoses use reviewed groups; unresolved injury diagnoses remain internal unknown values and are not shown as named diagnoses.",
)

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

BODY_CODES = {
    "Abdomen": "abdomen", "Ankle": "ankle", "Chest": "chest", "Elbow": "elbow",
    "Foot": "foot", "Forearm": "forearm", "Hand": "hand", "Head": "head",
    "Hip/Groin": "hip_groin", "Knee": "knee", "Lower leg": "lower_leg",
    "Lumbosacral": "lumbosacral", "Neck": "neck", "Shoulder": "shoulder",
    "Thigh": "thigh", "Thoracic spine": "thoracic_spine", "Upper arm": "upper_arm",
    "Wrist": "wrist", "Unknown": "unknown", "Unspecified": "unknown",
}
BODY_LABELS = {
    "abdomen": "Abdomen", "ankle": "Ankle", "chest": "Chest", "elbow": "Elbow",
    "foot": "Foot", "forearm": "Forearm", "hand": "Hand", "head": "Head",
    "hip_groin": "Hip/Groin", "knee": "Knee", "lower_leg": "Lower leg",
    "lumbosacral": "Lumbosacral", "neck": "Neck", "shoulder": "Shoulder",
    "thigh": "Thigh", "thoracic_spine": "Thoracic spine", "upper_arm": "Upper arm",
    "wrist": "Wrist", "unknown": "Unknown",
}
TYPE_CODES = {
    "Abrasion": "abrasion", "Arthritis": "arthritis", "Bone contusion": "bone_contusion",
    "Bone stress injury": "bone_stress_injury", "Brain/spinal cord injury": "brain_spinal_cord_injury",
    "Bursitis": "bursitis", "Cartilage injury": "cartilage_injury",
    "Chronic instability": "chronic_instability", "Contusion (superficial)": "contusion_superficial",
    "Fracture": "fracture", "Joint sprain": "joint_sprain", "Laceration": "laceration",
    "Muscle contusion": "muscle_contusion", "Muscle injury": "muscle_injury",
    "Nonspecific": "nonspecific", "Peripheral nerve injury": "peripheral_nerve_injury",
    "Physis injury": "physis_injury", "Synovitis/capsulitis": "synovitis_capsulitis",
    "Tendinopathy": "tendinopathy", "Tendon rupture": "tendon_rupture", "Unknown": "unknown",
}
TYPE_LABELS = {value: key for key, value in TYPE_CODES.items()}
TYPE_LABELS["bone_stress_injury"] = "Bone stress injury"

ADJUDICATION_VALUE = {
    "time_loss": "Time Loss",
    "medical_attention": "Medical Attention",
    "unknown": "unclassified",
    "unknown_ask_club": "unclassified",
}


class ReconciliationError(RuntimeError):
    """A local source or candidate contract is not safe to release."""


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def path_label(path: Path) -> str:
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def json_sha256(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def utf8_json_sha256(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()


def atomic_write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def normalise_master_value(value: Any) -> Any:
    if isinstance(value, dict) and value.get("$type") == "datetime":
        raw = str(value.get("value", ""))[:10]
        return f"{raw[8:10]}/{raw[5:7]}/{raw[:4]}"
    return "" if value is None else value


def parse_date(value: Any) -> date | None:
    if isinstance(value, dict):
        value = value.get("value")
    if isinstance(value, datetime):
        return value.date()
    text = str(value or "").strip()
    if not text:
        return None
    for pattern in ("%d/%m/%Y", "%Y-%m-%d", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(text, pattern).date()
        except ValueError:
            continue
    raise ReconciliationError(f"invalid Date Injured value: {text!r}")


def parse_days(value: Any) -> int | None:
    text = str(value or "").strip()
    if not text or text in {"-", "None", "null"}:
        return None
    try:
        parsed = Decimal(text)
    except InvalidOperation as exc:
        raise ReconciliationError(f"invalid Days Injured value: {value!r}") from exc
    if parsed != parsed.to_integral_value():
        raise ReconciliationError(f"non-integer Days Injured value: {value!r}")
    return int(parsed)


def rate(count: int, exposure_hours: Any) -> float | None:
    if exposure_hours is None:
        return None
    exposure = Decimal(str(exposure_hours))
    if exposure == 0:
        return None
    return float(Decimal(count) * Decimal(1000) / exposure)


def month_label(value: date) -> str:
    return value.strftime("%b %Y")


def read_master(path: Path) -> tuple[list[str], dict[int, dict[str, Any]], str]:
    if file_sha256(path) != EXPECTED_MASTER_SHA256:
        raise ReconciliationError("immutable master JSON fingerprint changed")
    document = json.loads(path.read_text(encoding="utf-8"))
    sheets = document.get("sheets") if isinstance(document, dict) else None
    sheet = next((item for item in sheets or [] if item.get("name") == "Injury Master"), None)
    if not isinstance(sheet, dict) or not isinstance(sheet.get("values"), list):
        raise ReconciliationError("immutable master lacks the Injury Master sheet")
    values = sheet["values"]
    headers = values[0]
    if len(headers) != 28 or headers[0] != "Team" or headers[-1] != "Exclusion Reason":
        raise ReconciliationError("immutable master A:AB header contract changed")
    rows = {number: dict(zip(headers, row, strict=True)) for number, row in enumerate(values[1:], 2)}
    return headers, rows, file_sha256(path)


def master_row_hash(headers: list[str], row: dict[str, Any]) -> str:
    canonical = {header: normalise_master_value(row[header]) for header in headers}
    return json_sha256(canonical)


def read_predecessor(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    """Load the retained live-aligned fixture, never a loose export."""
    fixture_sha = file_sha256(path)
    if fixture_sha != EXPECTED_PREDECESSOR_FIXTURE_SHA256:
        raise ReconciliationError("retained correction-aware predecessor fixture fingerprint changed")
    document = json.loads(path.read_text(encoding="utf-8"))
    stored = document.get("stored_v2")
    bundle = stored.get("bundle") if isinstance(stored, dict) else None
    if not isinstance(stored, dict) or not isinstance(bundle, dict):
        raise ReconciliationError("predecessor fixture lacks its stored V2 bundle")
    if stored.get("bundle_sha256") != EXPECTED_PREDECESSOR_BUNDLE_SHA256:
        raise ReconciliationError("predecessor embedded canonical bundle identity changed")
    if stored.get("database_bundle_sha256") != EXPECTED_PREDECESSOR_BUNDLE_SHA256:
        raise ReconciliationError("predecessor database bundle identity changed")
    if stored.get("release_label") != EXPECTED_PREDECESSOR_RELEASE_LABEL:
        raise ReconciliationError("predecessor release label changed")
    if document.get("season") != SEASON:
        raise ReconciliationError("predecessor fixture season changed")
    if bundle.get("schema_version") != "urc_dashboard_bundle_v2" or bundle.get("season") != SEASON:
        raise ReconciliationError("predecessor bundle schema or season changed")
    if len(bundle.get("teams", [])) != EXPECTED_TEAM_COUNT:
        raise ReconciliationError("predecessor is not an atomic 16-team bundle")
    return bundle, {
        "fixture_sha256": fixture_sha,
        "canonical_bundle_sha256": stored["bundle_sha256"],
        "release_id": EXPECTED_PREDECESSOR_RELEASE_ID,
        "release_label": stored["release_label"],
        "correction_set_hash": EXPECTED_CORRECTION_SET_HASH,
    }


def read_source(path: Path, manifest_path: Path, master_rows: dict[int, dict[str, Any]]) -> list[dict[str, Any]]:
    if file_sha256(path) != EXPECTED_SOURCE_SHA256:
        raise ReconciliationError("retained inclusion CSV fingerprint changed")
    document = json.loads(manifest_path.read_text(encoding="utf-8"))
    if document.get("season") != SEASON:
        raise ReconciliationError("retained inclusion manifest season changed")
    if document.get("output", {}).get("expected_csv_sha256") != EXPECTED_SOURCE_SHA256:
        raise ReconciliationError("retained inclusion manifest CSV fingerprint changed")
    stable_rows = document.get("selection", {}).get("included_source_rows")
    if not isinstance(stable_rows, list) or len(stable_rows) != 2309:
        raise ReconciliationError("retained inclusion manifest lacks its stable source-row list")
    if document.get("selection", {}).get("included_source_rows_sha256") != EXPECTED_SOURCE_ROW_MAPPING_SHA256:
        raise ReconciliationError("retained inclusion manifest source-row mapping fingerprint changed")
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != len(stable_rows):
        raise ReconciliationError("retained inclusion CSV row count differs from its manifest")
    output: list[dict[str, Any]] = []
    key_fields = ("Team", "PlayerID", "Date Injured", "Orchard Code", "Description")
    for csv_row, source_row in zip(rows, stable_rows, strict=True):
        if source_row not in master_rows:
            raise ReconciliationError(f"manifest points to missing master source row {source_row}")
        master = master_rows[source_row]
        expected_key = tuple(str(normalise_master_value(master[field])).strip() for field in key_fields)
        actual_key = tuple(str(csv_row[field] or "").strip() for field in key_fields)
        # One historical multi-diagnosis row is deterministically expanded by
        # the inclusion export.  Its stable source-row binding remains intact.
        if expected_key != actual_key and source_row != 2391:
            raise ReconciliationError(f"source row {source_row} no longer matches its inclusion locator")
        item = dict(csv_row)
        item["source_row"] = source_row
        output.append(item)
    return output


def load_adjudications(
    decisions_path: Path,
    evidence_path: Path,
    headers: list[str],
    master_rows: dict[int, dict[str, Any]],
    review_workbook_path: Path,
) -> tuple[dict[int, dict[str, Any]], dict[str, Any]]:
    evidence_file_sha256 = file_sha256(evidence_path)
    if evidence_file_sha256 != EXPECTED_EVIDENCE_FILE_SHA256:
        raise ReconciliationError("classification evidence file fingerprint changed")
    evidence_bytes = evidence_path.read_bytes()
    if hashlib.sha256(evidence_bytes).hexdigest() != evidence_file_sha256:
        raise ReconciliationError("classification evidence changed while being read")
    evidence = json.loads(evidence_bytes)
    if evidence.get("schema_version") != "urc_2024-25_classification_monthly_successor_evidence_v1":
        raise ReconciliationError("classification evidence schema changed")
    if evidence.get("season") != SEASON:
        raise ReconciliationError("classification evidence season changed")
    decision_identity = evidence.get("source_decision_record", {})
    if decision_identity.get("path") != str(DEFAULT_DECISIONS.relative_to(ROOT)):
        raise ReconciliationError("classification evidence decision-record locator changed")
    if decision_identity.get("sha256") != file_sha256(decisions_path):
        raise ReconciliationError("decision record fingerprint changed")
    master_identity = evidence.get("source_master", {})
    if master_identity.get("path") != str(DEFAULT_MASTER.relative_to(ROOT)) or master_identity.get("sha256") != EXPECTED_MASTER_SHA256:
        raise ReconciliationError("classification evidence master identity changed")
    predecessor_identity = evidence.get("predecessor_preflight", {})
    if (
        predecessor_identity.get("path") != str(DEFAULT_PREDECESSOR.relative_to(ROOT))
        or predecessor_identity.get("sha256") != EXPECTED_PREDECESSOR_FIXTURE_SHA256
        or predecessor_identity.get("embedded_candidate_canonical_bundle_sha256") != EXPECTED_PREDECESSOR_BUNDLE_SHA256
    ):
        raise ReconciliationError("classification evidence predecessor identity changed")
    correction_identity = evidence.get("active_correction_set", {})
    if correction_identity.get("sha256") != EXPECTED_CORRECTION_SET_HASH:
        raise ReconciliationError("classification evidence correction-set identity changed")
    accepted_workbook = evidence.get("accepted_review_workbook", {})
    if (
        accepted_workbook.get("path") != str(DEFAULT_REVIEW_WORKBOOK.relative_to(ROOT))
        or accepted_workbook.get("sha256") != EXPECTED_ACCEPTED_WORKBOOK_SHA256
    ):
        raise ReconciliationError("classification evidence accepted-workbook identity changed")
    adjudication_workbook = evidence.get("adjudication_baseline_workbook", {})
    if adjudication_workbook.get("sha256") != EXPECTED_ADJUDICATION_WORKBOOK_SHA256:
        raise ReconciliationError("classification evidence adjudication-workbook identity changed")
    release_identity = evidence.get("predecessor", {})
    if {
        "release_id": release_identity.get("release_id"),
        "canonical_bundle_sha256": release_identity.get("canonical_bundle_sha256"),
        "member_count": release_identity.get("member_count"),
        "analysis_version": release_identity.get("analysis_version"),
        "cohort_view_version": release_identity.get("cohort_view_version"),
    } != {
        "release_id": EXPECTED_PREDECESSOR_RELEASE_ID,
        "canonical_bundle_sha256": EXPECTED_PREDECESSOR_BUNDLE_SHA256,
        "member_count": EXPECTED_TEAM_COUNT,
        "analysis_version": "v5",
        "cohort_view_version": "analysis_window_2024-25_2026-07-25_v1",
    }:
        raise ReconciliationError("classification evidence release tuple changed")
    if evidence.get("adjudication_manifest_sha256") != EXPECTED_ADJUDICATION_SHA256:
        raise ReconciliationError("adjudication manifest fingerprint changed")
    contract = evidence.get("reconciliation_contract", {})
    expected_contract = {
        "source_reported_null_duration_time_loss": 111,
        "adjudicated_null_duration_time_loss": 15,
        "successor_time_loss_injuries": 913,
        "predecessor_recorded_injuries": 1662,
        "successor_recorded_injuries": 1662,
        "predecessor_observed_days_lost": 17575,
        "successor_observed_days_lost": 17575,
        "known_duration_time_loss_injuries": 787,
        "dated_monthly_recorded_injuries": 1656,
        "dated_monthly_time_loss_injuries": 912,
        "undated_recorded_injuries": 6,
        "undated_time_loss_injuries": 1,
        "adjudicated_recorded_total_delta": 0,
        "adjudicated_observed_days_delta": 0,
        "team_count": EXPECTED_TEAM_COUNT,
        "non_injury_payload_sections_must_be_byte_identical": [
            "analysis_window",
            "coverage",
            "prior_season",
            "monthly exposure_hours",
            "monthly distance_km",
        ],
        "successor_disclosure_keys": ["method", "limitations"],
        "successor_disclosure_method_sha256": json_sha256(list(SUCCESSOR_METHOD)),
        "successor_disclosure_limitations_sha256": json_sha256(list(SUCCESSOR_LIMITATIONS)),
        "injury_derived_sections": [
            "headline",
            "setting_split",
            "setting_metrics",
            "setting recorded_injuries",
            "setting overall_incidence_per_1000h",
            "monthly recorded_injuries",
            "monthly time_loss_injuries",
            "monthly days_lost",
            "monthly overall_incidence_per_1000h",
            "monthly incidence_per_1000h",
            "monthly burden_per_1000h",
            "body_locations",
            "injury_types",
            "injury_profiles",
            "severity_distribution",
            "contact_distribution",
        ],
    }
    if {key: contract.get(key) for key in expected_contract} != expected_contract:
        raise ReconciliationError("classification evidence reconciliation contract changed")
    disclosure = evidence.get("successor_disclosure", {})
    if (
        disclosure.get("method") != list(SUCCESSOR_METHOD)
        or disclosure.get("limitations") != list(SUCCESSOR_LIMITATIONS)
        or disclosure.get("method_sha256") != json_sha256(list(SUCCESSOR_METHOD))
        or disclosure.get("limitations_sha256") != json_sha256(list(SUCCESSOR_LIMITATIONS))
    ):
        raise ReconciliationError("classification evidence successor disclosure changed")
    if not review_workbook_path.is_file():
        raise ReconciliationError("review workbook locator is missing")
    decision_doc = json.loads(decisions_path.read_text(encoding="utf-8"))
    queue = decision_doc["decisions"][4]["pending_row_adjudication"]
    decision_rows = queue["row_adjudications"]
    evidence_rows = evidence.get("row_adjudications")
    if len(decision_rows) != EXPECTED_ADJUDICATION_ROWS or len(evidence_rows or []) != EXPECTED_ADJUDICATION_ROWS:
        raise ReconciliationError("the complete 32-row adjudication set is required")
    if json_sha256(evidence_rows) != evidence["adjudication_manifest_sha256"]:
        raise ReconciliationError("adjudication evidence-set hash changed")
    by_source: dict[int, dict[str, Any]] = {}
    for decision, recorded in zip(decision_rows, evidence_rows, strict=True):
        source_row = int(decision["excel_row"])
        if int(recorded["source_row"]) != source_row:
            raise ReconciliationError(f"adjudication locator mismatch at source row {source_row}")
        if source_row in by_source or source_row not in master_rows:
            raise ReconciliationError(f"duplicate or missing adjudication source row {source_row}")
        evidence_payload = dict(recorded)
        evidence_sha256 = evidence_payload.pop("evidence_sha256", None)
        if json_sha256(evidence_payload) != evidence_sha256:
            raise ReconciliationError(f"adjudication evidence hash changed at source row {source_row}")
        locator_material = (
            f"{SEASON}|Injury Master|{source_row}|{EXPECTED_ADJUDICATION_WORKBOOK_SHA256}"
        )
        if hashlib.sha256(locator_material.encode("utf-8")).hexdigest() != recorded.get(
            "source_locator_fingerprint"
        ):
            raise ReconciliationError(f"adjudication locator fingerprint changed at source row {source_row}")
        master = master_rows[source_row]
        digest = master_row_hash(headers, master)
        if digest != recorded.get("source_row_sha256"):
            raise ReconciliationError(f"canonical master hash changed at source row {source_row}")
        source_value = normalise_master_value(master["TimeLoss vs Medical Attention"])
        if source_value != recorded.get("source_value"):
            raise ReconciliationError(f"source classification changed at source row {source_row}")
        master_date = parse_date(master["Date Injured"])
        if decision.get("team") != master.get("Team") or decision.get("date_injured") != (master_date.isoformat() if master_date else None):
            raise ReconciliationError(f"adjudication locator facts changed at source row {source_row}")
        final = ADJUDICATION_VALUE.get(decision.get("first_human_adjudication"))
        if final != recorded.get("final_classification"):
            raise ReconciliationError(f"final classification mismatch at source row {source_row}")
        by_source[source_row] = {
            "source_locator": recorded.get("source_locator"),
            "source_locator_fingerprint": recorded.get("source_locator_fingerprint"),
            "source_value": source_value,
            "final_classification": final,
            "classification_origin": "adjudicated",
            "source_row_sha256": digest,
            "reviewer": recorded.get("reviewer", "Abdel Babiker"),
            "rationale": recorded.get("rationale"),
            "evidence_sha256": recorded.get("evidence_sha256"),
            "club_follow_up": bool(decision.get("club_follow_up")),
            "second_human_review": decision.get("second_human_review"),
        }
    source_values = {item["source_value"] for item in by_source.values()}
    if source_values != {"", "FALSE"} or sum(item["source_value"] == "" for item in by_source.values()) != 29:
        raise ReconciliationError("the 29 blank and 3 FALSE source facts do not reconcile")
    final_counts = {name: sum(item["final_classification"] == name for item in by_source.values()) for name in ("Time Loss", "Medical Attention", "unclassified")}
    if final_counts != {"Time Loss": 15, "Medical Attention": 1, "unclassified": 16}:
        raise ReconciliationError(f"adjudication outcomes do not reconcile: {final_counts}")
    if file_sha256(evidence_path) != evidence_file_sha256:
        raise ReconciliationError("classification evidence changed during reconciliation")
    return by_source, {
        "rows": EXPECTED_ADJUDICATION_ROWS,
        "source_values": {"blank": 29, "FALSE": 3},
        "final_classification_counts": final_counts,
        "row_adjudications": [
            {
                "source_row": source_row,
                "source_locator": item["source_locator"],
                "source_locator_fingerprint": item["source_locator_fingerprint"],
                "source_row_sha256": item["source_row_sha256"],
                "source_value": item["source_value"],
                "final_classification": item["final_classification"],
                "classification_origin": item["classification_origin"],
                "reviewer": item["reviewer"],
                "rationale": item["rationale"],
                "club_follow_up": item["club_follow_up"],
                "second_human_review": item["second_human_review"],
                "evidence_sha256": item["evidence_sha256"],
            }
            for source_row, item in sorted(by_source.items())
        ],
        "source_row_sha256s": {str(k): v["source_row_sha256"] for k, v in sorted(by_source.items())},
        "evidence_file_sha256": evidence_file_sha256,
    }


def eligible_rows(source_rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for row in source_rows:
        if row.get("Problem type") != "Injury":
            continue
        injured = parse_date(row.get("Date Injured"))
        if injured is None or WINDOW_START <= injured <= WINDOW_END:
            rows.append(row)
    return rows


def final_classification(row: dict[str, Any], adjudications: dict[int, dict[str, Any]]) -> str:
    override = adjudications.get(int(row["source_row"]))
    if override:
        return override["final_classification"]
    if int(row["source_row"]) in EXPECTED_CORRECTED_TIME_LOSS_DAYS:
        return "Time Loss"
    current = str(row.get("TimeLoss vs Medical Attention") or "").strip().casefold()
    if current in {"medical attention", "medical_attention", "medical-attention"}:
        return "Medical Attention"
    if parse_days(row.get("Days Injured")) == 0:
        return "Medical Attention"
    if current in {"time loss", "time_loss", "timeloss", "true"}:
        return "Time Loss"
    if parse_days(row.get("Days Injured")) is not None and parse_days(row.get("Days Injured")) > 0:
        return "Time Loss"
    return "unclassified"


def classification_origin(row: dict[str, Any], classification: str, adjudications: dict[int, dict[str, Any]]) -> str:
    if int(row["source_row"]) in adjudications:
        return "adjudicated"
    if int(row["source_row"]) in EXPECTED_CORRECTED_TIME_LOSS_DAYS:
        return "accepted_correction"
    source = str(row.get("TimeLoss vs Medical Attention") or "").strip().casefold()
    if source in {"medical attention", "medical_attention", "medical-attention", "time loss", "time_loss", "timeloss", "true"}:
        return "source_reported"
    days = parse_days(row.get("Days Injured"))
    if days == 0:
        return "inferred_zero_days"
    if days is not None and days > 0:
        return "inferred_positive_days"
    return "unclassified_default"


def severity_code(classification: str, days: int | None) -> str | None:
    if classification == "Medical Attention":
        return "zero_days_medical_attention_only"
    if classification != "Time Loss" or days is None:
        return None
    if days == 1:
        return "one_day"
    if 2 <= days <= 3:
        return "two_to_three_days"
    if 4 <= days <= 7:
        return "four_to_seven_days"
    if 8 <= days <= 28:
        return "eight_to_twenty_eight_days"
    if days > 28:
        return "greater_than_twenty_eight_days"
    return None


def setting_code(row: dict[str, Any]) -> str:
    value = str(row.get("Occasion category") or "").strip().casefold()
    return value if value in {"match", "training"} else "unknown"


def contact_code(row: dict[str, Any]) -> str:
    value = str(row.get("Is Contact") or "").strip().casefold()
    return {"non-contact": "non_contact", "contact": "contact"}.get(value, "unknown")


def load_diagnosis_evidence(
    path: Path, headers: list[str], master_rows: dict[int, dict[str, Any]]
) -> tuple[dict[int, dict[str, str]], dict[str, Any]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schema_version") != "urc_2024-25_specific_diagnosis_evidence_v1":
        raise ReconciliationError("specific-diagnosis evidence schema changed")
    sources = document.get("source_artifacts", {})
    if sources.get("review_workbook", {}).get("sha256") != EXPECTED_DIAGNOSIS_WORKBOOK_SHA256:
        raise ReconciliationError("specific-diagnosis review workbook identity changed")
    if sources.get("grouped_summary_workbook", {}).get("sha256") != EXPECTED_DIAGNOSIS_SUMMARY_SHA256:
        raise ReconciliationError("specific-diagnosis summary identity changed")
    if sources.get("immutable_master", {}).get("sha256") != EXPECTED_MASTER_SHA256:
        raise ReconciliationError("specific-diagnosis master identity changed")
    rows = document.get("rows")
    if not isinstance(rows, list):
        raise ReconciliationError("specific-diagnosis evidence rows are missing")
    mapping: dict[int, dict[str, str]] = {}
    illness_rows = 0
    for item in rows:
        source_row = item.get("master_source_row")
        if not isinstance(source_row, int) or source_row not in master_rows:
            raise ReconciliationError("specific-diagnosis evidence has an invalid source row")
        canonical = {
            header: normalise_master_value(master_rows[source_row][header])
            for header in headers
        }
        if item.get("source_row_sha256") != utf8_json_sha256(canonical):
            raise ReconciliationError(f"specific-diagnosis source identity changed at row {source_row}")
        if item.get("injury_metric_eligible") is not True:
            illness_rows += 1
            continue
        if item.get("problem_type") != "Injury":
            raise ReconciliationError("non-injury diagnosis entered injury metrics")
        mapping[source_row] = {
            "code": str(item.get("diagnosis_group_code") or "unknown"),
            "label": str(item.get("diagnosis_group_label") or "Unknown diagnosis"),
        }
    aggregate = document.get("aggregate_reconciliation", {})
    if len(mapping) != 1660 or illness_rows != 392:
        raise ReconciliationError("specific-diagnosis injury/illness counts changed")
    if aggregate.get("illness_rows_excluded_from_injury_metrics") != illness_rows:
        raise ReconciliationError("specific-diagnosis illness exclusion evidence changed")
    return mapping, {
        "path": path_label(path),
        "sha256": file_sha256(path),
        "injury_rows": len(mapping),
        "illness_rows_excluded": illness_rows,
        "rows_sha256": document.get("mapping", {}).get("rows_sha256"),
    }


def entry(rows: list[dict[str, Any]], **criteria: Any) -> dict[str, Any] | None:
    return next((row for row in rows if all(row.get(key) == value for key, value in criteria.items())), None)


def zero_metric_entry(template: dict[str, Any], code: str, label: str, *, dimension: str, setting: str) -> dict[str, Any]:
    item = copy.deepcopy(template)
    item.update({
        "code": code,
        "label": label,
        "dimension": dimension,
        "setting": setting,
        "days_lost": 0,
        "time_loss_injuries": 0,
        "incidence_per_1000h": rate(0, item.get("exposure_hours")),
        "burden_per_1000h": None if item.get("exposure_hours") is None else 0.0,
        "mean_severity_days": None,
    })
    return item


def ensure_profile(
    rows: list[dict[str, Any]],
    *,
    dimension: str,
    code: str,
    label: str,
    setting: str,
) -> dict[str, Any]:
    found = entry(rows, dimension=dimension, code=code, setting=setting)
    if found:
        return found
    template = next((item for item in rows if item.get("dimension") == dimension and item.get("setting") == setting), None)
    if template is None:
        template = next(item for item in rows if item.get("dimension") == dimension)
    found = zero_metric_entry(template, code, label, dimension=dimension, setting=setting)
    rows.append(found)
    return found


def increment_metric(item: dict[str, Any], count: int = 1) -> None:
    item["time_loss_injuries"] = int(item["time_loss_injuries"]) + count
    item["incidence_per_1000h"] = rate(item["time_loss_injuries"], item.get("exposure_hours"))


def rebuild_diagnosis_profiles(
    dashboard: dict[str, Any],
    rows: list[dict[str, Any]],
    diagnosis_mapping: dict[int, dict[str, str]],
) -> None:
    profiles = dashboard["injury_profiles"]
    aggregates: dict[tuple[str, str, str], dict[str, int]] = {}
    for row in rows:
        if row["final_classification"] != "Time Loss":
            continue
        diagnosis = diagnosis_mapping.get(
            row["source_row"], {"code": "unknown", "label": "Unknown diagnosis"}
        )
        for setting in ("all", setting_code(row)):
            key = (setting, diagnosis["code"], diagnosis["label"])
            aggregate = aggregates.setdefault(key, {"count": 0, "days": 0, "known": 0})
            aggregate["count"] += 1
            if row["days_parsed"] is not None:
                aggregate["days"] += row["days_parsed"]
                aggregate["known"] += 1
    settings = {setting for setting, _, _ in aggregates}
    templates = {
        setting: next(
            (
                item for item in profiles
                if item.get("dimension") == "diagnosis"
                and item.get("setting") == setting
            ),
            next(item for item in profiles if item.get("setting") == setting),
        )
        for setting in settings
    }
    diagnosis_rows: list[dict[str, Any]] = []
    setting_order = {"all": 0, "match": 1, "training": 2, "unknown": 3}
    for (setting, code, label), aggregate in sorted(
        aggregates.items(),
        key=lambda pair: (
            setting_order[pair[0][0]], -pair[1]["count"], pair[0][1]
        ),
    ):
        item = zero_metric_entry(
            templates[setting], code, label, dimension="diagnosis", setting=setting
        )
        item["time_loss_injuries"] = aggregate["count"]
        item["days_lost"] = aggregate["days"]
        item["incidence_per_1000h"] = rate(aggregate["count"], item.get("exposure_hours"))
        item["burden_per_1000h"] = rate(aggregate["days"], item.get("exposure_hours"))
        item["mean_severity_days"] = (
            aggregate["days"] / aggregate["known"] if aggregate["known"] else None
        )
        diagnosis_rows.append(item)
    dashboard["injury_profiles"] = [
        item for item in profiles if item.get("dimension") != "diagnosis"
    ] + diagnosis_rows


def map_section_entry(rows: list[dict[str, Any]], key: str, label: str) -> dict[str, Any]:
    found = entry(rows, key=key)
    if found:
        return found
    template = rows[0]
    found = copy.deepcopy(template)
    found.update({
        "key": key,
        "label": label,
        "days_lost": 0,
        "time_loss_injuries": 0,
        "incidence_per_1000h": rate(0, found.get("exposure_hours")),
        "burden_per_1000h": None if found.get("exposure_hours") is None else 0.0,
        "mean_severity_days": None,
    })
    rows.append(found)
    return found


def build_candidate(
    predecessor_path: Path,
    source_path: Path,
    source_manifest_path: Path,
    master_path: Path,
    review_workbook_path: Path,
    decisions_path: Path,
    evidence_path: Path,
    diagnosis_evidence_path: Path = DEFAULT_DIAGNOSIS_EVIDENCE,
) -> tuple[dict[str, Any], dict[str, Any]]:
    predecessor, predecessor_identity = read_predecessor(predecessor_path)
    teams = predecessor.get("teams")
    if not isinstance(teams, list) or len(teams) != EXPECTED_TEAM_COUNT:
        raise ReconciliationError("predecessor is not an atomic 16-team bundle")
    if len({team.get("team_key") for team in teams}) != EXPECTED_TEAM_COUNT:
        raise ReconciliationError("predecessor team keys are not unique")

    headers, master_rows, master_sha = read_master(master_path)
    source_rows = read_source(source_path, source_manifest_path, master_rows)
    adjudications, adjudication_summary = load_adjudications(
        decisions_path, evidence_path, headers, master_rows, review_workbook_path
    )
    diagnosis_mapping, diagnosis_evidence = load_diagnosis_evidence(
        diagnosis_evidence_path, headers, master_rows
    )
    active = eligible_rows(source_rows)
    if len(active) != 1662 or sum(parse_date(row.get("Date Injured")) is None for row in active) != 6:
        raise ReconciliationError("eligible injury cohort does not reconcile to 1,662 with six undated rows")
    if set(row.get("Team") for row in active) != set(TEAM_KEYS):
        raise ReconciliationError("eligible injury cohort does not cover all 16 teams")

    classified = []
    for row in active:
        row = dict(row)
        row["final_classification"] = final_classification(row, adjudications)
        row["days_parsed"] = EXPECTED_CORRECTED_TIME_LOSS_DAYS.get(
            row["source_row"], parse_days(row.get("Days Injured"))
        )
        row["injured_date"] = parse_date(row.get("Date Injured"))
        row["classification_origin"] = classification_origin(row, row["final_classification"], adjudications)
        row["duration_usable"] = row["days_parsed"] is not None
        row["closure_status"] = (
            "Open/Ongoing" if row["final_classification"] == "Time Loss" and row["days_parsed"] is None
            else "Closed" if row["final_classification"] in {"Time Loss", "Medical Attention"}
            else "Not applicable"
        )
        row["severity_code"] = severity_code(row["final_classification"], row["days_parsed"])
        classified.append(row)
    class_counts = {name: sum(row["final_classification"] == name for row in classified) for name in ("Time Loss", "Medical Attention", "unclassified")}
    if class_counts != {"Time Loss": 913, "Medical Attention": 731, "unclassified": 18}:
        raise ReconciliationError(f"source replay classifications do not reconcile: {class_counts}")
    source_null_time_loss = [
        row for row in classified
        if row["final_classification"] == "Time Loss"
        and row["days_parsed"] is None
        and row["source_row"] not in adjudications
        and str(row.get("TimeLoss vs Medical Attention") or "").strip() == "Time Loss"
    ]
    adjudicated_time_loss = [
        row for row in classified
        if row["source_row"] in adjudications
        and adjudications[row["source_row"]]["final_classification"] == "Time Loss"
        and row["days_parsed"] is None
    ]
    additions = source_null_time_loss + adjudicated_time_loss
    if len(source_null_time_loss) != 111 or len(adjudicated_time_loss) != 15 or len(additions) != 126:
        raise ReconciliationError("null-duration source and adjudicated Time Loss counts do not reconcile")
    if sum(row["injured_date"] is None for row in additions) != 1:
        raise ReconciliationError("null-duration Time Loss monthly undated reconciliation failed")
    source_positive_time_loss = sum(
        row["final_classification"] == "Time Loss" and row["days_parsed"] is not None
        for row in classified
    )
    if source_positive_time_loss != 787:
        raise ReconciliationError("governed source positive-duration Time Loss count changed")
    if any(
        row["final_classification"] == "Time Loss"
        and row["days_parsed"] is None
        and row["closure_status"] != "Open/Ongoing"
        for row in classified
    ):
        raise ReconciliationError("null-duration Time Loss is not Open/Ongoing")
    if any(
        row["final_classification"] == "Medical Attention"
        and (row["closure_status"] != "Closed" or row["severity_code"] != "zero_days_medical_attention_only")
        for row in classified
    ):
        raise ReconciliationError("Medical Attention rows are not closed zero-day presentation cases")
    if any(
        row["final_classification"] == "unclassified"
        and row["severity_code"] is not None
        for row in classified
    ):
        raise ReconciliationError("unclassified rows leaked into severity")
    predecessor_headline = {item["key"]: item for item in predecessor["league"]["headline"]}
    if predecessor_headline["recorded_injuries"]["value"] != 1662 or predecessor_headline["time_loss_injuries"]["value"] != 787:
        raise ReconciliationError("correction-aware predecessor aggregate baseline is not 1,662/787")
    if predecessor_headline["severity_mean_days"]["denominator"] != 787 or predecessor_headline["severity_mean_days"]["numerator"] != 17575:
        raise ReconciliationError("correction-aware predecessor known-duration severity baseline changed")

    candidate = copy.deepcopy(predecessor)
    team_dashboards = {team["team_key"]: team["dashboard"] for team in candidate["teams"]}
    source_by_team = {team: [row for row in classified if row["Team"] == team] for team in TEAM_KEYS}

    for team_name, dashboard in [("URC Overall", candidate["league"])] + [
        (team_name, team_dashboards[TEAM_KEYS[team_name]]) for team_name in TEAM_KEYS
    ]:
        rows_for_team = classified if team_name == "URC Overall" else source_by_team[team_name]
        team_additions = [row for row in additions if team_name == "URC Overall" or row["Team"] == team_name]
        recorded_by_month: dict[str, int] = {}
        tl_by_month: dict[str, int] = {}
        for row in rows_for_team:
            if row["injured_date"] is not None:
                label = month_label(row["injured_date"])
                recorded_by_month[label] = recorded_by_month.get(label, 0) + 1
        for row in team_additions:
            if row["injured_date"] is not None:
                label = month_label(row["injured_date"])
                tl_by_month[label] = tl_by_month.get(label, 0) + 1

        headline = {item["key"]: item for item in dashboard["headline"]}
        if headline["recorded_injuries"]["value"] != len(rows_for_team):
            raise ReconciliationError(f"{team_name} recorded count does not match source cohort")
        headline["time_loss_injuries"]["value"] += len(team_additions)
        headline["recorded_injuries"]["formula"] = "count(final classified eligible injury rows, including undated)"
        headline["time_loss_injuries"]["formula"] = "count(final classification = Time Loss)"
        headline["incidence_per_1000h"]["numerator"] = headline["time_loss_injuries"]["value"]
        headline["incidence_per_1000h"]["value"] = rate(
            headline["time_loss_injuries"]["value"], headline["incidence_per_1000h"]["denominator"]
        )
        overall_incidence = copy.deepcopy(headline["incidence_per_1000h"])
        overall_incidence.update({
            "key": "overall_incidence_per_1000h",
            "label": "Overall incidence",
            "value": rate(
                headline["recorded_injuries"]["value"],
                headline["incidence_per_1000h"]["denominator"],
            ),
            "formula": "eligible recorded injuries / pooled exposure hours * 1000",
            "numerator": headline["recorded_injuries"]["value"],
        })
        dashboard["headline"] = [
            item for item in dashboard["headline"]
            if item["key"] != "overall_incidence_per_1000h"
        ]
        dashboard["headline"].append(overall_incidence)
        dashboard["method"] = list(SUCCESSOR_METHOD)
        dashboard["limitations"] = list(SUCCESSOR_LIMITATIONS)

        monthly = dashboard["monthly"]
        monthly_by_label = {item["month"]: item for item in monthly}
        expected_months = set(recorded_by_month) | set(tl_by_month)
        if not expected_months <= set(monthly_by_label):
            raise ReconciliationError(f"{team_name} Date Injured month is absent from predecessor timeline")
        for label, item in monthly_by_label.items():
            item["recorded_injuries"] = recorded_by_month.get(label, 0)
            item["overall_incidence_per_1000h"] = rate(
                item["recorded_injuries"], item["exposure_hours"]
            )
            if label in tl_by_month:
                item["time_loss_injuries"] += tl_by_month[label]
                item["incidence_per_1000h"] = rate(item["time_loss_injuries"], item["exposure_hours"])

        split_by_key = {item["key"]: item for item in dashboard["setting_split"]}
        metric_by_key = {item["setting"]: item for item in dashboard["setting_metrics"]}
        for row in team_additions:
            setting = setting_code(row)
            increment_metric(split_by_key[setting])
            increment_metric(metric_by_key[setting])

            body = BODY_CODES.get(str(row.get("Body Part") or "").strip(), "unknown")
            injury_type = TYPE_CODES.get(str(row.get("Injury Tissue Type/s") or "").strip(), "unknown")
            body_item = map_section_entry(dashboard["body_locations"], body, BODY_LABELS[body])
            type_item = map_section_entry(dashboard["injury_types"], injury_type, TYPE_LABELS.get(injury_type, injury_type.replace("_", " ").title()))
            increment_metric(body_item)
            increment_metric(type_item)

            profile_rows = dashboard["injury_profiles"]
            profile_setting = setting
            for dimension, code, label in (
                ("body_location", body, BODY_LABELS[body]),
                ("injury_type", injury_type, TYPE_LABELS.get(injury_type, injury_type.replace("_", " ").title())),
                ("injury_profile", f"{body}__{injury_type}", f"{BODY_LABELS[body]} · {TYPE_LABELS.get(injury_type, injury_type.replace('_', ' ').title())}"),
            ):
                increment_metric(ensure_profile(profile_rows, dimension=dimension, code=code, label=label, setting="all"))
                increment_metric(ensure_profile(profile_rows, dimension=dimension, code=code, label=label, setting=profile_setting))
            contact = contact_code(row)
            for item in dashboard["contact_distribution"]:
                if item["key"] == contact and item["setting"] in {"all", setting}:
                    increment_metric(item)

        recorded_by_setting = {
            setting: sum(setting_code(row) == setting for row in rows_for_team)
            for setting in ("match", "training", "unknown")
        }
        for setting, item in metric_by_key.items():
            item["recorded_injuries"] = recorded_by_setting[setting]
            item["overall_incidence_per_1000h"] = rate(
                item["recorded_injuries"], item.get("exposure_hours")
            )

        rebuild_diagnosis_profiles(dashboard, rows_for_team, diagnosis_mapping)
        for setting, item in split_by_key.items():
            item["recorded_injuries"] = recorded_by_setting[setting]
            item["overall_incidence_per_1000h"] = rate(
                item["recorded_injuries"], item.get("exposure_hours")
            )

        # The public severity buckets intentionally remain byte-identical:
        # null duration is retained as unknown/censored and contributes no
        # observed days, burden, mean or median.

    candidate["teams"] = [{"team_key": key, "dashboard": team_dashboards[key]} for key in [team["team_key"] for team in predecessor["teams"]]]
    manifest = reconcile_candidate(
        predecessor,
        candidate,
        classified,
        adjudication_summary,
        predecessor_identity,
        predecessor_path,
        master_path,
        master_sha,
        source_path,
        source_manifest_path,
        review_workbook_path,
        decisions_path,
        evidence_path,
        diagnosis_evidence,
    )
    return candidate, manifest


def reconcile_candidate(
    predecessor: dict[str, Any],
    candidate: dict[str, Any],
    classified: list[dict[str, Any]],
    adjudication_summary: dict[str, Any],
    predecessor_identity: dict[str, Any],
    predecessor_path: Path,
    master_path: Path,
    master_sha: str,
    source_path: Path,
    source_manifest_path: Path,
    review_workbook_path: Path,
    decisions_path: Path,
    evidence_path: Path,
    diagnosis_evidence: dict[str, Any],
) -> dict[str, Any]:
    if len(candidate.get("teams", [])) != EXPECTED_TEAM_COUNT:
        raise ReconciliationError("candidate is not atomic 16-team output")
    team_names = [team["dashboard"]["team"] for team in candidate["teams"]]
    if len(set(team_names)) != EXPECTED_TEAM_COUNT or set(team_names) != set(TEAM_KEYS):
        raise ReconciliationError("candidate does not cover exactly the 16 league teams")
    base_league = predecessor["league"]
    league = candidate["league"]
    team_tl = sum(next(item["value"] for item in team["dashboard"]["headline"] if item["key"] == "time_loss_injuries") for team in candidate["teams"])
    league_tl = next(item["value"] for item in league["headline"] if item["key"] == "time_loss_injuries")
    if team_tl != league_tl:
        raise ReconciliationError("team Time Loss totals do not reconcile to league")
    team_recorded = sum(next(item["value"] for item in team["dashboard"]["headline"] if item["key"] == "recorded_injuries") for team in candidate["teams"])
    league_recorded = next(item["value"] for item in league["headline"] if item["key"] == "recorded_injuries")
    if team_recorded != league_recorded != len(classified):
        raise ReconciliationError("team recorded totals do not reconcile to league")

    # Preserve the allowlisted non-injury fields; disclosures are successor-owned.
    non_injury_hashes: dict[str, str] = {}
    for label, before, after in [("league", base_league, league)] + [
        (team["team_key"], next(item["dashboard"] for item in predecessor["teams"] if item["team_key"] == team["team_key"]), team["dashboard"])
        for team in candidate["teams"]
    ]:
        immutable = {key: before[key] for key in ("coverage", "prior_season", "analysis_window")}
        immutable["monthly_exposure_hours"] = [row["exposure_hours"] for row in before["monthly"]]
        immutable["monthly_distance_km"] = [row["distance_km"] for row in before["monthly"]]
        after_immutable = {key: after[key] for key in ("coverage", "prior_season", "analysis_window")}
        after_immutable["monthly_exposure_hours"] = [row["exposure_hours"] for row in after["monthly"]]
        after_immutable["monthly_distance_km"] = [row["distance_km"] for row in after["monthly"]]
        if immutable != after_immutable:
            raise ReconciliationError(f"non-injury payload changed for {label}")
        non_injury_hashes[label] = json_sha256(immutable)

    source_class_counts = {name: sum(row["final_classification"] == name for row in classified) for name in ("Time Loss", "Medical Attention", "unclassified")}
    undated = sum(row["injured_date"] is None for row in classified)
    monthly_recorded = sum(row.get("recorded_injuries", 0) for row in league["monthly"])
    monthly_tl = sum(row["time_loss_injuries"] for row in league["monthly"])
    base_headline = {item["key"]: item for item in base_league["headline"]}
    candidate_headline = {item["key"]: item for item in league["headline"]}
    source_null_time_loss = sum(
        row["final_classification"] == "Time Loss"
        and row["days_parsed"] is None
        and str(row.get("TimeLoss vs Medical Attention") or "").strip() == "Time Loss"
        and row["source_row"] not in {
            item["source_row"] for item in adjudication_summary["row_adjudications"]
        }
        for row in classified
    )
    adjudicated_time_loss = adjudication_summary["final_classification_counts"]["Time Loss"]
    null_time_loss = source_null_time_loss + adjudicated_time_loss
    undated_added_time_loss = sum(
        row["final_classification"] == "Time Loss" and row["days_parsed"] is None and row["injured_date"] is None
        for row in classified
    )
    if monthly_recorded != len(classified) - undated or monthly_tl != base_headline["time_loss_injuries"]["value"] + null_time_loss - undated_added_time_loss:
        raise ReconciliationError("monthly Date Injured reconciliation failed")
    known_tl = base_headline["severity_mean_days"]["denominator"]
    if source_null_time_loss != 111 or adjudicated_time_loss != 15 or null_time_loss != 126:
        raise ReconciliationError("source and adjudicated null-duration Time Loss delta failed")
    if known_tl != 787:
        raise ReconciliationError("known-duration severity denominator failed")
    if candidate_headline["recorded_injuries"]["value"] != 1662 or candidate_headline["time_loss_injuries"]["value"] != 913:
        raise ReconciliationError("candidate season totals failed 1,662 recorded / 913 Time Loss reconciliation")
    if candidate_headline["severity_mean_days"]["denominator"] != known_tl or candidate_headline["severity_mean_days"]["numerator"] != 17575:
        raise ReconciliationError("mean severity does not use known-duration Time Loss cases")
    if candidate_headline["burden_per_1000h"]["numerator"] != 17575:
        raise ReconciliationError("burden days changed despite null-duration classifications")
    if (
        candidate_headline["severity_median_days"]["value"]
        != base_headline["severity_median_days"]["value"]
        or candidate_headline["severity_median_days"]["value"] != 13
    ):
        raise ReconciliationError("median severity changed despite an unchanged known-duration cohort")
    payloads = [league] + [team["dashboard"] for team in candidate["teams"]]
    if any(
        dashboard.get("method") != list(SUCCESSOR_METHOD)
        or dashboard.get("limitations") != list(SUCCESSOR_LIMITATIONS)
        for dashboard in payloads
    ):
        raise ReconciliationError("successor method or limitations disclosure drifted")
    for label, dashboard, before in [("league", league, base_league)] + [
        (
            team["team_key"],
            team["dashboard"],
            next(item["dashboard"] for item in predecessor["teams"] if item["team_key"] == team["team_key"]),
        )
        for team in candidate["teams"]
    ]:
        expected_time_loss = next(item["value"] for item in dashboard["headline"] if item["key"] == "time_loss_injuries")
        for section in ("setting_split", "setting_metrics", "body_locations", "injury_types"):
            if sum(item.get("time_loss_injuries", 0) for item in dashboard[section]) != expected_time_loss:
                raise ReconciliationError(f"{label} {section} classification total does not match headline")
        for dimension in ("body_location", "injury_type", "injury_profile", "diagnosis"):
            if sum(
                item.get("time_loss_injuries", 0)
                for item in dashboard["injury_profiles"]
                if item.get("dimension") == dimension and item.get("setting") == "all"
            ) != expected_time_loss:
                raise ReconciliationError(f"{label} injury profile {dimension} total does not match headline")
        if sum(
            item.get("time_loss_injuries", 0)
            for item in dashboard["contact_distribution"]
            if item.get("setting") == "all"
        ) != expected_time_loss:
            raise ReconciliationError(f"{label} contact classification total does not match headline")
        if dashboard["severity_distribution"] != before["severity_distribution"]:
            raise ReconciliationError(f"{label} severity distribution changed for null-duration classifications")
    return {
        "schema_version": "urc_2024-25_timeline_successor_local_reconciliation_v1",
        "season": SEASON,
        "release_tuple": {
            "analysis_version": "v5",
            "classification_view_version": "reporting_classification_2024-25_2026-08-27_v1",
            "cohort_view_version": "analysis_window_2024-25_2026-07-25_v1",
        },
        "predecessor_path": path_label(predecessor_path),
        "predecessor_fixture_sha256": predecessor_identity["fixture_sha256"],
        "predecessor_canonical_bundle_sha256": predecessor_identity["canonical_bundle_sha256"],
        "predecessor_release_id": predecessor_identity["release_id"],
        "predecessor_sha256": predecessor_identity["fixture_sha256"],
        "source": {
            "master_path": path_label(master_path),
            "master_sha256": master_sha,
            "included_csv_path": path_label(source_path),
            "included_csv_sha256": file_sha256(source_path),
            "included_manifest_path": path_label(source_manifest_path),
            "included_manifest_sha256": file_sha256(source_manifest_path),
            "included_source_rows_sha256": EXPECTED_SOURCE_ROW_MAPPING_SHA256,
            "review_workbook_locator": path_label(review_workbook_path),
            "review_workbook_sha256_on_disk": file_sha256(review_workbook_path),
            "review_workbook_role": "locator only; not authoritative source identity or calculation input",
            "accepted_review_workbook_sha256": EXPECTED_ACCEPTED_WORKBOOK_SHA256,
            "adjudication_baseline_workbook_sha256": EXPECTED_ADJUDICATION_WORKBOOK_SHA256,
            "workbook_hash_caveat": "Current workbook bytes are retained for locator provenance; canonical row values and calculations are bound to immutable master JSON and evidence.",
            "decisions_path": path_label(decisions_path),
            "decisions_sha256": file_sha256(decisions_path),
            "evidence_path": path_label(evidence_path),
            "evidence_sha256": file_sha256(evidence_path),
            "specific_diagnosis_evidence": diagnosis_evidence,
        },
        "classification_contract": {
            "eligible_recorded_injuries": len(classified),
            "source_replay_classification_counts": source_class_counts,
            "successor_time_loss_injuries": candidate_headline["time_loss_injuries"]["value"],
            "time_loss_known_duration": known_tl,
            "time_loss_null_duration": null_time_loss,
            "source_reported_null_duration_time_loss": source_null_time_loss,
            "adjudicated_null_duration_time_loss": adjudicated_time_loss,
            "medical_attention_zero_or_closed": source_class_counts["Medical Attention"],
            "unclassified_recorded_only": source_class_counts["unclassified"],
            "undated_eligible": undated,
            "undated_time_loss": undated_added_time_loss,
            "dated_monthly_recorded": monthly_recorded,
            "dated_monthly_time_loss": monthly_tl,
            "observed_days_lost": 17575,
            "burden_days_numerator": 17575,
            "severity_mean_denominator": known_tl,
            "severity_median_denominator": known_tl,
        },
        "adjudication": adjudication_summary,
        "adjudication_reconciliation": {
            "adjudicated_null_duration_time_loss": 15,
            "recorded_injuries_delta": 0,
            "observed_days_lost_delta": 0,
        },
        "team_count": EXPECTED_TEAM_COUNT,
        "league_reconciliation": {
            "recorded_injuries": league_recorded,
            "time_loss_injuries": league_tl,
            "monthly_recorded_injuries": monthly_recorded,
            "monthly_time_loss_injuries": monthly_tl,
        },
        "non_injury_payload_sha256": non_injury_hashes,
        "non_injury_fields_checked": [
            "analysis_window",
            "coverage",
            "prior_season",
            "monthly exposure_hours",
            "monthly distance_km",
        ],
        "controlled_successor_disclosures": {
            "method": list(SUCCESSOR_METHOD),
            "limitations": list(SUCCESSOR_LIMITATIONS),
            "method_sha256": json_sha256(list(SUCCESSOR_METHOD)),
            "limitations_sha256": json_sha256(list(SUCCESSOR_LIMITATIONS)),
        },
        "atomic_output": True,
        "database_access": False,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--predecessor", type=Path, default=DEFAULT_PREDECESSOR)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--source-manifest", type=Path, default=DEFAULT_SOURCE_MANIFEST)
    parser.add_argument("--master", type=Path, default=DEFAULT_MASTER)
    parser.add_argument("--review-workbook", type=Path, default=DEFAULT_REVIEW_WORKBOOK)
    parser.add_argument("--decisions", type=Path, default=DEFAULT_DECISIONS)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--diagnosis-evidence", type=Path, default=DEFAULT_DIAGNOSIS_EVIDENCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--manifest", type=Path, default=None)
    args = parser.parse_args(argv)
    manifest_path = args.manifest or args.output.with_suffix(args.output.suffix + ".reconciliation.json")
    candidate, manifest = build_candidate(
        args.predecessor,
        args.source,
        args.source_manifest,
        args.master,
        args.review_workbook,
        args.decisions,
        args.evidence,
        args.diagnosis_evidence,
    )
    atomic_write_json(args.output, candidate)
    manifest["candidate_path"] = str(args.output.relative_to(ROOT)) if args.output.is_relative_to(ROOT) else str(args.output)
    manifest["candidate_sha256"] = file_sha256(args.output)
    atomic_write_json(manifest_path, manifest)
    headline = {item["key"]: item for item in candidate["league"]["headline"]}
    print(json.dumps({
        "status": "built_and_reconciled",
        "candidate": str(args.output),
        "manifest": str(manifest_path),
        "time_loss_injuries": headline["time_loss_injuries"]["value"],
        "recorded_injuries": headline["recorded_injuries"]["value"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
