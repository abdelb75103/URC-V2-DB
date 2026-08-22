from __future__ import annotations

from collections import Counter
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
PREDECESSOR = (
    ROOT
    / "supabase/migrations"
    / "20260815020000_urc_2025_26_reporting_v6.sql"
).read_text(encoding="utf-8")
MIGRATION = (
    ROOT
    / "supabase/migrations"
    / "20260822220611_urc_2025_26_v6_candidate_view_optimisation.sql"
)


def view_definition(sql: str, name: str) -> str:
    match = re.search(
        rf"create(?: or replace)? view analysis\.{re.escape(name)}\b.*?"
        rf"(?=\ncreate(?: or replace)? view |\Z)",
        sql,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"view definition not found: {name}")
    return match.group(0)


def function_calls(sql: str, name: str) -> list[str]:
    """Return balanced calls, including nested calls of the same name."""
    calls: list[str] = []
    lowered = sql.lower()
    needle = f"{name.lower()}("
    cursor = 0
    while (start := lowered.find(needle, cursor)) >= 0:
        depth = 0
        quoted = False
        index = start + len(name)
        while index < len(sql):
            char = sql[index]
            if char == "'":
                if quoted and index + 1 < len(sql) and sql[index + 1] == "'":
                    index += 2
                    continue
                quoted = not quoted
            elif not quoted:
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                    if depth == 0:
                        calls.append(sql[start : index + 1])
                        break
            index += 1
        else:
            raise AssertionError(f"unbalanced {name} call")
        cursor = start + 1
    return calls


def compact(sql: str) -> str:
    return re.sub(r"\s+", "", sql.lower())


def top_level_arguments(call: str) -> list[str]:
    """Split a function call without splitting nested SQL expressions."""
    opening = call.find("(")
    if opening < 0 or not call.endswith(")"):
        raise AssertionError("expected a complete function call")
    arguments: list[str] = []
    start = opening + 1
    depth = 0
    quoted = False
    index = start
    while index < len(call) - 1:
        char = call[index]
        if char == "'":
            if quoted and index + 1 < len(call) - 1 and call[index + 1] == "'":
                index += 2
                continue
            quoted = not quoted
        elif not quoted:
            if char in "([":
                depth += 1
            elif char in ")]":
                depth -= 1
            elif char == "," and depth == 0:
                arguments.append(call[start:index].strip())
                start = index + 1
        index += 1
    arguments.append(call[start:-1].strip())
    return arguments


def jsonb_object_key_contract(sql: str) -> Counter[tuple[str, ...]]:
    """Capture every JSON object's exact key names and order."""
    contracts: Counter[tuple[str, ...]] = Counter()
    for call in function_calls(sql, "jsonb_build_object"):
        arguments = top_level_arguments(call)
        if len(arguments) % 2:
            raise AssertionError("jsonb_build_object must contain key/value pairs")
        keys: list[str] = []
        for argument in arguments[::2]:
            match = re.fullmatch(r"'((?:[^']|'')*)'", argument)
            if match is None:
                raise AssertionError(f"dashboard JSON key is not a literal: {argument}")
            keys.append(match.group(1).replace("''", "'"))
        contracts[tuple(keys)] += 1
    return contracts


def assert_empty_array_coalesce_contract(test: unittest.TestCase, sql: str) -> None:
    """Pin every aggregate fallback to result first and an empty array second."""
    calls = function_calls(sql, "coalesce")
    test.assertEqual(8, len(calls))
    for call in calls:
        arguments = top_level_arguments(call)
        test.assertEqual(2, len(arguments))
        test.assertIn("jsonb_agg", arguments[0].lower())
        test.assertEqual("'[]'::jsonb", compact(arguments[1]))


