from __future__ import annotations

import inspect
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
        self.assertIn("from analysis.team_dashboard_payload_v2", self.source)
        self.assertIn("len(team_payloads) != 16", self.source)
        self.assertIn("insert into reporting.league_release_payloads_v2", self.source)
        self.assertIn("insert into reporting.team_dashboard_payloads_v2", self.source)
        self.assertIn("'league_dashboard_release_v2', 16, 17", self.source)

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

    def test_database_candidates_are_inserted_without_json_number_round_trip(self) -> None:
        self.assertIn("join analysis.league_dashboard_payload_v2 candidate", self.source)
        self.assertIn("join analysis.team_dashboard_payload_v2 candidate", self.source)
        self.assertNotIn("select id, {params.jsonb(dashboard)}", self.source)

    def test_export_is_written_before_promotion_and_removed_on_failure(self) -> None:
        self.assertLess(self.source.index("write_json_atomic(export_path"), self.source.index("run_sql(sql"))
        self.assertIn("export_path.unlink(missing_ok=True)", self.source)

    def test_release_remains_commit_and_migration_gated(self) -> None:
        self.assertIn('provenance["code_version"].endswith("-dirty")', self.source)
        self.assertIn("supabase_migrations.schema_migrations", self.source)
        self.assertIn("league release requires --preflight", self.source)


if __name__ == "__main__":
    unittest.main()
