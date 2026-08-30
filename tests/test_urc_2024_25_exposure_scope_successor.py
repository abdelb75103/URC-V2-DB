from __future__ import annotations

import hashlib
import importlib.util
import json
import re
from pathlib import Path
import unittest

from pipeline.season_contracts import FROZEN_2024_25_RELEASE_TUPLES


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/evidence/urc_2024-25_exposure_scope_successor_2026-08-30.json"
GENERATOR = ROOT / "tools/generate_2024_25_exposure_scope_successor.py"
MIGRATION = ROOT / "supabase/migrations/20260830120000_urc_2024_25_exposure_scope_successor.sql"
PIPELINE = ROOT / "pipeline/__main__.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("exposure_scope_successor", GENERATOR)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {GENERATOR}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ExposureScopeSuccessorContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.pipeline = PIPELINE.read_text(encoding="utf-8")
        cls.generator = load_generator()

    def test_evidence_pins_reconciliation_totals_and_hashes(self) -> None:
        successor = self.evidence["successor"]
        self.assertEqual(
            (successor["excluded_rows"], successor["excluded_hours"]),
            (1238, "1444.576389"),
        )
        self.assertEqual(
            (successor["included_rows"], successor["included_hours"]),
            (63273, "79908.343109"),
        )
        self.assertEqual(
            self.evidence["v5_replay"],
            {"rows": 64511, "hours": "81352.919497"},
        )
        self.assertEqual(
            successor["excluded_by_team"],
            {
                "cardiff": {"rows": 341, "hours": "363.778333"},
                "dragons": {"rows": 91, "hours": "96.833333"},
                "edinburgh": {"rows": 391, "hours": "524.938611"},
                "glasgow": {"rows": 40, "hours": "60.797778"},
                "ospreys": {"rows": 235, "hours": "254.391667"},
                "scarlets": {"rows": 140, "hours": "143.836667"},
            },
        )
        self.assertEqual(
            successor["excluded_by_reason"],
            {
                "academy_or_age_grade": {"rows": 423, "hours": "567.251944"},
                "explicit_non_urc_match": {"rows": 775, "hours": "816.526667"},
                "other_named_non_cohort": {"rows": 40, "hours": "60.797778"},
            },
        )
        self.assertEqual(
            successor["decision_rowset_sha256"],
            "672f788e8fea5220fe30a8742eca6b1561a2ad092a545667a5ab50a697fa4086",
        )
        self.assertEqual(
            successor["retained_rowset_sha256"],
            "5cd015547c05a3910e4743e8a3b705b4cf718982ec76df55b8fc4bf6625d3075",
        )
        self.assertEqual(
            hashlib.sha256(EVIDENCE.read_bytes()).hexdigest(),
            "a56372cc531076ab00102413417fabd08d289fa296afed4f244b2db2d1132010",
        )

    def test_generator_and_sql_keep_the_six_exact_context_rules(self) -> None:
        reason = self.generator.successor_reason
        cases = (
            ("cardiff", "academy_or_age_grade", {"Competition": "Age Grade"}),
            ("cardiff", "explicit_non_urc_match", {"session type": "Match", "Competition": "Europe Challenge Cup"}),
            ("dragons", "explicit_non_urc_match", {"session type": "Match", "Competition": "Europe Challenge Cup"}),
            ("edinburgh", "academy_or_age_grade", {"session type": "Academy Training"}),
            ("glasgow", "other_named_non_cohort", {"Training With": "Scottish Prem"}),
            ("ospreys", "explicit_non_urc_match", {"session type": "SRC Match"}),
            ("ospreys", "explicit_non_urc_match", {"session type": "Match", "Competition": "Friendly"}),
            ("scarlets", "explicit_non_urc_match", {"session type": "Match", "Competition": "Friendly"}),
        )
        for team, expected, fields in cases:
            with self.subTest(team=team, fields=fields):
                self.assertEqual(reason(team, fields), expected)

        for team, fields in (
            ("cardiff", {"Competition": "age grade"}),
            ("cardiff", {"session type": "Training", "Competition": "Europe Challenge Cup"}),
            ("dragons", {"session type": "Match", "Competition": "Friendly"}),
            ("edinburgh", {"session type": "Academy"}),
            ("glasgow", {"Training With": "Scottish prem"}),
            ("ospreys", {"session type": "Match", "Competition": "SRC"}),
            ("scarlets", {"session type": "SRC Match", "Competition": "Friendly"}),
            ("leinster", {"session type": "Match", "Competition": "Europe Challenge Cup"}),
        ):
            with self.subTest(team=team, fields=fields):
                self.assertIsNone(reason(team, fields))

        self.assertRegex(
            self.sql,
            r"exposure\.team_key = 'cardiff'\s+and source\.source_values ->> 'Competition' = 'Age Grade'",
        )
        for team in ("edinburgh", "glasgow", "dragons", "ospreys", "scarlets"):
            self.assertIn(f"exposure.team_key = '{team}'", self.sql)
        self.assertIn("'Academy Training', 'Academy Units', 'Academy Units & Training'", self.sql)
        self.assertIn("'Europe Challenge Cup', 'Pro 14', 'SRC'", self.sql)
        self.assertIn("'Europe Challenge Cup', 'Friendly'", self.sql)
        self.assertNotIn("ilike", self.sql.lower())

    def test_decisions_are_append_only_and_successor_does_not_mutate_prior_rows(self) -> None:
        table = "audit.urc_2024_25_exposure_scope_decisions_v1"
        self.assertIn(f"create table {table} (", self.sql)
        self.assertIn("exposure_id uuid primary key", self.sql)
        self.assertIn("source_row_id uuid not null unique", self.sql)
        self.assertIn("reason_code text not null check (reason_code in (", self.sql)
        self.assertIn("alter table audit.urc_2024_25_exposure_scope_decisions_v1 enable row level security", self.sql)
        self.assertIn(
            "create trigger urc_2024_25_exposure_scope_decisions_v1_immutable\n"
            "before update or delete on audit.urc_2024_25_exposure_scope_decisions_v1\n"
            "for each row execute function audit.reject_reporting_cohort_rule_adjudication_v3_mutation();",
            self.sql,
        )
        self.assertNotRegex(self.sql.lower(), r"(?:update|delete)\s+audit\.urc_2024_25_exposure_scope_decisions_v1")
        self.assertIn("from analysis.analysis_window_effective_exposure_cohort_v5_snapshot", self.sql)
        self.assertIn("join ingestion.source_rows source", self.sql)
        self.assertNotIn("update ingestion", self.sql.lower())
        self.assertNotIn("update curated", self.sql.lower())
        self.assertNotIn("delete from ingestion", self.sql.lower())
        self.assertNotIn("delete from curated", self.sql.lower())

    def test_tuple_candidate_paths_semantic_views_and_allowed_sections_are_bound(self) -> None:
        successor_tuple = (
            "v5",
            "reporting_classification_2024-25_2026-08-27_v1",
            "analysis_window_2024-25_2026-08-30_v2",
        )
        self.assertIn(successor_tuple, FROZEN_2024_25_RELEASE_TUPLES)
        self.assertIn(
            'URC_2024_25_EXPOSURE_SCOPE_SUCCESSOR_MIGRATION_VERSION = "20260830120000"',
            self.pipeline,
        )
        self.assertIn(
            'URC_2024_25_EXPOSURE_SCOPE_COHORT_VIEW_VERSION = "analysis_window_2024-25_2026-08-30_v2"',
            self.pipeline,
        )
        self.assertIn(
            "required_migrations.append(\n                    URC_2024_25_EXPOSURE_SCOPE_SUCCESSOR_MIGRATION_VERSION",
            self.pipeline,
        )
        for view in (
            "analysis.urc_2024_25_effective_exposure_scope_v1",
            "analysis.urc_2024_25_exposure_scope_team_v1",
            "analysis.urc_2024_25_exposure_scope_monthly_v1",
            "analysis.urc_2024_25_exposure_scope_league_summary_v1",
            "analysis.urc_2024_25_exposure_scope_league_monthly_v1",
            "analysis.urc_2024_25_team_dashboard_candidate_v4",
            "analysis.urc_2024_25_league_dashboard_candidate_v4",
        ):
            self.assertIn(view, self.sql)
        for candidate_view in (
            "analysis.team_dashboard_release_candidates_analysis_window_v5",
            "analysis.league_dashboard_release_candidates_analysis_window_v5",
        ):
            self.assertIn(f"create or replace view {candidate_view}", self.sql)
            self.assertIn(candidate_view, self.pipeline)
        self.assertIn("analysis.urc_2024_25_exposure_scope_league_monthly_v1", self.pipeline)
        self.assertIn("analysis.urc_2024_25_exposure_scope_league_summary_v1", self.pipeline)
        self.assertIn("URC_2024_25_EXPOSURE_SCOPE_MIGRATION_SHA256", self.pipeline)
        self.assertIn(
            "5cd015547c05a3910e4743e8a3b705b4cf718982ec76df55b8fc4bf6625d3075",
            self.sql,
        )
        self.assertEqual(
            self.sql.count("from analysis.urc_2024_25_team_dashboard_candidate_v3;"),
            1,
        )
        self.assertEqual(
            self.sql.count("from analysis.urc_2024_25_league_dashboard_candidate_v3;"),
            1,
        )

        compact_sql = re.sub(r"\s+", "", self.sql)
        allowed = (
            "array['coverage','headline','monthly','body_locations','injury_types',"
            "'injury_profiles','injury_type_families','setting_split','setting_metrics']"
        )
        self.assertEqual(compact_sql.count(allowed), 4)


if __name__ == "__main__":
    unittest.main()
