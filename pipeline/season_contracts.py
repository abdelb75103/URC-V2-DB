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
        ("v5", "reporting_classification_2024-25_2026-08-27_v1", "analysis_window_2024-25_2026-07-25_v1"),
        ("v5", "reporting_classification_2024-25_2026-08-27_v1", "analysis_window_2024-25_2026-08-30_v2"),
    }
)

YEAR2_2025_26_RELEASE_TUPLE: ReleaseTuple = (
    "v6",
    "reporting_classification_2025-26_2026-08-31_v3",
    "injury_lineage_2025-26_2026-08-30_v2",
)


@dataclass(frozen=True)
class FixtureContract:
    season: str
    fixture_count: int
    team_count: int
    regular_matches_per_team: int
    stage_counts: Mapping[str, int]
    required_columns: frozenset[str]
    source_locator_prefix: str
    source_request_sha256: str
    upstream_response_sha256: str
    prepared_file_sha256: str
    retrieved_at: str
    evidence_locator: str
    evidence_sha256: str


@dataclass(frozen=True)
class MigrationContract:
    """Exact migration identity expected by a release route."""

    version: str
    name: str
    sha256: str
    registration_statements: tuple[str, ...] = ()

    @property
    def statement(self) -> str:
        return f"migration_sha256={self.sha256}"

    @property
    def statements(self) -> list[str]:
        return [self.statement, *self.registration_statements]


@dataclass(frozen=True)
class ReleaseContract:
    season: str
    analysis_version: str
    classification_view_version: str
    cohort_view_version: str
    league_candidate_view: str | None = None
    team_candidate_view: str | None = None
    league_team_candidate_view: str | None = None
    member_view: str | None = None
    injury_cohort_view: str | None = None
    league_monthly_view: str | None = None
    league_summary_view: str | None = None
    required_migrations: tuple[str, ...] = ()
    required_migration_contracts: tuple[MigrationContract, ...] = ()
    league_required_migration_contracts: tuple[MigrationContract, ...] = ()
    release_rule_version: str | None = None
    release_reason_code: str | None = None
    decision_recorded_at: str | None = None
    cohort_adjudication_ref: str | None = None
    cohort_evidence_locator: str | None = None
    cohort_evidence_sha256: str | None = None
    classification_rule_evidence_locator: str | None = None
    classification_rule_evidence_sha256: str | None = None
    exposure_coverage_evidence_locator: str | None = None
    exposure_coverage_evidence_sha256: str | None = None
    injury_eligibility_evidence_locator: str | None = None
    injury_eligibility_evidence_sha256: str | None = None

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
    source_locator_prefix="https://www.unitedrugby.com/graphql#data.matchstats[",
    source_request_sha256="57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af",
    upstream_response_sha256="411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6",
    prepared_file_sha256="071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b",
    retrieved_at="2026-08-15T01:09:13Z",
    evidence_locator="docs/evidence/urc_2025_26_fixture_preparation.json",
    evidence_sha256="7b9a79ae5aeb3d8895d31e2c8d48ac0a555b40d772739b7949acac57f3a6d7ff",
)

