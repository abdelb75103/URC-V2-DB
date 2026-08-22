from __future__ import annotations

from pathlib import Path
import csv
import hashlib
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260815020000_urc_2025_26_reporting_v6.sql"
CATALOGUE_MIGRATION = ROOT / "supabase/migrations/20260722140000_osiics_source_body_pathology_mapping.sql"
CLASSIFICATION_RULES_MIGRATION = ROOT / "supabase/migrations/20260722130000_osiics_exact_reporting_classification.sql"
YEAR2_CLASSIFICATION_EVIDENCE = ROOT / "docs/evidence/urc_2025_26_classification_rule.json"


class Year2ReportingV6SqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.raw_sql = MIGRATION.read_text(encoding="utf-8")
        cls.sql = cls.raw_sql.lower()

    def test_creates_the_registered_v6_scientific_and_candidate_relations(self) -> None:
        for relation in (
            "analysis.analysis_window_injury_cohort_v6",
            "analysis.analysis_window_league_monthly_v6",
            "analysis.analysis_window_league_summary_v6",
            "analysis.team_dashboard_release_candidates_analysis_window_v6",
            "analysis.league_dashboard_release_candidates_analysis_window_v6",
        ):
            self.assertIn(relation, self.sql)

    def test_is_strictly_year2_and_binds_the_registered_tuple(self) -> None:
        self.assertIn("'2025-26'", self.sql)
        self.assertIn("'v6'", self.sql)
        self.assertIn("'reporting_classification_2026-07-22_v2'", self.sql)
        self.assertIn("'analysis_window_2025-26_2026-08-15_v1'", self.sql)
        self.assertIn("date '2025-09-01'", self.sql)
        self.assertIn("date '2026-06-30'", self.sql)
        self.assertIn("'2024-25'", self.sql)  # frozen prior-season display metadata only
        self.assertNotIn("_v5", self.sql)

    def test_reporting_window_uses_a_non_reserved_alias(self) -> None:
        self.assertNotRegex(
            self.sql,
            r"reporting_season_windows_v3\s+window\b",
        )
        self.assertIn("reporting_season_windows_v3 season_window", self.sql)

    def test_enriched_payload_views_replace_the_dashboard_column(self) -> None:
        self.assertNotIn("select base.*,", self.sql)
        self.assertIn(
            "select base.team_key, base.season, base.team_release_id, base.curated_build_id,",
            self.sql,
        )
        self.assertIn(
            "select base.season, base.classification_view_version,",
            self.sql,
        )

    def test_undated_rows_remain_in_totals_but_not_monthly_series(self) -> None:
        classification = self.sql.split(
            "create view analysis.analysis_window_reporting_classification_v6", 1
        )[1].split("create view analysis.analysis_window_injury_cohort_v6", 1)[0]
        monthly = self.sql.split("create view analysis.analysis_window_monthly_v6", 1)[1]
        self.assertIn("or injury.date_injured is null", classification)
        self.assertIn("and date_injured is not null", monthly)

    def test_team_candidates_are_active_build_derived_and_fail_closed_at_sixteen(self) -> None:
        self.assertIn("analysis.analysis_window_active_builds_v6", self.sql)
        self.assertIn("count(*) from curated.builds where season='2025-26' and status='active')=16", self.sql)
        self.assertNotIn("league_member_releases", self.sql)
        self.assertIn("curated.builds", self.sql)

    def test_candidates_and_team_hours_require_complete_checksum_bound_fixture_provenance(self) -> None:
        """A partial or mismatched fixture provenance set must suppress V6 output."""
        self.assertIn("create view analysis.accepted_urc_fixtures_v6", self.sql)
        accepted = self.sql.split("create view analysis.accepted_urc_fixtures_v6", 1)[1].split(
            "create or replace view analysis.analysis_window_active_builds_v6", 1
        )[0]
        for token in (
            "curated.fixture_provenance_v1",
            "analysis.fixture_preparation_evidence_v1",
            "fixture_count = 151",
            "provenance_count = 151",
            "joined_count = 151",
            "prepared_file_sha256=fixture.source_file_sha256",
            "prepared_hash_count = 1",
            "upstream_response_hash_count = 1",
            "provenance.source_locator ~ evidence.source_locator_pattern",
        ):
            self.assertIn(token, accepted)
        active_builds = self.sql.split("create or replace view analysis.analysis_window_active_builds_v6", 1)[1].split(
            "create view analysis.analysis_window_injury_cohort_v6", 1
        )[0]
        self.assertIn("exists (select 1 from analysis.accepted_urc_fixtures_v6)", active_builds)
        team_hours = self.sql.split("create view analysis.analysis_window_team_hours_v6", 1)[1].split(
            "create view analysis.analysis_window_team_summary_v6", 1
        )[0]
        self.assertIn("join analysis.accepted_urc_fixtures_v6 fixture", team_hours)
        self.assertNotIn("join curated.fixtures fixture", team_hours)

    def test_classification_carries_the_accepted_catalogue_and_conservative_inference_forward(self) -> None:
        classification = self.sql.split(
            "create view analysis.analysis_window_reporting_classification_v6", 1
        )[1].split("create view analysis.analysis_window_injury_cohort_v6", 1)[0]
        for token in (
            "ingestion.source_rows",
            "analysis.osiics_exact_ioc_mapping_v1",
            "analysis.osiics_multi_type_diagnosis_v1",
            "when evidence.body_location_code <> 'unknown' then evidence.body_location_code",
            "when body.injury_type_code <> 'unknown' then body.injury_type_code",
            "when coalesce(summary.candidate_count, 0) = 1 then summary.sole_candidate",
            "else 'unknown'",
            "remaining_unknown",
        ):
            self.assertIn(token, classification)
        self.assertNotIn("analysis.lineage_", classification)
        self.assertNotIn("analysis.season_bound_reporting_classification", classification)

    def test_year2_classification_evidence_excludes_prior_row_adjudications(self) -> None:
        evidence = self.sql.split(
            "create view analysis.accepted_year2_reporting_classification_rules_v6", 1
        )[1].split("create view analysis.accepted_urc_fixtures_v6", 1)[0]
        self.assertIn("catalogue_and_conservative_inference_only", evidence)
        self.assertIn("year1_row_adjudications','not_carried_forward", evidence)
        self.assertIn("urc_2025_26_classification_rule.json", evidence)
        self.assertIn("e898320fc5fa8cdf", evidence)
        self.assertIn("mapping_catalogue_projection_sha256','79767a9f", evidence)
        self.assertIn("multi_type_catalogue_projection_sha256','d7aa844a", evidence)
        self.assertIn("mapping_catalogue_row_count',52", evidence)
        self.assertIn("multi_type_catalogue_row_count',1", evidence)
        self.assertIn("expected_mapping", evidence)
        self.assertIn("expected_multi", evidence)
        self.assertGreaterEqual(evidence.count("except all select *"), 4)
        self.assertNotIn("audit.rule_adjudications", evidence)
        self.assertNotIn("db1823f5", evidence)
        self.assertNotIn("expected_live_time_loss", evidence)

    def test_year2_catalogue_projection_hashes_exclude_observed_case_counts(self) -> None:
        evidence = json.loads(YEAR2_CLASSIFICATION_EVIDENCE.read_text(encoding="utf-8"))
        for catalogue_name, path_name in (
            ("mapping_catalogue_projection", "osiics_exact_ioc_mapping_2024-25.csv"),
            ("multi_type_catalogue_projection", "osiics_multi_type_diagnosis_2024-25.csv"),
        ):
            contract = evidence[catalogue_name]
            with (ROOT / "docs/evidence" / path_name).open(encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            projection = [{field: row[field] for field in contract["fields"]} for row in rows]
            payload = json.dumps(
                projection, sort_keys=True, separators=(",", ":"), ensure_ascii=False
            ).encode("utf-8")
            self.assertEqual(contract["row_count"], len(projection))
            self.assertEqual(contract["sha256"], hashlib.sha256(payload).hexdigest())
            self.assertNotIn("expected_live_time_loss_cases", contract["fields"])
        self.assertNotIn("accepted_reporting_classification_rules_v4", self.sql)

    def test_classification_fixture_cases_preserve_explicit_values_map_osiics_and_retain_unknown(self) -> None:
        """V6 applies the accepted catalogue, without importing Year 1 rows."""
        catalogue_rows = set(
            re.findall(
                r"\('([A-Z0-9]+)','([a-z_]+)','([a-z_]+)'\)",
                CATALOGUE_MIGRATION.read_text(encoding="utf-8"),
            )
        )
        # QRA deliberately has two reviewed body candidates.  The current
        # curated body chooses the matching pathology; without that evidence
        # it remains ambiguous.  QBC is the additive pathology correction.
        self.assertTrue(
            {
                ("AL1", "ankle", "joint_sprain"),
                ("QRA", "ankle", "tendon_rupture"),
                ("QRA", "lower_leg", "tendon_rupture"),
                ("QBC", "lower_leg", "bursitis"),
            }.issubset(catalogue_rows)
        )
        mapping: dict[str, set[tuple[str, str]]] = {}
        for code, body_code, type_code in catalogue_rows:
            mapping.setdefault(code, set()).add((body_code, type_code))

        def classify(*, body: str, injury_type: str, orchard_code: str, text: str) -> tuple[str, str]:
            # Existing curated controlled values win.  Exact catalogue mapping
            # applies only where a value remains Unknown; unique explicit text
            # is conservative, and conflicting or weak text remains Unknown.
            mapped = mapping.get(orchard_code, set())
            candidate_bodies = {candidate_body for candidate_body, _ in mapped}
            effective_body = body if body != "unknown" else (
                next(iter(candidate_bodies)) if len(candidate_bodies) == 1 else "unknown"
            )
            mapped_types = {
                candidate_type
                for candidate_body, candidate_type in mapped
                if candidate_body == effective_body
            }
            if injury_type != "unknown":
                effective_type = injury_type
            elif len(mapped_types) == 1:
                effective_type = next(iter(mapped_types))
            elif text == "hamstring strain":
                effective_body, effective_type = "thigh", "muscle_injury"
            else:
                effective_type = "unknown"
            return effective_body, effective_type

        self.assertEqual(
            classify(body="knee", injury_type="joint_sprain", orchard_code="AL1", text=""),
            ("knee", "joint_sprain"),
        )
        self.assertEqual(
            classify(body="unknown", injury_type="unknown", orchard_code="AL1", text=""),
            ("ankle", "joint_sprain"),
        )
        self.assertEqual(
            classify(body="lower_leg", injury_type="unknown", orchard_code="QRA", text=""),
            ("lower_leg", "tendon_rupture"),
        )
        self.assertEqual(
            classify(body="unknown", injury_type="unknown", orchard_code="QRA", text=""),
            ("unknown", "unknown"),
        )
        self.assertEqual(
            classify(body="unknown", injury_type="unknown", orchard_code="QBC", text=""),
            ("lower_leg", "bursitis"),
        )
        self.assertEqual(
            classify(body="unknown", injury_type="unknown", orchard_code="", text="hamstring strain"),
            ("thigh", "muscle_injury"),
        )
        self.assertEqual(
            classify(body="unknown", injury_type="unknown", orchard_code="", text="soleus trigger points/spasm"),
            ("unknown", "unknown"),
        )

        def diagnose(
            *, body: str, injury_type: str, orchard_code: str,
            positive_concussion: bool = False, text: str = "",
        ) -> tuple[str, str]:
            if orchard_code in {"HN1", "HN2", "HNC1", "HNC2", "HNCA", "HNCD", "HNCH", "HNCN", "HNCO", "HNCX"} or positive_concussion:
                return "concussion", "Concussion"
            if orchard_code == "NPM":
                return "multi__neck__muscle_injury__tendinopathy", "Neck · Muscle/tendon injury"
            resolved_body, resolved_type = classify(
                body=body, injury_type=injury_type, orchard_code=orchard_code, text=text,
            )
            if resolved_body != "unknown" and resolved_type != "unknown":
                return f"compound__{resolved_body}__{resolved_type}", f"{resolved_body} · {resolved_type}"
            return "unknown", "Unknown diagnosis"

        self.assertEqual(
            diagnose(body="unknown", injury_type="unknown", orchard_code="", positive_concussion=True),
            ("concussion", "Concussion"),
        )
        self.assertEqual(
            diagnose(body="unknown", injury_type="unknown", orchard_code="AL1"),
            ("compound__ankle__joint_sprain", "ankle · joint_sprain"),
        )
        self.assertEqual(
            diagnose(body="unknown", injury_type="unknown", orchard_code="NPM"),
            ("multi__neck__muscle_injury__tendinopathy", "Neck · Muscle/tendon injury"),
        )
        self.assertEqual(
            diagnose(body="unknown", injury_type="unknown", orchard_code=""),
            ("unknown", "Unknown diagnosis"),
        )

    def test_diagnosis_is_carried_into_the_cohort_and_public_profiles(self) -> None:
        classification = self.sql.split(
            "create view analysis.analysis_window_reporting_classification_v6", 1
        )[1].split("create view analysis.analysis_window_injury_cohort_v6", 1)[0]
        cohort = self.sql.split(
            "create view analysis.analysis_window_injury_cohort_v6", 1
        )[1].split("create view analysis.analysis_window_team_exposure_v6", 1)[0]
        profiles = self.sql.split(
            "create view analysis.analysis_window_profile_rows_v6", 1
        )[1].split("create view analysis.analysis_window_profiles_v6", 1)[0]
        for token in (
            "effective_diagnosis_code", "effective_diagnosis_label",
            "accepted_current_concussion_evidence", "multi_diagnosis_code",
            "multi_diagnosis_label",
        ):
            self.assertIn(token, classification)
        self.assertIn("classification.effective_diagnosis_code as diagnosis_code", cohort)
        self.assertIn("classification.effective_diagnosis_label as diagnosis_label", cohort)
        self.assertEqual(
            profiles.count("('diagnosis'::text, cohort.diagnosis_code, cohort.diagnosis_label)"),
            2,
        )
        self.assertIn("'all'::text as setting_code", profiles)
        self.assertIn("cohort.setting_code, dimension, code, label", profiles)

    def test_classification_inference_literals_match_the_accepted_catalogue_rules(self) -> None:
        """PostgreSQL word/whitespace escapes must retain their regex meaning."""
        classification = self.raw_sql.split(
            "create view analysis.analysis_window_reporting_classification_v6", 1
        )[1].split("create view analysis.analysis_window_injury_cohort_v6", 1)[0]
        accepted = CLASSIFICATION_RULES_MIGRATION.read_text(encoding="utf-8")
        for literal in (
            r"'\m(neck|cervical)\M'",
            r"'(^|[,;/])\s*muscle(s| injury)?\s*($|[,;/])'",
            r"'(\mankle\M|syndesmo|high ankle sprain)'",
        ):
            # Not a source-text coincidence: these delimiters are required by
            # the accepted conservative rules and are executed by PostgreSQL.
            self.assertIn(literal, accepted)
            self.assertIn(literal, classification)
        self.assertNotIn(r"\\m", classification)
        self.assertNotIn(r"\\s", classification)

    def test_team_and_league_sections_are_materialised_from_curated_values(self) -> None:
        for relation in (
            "analysis_window_profiles_v6",
            "analysis_window_setting_metrics_v6",
            "analysis_window_severity_v6",
            "analysis_window_contact_distribution_v6",
            "analysis_window_league_profiles_v6",
            "analysis_window_league_setting_metrics_v6",
            "analysis_window_league_severity_v6",
            "analysis_window_league_contact_distribution_v6",
            "team_dashboard_payload_analysis_window_v6_enriched",
            "league_dashboard_payload_analysis_window_v6_enriched",
        ):
            self.assertIn(relation, self.sql)
        self.assertIn("sum(time_loss_injuries)", self.sql)
        self.assertIn("sum(days_lost)", self.sql)

    def test_every_headline_metric_satisfies_the_public_reader_formula_contract(self) -> None:
        headline_lines = [
            line for line in self.sql.splitlines()
            if "'headline',jsonb_build_array(" in line
        ]
        self.assertEqual(2, len(headline_lines), "team and league headline builders are required")
        for line in headline_lines:
            metrics = line.split("jsonb_build_object('key'")[1:]
            self.assertGreaterEqual(len(metrics), 5)
            for metric in metrics:
                self.assertIn("'formula'", metric)

    def test_contact_distribution_satisfies_the_public_key_and_label_contract(self) -> None:
        contact_lines = [
            line for line in self.sql.splitlines()
            if "'contact_distribution',coalesce(" in line
        ]
        self.assertEqual(2, len(contact_lines), "team and league contact builders are required")
        for line in contact_lines:
            self.assertIn("jsonb_build_object('key',contact_context,'label'", line)
            self.assertNotIn("jsonb_build_object('setting',setting_code,'contact_context'", line)

    def test_team_and_league_headlines_retain_the_shared_median_severity_metric(self) -> None:
        self.assertGreaterEqual(self.sql.count("percentile_cont(0.5)"), 2)
        headline_lines = [
            line for line in self.sql.splitlines()
            if "'headline',jsonb_build_array(" in line
        ]
        self.assertEqual(2, len(headline_lines))
        for line in headline_lines:
            self.assertIn("'key','severity_median_days'", line)
            self.assertIn("'formula','median(days lost) across pooled time-loss injuries'", line)

    def test_urc_match_activity_is_not_misclassified_as_unknown(self) -> None:
        self.assertIn(
            "when 'match' then 'match' when 'urc_match' then 'match'",
            self.sql,
        )

    def test_profiles_are_observed_while_setting_and_contact_grids_are_complete(self) -> None:
        """Profiles retain observations; setting/contact domains retain zero cells."""
        for token in (
            "analysis.analysis_window_profile_rows_v6",
            "values ('all'), ('match'), ('training'), ('unknown')",
            "values ('contact', 'contact'), ('non_contact', 'non-contact'), ('unknown', 'unknown')",
            "analysis.injury_type_families_from_payload_v1(",
            "when 'all' then hours.total_hours",
            "when 'all' then summary.exposure_hours",
        ):
            self.assertIn(token, self.sql)

    def test_reporting_window_coverage_counts_only_window_exposed_known_players(self) -> None:
        exposure = self.sql.split("create view analysis.analysis_window_team_exposure_v6", 1)[1]
        self.assertIn("exposure.player_uid", exposure)
        self.assertIn("period_start", exposure)
        self.assertIn("window.season_start", exposure)
        self.assertIn("window.season_end", exposure)
        self.assertIn("count(distinct nullif(exposure.player_uid,'unknown'))", self.sql)
        self.assertNotIn(
            "from curated.exposure exposure where exposure.curated_build_id=member.curated_build_id",
            self.sql,
        )

    def test_setting_metrics_keep_the_full_denominator_grid_when_a_setting_has_no_injury(self) -> None:
        setting_metrics = self.sql.split("create view analysis.analysis_window_setting_metrics_v6", 1)[1]
        self.assertIn("setting_domain(setting_code)", setting_metrics)
        self.assertIn("cross join setting_domain", setting_metrics)
        self.assertIn("coalesce(grouped.time_loss_injuries, 0)", setting_metrics)


if __name__ == "__main__":
    unittest.main()
