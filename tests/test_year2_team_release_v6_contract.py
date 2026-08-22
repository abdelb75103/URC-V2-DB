from __future__ import annotations

from pathlib import Path
import io
import inspect
import json
import re
import tempfile
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import patch

import pipeline.__main__ as pipeline
from pipeline.season_contracts import YEAR2_2025_26_RELEASE_TUPLE, release_contract_for
from tests.test_v6_public_payload_contract import dashboard as public_dashboard


ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20260815030000_urc_2025_26_team_release_v6.sql").read_text(encoding="utf-8").lower()


class Year2TeamReleaseV6ContractTests(unittest.TestCase):
    def test_team_storage_is_immutable_and_tuple_bound(self) -> None:
        for token in (
            "reporting.team_release_payloads_v6",
            "team_release_payloads_v6_immutable",
            "analysis_version = 'v6'",
            "classification_view_version = 'reporting_classification_2026-07-22_v2'",
            "cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'",
            "dashboard_payload jsonb not null",
        ):
            self.assertIn(token, SQL)

    def test_canonical_database_hashes_and_private_storage_are_enforced(self) -> None:
        for token in (
            "create function reporting.canonical_jsonb_sha256_v1(payload jsonb)",
            "payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard_payload)",
            "alter table reporting.team_release_payloads_v6 enable row level security",
            "alter table reporting.league_release_payloads_v6 enable row level security",
            "revoke all on reporting.league_release_payloads_v6",
        ):
            self.assertIn(token, SQL)

    def test_league_reads_only_one_completed_immutable_bundle(self) -> None:
        for token in (
            "create view reporting.latest_approved_league_bundle_v6",
            "limit 1",
            "reporting.league_release_members_v2",
            "reporting.team_dashboard_payloads_v2",
            "analysis.league_team_dashboard_release_candidates_analysis_window_v6",
            "from reporting.latest_approved_league_bundle_v6 bundle",
        ):
            self.assertIn(token, SQL)
        readers = SQL.split("create view reporting.latest_team_dashboard_v6", 1)[1]
        self.assertNotIn("from reporting.team_release_payloads_v6 payload", readers)

    def test_v6_validators_bind_stored_reviewed_bytes_without_rewriting_year1_branch(self) -> None:
        self.assertIn("every v6 team dashboard snapshot must equal its immutable reviewed candidate", SQL)
        self.assertIn("analysis.league_team_dashboard_release_candidates_analysis_window_v6 candidate", SQL)
        self.assertIn("context.analysis_version <> 'v6'", SQL)
        self.assertIn("analysis.team_dashboard_release_candidates_analysis_window_v5 candidate", SQL)
        self.assertIn("analysis.team_dashboard_release_candidates_lineage_v4 candidate", SQL)
        self.assertIn("analysis.team_dashboard_classification_incremental_20260722_v1", SQL)

    def test_dependency_direction_is_active_build_then_accepted_member(self) -> None:
        reporting_sql = (ROOT / "supabase/migrations/20260815020000_urc_2025_26_reporting_v6.sql").read_text(encoding="utf-8").lower()
        self.assertIn("analysis.analysis_window_active_builds_v6", reporting_sql)
        self.assertNotIn("league_member_releases", reporting_sql)
        self.assertIn("analysis.league_member_releases_v6", SQL)
        self.assertIn("where release.status = 'approved'", SQL)
        self.assertIn("having count(*) = 16", SQL)

    def test_team_candidate_adds_the_v6_analysis_version_literal(self) -> None:
        candidate = SQL.split(
            "create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6",
            1,
        )[1].split(
            "create view analysis.league_team_dashboard_release_candidates_analysis_window_v6",
            1,
        )[0]
        self.assertIn("'v6'::text as analysis_version", candidate)
        self.assertNotIn("active.analysis_version", candidate)

    def test_league_candidate_adds_the_v6_analysis_version_literal(self) -> None:
        candidate = SQL.split(
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6",
            1,
        )[1].split(
            "create or replace function reporting.validate_league_dashboard_v2_candidate",
            1,
        )[0]
        self.assertIn("'v6'::text as analysis_version", candidate)
        self.assertNotIn("candidate.analysis_version", candidate)

    def test_league_contract_routes_every_v6_member_read(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        self.assertIn("member_view =", source)
        self.assertEqual(source.count("{member_view}"), 3)
        self.assertEqual(release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE).member_view, "analysis.league_member_releases_v6")

    def test_year2_team_reader_gets_season_from_the_completed_bundle(self) -> None:
        reader = SQL.split("create view reporting.latest_team_dashboard_v6", 1)[1].split(
            "create view reporting.latest_league_dashboard_v6", 1
        )[0]
        self.assertIn("bundle.season", reader)
        self.assertNotIn("payload.season", reader)

    def test_league_promotion_locks_every_reviewed_build_before_rechecking_member_identities(self) -> None:
        source = inspect.getsource(pipeline.release_league).lower()
        lock = "from curated.builds build\n          join reviewed_league_members member on member.curated_build_id = build.id"
        self.assertIn(lock, source)
        self.assertIn("order by member.team_key, build.id\n        for update;", source)
        self.assertLess(
            source.index("order by member.team_key, build.id\n        for update;"),
            source.index("reviewed bundle member identities changed after preflight validation"),
        )
        self.assertIn("and build.status = 'active'", source)

    def test_first_release_pipeline_uses_v6_candidate_and_storage(self) -> None:
        source = inspect.getsource(pipeline.release_team_v6)
        for token in (
            "--preflight-file",
            "contract.team_candidate_view",
            "reporting.team_release_payloads_v6",
            "active V6 candidate changed after review",
            "status = 'approved'",
            "assert_v6_public_dashboard_contract(dashboard, \"team dashboard\")",
            "compare_complete_public_payloads(",
            "reviewed_exact",
            "reviewed_display=reviewed",
        ):
            self.assertIn(token, source)

    def test_team_preflight_and_promotion_share_one_candidate_predecessor_snapshot(self) -> None:
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)
        payload = public_dashboard()
        payload["team"] = "Example"
        payload["coverage"]["exposure_grain"] = "session"  # type: ignore[index]
        del payload["coverage"]["teams_included"]  # type: ignore[index]
        candidate_dashboard_json = json.dumps(payload).replace(
            '"value": 12',
            '"value": 12.0000000000000001',
            1,
        )
        candidate = {
            "team_key": "example",
            "season": "2025-26",
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "analysis_version": "v6",
            "classification_view_version": contract.classification_view_version,
            "classification_evidence_sha256": contract.classification_rule_evidence_sha256,
            "cohort_view_version": contract.cohort_view_version,
            "cohort_evidence_sha256": contract.cohort_evidence_sha256,
            "dashboard_json": candidate_dashboard_json,
            "payload_sha256": "a" * 64,
            "approved_predecessors": [],
        }
        provenance = {
            "code_version": "a" * 40,
            "dependency_lock_hash": "b" * 64,
            "operator": "tester",
        }

        with tempfile.TemporaryDirectory() as directory:
            reviewed_path = Path(directory) / "reviewed.json"
            preflight_args = SimpleNamespace(
                team="Example",
                season="2025-26",
                preflight=True,
                preflight_file="",
                preflight_reviewer="",
                previous_dashboard_file="",
                restatement_file="",
                output=str(reviewed_path),
            )
            with (
                patch.object(pipeline, "run_provenance", return_value=provenance) as provenance_call,
                patch.object(pipeline, "resolve_team_key", return_value="example"),
                patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                patch.object(pipeline, "query_sql", return_value=[candidate]) as query,
                redirect_stdout(io.StringIO()),
            ):
                pipeline.release_team_v6(preflight_args)

            provenance_call.assert_called_once_with()
            query.assert_called_once()
            snapshot_sql = query.call_args.args[0]
            self.assertIn("candidate.dashboard::text as dashboard_json", snapshot_sql)
            self.assertIn("jsonb_agg", snapshot_sql)
            self.assertIn("reporting.team_release_payloads_v6", snapshot_sql)
            self.assertNotIn(" limit 1", snapshot_sql.lower())
            self.assertEqual(
                reviewed_path.read_bytes(),
                candidate_dashboard_json.encode("utf-8") + b"\n",
            )

            promotion_args = SimpleNamespace(
                team="Example",
                season="2025-26",
                preflight=False,
                preflight_file=str(reviewed_path),
                preflight_reviewer="Abdel Babiker",
                previous_dashboard_file="",
                restatement_file="",
                output="",
            )
            with (
                patch.object(pipeline, "run_provenance", return_value=provenance) as provenance_call,
                patch.object(pipeline, "resolve_team_key", return_value="example"),
                patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                patch.object(pipeline, "query_sql", return_value=[candidate]) as query,
                patch.object(pipeline, "run_sql") as write,
                redirect_stdout(io.StringIO()),
            ):
                pipeline.release_team_v6(promotion_args)

            provenance_call.assert_called_once_with()
            query.assert_called_once()
            self.assertIn("jsonb_agg", query.call_args.args[0])
            write.assert_called_once()
            promotion_sql = write.call_args.args[0]
            self.assertIn(
                "approved V6 team predecessor set changed after review",
                promotion_sql,
            )
            self.assertIn(
                ") <> (\n          -- Keep CASE's THEN nested so PL/pgSQL does not terminate this IF early.\n          case",
                promotion_sql,
            )
            predecessor_guard = promotion_sql.split(
                "if (\n          select count(*)",
                1,
            )[1].split("end if;", 1)[0]
            depth = 1
            top_level_then = 0
            for token in re.finditer(r"\(|\)|\bthen\b", predecessor_guard, re.IGNORECASE):
                if token.group() == "(":
                    depth += 1
                elif token.group() == ")":
                    depth -= 1
                elif depth == 0:
                    top_level_then += 1
            self.assertEqual(top_level_then, 1)
            self.assertEqual(
                write.call_args.args[1].count(candidate_dashboard_json),
                2,
            )

            candidate["approved_predecessors"] = [
                {"release_id": "00000000-0000-0000-0000-000000000002"},
                {"release_id": "00000000-0000-0000-0000-000000000003"},
            ]
            with (
                patch.object(pipeline, "run_provenance", return_value=provenance),
                patch.object(pipeline, "resolve_team_key", return_value="example"),
                patch.object(pipeline, "assert_checksum_bound_release_migrations"),
                patch.object(pipeline, "query_sql", return_value=[candidate]) as query,
                redirect_stdout(io.StringIO()),
            ):
                with self.assertRaisesRegex(SystemExit, "at most one approved predecessor"):
                    pipeline.release_team_v6(preflight_args)
            query.assert_called_once()

    def test_dirty_team_preflight_fails_on_the_first_provenance_snapshot(self) -> None:
        dirty = {
            "code_version": f"{'a' * 40}-dirty",
            "dependency_lock_hash": "b" * 64,
            "operator": "tester",
        }
        clean = {**dirty, "code_version": "a" * 40}
        args = SimpleNamespace(
            team="Example",
            season="2025-26",
            preflight=True,
            preflight_file="",
            preflight_reviewer="",
            previous_dashboard_file="",
            restatement_file="",
            output="",
        )
        with (
            patch.object(pipeline, "run_provenance", side_effect=[dirty, clean]) as provenance_call,
            patch.object(pipeline, "query_sql") as query,
        ):
            with self.assertRaisesRegex(SystemExit, "uncommitted working tree"):
                pipeline.release_team_v6(args)

        provenance_call.assert_called_once_with()
        query.assert_not_called()

    def test_identical_payload_can_receive_append_only_successors_for_new_builds(self) -> None:
        self.assertNotIn("unique (team_key, season, payload_sha256)", SQL)
        payload_sha256 = "a" * 64
        first = pipeline.v6_team_release_label(
            team_key="example",
            curated_build_id="00000000-0000-0000-0000-000000000001",
            payload_sha256=payload_sha256,
            attempt_id="1" * 12,
        )
        replacement = pipeline.v6_team_release_label(
            team_key="example",
            curated_build_id="00000000-0000-0000-0000-000000000002",
            payload_sha256=payload_sha256,
            attempt_id="2" * 12,
        )
        retry = pipeline.v6_team_release_label(
            team_key="example",
            curated_build_id="00000000-0000-0000-0000-000000000002",
            payload_sha256=payload_sha256,
            attempt_id="3" * 12,
        )
        self.assertEqual(len({first, replacement, retry}), 3)
        self.assertIn("00000000-0000-0000-0000-000000000002", replacement)

    def test_reviewed_team_preflight_manifest_is_checksum_bound_and_rejects_each_identity_tamper(self) -> None:
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)
        candidate = {
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "payload_sha256": "a" * 64,
            "classification_evidence_sha256": "c" * 64,
            "cohort_evidence_sha256": "d" * 64,
        }
        dashboard = {"team": "Example", "season": "2025-26"}
        predecessor = {"release_id": "00000000-0000-0000-0000-000000000002"}
        provenance = {
            "code_version": "a" * 40,
            "dependency_lock_hash": "b" * 64,
            "operator": "tester",
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            reviewed_path = Path(temporary_directory) / "reviewed.json"
            reviewed_path.write_text(json.dumps(dashboard, sort_keys=True) + "\n", encoding="utf-8")
            manifest = pipeline.v6_team_preflight_manifest(
                team_key="example", contract=contract, candidate=candidate,
                predecessor=predecessor, preflight_file_sha256=pipeline.sha256_file(reviewed_path),
                provenance=provenance,
            )
            manifest_path = Path(f"{reviewed_path}.manifest.json")
            manifest_path.write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
            reviewed, reviewed_exact, reviewed_sha256, manifest_sha256 = pipeline.read_v6_team_reviewed_preflight(
                reviewed_path=reviewed_path, team_key="example", contract=contract,
                candidate=candidate, predecessor=predecessor, provenance=provenance,
            )
            self.assertEqual(reviewed, dashboard)
            self.assertEqual(reviewed_exact, dashboard)
            self.assertEqual(reviewed_sha256, pipeline.sha256_file(reviewed_path))
            self.assertEqual(manifest_sha256, pipeline.sha256_file(manifest_path))
            for key, replacement in (
                ("schema_version", "wrong"), ("season", "2024-25"),
                ("candidate_view", "analysis.wrong"), ("payload_sha256", "b" * 64),
                ("classification_evidence_sha256", "e" * 64),
                ("cohort_evidence_sha256", "f" * 64),
                ("required_migrations", []),
                ("provenance", {}),
                ("curated_build_id", "00000000-0000-0000-0000-000000000003"),
                ("predecessor_release_id", None),
            ):
                tampered = {**manifest, key: replacement}
                manifest_path.write_text(json.dumps(tampered, sort_keys=True) + "\n", encoding="utf-8")
                with self.assertRaisesRegex(SystemExit, "manifest"):
                    pipeline.read_v6_team_reviewed_preflight(
                        reviewed_path=reviewed_path, team_key="example", contract=contract,
                        candidate=candidate, predecessor=predecessor, provenance=provenance,
                    )
            manifest_path.write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
            reviewed_path.write_text(json.dumps({"team": "altered"}) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "manifest"):
                pipeline.read_v6_team_reviewed_preflight(
                    reviewed_path=reviewed_path, team_key="example", contract=contract,
                    candidate=candidate, predecessor=predecessor, provenance=provenance,
                )

    def test_reviewed_preflight_hashes_the_single_buffer_it_parses(self) -> None:
        contract = release_contract_for("2025-26", YEAR2_2025_26_RELEASE_TUPLE)
        candidate = {
            "curated_build_id": "00000000-0000-0000-0000-000000000001",
            "payload_sha256": "a" * 64,
            "classification_evidence_sha256": "c" * 64,
            "cohort_evidence_sha256": "d" * 64,
        }
        original = {"team": "Example", "season": "2025-26"}
        replacement = {"team": "Replaced", "season": "2025-26"}
        provenance = {
            "code_version": "a" * 40,
            "dependency_lock_hash": "b" * 64,
            "operator": "tester",
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            reviewed_path = Path(temporary_directory) / "reviewed.json"
            reviewed_path.write_text(json.dumps(original) + "\n", encoding="utf-8")
            original_bytes = reviewed_path.read_bytes()
            manifest = pipeline.v6_team_preflight_manifest(
                team_key="example", contract=contract, candidate=candidate,
                predecessor=None,
                preflight_file_sha256=pipeline.hashlib.sha256(original_bytes).hexdigest(),
                provenance=provenance,
            )
            manifest_path = Path(f"{reviewed_path}.manifest.json")
            manifest_path.write_text(json.dumps(manifest) + "\n", encoding="utf-8")
            real_read_bytes = Path.read_bytes
            reviewed_reads = 0

            def read_then_replace(path: Path) -> bytes:
                nonlocal reviewed_reads
                value = real_read_bytes(path)
                if path == reviewed_path:
                    reviewed_reads += 1
                    reviewed_path.write_text(json.dumps(replacement) + "\n", encoding="utf-8")
                return value

            with patch.object(Path, "read_bytes", read_then_replace):
                reviewed, reviewed_exact, reviewed_sha256, _ = pipeline.read_v6_team_reviewed_preflight(
                    reviewed_path=reviewed_path, team_key="example", contract=contract,
                    candidate=candidate, predecessor=None, provenance=provenance,
                )

            self.assertEqual(reviewed, original)
            self.assertEqual(reviewed_exact, original)
            self.assertEqual(reviewed_sha256, pipeline.hashlib.sha256(original_bytes).hexdigest())
            self.assertEqual(reviewed_reads, 1)
            self.assertEqual(json.loads(reviewed_path.read_text(encoding="utf-8")), replacement)

    def test_team_successor_rechecks_locked_db_candidate_and_retires_only_the_predecessor(self) -> None:
        source = inspect.getsource(pipeline.release_team_v6)
        for token in (
            "reporting.canonical_jsonb_sha256_v1(dashboard)",
            "for update",
            "dashboard = {params.text(candidate_dashboard_json)}::jsonb",
            "{params.text(candidate_dashboard_json)}::jsonb, {params.text(payload_sha256)}",
            "approved V6 team predecessor set changed after review",
            "set status = 'retired'",
            "classification_evidence_sha256",
            "cohort_evidence_sha256",
        ):
            self.assertIn(token, source)
        self.assertNotIn("params.jsonb(dashboard)", source)
        self.assertIn(
            ") <> (\n          -- Keep CASE's THEN nested so PL/pgSQL does not terminate this IF early.\n          case",
            source,
        )
        self.assertNotIn(") <> case", source)
        self.assertIn("select count(*)", source)
        self.assertLess(
            source.index("for update;"),
            source.index("approved V6 team predecessor set changed after review"),
        )

    def test_team_review_audit_preserves_build_specific_path_and_manifest_hash(self) -> None:
        source = inspect.getsource(pipeline.release_team_v6)
        self.assertIn('build_path_token = clean_text(candidate["curated_build_id"])', source)
        self.assertIn("reviewed_preflight_manifest_sha256", source)
        self.assertIn(
            "reviewed, reviewed_exact, reviewed_sha256, reviewed_manifest_sha256 =",
            source,
        )
        self.assertNotIn('sha256_file(Path(f"{reviewed_path}.manifest.json"))', source)
        self.assertNotIn("sha256_file(reviewed_path)", source)

    def test_v6_promotion_checks_only_the_completed_v6_public_readers(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        branch = source.split("if {params.text(analysis_version)} = 'v6' then", 1)[1]
        v6_branch, legacy_branch = branch.split("else", 1)
        self.assertIn("reporting.latest_league_dashboard_v6", v6_branch)
        self.assertIn("reporting.latest_team_dashboard_v6", v6_branch)
        self.assertNotIn("reporting.latest_league_dashboard_v2", v6_branch)
        self.assertIn("reporting.latest_league_dashboard_v2", legacy_branch)

    def test_v6_release_manifest_retains_exact_migration_triples(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        self.assertIn("league_release_manifest_document(", source)
        self.assertIn("required_migrations=manifest_required_migrations", source)

    def test_v6_pipeline_audit_names_the_exact_v6_validation_migration(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        self.assertIn("v6_validation_migration", source)
        self.assertIn('"version": validation_contract.version', source)
        self.assertIn('"sha256": validation_contract.sha256', source)
        self.assertIn('"payload_hash_validation_migration": (', source)
        self.assertIn('"payload_candidate_validation_migration": (', source)

    def test_v6_local_finalisation_is_read_only_and_deterministic(self) -> None:
        source = inspect.getsource(pipeline.finalize_v6_league_release_local)
        self.assertNotIn("run_sql(", source)
        self.assertIn("reviewed_preflight_manifest_sha256", source)
        self.assertIn("current_league_bundle_snapshot", source)
        self.assertIn("write_team_dashboard_parity_exports", source)
        self.assertIn("league_release_manifest_document", source)
        self.assertIn("existing V6 release manifest differs", source)
        parser_source = inspect.getsource(pipeline.main)
        self.assertIn("finalize-v6-league-release-local", parser_source)

    def test_v6_post_promotion_failures_name_the_exact_local_finaliser(self) -> None:
        command = pipeline.v6_local_finalizer_command(
            release_id="11111111-1111-1111-1111-111111111111",
            release_label="urc-2025-26-v6-example-a1",
            preflight_file=Path("reviewed candidates/year2.json"),
        )
        self.assertEqual(
            command,
            "python3 -m pipeline finalize-v6-league-release-local "
            "--release-id 11111111-1111-1111-1111-111111111111 "
            "--release-label urc-2025-26-v6-example-a1 "
            "--preflight-file 'reviewed candidates/year2.json'",
        )
        source = inspect.getsource(pipeline.release_league)
        self.assertIn("V6 league promotion succeeded, but the exact approved release identity", source)
        self.assertGreaterEqual(source.count("v6_finalizer_command"), 4)
        self.assertIn("repair the local league export path, then run exactly", source)
        self.assertIn("repair the parity ", source)
        self.assertIn("repair the release manifest path, then run exactly", source)
        self.assertGreaterEqual(source.count("then run exactly:"), 3)

    def test_v6_release_manifest_preserves_both_rollback_identities(self) -> None:
        manifest = pipeline.league_release_manifest_document(
            release_label="rollback-successor", season="2025-26",
            release_tuple={"analysis_version": "v6", "classification_view_version": "c", "cohort_view_version": "h"},
            required_migrations=[], member_count=16, member_input_hash="a" * 64,
            league_payload_sha256="b" * 64, bundle_payload_sha256="c" * 64,
            team_payload_sha256s={"team": "d" * 64},
            reviewed_preflight_sha256="e" * 64,
            reviewed_preflight_manifest_sha256="f" * 64,
            provenance={"code_version": "x", "dependency_lock_hash": "y", "operator": "z"},
            dirty_worktree_paths=[], dirty_worktree_allowed_paths=[],
            parity_export={"team_count": 16, "export_set_sha256": "1" * 64, "bundle_sha256": "2" * 64},
            rollback={"release_id": "bundle-b"},
            rollback_of_release_id="bundle-a", rollback_replaces_release_id="bundle-b",
        )
        self.assertEqual(manifest["rollback"]["rollback_of_release_id"], "bundle-a")
        self.assertEqual(manifest["rollback"]["replaces_release_id"], "bundle-b")
        self.assertNotEqual(
            manifest["rollback"]["rollback_of_release_id"],
            manifest["rollback"]["replaces_release_id"],
        )

    def test_league_release_validates_each_v6_public_payload_before_preflight(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        self.assertIn('assert_v6_public_dashboard_contract(dashboard, "league dashboard")', source)
        self.assertIn('assert_v6_public_dashboard_contract(row["dashboard"], row["team_key"])', source)

    def test_year2_classification_provenance_carries_only_catalogue_rules_not_year1_row_adjudications(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        v6_branch = source.split("classification_adjudications = [{", 1)[1].split(
            "}]", 1
        )[0]
        self.assertIn("catalogue_and_conservative_inference_only", v6_branch)
        self.assertIn("not_carried_forward", v6_branch)
        self.assertNotIn("IA-02", v6_branch)
        self.assertNotIn("ACL-01", v6_branch)
        self.assertNotIn("OSIICS-01", v6_branch)

    def test_v6_rollback_is_an_append_only_reviewed_successor_of_retained_bytes(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        loader = inspect.getsource(pipeline.load_v6_retained_league_rollback_candidate)
        parser_source = inspect.getsource(pipeline.main)
        for token in (
            "--rollback-of-release-id",
            "load_v6_retained_league_rollback_candidate",
            "rollback_of_release_id",
            "reporting.v6_league_rollback_context",
            "reporting.league_release_payloads_v6",
            "reporting.team_dashboard_payloads_v2",
        ):
            self.assertIn(token, source + loader + parser_source)
        self.assertIn("release.status in ('approved', 'retired')", loader)
        self.assertIn("current_approved.predecessor_release_id = context.release_id::text", loader)
        self.assertIn("replaces_release_id", loader)
        self.assertIn("retained.dashboard", source)
        self.assertIn("retained rollback curated-build identities are incomplete", source)
        self.assertIn("exact predecessor of the current approved bundle", source)
        self.assertIn("(release_id, rollback_of_release_id, replaces_release_id)", source)
        self.assertNotIn("set status = 'approved'\n          where r.id = rollback", source)

    def test_v6_export_failure_never_reapproves_historical_release_state(self) -> None:
        source = inspect.getsource(pipeline.release_league)
        v6_guard = source.split("except BaseException as export_error:", 1)[1].split(
            "recovery_params = SqlParams()", 1
        )[0]
        self.assertIn("promotion succeeded", v6_guard)
        self.assertIn("Historical releases were not re-approved", v6_guard)
        self.assertNotIn("set status", v6_guard)

    def test_v6_promotions_require_the_exact_authorised_reviewer(self) -> None:
        team_source = inspect.getsource(pipeline.release_team_v6)
        league_source = inspect.getsource(pipeline.release_league)
        self.assertIn(
            'reviewer != "Abdel Babiker"',
            team_source,
        )
        self.assertIn(
            'analysis_version == "v6" and preflight_file_arg and reviewer != "Abdel Babiker"',
            league_source,
        )

    def test_unified_reader_is_v5_passthrough_for_year1(self) -> None:
        for token in (
            "reporting.latest_team_dashboard_v6",
            "reporting.latest_league_dashboard_v6",
            "from reporting.latest_team_dashboard_v5",
            "from reporting.latest_league_dashboard_v5",
            "reporting.approved_dashboard_reader_target_v2",
            "reporting.latest_dashboard_cache_token_v2",
        ):
            self.assertIn(token, SQL)
        reader = (ROOT / "lib/reporting.ts").read_text(encoding="utf-8")
        self.assertNotIn("latest_team_dashboard_v5", reader)
        self.assertNotIn("latest_league_dashboard_v5", reader)
        self.assertIn("latest_team_dashboard_v6", reader)
        self.assertIn("approved_dashboard_reader_target_v2", reader)


if __name__ == "__main__":
    unittest.main()
