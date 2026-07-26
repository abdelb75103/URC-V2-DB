from __future__ import annotations

from pathlib import Path
import unittest

from pipeline.__main__ import (
    CONTACT_DISTRIBUTION_READER_V4_MIGRATION_VERSION,
    CONTACT_DISTRIBUTION_V5_MIGRATION_VERSION,
)


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT / "supabase/migrations/20260726160000_contact_distribution_v5.sql"
)
READER = (
    ROOT / "supabase/migrations/20260726161000_contact_distribution_reader_v4.sql"
)
REFRESH = ROOT / "tools/sql/refresh_analysis_window_v5_candidate_snapshots.sql"
REGISTER = ROOT / "tools/sql/register_contact_distribution_migrations.sql"


class ContactDistributionV5SqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.reader = READER.read_text(encoding="utf-8")
        cls.refresh = REFRESH.read_text(encoding="utf-8")
        cls.register = REGISTER.read_text(encoding="utf-8")

    def test_contact_context_comes_from_curated_injuries(self) -> None:
        """The released cohort view deliberately does not project it."""
        self.assertIn("join curated.injuries injury on injury.id = cohort.injury_id", self.sql)
        self.assertIn("analysis.analysis_window_injury_cohort_v5_snapshot", self.sql)
        self.assertIn("join analysis.league_member_releases_v2 member", self.sql)

    def test_the_unknown_slice_is_emitted(self) -> None:
        """Abdel, 26 July 2026: the Unknown mechanism slice stays."""
        self.assertIn("('unknown', 'Unknown')", self.sql)
        self.assertIn("'unknown'", self.sql)

    def test_every_other_payload_section_is_asserted_byte_identical(self) -> None:
        self.assertIn("dashboard - 'contact_distribution' <> coverage.dashboard", self.sql)

    def test_the_verified_acceptance_numbers_are_pinned(self) -> None:
        for row in (
            "('all', 'contact', 943, 443)",
            "('all', 'non_contact', 565, 280)",
            "('all', 'unknown', 150, 62)",
            "('match', 'contact', 671, 327)",
            "('training', 'non_contact', 406, 191)",
            "('unknown', 'unknown', 15, 4)",
        ):
            with self.subTest(row=row):
                self.assertIn(row, self.sql)

    def test_candidate_views_are_repointed_at_the_contact_layer(self) -> None:
        for view in (
            "analysis.team_dashboard_release_candidates_analysis_window_v5",
            "analysis.league_dashboard_release_candidates_analysis_window_v5",
        ):
            with self.subTest(view=view):
                self.assertIn(f"create or replace view\n  {view}", self.sql)
        self.assertIn(
            "from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot;",
            self.sql,
        )
        self.assertIn(
            "from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot;",
            self.sql,
        )

    def test_nothing_frozen_is_edited(self) -> None:
        """Additive only: no drop, no alter, no touching v2/v3 readers."""
        lowered = self.sql.lower() + self.reader.lower()
        for forbidden in ("drop view", "drop materialized view", "alter view", "drop function"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, lowered)
        self.assertNotIn("create or replace view reporting.latest_team_dashboard_v2", lowered)
        self.assertNotIn("create or replace view reporting.latest_team_dashboard_v3", lowered)

    def test_the_refresh_reruns_the_full_integrity_suite(self) -> None:
        """A refresh replaces the snapshots, so migration-time proof is not enough.

        Both the migration and the refresh must call the one shared definition,
        or the refresh could serve numbers the migration never validated.
        """
        self.assertIn(
            "refresh materialized view\n"
            "  analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot;",
            self.refresh,
        )
        self.assertIn(
            "refresh materialized view\n"
            "  analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot;",
            self.refresh,
        )
        self.assertIn(
            "perform analysis.assert_contact_distribution_v5_integrity();", self.refresh
        )
        self.assertIn(
            "perform analysis.assert_contact_distribution_v5_integrity();", self.sql
        )
        self.assertIn(
            "create function analysis.assert_contact_distribution_v5_integrity()", self.sql
        )

    def test_the_contact_refresh_follows_the_layer_it_inherits_from(self) -> None:
        """Refreshing contact before coverage would rebuild it from stale input."""
        coverage = self.refresh.index(
            "analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot;"
        )
        contact = self.refresh.index(
            "analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot;"
        )
        self.assertLess(coverage, contact)

    def test_the_reader_exposes_the_section_to_web_reader_only(self) -> None:
        for view in ("latest_team_dashboard_v4", "latest_league_dashboard_v4"):
            with self.subTest(view=view):
                self.assertIn(f"create view reporting.{view}", self.reader)
                self.assertIn(f"grant select on reporting.{view} to web_reader;", self.reader)
        self.assertIn("security_invoker = false, security_barrier = true", self.reader)
        self.assertIn("-> 'contact_distribution' as contact_distribution", self.reader)

    def test_the_reader_leaks_no_internal_identifier(self) -> None:
        projection = self.reader[: self.reader.index("grant select")]
        for internal in ("dashboard_payload as", "release_id as", "curated_build_id as"):
            with self.subTest(internal=internal):
                self.assertNotIn(internal, projection)

    def test_both_migrations_are_registered_and_required(self) -> None:
        self.assertEqual(CONTACT_DISTRIBUTION_V5_MIGRATION_VERSION, "20260726160000")
        self.assertEqual(CONTACT_DISTRIBUTION_READER_V4_MIGRATION_VERSION, "20260726161000")
        for version in ("20260726160000", "20260726161000"):
            with self.subTest(version=version):
                self.assertIn(version, self.register)
        self.assertIn("has_table_privilege(", self.register)


if __name__ == "__main__":
    unittest.main()
