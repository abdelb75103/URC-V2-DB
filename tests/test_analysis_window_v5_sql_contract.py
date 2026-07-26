from __future__ import annotations

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260725190000_analysis_window_reporting_v5.sql"
OPTIMIZATION_MIGRATION = (
    ROOT
    / "supabase/migrations/20260726010000_analysis_window_v5_candidate_query_optimization.sql"
)
SNAPSHOT_MIGRATION = (
    ROOT
    / "supabase/migrations/20260726020000_analysis_window_v5_release_candidate_snapshots.sql"
)
SHARED_COHORT_SNAPSHOT_MIGRATION = (
    ROOT
    / "supabase/migrations/20260726015000_analysis_window_v5_shared_cohort_snapshots.sql"
)
SNAPSHOT_REFRESH = (
    ROOT / "tools/sql/refresh_analysis_window_v5_candidate_snapshots.sql"
)
V4_MIGRATION = ROOT / "supabase/migrations/20260724181000_lineage_restated_reporting_v4.sql"
V4_FAST_PATH = ROOT / "supabase/migrations/20260724190000_lineage_v4_candidate_fast_path.sql"
RECONCILIATION = ROOT / "tests/analysis_window_v5_sql_reconciliation.sql"
PERFORMANCE = ROOT / "tests/analysis_window_v5_candidate_performance.sql"
TEAM_PERFORMANCE = ROOT / "tests/analysis_window_v5_team_candidate_performance.sql"
EXPOSURE_EXTRACTION = ROOT / "tools/sql/analysis_window_v5_exposure_evidence.sql"
EXPOSURE_EVIDENCE_SCHEMA = (
    ROOT / "docs/evidence/analysis_window_2024-25_v5_exposure_cohort_evidence.schema.json"
)


