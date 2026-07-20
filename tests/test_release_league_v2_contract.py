from __future__ import annotations

import inspect
from pathlib import Path
import unittest

from pipeline.__main__ import release_league


class ReleaseLeagueV2ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = inspect.getsource(release_league)

    def test_preflight_reviews_one_public_bundle(self) -> None:
        self.assertIn('"schema_version": "urc_dashboard_bundle_v2"', self.source)
        self.assertIn('"league": dashboard', self.source)
        self.assertIn('"teams": [', self.source)
        self.assertIn("diff_json_documents(reviewed_bundle, public_bundle)", self.source)

    def test_release_snapshots_league_and_all_team_payloads(self) -> None:
        self.assertIn("from analysis.team_dashboard_release_candidates_v4", self.source)
        self.assertIn("len(team_payloads) != 16", self.source)
        self.assertIn("insert into reporting.league_release_payloads_v2", self.source)
        self.assertIn("insert into reporting.team_dashboard_payloads_v2", self.source)
        self.assertIn("release_reason_code", self.source)

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

    def test_promotion_inserts_reviewed_json_without_recomputing_candidates(self) -> None:
        write_sql = self.source.split("sql = f\"\"\"", 1)[1].split(
            "output_arg = clean_text(args.output or \"\")", 1
        )[0]
        self.assertIn("create temp table reviewed_league_members", write_sql)
        self.assertIn("reviewed bundle member identities changed after preflight validation", write_sql)
        self.assertIn("select current_league_release.id, {params.jsonb(dashboard)}", write_sql)
        self.assertIn("cross join reviewed_league_team_payloads payload", write_sql)
        self.assertIn("from analysis.league_member_releases_v2\n            where season = {params.text(season)}", write_sql)
        self.assertNotIn("analysis.league_dashboard_release_candidates_v4 candidate", write_sql)
        self.assertNotIn("analysis.team_dashboard_release_candidates_v4 candidate", write_sql)

    def test_promotion_rehashes_the_stored_jsonb_bundle(self) -> None:
        self.assertIn("stored_bundle_hash", self.source)
        self.assertIn("stored bundle payload hash differs from the canonical candidate hash", self.source)
        self.assertIn("REVIEWED_BUNDLE_PAYLOAD_VALIDATION_MIGRATION_VERSION", self.source)

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
