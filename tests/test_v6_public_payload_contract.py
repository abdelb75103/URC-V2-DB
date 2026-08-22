from __future__ import annotations

import copy
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pipeline.__main__ as pipeline
from pipeline.__main__ import assert_v6_public_dashboard_contract
from pipeline.season_contracts import (
    YEAR2_2025_26_RELEASE_CONTRACT,
)


def dashboard() -> dict[str, object]:
    headline = [
        {"key": "recorded_injuries", "label": "Recorded injuries", "value": 12, "unit": "injuries", "formula": "count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)"},
        {"key": "time_loss_injuries", "label": "Time-loss injuries", "value": 9, "unit": "injuries", "formula": "count(eligible injury rows where days lost > 0)"},
        {"key": "incidence_per_1000h", "label": "Incidence", "value": 4.5, "unit": "per 1,000 player-hours", "numerator": 9, "denominator": 2000, "formula": "pooled time-loss injuries / pooled exposure hours * 1000"},
        {"key": "severity_mean_days", "label": "Mean severity", "value": 7, "unit": "days lost per injury", "numerator": 63, "denominator": 9, "formula": "pooled days lost / pooled time-loss injuries"},
        {"key": "severity_median_days", "label": "Median severity", "value": 6, "unit": "days lost per injury", "formula": "median(days lost) across pooled time-loss injuries"},
        {"key": "burden_per_1000h", "label": "Burden", "value": 31.5, "unit": "days lost per 1,000 player-hours", "numerator": 63, "denominator": 2000, "formula": "pooled days lost / pooled exposure hours * 1000"},
    ]
    profile = {
        "dimension": "injury_type", "code": "muscle_injury", "label": "Muscle injury", "setting": "all",
        "time_loss_injuries": 9, "days_lost": 63, "exposure_hours": 2000,
        "incidence_per_1000h": 4.5, "burden_per_1000h": 31.5, "mean_severity_days": 7,
    }
    contact = [
        {"key": key, "label": label, "setting": setting, "recorded_injuries": 0, "time_loss_injuries": 0}
        for setting in ("all", "match", "training", "unknown")
        for key, label in (("contact", "Contact"), ("non_contact", "Non-contact"), ("unknown", "Unknown"))
    ]
    return {
        "generated_at": "2026-08-15T00:00:00Z", "team": "URC Overall", "season": "2025-26",
        "analysis_window": {"start": "2025-09-01", "end": "2026-06-30", "basis": "Registered Year 2 reporting window."},
        "method": ["method"],
        "coverage": {"hours": 2000, "match_hours": 800, "training_hours": 1200, "distance_km": 1,
                     "exposure_rows": 2, "exposed_players": 3, "weeks": 4,
                     "included_exposure_status": "included_pending_protocol",
                     "analysis_window_start": "2025-09-01", "analysis_window_end": "2026-06-30", "teams_included": 16},
        "headline": headline, "monthly": [], "body_locations": [], "injury_types": [],
        "injury_profiles": [
            profile,
            {**profile, "dimension": "diagnosis", "code": "compound__thigh__muscle_injury", "label": "Thigh · Muscle injury"},
        ],
        "injury_type_families": [{**profile, "dimension": "injury_type_family", "mapping_version": "injury_type_family_2026-07-21_v1", "subtypes": [profile]}],
        "severity_distribution": [],
        "setting_split": [
            {"key": key, "label": label, "time_loss_injuries": 0, "days_lost": 0,
             "exposure_hours": None if key == "unknown" else 2000}
            for key, label in (("all", "All"), ("match", "Match"), ("training", "Training"), ("unknown", "Unknown"))
        ],
        "setting_metrics": [
            {"setting": key, "label": label, "time_loss_injuries": 0, "days_lost": 0,
             "exposure_hours": None if key == "unknown" else 2000,
             "incidence_per_1000h": None, "burden_per_1000h": None, "mean_severity_days": None}
            for key, label in (("all", "All"), ("match", "Match"), ("training", "Training"), ("unknown", "Unknown"))
        ],
        "contact_distribution": contact,
        "prior_season": {"season": "2024-25", "status": "frozen", "note": "Frozen."},
        "limitations": ["limit"],
    }


