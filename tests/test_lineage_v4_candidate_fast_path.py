from __future__ import annotations

import inspect
from pathlib import Path
import unittest

from pipeline.__main__ import (
    LINEAGE_V4_CANDIDATE_FAST_PATH_MIGRATION_VERSION,
    release_league,
)

MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "supabase"
    / "migrations"
    / f"{LINEAGE_V4_CANDIDATE_FAST_PATH_MIGRATION_VERSION}_lineage_v4_candidate_fast_path.sql"
)


class LineageV4CandidateFastPathTests(unittest.TestCase):
    """The V4 release path must never plan the legacy candidate union chain.

    Filtering analysis.*_dashboard_release_candidates_v6 on
    analysis_version = 'v4' does not prune the older UNION ALL branches, which
    made every V4 read overrun the pooler and hang the client. The lineage
    candidate views hold exactly the rows v6 contributes for 'v4'.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.source = inspect.getsource(release_league)
        cls.migration = MIGRATION.read_text(encoding="utf-8")

    def test_v4_reads_the_lineage_candidate_views(self) -> None:
        self.assertIn(
            '"analysis.league_dashboard_release_candidates_lineage_v4"', self.source
        )
        self.assertIn(
            '"analysis.team_dashboard_release_candidates_lineage_v4"', self.source
        )
        self.assertNotIn('"analysis.league_dashboard_release_candidates_v6"', self.source)
        self.assertNotIn('"analysis.team_dashboard_release_candidates_v6"', self.source)

    def test_v4_requires_the_fast_path_migration(self) -> None:
        self.assertIn("LINEAGE_V4_CANDIDATE_FAST_PATH_MIGRATION_VERSION", self.source)
        required = self.source.split("if analysis_version == \"v4\":", 1)[1].split("]", 1)[0]
        self.assertIn("LINEAGE_V4_CANDIDATE_FAST_PATH_MIGRATION_VERSION", required)

    def test_lineage_candidate_views_mirror_the_v6_branch(self) -> None:
        self.assertIn(
            "create view analysis.league_dashboard_release_candidates_lineage_v4",
            self.migration,
        )
        self.assertIn(
            "create view analysis.team_dashboard_release_candidates_lineage_v4",
            self.migration,
        )
        # Same source relations and the same literal analysis_version the v6
        # union assigns to this branch in 20260724181000.
        self.assertIn("from analysis.league_dashboard_payload_lineage_v1", self.migration)
        self.assertIn("from analysis.team_dashboard_payload_lineage_v1", self.migration)
        self.assertEqual(2, self.migration.count("'v4'::text as analysis_version"))

    def test_triggers_route_v4_away_from_the_union_chain(self) -> None:
        self.assertIn(
            "join analysis.league_dashboard_release_candidates_lineage_v4 candidate",
            self.migration,
        )
        self.assertIn(
            "left join analysis.team_dashboard_release_candidates_lineage_v4 candidate",
            self.migration,
        )
        # The retained legacy branches must no longer accept V4 contexts, or a
        # V4 release would still plan the union chain inside the trigger.
        self.assertIn("elsif target_analysis_version = 'v4' then", self.migration)
        self.assertIn("and context.analysis_version <> 'v4'", self.migration)

    def test_legacy_release_paths_keep_the_v6_validation(self) -> None:
        self.assertIn(
            "join analysis.league_dashboard_release_candidates_v6 candidate",
            self.migration,
        )
        self.assertIn(
            "left join analysis.team_dashboard_release_candidates_v6 candidate",
            self.migration,
        )


if __name__ == "__main__":
    unittest.main()
