#!/usr/bin/env python3
"""Build offline SQL for the reviewed 2024-25 injury lineage."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
import uuid
from collections import Counter, defaultdict, deque
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Iterable, Sequence


ROOT = Path(__file__).resolve().parents[1]
SEASON = "2024-25"
OUTPUT_DIR = ROOT / "data/reporting/lineage_load"
MASTER_PATH = ROOT / "data/2024-25/master/master_2024-25_v5.json"
LEDGER_PATH = ROOT / "data/2024-25/decisions/ledger.json"
BASELINE_RECORD_PATH = ROOT / "data/2024-25/master/baseline_record.json"
INCLUSION_PATH = (
    ROOT / "data/2024-25/inclusion/urc_injury_included_dataset_2024-25.csv"
)
DUMP_PATH = OUTPUT_DIR / "member_build_source_rows_2024-25.json"
BRIDGE_REPORT_PATH = OUTPUT_DIR / "bridge_report_2024-25.json"
MANIFEST_PATH = OUTPUT_DIR / "load_manifest_2024-25.json"

EXPECTED_HASHES = {
    "master_json": "15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63",
    "ledger": "b92c35cdfc86acabfcc999be2c007e084495321c637d1866b0924ad2407a37fe",
    "baseline_record": "6cbb6d45d6dd181b9bda3a228cf4c86d509060a75f631818726a4748115e0217",
    "inclusion_csv": "e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb",
}
EXPECTED_MAPPING_SHA256 = (
    "9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f"
)
EXPECTED_MASTER_ROWS = 3060
EXPECTED_EXCLUDED_ROWS = 755
EXPECTED_RETAINED_ROWS = 2301
EXPECTED_LEDGER_STEPS = 10
BATCH_SIZE = 200
STEP_VERSION = "lineage_load_2026-07-24_v1"
UUID_NAMESPACE = uuid.UUID("e5fe3de7-8f20-5b0f-b02f-7e62d83f6638")

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
DATE_FIELDS = (
    "Date Injured",
    "Fit For Selection Date",
    "Confirmed Return Date",
)
EXACT_FIELDS = (
    "Body Part",
    "Orchard Code",
    "Illness Code",
    "Problem type",
    "Days Injured",
    "Description",
    "Nature of onset",
    "Recurrence",
    "Required Surgery",
)
MATCHING_FIELDS = ("PlayerID", *DATE_FIELDS, *EXACT_FIELDS)


def _load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


REPLAY = _load_module("lineage_replay", ROOT / "tools/replay.py")


class LineageLoadError(ValueError):
    """Raised when the offline load contract cannot be proven."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_date_candidates(value: Any) -> set[date]:
    text = REPLAY.comparison_value(value).strip()
    if not text:
        return set()
    candidates = set()
    for pattern in (
        "%d/%m/%Y",
        "%d/%m/%y",
        "%Y-%m-%d",
        "%m/%d/%y",
        "%m/%d/%Y",
    ):
        try:
            candidates.add(datetime.strptime(text, pattern).date())
        except ValueError:
            pass
    return candidates


def _blank(value: Any) -> bool:
    return not REPLAY.comparison_value(value).strip()


def _numeric_text(value: Any) -> Decimal | None:
    text = REPLAY.comparison_value(value).strip()
    if not text:
        return None
    try:
        return Decimal(text)
    except InvalidOperation:
        return None


def _dates_compatible(
    master_values: dict[str, str],
    source_values: dict[str, str],
) -> bool:
    for field in DATE_FIELDS:
        master_value = master_values.get(field, "")
        source_value = source_values.get(field, "")
        master_blank = _blank(master_value)
        source_blank = _blank(source_value)
        if master_blank != source_blank:
            return False
        if master_blank:
            continue
        master_dates = parse_date_candidates(master_value)
        source_dates = parse_date_candidates(source_value)
        if not master_dates or not source_dates or master_dates.isdisjoint(
            source_dates
        ):
            return False
    return True


def fields_compatible(
    master_values: dict[str, str],
    source_values: dict[str, str],
    *,
    check_dates: bool = True,
) -> bool:
    if master_values.get("PlayerID", "").strip() != source_values.get(
        "PlayerID", ""
    ).strip():
        return False
    for field in EXACT_FIELDS:
        master_value = master_values.get(field, "")
        source_value = source_values.get(field, "")
        if _blank(master_value) or _blank(source_value):
            continue
        if field == "Days Injured":
            master_number = _numeric_text(master_value)
            source_number = _numeric_text(source_value)
            if master_number is not None and source_number is not None:
                if master_number != source_number:
                    return False
                continue
        if master_value.strip() != source_value.strip():
            return False
    return not check_dates or _dates_compatible(master_values, source_values)