class V6PublicPayloadContractTests(unittest.TestCase):
    def test_v6_scalar_equality_allows_scale_only_and_keeps_year1_tolerance(self) -> None:
        self.assertTrue(pipeline.v6_public_scalars_equal(12, 12.0))
        self.assertTrue(pipeline.v6_public_scalars_equal(12, Decimal("12.000")))
        self.assertFalse(pipeline.v6_public_scalars_equal(12, 12.0000000005))
        self.assertFalse(
            pipeline.v6_public_scalars_equal(
                12,
                Decimal("12.0000000000000001"),
            )
        )
        self.assertTrue(pipeline.v6_public_scalars_equal(True, True))
        self.assertFalse(pipeline.v6_public_scalars_equal(True, 1))
        self.assertFalse(pipeline.v6_public_scalars_equal(False, 0))
        self.assertTrue(pipeline.parity_values_equal(12, 12.0000000005))

    def test_accepts_the_exact_public_payload_shape(self) -> None:
        assert_v6_public_dashboard_contract(dashboard(), "fixture")

    def test_rejects_an_unpublished_field_or_incomplete_contact_grid(self) -> None:
        with_private = dashboard()
        with_private["release_id"] = "not-public"
        with self.assertRaisesRegex(SystemExit, "unexpected top-level"):
            assert_v6_public_dashboard_contract(with_private, "fixture")

        missing_contact = copy.deepcopy(dashboard())
        missing_contact["contact_distribution"].pop()  # type: ignore[index]
        with self.assertRaisesRegex(SystemExit, "12-cell contact"):
            assert_v6_public_dashboard_contract(missing_contact, "fixture")

    def test_rejects_extra_nested_public_fields_and_wrong_headline_formula(self) -> None:
        with_extra_coverage = dashboard()
        with_extra_coverage["coverage"]["candidate_build_id"] = "private"  # type: ignore[index]
        with self.assertRaisesRegex(SystemExit, "coverage"):
            assert_v6_public_dashboard_contract(with_extra_coverage, "fixture")

        wrong_formula = dashboard()
        wrong_formula["headline"][2]["formula"] = "unreviewed"  # type: ignore[index]
        with self.assertRaisesRegex(SystemExit, "formula"):
            assert_v6_public_dashboard_contract(wrong_formula, "fixture")

    def test_rejects_missing_duplicate_or_reordered_setting_grids(self) -> None:
        for section in ("setting_split", "setting_metrics"):
            missing = copy.deepcopy(dashboard())
            missing[section].pop()  # type: ignore[index]
            with self.assertRaisesRegex(SystemExit, "ordered all/match/training/unknown"):
                assert_v6_public_dashboard_contract(missing, "fixture")

            duplicate = copy.deepcopy(dashboard())
            duplicate[section][1] = copy.deepcopy(duplicate[section][0])  # type: ignore[index]
            with self.assertRaisesRegex(SystemExit, "ordered all/match/training/unknown"):
                assert_v6_public_dashboard_contract(duplicate, "fixture")

            reordered = copy.deepcopy(dashboard())
            reordered[section][0], reordered[section][1] = reordered[section][1], reordered[section][0]  # type: ignore[index]
            with self.assertRaisesRegex(SystemExit, "ordered all/match/training/unknown"):
                assert_v6_public_dashboard_contract(reordered, "fixture")

    def test_rejects_profiles_that_drop_the_accepted_diagnosis_dimension(self) -> None:
        missing_diagnosis = dashboard()
        missing_diagnosis["injury_profiles"] = [
            row for row in missing_diagnosis["injury_profiles"]  # type: ignore[index]
            if row["dimension"] != "diagnosis"
        ]
        with self.assertRaisesRegex(SystemExit, "diagnosis dimension"):
            assert_v6_public_dashboard_contract(missing_diagnosis, "fixture")