class AnalysisWindowV5SqlContractTests(unittest.TestCase):
    """Static contracts for the additive, unapplied V5 reporting migration.

    Runtime figures deliberately live in the read-only reconciliation query,
    not as SQL output constants. That query is intended to be run only after
    the exact reviewed migration has been applied to the approved database.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.optimization = OPTIMIZATION_MIGRATION.read_text(encoding="utf-8")
        cls.snapshot = SNAPSHOT_MIGRATION.read_text(encoding="utf-8")
        cls.shared_snapshot = SHARED_COHORT_SNAPSHOT_MIGRATION.read_text(
            encoding="utf-8"
        )
        cls.snapshot_refresh = SNAPSHOT_REFRESH.read_text(encoding="utf-8")
        cls.v4 = V4_MIGRATION.read_text(encoding="utf-8")
        cls.v4_fast_path = V4_FAST_PATH.read_text(encoding="utf-8")
        cls.reconciliation = RECONCILIATION.read_text(encoding="utf-8")
        cls.performance = PERFORMANCE.read_text(encoding="utf-8")
        cls.team_performance = TEAM_PERFORMANCE.read_text(encoding="utf-8")
        cls.exposure_extraction = EXPOSURE_EXTRACTION.read_text(encoding="utf-8")
        cls.exposure_evidence_schema = json.loads(
            EXPOSURE_EVIDENCE_SCHEMA.read_text(encoding="utf-8")
        )

    def test_immutable_v5_window_and_accepted_adjudication_are_bound(self) -> None:
        self.assertIn("'analysis_window_2024-25_2026-07-25_v1'", self.sql)
        self.assertIn("date '2024-09-01'", self.sql)
        self.assertIn("date '2025-06-30'", self.sql)
        self.assertIn("'ANALYSIS-WINDOW-01'", self.sql)
        self.assertIn(
            "c9530c949c60ff4abe91753571dfed6dd9d1146f33cc466dfbbc7fdeddb8443d",
            self.sql,
        )
        self.assertIn("docs/evidence/analysis_window_2024-25_v5.json", self.sql)
        self.assertIn("'20260725190000'", self.sql)
        self.assertIn("create view analysis.accepted_analysis_window_cohort_rules_v5", self.sql)
        self.assertIn("having count(*) = 1", self.sql)

    def test_effective_exposure_cohort_preserves_historical_state(self) -> None:
        self.assertIn(
            "create view analysis.analysis_window_effective_exposure_cohort_v5",
            self.sql,
        )
        for column in (
            "source_row_id",
            "historical_eligibility_status",
            "historical_exclusion_reasons",
            "effective_eligibility_status",
            "effective_exclusion_reasons",
            "outside_official_analysis_window_removed",
            "rejected_by_pre_urc_match_rule",
            "pre_urc_match_rule_rejected",
            "pre_urc_match_evidence_class",
            "pre_urc_match_evidence_value",
            "stable_source_row_id",
            "exposure_hours",
            "rule_basis_code",
            "effective_period_start",
            "effective_period_end",
            "reporting_grain",
            "rule_basis",
        ):
            self.assertIn(column, self.sql)
        self.assertIn("cardinality(s.historical_exclusion_reasons) = 1", self.sql)
        self.assertIn("'outside_official_analysis_window'", self.sql)
        self.assertIn("when e.grain = 'weekly' then 6 else 0 end", self.sql)
        self.assertIn("array_append(", self.sql)
        self.assertIn("and s.is_sole_window_historical_exclusion", self.sql)
        self.assertIn("else e.historical_exclusion_reasons", self.sql)
        self.assertNotIn("else array_remove(", self.sql)

    def test_pre_urc_rule_is_narrow_semantic_and_has_sharks_exception(self) -> None:
        self.assertIn("date '2024-09-19'", self.sql)
        self.assertIn("friendly|fixture|opposition|opponent|vs|versus", self.sql)
        self.assertIn("currie[[:space:]-]*cup", self.sql)
        self.assertIn("warm[[:space:]-]*up|top[[:space:]-]*up", self.sql)
        self.assertIn("captain.?s[[:space:]-]*run|game[[:space:]-]*[0-9]+", self.sql)
        self.assertIn("game[[:space:]]*\\([^)]*[[:alpha:]][^)]*\\)", self.sql)
        self.assertIn("p.team_key = 'sharks'", self.sql)
        self.assertIn("date '2024-09-08', date '2024-09-14'", self.sql)
        self.assertIn("s.is_sole_window_historical_exclusion", self.sql)
        self.assertIn("s.overlaps_pre_urc_band", self.sql)
        self.assertNotIn("pre[[:space:]-]*season", self.sql)
        emitted_classes = {
            "explicit_match",
            "explicit_friendly",
            "explicit_opponent_fixture",
            "semantic_non_urc_match",
            "verified_currie_cup_match",
        }
        input_contract = self.exposure_evidence_schema["input_contract"]
        self.assertEqual(
            emitted_classes,
            set(input_contract["semantic_evidence_classes"]),
        )
        for required_column in input_contract["required_columns"]:
            self.assertIn(required_column, self.sql)
        for evidence_class in emitted_classes:
            self.assertIn(f"'{evidence_class}'", self.sql)
        for invalid_class in (
            "verified_sharks_currie_cup_date",
            "explicit_pre_urc_match_scope",
            "opponent_game_scope",
        ):
            self.assertNotIn(invalid_class, self.sql)
        self.assertIn(
            "when not (\n"
            "        s.is_sole_window_historical_exclusion\n"
            "        and s.period_overlaps_window\n"
            "        and s.overlaps_pre_urc_band\n"
            "        and s.has_definite_pre_urc_match_evidence\n"
            "      ) then null",
            self.sql,
        )

    def test_injury_monthly_and_exposure_successors_share_v5_identity(self) -> None:
        for view in (
            "analysis_window_injury_cohort_v5",
            "analysis_window_monthly_v5",
            "analysis_window_team_summary_v5",
            "analysis_window_league_summary_v5",
            "team_dashboard_payload_analysis_window_v5",
            "league_dashboard_payload_analysis_window_v5",
        ):
            self.assertIn(f"analysis.{view}", self.sql)
        monthly = self.sql.split(
            "create view analysis.analysis_window_monthly_v5", 1
        )[1].split("create view analysis.analysis_window_severity_distribution_v5", 1)[0]
        self.assertEqual(
            2,
            monthly.count("'analysis_window_2024-25_2026-07-25_v1'"),
        )
        self.assertIn("and date_injured is not null", monthly)
        self.assertIn("analysis_window_effective_exposure_cohort_v5", monthly)
        self.assertIn("analysis_window_injury_cohort_v5", monthly)

    def test_injury_date_and_days_parsers_match_the_accepted_v4_lineage(self) -> None:
        for parser_literal in (
            r"~ '^\d{2}/\d{2}/\d{4}$'",
            r"~ '^\d+(\.0+)?$'",
        ):
            self.assertIn(parser_literal, self.sql)
            self.assertIn(parser_literal, self.v4)
        self.assertNotIn(r"~ '^\\d{2}/\\d{2}/\\d{4}$'", self.sql)
        self.assertNotIn(r"~ '^\\d+(\\.0+)?$'", self.sql)

    def test_fixture_derived_match_hours_are_not_reimplemented_from_labels(self) -> None:
        hours = self.sql.split(
            "create view analysis.exposure_hours_by_build_analysis_window_v5", 1
        )[1].split("create view analysis.analysis_window_team_summary_v5", 1)[0]
        self.assertIn("from curated.fixtures f", hours)
        self.assertIn("coalesce(f.matches_played, 0) * 20.0 as match_hours", hours)
        self.assertIn("e.total_hours - coalesce(f.matches_played, 0) * 20.0", hours)

    def test_v5_uses_direct_candidates_and_preserves_the_v4_fast_path(self) -> None:
        self.assertIn(
            "create view analysis.team_dashboard_release_candidates_analysis_window_v5",
            self.sql,
        )
        self.assertIn(
            "create view analysis.league_dashboard_release_candidates_analysis_window_v5",
            self.sql,
        )
        self.assertIn(
            "join analysis.league_dashboard_release_candidates_analysis_window_v5",
            self.sql,
        )
        self.assertIn(
            "left join analysis.team_dashboard_release_candidates_analysis_window_v5",
            self.sql,
        )
        self.assertIn("elsif target_analysis_version = 'v4' then", self.sql)
        self.assertIn(
            "analysis.league_dashboard_release_candidates_lineage_v4",
            self.sql,
        )
        self.assertIn(
            "analysis.team_dashboard_release_candidates_lineage_v4",
            self.sql,
        )
        self.assertIn("context.analysis_version <> 'v4'", self.sql)
        self.assertIn("context.analysis_version <> 'v5'", self.sql)
        self.assertIn("V4 releases against the lineage candidate view", self.v4_fast_path)

    def test_v5_payloads_materialise_shared_components_once_per_candidate(self) -> None:
        team_payload = self.optimization.split(
            "create or replace view analysis.team_dashboard_payload_analysis_window_v5",
            1,
        )[1].split(
            "create or replace view analysis.league_dashboard_payload_analysis_window_v5",
            1,
        )[0]
        league_payload = self.optimization.split(
            "create or replace view analysis.league_dashboard_payload_analysis_window_v5",
            1,
        )[1].split(
            "create view analysis.team_dashboard_release_candidates_analysis_window_v5",
            1,
        )[0]
        for payload in (team_payload, league_payload):
            for cte in (
                "effective_profiles_data as materialized",
                "diagnosis_data as materialized",
                "setting_data as materialized",
                "monthly_data as materialized",
                "severity_data as materialized",
                "summary_data as materialized",
            ):
                self.assertIn(cte, payload)
            self.assertEqual(2, payload.count("from setting_data x"))
            self.assertEqual(1, payload.count("from monthly_data x"))
            self.assertEqual(1, payload.count("from severity_data x"))
        self.assertIn("exposure_data as materialized", team_payload)
        self.assertIn("join summary_data s", team_payload)
        self.assertIn("join exposure_data e", team_payload)
        self.assertIn("from summary_data h", league_payload)

    def test_v5_optimization_changes_execution_only_not_payload_semantics(self) -> None:
        base_team = self.sql.split(
            "create view analysis.team_dashboard_payload_analysis_window_v5", 1
        )[1].split(
            "create view analysis.league_dashboard_payload_analysis_window_v5", 1
        )[0]
        optimized_team = self.optimization.split(
            "create or replace view analysis.team_dashboard_payload_analysis_window_v5",
            1,
        )[1].split(
            "create or replace view analysis.league_dashboard_payload_analysis_window_v5",
            1,
        )[0]
        base_league = self.sql.split(
            "create view analysis.league_dashboard_payload_analysis_window_v5", 1
        )[1].split("-- Direct V5 branches", 1)[0]
        optimized_league = self.optimization.split(
            "create or replace view analysis.league_dashboard_payload_analysis_window_v5",
            1,
        )[1].split("comment on view analysis.team_dashboard_payload", 1)[0]

        def normalize(
            definition: str, replacements: dict[str, str]
        ) -> str:
            cte_start = definition.index("\nwith effective_profiles_data as materialized")
            body_start = definition.index("), body as (", cte_start)
            definition = (
                definition[:cte_start]
                + "\nwith body as ("
                + definition[body_start + len("), body as (") :]
            )
            for optimized, original in replacements.items():
                definition = definition.replace(optimized, original)
            return definition.strip()

        self.assertEqual(
            base_team.strip(),
            normalize(
                optimized_team,
                {
                    "from effective_profiles_data p":
                        "from analysis.analysis_window_effective_injury_profiles_v5 p",
                    "from diagnosis_data p":
                        "from analysis.analysis_window_diagnosis_profiles_v5 p",
                    "from setting_data x":
                        "from analysis.analysis_window_setting_split_v5 x",
                    "from monthly_data x":
                        "from analysis.analysis_window_monthly_v5 x",
                    "from severity_data x":
                        "from analysis.analysis_window_severity_distribution_v5 x",
                    "join summary_data s":
                        "join analysis.analysis_window_team_summary_v5 s",
                    "join exposure_data e":
                        "join analysis.exposure_hours_by_build_analysis_window_v5 e",
                },
            ),
        )
        self.assertEqual(
            base_league.strip(),
            normalize(
                optimized_league,
                {
                    "from effective_profiles_data p":
                        "from analysis.analysis_window_league_effective_injury_profiles_v5 p",
                    "from diagnosis_data p":
                        "from analysis.analysis_window_league_diagnosis_profiles_v5 p",
                    "from setting_data x":
                        "from analysis.analysis_window_league_setting_split_v5 x",
                    "from monthly_data x":
                        "from analysis.analysis_window_league_monthly_v5 x",
                    "from severity_data x":
                        "from analysis.analysis_window_league_severity_distribution_v5 x",
                    "from summary_data h":
                        "from analysis.analysis_window_league_summary_v5 h",
                },
            ),
        )

    def test_v5_release_candidates_read_exact_build_pinned_snapshots(self) -> None:
        for view in (
            "analysis.team_dashboard_payload_analysis_window_v5_snapshot",
            "analysis.league_dashboard_payload_analysis_window_v5_snapshot",
        ):
            self.assertIn(f"create materialized view {view}", self.snapshot)
        self.assertIn(
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v5",
            self.snapshot,
        )
        self.assertIn(
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v5",
            self.snapshot,
        )
        self.assertIn(
            "from analysis.team_dashboard_payload_analysis_window_v5_snapshot",
            self.snapshot,
        )
        self.assertIn(
            "from analysis.league_dashboard_payload_analysis_window_v5_snapshot",
            self.snapshot,
        )
        self.assertIn(
            "set transaction isolation level repeatable read",
            self.snapshot,
        )
        self.assertIn(
            "V5 team candidate snapshot must contain exactly 16 teams",
            self.snapshot,
        )
        self.assertIn(
            "V5 league candidate snapshot must contain exactly one row",
            self.snapshot,
        )
        self.assertIn(
            "full join analysis.league_member_releases_v2 member",
            self.snapshot,
        )
        self.assertLess(
            self.snapshot.index("raise exception 'V5 candidate snapshots"),
            self.snapshot.index(
                "create or replace view analysis.team_dashboard_release_candidates"
            ),
        )
        for required in (
            "set transaction isolation level repeatable read",
            "refresh materialized view",
            "V5 team candidate snapshot must contain exactly 16 teams",
            "V5 league candidate snapshot must contain exactly one row",
            "full join analysis.league_member_releases_v2 member",
            "V5 candidate snapshots do not match the approved tuple",
        ):
            self.assertIn(required, self.snapshot_refresh)
        refresh_order = [
            self.snapshot_refresh.index(name)
            for name in (
                "analysis.analysis_window_injury_cohort_v5_snapshot",
                "analysis.analysis_window_reporting_classification_v5_snapshot",
                "analysis.analysis_window_effective_exposure_cohort_v5_snapshot",
                "analysis.team_dashboard_payload_analysis_window_v5_snapshot",
                "analysis.league_dashboard_payload_analysis_window_v5_snapshot",
            )
        ]
        self.assertEqual(sorted(refresh_order), refresh_order)

    def test_v5_shared_cohorts_are_snapshotted_once_without_metric_drift(self) -> None:
        self.assertIn(
            "set transaction isolation level repeatable read",
            self.shared_snapshot,
        )
        self.assertEqual(3, self.shared_snapshot.count("with no data;"))
        for view in (
            "analysis.analysis_window_injury_cohort_v5_snapshot",
            "analysis.analysis_window_reporting_classification_v5_snapshot",
            "analysis.analysis_window_effective_exposure_cohort_v5_snapshot",
        ):
            self.assertIn(f"create materialized view {view}", self.shared_snapshot)

        original = self.sql.split(
            "create view analysis.exposure_hours_by_build_analysis_window_v5", 1
        )[1].split(
            "create view analysis.team_dashboard_payload_analysis_window_v5", 1
        )[0]
        successor = self.shared_snapshot.split(
            "create or replace view analysis.exposure_hours_by_build_analysis_window_v5",
            1,
        )[1].split(
            "comment on materialized view analysis.analysis_window_injury", 1
        )[0]
        successor = successor.replace(
            "create or replace view analysis.", "create view analysis."
        )
        successor = successor.replace(
            "analysis.analysis_window_injury_cohort_v5_snapshot",
            "analysis.analysis_window_injury_cohort_v5",
        ).replace(
            "analysis.analysis_window_effective_exposure_cohort_v5_snapshot",
            "analysis.analysis_window_effective_exposure_cohort_v5",
        ).replace(
            "analysis.analysis_window_reporting_classification_v5_snapshot",
            "analysis.analysis_window_reporting_classification_v5",
        )
        self.assertEqual(original.strip(), successor.strip())
        for required in (
            "refresh materialized view\n  analysis.analysis_window_injury_cohort_v5_snapshot",
            "refresh materialized view\n  analysis.analysis_window_reporting_classification_v5_snapshot",
            "refresh materialized view\n  analysis.analysis_window_effective_exposure_cohort_v5_snapshot",
            "V5 shared injury and classification snapshots do not reconcile",
        ):
            self.assertIn(required, self.snapshot)

    def test_release_constraints_accept_v5_only_with_its_recorded_date_and_cohort(self) -> None:
        self.assertIn("analysis_version in ('v2', 'v3', 'v4', 'v5')", self.sql)
        self.assertIn(
            "(analysis_version = 'v5' and decision_recorded_at = date '2026-07-25')",
            self.sql,
        )
        self.assertIn("'analysis_window_2024-25_2026-07-25_v1'", self.sql)

    def test_reconciliation_targets_are_tests_not_output_logic(self) -> None:
        self.assertIn("64511", self.reconciliation)
        self.assertIn("81352.919497", self.reconciliation)
        self.assertIn("6040", self.reconciliation)
        self.assertIn("75312.919497", self.reconciliation)
        self.assertIn("1658", self.reconciliation)
        self.assertIn("785", self.reconciliation)
        self.assertIn("17573", self.reconciliation)
        self.assertIn("815", self.reconciliation)
        self.assertIn("865.830", self.reconciliation)
        for team, rows, hours in (
            ("cardiff", "164", "180.391667"),
            ("dragons", "348", "296.138333"),
            ("ospreys", "32", "23.623333"),
            ("scarlets", "169", "183.943333"),
            ("sharks", "46", "106.937222"),
            ("zebre", "56", "74.796111"),
        ):
            self.assertIn(f"('{team}', {rows}::numeric, {hours}::numeric)", self.reconciliation)
        self.assertNotIn("64511", self.sql)
        self.assertNotIn("81352.919497", self.sql)
        self.assertNotIn("75312.919497", self.sql)
        self.assertNotIn("865.830", self.sql)
        self.assertIn("left join actual using (contract_name)", self.reconciliation)
        self.assertIn(
            "coalesce(expected.expected_numeric = actual.actual_numeric, false)",
            self.reconciliation,
        )

    def test_evidence_extraction_is_build_pinned_and_candidate_perf_is_direct(self) -> None:
        for predicate in (
            "where season = '2024-25'",
            "and approved_member_build",
            "outside_official_analysis_window_removed",
            "pre_urc_match_rule_rejected",
        ):
            self.assertIn(predicate, self.exposure_extraction)
        self.assertIn("curated_build_id::text", self.exposure_extraction)
        self.assertIn(
            "analysis.league_dashboard_release_candidates_analysis_window_v5",
            self.performance,
        )
        self.assertIn(
            "analysis.team_dashboard_release_candidates_analysis_window_v5",
            self.team_performance,
        )
        for performance in (self.performance, self.team_performance):
            self.assertIn("octet_length(candidate.dashboard::text)", performance)
            self.assertIn("candidate_payload_passed", performance)
            self.assertIn("payload as materialized", performance)
            self.assertIn("completed as materialized", performance)
            self.assertIn(
                "extract(epoch from (completed_at - started_at))",
                performance,
            )
        self.assertNotIn(
            "analysis.team_dashboard_release_candidates_analysis_window_v5",
            self.performance,
        )
        self.assertNotIn(
            "analysis.league_dashboard_release_candidates_analysis_window_v5",
            self.team_performance,
        )

    def test_v4_migration_remains_a_predecessor_not_a_modified_target(self) -> None:
        self.assertIn("create view analysis.lineage_injury_cohort_v1", self.v4)
        self.assertIn("'lineage_2024-25_2026-07-24_v1'", self.v4)
        self.assertNotIn("analysis_window_2024-25_2026-07-25_v1", self.v4)

    def test_v4_league_trigger_branch_is_byte_identical_to_the_fast_path(self) -> None:
        old_start = self.v4_fast_path.index("  elsif target_analysis_version = 'v4' then")
        old_end = self.v4_fast_path.index("  elsif not exists (", old_start)
        new_start = self.sql.index("  elsif target_analysis_version = 'v4' then")
        new_end = self.sql.index("  elsif target_analysis_version = 'v5' then", new_start)
        self.assertEqual(
            self.v4_fast_path[old_start:old_end],
            self.sql[new_start:new_end],
        )

    def test_v4_team_trigger_branch_is_byte_identical_to_the_fast_path(self) -> None:
        needle = "left join analysis.team_dashboard_release_candidates_lineage_v4 candidate"
        old_position = self.v4_fast_path.index(needle)
        new_position = self.sql.index(needle)
        old_start = self.v4_fast_path.rfind("  if exists (", 0, old_position)
        new_start = self.sql.rfind("  if exists (", 0, new_position)
        old_end = self.v4_fast_path.index("  if exists (", old_position)
        new_end = self.sql.index("  if exists (", new_position)
        self.assertEqual(
            self.v4_fast_path[old_start:old_end],
            self.sql[new_start:new_end],
        )


if __name__ == "__main__":
    unittest.main()