YEAR2_2025_26_RELEASE_CONTRACT = ReleaseContract(
    season="2025-26",
    analysis_version=YEAR2_2025_26_RELEASE_TUPLE[0],
    classification_view_version=YEAR2_2025_26_RELEASE_TUPLE[1],
    cohort_view_version=YEAR2_2025_26_RELEASE_TUPLE[2],
    league_candidate_view="analysis.league_dashboard_release_candidates_analysis_window_v6",
    team_candidate_view="analysis.team_dashboard_release_candidates_analysis_window_v6",
    league_team_candidate_view="analysis.league_team_dashboard_release_candidates_analysis_window_v6",
    member_view="analysis.league_member_releases_v6",
    injury_cohort_view="analysis.urc_2025_26_injury_successor_cohort_v1",
    league_monthly_view="analysis.urc_2025_26_injury_successor_league_monthly_v1",
    league_summary_view="analysis.urc_2025_26_injury_successor_league_summary_v1",
    required_migrations=(
        "20260815010000",
        "20260815020000",
        "20260815030000",
        "20260822010000",
        "20260822020000",
        "20260822030000",
        "20260822220611",
        "20260823120000",
        "20260830150000",
        "20260830155000",
        "20260830170000",
        "20260831100000",
        "20260831101000",
    ),
    required_migration_contracts=(
        MigrationContract(
            version="20260815010000",
            name="urc_2025_26_reporting_contract",
            sha256="d150177f144d08346a0ffc5b63821a840a411be5ded07d21a9d4b3f954165cac",
        ),
        MigrationContract(
            version="20260815020000",
            name="urc_2025_26_reporting_v6",
            sha256="48380753d7ece51221fe64f0345366e72232401247ef0397ca1f33354f710dd2",
        ),
        MigrationContract(
            version="20260815030000",
            name="urc_2025_26_team_release_v6",
            sha256="013973d8abefc004d80ae11aafa5028da47f563c99d55248fb87b9edd0ef41b7",
        ),
        MigrationContract(
            version="20260822010000",
            name="urc_2025_26_fixture_team_aliases",
            sha256="d3409ef9ab0546c46690deb21173eddfb1e3d2fde357a3df16f949029c61865f",
        ),
        MigrationContract(
            version="20260822020000",
            name="urc_2025_26_incomplete_exposure_reporting_v6",
            sha256="2e7d81e2a543e754bbb1f3eb63f750f0a177591a5ec742e7560effa58159c0b8",
        ),
        MigrationContract(
            version="20260822030000",
            name="urc_2025_26_injury_eligibility_bridge",
            sha256="4960c284ab6a5257a7f8c64ef83a45c4aaed7c906b6b1843e8536516dbc95e03",
        ),
        MigrationContract(
            version="20260822220611",
            name="urc_2025_26_v6_candidate_view_optimisation",
            sha256="5e5c734a0d4b14337a6cf0a12f5891fbdd9b4ef7ea71fadc97c1a1d85a4cd8d6",
        ),
        MigrationContract(
            version="20260823120000",
            name="urc_2025_26_v6_league_candidate_fast_path",
            sha256="ad8ed2146569c81020f2d8425a84d053045a1bf727f767949eff0cee97f715eb",
        ),
        MigrationContract(
            version="20260830150000",
            name="urc_2025_26_exposure_successor_placeholders",
            sha256="4f890614d38f6b899b412e0a019cb53fd53306cf6cc557e351e197e9ab489912",
        ),
        MigrationContract(
            version="20260830155000",
            name="urc_2025_26_v6_exposure_successor_team_snapshot",
            sha256="9a5168da5d23bcb775c4e9c71fd03516e5cbc8fd55ad7c4376977d5cdbef326d",
        ),
        MigrationContract(
            version="20260830170000",
            name="urc_2025_26_injury_successor_cutover",
            sha256="06572c701bf99f2dc669c4c27feecb80bca69d0ed756d47b67a14ec4c8367187",
            registration_statements=(
                "injury_successor_version_id=2f419706-8c36-58dd-b4cb-e92162e782b8",
                "classification_view_version=reporting_classification_2025-26_2026-08-30_v2",
                "cohort_view_version=injury_lineage_2025-26_2026-08-30_v2",
            ),
        ),
        MigrationContract(
            version="20260831100000",
            name="urc_2025_26_reporting_key_family_correction",
            sha256="36754c640f808db0dc6e27d58135744005a304ba14cb3be7211b11224335b43f",
            registration_statements=(
                "classification_view_version=reporting_classification_2025-26_2026-08-31_v3",
                "cohort_view_version=injury_lineage_2025-26_2026-08-30_v2",
                "classification_evidence_sha256=d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172",
                "candidate_snapshot_version=20260831100000",
            ),
        ),
        MigrationContract(
            version="20260831101000",
            name="urc_2025_26_family_mapping_contract_correction",
            sha256="a711d6bdd4af0618c2adafb6b30ca7be03f5251150db799bc43915b62e3fd39f",
            registration_statements=(
                "classification_view_version=reporting_classification_2025-26_2026-08-31_v3",
                "cohort_view_version=injury_lineage_2025-26_2026-08-30_v2",
                "classification_evidence_sha256=d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172",
                "candidate_snapshot_version=20260831101000",
                "family_mapping_version=injury_type_family_2026-07-21_v1",
            ),
        ),
    ),
    league_required_migration_contracts=(
        MigrationContract(
            version="20260831110000",
            name="urc_2025_26_corrected_league_candidate_snapshot",
            sha256="9175bf77c27196193374e45a01f2ec3290a7a4ac6da3e66dfd0d97cbb6b40845",
            registration_statements=(
                "classification_view_version=reporting_classification_2025-26_2026-08-31_v3",
                "cohort_view_version=injury_lineage_2025-26_2026-08-30_v2",
                "team_member_count=16",
                "candidate_snapshot_version=20260831110000",
            ),
        ),
        MigrationContract(
            version="20260831111000",
            name="urc_2025_26_corrected_release_contract",
            sha256="3a62db419a073a1ffbf433c81db7f7a44f40f69a7ee967c9f49e2a813638e06a",
            registration_statements=(
                "classification_view_version=reporting_classification_2025-26_2026-08-31_v3",
                "cohort_view_version=injury_lineage_2025-26_2026-08-30_v2",
                "release_contract_table=analysis.accepted_release_contracts_v2",
            ),
        ),
    ),
    release_rule_version="league_dashboard_release_2026-08-31_v6_reporting_correction",
    release_reason_code="league_dashboard_release_v6_reporting_correction",
    decision_recorded_at="2026-08-31",
    cohort_adjudication_ref="INJURY-LINEAGE-2025-26-2026-08-30-V2",
    cohort_evidence_locator="docs/evidence/urc_2025_26_injury_reporting_cutover.json",
    cohort_evidence_sha256="1941f341fa3d49d523ae0093016b8cb79aea07da94edd33c5255edf1ef021988",
    classification_rule_evidence_locator="docs/evidence/urc_2025_26_reporting_key_family_correction.json",
    classification_rule_evidence_sha256="d9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172",
    exposure_coverage_evidence_locator=(
        "docs/evidence/urc_2025_26_exposure_successor_v6.json"
    ),
    exposure_coverage_evidence_sha256=(
        "66ba0a272de96510106a68c74046d4bf59ab04570ed38d83cbb98665f51c3ce1"
    ),
    injury_eligibility_evidence_locator=(
        "docs/evidence/urc_2025_26_injury_eligibility_bridge.json"
    ),
    injury_eligibility_evidence_sha256=(
        "a47d89700b22fdc3c9aa91203aed5227fbf76a2e4e7eab7dd8f18f9e13092ea1"
    ),
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
            source_locator_pattern = re.escape(contract.source_locator_prefix) + r"[0-9]+\]"
            if not re.fullmatch(source_locator_pattern, source_locator):
                raise ValueError(f"fixture provenance locator does not match committed evidence at source row {index}")
            if source_request_sha256 != contract.source_request_sha256:
                raise ValueError(f"fixture request checksum does not match committed evidence at source row {index}")
            if source_response_sha256 != contract.upstream_response_sha256:
                raise ValueError(f"fixture response checksum does not match committed evidence at source row {index}")
            if source_file_sha256 != source_response_sha256:
                raise ValueError(f"fixture response checksum mismatch at source row {index}")
            try:
                parsed_retrieved_at = datetime.fromisoformat(retrieved_at.replace("Z", "+00:00"))
            except ValueError as error:
                raise ValueError(f"fixture retrieval timestamp is invalid at source row {index}") from error
            if parsed_retrieved_at.tzinfo is None:
                raise ValueError(f"fixture retrieval timestamp lacks timezone at source row {index}")
            if retrieved_at != contract.retrieved_at:
                raise ValueError(f"fixture retrieval timestamp does not match committed evidence at source row {index}")
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
    season: str, rows: Sequence[Mapping[str, str]], *, prepared_file_sha256: str,
) -> list[dict[str, object]]:
    """Return provenance binding prepared CSV bytes to official response bytes."""
    validate_fixture_rows(season, rows)
    contract = fixture_contract_for(season)
    if contract is None:  # validate_fixture_rows above already guards this.
        raise ValueError(f"no explicit fixture contract for season {season!r}")
    if prepared_file_sha256 != contract.prepared_file_sha256:
        raise ValueError("prepared fixture file checksum does not match committed evidence")
    return [
        {
            "source_row_number": int(str(row["source_row_number"])),
            "upstream_match_id": str(row["match_id"]).strip(),
            "source_locator": str(row["source_locator"]).strip(),
            "prepared_file_sha256": prepared_file_sha256,
            "source_request_sha256": str(row["source_request_sha256"]).strip(),
            "upstream_response_sha256": str(row["source_response_sha256"]).strip(),
            "retrieved_at": str(row["retrieved_at"]).strip(),
        }
        for row in rows
    ]


