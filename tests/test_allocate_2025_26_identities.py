from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tools.allocate_2025_26_identities import prepare_identity_allocation


class Allocate2025_26IdentitiesTests(unittest.TestCase):
    def write_codebook(self, root: Path) -> Path:
        path = root / "codebook.csv"
        path.write_bytes(
            b"original_id,new_id\r\n"
            b"Returning Player,Ath_2\r\n"
            b"Collision,Ath_7\r\n"
            b" collision ,Ath_8\r\n"
        )
        return path

    def write_request(self, root: Path, team: str, identities: list[str]) -> None:
        directory = root / "requests" / team
        directory.mkdir(parents=True)
        (directory / "identity_allocation_request.json").write_text(
            json.dumps(
                {
                    "count": len(identities),
                    "purpose": "synthetic test",
                    "raw_identities_absent_from_codebook": identities,
                    "season": "2025-26",
                    "team_key": team,
                }
            ),
            encoding="utf-8",
        )

    def test_preserves_returning_ids_and_appends_new_ids_after_the_maximum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            codebook = self.write_codebook(root)
            self.write_request(root, "club-one", [" returning   player ", "New Player"])
            outputs = prepare_identity_allocation(
                codebook=codebook,
                requests_root=root / "requests",
                expected_codebook_sha256=hashlib.sha256(codebook.read_bytes()).hexdigest(),
                candidate_codebook=root / "candidate.csv",
                bridge_path=root / "bridge.json",
                audit_path=root / "audit.json",
            )

            self.assertEqual(outputs["existing_matches"], 1)
            self.assertEqual(outputs["appended_identities"], 1)
            self.assertEqual(outputs["unresolved_identities"], 0)
            self.assertTrue((root / "candidate.csv").read_bytes().startswith(codebook.read_bytes()))
            with (root / "candidate.csv").open(newline="", encoding="cp1252") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(rows[-1], {"original_id": "New Player", "new_id": "Ath_9"})
            bridge = json.loads((root / "bridge.json").read_text(encoding="utf-8"))
            resolved = {row["raw_identity"]: row["new_id"] for row in bridge["resolved"]}
            self.assertEqual(resolved[" returning   player "], "Ath_2")
            self.assertEqual(resolved["New Player"], "Ath_9")

    def test_quarantines_existing_collisions_and_cross_team_matches(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            codebook = self.write_codebook(root)
            self.write_request(root, "club-one", ["COLLISION", "Shared Player"])
            self.write_request(root, "club-two", ["shared player"])
            outputs = prepare_identity_allocation(
                codebook=codebook,
                requests_root=root / "requests",
                expected_codebook_sha256=hashlib.sha256(codebook.read_bytes()).hexdigest(),
                candidate_codebook=root / "candidate.csv",
                bridge_path=root / "bridge.json",
                audit_path=root / "audit.json",
            )

            self.assertEqual(outputs["appended_identities"], 0)
            self.assertEqual(outputs["unresolved_identities"], 3)
            self.assertEqual((root / "candidate.csv").read_bytes(), codebook.read_bytes())
            bridge = json.loads((root / "bridge.json").read_text(encoding="utf-8"))
            self.assertEqual(
                {row["reason"] for row in bridge["unresolved"]},
                {"ambiguous_existing_identity", "cross_team_identity_requires_review"},
            )

    def test_fails_closed_on_codebook_or_request_contract_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            codebook = self.write_codebook(root)
            self.write_request(root, "club-one", ["New Player"])
            with self.assertRaisesRegex(ValueError, "codebook checksum drift"):
                prepare_identity_allocation(
                    codebook=codebook,
                    requests_root=root / "requests",
                    expected_codebook_sha256="0" * 64,
                    candidate_codebook=root / "candidate.csv",
                    bridge_path=root / "bridge.json",
                    audit_path=root / "audit.json",
                )

            request = root / "requests/club-one/identity_allocation_request.json"
            payload = json.loads(request.read_text(encoding="utf-8"))
            payload["count"] = 2
            request.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "request count mismatch"):
                prepare_identity_allocation(
                    codebook=codebook,
                    requests_root=root / "requests",
                    expected_codebook_sha256=hashlib.sha256(codebook.read_bytes()).hexdigest(),
                    candidate_codebook=root / "candidate.csv",
                    bridge_path=root / "bridge.json",
                    audit_path=root / "audit.json",
                )


if __name__ == "__main__":
    unittest.main()
