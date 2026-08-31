from __future__ import annotations

import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (
    ROOT
    / "supabase/migrations/20260831110000_urc_2025_26_corrected_league_candidate_snapshot.sql"
)
REGISTRATION = (
    ROOT
    / "tools/sql/register_urc_2025_26_corrected_league_candidate_snapshot_migration.sql"
)


class Year2CorrectedLeagueCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.raw = MIGRATION.read_text(encoding="utf-8")
        cls.sql = cls.raw.lower()
        cls.registration = REGISTRATION.read_text(encoding="utf-8")

    def test_exact_migration_is_checksum_bound(self) -> None:
        self.assertEqual(
            hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
            "9175bf77c27196193374e45a01f2ec3290a7a4ac6da3e66dfd0d97cbb6b40845",
        )
        self.assertEqual(
            self.registration.count(
                "migration_sha256=9175bf77c27196193374e45a01f2ec3290a7a4ac6da3e66dfd0d97cbb6b40845"
            ),
            2,
        )

    def test_snapshot_binds_every_exact_corrected_team_release(self) -> None:
        release_ids = (
            "578d6c8d-9dce-4a42-a607-36e41f5acda7",
            "4ace6ac5-5c89-4025-90d5-86be53f18d61",
            "937a8cbc-0508-4bef-9055-cab3f508e909",
            "5a139497-50a5-462c-b2f9-e4ddc1bc5c29",
            "f9bce99a-d244-41ff-8758-22371c4bbde8",
            "23ba5ec9-f522-46df-8c39-c7e524fd75ec",
            "7061da59-94c3-4e43-a124-e6bb0d21dc44",
            "6cd84dc2-3fc4-44bd-a1ed-6fb2883b61ad",
            "c4c73952-49c0-4ea6-8299-0e2bfcfcf99a",
            "6d225fd3-9e9e-4aac-883f-dbab7fd8f8d7",
            "c786bdf5-6057-4bab-b114-666190770e21",
            "ce2fad6d-33a9-4b00-8590-75aafb14edf7",
            "93be1cbe-bdce-43ba-9200-483aef48afe2",
            "eb0b5486-1370-4f4f-9f68-f4ad57abb2b0",
            "7f357b01-fbdf-4dab-b4b7-c3fefc29a55d",
            "58939fb6-d161-43be-826d-f4bd4ff616b7",
        )
        for release_id in release_ids:
            self.assertEqual(self.raw.count(release_id), 1)
        for value in (
            "candidate_snapshot_version = '20260831101000'",
            "2f419706-8c36-58dd-b4cb-e92162e782b8",
            "member_manifest_sha256",
            "count(distinct team_key) from _urc_v6_corrected_members",
        ):
            self.assertIn(value, self.raw)

    def test_scientific_totals_and_known_duration_formulas_are_exact(self) -> None:
        for value in (
            "<> 1484",
            "<> 877",
            "<> 731",
            "<> 19047",
            "87854.0133391047619046::numeric",
            "<> 62481",
            "round((item ->> 'days_lost')::numeric",
            "summary.days_lost / nullif(summary.known_duration_time_loss_injuries, 0)",
            "analysis.injury_type_families_from_payload_v3(profile_payload.rows)",
        ):
            self.assertIn(value, self.raw)

    def test_estimated_exposure_stays_explicitly_unavailable_by_month(self) -> None:
        for value in (
            "14_source_backed_teams_plus_2_temporary_league_mean_estimates",
            "month -> 'exposure_hours' <> 'null'::jsonb",
            "month -> 'distance_km' <> 'null'::jsonb",
            "month -> 'overall_incidence_per_1000h' <> 'null'::jsonb",
            "monthly exposure, rates and distance are unavailable",
        ):
            self.assertIn(value.lower(), self.sql)

    def test_private_immutable_snapshot_replaces_only_candidate_view(self) -> None:
        for value in (
            "enable row level security",
            "before update or delete",
            "create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6",
            "revoke all on analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000",
        ):
            self.assertIn(value, self.sql)
        self.assertNotRegex(self.sql, r"(?m)^\s*(update|delete\s+from|truncate)\b")


if __name__ == "__main__":
    unittest.main()
