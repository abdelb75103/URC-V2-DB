from __future__ import annotations

import inspect
import unittest

from pipeline.__main__ import (
    assert_public_payload_is_publishable,
    current_league_bundle_snapshot,
    export_team_dashboard_parity_json,
    without_keys,
)


class ExportTeamDashboardParityTests(unittest.TestCase):
    """The 16 committed per-team files must track the served bundle.

    release-league rewrites only the league export, so without this the
    per-team parity exports keep the numbers of whichever release last wrote
    them while the website serves the current approved bundle.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.source = inspect.getsource(export_team_dashboard_parity_json)
        cls.snapshot_source = inspect.getsource(current_league_bundle_snapshot)

    def test_exports_come_from_the_approved_bundle(self) -> None:
        self.assertIn("current_league_bundle_snapshot(season)", self.source)
        # Not the frozen per-team _v1 release path, which would write old numbers.
        self.assertNotIn("export_release_dashboard_json", self.source)

    def test_resolves_the_bundle_through_the_view_the_website_reads(self) -> None:
        # A looser "newest approved release" rule could export a bundle the
        # website does not serve, because the view additionally requires 16
        # members, full roster coverage, and matching exposure denominators.
        self.assertIn(
            "reporting.latest_approved_dashboard_bundle_v2", self.snapshot_source
        )

    def test_writes_the_committed_per_team_paths(self) -> None:
        self.assertIn('f"{team_key}_dashboard_{season}.json"', self.source)
        self.assertIn('Path("content") / "reporting"', self.source)
        self.assertIn("write_json_atomic(path, public)", self.source)

    def test_rejects_an_incomplete_payload_instead_of_writing_it(self) -> None:
        self.assertIn("approved bundle contains an incomplete team payload", self.source)

    def test_records_the_release_identity_it_exported(self) -> None:
        self.assertIn("**metadata", self.source)
        self.assertIn('"team_parity_exported"', self.source)

    def test_internal_keys_never_reach_the_committed_payload(self) -> None:
        payload = {
            "team": "Munster",
            "source_files": [{"sha256": "deadbeef"}],
            "pipeline_evidence": {"run_id": "abc"},
            "headline": {"recorded_injuries": 125},
            "nested": {"source_files": ["should also go"]},
        }
        public = without_keys(payload, {"source_files", "pipeline_evidence"})
        self.assertNotIn("source_files", public)
        self.assertNotIn("pipeline_evidence", public)
        self.assertNotIn("source_files", public["nested"])
        self.assertEqual(public["headline"], {"recorded_injuries": 125})
        self.assertEqual(public["team"], "Munster")

    def test_protected_alias_placeholder_blocks_the_export(self) -> None:
        with self.assertRaises(SystemExit) as blocked:
            assert_public_payload_is_publishable(
                {"comparison": [{"label": "Team Q", "value": 3}]}, "munster"
            )
        self.assertIn("protected club-alias", str(blocked.exception))

    def test_player_pseudonym_blocks_the_export(self) -> None:
        with self.assertRaises(SystemExit) as blocked:
            assert_public_payload_is_publishable(
                {"rows": [{"player": "Ath_0421"}]}, "munster"
            )
        self.assertIn("player pseudonym", str(blocked.exception))

    def test_a_real_shaped_payload_passes_the_gate(self) -> None:
        # Real club names and small counts are explicitly allowed.
        assert_public_payload_is_publishable(
            {
                "team": "Glasgow Warriors",
                "headline": {"recorded_injuries": 1, "time_loss_injuries": 0},
                "comparison": [{"label": "Team", "value": 2}],
            },
            "glasgow",
        )


if __name__ == "__main__":
    unittest.main()
