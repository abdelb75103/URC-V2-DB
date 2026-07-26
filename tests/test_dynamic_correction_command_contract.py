from __future__ import annotations

import ast
import argparse
import importlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
CORRECTIONS = ROOT / "pipeline/corrections.py"
PIPELINE_MAIN = ROOT / "pipeline/__main__.py"


class DynamicCorrectionCommandContractTests(unittest.TestCase):
    """Offline command contracts for the human correction workflow.

    The command tests intentionally mock the database boundary once the module
    exists.  They must never require a live database or apply a sample V5
    correction merely to establish the interface.
    """

    @classmethod
    def setUpClass(cls) -> None:
        if not CORRECTIONS.exists():
            raise AssertionError(f"missing planned correction module: {CORRECTIONS}")
        cls.source = CORRECTIONS.read_text(encoding="utf-8")
        cls.main_source = PIPELINE_MAIN.read_text(encoding="utf-8")
        cls.tree = ast.parse(cls.source)
        cls.corrections = importlib.import_module("pipeline.corrections")

    def function_source(self, name: str) -> str:
        node = next(
            (
                candidate
                for candidate in self.tree.body
                if isinstance(candidate, (ast.FunctionDef, ast.AsyncFunctionDef))
                and candidate.name == name
            ),
            None,
        )
        self.assertIsNotNone(node, f"pipeline.corrections must expose {name}()")
        return ast.get_source_segment(self.source, node) or ""

    def test_public_commands_are_registered_without_reusing_legacy_adjudication_commands(self) -> None:
        for command in (
            "capture-served-baseline",
            "verify-served-baseline",
            "correction-propose",
            "correction-apply",
            "correction-release",
            "correction-rollback",
        ):
            self.assertTrue(
                f'add_parser("{command}")' in self.main_source,
                f"missing pipeline command registration: {command}",
            )
        self.assertIn("pipeline.corrections", self.main_source)
        self.assertNotIn("apply-adjudication-batch", self.source)

    def test_proposal_is_allowlisted_typed_evidence_bound_and_hashed(self) -> None:
        proposal = self.function_source("correction_propose").lower()
        proposal_builder = self.function_source("_proposal_from_args").lower()
        proposal_hash = self.function_source("_proposal_hash").lower()
        subject_binding = self.function_source("_subject_binding").lower()
        proposal_contract = "\n".join((proposal, proposal_builder, proposal_hash, subject_binding))
        for requirement in (
            "allow",
            "field",
            "expected_value",
            "new",
            "evidence",
            "reason",
            "operator",
            "rule",
            "row_sha256",
            "correction_set_sha256",
            "proposal_hash",
        ):
            self.assertIn(requirement, proposal_contract)
        self.assertIn("query_sql", proposal_hash)
        self.assertNotIn("run_sql", proposal)
        self.assertIn("analysis.row_correction_proposal_hash_v1", self.source)
        self.assertNotIn('"reviewer"', proposal_builder)
        proposal_parser = self.main_source.split(
            'subcommands.add_parser("correction-propose")', 1
        )[1].split('subcommands.add_parser("correction-apply")', 1)[0]
        self.assertNotIn("--reviewer", proposal_parser)

    def test_capture_and_verification_are_read_only_and_bind_v2_and_served_v3_hashes(self) -> None:
        capture = self.function_source("capture_served_baseline").lower()
        verify = self.function_source("verify_served_baseline").lower()
        served_state = self.function_source("_served_state").lower()
        for source in (capture, verify):
            self.assertNotIn("run_sql", source)
            self.assertIn("sha256", source)
        self.assertIn("query_sql", served_state)
        for view in (
            "reporting.latest_approved_dashboard_bundle_v4",
            "reporting.dashboard_bundle_team_payloads_v1",
            "reporting.dashboard_bundle_league_payloads_v1",
            "reporting.latest_team_dashboard_v5",
            "reporting.latest_league_dashboard_v5",
        ):
            self.assertTrue(view in self.source, f"missing baseline source: {view}")

    def test_preview_is_sql_derived_and_never_uses_the_write_runner(self) -> None:
        proposal = self.function_source("correction_propose").lower()
        self.assertIn("analysis.row_correction_preview_v1", self.source)
        self.assertIn("query_sql", self.function_source("_one_json_row").lower())
        self.assertNotIn("run_sql", proposal)
        self.assertNotIn("sql_exec.mjs", proposal)

    def test_apply_is_the_only_command_path_with_the_row_correction_write_primitive(self) -> None:
        apply = self.function_source("correction_apply").lower()
        self.assertIn("audit.apply_row_correction_v1", self.source)
        self.assertIn("run_sql", apply)
        self.assertRegex(apply, r"\b(stale|concurrent|correction_set|proposal)\b")
        self.assertIn('_required_text(args, "reviewer")', apply)
        self.assertIn('reviewer = _required_text(args, "reviewer")', self.source)
        self.assertGreater(
            apply.index('_required_text(args, "reviewer")'),
            apply.index("current_preview = _preview"),
            "apply must bind human approval only after replaying the read-only preview",
        )
        for name in (
            "capture_served_baseline",
            "verify_served_baseline",
            "correction_propose",
        ):
            self.assertNotIn("run_sql", self.function_source(name).lower())

    def test_no_dashboard_impact_apply_is_a_distinct_audited_terminal_state(self) -> None:
        apply = self.function_source("correction_apply").lower()
        candidate_check = self.function_source("_candidate_has_no_dashboard_impact").lower()
        self.assertIn("correction_applied_no_dashboard_impact", apply)
        self.assertIn("release_required", apply)
        self.assertIn("draft_bundle_sha256", candidate_check)
        self.assertIn("predecessor_bundle", candidate_check)
        self.assertIn("==", candidate_check)
        self.assertIn("release_required\": true", apply)

    def test_release_and_rollback_call_only_their_named_reporting_hooks(self) -> None:
        release = self.function_source("correction_release").lower()
        rollback = self.function_source("correction_rollback").lower()
        self.assertIn("reporting.promote_row_correction_v1", release)
        self.assertIn("run_sql", release)
        self.assertIn("reporting.rollback_row_correction_bundle_v1", rollback)
        self.assertIn("run_sql", rollback)
        self.assertNotIn("delete from", rollback)

    def test_promotion_export_failure_runs_the_compensating_database_rollback(self) -> None:
        release = self.function_source("correction_release").lower()
        self.assertIn("reporting.promote_row_correction_v1", release)
        self.assertIn("export", release)
        self.assertIn("try:", release)
        self.assertIn("except", release)
        self.assertIn("reporting.rollback_row_correction_bundle_v1", release)
        self.assertLess(
            release.index("reporting.promote_row_correction_v1"),
            release.index("reporting.rollback_row_correction_bundle_v1"),
        )

    def test_capture_baseline_uses_mocked_read_only_queries_and_never_write_runner(self) -> None:
        output = Path(tempfile.mkdtemp()) / "baseline.json"
        team_rows = [
            {"team_key": f"team-{index}", "dashboard": {"team": index}}
            for index in range(16)
        ]
        with (
            patch.object(self.corrections, "_require_private_output", return_value=output),
            patch.object(
                self.corrections,
                "query_sql",
                side_effect=[
                    [{"league": {"league": "served"}, "teams": team_rows}],
                    [{
                        "database_bundle_sha256": "a" * 64,
                        "league_payload_sha256": "b" * 64,
                        "team_payload_sha256s": {
                            f"team-{index}": "c" * 64 for index in range(16)
                        },
                    }],
                ],
            ) as query,
            patch.object(
                self.corrections,
                "_current_correction_aware_bundle_snapshot",
                return_value=(
                {"league": "stored"},
                {"release_label": "v5", "approved_at": "2026-07-26T00:00:00Z", "bundle_sha256": "a" * 64},
                ),
            ),
            patch.object(self.corrections, "assert_public_payload_is_publishable"),
            patch.object(self.corrections, "run_sql") as write,
        ):
            self.corrections.capture_served_baseline(
                argparse.Namespace(season="2024-25", output=str(output))
            )

        self.assertTrue(output.is_file())
        captured = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(captured["schema_version"], "urc_served_correction_baseline_v1")
        self.assertEqual(captured["stored_v2"]["bundle_sha256"], "a" * 64)
        self.assertIn("served_v3_sha256", captured)
        self.assertEqual(query.call_count, 2)
        query_sql = "\n".join(call.args[0] for call in query.call_args_list)
        self.assertIn("reporting.latest_team_dashboard_v5", query_sql)
        write.assert_not_called()

    def test_proposal_uses_mocked_preview_and_hash_queries_but_no_write_runner(self) -> None:
        output = Path(tempfile.mkdtemp()) / "proposal.json"
        evidence = output.parent / "evidence.json"
        evidence.write_text('{"source":"reviewed"}\n', encoding="utf-8")
        proposal_hash = "b" * 64
        preview = {
            "subject": {
                "source_row_id": "00000000-0000-0000-0000-000000000001",
                "source_row_sha256": "a" * 64,
                "row_fingerprint": "9" * 64,
                "team_key": "example",
            },
            "affected_team_before_sha256": "1" * 64,
            "affected_team_after_sha256": "2" * 64,
            "affected_league_before_sha256": "3" * 64,
            "affected_league_after_sha256": "4" * 64,
            "unchanged_team_hashes": [
                {
                    "team_key": f"team-{index}",
                    "payload_sha256": "0" * 64,
                }
                for index in range(15)
            ],
            "correction_set_hash_before": "5" * 64,
            "correction_set_hash_after": "6" * 64,
            "predecessor_bundle": {
                "release_id": "00000000-0000-0000-0000-000000000099",
                "release_label": "v5",
                "bundle_sha256": "7" * 64,
            },
        }
        with (
            patch.object(self.corrections, "_require_private_output", return_value=output),
            patch.object(
                self.corrections,
                "query_sql",
                side_effect=[[{"preview": preview}], [{"proposal_hash": proposal_hash}]],
            ) as query,
            patch.object(
                self.corrections,
                "_public_preview",
                return_value={"changed_paths": {"team": [], "league": []}},
            ),
            patch.object(self.corrections, "run_sql") as write,
        ):
            self.corrections.correction_propose(argparse.Namespace(
                season="2024-25",
                source_row_id="00000000-0000-0000-0000-000000000001",
                field_name="eligibility",
                expected_value="true",
                new_value="false",
                reason="Evidence-backed correction",
                evidence_file=str(evidence),
                operator="Abdel Babiker",
                rule_version="row_correction_v1",
                supersedes_correction_id="",
                output=str(output),
            ))

        self.assertEqual(query.call_count, 2)
        query_sql = "\n".join(call.args[0] for call in query.call_args_list)
        self.assertIn("analysis.row_correction_preview_v1", query_sql)
        self.assertIn("analysis.row_correction_proposal_hash_v1", query_sql)
        write.assert_not_called()
        stored = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(stored["proposal_hash"], proposal_hash)
        self.assertEqual(stored["proposal"]["proposal_hash"], proposal_hash)
        self.assertEqual(stored["proposal"]["source_row_sha256"], "a" * 64)
        self.assertEqual(stored["proposal"]["correction_set_hash_after"], "6" * 64)
        self.assertEqual(len(stored["proposal"]["unchanged_team_hashes"]), 15)
        self.assertEqual(stored["proposal"]["expected_value"], True)
        self.assertEqual(stored["proposal"]["new_value"], False)

    def test_apply_uses_the_single_audited_write_primitive_after_mocked_hash_check(self) -> None:
        proposal_hash = "c" * 64
        proposal = {
            "season": "2024-25",
            "source_row_id": "00000000-0000-0000-0000-000000000001",
            "field_name": "eligibility",
            "expected_value": True,
            "new_value": False,
            "reason": "Evidence-backed correction",
            "evidence_sha256": "d" * 64,
            "operator": "Abdel Babiker",
            "rule_version": "row_correction_v1",
            "source_row_sha256": "a" * 64,
            "row_fingerprint": "b" * 64,
            "correction_set_hash_before": "1" * 64,
            "correction_set_hash_after": "2" * 64,
            "predecessor_bundle": {
                "release_id": "00000000-0000-0000-0000-000000000099",
                "release_label": "v5",
                "bundle_sha256": "3" * 64,
            },
            "affected_team_before_sha256": "4" * 64,
            "affected_team_after_sha256": "5" * 64,
            "affected_league_before_sha256": "6" * 64,
            "affected_league_after_sha256": "7" * 64,
            "unchanged_team_hashes": [
                {
                    "team_key": f"team-{index}",
                    "payload_sha256": "8" * 64,
                }
                for index in range(15)
            ],
            "proposal_hash": proposal_hash,
            "code_version": "test-code-version",
            "dependency_lock_hash": "9" * 64,
            "migration_sha256": "8" * 64,
        }
        with tempfile.TemporaryDirectory() as temporary:
            proposal_file = Path(temporary) / "proposal.json"
            evidence = Path(temporary) / "evidence.json"
            evidence.write_text('{"source":"reviewed"}\n', encoding="utf-8")
            proposal["evidence_sha256"] = self.corrections.hashlib.sha256(evidence.read_bytes()).hexdigest()
            proposal_file.write_text(json.dumps({
                "proposal": proposal,
                "proposal_hash": proposal_hash,
                "evidence_file": str(evidence),
                "subject_binding": {
                    "source_row_sha256": "a" * 64,
                    "row_fingerprint": "b" * 64,
                },
            }), encoding="utf-8")
            with (
                patch.object(
                    self.corrections,
                    "query_sql",
                    side_effect=[
                        [{"proposal_hash": proposal_hash}],
                        [{"preview": {
                            "subject": {
                                "source_row_id": proposal["source_row_id"],
                                "source_row_sha256": "a" * 64,
                                "row_fingerprint": "b" * 64,
                            },
                            "correction_set_hash_before": "1" * 64,
                            "correction_set_hash_after": "2" * 64,
                            "predecessor_bundle": proposal["predecessor_bundle"],
                            "affected_team_before_sha256": "4" * 64,
                            "affected_team_after_sha256": "5" * 64,
                            "affected_league_before_sha256": "6" * 64,
                            "affected_league_after_sha256": "7" * 64,
                            "unchanged_team_hashes": proposal[
                                "unchanged_team_hashes"
                            ],
                        }}],
                        [{"candidate": {
                            "proposal_hash": proposal_hash,
                            "correction_set_hash": "e" * 64,
                            "draft_bundle_sha256": "f" * 64,
                            "predecessor_bundle": {
                                "bundle_sha256": "0" * 64,
                            },
                        }}],
                    ],
                ),
                patch.object(self.corrections, "run_sql") as write,
            ):
                self.corrections.correction_apply(argparse.Namespace(
                    proposal_file=str(proposal_file), reviewer="Abdel Babiker"
                ))

        write.assert_called_once()
        self.assertIn("audit.apply_row_correction_v1", write.call_args.args[0])
        self.assertNotIn("update curated", write.call_args.args[0].lower())

    def test_apply_rejects_a_stale_row_fingerprint_before_the_write(self) -> None:
        proposal_hash = "c" * 64
        proposal = {
            "season": "2024-25",
            "source_row_id": "00000000-0000-0000-0000-000000000001",
            "field_name": "eligibility",
            "expected_value": True,
            "new_value": False,
            "reason": "Evidence-backed correction",
            "operator": "Abdel Babiker",
            "rule_version": "row_correction_v1",
            "source_row_sha256": "a" * 64,
            "row_fingerprint": "b" * 64,
            "correction_set_hash_before": "1" * 64,
            "correction_set_hash_after": "2" * 64,
            "predecessor_bundle": {
                "release_id": "00000000-0000-0000-0000-000000000099",
                "release_label": "v5",
                "bundle_sha256": "3" * 64,
            },
            "affected_team_before_sha256": "4" * 64,
            "affected_team_after_sha256": "5" * 64,
            "affected_league_before_sha256": "6" * 64,
            "affected_league_after_sha256": "7" * 64,
            "unchanged_team_hashes": [
                {
                    "team_key": f"team-{index}",
                    "payload_sha256": "8" * 64,
                }
                for index in range(15)
            ],
            "proposal_hash": proposal_hash,
            "code_version": "test-code-version",
            "dependency_lock_hash": "9" * 64,
            "migration_sha256": "8" * 64,
        }
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary) / "evidence.json"
            evidence.write_text('{"source":"reviewed"}\n', encoding="utf-8")
            proposal["evidence_sha256"] = self.corrections.hashlib.sha256(evidence.read_bytes()).hexdigest()
            proposal_file = Path(temporary) / "proposal.json"
            proposal_file.write_text(json.dumps({
                "proposal": proposal,
                "proposal_hash": proposal_hash,
                "evidence_file": str(evidence),
                "subject_binding": {
                    "source_row_sha256": "a" * 64,
                    "row_fingerprint": "b" * 64,
                },
            }), encoding="utf-8")
            with (
                patch.object(
                    self.corrections,
                    "query_sql",
                    side_effect=[
                        [{"proposal_hash": proposal_hash}],
                        [{"preview": {
                            "subject": {
                                "source_row_id": proposal["source_row_id"],
                                "source_row_sha256": "a" * 64,
                                "row_fingerprint": "d" * 64,
                            },
                            "correction_set_hash_before": "1" * 64,
                            "correction_set_hash_after": "2" * 64,
                            "predecessor_bundle": proposal["predecessor_bundle"],
                            "affected_team_before_sha256": "4" * 64,
                            "affected_team_after_sha256": "5" * 64,
                            "affected_league_before_sha256": "6" * 64,
                            "affected_league_after_sha256": "7" * 64,
                            "unchanged_team_hashes": proposal[
                                "unchanged_team_hashes"
                            ],
                        }}],
                    ],
                ),
                patch.object(self.corrections, "run_sql") as write,
            ):
                with self.assertRaisesRegex(
                    SystemExit, "source-row, correction-set, or downstream"
                ):
                    self.corrections.correction_apply(argparse.Namespace(
                        proposal_file=str(proposal_file), reviewer="Abdel Babiker"
                    ))

        write.assert_not_called()


if __name__ == "__main__":
    unittest.main()
