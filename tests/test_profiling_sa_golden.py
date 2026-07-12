"""One-time local development regression for the Step 0 scanner.

The accepted artifacts and their source workbooks are intentionally ignored by
Git.  This test therefore skips in a fresh clone.  It never writes beside the
accepted artifacts: scanner outputs and the checksum cache live in a temporary
directory for the duration of the test.  It is not an operational family check,
profile gate, or requirement that future teams be reconciled in groups of four.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
import unittest
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
INTAKE_ROOT = REPO_ROOT / "data" / "intake" / "2024-25"
LEGACY_ROOT = Path(os.environ.get("URC_LEGACY_ROOT", "/Users/abdelbabiker/Desktop/URC"))
TEAMS = ("bulls", "lions", "sharks", "stormers")
TEAM_ALIAS_RE = re.compile(r"Team [A-Z]")
DATE_ORDERS = {
    ("bulls", "injury"): "month_first",
    ("lions", "injury"): "day_first",
    ("sharks", "injury"): "day_first",
    ("sharks", "exposure"): "month_first",
    ("stormers", "injury"): "day_first",
    ("stormers", "exposure"): "day_first",
}
GOLDEN_AGGREGATES = {
    "bulls": {
        "injury_player_date_groups": 4,
        "injury_full_key_groups": 0,
        "exposure_blank_identifier": 0,
        "distance_above_20000": 12,
        "distance_above_50000": 4,
    },
    "lions": {
        "injury_exact_duplicate_groups": 1,
        # Keep the defensible configured candidate key separate from exact-row
        # evidence: the two facts answer different questions.
        "injury_player_date_groups": 6,
        "exposure_blank_identifier": 547,
    },
    "sharks": {
        "injury_exact_duplicate_groups": 0,
        "injury_player_date_groups": 31,
        "exposure_blank_identifier": 246,
        "duration_above_240": 565,
    },
    "stormers": {
        "injury_exact_duplicate_groups": 0,
        "injury_player_date_groups": 3,
        "injury_full_key_groups": 0,
        "exposure_blank_identifier": 443,
        "duration_above_240": 27,
    },
}


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _source_entries(profile: dict[str, Any]) -> list[dict[str, Any]]:
    return profile.get("inputs") or profile.get("file_inventory") or profile.get("files") or []


def _candidate_entry(profile: dict[str, Any], kind: str) -> dict[str, Any]:
    matches = []
    for entry in _source_entries(profile):
        role = str(entry.get("role", "")).casefold()
        if kind in role and any(marker in role for marker in ("standardised", "candidate", "intended")):
            matches.append(entry)
    if len(matches) != 1:
        raise unittest.SkipTest(f"{profile.get('team', 'team')}: no unique {kind} candidate artifact")
    return matches[0]


def _resolve_source(entry: dict[str, Any]) -> Path:
    direct = entry.get("path") or entry.get("source_path")
    if direct:
        path = Path(str(direct))
        if path.is_file():
            return path

    filename = entry.get("name") or entry.get("filename")
    if not filename or not LEGACY_ROOT.is_dir():
        raise unittest.SkipTest("local candidate workbook is unavailable")
    matches = [path for path in LEGACY_ROOT.rglob(str(filename)) if path.is_file()]
    if len(matches) != 1:
        raise unittest.SkipTest("local candidate workbook could not be resolved uniquely")
    return matches[0]


def _normalise_columns(inventory: dict[str, Any], kind: str) -> list[dict[str, Any]]:
    result = []
    for column in inventory[kind]["columns"]:
        if isinstance(column, dict):
            result.append(
                {
                    "name": column["name"],
                    "populated": column.get("populated", column.get("populated_count")),
                    "blank": column.get("blank", column.get("blank_count")),
                }
            )
        else:
            name, _observed_types, populated, blank, _meaning = column
            result.append({"name": name, "populated": populated, "blank": blank})
    return result


def _sheet_name(
    profile: dict[str, Any], inventory: dict[str, Any], entry: dict[str, Any], kind: str
) -> str:
    sheet = entry.get("sheet") or inventory[kind].get("sheet")
    if sheet:
        return str(sheet)
    sheets = entry.get("sheets")
    if isinstance(sheets, list) and len(sheets) == 1:
        only = sheets[0]
        return str(only.get("name") if isinstance(only, dict) else only)
    # All four accepted candidate workbooks use this sheet; fail later if the
    # accepted artifact and workbook have drifted.
    return "Standardized Data"


def _window(profile: dict[str, Any], team_key: str, kind: str) -> dict[str, Any]:
    if team_key == "bulls":
        reporting = profile[f"{kind}_reporting"]
        return reporting["reporting_window"]
    if team_key == "lions":
        reporting = profile[f"{kind}_reporting_structure"]
        return reporting["reporting_window"]
    if kind == "injury":
        return profile["injury"]["window"]
    if team_key == "stormers":
        return profile["exposure"]["observed_window"]
    return profile["exposure"]["window"]


def _expected_source(team_key: str, kind: str) -> dict[str, Any]:
    team_dir = INTAKE_ROOT / team_key
    profile = _load_json(team_dir / "team_intake_profile.json")
    inventory = _load_json(team_dir / "column_inventory.json")
    entry = _candidate_entry(profile, kind)
    columns = _normalise_columns(inventory, kind)
    denominator = max(column["populated"] + column["blank"] for column in columns)
    return {
        "entry": entry,
        "path": _resolve_source(entry),
        "sha256": str(entry["sha256"]),
        "sheet": _sheet_name(profile, inventory, entry, kind),
        "physical_data_rows": denominator,
        "columns": columns,
        "reporting_window": {
            key: value for key, value in _window(profile, team_key, kind).items() if key in {"start", "end"}
        },
    }


def _column_classes(columns: list[dict[str, Any]], kind: str) -> dict[str, list[str]]:
    classes = {name: [] for name in ("safe_category", "identifier", "free_text", "opaque", "date")}
    reporting_date_selected = False
    for item in columns:
        name = str(item["name"])
        folded = re.sub(r"[^a-z0-9]", "", name.casefold())
        if (
            folded in {"name", "playerid", "playeruid", "athleteid", "dateofbirth", "dob"}
            or ("player" in folded and any(token in folded for token in ("id", "uid", "code", "name")))
        ):
            classes["identifier"].append(name)
        elif any(token in folded for token in ("description", "diagnosis", "freetext", "notes")):
            classes["free_text"].append(name)
        elif not reporting_date_selected and (
            (kind == "injury" and folded == "dateinjured")
            or (kind == "exposure" and folded in {"sessiondate", "date"})
        ):
            classes["date"].append(name)
            reporting_date_selected = True
        else:
            # Golden regression needs counts, not raw category values.  An
            # empty safe-category allowlist is the privacy-maximal plan.
            classes["opaque"].append(name)
    return classes


def _plan(team_key: str) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    expected = {kind: _expected_source(team_key, kind) for kind in ("injury", "exposure")}
    sources = []
    for kind, item in expected.items():
        classes = _column_classes(item["columns"], kind)
        identifier = classes["identifier"][:1]
        date_columns = classes["date"][:1]
        duplicate_keys = [identifier + date_columns] if identifier and date_columns else []
        if kind == "injury" and team_key in {"bulls", "stormers"}:
            full_key = ["PlayerID", "Date Injured", "Orchard Code"]
            if all(any(column["name"] == name for column in item["columns"]) for name in full_key):
                duplicate_keys.append(full_key)
        required_metrics = []
        if kind == "exposure":
            metric_names = {
                "minutestotal",
                "distancetotal",
                "highspeedrunningdistance",
                "veryhighspeedrunningdistance",
            }
            required_metrics = [
                column["name"]
                for column in item["columns"]
                if re.sub(r"[^a-z0-9]", "", str(column["name"]).casefold()) in metric_names
            ]
        anomaly_rules = [
            {"id": f"{kind}_blank_{index}", "column": name, "operator": "blank"}
            for index, name in enumerate(required_metrics)
        ]
        if kind == "exposure" and identifier:
            anomaly_rules.append(
                {"id": "exposure_blank_identifier", "column": identifier[0], "operator": "blank"}
            )
        if kind == "exposure" and team_key == "bulls":
            anomaly_rules.extend(
                (
                    {
                        "id": "distance_above_20000",
                        "column": "distance total",
                        "operator": "gt",
                        "value": 20000,
                    },
                    {
                        "id": "distance_above_50000",
                        "column": "distance total",
                        "operator": "gt",
                        "value": 50000,
                    },
                )
            )
        if kind == "exposure" and team_key == "sharks":
            anomaly_rules.append(
                {
                    "id": "duration_above_240",
                    "operator": "elapsed_minutes_gt",
                    "start_column": "session start date time",
                    "end_column": "session end date time",
                    "value": 240,
                }
            )
        if kind == "exposure" and team_key == "stormers":
            anomaly_rules.append(
                {
                    "id": "duration_above_240",
                    "operator": "duration_minutes_gt",
                    "column": "minutes total",
                    "value": 240,
                }
            )
        source = {
            "id": kind,
            "role": "proposed_intake",
            "kind": kind,
            "path": str(item["path"]),
            "sheets": [item["sheet"]],
            "column_classes": classes,
            "duplicate_keys": duplicate_keys,
            "required_metrics": required_metrics,
            "anomaly_rules": anomaly_rules,
            "exact_row_duplicates": kind == "injury",
        }
        if classes["date"]:
            # String-date order comes from the accepted team-specific evidence,
            # never from a cross-team default. Excel date cells are unambiguous;
            # the remaining two exposure sources therefore need no guess.
            source["date_order"] = DATE_ORDERS.get((team_key, kind), "day_first")
        if kind == "exposure":
            source["exposure_grain_evidence"] = {
                "weekly_columns": [name for name in ("Week",) if any(c["name"] == name for c in item["columns"])],
                "session_columns": date_columns,
            }
        sources.append(source)
    plan = {
        "plan_version": "team_intake_profiling_plan_v1",
        "team": _load_json(INTAKE_ROOT / team_key / "team_intake_profile.json")["team"],
        "team_key": team_key,
        "season": "2024-25",
        "sources": sources,
    }
    return plan, expected


def _jsonable(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        return {str(key): _jsonable(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(item) for item in value]
    return value


def _strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from _strings(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _strings(item)


class SouthAfricaProfilingGoldenTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        try:
            from pipeline import profiling  # type: ignore
        except (ImportError, ModuleNotFoundError) as exc:
            raise unittest.SkipTest("pipeline.profiling is not available yet") from exc
        if not callable(getattr(profiling, "scan_plan", None)):
            raise unittest.SkipTest("pipeline.profiling.scan_plan is not available yet")
        cls.profiling = profiling
        for team_key in TEAMS:
            team_dir = INTAKE_ROOT / team_key
            if not (team_dir / "team_intake_profile.json").is_file() or not (
                team_dir / "column_inventory.json"
            ).is_file():
                raise unittest.SkipTest("local accepted South African artifacts are unavailable")

    def test_scanner_matches_available_development_goldens(self) -> None:
        from openpyxl import load_workbook

        loader_calls = 0

        def counting_loader(*args: Any, **kwargs: Any):
            nonlocal loader_calls
            loader_calls += 1
            return load_workbook(*args, **kwargs)

        with tempfile.TemporaryDirectory(prefix="urc-profile-golden-") as temporary:
            temporary_root = Path(temporary)
            cache_root = temporary_root / "cache"
            all_generated: list[Path] = []

            for team_key in TEAMS:
                plan, expected = _plan(team_key)
                output_root = temporary_root / team_key

                before_cold = loader_calls
                cold = self.profiling.scan_plan(
                    plan,
                    output_root=output_root,
                    cache_root=cache_root,
                    workbook_loader=counting_loader,
                )
                self.assertEqual(loader_calls - before_cold, 2)
                self.assertEqual(cold["cache_misses"], 2)
                self.assertEqual(cold["cache_hits"], 0)
                self.assertEqual(cold["status"], "PASS")

                cold_evidence = _load_json(Path(cold["outputs"]["mechanical_evidence"]))
                actual_by_id = {source["id"]: source for source in cold_evidence["sources"]}
                self.assertEqual(set(actual_by_id), {"injury", "exposure"})
                for kind, golden in expected.items():
                    actual = actual_by_id[kind]
                    self.assertEqual(actual["sha256"], golden["sha256"])
                    self.assertEqual(len(actual["sheets"]), 1)
                    sheet = actual["sheets"][0]
                    self.assertEqual(sheet["name"], golden["sheet"])
                    self.assertEqual(sheet["dimensions"]["max_column"], len(golden["columns"]))
                    self.assertEqual(sheet["physical_data_rows"], golden["physical_data_rows"])
                    actual_columns = [
                        {key: column[key] for key in ("name", "populated", "blank")}
                        for column in sheet["columns"]
                    ]
                    self.assertEqual(actual_columns, golden["columns"])
                    self.assertEqual(
                        {key: sheet["reporting_window"].get(key) for key in ("start", "end")},
                        golden["reporting_window"],
                    )
                    expected_blanks = {column["name"]: column["blank"] for column in golden["columns"]}
                    for rule in next(source for source in plan["sources"] if source["id"] == kind)[
                        "anomaly_rules"
                    ]:
                        if rule["id"].startswith(f"{kind}_blank_"):
                            self.assertEqual(
                                sheet["anomalies"][rule["id"]], expected_blanks[rule["column"]]
                            )

                    aggregates = GOLDEN_AGGREGATES[team_key]
                    if kind == "injury":
                        duplicate_totals = {
                            tuple(item["columns"]): item["groups"] for item in sheet["duplicate_groups"]
                        }
                        player_date = ("PlayerID", "Date Injured")
                        self.assertEqual(
                            duplicate_totals[player_date], aggregates["injury_player_date_groups"]
                        )
                        if "injury_full_key_groups" in aggregates:
                            self.assertEqual(
                                duplicate_totals[("PlayerID", "Date Injured", "Orchard Code")],
                                aggregates["injury_full_key_groups"],
                            )
                        if "injury_exact_duplicate_groups" in aggregates:
                            self.assertEqual(
                                sheet["exact_duplicate_groups"],
                                aggregates["injury_exact_duplicate_groups"],
                            )
                    else:
                        for aggregate_id in (
                            "exposure_blank_identifier",
                            "distance_above_20000",
                            "distance_above_50000",
                            "duration_above_240",
                        ):
                            if aggregate_id in aggregates:
                                self.assertEqual(
                                    sheet["anomalies"][aggregate_id], aggregates[aggregate_id]
                                )

                output_paths = [Path(path) for path in cold["outputs"].values()]
                self.assertTrue(all(path.is_file() and temporary_root in path.parents for path in output_paths))
                cold_bytes = {path.name: path.read_bytes() for path in output_paths}
                all_generated.extend(output_paths)

                before_warm = loader_calls
                warm = self.profiling.scan_plan(
                    plan,
                    output_root=output_root,
                    cache_root=cache_root,
                    workbook_loader=counting_loader,
                )
                self.assertEqual(loader_calls - before_warm, 0)
                self.assertEqual(warm["cache_hits"], 2)
                self.assertEqual(warm["cache_misses"], 0)
                warm_paths = [Path(path) for path in warm["outputs"].values()]
                self.assertEqual(cold_bytes, {path.name: path.read_bytes() for path in warm_paths})
                warm_evidence = _load_json(Path(warm["outputs"]["mechanical_evidence"]))
                self.assertEqual(cold_evidence["sources"], warm_evidence["sources"])

                # Privacy scan without echoing a matched value. Safe categories
                # are deliberately empty; aliases must not appear anywhere.
                generated_value = _jsonable(warm)
                generated_text = json.dumps(generated_value, sort_keys=True)
                for path in warm_paths:
                    generated_text += path.read_text(encoding="utf-8")
                if TEAM_ALIAS_RE.search(generated_text):
                    self.fail("privacy scan found a protected-alias pattern")
                for source in warm_evidence["sources"]:
                    for sheet in source["sheets"]:
                        self.assertEqual(sheet.get("category_frequencies", {}), {})
                unsafe_keys = {
                    "identifier_values",
                    "free_text_values",
                    "raw_values",
                    "row_values",
                    "value_samples",
                }
                if any(string in unsafe_keys for string in _strings(generated_value)):
                    self.fail("privacy scan found a forbidden raw-value field")

            self.assertEqual(loader_calls, 2 * len(TEAMS))
            self.assertTrue(all(path.is_file() for path in all_generated))


if __name__ == "__main__":
    unittest.main()
