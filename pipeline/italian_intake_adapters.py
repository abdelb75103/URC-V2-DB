"""Checksum-bound, privacy-preserving Benetton and Zebre intake adapters."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from pipeline.__main__ import (
    clean_exposure,
    clean_text,
    parse_flexible_date,
    prepare_exposure,
    prepare_intake,
    read_xlsx_rows,
    sha256_file,
    write_rows,
)


ROOT = Path(__file__).resolve().parents[1]
INTAKE = ROOT / "data" / "intake" / "2024-25"
SOURCE_ROOT = Path("/Users/abdelbabiker/Desktop/URC")
SEASON = "2024-25"
CONFIG = {
    "benetton": {
        "team": "Benetton", "source_dir": SOURCE_ROOT / "Benneton",
        "injury_standard": "Benneton standardised_data 24_25.xlsx", "injury_standard_sheet": "Standardized Data",
        "injury_raw": "Overall Benneton Injuries 2024_25.xlsx", "injury_raw_sheet": "Sheet1",
        "exposure_standard": "Benneton standardised_Exposure data .xlsx", "exposure_standard_sheet": "Standardized Data",
        "exposure_raw": "Benneton exposure Data 24_25.xlsx", "exposure_raw_sheet": "ALL DATA",
        "exposure_codebook": "mapping-codebook-Benneton Exp.csv", "player_column": "name",
    },
    "zebre": {
        "team": "Zebre", "source_dir": SOURCE_ROOT / "Zebre",
        "injury_standard": "ZEBRE standardised_data .xlsx", "injury_standard_sheet": "Standardized Data",
        "injury_raw": "Overall Injuries Zebra 2024_25.xlsx", "injury_raw_sheet": "Sheet2",
        "exposure_standard": "Zebre standardised_Exposure data (8).xlsx", "exposure_standard_sheet": "Standardized Data",
        "exposure_raw": "Zebre Exposure Data 24_25 (1).xlsx", "exposure_raw_sheet": "Sheet1",
        "exposure_codebook": "mapping-codebook-Zebre Exp.csv", "player_column": "name",
    },
}


OVERRIDE_FIELDS = {
    "problem_type": ("Adapter Canonical Problem Type", "Adapter Canonical Problem Type Origin"),
    "body_location": ("Adapter Canonical Body Location", "Adapter Canonical Body Location Origin"),
    "tissue_pathology": (
        "Adapter Canonical Tissue Pathology",
        "Adapter Canonical Tissue Pathology Origin",
    ),
    "activity_context": ("Adapter Canonical Activity Context", "Adapter Canonical Activity Context Origin"),
    "contact_context": ("Adapter Canonical Contact Context", "Adapter Canonical Contact Context Origin"),
    "recurrence": ("Adapter Canonical Recurrence Status", "Adapter Canonical Recurrence Status Origin"),
}


@dataclass(frozen=True)
class AdapterResult:
    rows: list[dict[str, Any]]
    counts: dict[str, int]
    analysis_audit: list[dict[str, str]]


def _canonical_date(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%d/%m/%Y")
    text = _clean_scalar(value)
    if text.casefold() in {"", "-", "unknown", "n/a", "na"}:
        return ""
    parsed = parse_flexible_date(value, "day-first")
    if parsed is None:
        raise ValueError("adapter source date is not parseable")
    return parsed.strftime("%d/%m/%Y")


def _clean_scalar(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value).strip()


def _mapping_value(
    mapping: dict[str, Any],
    canonical_field: str,
    sources: dict[str, dict[str, Any]],
) -> tuple[str, str]:
    matches: list[dict[str, Any]] = []
    for collection in ("mappings", "adapter_source_mappings"):
        for entry in mapping.get(collection, []):
            if entry.get("canonical_field") != canonical_field:
                continue
            source = sources.get(entry.get("evidence_source_id"), {})
            evidence = {**entry.get("source_evidence", {}), **entry.get("supporting_evidence", {})}
            if evidence and all(_clean_scalar(source.get(field)) == str(value) for field, value in evidence.items()):
                matches.append(entry)
    targets = {entry["canonical_value"] for entry in matches}
    if len(targets) > 1:
        raise ValueError(f"conflicting approved mappings for {canonical_field}")
    if not matches:
        return "unknown", "approved_mapping:no_supported_evidence"
    chosen = max(matches, key=lambda entry: len(entry.get("source_evidence", {})) + len(entry.get("supporting_evidence", {})))
    adjudication_id = clean_text(chosen.get("adjudication_id"))
    origin = (
        f"manual_adjudication:{adjudication_id}"
        if adjudication_id
        else f"approved_mapping:{chosen['evidence_class']}"
    )
    return chosen["canonical_value"], origin


def _set_overrides(
    output: dict[str, Any],
    mapping: dict[str, Any],
    standard_source: dict[str, Any],
    raw_source: dict[str, Any],
) -> None:
    sources = {"injury": standard_source, "raw_injury": raw_source}
    problem, problem_origin = _mapping_value(mapping, "problem_type", sources)
    body, body_origin = _mapping_value(mapping, "body_location", sources)
    tissue, tissue_origin = _mapping_value(mapping, "tissue_pathology", sources)
    occasion, occasion_origin = _mapping_value(mapping, "occasion_category", sources)
    contact, contact_origin = _mapping_value(mapping, "contact_context", sources)
    recurrence, recurrence_origin = _mapping_value(mapping, "recurrence", sources)
    if problem == "illness":
        body, body_origin = "unknown", "approved_mapping:not_applicable_to_illness"
        tissue, tissue_origin = "unknown", "approved_mapping:not_applicable_to_illness"
    for canonical, value, origin in (
        ("problem_type", problem, problem_origin),
        ("body_location", body, body_origin),
        ("tissue_pathology", tissue, tissue_origin),
        (
            "activity_context",
            (
                "training" if occasion == "training" else
                "urc_match" if occasion == "match" and clean_text(standard_source.get("Match Type")).casefold() in {"urc", "united rugby championship"} else
                "match" if occasion == "match" else "unknown"
            ),
            occasion_origin,
        ),
        ("contact_context", contact, contact_origin),
        ("recurrence", recurrence, recurrence_origin),
    ):
        value_field, origin_field = OVERRIDE_FIELDS[canonical]
        output[value_field] = value
        output[origin_field] = origin


def adapt_injury_rows(
    team_key: str,
    standard_rows: list[dict[str, Any]],
    raw_rows: list[dict[str, Any]],
    mapping: dict[str, Any],
) -> AdapterResult:
    if team_key not in {"benetton", "zebre"}:
        raise ValueError(f"unsupported Italian team: {team_key}")
    if len(standard_rows) != len(raw_rows):
        raise ValueError("injury adapter row-count mismatch")

    output_rows: list[dict[str, Any]] = []
    counts = {
        "rows": len(standard_rows), "dob_values_removed": 0,
        "injury_dates_restored": 0, "return_dates_restored": 0,
        "days_injured_restored": 0, "tissue_values_restored": 0,
        "recurrence_values_restored": 0,
    }
    seen: dict[str, int] = {}
    analysis_audit: list[dict[str, str]] = []
    for index, (standard, raw) in enumerate(zip(standard_rows, raw_rows, strict=True), start=2):
        output = {key: value for key, value in standard.items() if not key.startswith("_")}
        if _clean_scalar(output.get("DOB")):
            counts["dob_values_removed"] += 1
        output["DOB"] = ""

        if team_key == "benetton":
            restorations = {
                "Date Injured": _canonical_date(raw.get("Injury Onset")),
                "Confirmed Return Date": _canonical_date(raw.get("End of injury")),
                "Days Injured": _clean_scalar(raw.get("Days Injured")),
                "Injury Tissue Type/s": _clean_scalar(raw.get("Injury Tissue Type/s")),
                "Recurrence": _clean_scalar(raw.get("Recurrence (Recurrence stage)")),
            }
        else:
            restorations = {
                "Date Injured": _canonical_date(raw.get("Date of injury")),
                "Confirmed Return Date": _canonical_date(
                    raw.get("Injury closing date (back to FULL participation)")
                ),
                "Fit For Selection Date": _canonical_date(
                    raw.get("Injury closing date (back to FULL participation)")
                ),
                "Days Injured": _clean_scalar(raw.get("Total Days Lost")),
            }
        for field, value in restorations.items():
            if value and _clean_scalar(output.get(field)) != value:
                if field == "Date Injured":
                    counts["injury_dates_restored"] += 1
                elif field in {"Confirmed Return Date", "Fit For Selection Date"}:
                    counts["return_dates_restored"] += 1
                elif field == "Days Injured":
                    counts["days_injured_restored"] += 1
                elif field == "Injury Tissue Type/s":
                    counts["tissue_values_restored"] += 1
                elif field == "Recurrence":
                    counts["recurrence_values_restored"] += 1
            output[field] = value

        _set_overrides(output, mapping, standard, raw)
        return_present = bool(clean_text(output.get("Confirmed Return Date")))
        days_text = clean_text(output.get("Days Injured"))
        zero_days = False
        try:
            zero_days = float(days_text) == 0
        except ValueError:
            pass
        closed = "closed" if return_present or (team_key == "zebre" and zero_days) else "open"
        output["Adapter Canonical Injury Closed"] = closed
        output["Adapter Canonical Injury Closed Origin"] = "approved_mapping:deterministic_derivation"
        output["Adapter Canonical Fit For Selection Status"] = (
            "fit" if team_key == "zebre" and return_present else "unknown"
        )
        output["Adapter Canonical Fit For Selection Status Origin"] = (
            "approved_mapping:source_reported" if team_key == "zebre" and return_present
            else "approved_mapping:no_supported_evidence"
        )
        output_rows.append(output)

        fingerprint = repr(sorted(
            (key, _clean_scalar(value)) for key, value in raw.items() if not key.startswith("_")
        ))
        if fingerprint in seen:
            analysis_audit.append({
                "standardised_row_number": str(index),
                "field": "analysis_eligibility",
                "action": "exclude",
                "reason": "exact_duplicate_copy",
                "review_status": "human_approved",
            })
        else:
            seen[fingerprint] = index

    counts["exact_duplicate_copies"] = len(analysis_audit)
    return AdapterResult(output_rows, counts, analysis_audit)


def adapt_exposure_rows(
    team_key: str,
    standard_rows: list[dict[str, Any]],
    raw_rows: list[dict[str, Any]],
) -> AdapterResult:
    if team_key not in {"benetton", "zebre"}:
        raise ValueError(f"unsupported Italian team: {team_key}")
    if len(standard_rows) != len(raw_rows):
        raise ValueError("exposure adapter row-count mismatch")
    output_rows: list[dict[str, Any]] = []
    counts = {"rows": len(standard_rows), "dates_restored": 0, "durations_restored": 0, "vhsr_restored": 0}
    for standard, raw in zip(standard_rows, raw_rows, strict=True):
        output = {key: value for key, value in standard.items() if not key.startswith("_")}
        if team_key == "benetton":
            output["name"] = standard.get("Name")
            restorations = {
                "session date": _canonical_date(raw.get("date")),
                "minutes total": raw.get("duration (min)"),
                "distance total": raw.get("distance (m)"),
                "HSR > 18 Km/h (m) (5 m/s)": raw.get("HSR > 18 Km/h (m)"),
                "HSR > 20 Km/h (m) (5.5 m/s)": raw.get("HSR > 20 Km/h (m)"),
                "HSR > 25.2 Km/h (m) (7 m/s)": raw.get("HSR > 25,2 Km/h (m)"),
                "high speed running distance": raw.get("HSR > 20 Km/h (m)"),
                "very high speed running distance": raw.get("HSR > 25,2 Km/h (m)"),
            }
        else:
            restorations = {
                "session date": _canonical_date(raw.get("Date")),
                "session start date time": raw.get("Start Time"),
                "session end date time": raw.get("End Time"),
                "minutes total": raw.get("Duration"),
                "distance total": raw.get("Total Distance"),
                "HSR > 18 Km/h (m) (5 m/s)": raw.get("HSRm (>18km/hr)"),
                "HSR > 20 Km/h (m) (5.5 m/s)": raw.get("HSRm (>20km/h)"),
                "HSR > 25.2 Km/h (m) (7 m/s)": raw.get("vHSR m (25km/hr)"),
                "high speed running distance": raw.get("HSRm (>20km/h)"),
                "very high speed running distance": raw.get("vHSR m (25km/hr)"),
                "session type": raw.get("Activity Name"),
            }
        for field, value in restorations.items():
            if value is not None and _clean_scalar(output.get(field)) != _clean_scalar(value):
                if field == "session date":
                    counts["dates_restored"] += 1
                elif field == "minutes total":
                    counts["durations_restored"] += 1
                elif field == "very high speed running distance":
                    counts["vhsr_restored"] += 1
            output[field] = value
        output_rows.append(output)
    return AdapterResult(output_rows, counts, [])


def _canonical_counts(rows: list[dict[str, Any]], field: str) -> dict[str, int]:
    result: dict[str, int] = {}
    for row in rows:
        value = _clean_scalar(row.get(field))
        result[value] = result.get(value, 0) + 1
    return result


def _assert_expected_counts(team_key: str, injury: AdapterResult, exposure: AdapterResult) -> None:
    if team_key == "benetton":
        expected = {
            "Adapter Canonical Problem Type": {"injury": 43},
            "Adapter Canonical Activity Context": {"urc_match": 16, "match": 14, "training": 9, "unknown": 4},
            "Adapter Canonical Contact Context": {"contact": 21, "non_contact": 21, "unknown": 1},
            "Adapter Canonical Recurrence Status": {"first_episode": 34, "recurrence": 3, "unknown": 6},
            "Adapter Canonical Body Location": {
                key: value for key, value in _canonical_counts(injury.rows, "Adapter Canonical Body Location").items()
                if key != "unknown"
            },
            "Adapter Canonical Tissue Pathology": {
                key: value for key, value in _canonical_counts(injury.rows, "Adapter Canonical Tissue Pathology").items()
                if key != "unknown"
            },
        }
        for field in expected:
            actual = _canonical_counts(injury.rows, field)
            if field == "Adapter Canonical Body Location":
                if actual.get("unknown", 0) != 0:
                    raise ValueError("Benetton body-location reconciliation failed")
            elif field == "Adapter Canonical Tissue Pathology":
                if actual.get("unknown", 0) != 14 or sum(actual.values()) - actual.get("unknown", 0) != 29:
                    raise ValueError("Benetton tissue reconciliation failed")
            elif actual != expected[field]:
                raise ValueError(f"Benetton reconciliation failed for {field}: {actual}")
        if len(injury.rows) != 43 or len(injury.analysis_audit) != 1 or len(exposure.rows) != 8446:
            raise ValueError("Benetton row/duplicate reconciliation failed")
        if _canonical_counts(injury.rows, "Adapter Canonical Injury Closed") != {"closed": 40, "open": 3}:
            raise ValueError("Benetton closure reconciliation failed")
        if _canonical_counts(injury.rows, "Adapter Canonical Fit For Selection Status") != {"unknown": 43}:
            raise ValueError("Benetton fit-for-selection reconciliation failed")
    else:
        expected = {
            "Adapter Canonical Problem Type": {"illness": 30, "injury": 103},
            "Adapter Canonical Activity Context": {"match": 39, "training": 53, "unknown": 41},
            "Adapter Canonical Contact Context": {"contact": 50, "non_contact": 52, "unknown": 31},
            "Adapter Canonical Recurrence Status": {"first_episode": 79, "recurrence": 26, "unknown": 28},
        }
        for field, counts in expected.items():
            actual = _canonical_counts(injury.rows, field)
            if actual != counts:
                raise ValueError(f"Zebre reconciliation failed for {field}: {actual}")
        body = _canonical_counts(injury.rows, "Adapter Canonical Body Location")
        tissue = _canonical_counts(injury.rows, "Adapter Canonical Tissue Pathology")
        if body.get("unknown") != 30 or sum(body.values()) - body.get("unknown", 0) != 103:
            raise ValueError("Zebre body-location reconciliation failed")
        if tissue.get("unknown") != 85 or tissue.get("unknown", 0) + sum(
            count for key, count in tissue.items() if key != "unknown"
        ) != 133:
            raise ValueError("Zebre taxonomy reconciliation failed")
        if len(injury.rows) != 133 or injury.analysis_audit or len(exposure.rows) != 4813:
            raise ValueError("Zebre row/duplicate reconciliation failed")
        if _canonical_counts(injury.rows, "Adapter Canonical Injury Closed") != {"closed": 123, "open": 10}:
            raise ValueError("Zebre closure reconciliation failed")
        if _canonical_counts(injury.rows, "Adapter Canonical Fit For Selection Status") != {"fit": 117, "unknown": 16}:
            raise ValueError("Zebre fit-for-selection reconciliation failed")


def _assert_expected_cleaning_qc(team_key: str, qc: dict[str, Any]) -> None:
    reasons = qc.get("exclusion_reason_counts", {})
    if team_key == "benetton":
        if reasons.get("exact_duplicate_copy") != 26 or reasons.get("session_minutes_above_220") != 49:
            raise ValueError("Benetton exposure cleaning reconciliation failed")
    elif reasons.get("exact_duplicate_copy", 0) != 0 or reasons.get("missing_or_unparseable_minutes") != 1:
        raise ValueError("Zebre exposure cleaning reconciliation failed")


def _write_json(path: Path, value: dict[str, Any] | list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def prepare_team(team_key: str, *, approved_controls: bool = False) -> dict[str, str]:
    config = CONFIG[team_key]
    team_dir = INTAKE / team_key
    source_dir = config["source_dir"]
    suffix = ".json" if approved_controls else ".draft.json"
    mapping_path = team_dir / f"source_to_canonical_mapping.v2{suffix}"
    adapter_plan_path = team_dir / f"source_adapter_plan.v1{suffix}"
    mapping = json.loads(mapping_path.read_text())

    injury_standard_path = source_dir / config["injury_standard"]
    injury_raw_path = source_dir / config["injury_raw"]
    injury_headers, injury_standard_rows = read_xlsx_rows(injury_standard_path, config["injury_standard_sheet"])
    _, injury_raw_rows = read_xlsx_rows(injury_raw_path, config["injury_raw_sheet"])
    injury = adapt_injury_rows(team_key, injury_standard_rows, injury_raw_rows, mapping)
    override_headers = [field for pair in OVERRIDE_FIELDS.values() for field in pair] + [
        "Adapter Canonical Injury Closed", "Adapter Canonical Injury Closed Origin",
        "Adapter Canonical Fit For Selection Status", "Adapter Canonical Fit For Selection Status Origin",
    ]
    injury_headers = injury_headers + [header for header in override_headers if header not in injury_headers]
    injury_sanitized = team_dir / f"{team_key}_injury_standardised_sanitized_{SEASON}.csv"
    write_rows(injury_sanitized, injury.rows, injury_headers)
    injury_qc = team_dir / f"{team_key}_injury_adapter_qc_{SEASON}.json"
    _write_json(injury_qc, {
        "rule_version": "italian_injury_boundary_adapter_2026-07-14_v1",
        "team": config["team"], "season": SEASON,
        "mapping_sha256": sha256_file(mapping_path), "adapter_plan_sha256": sha256_file(adapter_plan_path),
        "source_file_sha256s": {
            "standard": sha256_file(injury_standard_path), "raw_reference": sha256_file(injury_raw_path),
        },
        "output_file": str(injury_sanitized), "output_file_sha256": sha256_file(injury_sanitized),
        "output_rows": len(injury.rows), "action_counts": injury.counts,
        "canonical_counts": {field: _canonical_counts(injury.rows, field) for field in override_headers[::2]},
        "privacy": {"dob_values_remaining": 0, "raw_identifier_columns_copied": [], "identifying_values_logged": False},
    })
    analysis_audit = team_dir / f"{team_key}_injury_analysis_audit_{SEASON}.csv"
    audit_fields = ["standardised_row_number", "field", "action", "reason", "review_status"]
    write_rows(analysis_audit, injury.analysis_audit, audit_fields)

    manifest_path = team_dir / "intake_manifest.json"
    _write_json(manifest_path, {"team": team_key, "season": SEASON})
    injury_locator = team_dir / f"{team_key}_injury_intake_locator_enriched_{SEASON}.csv"
    prepare_intake(argparse.Namespace(
        team=config["team"], season=SEASON, file=str(injury_sanitized),
        source_file=str(injury_raw_path), output=str(injury_locator), manifest=str(manifest_path),
        source_sheet=config["injury_raw_sheet"], player_id_column="PlayerID",
    ))

    exposure_standard_path = source_dir / config["exposure_standard"]
    exposure_raw_path = source_dir / config["exposure_raw"]
    exposure_headers, exposure_standard_rows = read_xlsx_rows(exposure_standard_path, config["exposure_standard_sheet"])
    _, exposure_raw_rows = read_xlsx_rows(exposure_raw_path, config["exposure_raw_sheet"])
    exposure = adapt_exposure_rows(team_key, exposure_standard_rows, exposure_raw_rows)
    exposure_adapted = team_dir / f"{team_key}_exposure_standardised_sanitized_{SEASON}.csv"
    write_rows(exposure_adapted, exposure.rows, exposure_headers)
    exposure_locator = team_dir / f"{team_key}_exposure_intake_locator_enriched_{SEASON}.csv"
    exposure_qc = team_dir / f"{team_key}_exposure_qc_{SEASON}.json"
    prepare_exposure(argparse.Namespace(
        team=config["team"], season=SEASON, file=str(exposure_adapted), sheet="Standardized Data",
        codebook=str(source_dir / config["exposure_codebook"]), output=str(exposure_locator),
        qc_output=str(exposure_qc), manifest=str(manifest_path), reporting_grain="session",
        player_column=config["player_column"], date_column="session date", minutes_column="minutes total",
        distance_column="distance total", date_order="day-first", derive_minutes_from_timestamps=False,
        start_timestamp_column="session start date time", end_timestamp_column="session end date time",
        distance_source_file="", distance_source_sheet="", distance_source_column="",
    ))
    exposure_cleaned = team_dir / f"{team_key}_exposure_cleaned_{SEASON}.csv"
    exposure_clean_qc = team_dir / f"{team_key}_exposure_cleaning_qc_{SEASON}.json"
    clean_exposure(argparse.Namespace(
        file=str(exposure_locator), team=config["team"], season=SEASON,
        output=str(exposure_cleaned), qc_output=str(exposure_clean_qc), manifest=str(manifest_path),
        reporting_grain="session", date_order="day-first",
        window_start="2024-09-20", window_end="2025-06-14",
    ))
    _assert_expected_counts(team_key, injury, exposure)
    _assert_expected_cleaning_qc(team_key, json.loads(exposure_clean_qc.read_text()))

    manifest = json.loads(manifest_path.read_text())
    manifest["injury_adapter"] = {
        "qc_file": str(injury_qc), "qc_file_sha256": sha256_file(injury_qc),
        "analysis_audit_file": str(analysis_audit), "analysis_audit_file_sha256": sha256_file(analysis_audit),
        "sanitized_file": str(injury_sanitized), "sanitized_file_sha256": sha256_file(injury_sanitized),
    }
    _write_json(manifest_path, manifest)
    return {
        "injury": str(injury_locator), "exposure": str(exposure_cleaned),
        "manifest": str(manifest_path), "injury_qc": str(injury_qc),
        "analysis_audit": str(analysis_audit),
    }


def approve_control_files(team_key: str) -> None:
    team_dir = INTAKE / team_key
    draft_mapping = team_dir / "source_to_canonical_mapping.v2.draft.json"
    final_mapping = team_dir / "source_to_canonical_mapping.v2.json"
    mapping = json.loads(draft_mapping.read_text())
    mapping["status"] = "approved"
    _write_json(final_mapping, mapping)
    draft_plan = team_dir / "source_adapter_plan.v1.draft.json"
    final_plan = team_dir / "source_adapter_plan.v1.json"
    plan = json.loads(draft_plan.read_text())
    plan["status"] = "approved"
    _write_json(final_plan, plan)


def approve_team(team_key: str, outputs: dict[str, str]) -> None:
    team_dir = INTAKE / team_key
    final_mapping = team_dir / "source_to_canonical_mapping.v2.json"
    final_plan = team_dir / "source_adapter_plan.v1.json"
    plan = json.loads(final_plan.read_text())

    approved_at = datetime.now().astimezone().isoformat()
    profile = json.loads((team_dir / "team_intake_profile.v2.draft.json").read_text())
    profile.update({
        "approval_status": "approved", "approved_by": "Abdel Babiker", "approved_at": approved_at,
        "mapping_path": final_mapping.name, "mapping_sha256": sha256_file(final_mapping),
        "approved_input_sha256s": [sha256_file(Path(outputs["injury"])), sha256_file(Path(outputs["exposure"]))],
    })
    final_profile = team_dir / "team_intake_profile.v2.json"
    _write_json(final_profile, profile)
    manifest_path = Path(outputs["manifest"])
    manifest = json.loads(manifest_path.read_text())
    bound_fields = (
        "team", "season", "profile_version", "decision", "mapping_path", "mapping_sha256",
        "mapping_version", "ai_review_status", "ai_reviewed_by", "ai_reviewed_at", "approved_by",
        "approved_at", "unresolved_adjudication_ids", "approved_input_sha256s",
    )
    manifest["intake_profile"] = {field: profile.get(field) for field in bound_fields}
    manifest["intake_profile"].update({
        "profile_path": final_profile.name, "profile_sha256": sha256_file(final_profile),
    })
    manifest["adapter_plan"] = {
        "path": final_plan.name, "sha256": sha256_file(final_plan),
        "version": plan["adapter_plan_version"], "approved_by": "Abdel Babiker", "approved_at": approved_at,
    }
    _write_json(manifest_path, manifest)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Prepare approved Italian intake adapters locally.")
    parser.add_argument("--team", choices=sorted(CONFIG), required=True)
    parser.add_argument("--approve", action="store_true")
    args = parser.parse_args(argv)
    if args.approve:
        approve_control_files(args.team)
    outputs = prepare_team(args.team, approved_controls=args.approve)
    if args.approve:
        approve_team(args.team, outputs)
    print(json.dumps(outputs, indent=2))


if __name__ == "__main__":
    main()
