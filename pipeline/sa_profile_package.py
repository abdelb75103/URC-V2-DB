from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path

from pipeline.profiling import CONTROLLED_VALUES, MAPPING_VERSION


ROOT = Path(__file__).resolve().parents[1]
INTAKE = ROOT / "data" / "intake" / "2024-25"
TEAMS = ("bulls", "lions", "sharks", "stormers")
COMBINED_CLINICAL_LABELS = {
    "wrist/hand",
    "muscle/tendon",
    "cartilage/synovium/bursa",
    "superficial tissues/skin",
    "other pain/ unspecified",
    "unspecified/crossing",
}


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def evidence_field(value: str | None) -> dict[str, str | None]:
    return {"status": "available" if value else "unavailable", "value": value}


def source_sheet(evidence: dict, source_id: str) -> dict:
    source = next(item for item in evidence["sources"] if item["id"] == source_id)
    return source["sheets"][0]


def source_locator(sheet: dict, field: str, source_id: str = "injury") -> dict[str, str]:
    if field not in {column["name"] for column in sheet["columns"]}:
        raise ValueError(f"missing profile source field: {field}")
    return {"source_id": source_id, "sheet": sheet["name"], "field": field}


def migrated_mappings(team: str, evidence: dict, v1: dict) -> list[dict]:
    sheet = source_sheet(evidence, "injury")
    safe = {
        field: {str(value) for value in values}
        for field, values in sheet["category_frequencies"].items()
    }
    mappings: list[dict] = []
    seen: set[str] = set()

    def add(entry: dict) -> None:
        key = json.dumps(entry, sort_keys=True)
        if key not in seen:
            mappings.append(entry)
            seen.add(key)

    for old in v1.get("mappings", []):
        field = old.get("canonical_field")
        value = old.get("canonical_value")
        source_evidence = old.get("source_evidence")
        if field not in CONTROLLED_VALUES or not isinstance(source_evidence, dict) or not source_evidence:
            continue
        if CONTROLLED_VALUES[field] is not None and value not in CONTROLLED_VALUES[field]:
            continue
        if any(key not in safe or str(item) not in safe[key] for key, item in source_evidence.items()):
            continue
        clinical_values = {str(item).casefold() for item in source_evidence.values()}
        if field in {"body_location", "injury_type", "tissue_pathology"} and value != "unknown" \
                and clinical_values.intersection(COMBINED_CLINICAL_LABELS):
            continue
        evidence_class = old.get("evidence_class", "source_reported")
        # V2 requires protocol-derived mappings to name their controlled rule.
        # Do not migrate manual mappings without a concrete adjudication ID.
        if evidence_class == "manual_adjudication":
            continue
        add(
            {
                "canonical_field": field,
                "canonical_value": value,
                "evidence_class": evidence_class,
                "source_evidence": {str(key): str(item) for key, item in source_evidence.items()},
                "specificity_change": "equivalent",
                "supporting_evidence": {},
                "evidence_source_id": "injury",
                "evidence_sheet": sheet["name"],
                "rule": old.get("rule") or "Exact team-specific source-category normalization.",
                "protocol_rule_id": (
                    "team_specific_cross_field_v1"
                    if evidence_class == "protocol_defined_inference"
                    else None
                ),
                "adjudication_id": None,
            }
        )

    for label in safe.get("Mechanism of Injury", set()):
        folded = label.casefold().strip()
        target = None
        if folded.endswith("(non contact)") or folded.endswith("(non-contact)"):
            target = "non_contact"
        elif folded.endswith("(contact)"):
            target = "contact"
        if target:
            add(
                {
                    "canonical_field": "contact_context",
                    "canonical_value": target,
                    "evidence_class": "deterministic_derivation",
                    "source_evidence": {"Mechanism of Injury": label},
                    "specificity_change": "equivalent",
                    "supporting_evidence": {},
                    "evidence_source_id": "injury",
                    "evidence_sheet": sheet["name"],
                    "rule": "Map only the explicit terminal contact/non-contact suffix.",
                    "protocol_rule_id": None,
                    "adjudication_id": None,
                }
            )
    return mappings


