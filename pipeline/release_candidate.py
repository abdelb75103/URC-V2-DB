"""Prepare an isolated, source-bound dashboard candidate without activating it."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

SCHEMA = "urc_candidate_20260915"
IRFU = {"leinster", "munster", "ulster", "connacht"}


def prepare(directory: Path, migration: Path) -> None:
    sources = json.loads((directory / "analysis_sources.json").read_text())[0]["sources"]
    typed = json.loads((directory / "intake/irfu_typed_rows.json").read_text())
    root = directory / "intake/v15_candidate_intake_root_manifest.json"
    params = []
    params.extend({"kind": "injury_bridge", "row": row} for row in typed["bridge"])
    for kind, key in (("injury", "injuries"), ("illness", "illnesses")):
        rows = [r for r in sources[key] if r["season"] == "2025-26" and r["team_key"] not in IRFU]
        rows += typed[key]
        params.extend({"kind": kind, "row": r} for r in rows)
    for team, version in (("benetton", 3), ("edinburgh", 2)):
        path = directory / "intake" / team / f"exposure_intake_final_clean_v{version}.csv"
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        with path.open() as handle:
            for number, row in enumerate(csv.DictReader(handle), 2):
                params.append({"kind": "exposure", "row": {
                    "team_key": team, "file_sha256": digest, "source_row_number": number,
                    "player_uid": row["player_uid"], "grain": row["exposure_grain"],
                    "included": row["cleaning_action"] == "include",
                    "exclusion_reason": row["exclusion_reason"],
                    "exposure_date": row["cleaned_date"] or None,
                    "week_start": row["week_start_date"] or None,
                    "minutes": row["minutes_total_clean"] or None,
                    "distance_m": row["distance_total_m_clean"] or None,
                    "hsr_m": row["source_hsr_gt18_kmh" if team == "benetton" else "source_hsr_value"] or None,
                    "estimated": row.get("Actual/Estimated", "").lower() == "estimated",
                }})
    params.append({"kind": "provenance", "root_sha256": hashlib.sha256(root.read_bytes()).hexdigest(),
                   "baseline_sha256": hashlib.sha256((directory / "served_before.json").read_bytes()).hexdigest(),
                   "hsr_decision": "Abdel selected Benetton HSR >18 km/h and Edinburgh High Speed Running as actual source fields in this task. Preserve blank values and unspecified Edinburgh threshold.",
                   "rule_version": "urc_intake_candidate_20260915_v1",
                   "typed_sha256": hashlib.sha256((directory / "intake/irfu_typed_rows.json").read_bytes()).hexdigest()})
    output = directory / "candidate_params.json"
    output.write_text(json.dumps(params, separators=(",", ":")) + "\n")
    sql = (Path(__file__).parent / "release_candidate.sql").read_text()
    # Reuse accepted SQL calculators with only their explicitly selected inputs rebound.
    names = set(sources["views"]) | set(sources["functions"]) | {
        "urc_canonical_injury_rows_v1", "urc_2025_26_canonical_injury_rows_v1",
        "urc_illness_profile_rows_v2", "diagnosis_family_base_team_payloads_v1",
        "diagnosis_family_base_league_payloads_v1",
    }
    def bind(definition: str) -> str:
        for name in sorted(names, key=len, reverse=True):
            for old_schema in ("analysis", "reporting"):
                definition = definition.replace(f"{old_schema}.{name}", f"{SCHEMA}.{name}")
        return definition
    order = ["urc_diagnosis_family_team_exposure_v1", "urc_diagnosis_family_team_subtypes_v1",
             "urc_diagnosis_family_team_families_v1", "urc_diagnosis_family_league_exposure_v1",
             "urc_diagnosis_family_league_subtypes_v1", "urc_diagnosis_family_league_families_v1",
             "urc_illness_team_profiles_v1", "urc_illness_league_profiles_v1", "urc_2025_26_setting_severity_v1"]
    cloned = []
    for name in order:
        cloned.append(f"create view {SCHEMA}.{name} as\n{bind(sources['views'][name])}\n")
    for definition in sources["functions"].values():
        cloned.append(bind(definition) + ";\n")
    sql = sql.replace("-- CLONED_CALCULATORS", "\n".join(cloned))
    sql = sql.replace("CANDIDATE_PARAMS_SHA256", hashlib.sha256(output.read_bytes()).hexdigest())
    migration.write_text(sql)
    print(json.dumps({"params": str(output), "rows": len(params), "migration": str(migration)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--migration", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.directory, args.migration)
