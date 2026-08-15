"""Pure, season-keyed contracts for additive URC pipeline successors.

The frozen 2024-25 route deliberately remains represented as the exact
accepted tuples already used by ``release-league``.  New seasons must opt in
with an explicit contract: there is no implied fallback to a historical
analysis version or fixture shape.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from datetime import datetime
import re
from typing import Mapping, Sequence


ReleaseTuple = tuple[str, str, str]

FROZEN_2024_25_RELEASE_TUPLES = frozenset(
    {
        ("v2", "v2", "v2"),
        ("v2", "reporting_classification_2026-07-20_v1", "v2"),
        ("v3", "reporting_classification_2026-07-20_v1", "season_bound_2026-07-20_v1"),
        ("v3", "reporting_classification_2026-07-22_v2", "season_bound_2026-07-20_v1"),
        ("v4", "reporting_classification_2026-07-22_v2", "lineage_2024-25_2026-07-24_v1"),
        ("v5", "reporting_classification_2026-07-22_v2", "analysis_window_2024-25_2026-07-25_v1"),
    }
)

YEAR2_2025_26_RELEASE_TUPLE: ReleaseTuple = (
    "v6",
    "reporting_classification_2026-07-22_v2",
    "analysis_window_2025-26_2026-08-15_v1",
)


@dataclass(frozen=True)
class FixtureContract:
    season: str
    fixture_count: int
    team_count: int
    regular_matches_per_team: int
    stage_counts: Mapping[str, int]
    required_columns: frozenset[str]


@dataclass(frozen=True)
class ReleaseContract:
    season: str
    analysis_version: str
    classification_view_version: str
    cohort_view_version: str
    league_candidate_view: str | None = None
    team_candidate_view: str | None = None
    injury_cohort_view: str | None = None
    league_monthly_view: str | None = None
    league_summary_view: str | None = None
    required_migrations: tuple[str, ...] = ()
    release_rule_version: str | None = None
    release_reason_code: str | None = None
    decision_recorded_at: str | None = None
    cohort_adjudication_ref: str | None = None
    cohort_evidence_locator: str | None = None
    cohort_evidence_sha256: str | None = None

    @property
    def release_tuple(self) -> ReleaseTuple:
        return (
            self.analysis_version,
            self.classification_view_version,
            self.cohort_view_version,
        )


YEAR2_2025_26_FIXTURE_CONTRACT = FixtureContract(
    season="2025-26",
    fixture_count=151,
    team_count=16,
    regular_matches_per_team=18,
    stage_counts={
        "Regular season": 144,
        "Quarter-final": 4,
        "Semi-final": 2,
        "Final": 1,
    },
    required_columns=frozenset(
        {
            "season",
            "match_id",
            "stage",
            "round",
            "source_date",
            "corrected_date",
            "date_status",
            "home_team",
            "away_team",
            "source_file_sha256",
            "source_row_number",
            "source_locator",
            "source_request_sha256",
            "source_response_sha256",
            "retrieved_at",
        }
    ),
)

YEAR2_2025_26_RELEASE_CONTRACT = ReleaseContract(
    season="2025-26",
    analysis_version=YEAR2_2025_26_RELEASE_TUPLE[0],
    classification_view_version=YEAR2_2025_26_RELEASE_TUPLE[1],
    cohort_view_version=YEAR2_2025_26_RELEASE_TUPLE[2],
    league_candidate_view="analysis.league_dashboard_release_candidates_analysis_window_v6",
    team_candidate_view="analysis.team_dashboard_release_candidates_analysis_window_v6",
    injury_cohort_view="analysis.analysis_window_injury_cohort_v6",
    league_monthly_view="analysis.analysis_window_league_monthly_v6",
    league_summary_view="analysis.analysis_window_league_summary_v6",
    required_migrations=("20260815010000",),
    release_rule_version="league_dashboard_release_2026-08-15_v6",
    release_reason_code="league_dashboard_release_v6",
    decision_recorded_at="2026-08-15",
    cohort_adjudication_ref="ANALYSIS-WINDOW-2025-26-01",
    cohort_evidence_locator="docs/evidence/urc_2025_26_reporting_contract.json",
    cohort_evidence_sha256="a9c5ebc40a063564d70a2cc2e1f45fddb7069a900d398bea5b32208b65eaf3fe",
)

_FIXTURE_CONTRACTS = {YEAR2_2025_26_FIXTURE_CONTRACT.season: YEAR2_2025_26_FIXTURE_CONTRACT}
_RELEASE_CONTRACTS = {YEAR2_2025_26_RELEASE_CONTRACT.season: (YEAR2_2025_26_RELEASE_CONTRACT,)}


def fixture_contract_for(season: str) -> FixtureContract | None:
    """Return a season's explicit fixture contract, if it has one."""
    return _FIXTURE_CONTRACTS.get(season)


