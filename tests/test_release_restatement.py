from __future__ import annotations

import json
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path

from pipeline.__main__ import sha256_json, validate_release_restatement


class ReleaseRestatementTests(unittest.TestCase):
    def test_exact_approved_restatement_binds_the_blocked_diff(self) -> None:
        blocked = [{"path": "headline[0].value", "kind": "value_mismatch", "old": 12, "new": 62}]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "restatement.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": "release_restatement_v1",
                        "team_key": "bulls",
                        "season": "2024-25",
                        "previous_dashboard_sha256": "old-sha",
                        "release_content_hash": "new-content-hash",
                        "blocked_diffs_sha256": sha256_json(blocked),
                        "reason_code": "input_representation_correction",
                        "rationale": "Normalize the approved month-first source dates before frozen analysis.",
                        "approved_by": "Abdel Babiker",
                        "approved_at": datetime.now(UTC).isoformat(),
                    }
                )
                + "\n"
            )

            validated = validate_release_restatement(
                path,
                team_key="bulls",
                season="2024-25",
                previous_dashboard_sha256="old-sha",
                release_content_hash="new-content-hash",
                blocked_diffs=blocked,
            )

            self.assertEqual("input_representation_correction", validated["reason_code"])
            self.assertEqual(sha256_json(blocked), validated["blocked_diffs_sha256"])

    def test_restatement_rejects_a_different_numeric_diff(self) -> None:
        approved = [{"path": "headline[0].value", "kind": "value_mismatch", "old": 12, "new": 62}]
        actual = [{"path": "headline[0].value", "kind": "value_mismatch", "old": 12, "new": 61}]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "restatement.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": "release_restatement_v1",
                        "team_key": "bulls",
                        "season": "2024-25",
                        "previous_dashboard_sha256": "old-sha",
                        "release_content_hash": "new-content-hash",
                        "blocked_diffs_sha256": sha256_json(approved),
                        "reason_code": "input_representation_correction",
                        "rationale": "Approved exact correction.",
                        "approved_by": "Abdel Babiker",
                        "approved_at": datetime.now(UTC).isoformat(),
                    }
                )
                + "\n"
            )

            with self.assertRaisesRegex(SystemExit, "blocked diff checksum"):
                validate_release_restatement(
                    path,
                    team_key="bulls",
                    season="2024-25",
                    previous_dashboard_sha256="old-sha",
                    release_content_hash="new-content-hash",
                    blocked_diffs=actual,
                )


if __name__ == "__main__":
    unittest.main()
