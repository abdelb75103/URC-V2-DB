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
    validate_fixture_provenance_binding,
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
                    "source_file_sha256": "411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6",
                    "source_row_number": str(match_id + 1),
                    "source_locator": f"https://www.unitedrugby.com/graphql#data.matchstats[{match_id - 1}]",
                    "source_request_sha256": "57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af",
                    "source_response_sha256": "411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6",
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
                    "source_file_sha256": "411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6",
                    "source_row_number": str(match_id + 1),
                    "source_locator": f"https://www.unitedrugby.com/graphql#data.matchstats[{match_id - 1}]",
                    "source_request_sha256": "57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af",
                    "source_response_sha256": "411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6",
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
        self.assertEqual(
            contract.league_team_candidate_view,
            "analysis.league_team_dashboard_release_candidates_analysis_window_v6",
        )
        self.assertEqual(contract.member_view, "analysis.league_member_releases_v6")
        self.assertEqual(contract.injury_cohort_view, "analysis.analysis_window_injury_cohort_v6")
        self.assertEqual(contract.league_monthly_view, "analysis.analysis_window_league_monthly_v6")
        self.assertEqual(contract.league_summary_view, "analysis.analysis_window_league_summary_v6")
        self.assertEqual(
            contract.required_migrations,
            (
                "20260815010000", "20260815020000", "20260815030000",
                "20260822010000", "20260822020000", "20260822030000",
                "20260822220611", "20260823120000",
            ),
        )
        self.assertEqual(contract.cohort_adjudication_ref, "ANALYSIS-WINDOW-2025-26-01")
        self.assertEqual(
            contract.cohort_evidence_locator,
            "docs/evidence/urc_2025_26_reporting_contract.json",
        )
        self.assertEqual(
            contract.exposure_coverage_evidence_locator,
            "docs/evidence/urc_2025_26_incomplete_exposure_reporting_v6.json",
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
                    ("v5", "reporting_classification_2024-25_2026-08-27_v1", "analysis_window_2024-25_2026-07-25_v1"),
                    ("v5", "reporting_classification_2024-25_2026-08-27_v1", "analysis_window_2024-25_2026-08-30_v2"),
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
        provenance = fixture_provenance_rows(
            "2025-26", rows, prepared_file_sha256="071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b",
        )

        self.assertEqual(len(provenance), 151)
        self.assertEqual(provenance[0]["upstream_match_id"], "1")
        self.assertEqual(provenance[0]["source_row_number"], 2)
        self.assertEqual(provenance[0]["source_request_sha256"], "57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af")
        self.assertEqual(provenance[0]["prepared_file_sha256"], "071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b")
        self.assertEqual(provenance[0]["upstream_response_sha256"], "411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6")
        self.assertNotEqual(
            provenance[0]["prepared_file_sha256"],
            provenance[0]["upstream_response_sha256"],
        )

    def test_year2_fixture_provenance_rejects_non_public_locator(self) -> None:
        rows = fixture_rows()
        rows[0]["source_locator"] = "private://fixture/1"

        with self.assertRaisesRegex(ValueError, "committed evidence"):
            fixture_provenance_rows(
                "2025-26", rows, prepared_file_sha256="071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b",
            )

    def test_year2_fixture_contract_rejects_well_formed_but_uncommitted_source_evidence(self) -> None:
        for field, replacement in (
            ("source_locator", "https://www.unitedrugby.com/graphql#data.matchstats[999]x"),
            ("source_request_sha256", "a" * 64),
            ("source_response_sha256", "b" * 64),
            ("retrieved_at", "2026-08-15T01:09:14Z"),
        ):
            rows = fixture_rows()
            rows[0][field] = replacement
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "committed evidence"):
                validate_fixture_rows("2025-26", rows)
        with self.assertRaisesRegex(ValueError, "committed evidence"):
            fixture_provenance_rows(
                "2025-26", fixture_rows(), prepared_file_sha256="c" * 64,
            )

    def test_year2_fixture_provenance_binding_accepts_distinct_prepared_and_upstream_hashes(self) -> None:
        rows = fixture_rows()
        provenance = fixture_provenance_rows(
            "2025-26", rows, prepared_file_sha256="071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b",
        )

        validate_fixture_provenance_binding("2025-26", rows, provenance)

    def test_year2_fixture_provenance_binding_rejects_missing_or_partial_evidence(self) -> None:
        rows = fixture_rows()
        provenance = fixture_provenance_rows(
            "2025-26", rows, prepared_file_sha256="071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b",
        )

        with self.assertRaisesRegex(ValueError, "incomplete"):
            validate_fixture_provenance_binding("2025-26", rows, provenance[:-1])
        with self.assertRaisesRegex(ValueError, "expected 151 fixtures"):
            validate_fixture_provenance_binding("2025-26", rows[:-1], provenance[:-1])

    def test_year2_fixture_provenance_binding_rejects_a_prepared_checksum_mismatch(self) -> None:
        rows = fixture_rows()
        provenance = fixture_provenance_rows(
            "2025-26", rows, prepared_file_sha256="071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b",
        )
        provenance[0]["prepared_file_sha256"] = "d" * 64

        with self.assertRaisesRegex(ValueError, "prepared fixture bytes"):
            validate_fixture_provenance_binding("2025-26", rows, provenance)

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

    def test_local_evidence_byte_gate_is_purely_local(self) -> None:
        records = [
            {
                "role": "fixture",
                "locator": "docs/evidence/urc_2025_26_fixture_preparation.json",
                "sha256": fixture_contract_for("2025-26").evidence_sha256,
            }
        ]

        with patch.object(pipeline, "query_sql") as query_sql:
            pipeline.assert_local_evidence_bytes(records, "fixture test")

        query_sql.assert_not_called()

    def test_checksum_bound_migration_gate_checks_local_bytes_then_live_registration(self) -> None:
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)
        expected_hashes = {
            f"{item.version}_{item.name}.sql": item.sha256
            for item in contract.required_migration_contracts
        }
        expected_hashes.update(
            {
                "urc_2025_26_fixture_preparation.json": fixture_contract_for("2025-26").evidence_sha256,
                "urc_2025_26_reporting_contract.json": contract.cohort_evidence_sha256,
                "urc_2025_26_classification_rule.json": contract.classification_rule_evidence_sha256,
                "urc_2025_26_incomplete_exposure_reporting_v6.json": contract.exposure_coverage_evidence_sha256,
                "urc_2025_26_injury_eligibility_bridge.json": contract.injury_eligibility_evidence_sha256,
            }
        )
        registered = [
            {
                "version": item.version,
                "name": item.name,
                "statements": [item.statement],
            }
            for item in contract.required_migration_contracts
        ]

        with (
            patch.object(
                pipeline,
                "sha256_file",
                side_effect=lambda path: expected_hashes[path.name],
            ),
            patch.object(pipeline, "query_sql", return_value=registered) as query_sql,
        ):
            pipeline.assert_checksum_bound_release_migrations(contract, "release test")

        query_sql.assert_called_once()

    def test_v6_release_gate_rejects_altered_fixture_evidence_before_database_query(self) -> None:
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)
        migration_hashes = {
            f"{item.version}_{item.name}.sql": item.sha256
            for item in contract.required_migration_contracts
        }

        def evidence_drift(path):
            if path.name in migration_hashes:
                return migration_hashes[path.name]
            if path.name == "urc_2025_26_fixture_preparation.json":
                return "0" * 64
            raise AssertionError(f"unexpected hash request after fixture evidence drift: {path}")

        with (
            patch.object(pipeline, "sha256_file", side_effect=evidence_drift),
            patch.object(pipeline, "query_sql") as query_sql,
        ):
            with self.assertRaisesRegex(SystemExit, "fixture_preparation"):
                pipeline.assert_checksum_bound_release_migrations(contract, "release test")
        query_sql.assert_not_called()

    def test_year2_fixture_loader_rejects_conflicting_existing_provenance(self) -> None:
        source = inspect.getsource(pipeline.load_curated_fixtures)

        self.assertIn("expected_fixture_provenance", source)
        self.assertIn("is distinct from", source)
        self.assertIn("fixture provenance conflicts with existing immutable evidence", source)

    def test_year2_fixture_loader_requires_exact_migration_identity_before_write_sql(self) -> None:
        rows = fixture_rows()
        args = SimpleNamespace(season="2025-26", file="private/fixtures.csv")
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)
        fixture_migrations = tuple(
            migration for migration in contract.required_migration_contracts
            if migration.version in {
                pipeline.YEAR2_FIXTURE_PROVENANCE_MIGRATION_VERSION,
                pipeline.YEAR2_FIXTURE_ALIAS_MIGRATION_VERSION,
            }
        )
        fixture_contract = fixture_contract_for("2025-26")

        def expected_sha(path):
            for migration in fixture_migrations:
                if path.name == f"{migration.version}_{migration.name}.sql":
                    return migration.sha256
            if path.name == "urc_2025_26_fixture_preparation.json":
                return fixture_contract.evidence_sha256
            return fixture_contract.prepared_file_sha256

        exact = [
            {"version": migration.version, "name": migration.name, "statements": [migration.statement]}
            for migration in fixture_migrations
        ]
        for registered in (
            [{**exact[0], "name": "wrong_name"}, exact[1]],
            [{**exact[0], "statements": ["migration_sha256=" + "0" * 64]}, exact[1]],
        ):
            with self.subTest(registered=registered):
                with (
                    patch.object(pipeline, "read_rows", return_value=rows),
                    patch.object(pipeline, "sha256_file", side_effect=expected_sha),
                    patch.object(pipeline, "query_sql", return_value=registered),
                    patch.object(pipeline, "run_sql") as run_sql,
                ):
                    with self.assertRaisesRegex(SystemExit, "exact registered migration checksums"):
                        pipeline.load_curated_fixtures(args)
                    run_sql.assert_not_called()

        def wrong_migration_sha(path):
            migration = fixture_migrations[0]
            if path.name == f"{migration.version}_{migration.name}.sql":
                return "0" * 64
            return expected_sha(path)

        with (
            patch.object(pipeline, "read_rows", return_value=rows),
            patch.object(pipeline, "sha256_file", side_effect=wrong_migration_sha),
            patch.object(pipeline, "query_sql") as query_sql,
            patch.object(pipeline, "run_sql") as run_sql,
        ):
            with self.assertRaisesRegex(SystemExit, "local migration bytes"):
                pipeline.load_curated_fixtures(args)
            query_sql.assert_not_called()
            run_sql.assert_not_called()

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
        self.assertEqual(plan["rollback"]["mode"], "append_only_retained_bundle_successor")
        self.assertIn("--rollback-of-release-id", plan["rollback"]["preflight"])
        self.assertIn("never re-approves history", plan["rollback"]["invariant"])
        snapshot_step = next(step for step in plan["steps"] if "--snapshot-current" in step.get("action", ""))
        self.assertEqual(snapshot_step["condition"], "only when an approved predecessor exists")
        promotion = next(step for step in plan["steps"] if step["stage"] == "live_write")
        self.assertNotIn("--previous-bundle-file", promotion["action"])
        self.assertIn("--previous-bundle-file", promotion["action_if_predecessor_exists"])

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

    def test_year2_cli_defaults_resolve_to_the_only_registered_v6_tuple(self) -> None:
        args = SimpleNamespace(
            season="2025-26", snapshot_current=False, preflight=False,
            preflight_file="", preflight_reviewer="", previous_bundle_file="",
            rollback_of_release_id="", analysis_version="",
            classification_view_version="", cohort_view_version="", plan=True,
        )
        output = io.StringIO()
        with patch.object(pipeline, "query_sql") as query_sql, redirect_stdout(output):
            pipeline.release_league(args)
        query_sql.assert_not_called()
        self.assertEqual(tuple(json.loads(output.getvalue())["release_tuple"].values()), YEAR2_2025_26_RELEASE_TUPLE)


if __name__ == "__main__":
    unittest.main()
