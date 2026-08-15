from __future__ import annotations

import inspect
from pathlib import Path
import unittest

from pipeline.__main__ import (
    league_release_manifest_document,
    league_release_plan,
    load_league_release_candidate,
    release_league,
)


class ReleaseLeagueV2ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = inspect.getsource(release_league)
        cls.candidate_source = inspect.getsource(load_league_release_candidate)

    def test_preflight_reviews_one_public_bundle(self) -> None:
        self.assertIn('"schema_version": "urc_dashboard_bundle_v2"', self.source)
        self.assertIn('"league": dashboard', self.source)
        self.assertIn('"teams": [', self.source)
        self.assertIn("diff_json_documents(reviewed_bundle, public_bundle)", self.source)

    def test_frozen_year1_plan_preserves_the_legacy_predecessor_workflow(self) -> None:
        plan = league_release_plan(
            season="2024-25",
            analysis_version="v5",
            classification_view_version="reporting_classification_2026-07-22_v2",
            cohort_view_version="analysis_window_2024-25_2026-07-25_v1",
        )
        snapshot = next(
            step for step in plan["steps"]
            if "--snapshot-current" in step.get("action", "")
        )
        self.assertNotIn("condition", snapshot)
        promotion = next(
            step for step in plan["steps"]
            if step["stage"] == "live_write" and "release-league" in step["action"]
        )
        self.assertIn("--previous-bundle-file", promotion["action"])
        self.assertNotIn("action_if_predecessor_exists", promotion)
        self.assertEqual(
            plan["rollback"],
            "re-promote the retained predecessor tuple, then regenerate the 16-team parity exports",
        )

    def test_frozen_year1_manifest_preserves_legacy_timings_and_rollback_shape(self) -> None:
        predecessor = {"release_id": "year1-release", "release_label": "year1"}
        timings = {"candidate_load": 1.25, "workflow_total": 3.5}
        manifest = league_release_manifest_document(
            release_label="year1", season="2024-25",
            release_tuple={"analysis_version": "v5", "classification_view_version": "c", "cohort_view_version": "h"},
            required_migrations=["m"], member_count=16, member_input_hash="a" * 64,
            league_payload_sha256="b" * 64, bundle_payload_sha256="c" * 64,
            team_payload_sha256s={"team": "d" * 64},
            reviewed_preflight_sha256="e" * 64,
            reviewed_preflight_manifest_sha256="f" * 64,
            provenance={"code_version": "x", "dependency_lock_hash": "y", "operator": "z"},
            dirty_worktree_paths=[], dirty_worktree_allowed_paths=[],
            parity_export={"team_count": 16, "export_set_sha256": "1" * 64, "bundle_sha256": "2" * 64},
            rollback=predecessor, rollback_of_release_id=None,
            rollback_replaces_release_id=None, timings_ms=timings,
        )
        self.assertEqual(manifest["timings_ms"], timings)
        self.assertEqual(manifest["rollback"], predecessor)
        self.assertNotIn("retained_predecessor", manifest["rollback"])

    def test_v6_preflight_and_audit_fields_do_not_change_year1_contracts(self) -> None:
        self.assertIn("preflight_manifest[\"timings_ms\"] = timings_ms", self.source)
        self.assertIn("if analysis_version == \"v6\":\n        release_parameters", self.source)
        self.assertNotIn(
            '"rollback_of_release_id": rollback_of_release_id or None,\n    }',
            self.source,
        )
        fixture_source = inspect.getsource(__import__(
            "pipeline.__main__", fromlist=["load_curated_fixtures"]
        ).load_curated_fixtures)
        self.assertIn(
            'if fixture_evidence_record is not None:\n        fixture_run_parameters["local_evidence_file"]',
            fixture_source,
        )

    def test_release_snapshots_league_and_all_team_payloads(self) -> None:
        self.assertIn('team_candidate_view = (', self.source)
        self.assertIn('"analysis.team_dashboard_release_candidates_v4"', self.source)
        self.assertIn('"analysis.team_dashboard_classification_incremental_20260722_v1"', self.source)
        self.assertIn("len(team_payloads) != 16", self.source)
        self.assertIn("insert into reporting.league_release_payloads_v2", self.source)
        self.assertIn("insert into reporting.team_dashboard_payloads_v2", self.source)
        self.assertIn("release_reason_code", self.source)

    def test_classification_successor_uses_incremental_candidates(self) -> None:
        self.assertIn("classification-only successor inherits every non-classification field", self.source)
        self.assertIn("analysis.league_dashboard_classification_incremental_20260722_v1", self.source)
        self.assertIn("analysis.team_dashboard_classification_incremental_20260722_v1", self.source)
        self.assertIn("INCREMENTAL_CLASSIFICATION_BUNDLE_MIGRATION_VERSION", self.source)

    def test_database_generates_payload_hashes(self) -> None:
        league_insert = self.source.split(
            "insert into reporting.league_release_payloads_v2", 1
        )[1].split("insert into reporting.team_dashboard_payloads_v2", 1)[0]
        self.assertIn("(release_id, dashboard_payload)", league_insert)
        self.assertNotIn("payload_sha256)", league_insert)

    def test_atomic_readback_checks_whitelisted_public_views(self) -> None:
        self.assertIn("from reporting.latest_league_dashboard_v2", self.source)
        self.assertIn("from reporting.latest_team_dashboard_v2", self.source)
        self.assertIn("published_team_count <> 16", self.source)
        self.assertIn("stored_league_hash is distinct from", self.source)
        self.assertIn("stored_team_hashes is distinct from", self.source)
        self.assertLess(
            self.source.index("set status = 'approved'"),
            self.source.index("published league dashboard bundle must expose exactly one league row"),
        )

    def test_promotion_reads_database_candidates_once_and_uses_bound_triggers(self) -> None:
        write_sql = self.source.split("sql = f\"\"\"", 1)[1].split(
            "output_arg = clean_text(args.output or \"\")", 1
        )[0]
        self.assertIn("create temp table reviewed_league_members", write_sql)
        self.assertIn("reviewed bundle member identities changed after preflight validation", write_sql)
        # The frozen route resolves this exact V2 view; the additive V6 route
        # supplies its registered zero-or-sixteen member view instead.
        self.assertIn('else "analysis.league_member_releases_v2"', self.source)
        self.assertIn("from {member_view}\n            where season = {params.text(season)}", write_sql)
        self.assertEqual(write_sql.count("join {league_candidate_view} candidate"), 1)
        self.assertEqual(write_sql.count("join {team_candidate_view} candidate"), 1)
        self.assertIn("join reviewed_league_members expected", write_sql)
        # Ordinary releases still re-read bound database candidates. The one
        # reviewed JSON insertion is confined to the V6-only retained-bundle
        # rollback branch, which the frozen V2 route cannot enter.
        self.assertEqual(write_sql.count("params.jsonb(dashboard)"), 1)
        self.assertLess(
            write_sql.index("if rollback_of_release_id:"),
            write_sql.index("params.jsonb(dashboard)"),
        )

    def test_promotion_rehashes_the_stored_jsonb_bundle(self) -> None:
        self.assertIn("stored_bundle_hash", self.source)
        self.assertIn("stored bundle payload hash differs from the canonical candidate hash", self.source)
        self.assertIn("REVIEWED_BUNDLE_PAYLOAD_VALIDATION_MIGRATION_VERSION", self.source)
        self.assertIn('"payload_hash_validation_migration"', self.source)
        self.assertIn('"payload_candidate_validation_migration"', self.source)
        self.assertIn("INCREMENTAL_CLASSIFICATION_BUNDLE_MIGRATION_VERSION", self.source)

    def test_preflight_preserves_postgres_canonical_numeric_text(self) -> None:
        self.assertIn("document::text as bundle_payload_json", self.candidate_source)
        self.assertIn("write_text_atomic(output_path, canonical_bundle_json", self.source)
        self.assertIn("reviewed_canonical_sha256 != bundle_payload_sha256", self.source)
        self.assertIn("reviewed preflight canonical hash", self.source)

    def test_candidate_loader_expands_each_build_pinned_view_once(self) -> None:
        self.assertEqual(self.candidate_source.count("from {league_candidate_view}"), 1)
        self.assertEqual(self.candidate_source.count("from {team_candidate_view}"), 1)
        self.assertIn("candidates as team_payloads", self.candidate_source)
        self.assertIn("hashes as team_payload_sha256s", self.candidate_source)
        self.assertIn("candidate_assembly_reads", self.source)

    def test_payload_validation_migration_uses_hashes_and_member_identities(self) -> None:
        migration = (
            Path(__file__).resolve().parents[1]
            / "supabase/migrations/20260720180000_reviewed_bundle_payload_validation.sql"
        ).read_text()
        self.assertIn("new.payload_sha256 is distinct from expected_hash", migration)
        self.assertIn("payload.team_release_id = member.team_release_id", migration)
        self.assertIn("payload.curated_build_id = member.curated_build_id", migration)
        self.assertIn("live.season = context.season", migration)
        self.assertIn("inserted_count <> 16", migration)
        self.assertNotIn("analysis.league_dashboard_release_candidates_v4", migration)
        self.assertNotIn("analysis.team_dashboard_release_candidates_v4", migration)

        incremental = (
            Path(__file__).resolve().parents[1]
            / "supabase/migrations/20260722150000_incremental_classification_bundle_release.sql"
        ).read_text()
        self.assertIn("create or replace function reporting.validate_league_dashboard_v2_candidate()", incremental)
        self.assertIn("create or replace function reporting.validate_team_dashboard_v2_candidates()", incremental)
        self.assertIn("analysis.league_dashboard_classification_incremental_20260722_v1", incremental)
        self.assertIn("analysis.team_dashboard_classification_incremental_20260722_v1", incremental)
        self.assertIn("changed fields outside the accepted classification sections", incremental)

    def test_rollback_only_hosted_contract_covers_validator_paths(self) -> None:
        harness = (
            Path(__file__).resolve().parents[1]
            / "tests/reviewed_bundle_payload_validation_live.mjs"
        ).read_text()
        self.assertIn("await client.query(\"begin\")", harness)
        self.assertIn("await client.query(migrationSql)", harness)
        self.assertIn("await client.query(\"rollback\")", harness)
        for scenario in (
            "valid_v3",
            "tampered_league_hash",
            "tampered_team_hash",
            "wrong_member_identity",
            "fifteen_team_rows",
            "seventeen_team_rows",
        ):
            self.assertIn(scenario, harness)
        self.assertIn("live_with_extra_season", harness)
        self.assertIn("valid_v2", harness)

    def test_export_is_written_before_promotion_and_removed_on_failure(self) -> None:
        self.assertLess(
            self.source.index("write_json_atomic(staged_export_path"),
            self.source.index("run_sql(sql"),
        )
        self.assertIn("os.replace(staged_export_path, export_path)", self.source)

    def test_release_remains_commit_and_migration_gated(self) -> None:
        self.assertIn('provenance["code_version"].endswith("-dirty")', self.source)
        self.assertIn("supabase_migrations.schema_migrations", self.source)
        self.assertIn("league release requires --preflight", self.source)


if __name__ == "__main__":
    unittest.main()
