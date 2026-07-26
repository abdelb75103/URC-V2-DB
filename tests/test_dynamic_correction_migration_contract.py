from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260726200000_dynamic_row_correction_pipeline.sql"


class DynamicCorrectionMigrationContractTests(unittest.TestCase):
    """Static contracts for the additive, unapplied row-correction migration.

    These assertions deliberately do not connect to Supabase.  They lock down
    the guardrails that must be visible in the reviewed SQL before the live,
    data-neutral migration is considered for application.
    """

    @classmethod
    def setUpClass(cls) -> None:
        if not MIGRATION.exists():
            raise AssertionError(f"missing planned migration: {MIGRATION}")
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lowered = cls.sql.lower()

    def assertSqlContains(self, *fragments: str) -> None:
        for fragment in fragments:
            self.assertIn(fragment.lower(), self.lowered)

    def function_body(self, qualified_name: str) -> str:
        match = re.search(
            rf"create function\s+{re.escape(qualified_name.lower())}\s*\(.*?\n\$\$;",
            self.lowered,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, f"missing function {qualified_name}")
        return match.group(0) if match else ""

    def test_is_additive_and_does_not_mutate_frozen_or_source_layers(self) -> None:
        self.assertSqlContains(
            "audit.apply_row_correction_v1",
            "analysis.row_correction_preview_v1",
            "analysis.row_correction_proposal_hash_v1",
            "analysis.row_correction_pending_candidate_v1",
            "reporting.promote_row_correction_v1",
            "reporting.rollback_row_correction_bundle_v1",
        )
        self.assertNotRegex(self.lowered, r"\b(drop|truncate)\s+(table|view|materialized view|function)\b")
        self.assertNotRegex(self.lowered, r"\b(update|delete\s+from|insert\s+into)\s+ingestion\.source_rows\b")
        self.assertNotRegex(self.lowered, r"\b(update|delete\s+from|insert\s+into)\s+curated\.")
        self.assertNotRegex(
            self.lowered,
            r"create\s+or\s+replace\s+(?:materialized\s+)?view\s+analysis\.[^\s;]*_v5\b",
        )

    def test_append_only_correction_history_has_old_value_and_optimistic_guards(self) -> None:
        self.assertSqlContains(
            "source_row_id",
            "season",
            "field_name",
            "old_value",
            "new_value",
            "row_sha256",
            "evidence_sha256",
            "proposal_hash",
            "correction_set_hash",
            "rule_version",
            "operator",
            "reviewer",
            "supersedes",
        )
        self.assertRegex(self.lowered, r"\bimmutable\b")
        self.assertRegex(self.lowered, r"\b(concurrent|stale|optimistic)\b")
        self.assertRegex(self.lowered, r"\bcurrent\s+(?:effective\s+)?value\b|old[_ ]value")
        self.assertRegex(self.lowered, r"\bfor\s+update\b")
        self.assertRegex(self.lowered, r"\b(unique|exclude)\b")

    def test_effective_overlay_is_season_keyed_and_covers_all_rows(self) -> None:
        self.assertSqlContains("processing.record_versions", "row correction", "season")
        self.assertRegex(
            self.lowered,
            r"(?:left\s+join|not\s+exists|union\s+all).{0,500}(?:row_correction|correction)",
        )
        self.assertNotRegex(self.lowered, r"\b(?:where|and)\s+season\s*=\s*'2024-25'")
        self.assertNotRegex(self.lowered, r"\b(?:where|and)\s+season\s*=\s*'2025-26'")

    def test_allowlisted_typed_fields_preserve_clinical_evidence_and_validate_ioc(self) -> None:
        for field in (
            "eligibility",
            "diagnosis",
            "body_location",
            "injury_type",
            "days",
        ):
            self.assertIn(field, self.lowered)
        self.assertRegex(self.lowered, r"\b(?:allowlist|allowlisted|allowed[_ ]fields?)\b")
        self.assertRegex(self.lowered, r"\b(jsonb_typeof|pg_typeof|typeof)\b|\bboolean\b|\bnumeric\b")
        self.assertRegex(self.lowered, r"\b(ioc|taxonomy|code_lists)\b")
        self.assertRegex(self.lowered, r"\b(source|evidence).{0,120}(?:preserv|original)")

    def test_preview_rederives_team_and_pooled_league_metrics_in_sql(self) -> None:
        preview = self.function_body("analysis.row_correction_preview_v1")
        self.assertIn("row_correction_pending_candidate_v1", preview)
        self.assertSqlContains(
            "analysis.team_dashboard_release_candidates_correction_v1",
            "analysis.league_dashboard_release_candidates_correction_v1",
            "analysis.row_correction_team_dashboard_payload_v1",
            "analysis.row_correction_league_dashboard_payload_v1",
        )
        for metric_signal in (
            "injury",
            "time_loss",
            "days_lost",
            "incidence",
            "burden",
            "severity",
            "team",
            "league",
        ):
            self.assertIn(metric_signal, self.lowered)
        self.assertRegex(self.lowered, r"\bcount\s*\(")
        self.assertRegex(self.lowered, r"\bsum\s*\(")
        self.assertRegex(self.lowered, r"\*\s*1000(?:\.0)?")
        self.assertRegex(
            self.lowered,
            r"\b(pool|pooled).{0,240}\bleague\b|\bleague\b.{0,240}\b(pool|pooled)\b",
        )

    def test_candidate_reuses_fifteen_predecessors_and_binds_exact_hashes(self) -> None:
        candidate = self.lowered.split("analysis.row_correction_pending_candidate_v1", 1)[1]
        self.assertIn("payload_sha256", candidate)
        self.assertRegex(candidate, r"\b15\b")
        self.assertRegex(candidate, r"\b(predecessor|unchanged|reuse)\b")
        self.assertIn("league", candidate)
        self.assertIn("team", candidate)
        self.assertRegex(candidate, r"\b(jsonb|dashboard_payload|bundle)\b")

    def test_promotion_and_compensating_rollback_are_separate_audited_hooks(self) -> None:
        promotion = self.lowered.split("reporting.promote_row_correction_v1", 1)[1]
        rollback = self.lowered.split("reporting.rollback_row_correction_bundle_v1", 1)[1]
        self.assertRegex(promotion, r"\b(approved|promot)\b")
        self.assertRegex(promotion, r"\b(preflight|candidate|hash)\b")
        self.assertRegex(promotion, r"\b(retired|predecessor)\b")
        self.assertRegex(rollback, r"\b(predecessor|compensat|restore)\b")
        self.assertNotRegex(rollback, r"\bdelete\s+from\b")

    def test_dynamic_payload_storage_does_not_bypass_frozen_v2_foreign_keys(self) -> None:
        promotion = self.function_body("reporting.promote_row_correction_v1")
        rollback = self.function_body(
            "reporting.rollback_row_correction_bundle_v1"
        )
        self.assertSqlContains(
            "create table reporting.correction_league_payloads_v1",
            "create table reporting.correction_team_payloads_v1",
            "create view reporting.dashboard_bundle_league_payloads_v1",
            "create view reporting.dashboard_bundle_team_payloads_v1",
            "create view reporting.latest_approved_dashboard_bundle_v4",
            "create view reporting.latest_team_dashboard_v5",
            "create view reporting.latest_league_dashboard_v5",
        )
        for body in (promotion, rollback):
            self.assertIn(
                "insert into reporting.correction_league_payloads_v1", body
            )
            self.assertIn(
                "insert into reporting.correction_team_payloads_v1", body
            )
            self.assertNotIn(
                "insert into reporting.league_release_payloads_v2", body
            )
            self.assertNotIn(
                "insert into reporting.team_dashboard_payloads_v2", body
            )
            self.assertNotIn(
                "insert into reporting.league_release_context_v2", body
            )

    def test_unified_views_are_owner_executed_but_private_from_web_reader(self) -> None:
        for view_name in (
            "reporting.dashboard_bundle_context_v1",
            "reporting.dashboard_bundle_league_payloads_v1",
            "reporting.dashboard_bundle_team_payloads_v1",
            "reporting.latest_approved_dashboard_bundle_v4",
        ):
            definition = self.lowered.split(f"create view {view_name}", 1)[1]
            definition = definition.split("create ", 1)[0]
            self.assertIn(
                "security_invoker = false",
                definition,
                f"{view_name} must execute as its owner across private sources",
            )
            self.assertIn("security_barrier = true", definition)
        self.assertRegex(
            self.lowered,
            r"revoke\s+all\s+on\s+reporting\.dashboard_bundle_context_v1"
            r"[\s\S]{0,300}\bweb_reader\b",
        )
        self.assertRegex(
            self.lowered,
            r"revoke\s+all\s+on\s+reporting\.dashboard_bundle_league_payloads_v1"
            r"[\s\S]{0,300}\bweb_reader\b",
        )
        self.assertRegex(
            self.lowered,
            r"revoke\s+all\s+on\s+reporting\.dashboard_bundle_team_payloads_v1"
            r"[\s\S]{0,300}\bweb_reader\b",
        )

    def test_v5_readers_preserve_contact_distribution(self) -> None:
        for view_name in (
            "reporting.latest_team_dashboard_v5",
            "reporting.latest_league_dashboard_v5",
        ):
            definition = self.lowered.split(f"create view {view_name}", 1)[1]
            definition = definition.split("create ", 1)[0]
            self.assertIn("security_invoker = false", definition)
            self.assertIn("security_barrier = true", definition)
            self.assertIn(
                "payload.dashboard_payload -> 'contact_distribution'",
                definition,
            )
        self.assertSqlContains(
            "grant select on reporting.latest_team_dashboard_v5 to web_reader",
            "grant select on reporting.latest_league_dashboard_v5 to web_reader",
            "analysis.row_correction_contact_distribution_v1",
            "analysis.row_correction_league_contact_distribution_v1",
        )

    def test_proposal_requires_present_json_keys_and_preserves_null_days(self) -> None:
        preview = self.function_body("analysis.row_correction_preview_v1")
        self.assertIn("not (proposal ? 'expected_value')", preview)
        self.assertIn("not (proposal ? 'new_value')", preview)
        self.assertRegex(
            self.lowered,
            r"to_jsonb\(subject\.baseline_days_injured\),\s*'null'::jsonb",
        )

    def test_dynamic_payloads_cannot_be_orphaned_from_dynamic_context(self) -> None:
        league = self.function_body(
            "reporting.validate_dynamic_league_payload_v1"
        )
        teams = self.function_body(
            "reporting.validate_dynamic_team_payloads_v1"
        )
        for body in (league, teams):
            self.assertRegex(
                body,
                r"(requires|must have).{0,100}(correction|rollback).{0,40}context",
            )
        approval = self.function_body(
            "reporting.validate_dynamic_bundle_context_v1"
        )
        self.assertIn("correction_league_payloads_v1", approval)
        self.assertIn("correction_team_payloads_v1", approval)
        self.assertRegex(approval, r"payload_count\s*<>\s*16")

    def test_dead_frozen_v2_candidate_validators_are_not_redeclared(self) -> None:
        for validator in (
            "reporting.validate_league_dashboard_correction_v1_candidate",
            "reporting.validate_team_dashboard_correction_v1_candidates",
        ):
            self.assertNotRegex(
                self.lowered,
                rf"create(?:\s+or\s+replace)?\s+function\s+"
                rf"{re.escape(validator)}\b",
            )

    def test_ordinary_release_cannot_silently_drop_served_corrections(self) -> None:
        guard = self.function_body("reporting.guard_active_row_corrections_v1")
        self.assertIn("old.status = 'draft'", guard)
        self.assertIn("new.status = 'approved'", guard)
        self.assertIn("row_correction_served_sets_v1", guard)
        self.assertIn(
            "ordinary release approval blocked while served row corrections are active",
            guard,
        )
        self.assertIn("correction_release_context_v1", guard)
        self.assertIn("correction_rollback_context_v1", guard)
        self.assertIn("audit.correction_sets_v1", guard)
        self.assertRegex(guard, r"correction is (?:pending|applied but unpromoted)")

    def test_dynamic_bundle_is_validated_before_approval(self) -> None:
        validator = self.function_body(
            "reporting.validate_dynamic_bundle_context_v1"
        )
        self.assertIn("new.status <> 'approved'", validator)
        self.assertIn("correction_team_payloads_v1", validator)
        self.assertIn("correction_league_payloads_v1", validator)
        self.assertIn("row_correction_bundle_hash_v1(new.id)", validator)
        self.assertSqlContains(
            "before update of status on reporting.aggregate_releases",
            "execute function reporting.validate_dynamic_bundle_context_v1()",
        )

    def test_no_impact_correction_is_audited_and_promotes_an_all_predecessor_bundle(self) -> None:
        apply = self.function_body("audit.apply_row_correction_v1")
        promotion = self.function_body("reporting.promote_row_correction_v1")
        self.assertIn("insert into audit.correction_sets_v1", apply)
        self.assertIn("insert into processing.correction_drafts_v1", apply)
        self.assertRegex(
            promotion,
            r"affected_count\s*=\s*0",
            "promotion must permit a clean no-impact correction candidate",
        )
        self.assertRegex(
            promotion,
            r"unchanged_count\s*=\s*16",
            "no-impact promotion must retain all 16 predecessor team payloads",
        )
        self.assertIn("reporting.correction_release_context_v1", promotion)
        self.assertIn("not exists", self.function_body("analysis.row_correction_preview_v1"))

    def test_apply_signature_binds_reviewer_after_read_only_preview(self) -> None:
        apply = self.function_body("audit.apply_row_correction_v1")
        self.assertRegex(
            apply,
            r"proposal jsonb,\s+approval_evidence text,\s+approval_reviewer text",
        )
        self.assertIn("approval_reviewer", apply)
        self.assertNotIn("proposal ->> 'reviewer'", apply)
        self.assertIn("approval_evidence", apply)
        self.assertIn("'reviewer', approval_reviewer", apply)

    def test_code_and_dependency_provenance_are_recorded_with_every_correction_run(self) -> None:
        apply = self.function_body("audit.apply_row_correction_v1")
        promotion = self.function_body("reporting.promote_row_correction_v1")
        for body in (apply, promotion):
            self.assertIn("code_version", body)
            self.assertIn("migration_sha256", body)
            self.assertIn("dependency", body)
            self.assertIn("20260726200000_dynamic_row_correction_pipeline.sql", body)

    def test_immutable_layers_and_frozen_validator_contracts_are_not_rewritten(self) -> None:
        for relation in (
            "ingestion.source_rows",
            "processing.record_versions",
            "curated.injuries",
            "curated.exposure",
        ):
            self.assertNotRegex(
                self.lowered,
                rf"\b(update|delete\s+from|insert\s+into|alter\s+table)\s+{re.escape(relation)}\b",
            )
        self.assertNotRegex(
            self.lowered,
            r"\balter\s+table\s+reporting\.league_release_context_v2\b",
        )
        for validator in (
            "reporting.validate_league_dashboard_v2_candidate",
            "reporting.validate_team_dashboard_v2_candidates",
        ):
            self.assertNotRegex(
                self.lowered,
                rf"create\s+or\s+replace\s+function\s+{re.escape(validator)}\b",
            )
            self.assertNotRegex(
                self.lowered,
                rf"\bdrop\s+function\s+{re.escape(validator)}\b",
            )
        self.assertNotRegex(
            self.lowered,
            r"\bdrop\s+constraint\s+league_release_context_v2_",
        )

    def test_all_mutating_functions_take_the_season_advisory_lock_before_row_locks(self) -> None:
        for function in (
            "audit.apply_row_correction_v1",
            "reporting.promote_row_correction_v1",
            "reporting.rollback_row_correction_bundle_v1",
        ):
            body = self.function_body(function)
            advisory = body.find("pg_advisory_xact_lock")
            row_lock = body.find("for update")
            self.assertNotEqual(advisory, -1, f"{function} must take an advisory lock")
            self.assertNotEqual(row_lock, -1, f"{function} must lock its current row")
            self.assertLess(
                advisory,
                row_lock,
                f"{function} must acquire the season advisory lock before any row lock",
            )

    def test_hashing_is_schema_qualified_and_security_definers_have_safe_paths(self) -> None:
        self.assertNotRegex(self.lowered, r"(?<![a-z0-9_\.])digest\s*\(")
        self.assertIn("extensions.digest(", self.lowered)
        for function in (
            "analysis.row_correction_preview_v1",
            "audit.apply_row_correction_v1",
            "reporting.promote_row_correction_v1",
            "reporting.rollback_row_correction_bundle_v1",
        ):
            body = self.function_body(function)
            self.assertRegex(
                body,
                r"security definer\s+set search_path = pg_catalog",
                f"{function} must pin a safe search path",
            )
            self.assertNotIn("public", body.split("as $$", 1)[0])

    def test_nullable_days_lost_is_preserved_until_aggregate_stage(self) -> None:
        cohort = self.lowered.split(
            "create view analysis.row_correction_effective_injury_cohort_v1", 1
        )[1].split("create view analysis.row_correction_effective_exposure_cohort_v1", 1)[0]
        self.assertRegex(
            cohort,
            r"when jsonb_typeof\(subject\.effective_days_injured_value\) <> 'number'\s+then null",
        )
        self.assertNotRegex(cohort, r"coalesce\([^\n]*effective_days_injured_value[^\n]*,\s*0\)")

    def test_rollback_leaves_correction_history_effective_and_append_only(self) -> None:
        rollback = self.function_body("reporting.rollback_row_correction_bundle_v1")
        self.assertIn("correction_rollback_context_v1", rollback)
        self.assertIn("rollback_release_id", rollback)
        self.assertIn("active_correction_state_restored_from_predecessor", rollback)
        self.assertIn("row_correction_served_sets_v1", self.lowered)
        self.assertIn("rollback.restored_bundle_id", self.lowered)
        for relation in (
            "audit.correction_sets_v1",
            "audit.row_corrections_v1",
            "processing.correction_versions_v1",
            "processing.correction_drafts_v1",
        ):
            self.assertNotRegex(
                rollback,
                rf"\b(update|delete\s+from)\s+{re.escape(relation)}\b",
            )
        self.assertRegex(rollback, r"set status = 'retired'")
        self.assertRegex(rollback, r"set status = 'approved'")
        self.assertNotRegex(
            rollback,
            r"set status = 'approved', approved_at = now\(\)\s+where id = predecessor\.id",
        )


if __name__ == "__main__":
    unittest.main()
