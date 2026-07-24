#!/usr/bin/env python3
"""Independently verify the loaded lineage layer against the accepted artifacts.

Read-only. Pulls the DB-derived inclusion rows (analysis.lineage_included_rows_v1)
through pipeline/sql_query.mjs, serializes them with the accepted export code
path, and compares byte hashes against the accepted inclusion CSV and retained
source-row mapping. Also reconciles master/ledger/bridge row counts.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_CSV_SHA256 = (
    "e8da3caf4934f62a521ccecd61abbbf4fa03a837621c4103862b0e87ac31fedb"
)
EXPECTED_MAPPING_SHA256 = (
    "9910b585af28cc304e5beaf4806113bb770c0ef239d852ae1270c4ec1a4faf4f"
)
HEADERS = [
    "Team", "PlayerID", "Received At Club", "Received/Injured In Team",
    "Problem type", "Date Injured", "Fit For Selection Date",
    "Confirmed Return Date", "Days Injured", "Occasion category", "Body Part",
    "Orchard Code", "Illness Code", "Description", "Injury Tissue Type/s",
    "Side", "Nature of onset", "Recurrence", "Is Contact",
    "Mechanism of Injury", "Mechanism Notes", "Injury Surface Type",
    "Match Type", "Received At Position", "Required Surgery",
    "TimeLoss vs Medical Attention", "Diagnosis", "Exclusion Reason",
]


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


EXPORT = _load_module(
    "export_included_injury_dataset",
    ROOT / "tools/export_included_injury_dataset.py",
)


def query(sql: str):
    with tempfile.NamedTemporaryFile(
        "w", suffix=".sql", dir=ROOT / "data/reporting", delete=False
    ) as handle:
        handle.write(sql)
        sql_path = handle.name
    try:
        result = subprocess.run(
            ["node", str(ROOT / "pipeline/sql_query.mjs"), sql_path],
            capture_output=True, text=True, check=True, cwd=ROOT,
        )
    finally:
        Path(sql_path).unlink(missing_ok=True)
    return json.loads(result.stdout)


def main() -> int:
    failures = []

    counts = query(
        """
        select
          (select count(*) from lineage.master_rows where season = '2024-25') as master_rows,
          (select count(*) from lineage.master_rows where season = '2024-25' and excluded) as master_excluded,
          (select count(*) from lineage.ledger_steps where season = '2024-25') as ledger_steps,
          (select count(*) from lineage.ledger_entries where season = '2024-25') as ledger_entries,
          (select count(*) from lineage.ledger_entries where season = '2024-25' and is_removal) as removal_entries,
          (select count(*) from lineage.master_source_bridge where season = '2024-25') as bridge_rows,
          (select count(distinct source_row_id) from lineage.master_source_bridge where season = '2024-25') as bridge_source_rows,
          (select count(distinct injury_id) from lineage.master_source_bridge where season = '2024-25') as bridge_injuries,
          (select count(*) from analysis.lineage_included_rows_v1 where season = '2024-25') as included_rows,
          (select count(*) from analysis.lineage_injury_cohort_v1 where season = '2024-25') as cohort_rows
        """
    )[0]
    expected = {
        "master_rows": 3060, "master_excluded": 755, "ledger_steps": 10,
        "ledger_entries": 3691, "removal_entries": 125, "bridge_rows": 3060,
        "bridge_source_rows": 3060, "bridge_injuries": 3060,
        "included_rows": 2301, "cohort_rows": 1866,
    }
    for key, want in expected.items():
        got = int(counts[key])
        status = "ok" if got == want else "MISMATCH"
        if got != want:
            failures.append(f"count {key}: got {got}, expected {want}")
        print(f"count {key}: {got} (expected {want}) {status}")

    rows = query(
        """
        select source_row, final_values
        from analysis.lineage_included_rows_v1
        where season = '2024-25'
        order by source_row
        """
    )
    source_rows = [int(row["source_row"]) for row in rows]
    mapping_payload = ("\n".join(str(r) for r in source_rows) + "\n").encode("utf-8")
    mapping_hash = hashlib.sha256(mapping_payload).hexdigest()
    print(f"mapping sha256: {mapping_hash}")
    if mapping_hash != EXPECTED_MAPPING_SHA256:
        failures.append("retained source-row mapping hash mismatch")

    table = []
    for row in rows:
        values = row["final_values"]
        table.append([values.get(header, "") for header in HEADERS])
    with tempfile.NamedTemporaryFile(
        "wb", suffix=".csv", dir=ROOT / "data/reporting", delete=False
    ) as handle:
        csv_path = Path(handle.name)
    EXPORT.write_csv_atomic(csv_path, HEADERS, table)
    raw = csv_path.read_bytes()
    if raw.endswith(b"\n"):
        csv_path.write_bytes(raw[:-1])
    csv_hash = hashlib.sha256(csv_path.read_bytes()).hexdigest()
    csv_path.unlink(missing_ok=True)
    print(f"inclusion csv sha256: {csv_hash}")
    if csv_hash != EXPECTED_CSV_SHA256:
        failures.append("DB-derived inclusion CSV hash mismatch")

    if failures:
        print("FAILED:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    print("Lineage DB verification passed: byte-exact against the accepted artifacts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
