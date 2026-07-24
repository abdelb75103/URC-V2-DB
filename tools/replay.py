#!/usr/bin/env python3
"""Replay the canonical 2024-25 decision ledger from the v5 master."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import sys
from collections import Counter
from datetime import date, datetime
from pathlib import Path
from types import SimpleNamespace
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = ROOT / "data/2024-25/master/master_2024-25_v5.json"
DEFAULT_LEDGER = ROOT / "data/2024-25/decisions/ledger.json"
DEFAULT_OUTPUT = (
    ROOT / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.csv"
)
DEFAULT_MANIFEST = (
    ROOT / "data/2024-25/inclusion/"
    "urc_injury_included_dataset_2024-25.manifest.json"
)
DEFAULT_METHODOLOGY = ROOT / "docs/METHODOLOGY.md"
DELETED_EVIDENCE_MANIFEST = (
    ROOT / "docs/evidence/phase5_deleted_ledger_evidence_2026-07-24.json"
)
REFERENCE_OUTPUT = (
    ROOT / "outputs/urc_final_human_review_2024-25/"
    "urc_injury_included_dataset_2024-25.csv"
)
EXPECTED_OUTPUT_SHA256 = (
    "e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb"
)
EXPECTED_MAPPING_SHA256 = (
    "9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f"
)
SEASON_START = date(2024, 7, 1)
SEASON_END = date(2025, 6, 30)
CONTROLLED_FIELDS = (
    "TimeLoss vs Medical Attention",
    "Problem type",
    "Occasion category",
)
DATE_FIELDS = ("Date Injured", "Confirmed Return Date")


def _load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


EXPORT = _load_module(
    "export_included_injury_dataset",
    ROOT / "tools/export_included_injury_dataset.py",
)
RENDER = _load_module("render_master_workbook", ROOT / "tools/render.py")


class ReplayError(ValueError):
    """Raised when a replay input violates the canonical contract."""


def sha256_file(path: Path) -> str:
    return EXPORT.sha256_file(path)


def mapping_sha256(source_rows: list[int]) -> str:
    payload = ("\n".join(str(row) for row in source_rows) + "\n").encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def serialize_master_value(value: Any) -> str | int | float:
    decoded = RENDER.decode_value(value)
    cell = SimpleNamespace(value=decoded, data_type="s", coordinate="A1")
    return EXPORT.serialize_value(cell)


def comparison_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def load_master_table(payload: dict[str, Any]) -> tuple[list[str], dict[int, list[Any]]]:
    sheets = [
        sheet for sheet in payload.get("sheets", [])
        if sheet.get("name") == EXPORT.SOURCE_SHEET
    ]
    if len(sheets) != 1:
        raise ReplayError("Expected exactly one Injury Master sheet")
    values = sheets[0].get("values")
    if not isinstance(values, list) or not values:
        raise ReplayError("Injury Master has no values")
    headers = [comparison_value(value).strip() for value in values[0]]
    if len(headers) != 28 or len(headers) != len(set(headers)):
        raise ReplayError("Injury Master must have 28 unique headers")
    if headers.count(EXPORT.EXCLUSION_HEADER) != 1:
        raise ReplayError("Injury Master must have one Exclusion Reason column")
    rows: dict[int, list[Any]] = {}
    for source_row, raw_row in enumerate(values[1:], start=2):
        if len(raw_row) > len(headers):
            raise ReplayError(f"Source row {source_row} exceeds the header width")
        padded = list(raw_row) + [None] * (len(headers) - len(raw_row))
        rows[source_row] = [
            serialize_master_value(value) for value in padded
        ]
    return headers, rows


def select_inclusion(
    headers: list[str], master_rows: dict[int, list[Any]]
) -> tuple[dict[int, list[Any]], list[int]]:
    exclusion_index = headers.index(EXPORT.EXCLUSION_HEADER)
    selected: dict[int, list[Any]] = {}
    source_rows: list[int] = []
    for source_row, row in master_rows.items():
        if EXPORT.is_blank(row[exclusion_index]):
            selected[source_row] = list(row)
            source_rows.append(source_row)
    return selected, source_rows


def load_deleted_evidence(manifest_path: Path) -> set[tuple[str, str]]:
    """Return the (path, sha256) pairs recorded as deleted in Phase 5."""
    if not manifest_path.exists():
        return set()
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    return {
        (entry["path"], entry["sha256"]) for entry in payload.get("entries", [])
    }


def verify_ledger_evidence(
    ledger: dict[str, Any],
    deleted_evidence_manifest: Path = DELETED_EVIDENCE_MANIFEST,
) -> None:
    """Verify every hashed evidence reference before replaying.

    Evidence entries marked "mutable": true (living documents such as the
    rule changelog) are exempt from byte verification by recorded design;
    everything else with a sha256 must match the file on disk.

    A file removed by the Phase 5 deletion manifest is exempt only while it
    is absent and the deleted-evidence manifest records that exact path with
    that exact sha256; the ledger keeps the path and hash as the historical
    record, and any other missing file still fails.
    """
    deleted = load_deleted_evidence(deleted_evidence_manifest)
    problems = []
    for step in ledger.get("steps", []):
        for evidence in step.get("evidence", []):
            path = evidence.get("path")
            expected = evidence.get("sha256")
            if not path or not expected or evidence.get("mutable"):
                continue
            target = Path(path)
            if not target.exists():
                if (path, expected) in deleted:
                    continue
                problems.append(f"{step['rule_version']}: missing {path}")
                continue
            actual = sha256_file(target)
            if actual != expected:
                problems.append(
                    f"{step['rule_version']}: {path} sha256 {actual} != {expected}"
                )
    if problems:
        raise ReplayError(
            "Ledger evidence verification failed:\n  " + "\n  ".join(problems)
        )


def _is_removal(entry: dict[str, Any]) -> bool:
    return (
        entry.get("action") == "removed_from_inclusion_csv"
        or (
            entry.get("field") == "Inclusion Status"
            and entry.get("new_value") == "Excluded from included CSV"
        )
    )


def apply_ledger(
    headers: list[str],
    selected_rows: dict[int, list[Any]],
    ordered_source_rows: list[int],
    ledger: dict[str, Any],
    master_rows: dict[int, list[Any]] | None = None,
) -> tuple[list[list[Any]], list[int], list[dict[str, Any]], list[dict[str, Any]]]:
    rows = {source_row: list(row) for source_row, row in selected_rows.items()}
    header_indexes = {header: index for index, header in enumerate(headers)}
    master_rows = master_rows if master_rows is not None else {}
    summaries: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []

    steps = ledger.get("steps")
    if not isinstance(steps, list):
        raise ReplayError("Ledger steps must be a list")
    orders = [step.get("order") for step in steps]
    if orders != sorted(orders) or len(orders) != len(set(orders)):
        raise ReplayError("Ledger step order must be unique and ascending")

    for step in steps:
        counts: Counter[str] = Counter()
        for entry in step.get("entries", []):
            source_row = int(entry["source_workbook_row"])
            if _is_removal(entry):
                if source_row in rows:
                    del rows[source_row]
                    counts["applied"] += 1
                elif source_row in master_rows:
                    counts["materialized_in_master"] += 1
                else:
                    conflicts.append(
                        {
                            "rule_version": step["rule_version"],
                            "source_workbook_row": source_row,
                            "field": entry.get("field"),
                            "reason": "source_row_missing_from_master",
                        }
                    )
                    counts["conflict"] += 1
                continue

            if source_row not in rows:
                # A value entry can target a row the master now excludes
                # (for example a later exclusion superseded the edit). That
                # is not the same as the edit being materialized: classify
                # it separately and treat a row missing from the master
                # entirely as a conflict.
                if source_row in master_rows:
                    counts["row_excluded_from_selection"] += 1
                else:
                    conflicts.append(
                        {
                            "rule_version": step["rule_version"],
                            "source_workbook_row": source_row,
                            "field": entry.get("field"),
                            "reason": "source_row_missing_from_master",
                        }
                    )
                    counts["conflict"] += 1
                continue

            field = entry["field"]
            if field not in header_indexes:
                conflict = {
                    "rule_version": step["rule_version"],
                    "source_workbook_row": source_row,
                    "field": field,
                    "old_value": entry.get("old_value"),
                    "new_value": entry.get("new_value"),
                    "current_value": None,
                    "reason": "field_missing_from_master",
                }
                conflicts.append(conflict)
                counts["conflict"] += 1
                continue

            row = rows[source_row]
            team = comparison_value(row[header_indexes["Team"]])
            player_id = comparison_value(row[header_indexes["PlayerID"]])
            if team != comparison_value(entry.get("team")) or player_id != comparison_value(
                entry.get("player_id")
            ):
                conflict = {
                    "rule_version": step["rule_version"],
                    "source_workbook_row": source_row,
                    "field": field,
                    "old_value": entry.get("old_value"),
                    "new_value": entry.get("new_value"),
                    "current_value": comparison_value(row[header_indexes[field]]),
                    "reason": "row_identity_mismatch",
                    "expected_team": entry.get("team"),
                    "current_team": team,
                    "expected_player_id": entry.get("player_id"),
                    "current_player_id": player_id,
                }
                conflicts.append(conflict)
                counts["conflict"] += 1
                continue

            field_index = header_indexes[field]
            current = comparison_value(row[field_index])
            old_value = comparison_value(entry.get("old_value"))
            new_value = comparison_value(entry.get("new_value"))
            if current == old_value:
                row[field_index] = new_value
                counts["applied"] += 1
            elif current == new_value:
                counts["materialized_in_master"] += 1
            else:
                conflict = {
                    "rule_version": step["rule_version"],
                    "source_workbook_row": source_row,
                    "field": field,
                    "old_value": old_value,
                    "new_value": new_value,
                    "current_value": current,
                    "reason": "old_value_guard_failed",
                }
                conflicts.append(conflict)
                counts["conflict"] += 1

        summaries.append(
            {
                "order": step["order"],
                "rule_version": step["rule_version"],
                "entries": len(step.get("entries", [])),
                "applied": counts["applied"],
                "materialized_in_master": counts["materialized_in_master"],
                "row_excluded_from_selection": counts[
                    "row_excluded_from_selection"
                ],
                "conflict": counts["conflict"],
            }
        )

    retained_source_rows = [
        source_row for source_row in ordered_source_rows if source_row in rows
    ]
    retained_rows = [rows[source_row] for source_row in retained_source_rows]
    return retained_rows, retained_source_rows, summaries, conflicts


def _parse_date(value: Any) -> date | None:
    text = comparison_value(value).strip()
    if not text:
        return None
    for pattern in ("%d/%m/%Y", "%d/%m/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, pattern).date()
        except ValueError:
            pass
    return None


def category_baseline(
    headers: list[str], master_rows: dict[int, list[Any]]
) -> dict[str, set[str]]:
    indexes = {header: headers.index(header) for header in CONTROLLED_FIELDS}
    return {
        field: {
            comparison_value(row[index]).strip()
            for row in master_rows.values()
            if comparison_value(row[index]).strip()
        }
        for field, index in indexes.items()
    }


def generate_flags(
    headers: list[str],
    rows: list[list[Any]],
    source_rows: list[int],
    allowed_categories: dict[str, set[str]],
) -> list[dict[str, Any]]:
    indexes = {header: headers.index(header) for header in headers}
    flags: list[dict[str, Any]] = []
    for row, source_row in zip(rows, source_rows, strict=True):
        parsed_dates: dict[str, date | None] = {}
        for field in DATE_FIELDS:
            value = row[indexes[field]]
            parsed = _parse_date(value)
            parsed_dates[field] = parsed
            if parsed is not None and not SEASON_START <= parsed <= SEASON_END:
                flags.append(
                    {
                        "source_workbook_row": source_row,
                        "field": field,
                        "value": comparison_value(value),
                        "flag": "date_outside_season_window",
                    }
                )

        injury_date = parsed_dates["Date Injured"]
        return_date = parsed_dates["Confirmed Return Date"]
        if injury_date is not None and return_date is not None and return_date < injury_date:
            flags.append(
                {
                    "source_workbook_row": source_row,
                    "field": "Confirmed Return Date",
                    "value": comparison_value(row[indexes["Confirmed Return Date"]]),
                    "flag": "return_date_precedes_injury_date",
                }
            )

        days_value = comparison_value(row[indexes["Days Injured"]]).strip()
        if days_value:
            try:
                parsed_days = float(days_value)
            except ValueError:
                parsed_days = None
            if (
                parsed_days is None
                or not parsed_days.is_integer()
                or parsed_days < 0
            ):
                flags.append(
                    {
                        "source_workbook_row": source_row,
                        "field": "Days Injured",
                        "value": days_value,
                        "flag": "negative_or_non_integer_days_injured",
                    }
                )

        for field in CONTROLLED_FIELDS:
            value = comparison_value(row[indexes[field]]).strip()
            if value and value not in allowed_categories.get(field, set()):
                flags.append(
                    {
                        "source_workbook_row": source_row,
                        "field": field,
                        "value": value,
                        "flag": "category_outside_master_values",
                    }
                )

        fit_date = _parse_date(row[indexes["Fit For Selection Date"]])
        if injury_date is not None and fit_date is not None and fit_date < injury_date:
            flags.append(
                {
                    "source_workbook_row": source_row,
                    "field": "Fit For Selection Date",
                    "value": comparison_value(row[indexes["Fit For Selection Date"]]),
                    "flag": "fit_date_precedes_injury_date",
                }
            )
    return flags


def _relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def diff_csv(reference: Path, candidate: Path) -> list[dict[str, Any]]:
    if not reference.exists():
        return [{"reason": "reference_missing", "path": str(reference)}]
    with reference.open(encoding="utf-8", newline="") as handle:
        expected = list(csv.reader(handle))
    with candidate.open(encoding="utf-8", newline="") as handle:
        actual = list(csv.reader(handle))
    differences: list[dict[str, Any]] = []
    maximum = max(len(expected), len(actual))
    for index in range(maximum):
        expected_row = expected[index] if index < len(expected) else None
        actual_row = actual[index] if index < len(actual) else None
        if expected_row != actual_row:
            differences.append(
                {
                    "csv_row": index + 1,
                    "expected": expected_row,
                    "actual": actual_row,
                }
            )
    return differences


def _source_to_master_section() -> list[str]:
    """Generate the dirty-source-to-master story from the per-team
    Standardization Records (documented, not re-executed, for 2024-25)."""
    records_dir = Path("data/2024-25/intake/standardization_records")
    record_paths = sorted(records_dir.glob("*.json"))
    lines = [
        "## Source to master: per-team standardization (documented, not re-executed)",
        "",
        "For 2024-25 the dirty-source-to-master leg is evidenced by one",
        "consolidated Standardization Record per team under",
        "`data/2024-25/intake/standardization_records/` (source checksums,",
        "steps applied, pseudonymisation notes, row reconciliation, and",
        "explicit gaps). The go-forward scripted path for later seasons is",
        "`tools/intake.py`.",
        "",
    ]
    if not record_paths:
        lines.extend(
            [
                "Standardization Records were not available when this document",
                "was generated; regenerate after restoring them.",
                "",
            ]
        )
        return lines
    lines.extend(
        [
            "| Team | Master rows | Included | Excluded | Sources | Steps | Gaps |",
            "|---|---:|---:|---:|---:|---:|---:|",
        ]
    )
    total_gaps = 0
    for record_path in record_paths:
        record = json.loads(record_path.read_text(encoding="utf-8"))
        reconciliation = record.get("row_reconciliation", {})
        gaps = record.get("gaps", [])
        total_gaps += len(gaps)
        lines.append(
            f"| {record.get('team')} "
            f"| {reconciliation.get('master_source_rows')} "
            f"| {reconciliation.get('included_rows')} "
            f"| {reconciliation.get('excluded_rows')} "
            f"| {len(record.get('source_files', []))} "
            f"| {len(record.get('steps_applied', []))} "
            f"| {len(gaps)} |"
        )
    lines.extend(
        [
            "",
            f"Recorded evidence gaps across teams: {total_gaps}. Each gap is",
            "stated verbatim in its team record; gaps are never silently",
            "filled. Where historical master-stage counts disagree with the",
            "current manifest, both numbers are preserved in the record.",
            "",
        ]
    )
    return lines


def write_methodology(ledger: dict[str, Any], path: Path) -> None:
    lines = [
        "# URC 2024-25 Inclusion Methodology",
        "",
        "> Generated by `tools/replay.py --write-methodology`. Do not edit by hand.",
        "",
        "## Three-layer contract",
        "",
        "1. **Master:** Preserves every standardized source row and records row-level exclusions. It does not store inclusion-only inference.",
        "2. **Decision ledger:** Applies ordered, evidence-bound corrections, standardizations, inferences, adjudications, and inclusion removals.",
        "3. **Inclusion:** Contains only master rows with a blank exclusion reason after the ordered ledger is replayed. Analysis consumes this layer.",
        "",
    ]
    lines.extend(_source_to_master_section())
    for step in ledger["steps"]:
        counts = Counter(entry["field"] for entry in step.get("entries", []))
        lines.extend(
            [
                f"## {step['order']}. {step['rule_version']}",
                "",
                f"- Applied at: {step['applied_at']}",
                f"- Carry-forward: {step['carry_forward']}",
                f"- Entries: {len(step.get('entries', []))}",
                "",
                step["description"],
                "",
                "### Entry counts by field",
                "",
            ]
        )
        if counts:
            lines.extend(f"- {field}: {count}" for field, count in sorted(counts.items()))
        else:
            lines.append("- None. This step records metadata only.")
        lines.append("")

    lines.extend(["## Open items", ""])
    for item in ledger.get("open_items", []):
        lines.append(
            f"- Source workbook row {item['source_workbook_row']}: {item['description']}"
        )
    if not ledger.get("open_items"):
        lines.append("- None.")
    lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def replay(
    baseline_path: Path,
    ledger_path: Path,
    output_path: Path,
    manifest_path: Path,
) -> dict[str, Any]:
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    expected_baseline_hash = ledger["baseline"]["master_v5_json"]["sha256"]
    actual_baseline_hash = sha256_file(baseline_path)
    if actual_baseline_hash != expected_baseline_hash:
        raise ReplayError(
            f"Baseline hash mismatch: {actual_baseline_hash} != {expected_baseline_hash}"
        )

    headers, master_rows = load_master_table(baseline)
    verify_ledger_evidence(ledger)
    record_path = Path(ledger["baseline"]["record"])
    if record_path.exists():
        actual_record_hash = sha256_file(record_path)
        if actual_record_hash != ledger["baseline"]["record_sha256"]:
            raise ReplayError(
                "baseline_record.json hash mismatch: "
                f"{actual_record_hash} != {ledger['baseline']['record_sha256']}"
            )
    else:
        raise ReplayError(f"Baseline record does not exist: {record_path}")
    selected, ordered_source_rows = select_inclusion(headers, master_rows)
    rows, source_rows, summaries, conflicts = apply_ledger(
        headers, selected, ordered_source_rows, ledger, master_rows
    )
    # Write a candidate first; the canonical output is promoted only after
    # the conflict check passes, so a failing replay never clobbers the
    # previous accepted CSV.
    candidate_path = output_path.with_suffix(output_path.suffix + ".candidate")
    EXPORT.write_csv_atomic(candidate_path, headers, rows)
    if not ledger.get("serialization", {}).get("trailing_newline", True):
        raw = candidate_path.read_bytes()
        if raw.endswith(b"\n"):
            candidate_path.write_bytes(raw[:-1])
    if conflicts:
        candidate_hash = sha256_file(candidate_path)
        print(
            f"CONFLICTS: {len(conflicts)}; canonical output NOT updated. "
            f"Candidate retained at {candidate_path} (sha256 {candidate_hash})"
        )
        for conflict in conflicts:
            print(f"  CONFLICT {json.dumps(conflict, sort_keys=True)}")
        raise ReplayError("Replay produced conflicts; canonical output not promoted")
    candidate_path.replace(output_path)
    output_hash = sha256_file(output_path)
    source_mapping_hash = mapping_sha256(source_rows)
    flags = generate_flags(
        headers, rows, source_rows, category_baseline(headers, master_rows)
    )
    ledger_hash = sha256_file(ledger_path)
    payload = {
        "artifact_type": "replayed_included_injury_dataset",
        "season": ledger["season"],
        "baseline": {
            "path": _relative(baseline_path),
            "sha256": actual_baseline_hash,
            "record": ledger["baseline"]["record"],
            "record_sha256": ledger["baseline"]["record_sha256"],
        },
        "ledger": {
            "path": _relative(ledger_path),
            "sha256": ledger_hash,
        },
        "replay_counts": summaries,
        "conflicts": conflicts,
        "selection": {
            "rule": "Exclusion Reason is blank after trimming whitespace",
            "included_rows": len(rows),
            "included_source_rows": source_rows,
            "included_source_rows_sha256": source_mapping_hash,
        },
        "output": {
            "csv": _relative(output_path),
            "csv_sha256": output_hash,
            "expected_csv_sha256": EXPECTED_OUTPUT_SHA256,
            "data_rows": len(rows),
            "columns": len(headers),
            "encoding": "UTF-8",
            "line_ending": "LF",
        },
        "flags": flags,
        "flag_counts": dict(sorted(Counter(flag["flag"] for flag in flags).items())),
        "generator": {
            "script": _relative(Path(__file__)),
            "script_sha256": sha256_file(Path(__file__)),
        },
    }
    EXPORT.write_json_atomic(manifest_path, payload)
    return payload


def print_summary(payload: dict[str, Any], output_path: Path) -> None:
    print("Replay summary")
    for step in payload["replay_counts"]:
        print(
            f"{step['order']:>2} {step['rule_version']}: "
            f"applied={step['applied']} "
            f"materialized_in_master={step['materialized_in_master']} "
            f"row_excluded_from_selection={step['row_excluded_from_selection']} "
            f"conflict={step['conflict']}"
        )
    print("Anomaly flags")
    for name, count in payload["flag_counts"].items():
        print(f"  {name}={count}")
    for flag in payload["flags"]:
        print(
            f"  FLAG source_row={flag['source_workbook_row']} "
            f"field={flag['field']} value={flag['value']!r} type={flag['flag']}"
        )
    print(
        f"Output SHA-256: {payload['output']['csv_sha256']} "
        f"expected {payload['output']['expected_csv_sha256']}"
    )
    print(
        "Retained source-row mapping SHA-256: "
        f"{payload['selection']['included_source_rows_sha256']} "
        f"expected {EXPECTED_MAPPING_SHA256}"
    )
    if payload["conflicts"]:
        print("Conflicts")
        for conflict in payload["conflicts"]:
            print(json.dumps(conflict, sort_keys=True))
    if payload["output"]["csv_sha256"] != EXPECTED_OUTPUT_SHA256:
        print("Row-by-row differences from the accepted CSV")
        for difference in diff_csv(REFERENCE_OUTPUT, output_path):
            print(json.dumps(difference, ensure_ascii=False, sort_keys=True))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay the canonical decision ledger from the v5 master"
    )
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--write-methodology", action="store_true")
    parser.add_argument("--methodology", type=Path, default=DEFAULT_METHODOLOGY)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = replay(args.baseline, args.ledger, args.output, args.manifest)
    ledger = json.loads(args.ledger.read_text(encoding="utf-8"))
    if args.write_methodology:
        write_methodology(ledger, args.methodology)
        print(f"Methodology written: {_relative(args.methodology)}")
    print_summary(payload, args.output)
    valid = (
        not payload["conflicts"]
        and payload["output"]["data_rows"] == 2301
        and payload["output"]["columns"] == 28
        and payload["output"]["csv_sha256"] == EXPECTED_OUTPUT_SHA256
        and payload["selection"]["included_source_rows_sha256"]
        == EXPECTED_MAPPING_SHA256
    )
    return 0 if valid else 1


if __name__ == "__main__":
    sys.exit(main())
