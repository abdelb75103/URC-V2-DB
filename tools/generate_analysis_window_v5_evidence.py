#!/usr/bin/env python3
"""Generate safe, deterministic row-level evidence for the 2024-25 v5 window.

This tool performs no database access. It consumes either the accepted local
injury inclusion artefacts or a deliberately non-sensitive CSV export from the
row-level v5 exposure cohort view. Output replaces stable source identifiers
and free-text semantic evidence with deterministic SHA-256 evidence keys.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from collections.abc import Iterable
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
COHORT_VIEW_VERSION = "analysis_window_2024-25_2026-07-25_v1"
EVIDENCE_VERSION = "analysis_window_2024-25_v5"
EVIDENCE_REF = "ANALYSIS-WINDOW-01"
WINDOW_START = date(2024, 9, 1)

DEFAULT_INJURY_INPUT = ROOT / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.csv"
DEFAULT_INJURY_MANIFEST = ROOT / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.manifest.json"
DEFAULT_INJURY_OUTPUT = ROOT / "docs/evidence/analysis_window_2024-25_v5_injury_cohort_audit.csv"
DEFAULT_EXPOSURE_OUTPUT = ROOT / "docs/evidence/analysis_window_2024-25_v5_exposure_cohort_evidence.csv"
DEFAULT_EXPOSURE_SCHEMA = (
    ROOT
    / "docs/evidence/analysis_window_2024-25_v5_exposure_cohort_evidence.schema.json"
)
HOUR_PRECISION = Decimal("0.000001")
ACCEPTED_INJURY_CSV_SHA256 = (
    "e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb"
)
ACCEPTED_INJURY_MAPPING_SHA256 = (
    "9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f"
)

INJURY_FIELDS = [
    "source_row_evidence_key",
    "team",
    "injury_date",
    "effective_v5_cohort_status",
    "effective_v5_cohort_reason",
    "time_loss_by_positive_days",
    "days_lost",
    "cohort_view_version",
    "evidence_ref",
]

EXPOSURE_INPUT_FIELDS = {
    "stable_source_row_id",
    "curated_build_id",
    "approved_member_build",
    "team",
    "reporting_grain",
    "period_start",
    "period_end",
    "historical_eligibility_status",
    "historical_exclusion_reasons",
    "effective_v5_eligibility_status",
    "effective_v5_exclusion_reasons",
    "outside_official_analysis_window_removed",
    "pre_urc_match_rule_rejected",
    "pre_urc_match_evidence_class",
    "pre_urc_match_evidence_value",
    "exposure_hours",
    "rule_basis_code",
}

EXPOSURE_FIELDS = [
    "source_row_evidence_key",
    "curated_build_evidence_key",
    "team",
    "reporting_grain",
    "period_start",
    "period_end",
    "historical_eligibility_status",
    "historical_exclusion_reasons",
    "effective_v5_eligibility_status",
    "effective_v5_exclusion_reasons",
    "outside_official_analysis_window_removed",
    "pre_urc_match_rule_rejected",
    "pre_urc_match_evidence_class",
    "pre_urc_match_evidence_sha256",
    "exposure_hours",
    "cohort_view_version",
    "rule_basis_code",
]

ALLOWED_EVIDENCE_CLASSES = {
    "",
    "explicit_match",
    "explicit_friendly",
    "explicit_opponent_fixture",
    "semantic_non_urc_match",
    "verified_currie_cup_match",
}


class EvidenceError(ValueError):
    """Raised when an input cannot support the committed evidence contract."""


def evidence_key(kind: str, stable_identifier: str) -> str:
    if not stable_identifier:
        raise EvidenceError(f"{kind} evidence requires a stable source-row identifier")
    payload = f"{EVIDENCE_VERSION}|{kind}|{stable_identifier}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def parse_injury_date(value: str) -> date:
    try:
        return datetime.strptime(value.strip(), "%d/%m/%Y").date()
    except (InvalidOperation, ValueError) as error:
        raise EvidenceError(f"invalid Date Injured value {value!r}") from error


def positive_days(value: str) -> int:
    if not value.strip():
        return 0
    try:
        parsed = Decimal(value.strip())
    except (InvalidOperation, ValueError) as error:
        raise EvidenceError(f"invalid Days Injured value {value!r}") from error
    if parsed != parsed.to_integral_value():
        raise EvidenceError(f"Days Injured must be an integer, received {value!r}")
    return int(parsed)


def write_csv(path: Path, fields: list[str], rows: Iterable[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def generate_injury_audit(
    injury_input: Path,
    injury_manifest: Path,
    output: Path,
) -> dict[str, int]:
    actual_csv_sha256 = hashlib.sha256(injury_input.read_bytes()).hexdigest()
    with injury_input.open(encoding="utf-8-sig", newline="") as handle:
        injuries = list(csv.DictReader(handle))
    manifest = json.loads(injury_manifest.read_text(encoding="utf-8"))
    source_rows = manifest["selection"]["included_source_rows"]
    manifest_csv_sha256 = manifest["output"]["csv_sha256"]
    manifest_expected_csv_sha256 = manifest["output"]["expected_csv_sha256"]
    manifest_mapping_sha256 = manifest["selection"]["included_source_rows_sha256"]
    actual_mapping_sha256 = hashlib.sha256(
        ("\n".join(str(row) for row in source_rows) + "\n").encode("utf-8")
    ).hexdigest()
    if {
        actual_csv_sha256,
        manifest_csv_sha256,
        manifest_expected_csv_sha256,
    } != {ACCEPTED_INJURY_CSV_SHA256}:
        raise EvidenceError(
            "injury audit input does not match the accepted inclusion CSV fingerprint"
        )
    if (
        actual_mapping_sha256 != ACCEPTED_INJURY_MAPPING_SHA256
        or manifest_mapping_sha256 != ACCEPTED_INJURY_MAPPING_SHA256
    ):
        raise EvidenceError(
            "injury audit source-row mapping does not match the accepted fingerprint"
        )
    if len(injuries) != len(source_rows):
        raise EvidenceError(
            "injury CSV and included-source-row mapping cardinalities differ: "
            f"{len(injuries)} != {len(source_rows)}"
        )

    audit_rows: list[dict[str, str]] = []
    for injury, source_row in zip(injuries, source_rows):
        if injury.get("Problem type", "").strip().casefold() != "injury":
            continue
        injury_date_value = injury.get("Date Injured", "").strip()
        if not injury_date_value:
            continue
        injury_date = parse_injury_date(injury_date_value)
        if injury_date >= WINDOW_START:
            continue
        days_lost = positive_days(injury.get("Days Injured", ""))
        audit_rows.append(
            {
                "source_row_evidence_key": evidence_key("injury", str(source_row)),
                "team": injury.get("Team", "").strip(),
                "injury_date": injury_date.isoformat(),
                "effective_v5_cohort_status": "excluded_from_v5_analysis_window",
                "effective_v5_cohort_reason": "dated_before_2024-09-01",
                "time_loss_by_positive_days": str(days_lost > 0).lower(),
                "days_lost": str(days_lost),
                "cohort_view_version": COHORT_VIEW_VERSION,
                "evidence_ref": EVIDENCE_REF,
            }
        )

    audit_rows.sort(key=lambda row: (row["injury_date"], row["team"], row["source_row_evidence_key"]))
    write_csv(output, INJURY_FIELDS, audit_rows)
    return {
        "rows": len(audit_rows),
        "time_loss_rows": sum(row["time_loss_by_positive_days"] == "true" for row in audit_rows),
        "days_lost": sum(int(row["days_lost"]) for row in audit_rows),
    }


def parse_flag(value: str, field: str) -> bool:
    normalised = value.strip().casefold()
    if normalised in {"true", "t", "1", "yes"}:
        return True
    if normalised in {"false", "f", "0", "no", ""}:
        return False
    raise EvidenceError(f"{field} must be a boolean, received {value!r}")


def reason_tokens(value: str) -> set[str]:
    normalised = value.strip().strip("{}[]")
    if not normalised:
        return set()
    return {
        token.strip().strip('"')
        for token in normalised.replace(";", ",").replace("|", ",").split(",")
        if token.strip()
    }


def decimal_text(value: str, field: str) -> str:
    try:
        parsed = Decimal(value.strip())
    except (InvalidOperation, ValueError) as error:
        raise EvidenceError(f"{field} must be numeric, received {value!r}") from error
    if parsed < 0:
        raise EvidenceError(f"{field} must not be negative, received {value!r}")
    return format(parsed, "f")


def load_exposure_rows(
    exposure_input: Path | None, input_json: str | None
) -> list[dict[str, str]]:
    if input_json is not None:
        if input_json != "-":
            raise EvidenceError("--input-json accepts only '-' for standard input")
        payload = json.load(sys.stdin)
        if not isinstance(payload, list) or any(not isinstance(row, dict) for row in payload):
            raise EvidenceError("--input-json must receive a JSON array of row objects")
        rows: list[dict[str, Any]] = payload
    else:
        if exposure_input is None:
            raise EvidenceError("one exposure input is required")
        with exposure_input.open(encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))

    input_fields = set().union(*(row.keys() for row in rows)) if rows else set()
    missing = sorted(EXPOSURE_INPUT_FIELDS - input_fields)
    if missing:
        raise EvidenceError("exposure input is missing required fields: " + ", ".join(missing))
    return [
        {
            field: (
                ""
                if value is None
                else ";".join(str(item) for item in value)
                if isinstance(value, list)
                else str(value)
            )
            for field, value in row.items()
        }
        for row in rows
    ]


def generate_exposure_evidence(
    candidate_rows: list[dict[str, str]],
    output: Path,
    expected_rejected_rows: int,
    expected_rejected_hours: Decimal,
    expected_team_rejections: dict[str, dict[str, Decimal | int]],
) -> dict[str, Decimal | int]:
    evidence_rows: list[dict[str, str]] = []
    rejected_hours = Decimal("0")
    rejected_rows = 0
    rejected_by_team: dict[str, dict[str, Decimal | int]] = {}
    seen_source_rows: set[str] = set()
    builds_by_team: dict[str, set[str]] = {}
    for row in candidate_rows:
        stable_source_row_id = row["stable_source_row_id"].strip()
        if stable_source_row_id in seen_source_rows:
            raise EvidenceError(
                f"duplicate stable source-row identifier {stable_source_row_id!r}"
            )
        seen_source_rows.add(stable_source_row_id)
        approved_member_build = parse_flag(
            row["approved_member_build"], "approved_member_build"
        )
        if not approved_member_build:
            raise EvidenceError("exposure evidence contains a superseded or unapproved build")
        team = row["team"].strip()
        team_contract_key = team.casefold()
        curated_build_id = row["curated_build_id"].strip()
        if not team or not curated_build_id:
            raise EvidenceError("exposure evidence requires team and curated_build_id")
        builds_by_team.setdefault(team, set()).add(curated_build_id)
        if len(builds_by_team[team]) != 1:
            raise EvidenceError(f"exposure evidence contains multiple builds for {team}")
        outside_removed = parse_flag(
            row["outside_official_analysis_window_removed"],
            "outside_official_analysis_window_removed",
        )
        pre_urc_rejected = parse_flag(
            row["pre_urc_match_rule_rejected"], "pre_urc_match_rule_rejected"
        )
        if not outside_removed and not pre_urc_rejected:
            continue
        historical_reasons = reason_tokens(row["historical_exclusion_reasons"])
        if outside_removed and historical_reasons != {"outside_official_analysis_window"}:
            raise EvidenceError(
                "outside_official_analysis_window can be removed only when it is the "
                "sole historical exclusion reason"
            )
        evidence_class = row["pre_urc_match_evidence_class"].strip()
        if evidence_class not in ALLOWED_EVIDENCE_CLASSES:
            raise EvidenceError(f"unrecognised semantic evidence class {evidence_class!r}")
        if pre_urc_rejected and not evidence_class:
            raise EvidenceError("a pre-URC match rejection requires an evidence class")
        if not pre_urc_rejected and evidence_class:
            raise EvidenceError("semantic evidence class is set for a non-rejected row")
        hours = Decimal(decimal_text(row["exposure_hours"], "exposure_hours"))
        if pre_urc_rejected:
            rejected_rows += 1
            rejected_hours += hours
            team_summary = rejected_by_team.setdefault(
                team_contract_key, {"rows": 0, "hours": Decimal("0")}
            )
            team_summary["rows"] = int(team_summary["rows"]) + 1
            team_summary["hours"] = Decimal(team_summary["hours"]) + hours
        evidence_rows.append(
            {
                "source_row_evidence_key": evidence_key("exposure", stable_source_row_id),
                "curated_build_evidence_key": evidence_key(
                    "curated_build", curated_build_id
                ),
                "team": team,
                "reporting_grain": row["reporting_grain"].strip(),
                "period_start": row["period_start"].strip(),
                "period_end": row["period_end"].strip(),
                "historical_eligibility_status": row["historical_eligibility_status"].strip(),
                "historical_exclusion_reasons": ";".join(sorted(historical_reasons)),
                "effective_v5_eligibility_status": row["effective_v5_eligibility_status"].strip(),
                "effective_v5_exclusion_reasons": ";".join(
                    sorted(reason_tokens(row["effective_v5_exclusion_reasons"]))
                ),
                "outside_official_analysis_window_removed": str(outside_removed).lower(),
                "pre_urc_match_rule_rejected": str(pre_urc_rejected).lower(),
                "pre_urc_match_evidence_class": evidence_class,
                "pre_urc_match_evidence_sha256": evidence_key(
                    "pre_urc_match_evidence", row["pre_urc_match_evidence_value"].strip()
                )
                if evidence_class
                else "",
                "exposure_hours": decimal_text(row["exposure_hours"], "exposure_hours"),
                "cohort_view_version": COHORT_VIEW_VERSION,
                "rule_basis_code": row["rule_basis_code"].strip(),
            }
        )

    rejected_hours_rounded = rejected_hours.quantize(HOUR_PRECISION)
    expected_rejected_hours_rounded = expected_rejected_hours.quantize(HOUR_PRECISION)
    normalised_team_actual = {
        team: {
            "rows": int(summary["rows"]),
            "hours": Decimal(summary["hours"]).quantize(HOUR_PRECISION),
        }
        for team, summary in rejected_by_team.items()
    }
    normalised_team_expected = {
        team.casefold(): {
            "rows": int(summary["rows"]),
            "hours": Decimal(summary["hours"]).quantize(HOUR_PRECISION),
        }
        for team, summary in expected_team_rejections.items()
    }
    if (
        rejected_rows != expected_rejected_rows
        or rejected_hours_rounded != expected_rejected_hours_rounded
        or normalised_team_actual != normalised_team_expected
    ):
        raise EvidenceError(
            "pre-URC rejection reconciliation failed: "
            f"rows={rejected_rows} expected={expected_rejected_rows}; "
            f"hours={rejected_hours_rounded} expected={expected_rejected_hours_rounded}; "
            f"by_team={normalised_team_actual} expected_by_team={normalised_team_expected}"
        )
    evidence_rows.sort(
        key=lambda row: (
            row["period_start"],
            row["team"],
            row["source_row_evidence_key"],
        )
    )
    write_csv(output, EXPOSURE_FIELDS, evidence_rows)
    return {
        "rows": len(evidence_rows),
        "pre_urc_rejected_rows": rejected_rows,
        "pre_urc_rejected_hours": rejected_hours_rounded,
    }


def expected_team_rejections_from_schema(
    schema_path: Path,
) -> dict[str, dict[str, Decimal | int]]:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    raw = schema["required_reconciliation"]["rejected_rows_by_team"]
    return {
        team: {
            "rows": int(summary["rows"]),
            "hours": Decimal(str(summary["hours"])),
        }
        for team, summary in raw.items()
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate safe v5 analysis-window evidence from local artefacts or a view export"
    )
    subcommands = parser.add_subparsers(dest="command", required=True)

    injury = subcommands.add_parser("injury-audit")
    injury.add_argument("--injury-input", type=Path, default=DEFAULT_INJURY_INPUT)
    injury.add_argument("--injury-manifest", type=Path, default=DEFAULT_INJURY_MANIFEST)
    injury.add_argument("--output", type=Path, default=DEFAULT_INJURY_OUTPUT)

    exposure = subcommands.add_parser("exposure-evidence")
    exposure_input = exposure.add_mutually_exclusive_group(required=True)
    exposure_input.add_argument(
        "--input",
        type=Path,
        help="non-sensitive CSV export from analysis_window_effective_exposure_cohort_v5",
    )
    exposure_input.add_argument(
        "--input-json",
        help="use '-' to read a JSON array directly from standard input without writing a raw export",
    )
    exposure.add_argument("--output", type=Path, default=DEFAULT_EXPOSURE_OUTPUT)
    exposure.add_argument("--expected-rejected-rows", type=int, default=815)
    exposure.add_argument("--expected-rejected-hours", type=Decimal, default=Decimal("865.830000"))
    exposure.add_argument(
        "--evidence-schema",
        type=Path,
        default=DEFAULT_EXPOSURE_SCHEMA,
        help="schema containing the accepted per-team rejection reconciliation",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "injury-audit":
        summary = generate_injury_audit(
            args.injury_input, args.injury_manifest, args.output
        )
    else:
        candidate_rows = load_exposure_rows(args.input, args.input_json)
        summary = generate_exposure_evidence(
            candidate_rows,
            args.output,
            args.expected_rejected_rows,
            args.expected_rejected_hours,
            expected_team_rejections_from_schema(args.evidence_schema),
        )
    print(json.dumps(summary, sort_keys=True, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
