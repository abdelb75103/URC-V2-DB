from __future__ import annotations

import unittest
import io
import inspect
import json
from types import SimpleNamespace
from unittest.mock import patch
from contextlib import redirect_stdout

import pipeline.__main__ as pipeline
from pipeline.season_contracts import (
    FROZEN_2024_25_RELEASE_TUPLES,
    YEAR2_2025_26_RELEASE_TUPLE,
    fixture_contract_for,
    fixture_provenance_rows,
    release_contract_for,
    validate_fixture_rows,
)


def fixture_rows() -> list[dict[str, str]]:
    teams = [f"Team {index}" for index in range(16)]
    rows: list[dict[str, str]] = []
    match_id = 1
    for round_value in range(1, 19):
        offset = (round_value - 1) % 15
        for index in range(8):
            rows.append(
                {
                    "season": "2025-26",
                    "match_id": str(match_id),
                    "stage": "Regular season",
                    "round": str(round_value),
                    "source_date": "2025-09-26",
                    "corrected_date": "2025-09-26",
                    "date_status": "source_confirmed",
                    "home_team": teams[(offset + index) % 16],
                    "away_team": teams[(offset + 15 - index) % 16],
                    "source_file_sha256": "a" * 64,
                    "source_row_number": str(match_id + 1),
                    "source_locator": f"https://fixtures.example.test/source[{match_id}]",
                    "source_request_sha256": "b" * 64,
                    "source_response_sha256": "a" * 64,
                    "retrieved_at": "2026-08-15T01:09:13Z",
                }
            )
            match_id += 1
    for stage, pairings in (
        ("Quarter-final", [(0, 1), (2, 3), (4, 5), (6, 7)]),
        ("Semi-final", [(0, 2), (4, 6)]),
        ("Final", [(0, 4)]),
    ):
        for home, away in pairings:
            rows.append(
                {
                    "season": "2025-26",
                    "match_id": str(match_id),
                    "stage": stage,
                    "round": {"Quarter-final": "19", "Semi-final": "20", "Final": "21"}[stage],
                    "source_date": "2026-06-20",
                    "corrected_date": "2026-06-20",
                    "date_status": "source_confirmed",
                    "home_team": teams[home],
                    "away_team": teams[away],
                    "source_file_sha256": "a" * 64,
                    "source_row_number": str(match_id + 1),
                    "source_locator": f"https://fixtures.example.test/source[{match_id}]",
                    "source_request_sha256": "b" * 64,
                    "source_response_sha256": "a" * 64,
                    "retrieved_at": "2026-08-15T01:09:13Z",
                }
            )
            match_id += 1
    return rows


