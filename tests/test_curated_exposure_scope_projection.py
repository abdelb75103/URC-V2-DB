from __future__ import annotations

import argparse
import inspect
from pathlib import Path
import unittest
from unittest.mock import patch

import pipeline.__main__ as pipeline


ROOT = Path(__file__).resolve().parents[1]
CURATED_LAYER_SQL = (
    ROOT / "supabase/migrations/20260709233356_curated_layer.sql"
).read_text(encoding="utf-8")


class CuratedExposureScopeProjectionTests(unittest.TestCase):
    def test_signed_excluded_status_projects_to_canonical_unknown_included(self) -> None:
        self.assertEqual(
            pipeline.canonical_curated_exposure_scope_status("excluded"),
            "scope_unknown_included",
        )

    def test_signed_noncanonical_statuses_project_to_canonical_unknown_included(self) -> None:
        for status in (
            "excluded",
            "outside_protocol_window",
            "within_protocol_window_scope_unknown",
        ):
            with self.subTest(status=status):
                self.assertEqual(
                    pipeline.canonical_curated_exposure_scope_status(status),
                    "scope_unknown_included",
                )

    def test_canonical_statuses_are_retained(self) -> None:
        for status in (
            "in_scope_explicit",
            "scope_unknown_included",
            "out_of_scope_explicit",
        ):
            with self.subTest(status=status):
                self.assertEqual(
                    pipeline.canonical_curated_exposure_scope_status(status),
                    status,
                )

    def test_null_and_blank_statuses_remain_null(self) -> None:
        for status in (None, "", "  \t"):
            with self.subTest(status=status):
                self.assertIsNone(
                    pipeline.canonical_curated_exposure_scope_status(status)
                )

    def test_unknown_nonblank_status_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported exposure scope_status"):
            pipeline.canonical_curated_exposure_scope_status("future_unreviewed_status")

    def test_build_sql_maps_only_the_reviewed_values_and_rejects_unknowns_first(self) -> None:
        source = inspect.getsource(pipeline.build_curated)

        self.assertIn("unsupported exposure scope_status in latest processed exposure rows", source)
        self.assertIn("nullif(btrim(rv.record_state ->> 'scope_status'), '') is not null", source)
        self.assertIn("rv.record_state ->> 'scope_status' not in", source)
        self.assertIn("= 'excluded' then 'scope_unknown_included'", source)
        self.assertIn("= 'outside_protocol_window' then 'scope_unknown_included'", source)
        self.assertIn(
            "= 'within_protocol_window_scope_unknown' then 'scope_unknown_included'",
            source,
        )
        self.assertIn("else rv.record_state ->> 'scope_status'", source)

    def test_projection_bumps_the_audited_curated_build_rule(self) -> None:
        self.assertEqual(
            pipeline.CURATED_BUILD_RULE_VERSION,
            "curated_build_2026-08-22_v2",
        )

    def test_projection_outputs_match_the_existing_curated_constraint(self) -> None:
        self.assertIn(
            "scope_status text check (scope_status in "
            "('in_scope_explicit', 'scope_unknown_included', 'out_of_scope_explicit'))",
            CURATED_LAYER_SQL,
        )
        expected_outputs = {
            "in_scope_explicit",
            "scope_unknown_included",
            "out_of_scope_explicit",
        }
        self.assertEqual(set(pipeline.CURATED_EXPOSURE_SCOPE_STATUSES), expected_outputs)
        self.assertEqual(
            set(pipeline.CURATED_EXPOSURE_SCOPE_PROJECTION.values()),
            {"scope_unknown_included"},
        )

    def test_year2_successor_build_rejects_a_different_exposure_digest(self) -> None:
        args = argparse.Namespace(
            team="Bulls",
            season="2025-26",
            rebuild=True,
            exposure_file_sha256="0" * 64,
        )
        with patch.object(pipeline, "resolve_team_key", return_value="bulls"):
            with self.assertRaisesRegex(SystemExit, "approved contract for bulls"):
                pipeline.build_curated(args)

    def test_year2_successor_build_selects_the_reviewed_digest_by_default(self) -> None:
        args = argparse.Namespace(
            team="Bulls",
            season="2025-26",
            rebuild=True,
            exposure_file_sha256="",
        )
        calls: list[tuple[str, str, str, str]] = []

        def capture(team: str, season: str, pattern: str, digest: str = "") -> list[str]:
            calls.append((team, season, pattern, digest))
            if pattern == "%injury%":
                return ["injury-version"]
            raise RuntimeError("selection captured before any database mutation")

        with (
            patch.object(pipeline, "resolve_team_key", return_value="bulls"),
            patch.object(pipeline, "latest_curated_source_version_ids", side_effect=capture),
            self.assertRaisesRegex(RuntimeError, "selection captured"),
        ):
            pipeline.build_curated(args)

        self.assertEqual(
            calls[-1],
            (
                "Bulls",
                "2025-26",
                "%exposure%",
                pipeline.V14_EXPOSURE_SHA256S["bulls"],
            ),
        )


if __name__ == "__main__":
    unittest.main()
