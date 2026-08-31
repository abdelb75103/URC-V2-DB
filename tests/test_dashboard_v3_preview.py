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
DASHBOARD_TABS = (ROOT / "lib/dashboard-tab.ts").read_text()
CHARTS = (ROOT / "components/dashboard/charts.tsx").read_text()
INJURY_TYPE_DOSSIER = (ROOT / "components/dashboard/injury-type-dossier.tsx").read_text()
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
        self.assertNotIn("V3 inference preview - draft, not released", UI)
        self.assertNotIn("Exposure-aligned rate cohort", UI)
        self.assertNotIn("The approved V2 rate cohort uses positive recorded days", UI)

    def test_profile_rings_have_independent_settings_and_setting_aware_severity(self) -> None:
        severity_cte = PREVIEW.split("), severity as (", 1)[1].split("), match_scope as (", 1)[0]
        self.assertIn("cross join settings st", severity_cte)
        self.assertIn("st.setting_code = 'all' or c.setting_code = st.setting_code", severity_cte)
        self.assertIn("'setting', v.setting_code", PREVIEW)
        self.assertIn('.filter((item) => item.setting === "all")', GENERATOR)
        # Severity and contact expose their own setting controls.
        self.assertIn("const [setting, setSetting] = useState<Setting>('all')", UI)
        self.assertIn("row.setting === effectiveSeveritySetting", UI)
        self.assertIn("const contactDistribution = dashboard.contact_distribution", UI)
        self.assertIn("row.setting === effectiveContactSetting", UI)
        self.assertIn("<ScopeChip", UI)
        self.assertNotIn("Data coverage & provenance", UI)
        self.assertNotIn("InferenceCoverageSummary", UI)
        self.assertIn('aria-label={ariaLabel}', CHARTS)
        self.assertIn('aria-label={`${row.label}: ${count(row.value)} cases.`}', CHARTS)
        self.assertIn("CONTACT_RING_COLORS[row.key]", UI)
        self.assertNotIn("isFrontFacingUnknown(row)", UI)
        self.assertIn("selected ? 'cases' : 'total cases'", CHARTS)

    def test_descriptive_and_rate_cohorts_are_not_mixed(self) -> None:
        self.assertIn("scoped_descriptive", PREVIEW)
        self.assertIn("scoped_cohort", PREVIEW)
        self.assertIn("rate_time_loss_injuries", PREVIEW)
        incidence = PREVIEW.split("'incidence_per_1000h'", 1)[1].split("'contact_distribution'", 1)[0]
        self.assertIn("m.rate_time_loss_injuries", incidence)
        self.assertNotIn("then m.time_loss_injuries::numeric", incidence)
        self.assertIn("no team exposure-window restriction is applied", RECONCILIATION)
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
            "'knee_ligament', 'acl'",
            "'knee_ligament', 'mcl'",
            "'knee_ligament', 'pcl'",
            "'knee_ligament', 'lcl'",
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
        current_summary = PREVIEW.split("), diagnosis_candidate_summary as (", 1)[1].split(
            "), legacy_diagnosis_candidates as (", 1
        )[0]
        legacy_summary = PREVIEW.split("), legacy_diagnosis_candidate_summary as (", 1)[1].split(
            "), diagnosis_stage as (", 1
        )[0]
        for summary in (current_summary, legacy_summary):
            self.assertIn("count(distinct diagnosis_code)", summary)
            self.assertIn("array_agg(distinct diagnosis_code order by diagnosis_code)", summary)
            self.assertIn("count(distinct diagnosis_subtype)", summary)
            self.assertNotIn("count(distinct profile_code)", summary)
        self.assertIn("select id, count(distinct code)::int as candidate_count", RECONCILIATION)
        self.assertIn("count(distinct diagnosis_subtype)::int as subtype_candidate_count", RECONCILIATION)
        self.assertNotIn("select id, count(distinct profile_code)::int as candidate_count", RECONCILIATION)

    def test_concussion_capture_is_cross_column_exact_code_and_negation_aware(self) -> None:
        self.assertIn("reliable_concussion_text", PREVIEW)
        self.assertIn("cross join lateral jsonb_each_text(d.source_values)", PREVIEW)
        for field in (
            "Description", "Injury Tissue Type/s", "Body Part", "Mechanism of Injury",
            "Mechanism Notes", "Treatment/Rehab", "Injury Immediate Action",
        ):
            self.assertIn(f"'{field}'", PREVIEW)
        for code in ("HN1", "HN2", "HNC1", "HNC2", "HNCA", "HNCD", "HNCH", "HNCN", "HNCO", "HNCX"):
            self.assertIn(f"'{code}'", PREVIEW)
        self.assertIn("mapped_from_exact_orchard_concussion_code", PREVIEW)
        self.assertIn("not diagnosed", PREVIEW)
        self.assertIn("HIA negative", PREVIEW)
        self.assertIn("player not concussed", PREVIEW)
        self.assertIn("concussion with no concerning history", PREVIEW)
        self.assertIn("legacy_concussion_case_failures", PREVIEW)
        self.assertIn("Legacy fallback remains negation-aware", PREVIEW)
        self.assertIn("case when i.problem_type = 'injury' then sr.source_values ->> 'Illness Code' end", RECONCILIATION)
        self.assertIn("validateDraft9RuleChecks", GENERATOR)

    def test_knee_and_ankle_ligaments_display_under_ioc_joint_sprain_parents(self) -> None:
        self.assertIn("diagnosis_labels", PREVIEW)
        for source_code, label in (
            ("compound__knee__joint_sprain", "Knee · Joint sprain"),
            ("compound__ankle__joint_sprain", "Ankle · Joint sprain"),
            ("meniscal_injury", "Meniscal injury"),
            ("concussion", "Concussion"),
            ("hamstring_strain", "Hamstring strain"),
            ("quadriceps_muscle", "Quadriceps muscle injury"),
        ):
            self.assertRegex(PREVIEW, rf"\('{source_code}', '{re.escape(label)}',")
        for removed_code in ("acl_injury", "mcl_injury", "pcl_lcl_injury"):
            self.assertNotIn(f"('{removed_code}',", PREVIEW)
        diagnosis_labels = PREVIEW.split("), diagnosis_labels as (", 1)[1].split(
            "), diagnosis_profile_rows as (", 1
        )[0]
        self.assertNotIn("Knee ligament injury", diagnosis_labels)
        self.assertIn("'acl', 'mapped'", PREVIEW)
        self.assertIn("'generic_knee_sprain'", PREVIEW)
        self.assertIn("array['unspecified']::text[], 'unspecified', 'inferred'", PREVIEW)
        for subtype in ("ankle_lateral_ligament", "syndesmosis", "unspecified"):
            self.assertIn(f"'{subtype}'", PREVIEW)
        for distinct_code in (
            "shoulder_instability", "ac_joint_sprain", "lisfranc_injury",
            "meniscal_injury", "compound__knee__cartilage_injury",
            "compound__knee__peripheral_nerve_injury", "hamstring_strain",
            "quadriceps_muscle",
        ):
            self.assertIn(f"'{distinct_code}'", PREVIEW)
        self.assertIn("synthetic_display_taxonomy_case_failures", PREVIEW)
        self.assertIn("display_taxonomy_origin_class_changes", PREVIEW)
        self.assertIn("count(distinct diagnosis_code)::int as candidate_count", PREVIEW)
        self.assertIn("count(distinct diagnosis_subtype)::int as subtype_candidate_count", PREVIEW)
        self.assertIn("within_bucket_multi_match_refusals", PREVIEW)
        self.assertIn("cross_bucket_conflicts_classified", PREVIEW)
        self.assertIn("diagnosis_bucket_rule_cases", PREVIEW)
        for case_name in (
            "acl", "mcl", "pcl", "lcl", "cruciate", "collateral",
            "within_bucket_acl_pcl", "cross_bucket_knee_fracture",
        ):
            self.assertIn(f"'{case_name}'", PREVIEW)
        self.assertIn("synthetic_diagnosis_bucket_case_failures", PREVIEW)
        self.assertIn("from all_diagnosis_candidates", PREVIEW)
        self.assertNotIn("synthetic_diagnosis_candidates as (", PREVIEW)
        self.assertIn("('unknown', 'Unknown diagnosis'", PREVIEW)
        self.assertIn("'dimension', 'diagnosis'", PREVIEW)
        self.assertIn("profile_map_duplicate_source_codes", PREVIEW)
        self.assertIn("diagnosis_bucket_rows", PREVIEW)
        self.assertIn("duplicate_injury_rows", PREVIEW)
        self.assertIn("time_loss_profile_assignments", PREVIEW)
        self.assertIn("legacy_multi_match_refusal_checks", PREVIEW)
        self.assertIn("profile_rows", PREVIEW)

    def test_tier2_compound_and_unknown_invariants_are_explicit(self) -> None:
        self.assertIn("then concat('compound__', effective_body_location, '__', effective_injury_type)", PREVIEW)
        self.assertIn("then 'tier_2_compound'", PREVIEW)
        self.assertIn("effective_body_location <> 'unknown' and effective_injury_type <> 'unknown'", PREVIEW)
        self.assertIn("compound_missing_input_failures", PREVIEW)
        self.assertIn("unknown_with_complete_compound_inputs", PREVIEW)
        self.assertIn("synthetic_compound_origin_results", PREVIEW)
        self.assertIn("synthetic_compound_origin_case_failures", PREVIEW)
        self.assertIn("then compound_origin_group", PREVIEW)
        self.assertIn("from compound_origin_expected_cases", PREVIEW)
        self.assertIn("join compound_origin_pairs", PREVIEW)
        self.assertIn("diagnosis_unknown_exception", RECONCILIATION)
        self.assertIn("draft7_unknown_decomposition", PREVIEW)
        self.assertIn("genuinely_evidence_less_all_four", PREVIEW)

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
        self.assertIn("urc-diagnosis-inference-v3-draft.9", PREVIEW)
        self.assertIn("urc-diagnosis-inference-v3-draft.9", RECONCILIATION)
        self.assertIn("knee_ankle_ligament_families_display_under_ioc_joint_sprain_parent", RECONCILIATION)

    def test_common_injuries_contains_overall_match_and_training_rows(self) -> None:
        self.assertIn("select * from (values ('all', 1), ('match', 2), ('training', 3))", PREVIEW)
        self.assertIn("cross join settings st", PREVIEW)
        self.assertIn("'setting', p.setting_code", PREVIEW)
        self.assertIn("'Unknown diagnosis'", PREVIEW)
        self.assertIn("withoutFrontFacingUnknown", UI)
        for surface in ("Match vs training", "settingOptions", "SettingBench"):
            self.assertIn(surface, UI)
        self.assertIn("metricFor('match')", UI)
        self.assertIn("metricFor('training')", UI)

    def test_draft9_uses_one_season_bound_for_injuries_and_exposure(self) -> None:
        rule = "season_bound_2024-07-01_2025-06-30_no_exposure_window"
        self.assertIn(rule, PREVIEW)
        self.assertIn(rule, RECONCILIATION)
        self.assertIn("date_injured is null", PREVIEW)
        self.assertIn("date_injured between date '2024-07-01' and date '2025-06-30'", PREVIEW)
        self.assertIn("from curated.exposure e", PREVIEW)
        self.assertIn("coalesce(e.session_date, e.week_start_date)", PREVIEW)
        self.assertIn("round(coalesce(sum(e.minutes_clean), 0) / 60, 1)", PREVIEW)
        self.assertNotIn("from analysis.injury_cohort_by_build_v2 c", PREVIEW)
        self.assertNotIn("from analysis.exposure_hours_by_build_v2 e", PREVIEW)
        self.assertIn("outside_season_date_injuries", PREVIEW)
        self.assertIn("undated_injuries", PREVIEW)
        self.assertIn("validateDraft9SeasonBoundCohort", GENERATOR)
        self.assertIn("validateDraft9DiagnosisBuckets", GENERATOR)
        self.assertIn("classification_profile_rows", PREVIEW)
        self.assertIn("'body_locations'", PREVIEW)
        self.assertIn("'injury_types'", PREVIEW)
        self.assertIn("supplement.body_locations", UI)
        self.assertIn("supplement.injury_types", UI)

    def test_requested_dashboard_surfaces_exist(self) -> None:
        for label in (
            "Season timeline",
            "Contact mechanism",
            "Injury Location",
            "Team Comparison",
            "Exposure",
            "Common Injuries",
            "Season Comparison",
        ):
            self.assertIn(label, UI + DASHBOARD_TABS)
        self.assertIn("<InjuryTypeRanking", UI)
        self.assertIn("<InjuryTypeDossier", UI)
        self.assertIn("availableSettings(classifiedFamilies", UI)
        self.assertIn("row.setting === effectiveSetting && row.time_loss_injuries > 0", UI)
        self.assertIn("Included injury types", INJURY_TYPE_DOSSIER)
        self.assertNotIn("<svg", INJURY_TYPE_DOSSIER)
        self.assertNotIn("Head-to-foot profile", UI)

    def test_draft_supplement_is_dev_only_with_complete_production_fallback(self) -> None:
        self.assertIn('process.env.NODE_ENV === "production"', PREVIEW_READER)
        self.assertIn("supplement.monthly_by_setting.filter((row) => row.setting === effectiveSetting)", UI)
        self.assertIn("const perSettingMonthly = Boolean(supplement)", UI)
        self.assertIn("const severityDistribution = supplement?.severity_distribution ?? dashboard.severity_distribution", UI)
        self.assertIn("const severitySettings = availableSettings", UI)


if __name__ == "__main__":
    unittest.main()