class Year2V6CandidateViewOptimisationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.team_before = view_definition(
            PREDECESSOR, "team_dashboard_payload_analysis_window_v6_enriched"
        )
        cls.team_after = view_definition(
            cls.sql, "team_dashboard_payload_analysis_window_v6_enriched"
        )
        cls.league_before = view_definition(
            PREDECESSOR, "league_dashboard_payload_analysis_window_v6_enriched"
        )
        cls.league_after = view_definition(
            cls.sql, "league_dashboard_payload_analysis_window_v6_enriched"
        )

    def test_is_additive_and_replaces_only_the_two_enriched_v6_views(self) -> None:
        created = re.findall(
            r"create or replace view\s+([a-z0-9_.]+)", self.sql, re.IGNORECASE
        )
        self.assertEqual(
            [
                "analysis.team_dashboard_payload_analysis_window_v6_enriched",
                "analysis.league_dashboard_payload_analysis_window_v6_enriched",
            ],
            [name.lower() for name in created],
        )
        self.assertNotIn("analysis_window_2024", self.sql.lower())
        self.assertNotIn("create or replace view reporting.", self.sql.lower())

    def test_view_columns_and_security_invoker_contract_are_unchanged(self) -> None:
        expected_team_columns = (
            "base.team_key,base.season,base.team_release_id,base.curated_build_id,"
            "base.classification_view_version,base.classification_evidence_sha256,"
            "base.cohort_view_version,base.cohort_evidence_sha256,"
        )
        expected_league_columns = (
            "base.season,base.classification_view_version,"
            "base.classification_evidence_sha256,base.cohort_view_version,"
            "base.cohort_evidence_sha256,"
        )
        self.assertIn(expected_team_columns, compact(self.team_before))
        self.assertIn(expected_team_columns, compact(self.team_after))
        self.assertIn(expected_league_columns, compact(self.league_before))
        self.assertIn(expected_league_columns, compact(self.league_after))
        self.assertEqual(2, self.sql.lower().count("with (security_invoker = true)"))
        self.assertEqual(2, self.sql.lower().count(" as dashboard\nfrom "))

    def test_team_sources_are_filtered_then_materialised_once_per_base_row(self) -> None:
        for cte, relation in (
            ("profiles", "analysis.analysis_window_profiles_v6"),
            ("severity", "analysis.analysis_window_severity_v6"),
            ("setting_metrics", "analysis.analysis_window_setting_metrics_v6"),
            ("contact_distribution", "analysis.analysis_window_contact_distribution_v6"),
        ):
            self.assertEqual(1, self.team_after.lower().count(f"{cte} as materialized"))
            self.assertEqual(1, self.team_after.lower().count(f"from {relation}"))
        for predicate in (
            "curated_build_id = base.curated_build_id",
            "team_key = base.team_key",
            "season = base.season",
        ):
            self.assertEqual(4, self.team_after.lower().count(predicate))
        self.assertIn("cross join lateral", self.team_after.lower())

    def test_league_sources_are_filtered_then_materialised_once_per_season(self) -> None:
        for cte, relation in (
            ("profiles", "analysis.analysis_window_league_profiles_v6"),
            ("severity", "analysis.analysis_window_league_severity_v6"),
            ("setting_metrics", "analysis.analysis_window_league_setting_metrics_v6"),
            (
                "contact_distribution",
                "analysis.analysis_window_league_contact_distribution_v6",
            ),
        ):
            self.assertEqual(1, self.league_after.lower().count(f"{cte} as materialized"))
            self.assertEqual(1, self.league_after.lower().count(f"from {relation}"))
        self.assertEqual(4, self.league_after.lower().count("season = base.season"))
        self.assertIn("cross join lateral", self.league_after.lower())

    def test_team_json_rows_values_and_ordering_match_the_predecessor(self) -> None:
        before = Counter(compact(call) for call in function_calls(self.team_before, "jsonb_agg"))
        after = Counter(compact(call) for call in function_calls(self.team_after, "jsonb_agg"))
        self.assertEqual(before, after)
        self.assertEqual(8, sum(before.values()))
        self.assertEqual(
            self.team_before.lower().count("'[]'::jsonb"),
            self.team_after.lower().count("'[]'::jsonb"),
        )
        self.assertEqual(1, self.team_after.lower().count("injury_type_families_from_payload_v1"))

    def test_team_dashboard_json_keys_and_concat_precedence_are_exact(self) -> None:
        self.assertEqual(
            jsonb_object_key_contract(self.team_before),
            jsonb_object_key_contract(self.team_after),
        )
        self.assertIn(
            (
                "body_locations", "injury_types", "injury_profiles",
                "severity_distribution", "setting_metrics", "setting_split",
                "contact_distribution",
            ),
            jsonb_object_key_contract(self.team_after),
        )
        self.assertIn(("injury_type_families",), jsonb_object_key_contract(self.team_after))
        assert_empty_array_coalesce_contract(self, self.team_before)
        assert_empty_array_coalesce_contract(self, self.team_after)
        self.assertIn(
            "base.dashboard||sections.dashboard_sections||sections.family_sectionasdashboard",
            compact(self.team_after),
        )

    def test_league_json_rows_values_and_ordering_match_the_predecessor(self) -> None:
        before = Counter(compact(call) for call in function_calls(self.league_before, "jsonb_agg"))
        after = Counter(compact(call) for call in function_calls(self.league_after, "jsonb_agg"))
        self.assertEqual(before, after)
        self.assertEqual(8, sum(before.values()))
        self.assertEqual(
            self.league_before.lower().count("'[]'::jsonb"),
            self.league_after.lower().count("'[]'::jsonb"),
        )
        self.assertEqual(1, self.league_after.lower().count("injury_type_families_from_payload_v1"))

    def test_league_dashboard_json_keys_and_concat_precedence_are_exact(self) -> None:
        self.assertEqual(
            jsonb_object_key_contract(self.league_before),
            jsonb_object_key_contract(self.league_after),
        )
        self.assertIn(
            (
                "body_locations", "injury_types", "injury_profiles",
                "severity_distribution", "setting_metrics", "setting_split",
                "contact_distribution",
            ),
            jsonb_object_key_contract(self.league_after),
        )
        self.assertIn(("injury_type_families",), jsonb_object_key_contract(self.league_after))
        assert_empty_array_coalesce_contract(self, self.league_before)
        assert_empty_array_coalesce_contract(self, self.league_after)
        self.assertIn(
            "base.dashboard||sections.dashboard_sections||sections.family_sectionasdashboard",
            compact(self.league_after),
        )

    def test_downstream_candidate_relations_remain_in_place(self) -> None:
        team_release = (
            ROOT
            / "supabase/migrations"
            / "20260815030000_urc_2025_26_team_release_v6.sql"
        ).read_text(encoding="utf-8").lower()
        self.assertIn(
            "from analysis.team_dashboard_payload_analysis_window_v6_enriched active",
            team_release,
        )
        self.assertIn(
            "from analysis.league_dashboard_payload_analysis_window_v6_enriched candidate",
            team_release,
        )
        self.assertNotIn("release_candidates", self.sql.lower())


if __name__ == "__main__":
    unittest.main()
