from __future__ import annotations

import hashlib
import inspect
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pipeline.__main__ as pipeline


V5_TUPLE = (
    "v5",
    "reporting_classification_2026-07-22_v2",
    "analysis_window_2024-25_2026-07-25_v1",
)
V4_TUPLE = (
    "v4",
    "reporting_classification_2026-07-22_v2",
    "lineage_2024-25_2026-07-24_v1",
)


def release_args(variant: tuple[str, str, str]) -> SimpleNamespace:
    analysis_version, classification_view_version, cohort_view_version = variant
    return SimpleNamespace(
        season="2024-25",
        output="",
        snapshot_current=False,
        preflight=True,
        preflight_file="",
        preflight_reviewer="",
        previous_bundle_file="",
        analysis_version=analysis_version,
        classification_view_version=classification_view_version,
        cohort_view_version=cohort_view_version,
    )


class ReleaseLeagueV5Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = inspect.getsource(pipeline.release_league)

    def test_v5_exact_tuple_reaches_its_direct_league_candidate_view(self) -> None:
        queries: list[str] = []
        required_versions = [
            pipeline.INJURY_MASTER_LINEAGE_MIGRATION_VERSION,
            pipeline.LINEAGE_RESTATED_REPORTING_MIGRATION_VERSION,
            pipeline.LINEAGE_V4_CANDIDATE_FAST_PATH_MIGRATION_VERSION,
            pipeline.OSIICS_EXACT_REPORTING_CLASSIFICATION_MIGRATION_VERSION,
            pipeline.INCREMENTAL_CLASSIFICATION_BUNDLE_MIGRATION_VERSION,
            pipeline.ANALYSIS_WINDOW_REPORTING_V5_MIGRATION_VERSION,
            pipeline.ANALYSIS_WINDOW_V5_CANDIDATE_OPTIMIZATION_MIGRATION_VERSION,
            pipeline.ANALYSIS_WINDOW_V5_SHARED_COHORT_SNAPSHOT_MIGRATION_VERSION,
            pipeline.ANALYSIS_WINDOW_V5_CANDIDATE_SNAPSHOT_MIGRATION_VERSION,
            pipeline.ANALYSIS_WINDOW_V5_COVERAGE_SNAPSHOT_MIGRATION_VERSION,
        ]

        def query(sql: str, _values: list[object] | None = None) -> list[dict[str, str]]:
            queries.append(sql)
            if "supabase_migrations.schema_migrations" in sql:
                return [{"version": version} for version in required_versions]
            return []

        with (
            patch.object(pipeline, "run_provenance", return_value={"code_version": "test"}),
            patch.object(pipeline, "query_sql", side_effect=query),
            patch.object(
                pipeline,
                "ANALYSIS_WINDOW_V5_EXPOSURE_EVIDENCE_LOCATOR",
                pipeline.ANALYSIS_WINDOW_V5_EVIDENCE_LOCATOR,
            ),
            patch.object(
                pipeline,
                "ANALYSIS_WINDOW_V5_SQL_RECONCILIATION_LOCATOR",
                pipeline.ANALYSIS_WINDOW_V5_EVIDENCE_LOCATOR,
            ),
            patch.object(
                pipeline,
                "ANALYSIS_WINDOW_V5_CANDIDATE_PERFORMANCE_LOCATOR",
                pipeline.ANALYSIS_WINDOW_V5_EVIDENCE_LOCATOR,
            ),
        ):
            with self.assertRaisesRegex(SystemExit, "expected one complete league payload"):
                pipeline.release_league(release_args(V5_TUPLE))

        self.assertIn(
            "analysis.league_dashboard_release_candidates_analysis_window_v5",
            "\n".join(queries),
        )
        migration_query = next(
            sql for sql in queries if "supabase_migrations.schema_migrations" in sql
        )
        self.assertIn(pipeline.ANALYSIS_WINDOW_REPORTING_V5_MIGRATION_VERSION, migration_query)
        self.assertIn(
            pipeline.ANALYSIS_WINDOW_V5_CANDIDATE_OPTIMIZATION_MIGRATION_VERSION,
            migration_query,
        )
        self.assertIn(
            pipeline.ANALYSIS_WINDOW_V5_CANDIDATE_SNAPSHOT_MIGRATION_VERSION,
            migration_query,
        )
        self.assertIn(
            pipeline.ANALYSIS_WINDOW_V5_SHARED_COHORT_SNAPSHOT_MIGRATION_VERSION,
            migration_query,
        )
        self.assertIn(
            pipeline.ANALYSIS_WINDOW_V5_COVERAGE_SNAPSHOT_MIGRATION_VERSION,
            migration_query,
        )

    def test_dirty_tree_override_is_explicit_and_audited(self) -> None:
        with (
            patch.object(
                pipeline,
                "run_provenance",
                return_value={"code_version": "test-dirty"},
            ),
            patch.dict(os.environ, {}, clear=False),
        ):
            os.environ.pop("PIPELINE_ALLOW_DIRTY_RELEASE_LEAGUE", None)
            with self.assertRaisesRegex(
                SystemExit,
                "PIPELINE_ALLOW_DIRTY_RELEASE_LEAGUE=1",
            ):
                pipeline.release_league(release_args(V5_TUPLE))

        self.assertIn(
            '"dirty_worktree_override": dirty_release_override',
            self.source,
        )

    def test_dirty_tree_override_rejects_release_owned_files_only(self) -> None:
        self.assertEqual(
            pipeline.release_owned_dirty_paths(
                [
                    "components/dashboard/charts.tsx",
                    "pipeline/__main__.py",
                    "docs/evidence/example.json",
                ]
            ),
            ["docs/evidence/example.json", "pipeline/__main__.py"],
        )
        pipeline.validate_dirty_release_override(
            ["components/dashboard/charts.tsx"],
            ["components/dashboard/charts.tsx"],
        )
        with self.assertRaisesRegex(SystemExit, "unapproved paths"):
            pipeline.validate_dirty_release_override(
                [
                    "components/dashboard/charts.tsx",
                    "components/dashboard/team-dashboard.tsx",
                ],
                ["components/dashboard/charts.tsx"],
            )
        with self.assertRaisesRegex(SystemExit, "release-owned files"):
            pipeline.validate_dirty_release_override(
                ["config/teams.ts"],
                ["config/teams.ts"],
            )

    def test_v4_rollback_tuple_still_reaches_its_lineage_candidate_view(self) -> None:
        queries: list[str] = []
        required_versions = [
            pipeline.INJURY_MASTER_LINEAGE_MIGRATION_VERSION,
            pipeline.LINEAGE_RESTATED_REPORTING_MIGRATION_VERSION,
            pipeline.LINEAGE_V4_CANDIDATE_FAST_PATH_MIGRATION_VERSION,
            pipeline.OSIICS_EXACT_REPORTING_CLASSIFICATION_MIGRATION_VERSION,
            pipeline.INCREMENTAL_CLASSIFICATION_BUNDLE_MIGRATION_VERSION,
        ]

        def query(sql: str, _values: list[object] | None = None) -> list[dict[str, str]]:
            queries.append(sql)
            if "supabase_migrations.schema_migrations" in sql:
                return [{"version": version} for version in required_versions]
            return []

        with (
            patch.object(pipeline, "run_provenance", return_value={"code_version": "test"}),
            patch.object(pipeline, "query_sql", side_effect=query),
        ):
            with self.assertRaisesRegex(SystemExit, "expected one complete league payload"):
                pipeline.release_league(release_args(V4_TUPLE))

        self.assertIn(
            "analysis.league_dashboard_release_candidates_lineage_v4",
            "\n".join(queries),
        )
        self.assertNotIn(
            "analysis.league_dashboard_release_candidates_analysis_window_v5",
            "\n".join(queries),
        )

    def test_v5_release_contract_binds_semantics_evidence_and_candidate_hashes(self) -> None:
        self.assertIn(V5_TUPLE[0], self.source)
        self.assertIn(V5_TUPLE[1], self.source)
        self.assertIn("ANALYSIS_WINDOW_V5_COHORT_VIEW_VERSION", self.source)
        for view in (
            "analysis.analysis_window_injury_cohort_v5",
            "analysis.analysis_window_league_monthly_v5",
            "analysis.analysis_window_league_summary_v5",
            "analysis.league_dashboard_release_candidates_analysis_window_v5",
            "analysis.team_dashboard_release_candidates_analysis_window_v5",
        ):
            self.assertIn(view, self.source)
        self.assertNotIn(
            'semantic_monthly_view = "analysis.analysis_window_monthly_v5"',
            self.source,
        )
        for value in (
            "league_dashboard_release_v5",
            "ANALYSIS_WINDOW_LEAGUE_DASHBOARD_RELEASE_RULE_VERSION",
            "2026-07-25",
            "ANALYSIS-WINDOW-01",
            "ANALYSIS_WINDOW_V5_EVIDENCE_LOCATOR",
            "ANALYSIS_WINDOW_V5_EVIDENCE_SHA256",
            "ANALYSIS_WINDOW_REPORTING_V5_MIGRATION_VERSION",
            "ANALYSIS_WINDOW_V5_CANDIDATE_OPTIMIZATION_MIGRATION_VERSION",
            "ANALYSIS_WINDOW_V5_CANDIDATE_SNAPSHOT_MIGRATION_VERSION",
            "ANALYSIS_WINDOW_V5_SHARED_COHORT_SNAPSHOT_MIGRATION_VERSION",
            "ANALYSIS_WINDOW_V5_COVERAGE_SNAPSHOT_MIGRATION_VERSION",
            "ANALYSIS_WINDOW_V5_INJURY_AUDIT_LOCATOR",
            "ANALYSIS_WINDOW_V5_EXPOSURE_EVIDENCE_LOCATOR",
            "ANALYSIS_WINDOW_V5_SQL_RECONCILIATION_LOCATOR",
            "ANALYSIS_WINDOW_V5_CANDIDATE_PERFORMANCE_LOCATOR",
            "analysis_window_v5_evidence_sha256s",
        ):
            self.assertIn(value, self.source)
        self.assertIn(
            '"payload_candidate_validation_migration": (', self.source
        )

    def test_v5_manifest_hash_matches_the_release_gate(self) -> None:
        manifest = (
            Path(__file__).resolve().parents[1]
            / pipeline.ANALYSIS_WINDOW_V5_EVIDENCE_LOCATOR
        )
        self.assertTrue(manifest.is_file())
        self.assertEqual(
            pipeline.ANALYSIS_WINDOW_V5_EVIDENCE_SHA256,
            hashlib.sha256(manifest.read_bytes()).hexdigest(),
        )

    def test_release_cli_accepts_explicit_v5_and_keeps_v2_defaults(self) -> None:
        with (
            patch.object(pipeline, "release_league") as release,
            patch.object(
                sys,
                "argv",
                [
                    "pipeline",
                    "release-league",
                    "--preflight",
                    "--analysis-version",
                    V5_TUPLE[0],
                    "--classification-view-version",
                    V5_TUPLE[1],
                    "--cohort-view-version",
                    V5_TUPLE[2],
                ],
            ),
        ):
            pipeline.main()
        explicit = release.call_args.args[0]
        self.assertEqual(V5_TUPLE, (
            explicit.analysis_version,
            explicit.classification_view_version,
            explicit.cohort_view_version,
        ))

        with (
            patch.object(pipeline, "release_league") as release,
            patch.object(sys, "argv", ["pipeline", "release-league", "--preflight"]),
        ):
            pipeline.main()
        defaults = release.call_args.args[0]
        self.assertEqual(
            ("v2", "v2", "v2"),
            (
                defaults.analysis_version,
                defaults.classification_view_version,
                defaults.cohort_view_version,
            ),
        )

    def test_v5_rejects_a_mismatched_cohort_before_database_access(self) -> None:
        with self.assertRaisesRegex(SystemExit, "V5 requires the accepted OSIICS classification"):
            pipeline.release_league(
                release_args((V5_TUPLE[0], V5_TUPLE[1], "lineage_2024-25_2026-07-24_v1"))
            )

    def test_plan_mode_separates_access_levels_without_database_access(self) -> None:
        args = release_args(V5_TUPLE)
        args.plan = True
        args.snapshot_current = True
        output = io.StringIO()
        with (
            patch.object(pipeline, "query_sql") as query,
            patch.object(pipeline, "run_sql") as write,
            redirect_stdout(output),
        ):
            pipeline.release_league(args)
        query.assert_not_called()
        write.assert_not_called()
        plan = json.loads(output.getvalue())
        self.assertEqual(plan["database_access"], "none")
        self.assertEqual(
            [step["stage"] for step in plan["steps"]],
            [
                "local",
                "live_write",
                "read_only_live",
                "read_only_live",
                "human_review",
                "live_write",
            ],
        )
        self.assertEqual(
            plan["steps"][-1]["includes"],
            "promotion and 16-team parity export",
        )

    def test_first_safe_mismatch_covers_coverage_and_headline_denominators(self) -> None:
        dashboard = {
            "headline": [
                {"key": "recorded_injuries", "value": 10},
                {"key": "time_loss_injuries", "value": 4},
                {"key": "incidence_per_1000h", "denominator": 99},
                {"key": "burden_per_1000h", "denominator": 100},
            ],
            "coverage": {"hours": 100},
        }
        semantic = {
            "recorded_injuries": 10,
            "time_loss_injuries": 4,
            "monthly_time_loss_injuries": 4,
            "dated_time_loss_injuries": 4,
            "monthly_exposure_hours": 100,
            "exposure_hours": 100,
        }
        self.assertEqual(
            pipeline.first_release_payload_mismatch(dashboard, semantic),
            ("headline.incidence_per_1000h.denominator", 99, 100),
        )

    def test_preflight_and_promotion_write_workflow_manifests(self) -> None:
        self.assertIn("urc_league_release_preflight_manifest_v1", self.source)
        self.assertIn("reviewed_preflight_manifest_sha256", self.source)
        self.assertIn("urc_league_release_manifest_v1", self.source)
        self.assertIn("write_team_dashboard_parity_exports(", self.source)
        self.assertIn("league preflight manifest is required", self.source)
        for bound_field in (
            "candidate_views",
            "required_migrations",
            "member_input_hash",
            "league_payload_sha256",
            "team_payload_sha256s",
            "evidence_sha256s",
            "classification_evidence_sha256",
            "cohort_evidence_sha256",
            "classification_adjudications_sha256",
            "cohort_adjudications_sha256",
            "provenance",
            "dirty_worktree_paths",
        ):
            self.assertIn(f'"{bound_field}"', self.source)


if __name__ == "__main__":
    unittest.main()