def identical_group_is_verified(source_rows: Sequence[dict[str, Any]]) -> bool:
    if not source_rows:
        return False
    projections = [
        tuple(row["source_values"].get(field, "") for field in MATCHING_FIELDS)
        for row in source_rows
    ]
    if any(projection != projections[0] for projection in projections[1:]):
        return False
    return True


def _field_match(field: str, master_value: Any, source_value: Any) -> bool:
    if field in DATE_FIELDS:
        master_blank = _blank(master_value)
        source_blank = _blank(source_value)
        if master_blank or source_blank:
            return master_blank and source_blank
        master_dates = parse_date_candidates(master_value)
        source_dates = parse_date_candidates(source_value)
        return bool(
            master_dates
            and source_dates
            and not master_dates.isdisjoint(source_dates)
        )
    if _blank(master_value) or _blank(source_value):
        return False
    if field == "Days Injured":
        master_number = _numeric_text(master_value)
        source_number = _numeric_text(source_value)
        if master_number is not None and source_number is not None:
            return master_number == source_number
    master_text = REPLAY.comparison_value(master_value).strip()
    source_text = REPLAY.comparison_value(source_value).strip()
    if master_text == source_text:
        return True
    if field == "Recurrence":
        recurrence_groups = (
            {"New injury", "New injury (non-recurring)", "first episode", "No"},
            {"Recurrence", "recurrence", "Yes"},
        )
        return any(
            master_text in group and source_text in group
            for group in recurrence_groups
        )
    return False


def sql_literal(value: str) -> str:
    if "\x00" in value:
        raise LineageLoadError("Postgres text literals cannot contain NUL")
    return "'" + value.replace("'", "''") + "'"


def sql_json(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True)
    return f"{sql_literal(payload)}::jsonb"


def sql_value(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return sql_literal(str(value))


def insert_batches(
    table: str,
    columns: Sequence[str],
    rows: Sequence[Sequence[str]],
) -> str:
    statements = []
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start : start + BATCH_SIZE]
        values = ",\n".join(f"  ({', '.join(row)})" for row in batch)
        statements.append(
            f"INSERT INTO {table} ({', '.join(columns)}) VALUES\n{values};"
        )
    return "\n\n".join(statements) + ("\n" if statements else "")


def _git_head() -> str:
    git_path = ROOT / ".git"
    if git_path.is_file():
        marker = git_path.read_text(encoding="utf-8").strip()
        if not marker.startswith("gitdir: "):
            raise LineageLoadError("Cannot resolve .git file")
        git_path = (ROOT / marker.removeprefix("gitdir: ")).resolve()
    head = (git_path / "HEAD").read_text(encoding="utf-8").strip()
    if not head.startswith("ref: "):
        return head
    reference = head.removeprefix("ref: ")
    loose_ref = git_path / reference
    if loose_ref.exists():
        return loose_ref.read_text(encoding="utf-8").strip()
    packed_refs = git_path / "packed-refs"
    if packed_refs.exists():
        for line in packed_refs.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith(("#", "^")):
                continue
            commit, name = line.split(" ", 1)
            if name == reference:
                return commit
    raise LineageLoadError(f"Cannot resolve Git reference {reference}")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _master_records(
    headers: list[str], master_rows: dict[int, list[Any]]
) -> list[dict[str, Any]]:
    records = []
    for source_row, row in master_rows.items():
        row_values = {
            header: REPLAY.comparison_value(value)
            for header, value in zip(headers, row, strict=True)
        }
        records.append(
            {
                "source_row": source_row,
                "team": row_values["Team"],
                "team_key": TEAM_KEYS.get(row_values["Team"]),
                "row_values": row_values,
            }
        )
    missing = sorted(
        {record["team"] for record in records if record["team_key"] is None}
    )
    if missing:
        raise LineageLoadError(f"Unknown master team names: {missing}")
    return records