class SeasonContracts2025_26Tests(unittest.TestCase):
    def test_year2_release_tuple_is_season_bound_and_not_a_v5_fallback(self) -> None:
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)

        self.assertEqual(contract.season, "2025-26")
        self.assertEqual(contract.analysis_version, "v6")
        self.assertEqual(
            contract.classification_view_version,
            "reporting_classification_2026-07-22_v2",
        )
        self.assertEqual(
            contract.cohort_view_version,
            "analysis_window_2025-26_2026-08-15_v1",
        )
        self.assertEqual(
            contract.league_candidate_view,
            "analysis.league_dashboard_release_candidates_analysis_window_v6",
        )
        self.assertEqual(
            contract.team_candidate_view,
            "analysis.team_dashboard_release_candidates_analysis_window_v6",
        )
        self.assertEqual(contract.member_view, "analysis.league_member_releases_v6")
        self.assertEqual(contract.injury_cohort_view, "analysis.analysis_window_injury_cohort_v6")
        self.assertEqual(contract.league_monthly_view, "analysis.analysis_window_league_monthly_v6")
        self.assertEqual(contract.league_summary_view, "analysis.analysis_window_league_summary_v6")
        self.assertEqual(contract.required_migrations, ("20260815010000", "20260815020000", "20260815030000"))
        self.assertEqual(contract.cohort_adjudication_ref, "ANALYSIS-WINDOW-2025-26-01")
        self.assertEqual(
            contract.cohort_evidence_locator,
            "docs/evidence/urc_2025_26_reporting_contract.json",
        )
        self.assertNotEqual(contract.analysis_version, "v5")

    def test_year1_release_tuples_remain_exactly_accepted(self) -> None:
        self.assertEqual(
            FROZEN_2024_25_RELEASE_TUPLES,
            frozenset(
                {
                    ("v2", "v2", "v2"),
                    ("v2", "reporting_classification_2026-07-20_v1", "v2"),
                    ("v3", "reporting_classification_2026-07-20_v1", "season_bound_2026-07-20_v1"),
                    ("v3", "reporting_classification_2026-07-22_v2", "season_bound_2026-07-20_v1"),
                    ("v4", "reporting_classification_2026-07-22_v2", "lineage_2024-25_2026-07-24_v1"),
                    ("v5", "reporting_classification_2026-07-22_v2", "analysis_window_2024-25_2026-07-25_v1"),
                }
            ),
        )

    def test_year2_fixture_contract_accepts_the_official_structure(self) -> None:
        rows = fixture_rows()

        summary = validate_fixture_rows("2025-26", rows)

        self.assertEqual(summary["fixture_count"], 151)
        self.assertEqual(summary["team_count"], 16)
        self.assertEqual(summary["regular_matches_per_team"], 18)
        self.assertEqual(
            summary["stage_counts"],
            {
                "Regular season": 144,
                "Quarter-final": 4,
                "Semi-final": 2,
                "Final": 1,
            },
        )

    def test_year2_fixture_contract_rejects_duplicate_match_id_before_database_work(self) -> None:
        rows = fixture_rows()
        rows[-1]["match_id"] = rows[0]["match_id"]

        with self.assertRaisesRegex(ValueError, "match IDs must be unique"):
            validate_fixture_rows("2025-26", rows)

    def test_year2_fixture_provenance_is_public_complete_and_deterministic(self) -> None:
        rows = fixture_rows()
        provenance = fixture_provenance_rows("2025-26", rows)

        self.assertEqual(len(provenance), 151)
        self.assertEqual(provenance[0]["upstream_match_id"], "1")
        self.assertEqual(provenance[0]["source_row_number"], 2)
        self.assertEqual(provenance[0]["source_request_sha256"], "b" * 64)

    def test_year2_fixture_provenance_rejects_non_public_locator(self) -> None:
        rows = fixture_rows()
        rows[0]["source_locator"] = "private://fixture/1"

        with self.assertRaisesRegex(ValueError, "public https"):
            fixture_provenance_rows("2025-26", rows)

    def test_unknown_season_has_no_fixture_contract(self) -> None:
        self.assertIsNone(fixture_contract_for("2026-27"))

    def test_year2_tuple_is_rejected_for_year1_and_unknown_tuples_fail_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "not accepted for season"):
            release_contract_for("2024-25", YEAR2_2025_26_RELEASE_TUPLE)
        with self.assertRaisesRegex(ValueError, "unsupported"):
            release_contract_for("2025-26", ("v5", "v2", "v2"))

    def test_year2_fixture_loader_validates_before_issuing_a_database_query(self) -> None:
        rows = fixture_rows()
        rows[-1]["match_id"] = rows[0]["match_id"]
        args = SimpleNamespace(season="2025-26", file="private/fixtures.csv")

        with (
            patch.object(pipeline, "read_rows", return_value=rows),
            patch.object(pipeline, "query_sql") as query_sql,
        ):
            with self.assertRaisesRegex(SystemExit, "match IDs must be unique"):
                pipeline.load_curated_fixtures(args)
        query_sql.assert_not_called()

    def test_year2_fixture_loader_rejects_conflicting_existing_provenance(self) -> None:
        source = inspect.getsource(pipeline.load_curated_fixtures)

        self.assertIn("expected_fixture_provenance", source)
        self.assertIn("is distinct from", source)
        self.assertIn("fixture provenance conflicts with existing immutable evidence", source)

    def test_year2_release_plan_accepts_only_the_registered_v6_tuple_without_database_access(self) -> None:
        args = SimpleNamespace(
            season="2025-26",
            snapshot_current=False,
            preflight=False,
            preflight_file="",
            preflight_reviewer="",
            previous_bundle_file="",
            analysis_version=YEAR2_2025_26_RELEASE_TUPLE[0],
            classification_view_version=YEAR2_2025_26_RELEASE_TUPLE[1],
            cohort_view_version=YEAR2_2025_26_RELEASE_TUPLE[2],
            plan=True,
        )
        output = io.StringIO()

        with patch.object(pipeline, "query_sql") as query_sql, redirect_stdout(output):
            pipeline.release_league(args)

        query_sql.assert_not_called()
        plan = json.loads(output.getvalue())
        self.assertEqual(plan["season"], "2025-26")
        self.assertEqual(plan["release_tuple"], {
            "analysis_version": "v6",
            "classification_view_version": "reporting_classification_2026-07-22_v2",
            "cohort_view_version": "analysis_window_2025-26_2026-08-15_v1",
        })

    def test_release_cli_accepts_the_registered_v6_tuple(self) -> None:
        with (
            patch.object(pipeline, "release_league") as release,
            patch.object(
                pipeline.sys,
                "argv",
                [
                    "pipeline", "release-league", "--preflight",
                    "--season", "2025-26",
                    "--analysis-version", "v6",
                    "--classification-view-version", "reporting_classification_2026-07-22_v2",
                    "--cohort-view-version", "analysis_window_2025-26_2026-08-15_v1",
                ],
            ),
        ):
            pipeline.main()
        args = release.call_args.args[0]
        self.assertEqual(
            YEAR2_2025_26_RELEASE_TUPLE,
            (args.analysis_version, args.classification_view_version, args.cohort_view_version),
        )


if __name__ == "__main__":
    unittest.main()
