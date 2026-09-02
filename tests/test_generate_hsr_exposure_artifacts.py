import csv
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from generate_hsr_exposure_artifacts import (  # noqa: E402
    CANONICAL_HSR_FIELD,
    DEFAULT_BLANK_REASON_FIELD,
    EXPECTED_TEAMS,
    GenerationError,
    _database_parameter_payload,
    generate_all,
    generate_team_artifact,
    load_mapping,
    parse_team_mapping,
    sha256_file,
)


TEAMS = sorted(EXPECTED_TEAMS)
LOCATORS = [
    "source_file_sha256",
    "source_sheet",
    "source_row_number",
    "source_row_sha256",
]
FIELDS = LOCATORS + ["session date", "inclusion", "eligibility", "exposure minutes", "distance total", "HSR metres"]


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


class HsrExposureArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.exposure = self.root / "accepted.csv"
        base_rows = [
            {
                "source_file_sha256": "",
                "source_sheet": "Exposure",
                "source_row_number": "2",
                "source_row_sha256": "a" * 64,
                "session date": "2025-09-01",
                "inclusion": "included",
                "eligibility": "eligible",
                "exposure minutes": "10",
                "distance total": "100",
                "HSR metres": "7.50",
            },
            {
                "source_file_sha256": "",
                "source_sheet": "Exposure",
                "source_row_number": "3",
                "source_row_sha256": "b" * 64,
                "session date": "2025-09-02",
                "inclusion": "excluded",
                "eligibility": "ineligible",
                "exposure minutes": "20",
                "distance total": "200",
                "HSR metres": "",
            },
        ]
        write_csv(self.exposure, FIELDS, base_rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        _, rows = read_csv(self.exposure)
        for row in rows:
            row["source_file_sha256"] = self.exposure_sha
        write_csv(self.exposure, FIELDS, rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        _, rows = read_csv(self.exposure)
        # The locator value is an immutable field in the accepted input.  A
        # fixture therefore writes the final file hash before each test map.
        for row in rows:
            row["source_file_sha256"] = self.exposure_sha
        write_csv(self.exposure, FIELDS, rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def mapping_entry(self, team: str, *, mode: str = "accepted_row", available: bool = True, source: dict | None = None, field: str = "HSR metres") -> dict:
        entry = {
            "team_key": team,
            "accepted_exposure": {"path": str(self.exposure), "sha256": self.exposure_sha},
            "accepted_locator_fields": LOCATORS,
            "date_field": "session date",
            "comparability_status": "team-defined HSR distance; cross-team comparison limited",
            "hsr": {
                "mode": mode,
                "source_field": field,
                "distance_like": True,
                "units": "unknown",
                "threshold_or_zone": "unknown",
            },
        }
        if not available:
            entry["source_available"] = False
            entry["gap_reason"] = "supplied HSR does not cover accepted in-season period"
            entry["hsr"] = {"mode": "gap", "units": "unknown", "threshold_or_zone": "unknown"}
        elif source is not None:
            entry["hsr"]["source"] = source
        return entry

    def test_gap_output_preserves_rows_and_records_reason(self) -> None:
        mapping = parse_team_mapping(self.mapping_entry("benetton", available=False), "2025-26", self.root / "mapping.json")
        result = generate_team_artifact(mapping, self.root / "outputs")
        _, before = read_csv(self.exposure)
        _, after = read_csv(self.root / "outputs/2025-26/benetton/exposure_with_hsr.csv")
        self.assertEqual(len(before), result["before_row_count"])
        self.assertEqual(len(before), result["after_row_count"])
        self.assertEqual([row["source_row_number"] for row in before], [row["source_row_number"] for row in after])
        self.assertEqual({""}, {row[CANONICAL_HSR_FIELD] for row in after})
        self.assertEqual(
            {"supplied HSR does not cover accepted in-season period"},
            {row[DEFAULT_BLANK_REASON_FIELD] for row in after},
        )

    def test_external_source_join_traces_same_row_and_preserves_protected_columns(self) -> None:
        source = self.root / "hsr_source.csv"
        source_fields = LOCATORS + ["distance_z_4_to_z_6"]
        source_rows = [
            {**{field: value for field, value in zip(LOCATORS, ["SOURCE", "GPS", "2", "a" * 64])}, "distance_z_4_to_z_6": "9.25"},
            {**{field: value for field, value in zip(LOCATORS, ["SOURCE", "GPS", "3", "b" * 64])}, "distance_z_4_to_z_6": ""},
        ]
        write_csv(source, source_fields, source_rows)
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        # Accepted locators identify the exact source file.  The source file
        # itself has a different checksum, so the fixture joins on the stable
        # row and sheet/hash fields explicitly.
        _, accepted_rows = read_csv(self.exposure)
        for row in accepted_rows:
            row["source_file_sha256"] = "SOURCE"
            row["source_sheet"] = "GPS"
        write_csv(self.exposure, FIELDS, accepted_rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        mapping_value = self.mapping_entry(
            "glasgow",
            mode="external_row",
            field="distance_z_4_to_z_6",
            source={
                "path": str(source),
                "sha256": source_sha,
                "sheet": "GPS",
                "source_locator_fields": LOCATORS,
            },
        )
        mapping_value["hsr"]["join_fields"] = LOCATORS
        # In this fixture SOURCE/GPS are source-side locator values and the
        # accepted row carries the same values after the immutable fixture is
        # written.
        mapping = parse_team_mapping(mapping_value, "2025-26", self.root / "mapping.json")
        result = generate_team_artifact(mapping, self.root / "outputs")
        _, after = read_csv(self.root / "outputs/2025-26/glasgow/exposure_with_hsr.csv")
        self.assertEqual(2, result["after_row_count"])
        self.assertTrue(result["locator_set_identity"]["identical"])
        self.assertEqual(
            {tuple(row[field] for field in LOCATORS) for row in accepted_rows},
            {tuple(row[field] for field in LOCATORS) for row in after},
        )
        self.assertEqual("9.25", after[0][CANONICAL_HSR_FIELD])
        self.assertEqual("", after[1][CANONICAL_HSR_FIELD])
        self.assertEqual("2", after[0]["hsr_source_row_number"])
        self.assertEqual("a" * 64, after[0]["hsr_source_row_sha256"])
        for field in ("inclusion", "eligibility", "exposure minutes", "distance total"):
            self.assertEqual([row[field] for row in accepted_rows], [row[field] for row in after])

    def test_canonical_numeric_values_normalise_decimal_commas_and_flag_invalid_distances(self) -> None:
        _, rows = read_csv(self.exposure)
        rows[0]["HSR metres"] = "12,5"
        rows[1]["HSR metres"] = "NA"
        write_csv(self.exposure, FIELDS, rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        mapping = parse_team_mapping(self.mapping_entry("glasgow"), "2025-26", self.root / "mapping.json")
        generate_team_artifact(mapping, self.root / "outputs")
        _, after = read_csv(self.root / "outputs/2025-26/glasgow/exposure_with_hsr.csv")
        self.assertEqual("12.5", after[0][CANONICAL_HSR_FIELD])
        self.assertEqual("", after[1][CANONICAL_HSR_FIELD])
        self.assertEqual("hsr_source_value_missing_token", after[1][DEFAULT_BLANK_REASON_FIELD])

        rows[0]["HSR metres"] = "101"
        rows[1]["HSR metres"] = "not numeric"
        write_csv(self.exposure, FIELDS, rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        mapping = parse_team_mapping(self.mapping_entry("glasgow"), "2025-26", self.root / "mapping.json")
        with self.assertRaisesRegex(GenerationError, "not numeric"):
            generate_team_artifact(mapping, self.root / "outputs")

        rows[1]["HSR metres"] = ""
        write_csv(self.exposure, FIELDS, rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        mapping = parse_team_mapping(self.mapping_entry("glasgow"), "2025-26", self.root / "mapping.json")
        generate_team_artifact(mapping, self.root / "outputs")
        _, after = read_csv(self.root / "outputs/2025-26/glasgow/exposure_with_hsr.csv")
        self.assertEqual("", after[0][CANONICAL_HSR_FIELD])
        self.assertEqual("hsr_source_value_exceeds_total_distance", after[0][DEFAULT_BLANK_REASON_FIELD])

    def test_non_distance_sources_are_rejected(self) -> None:
        for bad_field in ("sprints", "HSR rate", "HSR percentage", "session duration", "distance total"):
            with self.subTest(field=bad_field):
                with self.assertRaisesRegex(GenerationError, "not a distance-like field"):
                    parse_team_mapping(self.mapping_entry("glasgow", field=bad_field), "2025-26", self.root / "mapping.json")

    def test_observation_group_join_emits_source_row_provenance(self) -> None:
        source = self.root / "long_hsr_source.csv"
        source_fields = ["group_key", "source_row_number", "source_row_sha256", "metric", "distance_z_4_to_z_6"]
        source_rows = [
            {"group_key": "2", "source_row_number": "21", "source_row_sha256": "c" * 64, "metric": "distance", "distance_z_4_to_z_6": "5.00"},
            {"group_key": "3", "source_row_number": "22", "source_row_sha256": "d" * 64, "metric": "distance", "distance_z_4_to_z_6": "6.00"},
        ]
        write_csv(source, source_fields, source_rows)
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        mapping_value = self.mapping_entry(
            "connacht",
            mode="observation_group",
            field="distance_z_4_to_z_6",
            source={
                "path": str(source),
                "sha256": source_sha,
                "source_locator_fields": ["source_row_number", "source_row_sha256"],
            },
        )
        mapping_value["hsr"]["join_fields"] = [{"accepted": "source_row_number", "source": "group_key"}]
        mapping_value["hsr"]["source_filter"] = {"metric": "distance"}
        mapping = parse_team_mapping(mapping_value, "2025-26", self.root / "mapping.json")
        result = generate_team_artifact(mapping, self.root / "outputs")
        _, after = read_csv(self.root / "outputs/2025-26/connacht/exposure_with_hsr.csv")
        self.assertEqual(2, result["matched_hsr_count"])
        self.assertEqual(["5.00", "6.00"], [row[CANONICAL_HSR_FIELD] for row in after])
        self.assertEqual(["21", "22"], [row["hsr_source_row_number"] for row in after])
        self.assertEqual(["c" * 64, "d" * 64], [row["hsr_source_row_sha256"] for row in after])

    def test_locator_files_reads_the_checksum_bound_physical_row(self) -> None:
        source = self.root / "monthly.csv"
        write_csv(source, ["Name", "High Speed Distance (m)"], [
            {"Name": "one", "High Speed Distance (m)": "11.5"},
            {"Name": "two", "High Speed Distance (m)": "12.5"},
        ])
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        _, accepted = read_csv(self.exposure)
        for row in accepted:
            row["source_file_sha256"] = source_sha
            row["source_sheet"] = "table_1"
        write_csv(self.exposure, FIELDS, accepted)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        value = self.mapping_entry("stormers", mode="locator_files", field="High Speed Distance (m)")
        value["accepted_exposure"]["sha256"] = self.exposure_sha
        value["hsr"]["source_roots"] = [str(source)]
        mapping = parse_team_mapping(value, "2025-26", self.root / "mapping.json")
        result = generate_team_artifact(mapping, self.root / "outputs")
        _, after = read_csv(self.root / "outputs/2025-26/stormers/exposure_with_hsr.csv")
        self.assertEqual(2, result["source_rows_matched"])
        self.assertEqual(["11.5", "12.5"], [row[CANONICAL_HSR_FIELD] for row in after])
        self.assertEqual(["2", "3"], [row["hsr_source_row_number"] for row in after])

    def test_long_variable_files_requires_the_same_observation(self) -> None:
        source = self.root / "long.csv"
        source_fields = ["week_start", "player_display_name_harmonised", "variable", "match_day", "value"]
        source_rows = [
            {"week_start": "9/22/2025", "player_display_name_harmonised": "Player One", "variable": "total_time_minutes", "match_day": "0", "value": "10"},
            {"week_start": "9/22/2025", "player_display_name_harmonised": "Player One", "variable": "distance_z_4_to_z_6", "match_day": "0", "value": "8.5"},
            {"week_start": "9/22/2025", "player_display_name_harmonised": "Player One", "variable": "distance_total", "match_day": "0", "value": "100"},
            {"week_start": "9/22/2025", "player_display_name_harmonised": "Player One", "variable": "time_z_4_to_z_6", "match_day": "0", "value": "2"},
        ]
        write_csv(source, source_fields, source_rows)
        source_sha = hashlib.sha256(source.read_bytes()).hexdigest()

        def row_hash(row: dict[str, str]) -> str:
            return hashlib.sha256(
                json.dumps(row, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest()

        player_uid = "ply_" + hashlib.sha256("ply\x1fconnacht\x1fPlayer One".encode()).hexdigest()[:24]
        accepted_fields = LOCATORS + [
            "session date", "player_uid", "setting", "cleaned_date", "minutes_total_clean",
            "distance_total_m_clean", "duration_source_row_number", "duration_source_row_sha256",
            "distance_source_row_number", "distance_source_row_sha256",
        ]
        accepted = self.root / "long_accepted.csv"
        write_csv(accepted, accepted_fields, [{
            "source_file_sha256": source_sha,
            "source_sheet": "table_1",
            "source_row_number": "2",
            "source_row_sha256": "a" * 64,
            "session date": "2025-09-22",
            "player_uid": player_uid,
            "setting": "training",
            "cleaned_date": "2025-09-22",
            "minutes_total_clean": "10",
            "distance_total_m_clean": "100",
            "duration_source_row_number": "2",
            "duration_source_row_sha256": row_hash(source_rows[0]),
            "distance_source_row_number": "4",
            "distance_source_row_sha256": row_hash(source_rows[2]),
        }])
        accepted_sha = hashlib.sha256(accepted.read_bytes()).hexdigest()
        value = {
            "team_key": "connacht",
            "accepted_exposure": {"path": str(accepted), "sha256": accepted_sha},
            "accepted_locator_fields": LOCATORS,
            "date_field": "cleaned_date",
            "comparability_status": "team-defined",
            "hsr": {
                "mode": "long_variable_files",
                "source_field": "value",
                "metric_kind": "hsr_distance",
                "source_filter": {"variable": "distance_z_4_to_z_6"},
                "source_roots": [str(source)],
                "units": "unknown",
                "threshold_or_zone": "zone 4 to zone 6",
            },
        }
        for forbidden_variable in (
            "time_z_4_to_z_6",
            "distance_total",
            "sprint_distance",
            "hsr_count",
            "hsr_rate",
        ):
            with self.subTest(variable=forbidden_variable):
                rejected = copy.deepcopy(value)
                rejected["hsr"]["source_filter"]["variable"] = forbidden_variable
                with self.assertRaisesRegex(GenerationError, "not a distance-like field"):
                    parse_team_mapping(rejected, "2025-26", self.root / "mapping.json")
        mapping = parse_team_mapping(value, "2025-26", self.root / "mapping.json")
        result = generate_team_artifact(mapping, self.root / "outputs")
        _, after = read_csv(self.root / "outputs/2025-26/connacht/exposure_with_hsr.csv")
        self.assertEqual(1, result["source_rows_matched"])
        self.assertEqual("8.5", after[0][CANONICAL_HSR_FIELD])
        self.assertEqual("3", after[0]["hsr_source_row_number"])

    def test_accepted_input_checksum_mismatch_fails_closed(self) -> None:
        mapping = parse_team_mapping(self.mapping_entry("glasgow"), "2025-26", self.root / "mapping.json")
        with self.exposure.open("a", encoding="utf-8") as handle:
            handle.write("\n")
        with self.assertRaisesRegex(GenerationError, "checksum differs"):
            generate_team_artifact(mapping, self.root / "outputs")

    def test_full_maps_have_expected_availability_and_regenerate_deterministically(self) -> None:
        mapping_paths = {}
        for season in ("2024-25", "2025-26"):
            entries = [self.mapping_entry(team, available=not (season == "2025-26" and team in {"benetton", "edinburgh"})) for team in TEAMS]
            path = self.root / f"{season}.json"
            path.write_text(json.dumps({"schema_version": "urc_hsr_mapping_v1", "season": season, "teams": entries}, indent=2), encoding="utf-8")
            mapping_paths[season] = path
        first_manifest = self.root / "manifest.json"
        first_report = self.root / "validation.json"
        generate_all(mapping_paths, output_root=self.root / "outputs", manifest_path=first_manifest, validation_path=first_report)
        first_outputs = {path.relative_to(self.root): path.read_bytes() for path in (self.root / "outputs").rglob("*.csv")}
        first_manifest_bytes = first_manifest.read_bytes()
        first_report_bytes = first_report.read_bytes()
        generate_all(mapping_paths, output_root=self.root / "outputs", manifest_path=first_manifest, validation_path=first_report)
        self.assertEqual(first_outputs, {path.relative_to(self.root): path.read_bytes() for path in (self.root / "outputs").rglob("*.csv")})
        self.assertEqual(first_manifest_bytes, first_manifest.read_bytes())
        self.assertEqual(first_report_bytes, first_report.read_bytes())
        manifest = json.loads(first_manifest.read_text(encoding="utf-8"))
        self.assertEqual(32, len(manifest["team_seasons"]))
        self.assertEqual(16, manifest["source_availability"]["2024-25"]["teams_with_source"])
        self.assertEqual(14, manifest["source_availability"]["2025-26"]["teams_with_source"])
        self.assertEqual("16/16", manifest["source_availability_summary"]["2024-25"])
        self.assertEqual("14/16", manifest["source_availability_summary"]["2025-26"])
        self.assertEqual(["benetton", "edinburgh"], manifest["source_availability"]["2025-26"]["gaps"])
        self.assertEqual("unknown", manifest["team_seasons"][0]["units"])
        self.assertEqual("unknown", manifest["team_seasons"][0]["threshold_or_zone"])

    def test_database_parameter_payload_has_exact_inventory_and_is_byte_stable(self) -> None:
        mapping_paths = {}
        for season in ("2024-25", "2025-26"):
            entries = [self.mapping_entry(team, available=not (season == "2025-26" and team in {"benetton", "edinburgh"})) for team in TEAMS]
            path = self.root / f"{season}.json"
            path.write_text(json.dumps({"schema_version": "urc_hsr_mapping_v1", "season": season, "teams": entries}, indent=2), encoding="utf-8")
            mapping_paths[season] = path
        parameter_path = self.root / "outputs/hsr_database_parameters.json"
        generate_all(mapping_paths, output_root=self.root / "outputs", manifest_path=self.root / "manifest.json", validation_path=self.root / "validation.json", parameter_path=parameter_path)
        first_bytes = parameter_path.read_bytes()
        payload = json.loads(first_bytes)
        metadata = [item for item in payload if item["kind"] == "team_season"]
        observations = [item for item in payload if item["kind"] == "observation"]
        expected_keys = {(season, team) for season in ("2024-25", "2025-26") for team in TEAMS}
        self.assertEqual(32, len(metadata))
        self.assertEqual(expected_keys, {(item["season"], item["team_key"]) for item in metadata})
        self.assertEqual(64, len(observations))
        self.assertEqual(64, sum(item["accepted_row_count"] for item in metadata))
        self.assertFalse(any(key in json.dumps(payload) for key in ("player_uid", "player_id", "Name", "name")))
        for item in metadata:
            self.assertEqual(4, len(item["accepted_locator_fields"]))
            self.assertEqual(item["accepted_row_count"], sum(1 for row in observations if (row["season"], row["team_key"]) == (item["season"], item["team_key"])))
        generate_all(mapping_paths, output_root=self.root / "outputs", manifest_path=self.root / "manifest.json", validation_path=self.root / "validation.json", parameter_path=parameter_path)
        self.assertEqual(first_bytes, parameter_path.read_bytes())

    def test_database_parameter_payload_rejects_tampered_canonical_value(self) -> None:
        mapping_paths = {}
        mappings = []
        for season in ("2024-25", "2025-26"):
            entries = [self.mapping_entry(team, available=not (season == "2025-26" and team in {"benetton", "edinburgh"})) for team in TEAMS]
            path = self.root / f"{season}.json"
            path.write_text(json.dumps({"schema_version": "urc_hsr_mapping_v1", "season": season, "teams": entries}, indent=2), encoding="utf-8")
            mapping_paths[season] = path
            mappings.extend(parse_team_mapping(entry, season, path) for entry in entries)
        output_root = self.root / "outputs"
        _, validation = generate_all(mapping_paths, output_root=output_root, manifest_path=self.root / "manifest.json", validation_path=self.root / "validation.json")
        tampered = output_root / "2024-25/benetton/exposure_with_hsr.csv"
        fields, rows = read_csv(tampered)
        rows[0][CANONICAL_HSR_FIELD] = "not numeric"
        write_csv(tampered, fields, rows)
        result_by_key = {(item["season"], item["team_key"]): item for item in validation["team_seasons"]}
        mapping_hashes = {season: sha256_file(path) for season, path in mapping_paths.items()}
        with self.assertRaisesRegex(GenerationError, "canonical HSR distance is not numeric"):
            _database_parameter_payload(mappings, result_by_key, mapping_hashes, output_root)

    def test_mapping_with_missing_or_duplicate_locator_fails_closed(self) -> None:
        bad = self.mapping_entry("glasgow")
        _, missing_rows = read_csv(self.exposure)
        missing_rows[0]["source_row_sha256"] = ""
        write_csv(self.exposure, FIELDS, missing_rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        bad["accepted_exposure"]["sha256"] = self.exposure_sha
        with self.assertRaisesRegex(GenerationError, "missing stable locator"):
            mapping = parse_team_mapping(bad, "2025-26", self.root / "mapping.json")
            generate_team_artifact(mapping, self.root / "outputs")
        duplicate = self.mapping_entry("glasgow")
        _, rows = read_csv(self.exposure)
        rows[0]["source_row_sha256"] = "a" * 64
        rows[1]["source_row_number"] = rows[0]["source_row_number"]
        rows[1]["source_row_sha256"] = rows[0]["source_row_sha256"]
        write_csv(self.exposure, FIELDS, rows)
        self.exposure_sha = hashlib.sha256(self.exposure.read_bytes()).hexdigest()
        duplicate["accepted_exposure"]["sha256"] = self.exposure_sha
        mapping = parse_team_mapping(duplicate, "2025-26", self.root / "mapping.json")
        with self.assertRaisesRegex(GenerationError, "duplicated stable locator"):
            generate_team_artifact(mapping, self.root / "outputs")


if __name__ == "__main__":
    unittest.main()