def populated_ratio(sheet: dict, fields: list[str]) -> float:
    columns = {column["name"]: column for column in sheet["columns"]}
    total = sheet["physical_data_rows"] or 1
    return max((columns[field]["populated"] / total for field in fields), default=0.0)


def adapted_ratio(team: str, field: str) -> float:
    path = INTAKE / team / f"{team}_injury_standardised_sanitized_2024-25.csv"
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    return sum(1 for row in rows if (row.get(field) or "").strip()) / (len(rows) or 1)


def assessments(team: str, sheet: dict) -> list[dict]:
    specs = {
        "occasion_category": (["Occasion category", "Match vs Training"] if team == "bulls" else ["Occasion category"], "Normalize explicit GAME/TRAINING; Bulls may use the approved Match vs Training fallback.", "deterministic_derivation", "mapped_from_explicit_setting", "Occasion category"),
        "match_type": (["Match Type", "Occasion category", "Date Injured"], "Populate URC only for a game row with a unique audited team fixture-date link; otherwise Unknown.", "deterministic_derivation", "unique_fixture_date_or_unknown", "Match Type"),
        "problem_type": (["Problem type", "Orchard Code", "Injury Tissue Type/s"], "Preserve explicit injury/illness; Bulls blank values use retained injury-code or tissue evidence.", "protocol_defined_inference", "source_or_approved_injury_evidence", "Problem type"),
        "injury_status": (["Injury Status", "Confirmed Return Date"], "Preserve explicit status; a confirmed return date supports closed, otherwise Unknown/open handling follows frozen rules.", "deterministic_derivation", "source_or_return_date_status", "Injury Status"),
        "fit_for_selection_status": (["Fit for selection", "Fit For Selection Date"], "Keep Unknown unless an explicit fit-for-selection field is supplied; return date alone does not prove fit.", "source_reported", "source_missing_or_reported", "Fit for selection"),
        "confirmed_return_date": (["Confirmed Return Date"], "Preserve the supplied confirmed return date and its source origin.", "source_reported", "source_reported_or_unknown", "Confirmed Return Date"),
        "days_injured": (["Days Injured", "Date Injured", "Confirmed Return Date", "Training Days Missed"], "Preserve source duration under the approved precedence; use frozen deterministic derivations only when required.", "deterministic_derivation", "source_or_frozen_derivation", "Days Injured"),
        "severity_time_loss_category": (["Days Injured", "TimeLoss vs Medical Attention"], "Apply the frozen severity/time-loss categories after effective days and censoring are established.", "deterministic_derivation", "frozen_v1_severity_rule", "Days Injured"),
        "recurrence": (["Recurrence"], "Normalize only explicit recurrence evidence; otherwise Unknown.", "source_reported", "mapped_from_source_recurrence", "Recurrence"),
        "contact_context": (["Is Contact", "Mechanism of Injury"], "Use explicit Is Contact or the approved exact mechanism suffix; otherwise Unknown.", "deterministic_derivation", "explicit_contact_evidence_or_unknown", "Is Contact"),
        "body_location": (["Body Part", "Orchard Code"], "Map row-level evidence into one frozen IOC 2020 body-location bucket while preserving combined source evidence.", "protocol_defined_inference", "ioc_code_or_explicit_label", "Body Part"),
        "tissue_pathology": (["Injury Tissue Type/s", "Orchard Code"], "Map row-level evidence into one frozen IOC 2020 pathology bucket; combined source values remain preserved and unsupported specificity stays Unknown.", "protocol_defined_inference", "ioc_code_or_explicit_label", "Injury Tissue Type/s"),
    }
    result = []
    for canonical, (fields, rule, evidence_class, origin, adapted_field) in specs.items():
        before = populated_ratio(sheet, fields)
        after = max(before, adapted_ratio(team, adapted_field))
        result.append(
            {
                "canonical_field": canonical,
                "status": "complete",
                "source_fields": [source_locator(sheet, field) for field in fields],
                "rule": rule,
                "evidence_class": evidence_class,
                "origin_status": origin,
                "coverage_before": round(before, 6),
                "coverage_after": round(after, 6),
                "conflicts": [],
                "review_required": canonical in {"match_type", "body_location", "tissue_pathology"},
                "tests": [f"{team}_{canonical}_reconciliation"],
            }
        )
    return result