def _candidate_sets(
    masters: Sequence[dict[str, Any]],
    dumps: Sequence[dict[str, Any]],
    *,
    check_dates: bool,
) -> dict[int, set[int]]:
    dumps_by_player: dict[str, list[int]] = defaultdict(list)
    for dump_index, dump_row in enumerate(dumps):
        player_id = dump_row["source_values"].get("PlayerID", "").strip()
        dumps_by_player[player_id].append(dump_index)
    candidates = {}
    for master_index, master_row in enumerate(masters):
        player_id = master_row["row_values"]["PlayerID"].strip()
        candidates[master_index] = {
            dump_index
            for dump_index in dumps_by_player.get(player_id, [])
            if fields_compatible(
                master_row["row_values"],
                dumps[dump_index]["source_values"],
                check_dates=check_dates,
            )
        }
    return candidates


def _constraint_candidates(
    masters: Sequence[dict[str, Any]],
    dumps: Sequence[dict[str, Any]],
    remaining_masters: set[int],
    remaining_dumps: set[int],
) -> dict[int, set[int]]:
    fields = (*DATE_FIELDS, *EXACT_FIELDS)
    candidates = {}
    for master_index in remaining_masters:
        master_values = masters[master_index]["row_values"]
        player_id = master_values["PlayerID"].strip()
        possible = {
            dump_index
            for dump_index in remaining_dumps
            if dumps[dump_index]["source_values"].get("PlayerID", "").strip()
            == player_id
        }
        if len(possible) == 1:
            dump_index = next(iter(possible))
            if not _dates_compatible(
                master_values,
                dumps[dump_index]["source_values"],
            ):
                candidates[master_index] = set()
                continue
        for field in fields:
            matching = {
                dump_index
                for dump_index in possible
                if _field_match(
                    field,
                    master_values.get(field, ""),
                    dumps[dump_index]["source_values"].get(field, ""),
                )
            }
            if matching:
                possible = matching
        candidates[master_index] = possible
    return candidates


def _forced_assignments(
    masters: Sequence[dict[str, Any]],
    dumps: Sequence[dict[str, Any]],
    candidates: dict[int, set[int]],
    remaining_masters: set[int],
    remaining_dumps: set[int],
    assignments: dict[int, tuple[int, str]],
) -> bool:
    changed = False
    while True:
        active = {
            master: candidates[master] & remaining_dumps
            for master in remaining_masters
        }
        dump_candidates: dict[int, set[int]] = {
            dump: set() for dump in remaining_dumps
        }
        for master, dump_indexes in active.items():
            for dump in dump_indexes:
                dump_candidates[dump].add(master)
        forced = []
        for master, dump_indexes in active.items():
            if len(dump_indexes) == 1:
                forced.append((master, next(iter(dump_indexes))))
        for dump, master_indexes in dump_candidates.items():
            if len(master_indexes) == 1:
                forced.append((next(iter(master_indexes)), dump))
        if not forced:
            return changed
        master, dump = min(
            set(forced),
            key=lambda pair: (
                masters[pair[0]]["source_row"],
                dumps[pair[1]]["source_row_number"],
            ),
        )
        assignments[master] = (dump, "unique_candidate")
        remaining_masters.remove(master)
        remaining_dumps.remove(dump)
        changed = True


def _components(
    candidates: dict[int, set[int]],
    remaining_masters: set[int],
    remaining_dumps: set[int],
) -> list[tuple[set[int], set[int]]]:
    reverse: dict[int, set[int]] = {dump: set() for dump in remaining_dumps}
    for master in remaining_masters:
        for dump in candidates[master] & remaining_dumps:
            reverse[dump].add(master)
    components = []
    unseen_masters = set(remaining_masters)
    while unseen_masters:
        start = min(unseen_masters)
        component_masters: set[int] = set()
        component_dumps: set[int] = set()
        queue = deque([("master", start)])
        while queue:
            kind, index = queue.popleft()
            if kind == "master":
                if index in component_masters:
                    continue
                component_masters.add(index)
                unseen_masters.discard(index)
                for dump in candidates[index] & remaining_dumps:
                    queue.append(("dump", dump))
            else:
                if index in component_dumps:
                    continue
                component_dumps.add(index)
                for master in reverse[index]:
                    queue.append(("master", master))
        components.append((component_masters, component_dumps))
    for dump in remaining_dumps:
        if not reverse[dump]:
            components.append((set(), {dump}))
    return components