def release_contract_for(season: str, release_tuple: ReleaseTuple) -> ReleaseContract:
    """Resolve only an explicitly accepted, season-bound release tuple.

    Historical tuples are recognised only for their frozen season.  A tuple
    accepted for another season is an error, rather than an accidental reuse.
    """
    if season == "2024-25":
        if release_tuple in FROZEN_2024_25_RELEASE_TUPLES:
            return ReleaseContract(season=season, *release_tuple)
        if any(
            release_tuple == contract.release_tuple
            for contracts in _RELEASE_CONTRACTS.values()
            for contract in contracts
        ):
            raise ValueError(f"release tuple {release_tuple!r} is not accepted for season {season!r}")
        raise ValueError(f"unsupported release tuple {release_tuple!r} for season {season!r}")

    contracts = _RELEASE_CONTRACTS.get(season)
    if not contracts:
        raise ValueError(f"unsupported season {season!r}")
    for contract in contracts:
        if contract.release_tuple == release_tuple:
            return contract
    if release_tuple in FROZEN_2024_25_RELEASE_TUPLES:
        raise ValueError(f"release tuple {release_tuple!r} is not accepted for season {season!r}")
    raise ValueError(f"unsupported release tuple {release_tuple!r} for season {season!r}")


def validate_fixture_rows(
    season: str, rows: Sequence[Mapping[str, str]],
) -> dict[str, object]:
    """Validate the narrow, public fixture loader contract before DB access."""
    contract = fixture_contract_for(season)
    if contract is None:
        raise ValueError(f"no explicit fixture contract for season {season!r}")
    if not rows:
        raise ValueError("fixture rows are empty")
    missing = sorted(contract.required_columns - set(rows[0]))
    if missing:
        raise ValueError(f"fixture rows missing required columns: {', '.join(missing)}")
    if len(rows) != contract.fixture_count:
        raise ValueError(f"expected {contract.fixture_count} fixtures, got {len(rows)}")

    stage_counts: Counter[str] = Counter()
    match_ids: list[str] = []
    teams: set[str] = set()
    regular_matches: Counter[str] = Counter()
    for index, row in enumerate(rows, start=2):
        row_season = str(row.get("season", "")).strip()
        if row_season != season:
            raise ValueError(f"fixture season mismatch at source row {index}: {row_season!r}")
        match_id = str(row.get("match_id", "")).strip()
        home = str(row.get("home_team", "")).strip()
        away = str(row.get("away_team", "")).strip()
        if not match_id:
            raise ValueError(f"missing match ID at source row {index}")
        if not home or not away:
            raise ValueError(f"missing fixture team at source row {index}")
        if home.casefold() == away.casefold():
            raise ValueError(f"self-match at source row {index}")
        if fixture_contract_for(season) is not None:
            source_locator = str(row.get("source_locator", "")).strip()
            source_request_sha256 = str(row.get("source_request_sha256", "")).strip()
            source_response_sha256 = str(row.get("source_response_sha256", "")).strip()
            source_file_sha256 = str(row.get("source_file_sha256", "")).strip()
            retrieved_at = str(row.get("retrieved_at", "")).strip()
            if not source_locator.startswith("https://"):
                raise ValueError(f"fixture provenance locator must be public https at source row {index}")
            if not re.fullmatch(r"[0-9a-f]{64}", source_request_sha256):
                raise ValueError(f"fixture request checksum must be SHA-256 at source row {index}")
            if not re.fullmatch(r"[0-9a-f]{64}", source_response_sha256):
                raise ValueError(f"fixture response checksum must be SHA-256 at source row {index}")
            if source_file_sha256 != source_response_sha256:
                raise ValueError(f"fixture response checksum mismatch at source row {index}")
            try:
                parsed_retrieved_at = datetime.fromisoformat(retrieved_at.replace("Z", "+00:00"))
            except ValueError as error:
                raise ValueError(f"fixture retrieval timestamp is invalid at source row {index}") from error
            if parsed_retrieved_at.tzinfo is None:
                raise ValueError(f"fixture retrieval timestamp lacks timezone at source row {index}")
        match_ids.append(match_id)
        teams.update((home, away))
        stage = str(row.get("stage", "")).strip()
        stage_counts[stage] += 1
        if stage == "Regular season":
            regular_matches.update((home, away))

    if len(match_ids) != len(set(match_ids)):
        raise ValueError("fixture match IDs must be unique")
    stage_counts_dict = dict(stage_counts)
    if stage_counts_dict != dict(contract.stage_counts):
        raise ValueError(f"unexpected fixture stages: {stage_counts_dict}")
    if len(teams) != contract.team_count:
        raise ValueError(f"expected {contract.team_count} teams, got {len(teams)}")
    invalid_regular_counts = {
        team: count
        for team, count in regular_matches.items()
        if count != contract.regular_matches_per_team
    }
    if invalid_regular_counts or len(regular_matches) != contract.team_count:
        raise ValueError(
            "each team must have exactly "
            f"{contract.regular_matches_per_team} regular-season matches: {invalid_regular_counts}"
        )
    return {
        "fixture_count": len(rows),
        "team_count": len(teams),
        "regular_matches_per_team": contract.regular_matches_per_team,
        "stage_counts": stage_counts_dict,
    }


def fixture_provenance_rows(
    season: str, rows: Sequence[Mapping[str, str]],
) -> list[dict[str, object]]:
    """Return insert-ready public fixture provenance after complete validation."""
    validate_fixture_rows(season, rows)
    return [
        {
            "source_row_number": int(str(row["source_row_number"])),
            "upstream_match_id": str(row["match_id"]).strip(),
            "source_locator": str(row["source_locator"]).strip(),
            "source_request_sha256": str(row["source_request_sha256"]).strip(),
            "source_response_sha256": str(row["source_response_sha256"]).strip(),
            "retrieved_at": str(row["retrieved_at"]).strip(),
        }
        for row in rows
    ]
