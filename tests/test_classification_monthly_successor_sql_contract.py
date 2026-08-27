"""Static and local evidence contracts for the 2024-25 successor.

These checks never connect to Postgres. They replay the immutable master rows
in memory and inspect the additive SQL so a changed or missing source row
cannot be silently accepted.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import re
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / (
    "docs/evidence/urc_2024-25_classification_monthly_successor_2026-08-26.json"
)
MASTER = ROOT / "data/2024-25/master/master_2024-25_v5.json"
MIGRATION = ROOT / (
    "supabase/migrations/20260826100000_urc_2024_25_"
    "classification_monthly_successor.sql"
)
REGISTRATION = ROOT / (
    "tools/sql/register_urc_2024_25_classification_monthly_successor_migration.sql"
)
RECONCILIATION = ROOT / (
    "tests/urc_2024_25_classification_monthly_successor_reconciliation.sql"
)
SPECIFIC_DIAGNOSIS_EVIDENCE = ROOT / "docs/evidence/urc_2024-25_specific_diagnosis_evidence.json"
SPECIFIC_DIAGNOSIS_EVIDENCE_SHA256 = (
    "a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167"
)
SPECIFIC_DIAGNOSIS_ROWS_SHA256 = (
    "8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7"
)
SOURCE_MASTER_SHA256 = (
    "15b9af0da05aa57698487f4c8ebacf9923cec4e66846ac00b76fa3c2b75f2f63"
)
ADJUDICATION_MANIFEST_SHA256 = (
    "cd5bed8cd5a98a6b5290194371fb92f01020ed8020ff3ddb859251741f349835"
)
PREDECESSOR_RELEASE_ID = "8b50b9e2-023b-4f99-b6ae-e53d8e21706e"
PREDECESSOR_BUNDLE_SHA256 = (
    "93fdd34371aac097c4364d3c64c32135fba7e3f235747b9daeb285335b330a8f"
)
PREDECESSOR_LEAGUE_SHA256 = (
    "47853342b5f999810bdb151a3e4757a982bbaf3d6b49f002ee19f53e0378cc56"
)
PREDECESSOR_TEAM_SET_SHA256 = (
    "1563ac044888003751c0294df242b4b83fec811be0779d9a4c3d65ac6163234e"
)
ACCEPTED_WORKBOOK_SHA256 = (
    "4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73"
)
ADJUDICATION_WORKBOOK_SHA256 = (
    "87ebb569afc45ef28116df98dc83c2d8799139eaecd1c249372c209fa783f155"
)
PREDECESSOR_PREFLIGHT_SHA256 = (
    "06a51c1e880f2a3b9b227e990b80b491005cf827fd12bb81c6cbb06856d5d503"
)
ACTIVE_CORRECTION_SET_SHA256 = (
    "b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051"
)
CURRENT_REVIEW_WORKBOOK_DISK_SHA256 = (
    "4f1db130f9f5aff23c3473eb2ab64a467f739a0b6ac7e4f170ca0383d9072b73"
)
SUCCESSOR_DISCLOSURE_METHOD = [
    "Overall incidence includes all eligible injury records; TL incidence includes final Time Loss injuries, including open or ongoing cases with null duration. Both use pooled exposure hours x 1,000.",
    "Severity mean, severity median and burden use known-duration Time Loss injuries only; null-duration Time Loss contributes no days until duration is known.",
    "Explicit Medical Attention and zero-day cases are closed Medical Attention on Date Injured and are excluded from Time Loss, incidence and burden.",
    "Unclassified eligible injuries count as recorded injuries only and are excluded from Time Loss, Medical Attention, severity, burden and dashboard unknown categories.",
    "Monthly assignment uses Date Injured only; undated eligible injuries remain in season totals and are excluded from monthly series.",
    "Diagnosis metrics use reviewed specific-diagnosis groups for injuries only; illnesses are excluded.",
    "IOC-aligned body-location and tissue/pathology categories remain separate accepted mappings.",
    "Exposure and rate calculations retain full stored precision; display formatting may round hours.",
]
SUCCESSOR_DISCLOSURE_LIMITATIONS = [
    "Open or ongoing Time Loss cases are counted for incidence but cannot contribute severity or burden until duration is known.",
    "Medical Attention and zero-day cases are recorded and closed on Date Injured, but never contribute to Time Loss, incidence or burden.",
    "Unclassified eligible cases are recorded only; no Time Loss, Medical Attention, severity, burden or front-facing unknown category is assigned.",
    "Only dated cases are plotted monthly from Date Injured; undated cases remain season totals only.",
    "The immutable reporting window defines numerator and denominator eligibility.",
    "Historical exposure state is retained; correction overlays do not mutate curated rows.",
    "Unknown-setting injuries are included in all-setting metrics but have no setting-specific rate.",
    "Specific diagnoses use reviewed groups; unresolved injury diagnoses remain internal unknown values and are not shown as named diagnoses.",
]
SUCCESSOR_DISCLOSURE_METHOD_SHA256 = (
    "9bd4ff3c60fb1aa33e3f4d1d1c5ff35f83bbd6cbd777aca90b6fbd3bc980de7c"
)
SUCCESSOR_DISCLOSURE_LIMITATIONS_SHA256 = (
    "d8b32c5dddb9f740d238b44e4c40d099ed671ccc58bcdc95a5310471c78b75f9"
)


def _load_replay() -> Any:
    spec = importlib.util.spec_from_file_location("urc_replay", ROOT / "tools/replay.py")
    if spec is None or spec.loader is None:
        raise ImportError("cannot load tools/replay.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _compact_hash(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _row_value_sha(headers: list[str], rows: dict[int, list[str]], source_row: int) -> str:
    values = rows[source_row]
    return _compact_hash(dict(zip(headers, values, strict=True)))


class ClassificationMonthlySuccessorContractTests(unittest.TestCase):
    def test_adjudication_values_end_before_the_evidence_view(self) -> None:
        boundary = self.sql.split(
            "create view analysis.urc_2024_25_classification_evidence_v1", 1
        )[0]
        self.assertTrue(boundary.rstrip().endswith(");"))

    @classmethod
    def setUpClass(cls) -> None:
        cls.evidence = json.loads(EVIDENCE.read_text())
        cls.specific_diagnosis_evidence = json.loads(SPECIFIC_DIAGNOSIS_EVIDENCE.read_text())
        cls.master = json.loads(MASTER.read_text())
        cls.sql = MIGRATION.read_text()
        cls.registration = REGISTRATION.read_text()
        cls.reconciliation = RECONCILIATION.read_text()
        cls.replay = _load_replay()
        cls.headers, cls.rows = cls.replay.load_master_table(cls.master)

    def test_evidence_file_and_source_master_are_pinned(self) -> None:
        self.assertEqual(
            hashlib.sha256(EVIDENCE.read_bytes()).hexdigest(),
            "0f7707e9b905ce1c604beeb2261ac18df880af9942de5093e2a564589e08e833",
        )
        self.assertEqual(hashlib.sha256(MASTER.read_bytes()).hexdigest(), SOURCE_MASTER_SHA256)
        self.assertEqual(self.evidence["source_master"]["sha256"], SOURCE_MASTER_SHA256)
        self.assertEqual(
            self.evidence["adjudication_manifest_sha256"], ADJUDICATION_MANIFEST_SHA256
        )
        self.assertEqual(self.evidence["source_row_fingerprint_field_order"], self.headers)
        self.assertIn("tools/replay.py", self.evidence["source_row_fingerprint_method"])
        self.assertIn("compact UTF-8 JSON", self.evidence["source_row_fingerprint_method"])
        self.assertEqual(
            self.evidence["predecessor_preflight"]["path"],
            "outputs/dragons_type_diagnosis_20260825/.work/served_baseline_after_dragons_type_diagnosis.json",
        )
        self.assertEqual(
            self.evidence["predecessor_preflight"]["sha256"],
            PREDECESSOR_PREFLIGHT_SHA256,
        )
        self.assertEqual(
            self.evidence["predecessor_preflight"]["embedded_candidate_canonical_bundle_sha256"],
            PREDECESSOR_BUNDLE_SHA256,
        )
        self.assertEqual(
            self.evidence["active_correction_set"]["sha256"],
            ACTIVE_CORRECTION_SET_SHA256,
        )
        provenance = self.evidence["implementation_provenance"]
        self.assertEqual(
            provenance["current_review_workbook_disk_sha256"],
            CURRENT_REVIEW_WORKBOOK_DISK_SHA256,
        )
        self.assertTrue(provenance["current_review_workbook_disk_authoritative"])
        self.assertEqual(
            provenance["authoritative_workbook_sha256"], ACCEPTED_WORKBOOK_SHA256
        )
        disclosure = self.evidence["successor_disclosure"]
        self.assertEqual(disclosure["method"], SUCCESSOR_DISCLOSURE_METHOD)
        self.assertEqual(disclosure["limitations"], SUCCESSOR_DISCLOSURE_LIMITATIONS)
        self.assertEqual(
            disclosure["method_sha256"], SUCCESSOR_DISCLOSURE_METHOD_SHA256
        )
        self.assertEqual(
            disclosure["limitations_sha256"], SUCCESSOR_DISCLOSURE_LIMITATIONS_SHA256
        )
        self.assertEqual(_compact_hash(disclosure["method"]), SUCCESSOR_DISCLOSURE_METHOD_SHA256)
        self.assertEqual(
            _compact_hash(disclosure["limitations"]),
            SUCCESSOR_DISCLOSURE_LIMITATIONS_SHA256,
        )

    def test_replay_reproduces_all_32_canonical_rows_and_locators(self) -> None:
        adjudications = self.evidence["row_adjudications"]
        self.assertEqual(len(adjudications), 32)
        self.assertEqual(len({row["source_row"] for row in adjudications}), 32)
        canonical_keys = {
            (
                self.evidence["season"],
                row["source_row"],
                row["source_row_sha256"],
            )
            for row in adjudications
        }
        self.assertEqual(len(canonical_keys), 32)

        for adjudication in adjudications:
            source_row = adjudication["source_row"]
            self.assertEqual(
                _row_value_sha(self.headers, self.rows, source_row),
                adjudication["source_row_sha256"],
            )
            locator = (
                f"2024-25|Injury Master|{source_row}|{ADJUDICATION_WORKBOOK_SHA256}"
            )
            self.assertEqual(
                hashlib.sha256(locator.encode("utf-8")).hexdigest(),
                adjudication["source_locator_fingerprint"],
            )
            without_hash = dict(adjudication)
            evidence_hash = without_hash.pop("evidence_sha256")
            self.assertEqual(_compact_hash(without_hash), evidence_hash)

        self.assertEqual(
            _compact_hash(adjudications), self.evidence["adjudication_manifest_sha256"]
        )

    def test_specific_diagnosis_evidence_is_injury_only_and_pinned(self) -> None:
        evidence = self.specific_diagnosis_evidence
        self.assertEqual(
            hashlib.sha256(SPECIFIC_DIAGNOSIS_EVIDENCE.read_bytes()).hexdigest(),
            SPECIFIC_DIAGNOSIS_EVIDENCE_SHA256,
        )
        self.assertEqual(
            evidence["schema_version"], "urc_2024-25_specific_diagnosis_evidence_v1"
        )
        self.assertEqual(evidence["mapping"]["rows_sha256"], SPECIFIC_DIAGNOSIS_ROWS_SHA256)
        injury_rows = [row for row in evidence["rows"] if row["injury_metric_eligible"]]
        self.assertEqual(len(injury_rows), 1660)
        self.assertTrue(all(row["problem_type_code"] == "injury" for row in injury_rows))
        self.assertEqual(
            evidence["aggregate_reconciliation"]["illness_rows_excluded_from_injury_metrics"],
            392,
        )

    def test_replay_fails_closed_for_changed_or_missing_master_row(self) -> None:
        source_row = self.evidence["row_adjudications"][0]["source_row"]
        changed_rows = copy.deepcopy(self.rows)
        changed_rows[source_row][0] = changed_rows[source_row][0] + " changed"
        self.assertNotEqual(
            _row_value_sha(self.headers, changed_rows, source_row),
            self.evidence["row_adjudications"][0]["source_row_sha256"],
        )
        missing_rows = copy.deepcopy(self.rows)
        del missing_rows[source_row]
        with self.assertRaises(KeyError):
            _row_value_sha(self.headers, missing_rows, source_row)

    def test_exact_adjudication_outcomes_and_preserved_source_facts(self) -> None:
        rows = self.evidence["row_adjudications"]
        self.assertEqual(
            sum(row["final_classification"] == "Time Loss" for row in rows), 15
        )
        self.assertEqual(
            sum(row["final_classification"] == "Medical Attention" for row in rows), 1
        )
        self.assertEqual(
            sum(row["final_classification"] == "unclassified" for row in rows), 16
        )
        self.assertEqual(sum(row["source_value"] == "" for row in rows), 29)
        self.assertEqual(sum(row["source_value"] == "FALSE" for row in rows), 3)
        self.assertTrue(all(row["classification_origin"] == "adjudicated" for row in rows))
        self.assertTrue(all(row["reviewer"] == "Abdel Babiker" for row in rows))
        self.assertTrue(all("Player" not in json.dumps(row) for row in rows))

    def test_successor_sql_is_additive_and_contract_bound(self) -> None:
        lower_sql = self.sql.lower()
        self.assertIn("season text not null default '2024-25'", lower_sql)
        adjudication_sql = self.sql.split(
            "insert into audit.urc_2024_25_classification_adjudications_v1", 1
        )[1]
        self.assertEqual(len(re.findall(r"(?m)^  \(\d+,", adjudication_sql)), 32)
        self.assertNotIn("from analysis.urc_2024_25_team_contact_distribution_v1 x\n        ), '[]'::jsonb),\n    )", lower_sql)
        self.assertNotIn("from analysis.urc_2024_25_league_contact_distribution_v1 x\n      ), '[]'::jsonb),\n    )", lower_sql)
        self.assertEqual(
            re.findall(r"create\s+or\s+replace\s+view\s+([\w.]+)", lower_sql),
            [
                "analysis.team_dashboard_release_candidates_analysis_window_v5",
                "analysis.league_dashboard_release_candidates_analysis_window_v5",
            ],
        )
        self.assertNotRegex(
            lower_sql, r"(?m)^\s*(drop|truncate|delete|update)\s"
        )
        self.assertGreaterEqual(lower_sql.count("'method', jsonb_build_array("), 2)
        self.assertGreaterEqual(lower_sql.count("'limitations', jsonb_build_array("), 2)
        for token in (
            "audit.urc_2024_25_classification_adjudications_v1",
            "audit.urc_2024_25_specific_diagnosis_mappings_v1",
            "source_identity",
            "source_row_sha256",
            "final_classification",
            "classification_origin",
            "duration_usable",
            "closure_status",
            "Date Injured",
            "date_injured",
            "recorded_injuries",
            "time_loss_injuries",
            "known_duration_time_loss_injuries",
            "urc_2024_25_team_dashboard_candidate_v1",
            "urc_2024_25_league_dashboard_candidate_v1",
            "assert_urc_2024_25_classification_successor_v1",
            "successor_disclosure_method_sha256",
            "successor_disclosure_limitations_sha256",
            "'method', jsonb_build_array(",
            "'limitations', jsonb_build_array(",
            "open or ongoing time loss",
            "zero-day cases are closed medical attention",
            "unclassified eligible cases are recorded only",
            "monthly assignment uses date injured only",
            "canonical_problem_type = 'injury'",
            "coalesce(m.diagnosis_group_code, 'unknown')",
            "'all'::text",
            "union all",
        ):
            self.assertIn(token.lower(), lower_sql)
        for value in (
            PREDECESSOR_RELEASE_ID,
            PREDECESSOR_BUNDLE_SHA256,
            PREDECESSOR_LEAGUE_SHA256,
            PREDECESSOR_TEAM_SET_SHA256,
            ACCEPTED_WORKBOOK_SHA256,
            ADJUDICATION_WORKBOOK_SHA256,
            ADJUDICATION_MANIFEST_SHA256,
            SOURCE_MASTER_SHA256,
        ):
            self.assertIn(value, self.sql + self.registration)
        for value in (
            "old_recorded <> 1662",
            "old_time_loss <> 787",
            "old_days <> 17575",
            "new_recorded <> 1662",
            "new_days <> 17575",
            "source_reported_null_time_loss",
            "source_reported_null_time_loss <> 111",
            "new_time_loss <> 913",
            "new_time_loss <> old_time_loss + source_reported_null_time_loss",
            "+ adjudicated_null_duration_time_loss",
            "adjudicated_null_duration_time_loss",
            "team_recorded <> new_recorded",
            "team_time_loss <> new_time_loss",
            "team_days <> new_days",
            "f.source_row = a.source_row",
            "adjudication.source_row = parsed.source_row",
            "lineage.master_rows",
            "lineage.baselines",
            "master.row_values ->> 'timeloss vs medical attention'",
            "adjudication.source_value <>",
            "analysis.row_correction_subject_v3(",
            SOURCE_MASTER_SHA256,
            "f.date_injured is not null",
            "'open/ongoing'",
            "'closed'",
            "'unclassified'",
            "'distance_km'",
        ):
            self.assertIn(value.lower(), lower_sql)
        self.assertNotIn("new_time_loss <> old_time_loss + 15", lower_sql)
        self.assertNotIn("f.source_row_sha256 = a.source_row_sha256", lower_sql)
        self.assertRegex(
            lower_sql,
            r"league_metrics_v1\)\s*<>\s*787",
        )
        self.assertNotIn("analysis.row_correction_subject_v1(", lower_sql)
        self.assertIn(ACTIVE_CORRECTION_SET_SHA256, self.sql + self.registration)
        self.assertIn("ingestion_source_row_sha256", lower_sql)
        self.assertIn("active_correction_set_sha256", lower_sql)
        self.assertIn(SPECIFIC_DIAGNOSIS_EVIDENCE_SHA256, self.sql + self.registration)
        self.assertIn(SPECIFIC_DIAGNOSIS_ROWS_SHA256, self.sql + self.registration)
        self.assertEqual(lower_sql.count("create materialized view analysis.urc_2024_25_"), 3)
        self.assertIn("'01 ' || (item ->> 'month')", self.sql)
        self.assertNotIn("'01 ' || item ->> 'month'", self.sql)
        self.assertNotIn("min(source_item)", lower_sql)
        self.assertNotIn("reporting.canonical_jsonb_sha256_v1(", lower_sql)
        self.assertNotIn(
            "m.source_row_sha256 = f.ingestion_source_row_sha256", lower_sql
        )
        self.assertIn(
            "cohort.final_values ->> 'timeloss vs medical attention'", lower_sql
        )

    def test_every_injury_section_reads_final_classification_fact(self) -> None:
        lower_sql = self.sql.lower()
        for view_name in (
            "urc_2024_25_team_injury_metrics_v1",
            "urc_2024_25_team_setting_metrics_v1",
            "urc_2024_25_team_profiles_v1",
            "urc_2024_25_team_severity_distribution_v1",
            "urc_2024_25_team_contact_distribution_v1",
            "urc_2024_25_team_monthly_v1",
            "urc_2024_25_league_metrics_v1",
            "urc_2024_25_league_setting_metrics_v1",
            "urc_2024_25_league_profiles_v1",
            "urc_2024_25_league_severity_distribution_v1",
            "urc_2024_25_league_contact_distribution_v1",
            "urc_2024_25_league_monthly_v1",
        ):
            self.assertIn(f"create view analysis.{view_name}", lower_sql)
        self.assertGreaterEqual(lower_sql.count("final_classification = 'time loss'"), 12)
        self.assertNotIn(
            "union all\n  select f.curated_build_id, f.team_key, f.season, 'all'::text,\n    count(*)",
            lower_sql,
        )
        self.assertIn("where f.date_injured is not null", lower_sql)
        self.assertNotIn("confirmed_return_date", lower_sql)

    def test_registration_binds_final_migration_and_evidence_hashes(self) -> None:
        migration_sha = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
        evidence_sha = hashlib.sha256(EVIDENCE.read_bytes()).hexdigest()
        self.assertIn(f"migration_sha256={migration_sha}", self.registration)
        self.assertIn(f"'{evidence_sha}'::text", self.sql)
        self.assertIn(
            f"evidence_file_sha256={evidence_sha}",
            self.registration,
        )
        self.assertIn(
            f"successor_disclosure_method_sha256={SUCCESSOR_DISCLOSURE_METHOD_SHA256}",
            self.registration,
        )
        self.assertIn(
            f"successor_disclosure_limitations_sha256={SUCCESSOR_DISCLOSURE_LIMITATIONS_SHA256}",
            self.registration,
        )
        self.assertIn(f"adjudication_manifest_sha256={ADJUDICATION_MANIFEST_SHA256}", self.registration)
        self.assertIn("active_correction_set_hash=", self.registration)
        self.assertIn(
            f"active_correction_set_hash={ACTIVE_CORRECTION_SET_SHA256}",
            self.registration,
        )
        self.assertIn("successor_analysis_version=v5", self.registration)
        self.assertIn("successor_classification_view_version=reporting_classification_2024-25_2026-08-27_v1", self.registration)
        self.assertIn("successor_cohort_view_version=analysis_window_2024-25_2026-07-25_v1", self.registration)

    def test_read_only_reconciliation_reports_without_mutation(self) -> None:
        lower = self.reconciliation.lower()
        self.assertIn("predecessor_time_loss_injuries", lower)
        self.assertIn("source_reported_null_duration_time_loss", lower)
        self.assertIn("adjudicated_null_duration_time_loss", lower)
        self.assertIn("time_loss_total_reconciles", lower)
        self.assertIn("monthly_recorded_reconciles", lower)
        self.assertIn("monthly_time_loss_reconciles", lower)
        self.assertIn("diagnosis_excludes_illness", lower)
        self.assertIn("diagnosis_time_loss_reconciles", lower)
        self.assertIn("8b50b9e2-023b-4f99-b6ae-e53d8e21706e", lower)
        self.assertNotRegex(
            lower, r"(?m)^\s*(insert|update|delete|drop|truncate|alter)\s"
        )


if __name__ == "__main__":
    unittest.main()
