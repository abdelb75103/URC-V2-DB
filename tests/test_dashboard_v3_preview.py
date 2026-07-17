from __future__ import annotations

import csv
import os
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREVIEW = (ROOT / "tools/sql/dashboard_v3_preview.sql").read_text()
RECONCILIATION = (ROOT / "tools/sql/dashboard_v3_reconciliation.sql").read_text()
GENERATOR = (ROOT / "tools/generate-dashboard-v3-preview.mjs").read_text()
UI = (ROOT / "components/dashboard/team-dashboard.tsx").read_text()
PREVIEW_READER = (ROOT / "lib/reporting-preview.ts").read_text()
REPORTING_TYPES = (ROOT / "lib/reporting-types.ts").read_text()
IOC_BUCKETS = list(csv.DictReader((ROOT / "docs/IOC_TAXONOMY_BUCKETS.csv").open()))


class DashboardV3PreviewTests(unittest.TestCase):
    def test_database_work_is_read_only_and_build_pinned(self) -> None:
        self.assertIn('client.query("begin read only")', GENERATOR)
        for sql in (PREVIEW, RECONCILIATION):
            self.assertNotRegex(
                sql.lower(),
                r"\b(insert|update|delete|drop|create|alter|truncate)\s+(into|table|view|function|schema)?\b",
            )
            self.assertIn("analysis.league_member_releases_v2", sql)
        self.assertIn("source_query_sha256", GENERATOR)
        self.assertIn("draft_not_for_release", PREVIEW)
        self.assertIn('"test:dashboard-v3"', (ROOT / "package.json").read_text())

    def test_generator_refuses_public_output_paths_before_database_access(self) -> None:
        env = os.environ.copy()
        env.pop("DATABASE_URL", None)
        env.pop("SUPABASE_DB_URL", None)
        for arguments in (
            ["--output", str(ROOT / "content/reporting/blocked-preview.json")],
            [
                "--output", str(ROOT / "data/reporting/unused-preview.json"),
                "--reconciliation-output", str(ROOT / "public/blocked-reconciliation.json"),
            ],
        ):
            result = subprocess.run(
                ["node", str(ROOT / "tools/generate-dashboard-v3-preview.mjs"), *arguments],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must not write under public payload directory", result.stderr)

    def test_case_status_and_severity_are_separate(self) -> None:
        self.assertIn("descriptive_consequence", PREVIEW)
        self.assertIn("coalesce(days_injured, 0) > 0 or source_class in", PREVIEW)
        self.assertIn("days_injured = 0 and is_closed is true", PREVIEW)
        self.assertIn("consequence_unknown", PREVIEW)
        self.assertIn("rate_ineligible_time_loss_injuries", PREVIEW)
        self.assertIn("descriptive and rate time-loss cohorts do not reconcile", GENERATOR)
        self.assertIn("Exposure-aligned rate cohort", UI)
        self.assertIn("Positive-day cases", UI)

    def test_descriptive_and_rate_cohorts_are_not_mixed(self) -> None:
        self.assertIn("scoped_descriptive", PREVIEW)
        self.assertIn("scoped_cohort", PREVIEW)
        self.assertIn("rate_time_loss_injuries", PREVIEW)
        incidence = PREVIEW.split("'incidence_per_1000h'", 1)[1].split("'contact_distribution'", 1)[0]
        self.assertIn("m.rate_time_loss_injuries", incidence)
        self.assertNotIn("then m.time_loss_injuries::numeric", incidence)
        self.assertIn("only this cohort can feed incidence and burden", RECONCILIATION)
        self.assertIn("italian elite championship", PREVIEW)
        self.assertIn("retained_generic_match_cases", PREVIEW)

    def test_monthly_match_denominator_matches_approved_fixture_rule(self) -> None:
        self.assertIn("20.0::numeric as exposure_hours", PREVIEW)
        self.assertIn("curated.fixtures", PREVIEW)
        self.assertIn("f.home_team_key", PREVIEW)
        self.assertIn("f.away_team_key", PREVIEW)

    def test_diagnosis_rules_are_conservative_and_auditable(self) -> None:
        for rule in (
            "ac_joint_sprain",
            "syndesmosis_injury",
            "lisfranc_injury",
            "acl_injury",
            "mcl_injury",
            "pcl_lcl_injury",
            "meniscal_injury",
        ):
            self.assertIn(rule, PREVIEW)
        self.assertIn("diagnosis_code", PREVIEW)
        self.assertIn("classified_time_loss_injuries", PREVIEW)
        self.assertIn("Named-diagnosis precedence", PREVIEW)
        self.assertLess(PREVIEW.index("'ac_joint_sprain'"), PREVIEW.index("'tendon_injury'"))
        self.assertIn("legacy_diagnosis_candidates", PREVIEW)
        self.assertIn("legacy_diagnosis_candidate_count > 1", PREVIEW)
        self.assertIn("Multiple current or legacy named diagnosis patterns match; none is selected.", PREVIEW)
        diagnosis_rules = PREVIEW.split("), diagnosis_candidates as (", 1)[1].split(
            "), diagnosis_candidate_summary as (", 1
        )[0]
        self.assertNotRegex(diagnosis_rules.lower(), r"substring\([^\n]*orchard|substr\([^\n]*orchard")

    def test_body_and_tissue_rules_use_only_controlled_ioc_buckets(self) -> None:
        body_buckets = {row["bucket_key"] for row in IOC_BUCKETS if row["domain"] == "body_location"}
        tissue_buckets = {row["bucket_key"] for row in IOC_BUCKETS if row["domain"] == "injury_type"}
        for bucket in ("thigh", "ankle", "shoulder", "foot", "knee", "lower_leg"):
            self.assertIn(bucket, body_buckets)
            self.assertIn(f"'{bucket}'", PREVIEW)
        for bucket in ("muscle_injury", "joint_sprain", "cartilage_injury", "tendon_rupture", "fracture"):
            self.assertIn(bucket, tissue_buckets)
            self.assertIn(f"'{bucket}'", PREVIEW)
        self.assertIn("strict Orchard/OSIICS first-character", PREVIEW)
        self.assertIn("A strict second-character code is pathology evidence, never a diagnosis", PREVIEW)
        self.assertIn("when coalesce(d.body_location, 'unknown') <> 'unknown' then d.body_location", PREVIEW)
        self.assertIn("when coalesce(d.injury_type, 'unknown') <> 'unknown' then d.injury_type", PREVIEW)

    def test_conflicts_are_refused_and_written_to_adjudication_ledger(self) -> None:
        for field, count_column in (
            ("body_location", "body_candidate_count"),
            ("tissue_pathology", "tissue_candidate_count"),
            ("contact_context", "contact_candidate_count"),
            ("diagnosis", "diagnosis_candidate_count"),
        ):
            self.assertIn(f"'{field}'", PREVIEW)
            self.assertIn(f"{count_column} > 1", PREVIEW)
        self.assertIn("row.candidate_values.length < 2", GENERATOR)
        self.assertIn("evidence fragment exceeds six words", GENERATOR)
        self.assertIn("adjudication_candidates: _privateCandidates", GENERATOR)
        self.assertIn("inference_adjudication_candidates_2024-25.json", GENERATOR)

    def test_each_inference_coverage_column_partitions_the_same_cohort(self) -> None:
        for field in ("body_location", "tissue_pathology", "diagnosis", "contact_context"):
            self.assertIn(f"'{field}', jsonb_build_object", PREVIEW)
            self.assertIn(f"{field}:", PREVIEW_READER)
            self.assertIn(field, REPORTING_TYPES)
        for count in (
            "source_reported",
            "mapped",
            "inferred",
            "adjudicated",
            "remaining_unknown",
            "unknown_before_v3",
            "classified",
            "total",
        ):
            self.assertIn(count, PREVIEW)
            self.assertIn(count, PREVIEW_READER)
            self.assertIn(count, REPORTING_TYPES)
        self.assertIn("origins do not partition the descriptive cohort", GENERATOR)
        self.assertIn("preview/reconciliation counts differ", GENERATOR)
        self.assertIn("inference_partition_total", RECONCILIATION)
        self.assertIn("urc-diagnosis-inference-v3-draft.5", PREVIEW)
        self.assertIn("urc-diagnosis-inference-v3-draft.5", RECONCILIATION)

    def test_requested_dashboard_surfaces_exist(self) -> None:
        for label in (
            "Cases by month",
            "Match incidence by month",
            "Contact vs non-contact",
            "Team Comparison",
            "Exposure",
            "Common Injuries",
        ):
            self.assertIn(label, UI)
        self.assertIn("slice(0, 10)", UI)
        self.assertNotIn("Head-to-foot profile", UI)

    def test_draft_supplement_is_dev_only_with_complete_production_fallback(self) -> None:
        self.assertIn('process.env.NODE_ENV === "production"', PREVIEW_READER)
        self.assertIn("supplement ? matchMonthly : approvedMonthly", UI)
        self.assertIn("supplement && <Panel title=\"Contact vs non-contact\"", UI)


if __name__ == "__main__":
    unittest.main()