def validate_fixture_provenance_binding(
    season: str,
    fixture_rows: Sequence[Mapping[str, str]],
    provenance_rows: Sequence[Mapping[str, object]],
) -> None:
    """Fail closed unless the complete prepared fixture set has exact source proof.

    This is the pure counterpart to ``analysis.accepted_urc_fixtures_v6``.  It
    deliberately compares a prepared CSV checksum only with the provenance's
    prepared checksum, while preserving the distinct upstream JSON response
    checksum as source evidence.
    """
    contract = fixture_contract_for(season)
    if contract is None:
        return
    summary = validate_fixture_rows(season, fixture_rows)
    expected_count = int(summary["fixture_count"])
    if len(provenance_rows) != expected_count:
        raise ValueError(
            "fixture provenance is incomplete: "
            f"expected {expected_count} rows, found {len(provenance_rows)}"
        )

    source_by_row: dict[int, Mapping[str, str]] = {}
    for row in fixture_rows:
        source_row_number = int(str(row["source_row_number"]))
        if source_row_number in source_by_row:
            raise ValueError("fixture source rows must be unique")
        source_by_row[source_row_number] = row

    provenance_by_row: dict[int, Mapping[str, object]] = {}
    prepared_hashes: set[str] = set()
    upstream_response_hashes: set[str] = set()
    for provenance in provenance_rows:
        source_row_number = int(str(provenance.get("source_row_number", "")))
        if source_row_number in provenance_by_row:
            raise ValueError("fixture provenance source rows must be unique")
        provenance_by_row[source_row_number] = provenance
        prepared_file_sha256 = str(provenance.get("prepared_file_sha256", "")).strip()
        upstream_response_sha256 = str(provenance.get("upstream_response_sha256", "")).strip()
        if not re.fullmatch(r"[0-9a-f]{64}", prepared_file_sha256):
            raise ValueError("fixture provenance prepared checksum must be SHA-256")
        if not re.fullmatch(r"[0-9a-f]{64}", upstream_response_sha256):
            raise ValueError("fixture provenance upstream response checksum must be SHA-256")
        prepared_hashes.add(prepared_file_sha256)
        upstream_response_hashes.add(upstream_response_sha256)

    if set(source_by_row) != set(provenance_by_row):
        raise ValueError("fixture provenance is incomplete for the prepared fixture source rows")
    if len(prepared_hashes) != 1:
        raise ValueError("fixture provenance is not bound to one set of prepared fixture bytes")
    if len(upstream_response_hashes) != 1:
        raise ValueError("fixture provenance must name exactly one upstream response")

    for source_row_number, source in source_by_row.items():
        provenance = provenance_by_row[source_row_number]
        if (
            str(provenance.get("upstream_match_id", "")).strip() != str(source["match_id"]).strip()
            or str(provenance.get("source_locator", "")).strip() != str(source["source_locator"]).strip()
            or str(provenance.get("source_request_sha256", "")).strip()
            != str(source["source_request_sha256"]).strip()
            or str(provenance.get("upstream_response_sha256", "")).strip()
            != str(source["source_response_sha256"]).strip()
            or str(provenance.get("retrieved_at", "")).strip() != str(source["retrieved_at"]).strip()
        ):
            raise ValueError("fixture provenance does not match the official source response")