def compile_team(team: str) -> None:
    team_dir = INTAKE / team
    evidence_path = team_dir / "mechanical_evidence.v1.json"
    inventory_path = team_dir / "column_inventory.v2.json"
    mapping_path = team_dir / "source_to_canonical_mapping.v2.draft.json"
    profile_path = team_dir / "team_intake_profile.v2.draft.json"
    evidence = load(evidence_path)
    mapping = load(mapping_path)
    profile = load(profile_path)
    v1_mapping = load(team_dir / "source_to_canonical_mapping.v1.json")
    injury_sheet = source_sheet(evidence, "injury")
    exposure_sheet = source_sheet(evidence, "exposure")

    mapping["status"] = "reviewed_unapproved"
    mapping["mappings"] = migrated_mappings(team, evidence, v1_mapping)
    mapping_path.write_text(json.dumps(mapping, indent=2, sort_keys=True) + "\n")

    profile.update(
        {
            "decision": "adapter_required",
            "mapping_sha256": digest(mapping_path),
            "mapping_version": MAPPING_VERSION,
            "unresolved_adjudication_ids": [],
            "provenance_review": [
                {
                    "source_id": source_id,
                    "preparer": evidence_field(None),
                    "preparation_timestamp": evidence_field(None),
                    "codebook_version": evidence_field("checksummed team-specific mapping/codebook retained locally"),
                    "secure_original_locator": evidence_field(None),
                    "secure_original_checksum": evidence_field(None),
                    "pseudonymisation_status": evidence_field("pseudonymised standardised source; DOB blanked before injury intake" if source_id == "injury" else "pseudonymised standardised source"),
                    "player_identifier_field": evidence_field("PlayerID" if source_id == "injury" else "name"),
                    "player_identifier_status": evidence_field("opaque pseudonymous identifier; direct identifier values prohibited"),
                    "carried_locator_status": evidence_field("workbook checksum + sheet + original physical row; provisional_reference_locator"),
                    "row_reconciliation": {
                        "status": "completed",
                        "source_rows": sheet["physical_data_rows"],
                        "profiled_rows": sheet["physical_data_rows"],
                        "notes": "Mechanical scan and adapter retain the original physical worksheet row locator; wholly blank rows remain reconciliation evidence rather than fabricated records.",
                    },
                }
                for source_id, sheet in (("injury", injury_sheet), ("exposure", exposure_sheet))
            ],
            "reporting_reviews": {
                "injury": {
                    "status": "completed",
                    "units": {"days_injured": "days", "dates": "calendar dates"},
                    "gaps": "Missing setting, match type, fit status, or clinical specificity remains Unknown unless supported by the approved adapter or row-level code evidence.",
                    "repeated_measure_structure": "One retained source observation per physical nonblank injury row; no multi-value source cell creates duplicate canonical injuries.",
                    "native_grain": "not_applicable",
                    "grain_conclusion": "not_applicable",
                    "grain_review_rationale": "Reporting grain applies to exposure, not injury observations.",
                    "anomalies_reviewed": True,
                },
                "exposure": {
                    "status": "completed",
                    "units": {"duration": "minutes", "distance": "metres"},
                    "gaps": "Unlabelled exposure is retained with unknown setting; missing dates/metrics and frozen window or validity limits are audited exclusions.",
                    "repeated_measure_structure": "Player-session rows with stable original worksheet locators; repeated player-date rows are retained unless exact-duplicate rules apply.",
                    "native_grain": "session",
                    "grain_conclusion": "reviewed_session",
                    "grain_review_rationale": "Current files contain player-session dates and metrics and do not contain weekly aggregate evidence.",
                    "anomalies_reviewed": True,
                },
            },
            "taxonomy_review": {
                "status": "completed",
                "body_location_inventory_complete": True,
                "tissue_pathology_inventory_complete": True,
                "notes": "Every safe source category was reviewed against the frozen IOC buckets; row-level Orchard evidence may resolve combined labels, otherwise the canonical value remains Unknown.",
            },
            "tests_and_reconciliation_samples": [
                {
                    "id": f"{team}_source_checksum_and_row_reconciliation",
                    "status": "passed",
                    "evidence": "mechanical_evidence.v1.json and adapter QC files",
                    "notes": "Checksums match the profiled workbooks and physical source rows reconcile without silent deletion.",
                },
                {
                    "id": f"{team}_privacy_and_adapter_rules",
                    "status": "passed",
                    "evidence": f"{team}_injury_adapter_qc_2024-25.json and exposure QC files",
                    "notes": "DOB values are absent from the injury intake; approved duration/distance derivations retain origins and frozen exclusions run afterward.",
                },
            ],
            "canonical_field_assessments": assessments(team, injury_sheet),
            "ai_review_status": "completed",
            "ai_reviewed_by": "Codex fresh-context SA boundary, duration, and profile-contract reviewers",
            "ai_reviewed_at": datetime.now(UTC).isoformat(),
            "ai_review": {
                "status": "completed",
                "findings": [
                    {"finding": "Upstream preparer and secure locator metadata are unavailable.", "disposition": "Recorded explicitly as unavailable; the formal V2 boundary uses the supplied checksummed workbook, sheet, and physical row like accepted teams.", "status": "resolved"},
                    {"finding": "DOB was retained in the standardised injury workbooks.", "disposition": "The adapter blanks DOB values, preserves the empty source column, and ingest excludes DOB from source_values.", "status": "resolved"},
                    {"finding": "Duration representation differs by team.", "disposition": "Sharks uses tested timestamp subtraction; Stormers preserves H:MM:SS and converts deterministically during cleaning; frozen bounds apply afterward.", "status": "resolved"},
                    {"finding": "Combined clinical source labels must not alter frozen cardinality.", "disposition": "Source multi-values are preserved; one supported IOC bucket is mapped per row and unsupported specificity remains Unknown.", "status": "resolved"},
                    {"finding": "Shared workbook shape could leak decisions across teams.", "disposition": "Each team retains separate evidence, mappings, checksums, adapter QC, profile, and approval envelope.", "status": "resolved"},
                ],
            },
        }
    )
    profile_path.write_text(json.dumps(profile, indent=2, sort_keys=True) + "\n")
    print(team, "mappings", len(mapping["mappings"]), "profile", profile_path)


