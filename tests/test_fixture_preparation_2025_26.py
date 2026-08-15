from __future__ import annotations

import csv
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from pipeline.fixture_preparation import (
    OFFICIAL_URC_2025_26_RESPONSE_SHA256,
    prepare_urc_2025_26_fixtures,
)


class FixturePreparation2025_26Tests(unittest.TestCase):
    provenance = {
        "source_url": "https://www.unitedrugby.com/graphql",
        "source_request_sha256": "57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af",
        "retrieved_at": "2026-08-15T01:09:13Z",
    }

    def write_response(self, path: Path, matches: list[dict]) -> None:
        path.write_text(json.dumps({"data": {"matchstats": matches}}), encoding="utf-8")

    def match(self, match_id: int, round_value: int, home: str = "Home", away: str = "Away") -> dict:
        return {
            "match_id": match_id,
            "match_datetime": "2025-09-26 17:00:00",
            "stats_data": {
                "id": match_id,
                "round": round_value,
                "season": {"id": 202501},
                "homeTeam": {"team": {"id": 1, "name": home}},
                "awayTeam": {"team": {"id": 2, "name": away}},
            },
        }

    def valid_season(self) -> list[dict]:
        teams = [f"Team {index}" for index in range(16)]
        matches: list[dict] = []
        match_id = 1
        # A deterministic 15-round circle schedule, then three repeated
        # rounds, supplies the required 18 regular fixtures per team.
        for round_value in range(1, 19):
            offset = (round_value - 1) % 15
            for index in range(8):
                home = teams[(offset + index) % 16]
                away = teams[(offset + 15 - index) % 16]
                matches.append(self.match(match_id, round_value, home, away))
                match_id += 1
        for round_value, pairings in {
            19: [("Team 0", "Team 1"), ("Team 2", "Team 3"), ("Team 4", "Team 5"), ("Team 6", "Team 7")],
            20: [("Team 0", "Team 2"), ("Team 4", "Team 6")],
            21: [("Team 0", "Team 4")],
        }.items():
            for home, away in pairings:
                matches.append(self.match(match_id, round_value, home, away))
                match_id += 1
        return matches

    def test_writes_loader_contract_and_stable_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "official.json"
            output = root / "fixtures.csv"
            self.write_response(source, self.valid_season())

            # This synthetic response exercises deterministic transformation.
            # The separate protected-source test exercises the immutable
            # official response and committed checksum gate end to end.
            with patch("pipeline.fixture_preparation.validate_fixture_rows"):
                summary = prepare_urc_2025_26_fixtures(source, output, **self.provenance)

            with output.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(rows[0], {
                "season": "2025-26",
                "match_id": "1",
                "stage": "Regular season",
                "round": "1",
                "source_date": "2025-09-26",
                "corrected_date": "2025-09-26",
                "date_status": "source_confirmed",
                "home_team": "Team 0",
                "away_team": "Team 15",
                "source_file_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "source_row_number": "2",
                "source_locator": "https://www.unitedrugby.com/graphql#data.matchstats[0]",
                "source_request_sha256": "57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af",
                "source_response_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                "retrieved_at": "2026-08-15T01:09:13Z",
            })
            self.assertEqual(summary["stage_counts"], {
                "Regular season": 144, "Quarter-final": 4, "Semi-final": 2, "Final": 1,
            })
            self.assertEqual(summary["source_sha256"], hashlib.sha256(source.read_bytes()).hexdigest())

    def test_rejects_invalid_fixture_invariants_before_writing_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "official.json"
            output = root / "fixtures.csv"
            self.write_response(source, [self.match(44, 1, "Alpha", "Alpha")])

            with self.assertRaisesRegex(ValueError, "self-match"):
                prepare_urc_2025_26_fixtures(source, output, **self.provenance)

            self.assertFalse(output.exists())

    def test_full_official_response_has_expected_league_structure(self) -> None:
        source = Path("/Users/abdelbabiker/Desktop/URC-V2-DB-private/2025-26/fixtures/urc_2025_26_fixture_response.json")
        if not source.exists():
            self.skipTest("protected official response is unavailable")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "fixtures.csv"
            summary = prepare_urc_2025_26_fixtures(
                source, output, expected_source_sha256=OFFICIAL_URC_2025_26_RESPONSE_SHA256,
                **self.provenance,
            )

            self.assertEqual(summary["fixture_count"], 151)
            self.assertEqual(summary["stage_counts"], {
                "Regular season": 144,
                "Quarter-final": 4,
                "Semi-final": 2,
                "Final": 1,
            })
            self.assertEqual(summary["team_count"], 16)
            self.assertEqual(summary["regular_matches_per_team"], 18)
            self.assertEqual(len(summary["output_sha256"]), 64)

    def test_refuses_to_write_prepared_rows_inside_the_repository(self) -> None:
        source = Path("/Users/abdelbabiker/Desktop/URC-V2-DB-private/2025-26/fixtures/urc_2025_26_fixture_response.json")
        if not source.exists():
            self.skipTest("protected official response is unavailable")
        repository_output = Path(__file__).resolve().parents[1] / "output" / "fixture-test.csv"
        with self.assertRaisesRegex(ValueError, "outside the repository"):
            prepare_urc_2025_26_fixtures(source, repository_output, **self.provenance)

    def test_rejects_unverifiable_fixture_provenance_before_writing_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "official.json"
            output = root / "fixtures.csv"
            self.write_response(source, self.valid_season())

            with self.assertRaisesRegex(ValueError, "request checksum"):
                prepare_urc_2025_26_fixtures(
                    source,
                    output,
                    source_url=self.provenance["source_url"],
                    source_request_sha256="short",
                    retrieved_at=self.provenance["retrieved_at"],
                )
            self.assertFalse(output.exists())