class V6AnalysisParityPublicInterfaceTests(unittest.TestCase):
    def test_scale_normalised_reviewed_payload_uses_the_manifest_bound_candidate_hash(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        candidate_hash = "a" * 64
        classification_evidence_sha256 = (
            "b470d6816364cde0dc3025438e85b0ab099fa88002e818ebae83118f1578cffa"
        )
        cohort_evidence_sha256 = (
            "604a9775f8e23f1a01235ae412b7814ec9797babd503ef2fb48c2c5a4db0763e"
        )
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        registered_migrations = [
            {
                "version": item.version,
                "name": item.name,
                "statements": [item.statement],
            }
            for item in contract.required_migration_contracts
        ]
        candidate_dashboard_json = json.dumps(reviewed).replace(
            '"value": 12',
            '"value": 12.0',
            1,
        )
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": classification_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": cohort_evidence_sha256,
            "dashboard_json": candidate_dashboard_json,
            "payload_sha256": candidate_hash,
            "approved_predecessors": [],
        }
        queries: list[str] = []

        def query(sql: str, params: list[object] | None = None) -> list[dict[str, object]]:
            queries.append(sql)
            if "reporting.team_key_aliases" in sql:
                return [{"team_key": "example", "excluded": False}]
            if "supabase_migrations.schema_migrations" in sql:
                return registered_migrations
            if contract.team_candidate_view in sql:
                return [candidate]
            self.fail(f"unexpected query: {sql}")

        log_path = Path("data/reporting/example_analysis_parity_2025-26.json")
        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "example-v6-preflight.json"
            preflight.write_text(json.dumps(reviewed, sort_keys=True) + "\n", encoding="utf-8")
            provenance = {
                "code_version": "a" * 40,
                "dependency_lock_hash": "b" * 64,
                "operator": "tester",
            }
            manifest = pipeline.v6_team_preflight_manifest(
                team_key="example",
                contract=contract,
                candidate=candidate,
                predecessor=None,
                preflight_file_sha256=pipeline.sha256_file(preflight),
                provenance=provenance,
            )
            Path(f"{preflight}.manifest.json").write_text(
                json.dumps(manifest, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            output = io.StringIO()
            try:
                with (
                    patch.object(pipeline, "query_sql", side_effect=query),
                    patch.object(pipeline, "run_provenance", return_value=provenance) as provenance_call,
                    redirect_stdout(output),
                ):
                    pipeline.verify_analysis_parity(
                        SimpleNamespace(
                            team="Example",
                            season="2025-26",
                            dashboard_file=str(preflight),
                        )
                    )
                result = json.loads(output.getvalue())
                evidence = json.loads(log_path.read_text(encoding="utf-8"))
            finally:
                log_path.unlink(missing_ok=True)

        self.assertEqual(result["overall"], "PARITY")
        provenance_call.assert_called_once_with()
        self.assertEqual(result["canonical_payload_sha256"], candidate_hash)
        self.assertEqual(
            result["classification_evidence_sha256"],
            classification_evidence_sha256,
        )
        self.assertEqual(result["cohort_evidence_sha256"], cohort_evidence_sha256)
        self.assertEqual(evidence["candidate_view"], contract.team_candidate_view)
        self.assertEqual(evidence["canonical_payload_sha256"], candidate_hash)
        self.assertEqual(
            evidence["classification_evidence_sha256"],
            classification_evidence_sha256,
        )
        self.assertEqual(
            evidence["cohort_evidence_sha256"],
            cohort_evidence_sha256,
        )
        self.assertEqual(evidence["diffs"], [])
        self.assertTrue(any(contract.team_candidate_view in sql for sql in queries))
        candidate_query = next(sql for sql in queries if contract.team_candidate_view in sql)
        self.assertIn("candidate.dashboard::text as dashboard_json", candidate_query)
        self.assertEqual(candidate_query.count("canonical_jsonb_sha256_v1"), 1)
        self.assertNotIn("reviewed_payload_sha256", candidate_query)
        self.assertIn("jsonb_agg", candidate_query)
        self.assertIn("reporting.team_release_payloads_v6", candidate_query)
        self.assertEqual(
            sum(contract.team_candidate_view in sql for sql in queries),
            1,
        )
        self.assertFalse(any("analysis.headline_metrics_v1" in sql for sql in queries))
        self.assertFalse(any("analysis.coverage_v1" in sql for sql in queries))

    def test_verify_analysis_parity_uses_only_the_reviewed_buffer_returned_by_the_manifest_reader(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": contract.classification_rule_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": contract.cohort_evidence_sha256,
            "dashboard_json": json.dumps(reviewed),
            "payload_sha256": "a" * 64,
            "approved_predecessors": [],
        }
        reviewed_sha256 = "e" * 64
        manifest_sha256 = "f" * 64
        log_path = Path("data/reporting/example_analysis_parity_2025-26.json")
        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "not-opened-directly.json"
            try:
                with (
                    patch.object(pipeline, "resolve_team_key", return_value="example"),
                    patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                    patch.object(pipeline, "query_sql", return_value=[candidate]),
                    patch.object(
                        pipeline,
                        "read_v6_team_reviewed_preflight",
                        return_value=(reviewed, reviewed, reviewed_sha256, manifest_sha256),
                    ) as reader,
                    patch.object(Path, "read_bytes", side_effect=AssertionError("unexpected reopen")),
                    patch.object(Path, "read_text", side_effect=AssertionError("unexpected reopen")),
                    redirect_stdout(io.StringIO()),
                ):
                    pipeline.verify_analysis_parity(
                        SimpleNamespace(
                            team="Example",
                            season="2025-26",
                            dashboard_file=str(preflight),
                        )
                    )
                evidence = json.loads(log_path.read_text(encoding="utf-8"))
            finally:
                log_path.unlink(missing_ok=True)

        reader.assert_called_once()
        self.assertEqual(evidence["reviewed_file_sha256"], reviewed_sha256)
        self.assertEqual(
            evidence["reviewed_preflight_manifest_sha256"],
            manifest_sha256,
        )

    def test_verify_analysis_parity_fails_on_the_first_dirty_provenance_snapshot(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": contract.classification_rule_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": contract.cohort_evidence_sha256,
            "dashboard_json": json.dumps(reviewed),
            "payload_sha256": "a" * 64,
            "approved_predecessors": [],
        }
        clean = {
            "code_version": "a" * 40,
            "dependency_lock_hash": "b" * 64,
            "operator": "tester",
        }
        dirty = {**clean, "code_version": f"{'a' * 40}-dirty"}
        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "reviewed-v6-preflight.json"
            preflight.write_text(json.dumps(reviewed) + "\n", encoding="utf-8")
            manifest = pipeline.v6_team_preflight_manifest(
                team_key="example",
                contract=contract,
                candidate=candidate,
                predecessor=None,
                preflight_file_sha256=pipeline.sha256_file(preflight),
                provenance=clean,
            )
            Path(f"{preflight}.manifest.json").write_text(
                json.dumps(manifest) + "\n",
                encoding="utf-8",
            )
            with (
                patch.object(pipeline, "resolve_team_key", return_value="example"),
                patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                patch.object(pipeline, "query_sql", return_value=[candidate]),
                patch.object(
                    pipeline,
                    "run_provenance",
                    side_effect=[dirty, clean],
                ) as provenance_call,
                redirect_stdout(io.StringIO()),
            ):
                with self.assertRaisesRegex(SystemExit, "manifest does not bind"):
                    pipeline.verify_analysis_parity(
                        SimpleNamespace(
                            team="Example",
                            season="2025-26",
                            dashboard_file=str(preflight),
                        )
                    )

        provenance_call.assert_called_once_with()

    def test_verify_analysis_parity_keeps_the_frozen_year1_route(self) -> None:
        with (
            patch.object(pipeline, "resolve_team_key", return_value="example"),
            patch.object(pipeline, "query_sql", return_value=[]) as query,
            patch.object(pipeline, "verify_analysis_parity_v6") as v6,
        ):
            with self.assertRaisesRegex(SystemExit, "analysis_views_v1"):
                pipeline.verify_analysis_parity(
                    SimpleNamespace(
                        team="Example",
                        season="2024-25",
                        dashboard_file="",
                    )
                )

        v6.assert_not_called()
        self.assertIn("supabase_migrations.schema_migrations", query.call_args.args[0])

    def test_verify_analysis_parity_rejects_missing_or_invalid_database_evidence_hashes(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        base_candidate = {
            "team_key": "example",
            "season": "2025-26",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": "c" * 64,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": "d" * 64,
            "dashboard_json": json.dumps(reviewed),
            "candidate_payload_sha256": "a" * 64,
            "reviewed_payload_sha256": "a" * 64,
        }
        cases = (
            ("classification_evidence_sha256", None),
            ("classification_evidence_sha256", "not-a-sha256"),
            ("cohort_evidence_sha256", None),
            ("cohort_evidence_sha256", "D" * 64),
        )

        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "example-v6-preflight.json"
            preflight.write_text(json.dumps(reviewed) + "\n", encoding="utf-8")
            for field, value in cases:
                with self.subTest(field=field, value=value):
                    candidate = dict(base_candidate)
                    if value is None:
                        candidate.pop(field)
                    else:
                        candidate[field] = value
                    with (
                        patch.object(pipeline, "resolve_team_key", return_value="example"),
                        patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                        patch.object(pipeline, "query_sql", return_value=[candidate]),
                        redirect_stdout(io.StringIO()),
                    ):
                        with self.assertRaisesRegex(SystemExit, f"invalid {field}"):
                            pipeline.verify_analysis_parity(
                                SimpleNamespace(
                                    team="Example",
                                    season="2025-26",
                                    dashboard_file=str(preflight),
                                )
                            )

    def test_verify_analysis_parity_enforces_the_local_evidence_contract_before_querying_candidate(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT

        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "example-v6-preflight.json"
            preflight.write_text(json.dumps(reviewed) + "\n", encoding="utf-8")
            with (
                patch.object(pipeline, "resolve_team_key", return_value="example"),
                patch.object(
                    pipeline,
                    "assert_local_evidence_bytes",
                    side_effect=SystemExit("local evidence rejected"),
                ) as evidence_check,
                patch.object(pipeline, "query_sql") as query,
            ):
                with self.assertRaisesRegex(SystemExit, "local evidence rejected"):
                    pipeline.verify_analysis_parity(
                        SimpleNamespace(
                            team="Example",
                            season="2025-26",
                            dashboard_file=str(preflight),
                        )
                    )

        evidence_check.assert_called_once_with(
            pipeline.year2_release_local_evidence_records(contract),
            "V6 analysis parity",
        )
        query.assert_not_called()

    def test_verify_analysis_parity_requires_the_adjacent_preflight_manifest(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": contract.classification_rule_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": contract.cohort_evidence_sha256,
            "dashboard_json": json.dumps(reviewed),
            "payload_sha256": "a" * 64,
            "approved_predecessors": [],
        }

        def query(sql: str, params: list[object] | None = None) -> list[dict[str, object]]:
            if contract.team_candidate_view in sql:
                return [candidate]
            self.fail(f"unexpected query: {sql}")

        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "reviewed-v6-preflight.json"
            preflight.write_text(json.dumps(reviewed) + "\n", encoding="utf-8")
            with (
                patch.object(pipeline, "resolve_team_key", return_value="example"),
                patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                patch.object(pipeline, "query_sql", side_effect=query),
                redirect_stdout(io.StringIO()),
            ):
                with self.assertRaisesRegex(SystemExit, "preflight and its manifest are required"):
                    pipeline.verify_analysis_parity(
                        SimpleNamespace(
                            team="Example",
                            season="2025-26",
                            dashboard_file=str(preflight),
                        )
                    )

    def test_verify_analysis_parity_rejects_multiple_approved_predecessors_from_the_candidate_snapshot(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": contract.classification_rule_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": contract.cohort_evidence_sha256,
            "dashboard_json": json.dumps(reviewed),
            "payload_sha256": "a" * 64,
            "approved_predecessors": [
                {"release_id": "00000000-0000-0000-0000-000000000002"},
                {"release_id": "00000000-0000-0000-0000-000000000003"},
            ],
        }

        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "reviewed-v6-preflight.json"
            preflight.write_text(json.dumps(reviewed) + "\n", encoding="utf-8")
            with (
                patch.object(pipeline, "resolve_team_key", return_value="example"),
                patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                patch.object(pipeline, "query_sql", return_value=[candidate]) as query,
                redirect_stdout(io.StringIO()),
            ):
                with self.assertRaisesRegex(SystemExit, "at most one approved predecessor"):
                    pipeline.verify_analysis_parity(
                        SimpleNamespace(
                            team="Example",
                            season="2025-26",
                            dashboard_file=str(preflight),
                        )
                    )

        query.assert_called_once()

    def test_verify_analysis_parity_rejects_each_manifest_identity_tamper(self) -> None:
        reviewed = dashboard()
        reviewed["team"] = "Example"
        reviewed["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del reviewed["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": contract.classification_rule_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": contract.cohort_evidence_sha256,
            "dashboard_json": json.dumps(reviewed),
            "payload_sha256": "a" * 64,
        }
        predecessor = {
            "release_id": "00000000-0000-0000-0000-000000000002",
            "release_label": "retained-predecessor",
            "payload_sha256": "b" * 64,
        }
        candidate["approved_predecessors"] = [predecessor]

        def query(sql: str, params: list[object] | None = None) -> list[dict[str, object]]:
            if contract.team_candidate_view in sql:
                return [candidate]
            self.fail(f"unexpected query: {sql}")

        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "reviewed-v6-preflight.json"
            preflight.write_text(json.dumps(reviewed) + "\n", encoding="utf-8")
            manifest = pipeline.v6_team_preflight_manifest(
                team_key="example",
                contract=contract,
                candidate=candidate,
                predecessor=predecessor,
                preflight_file_sha256=pipeline.sha256_file(preflight),
                provenance=pipeline.run_provenance(),
            )
            manifest_path = Path(f"{preflight}.manifest.json")
            cases = (
                ("payload_sha256", "c" * 64),
                ("preflight_file_sha256", "d" * 64),
                ("curated_build_id", "00000000-0000-0000-0000-000000000003"),
                ("release_tuple", {}),
                ("classification_evidence_sha256", "e" * 64),
                ("cohort_evidence_sha256", "f" * 64),
                ("local_evidence_files", []),
                ("provenance", {}),
                ("predecessor_release_id", None),
            )
            for key, replacement in cases:
                with self.subTest(key=key):
                    manifest_path.write_text(
                        json.dumps({**manifest, key: replacement}) + "\n",
                        encoding="utf-8",
                    )
                    with (
                        patch.object(pipeline, "resolve_team_key", return_value="example"),
                        patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                        patch.object(pipeline, "query_sql", side_effect=query),
                        redirect_stdout(io.StringIO()),
                    ):
                        with self.assertRaisesRegex(SystemExit, "manifest does not bind"):
                            pipeline.verify_analysis_parity(
                                SimpleNamespace(
                                    team="Example",
                                    season="2025-26",
                                    dashboard_file=str(preflight),
                                )
                            )

    def test_verify_analysis_parity_rejects_coordinated_public_scalar_tampering(self) -> None:
        candidate_dashboard = dashboard()
        candidate_dashboard["team"] = "Example"
        candidate_dashboard["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del candidate_dashboard["coverage"]["teams_included"]  # type: ignore[index]
        contract = YEAR2_2025_26_RELEASE_CONTRACT
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": contract.classification_rule_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": contract.cohort_evidence_sha256,
            "dashboard_json": json.dumps(candidate_dashboard),
            "payload_sha256": "a" * 64,
            "approved_predecessors": [],
        }

        def query(sql: str, params: list[object] | None = None) -> list[dict[str, object]]:
            if contract.team_candidate_view in sql:
                return [candidate]
            self.fail(f"unexpected query: {sql}")

        log_path = Path("data/reporting/example_analysis_parity_2025-26.json")
        with tempfile.TemporaryDirectory() as directory:
            preflight = Path(directory) / "changed-v6-preflight.json"
            cases = (
                ("integer_delta", 13, None, None),
                ("small_float_delta", 12.0000000005, None, None),
                ("bool_for_number", True, None, None),
                ("reviewed_beyond_binary_float_precision", 12, "12.0000000000000001", None),
                ("candidate_beyond_binary_float_precision", 12, None, "12.0000000000000001"),
            )
            for label, reviewed_value, reviewed_exact_number, candidate_exact_number in cases:
                with self.subTest(label=label):
                    candidate_json = json.dumps(candidate_dashboard)
                    if candidate_exact_number is not None:
                        candidate_json = candidate_json.replace(
                            '"value": 12',
                            f'"value": {candidate_exact_number}',
                            1,
                        )
                    candidate["dashboard_json"] = candidate_json
                    reviewed = copy.deepcopy(candidate_dashboard)
                    reviewed["headline"][0]["value"] = reviewed_value  # type: ignore[index]
                    reviewed_json = json.dumps(reviewed)
                    if reviewed_exact_number is not None:
                        reviewed_json = reviewed_json.replace(
                            '"value": 12',
                            f'"value": {reviewed_exact_number}',
                            1,
                        )
                    preflight.write_text(reviewed_json + "\n", encoding="utf-8")
                    manifest = pipeline.v6_team_preflight_manifest(
                        team_key="example",
                        contract=contract,
                        candidate=candidate,
                        predecessor=None,
                        preflight_file_sha256=pipeline.sha256_file(preflight),
                        provenance=pipeline.run_provenance(),
                    )
                    Path(f"{preflight}.manifest.json").write_text(
                        json.dumps(manifest) + "\n",
                        encoding="utf-8",
                    )
                    try:
                        with (
                            patch.object(pipeline, "resolve_team_key", return_value="example"),
                            patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                            patch.object(pipeline, "query_sql", side_effect=query),
                            redirect_stdout(io.StringIO()),
                        ):
                            with self.assertRaises(SystemExit):
                                pipeline.verify_analysis_parity(
                                    SimpleNamespace(
                                        team="Example",
                                        season="2025-26",
                                        dashboard_file=str(preflight),
                                    )
                                )
                        evidence = json.loads(log_path.read_text(encoding="utf-8"))
                    finally:
                        log_path.unlink(missing_ok=True)

                    self.assertEqual(evidence["summary"]["overall"], "DIFFS")
                    self.assertEqual(
                        evidence["diffs"][0]["path"],
                        "headline[0].value",
                    )


if __name__ == "__main__":
    unittest.main()