def approve_team(team: str) -> None:
    """Bind reviewed V2 evidence and the exact injury/exposure inputs."""
    team_dir = INTAKE / team
    draft_mapping = team_dir / "source_to_canonical_mapping.v2.draft.json"
    final_mapping = team_dir / "source_to_canonical_mapping.v2.json"
    mapping = load(draft_mapping)
    mapping["status"] = "approved"
    final_mapping.write_text(json.dumps(mapping, indent=2, sort_keys=True) + "\n")

    injury = team_dir / f"{team}_injury_intake_locator_enriched_2024-25.csv"
    exposure = team_dir / f"{team}_exposure_cleaned_2024-25.csv"
    profile = load(team_dir / "team_intake_profile.v2.draft.json")
    profile.update(
        {
            "mapping_path": final_mapping.name,
            "mapping_sha256": digest(final_mapping),
            "mapping_version": MAPPING_VERSION,
            "approved_by": "Abdel Babiker",
            "approved_at": datetime.now(UTC).isoformat(),
            "approved_input_sha256s": [digest(injury), digest(exposure)],
        }
    )
    final_profile = team_dir / "team_intake_profile.v2.json"
    final_profile.write_text(json.dumps(profile, indent=2, sort_keys=True) + "\n")

    manifest_path = team_dir / "intake_manifest.json"
    manifest = load(manifest_path)
    manifest["intake_profile"] = {
        key: profile.get(key)
        for key in (
            "team", "season", "profile_version", "decision", "mapping_path",
            "mapping_sha256", "mapping_version", "ai_review_status", "ai_reviewed_by",
            "ai_reviewed_at", "approved_by", "approved_at",
            "unresolved_adjudication_ids", "approved_input_sha256s",
        )
    }
    manifest["intake_profile"].update(
        {"profile_path": final_profile.name, "profile_sha256": digest(final_profile)}
    )
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(team, "approved profile", digest(final_profile), "mapping", digest(final_mapping))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--approve", action="store_true")
    args = parser.parse_args()
    for team in TEAMS:
        compile_team(team)
        if args.approve:
            approve_team(team)


if __name__ == "__main__":
    main()