def _stuck_report(
    team_key: str,
    masters: Sequence[dict[str, Any]],
    dumps: Sequence[dict[str, Any]],
    candidates: dict[int, set[int]],
    remaining_masters: set[int],
    remaining_dumps: set[int],
) -> dict[str, Any]:
    return {
        "team_key": team_key,
        "master_rows": [
            {
                "source_row": masters[index]["source_row"],
                "player_id": masters[index]["row_values"]["PlayerID"],
                "candidate_source_row_numbers": sorted(
                    dumps[dump]["source_row_number"]
                    for dump in candidates[index] & remaining_dumps
                ),
            }
            for index in sorted(
                remaining_masters, key=lambda item: masters[item]["source_row"]
            )
        ],
        "dump_rows": [
            {
                "source_row_number": dumps[index]["source_row_number"],
                "player_id": dumps[index]["source_values"].get("PlayerID", ""),
            }
            for index in sorted(
                remaining_dumps,
                key=lambda item: dumps[item]["source_row_number"],
            )
        ],
    }


def match_team(
    team_key: str,
    masters: Sequence[dict[str, Any]],
    dumps: Sequence[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[int]]:
    if len(masters) != len(dumps):
        raise LineageLoadError(
            f"{team_key}: master count {len(masters)} != dump count {len(dumps)}"
        )
    candidates = _candidate_sets(masters, dumps, check_dates=True)
    remaining_masters = set(range(len(masters)))
    remaining_dumps = set(range(len(dumps)))
    assignments: dict[int, tuple[int, str]] = {}
    _forced_assignments(
        masters,
        dumps,
        candidates,
        remaining_masters,
        remaining_dumps,
        assignments,
    )

    if remaining_masters:
        candidates.update(
            _constraint_candidates(
                masters,
                dumps,
                remaining_masters,
                remaining_dumps,
            )
        )
        _forced_assignments(
            masters,
            dumps,
            candidates,
            remaining_masters,
            remaining_dumps,
            assignments,
        )

    identical_sizes = []
    if remaining_masters or remaining_dumps:
        for component_masters, component_dumps in _components(
            candidates, remaining_masters, remaining_dumps
        ):
            complete = (
                bool(component_masters)
                and len(component_masters) == len(component_dumps)
                and all(
                    candidates[master] & remaining_dumps == component_dumps
                    for master in component_masters
                )
            )
            source_group = [dumps[index] for index in component_dumps]
            if not complete or not identical_group_is_verified(source_group):
                continue
            ordered_masters = sorted(
                component_masters, key=lambda index: masters[index]["source_row"]
            )
            ordered_dumps = sorted(
                component_dumps, key=lambda index: dumps[index]["source_row_number"]
            )
            for master, dump in zip(ordered_masters, ordered_dumps, strict=True):
                assignments[master] = (dump, "identical_duplicate_group")
                remaining_masters.remove(master)
                remaining_dumps.remove(dump)
            identical_sizes.append(len(component_masters))

    if remaining_masters or remaining_dumps:
        masters_by_player: dict[str, list[int]] = defaultdict(list)
        dumps_by_player: dict[str, list[int]] = defaultdict(list)
        for master in remaining_masters:
            player_id = masters[master]["row_values"]["PlayerID"].strip()
            masters_by_player[player_id].append(master)
        for dump in remaining_dumps:
            player_id = dumps[dump]["source_values"].get("PlayerID", "").strip()
            dumps_by_player[player_id].append(dump)
        for player_id in sorted(set(masters_by_player) | set(dumps_by_player)):
            player_masters = masters_by_player[player_id]
            player_dumps = dumps_by_player[player_id]
            if len(player_masters) != 1 or len(player_dumps) != 1:
                stuck = _stuck_report(
                    team_key,
                    masters,
                    dumps,
                    candidates,
                    remaining_masters,
                    remaining_dumps,
                )
                raise LineageLoadError(
                    "Ambiguous bridge rows: "
                    + json.dumps(stuck, ensure_ascii=False, sort_keys=True)
                )
            master = player_masters[0]
            dump = player_dumps[0]
            assignments[master] = (dump, "leftover_singleton")
            remaining_masters.remove(master)
            remaining_dumps.remove(dump)

    if remaining_masters or remaining_dumps or len(assignments) != len(masters):
        raise LineageLoadError(f"{team_key}: bridge assignment is incomplete")
    matched = []
    for master_index in sorted(
        assignments, key=lambda index: masters[index]["source_row"]
    ):
        dump_index, method = assignments[master_index]
        matched.append(
            {
                "master": masters[master_index],
                "dump": dumps[dump_index],
                "match_method": method,
            }
        )
    return matched, identical_sizes


def _pair_disagreements(
    pair: dict[str, Any], headers: Sequence[str]
) -> list[dict[str, Any]]:
    master = pair["master"]
    source_values = pair["dump"]["source_values"]
    disagreements = []
    for field in headers:
        if field not in source_values:
            continue
        master_value = master["row_values"][field]
        source_value = source_values[field]
        if field in DATE_FIELDS and _field_match(
            field, master_value, source_value
        ):
            continue
        if master_value != source_value:
            disagreements.append(
                {
                    "field": field,
                    "master_value": master_value,
                    "source_value": source_value,
                    "master_source_row": master["source_row"],
                    "team": master["team"],
                }
            )
    return disagreements


def build_bridge(
    master_records: Sequence[dict[str, Any]],
    dump_rows: Sequence[dict[str, Any]],
    headers: Sequence[str],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    masters_by_team: dict[str, list[dict[str, Any]]] = defaultdict(list)
    dumps_by_team: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for master in master_records:
        masters_by_team[master["team_key"]].append(master)
    for dump in dump_rows:
        dumps_by_team[dump["team_key"]].append(dump)

    pairs = []
    per_team = {}
    identical_group_sizes = []
    for team_key in sorted(TEAM_KEYS.values()):
        team_pairs, group_sizes = match_team(
            team_key,
            masters_by_team[team_key],
            dumps_by_team[team_key],
        )
        pairs.extend(team_pairs)
        per_team[team_key] = {
            "master_rows": len(masters_by_team[team_key]),
            "dump_rows": len(dumps_by_team[team_key]),
            "matched_rows": len(team_pairs),
        }
        identical_group_sizes.extend(group_sizes)

    disagreements = []
    for pair in pairs:
        pair["disagreements"] = _pair_disagreements(pair, headers)
        disagreements.extend(pair["disagreements"])
    method_counts = Counter(pair["match_method"] for pair in pairs)
    leftover_singletons = [
        {
            "team": pair["master"]["team"],
            "team_key": pair["dump"]["team_key"],
            "player_id": pair["master"]["row_values"]["PlayerID"],
            "master_source_row": pair["master"]["source_row"],
            "source_row_number": pair["dump"]["source_row_number"],
            "source_row_id": pair["dump"]["source_row_id"],
            "injury_id": pair["dump"]["injury_id"],
            "disagreeing_fields": [
                disagreement["field"]
                for disagreement in pair["disagreements"]
            ],
        }
        for pair in pairs
        if pair["match_method"] == "leftover_singleton"
    ]
    source_ids = {pair["dump"]["source_row_id"] for pair in pairs}
    injury_ids = {pair["dump"]["injury_id"] for pair in pairs}
    bijective = (
        len(pairs) == EXPECTED_MASTER_ROWS
        and len(source_ids) == EXPECTED_MASTER_ROWS
        and len(injury_ids) == EXPECTED_MASTER_ROWS
    )
    report = {
        "season": SEASON,
        "per_team_counts": per_team,
        "match_method_counts": dict(sorted(method_counts.items())),
        "identical_group_sizes": sorted(identical_group_sizes),
        "leftover_singletons": leftover_singletons,
        "disagreements": disagreements,
        "bijective": bijective,
        "aborted": False,
    }
    if not bijective:
        raise LineageLoadError("Bridge did not produce a 3,060-row bijection")
    return pairs, report


def _fixed_timestamp(ledger: dict[str, Any]) -> str:
    timestamps = []
    for step in ledger["steps"]:
        value = step["applied_at"]
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        timestamps.append(parsed.astimezone(timezone.utc))
    return max(timestamps).isoformat().replace("+00:00", "Z")


def _step_run_sql(
    run_id: uuid.UUID,
    step_name: str,
    reason_code: str,
    count: int,
    timestamp: str,
    input_hash: str,
    output_hash: str,
) -> str:
    columns = (
        "pipeline_run_id",
        "step_name",
        "step_version",
        "reason_code",
        "input_count",
        "output_count",
        "input_hash",
        "output_hash",
        "started_at",
        "ended_at",
    )
    row = (
        sql_literal(str(run_id)),
        sql_literal(step_name),
        sql_literal(STEP_VERSION),
        sql_literal(reason_code),
        str(count),
        str(count),
        sql_literal(input_hash),
        sql_literal(output_hash),
        sql_literal(timestamp),
        sql_literal(timestamp),
    )
    return insert_batches("audit.step_runs", columns, [row])


def _master_sql(
    master_records: Sequence[dict[str, Any]],
    run_id: uuid.UUID,
    timestamp: str,
    master_hash: str,
) -> str:
    rows = []
    for record in master_records:
        reason = record["row_values"]["Exclusion Reason"].strip()
        excluded = bool(reason)
        rows.append(
            (
                sql_literal(SEASON),
                str(record["source_row"]),
                sql_literal(record["team"]),
                sql_json(record["row_values"]),
                sql_value(excluded),
                sql_value(reason if excluded else None),
            )
        )
    body = insert_batches(
        "lineage.master_rows",
        (
            "season",
            "source_row",
            "team",
            "row_values",
            "excluded",
            "exclusion_reason",
        ),
        rows,
    )
    return body + "\n" + _step_run_sql(
        run_id,
        "lineage_master_rows",
        "lineage_baseline_load",
        len(rows),
        timestamp,
        master_hash,
        hashlib.sha256(body.encode("utf-8")).hexdigest(),
    )


def _ledger_sql(
    ledger: dict[str, Any],
    run_id: uuid.UUID,
    timestamp: str,
    ledger_hash: str,
) -> tuple[str, int]:
    step_rows = []
    entry_rows = []
    for step in ledger["steps"]:
        order = int(step["order"])
        step_rows.append(
            (
                sql_literal(SEASON),
                str(order),
                sql_literal(REPLAY.comparison_value(step["rule_version"])),
                sql_literal(REPLAY.comparison_value(step["applied_at"])),
                sql_literal(REPLAY.comparison_value(step["carry_forward"])),
                sql_literal(REPLAY.comparison_value(step["description"])),
                sql_json(step.get("evidence", [])),
            )
        )
        for entry_index, entry in enumerate(step.get("entries", [])):
            entry_rows.append(
                (
                    sql_literal(SEASON),
                    str(order),
                    str(entry_index),
                    str(int(entry["source_workbook_row"])),
                    sql_literal(REPLAY.comparison_value(entry["team"])),
                    sql_literal(REPLAY.comparison_value(entry["player_id"])),
                    sql_literal(REPLAY.comparison_value(entry["field"])),
                    sql_literal(REPLAY.comparison_value(entry.get("old_value"))),
                    sql_literal(REPLAY.comparison_value(entry.get("new_value"))),
                    sql_literal(REPLAY.comparison_value(entry["action"])),
                    sql_literal(REPLAY.comparison_value(entry["reason"])),
                    sql_value(entry.get("evidence_origin")),
                    sql_value(entry.get("value_origin")),
                    sql_value(REPLAY._is_removal(entry)),
                )
            )
    steps_sql = insert_batches(
        "lineage.ledger_steps",
        (
            "season",
            "step_order",
            "rule_version",
            "applied_at",
            "carry_forward",
            "description",
            "evidence",
        ),
        step_rows,
    )
    entries_sql = insert_batches(
        "lineage.ledger_entries",
        (
            "season",
            "step_order",
            "entry_index",
            "source_row",
            "team",
            "player_id",
            "field",
            "old_value",
            "new_value",
            "action",
            "reason",
            "evidence_origin",
            "value_origin",
            "is_removal",
        ),
        entry_rows,
    )
    body = steps_sql + "\n" + entries_sql
    result = body + "\n" + _step_run_sql(
        run_id,
        "lineage_ledger",
        "lineage_baseline_load",
        len(entry_rows),
        timestamp,
        ledger_hash,
        hashlib.sha256(body.encode("utf-8")).hexdigest(),
    )
    return result, len(entry_rows)


def _bridge_sql(
    pairs: Sequence[dict[str, Any]],
    run_id: uuid.UUID,
    timestamp: str,
    dump_hash: str,
) -> str:
    rows = []
    for pair in pairs:
        master = pair["master"]
        dump = pair["dump"]
        evidence = {}
        if pair["disagreements"]:
            evidence["disagreements"] = [
                disagreement["field"] for disagreement in pair["disagreements"]
            ]
        rows.append(
            (
                sql_literal(SEASON),
                str(master["source_row"]),
                sql_literal(master["team_key"]),
                sql_literal(dump["source_row_id"]),
                sql_literal(dump["injury_id"]),
                sql_literal(dump["curated_build_id"]),
                sql_literal(pair["match_method"]),
                sql_json(evidence),
            )
        )
    body = insert_batches(
        "lineage.master_source_bridge",
        (
            "season",
            "source_row",
            "team_key",
            "source_row_id",
            "injury_id",
            "curated_build_id",
            "match_method",
            "match_evidence",
        ),
        rows,
    )
    return body + "\n" + _step_run_sql(
        run_id,
        "lineage_master_source_bridge",
        "lineage_master_source_bridge",
        len(rows),
        timestamp,
        dump_hash,
        hashlib.sha256(body.encode("utf-8")).hexdigest(),
    )


def _baseline_sql(
    baseline_record: dict[str, Any],
    run_id: uuid.UUID,
    timestamp: str,
    code_version: str,
    input_hashes: dict[str, str],
    generated_hashes: dict[str, str],
) -> str:
    parameters = {
        "input_artifact_sha256": input_hashes,
        "generated_file_sha256": generated_hashes,
    }
    run_columns = (
        "id",
        "command",
        "season",
        "status",
        "parameters",
        "code_version",
        "started_at",
        "ended_at",
    )
    run_row = (
        sql_literal(str(run_id)),
        sql_literal("lineage-load"),
        sql_literal(SEASON),
        sql_literal("succeeded"),
        sql_json(parameters),
        sql_literal(code_version),
        sql_literal(timestamp),
        sql_literal(timestamp),
    )
    baseline_columns = (
        "season",
        "baseline_identity",
        "baseline_record",
        "baseline_record_sha256",
        "master_json_sha256",
        "ledger_sha256",
        "inclusion_csv_sha256",
        "source_row_mapping_sha256",
        "pipeline_run_id",
        "loaded_at",
    )
    baseline_row = (
        sql_literal(SEASON),
        sql_literal(REPLAY.comparison_value(baseline_record["identity"])),
        sql_json(baseline_record),
        sql_literal(input_hashes["baseline_record"]),
        sql_literal(input_hashes["master_json"]),
        sql_literal(input_hashes["ledger"]),
        sql_literal(input_hashes["inclusion_csv"]),
        sql_literal(EXPECTED_MAPPING_SHA256),
        sql_literal(str(run_id)),
        sql_literal(timestamp),
    )
    return (
        insert_batches("audit.pipeline_runs", run_columns, [run_row])
        + "\n"
        + insert_batches("lineage.baselines", baseline_columns, [baseline_row])
    )


def _write_json(path: Path, payload: Any) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _verify_inputs() -> dict[str, str]:
    paths = {
        "master_json": MASTER_PATH,
        "ledger": LEDGER_PATH,
        "baseline_record": BASELINE_RECORD_PATH,
        "inclusion_csv": INCLUSION_PATH,
        "member_build_source_rows": DUMP_PATH,
    }
    hashes = {}
    for name, path in paths.items():
        if not path.exists():
            raise LineageLoadError(f"Missing input artifact: {path}")
        hashes[name] = sha256_file(path)
        expected = EXPECTED_HASHES.get(name)
        if expected is not None and hashes[name] != expected:
            raise LineageLoadError(
                f"{name} sha256 {hashes[name]} does not match expected {expected}"
            )
    return hashes


def _run(season: str) -> dict[str, Any]:
    if season != SEASON:
        raise LineageLoadError(f"Only season {SEASON} is supported")
    input_hashes = _verify_inputs()
    master_payload = _load_json(MASTER_PATH)
    ledger = _load_json(LEDGER_PATH)
    baseline_record = _load_json(BASELINE_RECORD_PATH)
    dump_rows = _load_json(DUMP_PATH)

    headers, master_rows = REPLAY.load_master_table(master_payload)
    selected, ordered_source_rows = REPLAY.select_inclusion(headers, master_rows)
    retained, retained_source_rows, _, conflicts = REPLAY.apply_ledger(
        headers,
        selected,
        ordered_source_rows,
        ledger,
        master_rows,
    )
    if len(master_rows) != EXPECTED_MASTER_ROWS:
        raise LineageLoadError(f"Expected 3,060 master rows, got {len(master_rows)}")
    excluded_count = len(master_rows) - len(selected)
    if excluded_count != EXPECTED_EXCLUDED_ROWS:
        raise LineageLoadError(
            f"Expected 755 excluded master rows, got {excluded_count}"
        )
    if len(retained) != EXPECTED_RETAINED_ROWS or conflicts:
        raise LineageLoadError(
            f"Replay produced {len(retained)} retained rows and "
            f"{len(conflicts)} conflicts"
        )
    mapping_hash = REPLAY.mapping_sha256(retained_source_rows)
    if mapping_hash != EXPECTED_MAPPING_SHA256:
        raise LineageLoadError(
            f"Retained mapping sha256 {mapping_hash} does not match expected "
            f"{EXPECTED_MAPPING_SHA256}"
        )
    if len(ledger.get("steps", [])) != EXPECTED_LEDGER_STEPS:
        raise LineageLoadError(
            f"Expected 10 ledger steps, got {len(ledger.get('steps', []))}"
        )
    if len(dump_rows) != EXPECTED_MASTER_ROWS:
        raise LineageLoadError(f"Expected 3,060 dump rows, got {len(dump_rows)}")

    master_records = _master_records(headers, master_rows)
    try:
        pairs, bridge_report = build_bridge(master_records, dump_rows, headers)
    except LineageLoadError as error:
        report = {
            "season": SEASON,
            "per_team_counts": {},
            "match_method_counts": {},
            "identical_group_sizes": [],
            "disagreements": [],
            "bijective": False,
            "aborted": True,
            "error": str(error),
        }
        _write_json(BRIDGE_REPORT_PATH, report)
        raise
    _write_json(BRIDGE_REPORT_PATH, bridge_report)

    timestamp = _fixed_timestamp(ledger)
    identity_material = json.dumps(
        input_hashes, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    run_id = uuid.uuid5(UUID_NAMESPACE, identity_material)
    sql_paths = {
        "01_baseline.sql": OUTPUT_DIR / "01_baseline.sql",
        "02_master_rows.sql": OUTPUT_DIR / "02_master_rows.sql",
        "03_ledger.sql": OUTPUT_DIR / "03_ledger.sql",
        "04_bridge.sql": OUTPUT_DIR / "04_bridge.sql",
    }
    master_sql = _master_sql(
        master_records, run_id, timestamp, input_hashes["master_json"]
    )
    ledger_sql, ledger_entry_count = _ledger_sql(
        ledger, run_id, timestamp, input_hashes["ledger"]
    )
    bridge_sql = _bridge_sql(
        pairs, run_id, timestamp, input_hashes["member_build_source_rows"]
    )
    sql_paths["02_master_rows.sql"].write_text(master_sql, encoding="utf-8")
    sql_paths["03_ledger.sql"].write_text(ledger_sql, encoding="utf-8")
    sql_paths["04_bridge.sql"].write_text(bridge_sql, encoding="utf-8")
    generated_hashes = {
        name: sha256_file(path)
        for name, path in sql_paths.items()
        if name != "01_baseline.sql"
    }
    generated_hashes[BRIDGE_REPORT_PATH.name] = sha256_file(BRIDGE_REPORT_PATH)
    baseline_sql = _baseline_sql(
        baseline_record,
        run_id,
        timestamp,
        _git_head(),
        input_hashes,
        generated_hashes,
    )
    sql_paths["01_baseline.sql"].write_text(baseline_sql, encoding="utf-8")
    sql_hashes = {name: sha256_file(path) for name, path in sql_paths.items()}

    row_counts = {
        "lineage.baselines": 1,
        "lineage.master_rows": len(master_records),
        "lineage.ledger_steps": len(ledger["steps"]),
        "lineage.ledger_entries": ledger_entry_count,
        "lineage.master_source_bridge": len(pairs),
    }
    manifest = {
        "season": SEASON,
        "pipeline_run_id": str(run_id),
        "input_artifact_sha256": input_hashes,
        "generated_sql_sha256": sql_hashes,
        "bridge_report_sha256": sha256_file(BRIDGE_REPORT_PATH),
        "row_counts": row_counts,
    }
    _write_json(MANIFEST_PATH, manifest)
    return {
        "row_counts": row_counts,
        "match_method_counts": bridge_report["match_method_counts"],
        "disagreements": bridge_report["disagreements"],
    }


def _print_summary(summary: dict[str, Any]) -> None:
    print("Lineage load SQL generated")
    for table, count in summary["row_counts"].items():
        print(f"  {table}: {count}")
    print("Bridge match methods")
    for method, count in summary["match_method_counts"].items():
        print(f"  {method}: {count}")
    field_counts = Counter(
        item["field"] for item in summary["disagreements"]
    )
    print("Matched-pair field disagreements")
    if not field_counts:
        print("  none")
    for field, count in sorted(field_counts.items()):
        print(f"  {field}: {count}")


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build deterministic offline SQL for reviewed injury lineage."
    )
    parser.add_argument("--season", required=True)
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        summary = _run(args.season)
    except (LineageLoadError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    _print_summary(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
