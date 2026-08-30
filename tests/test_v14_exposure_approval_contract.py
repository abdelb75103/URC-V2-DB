from __future__ import annotations

import hashlib
import inspect
import json
from pathlib import Path
import tempfile
import unittest

import pipeline.__main__ as pipeline
from scripts import build_year2_exposure_successor_envelope as builder


ROOT = Path(__file__).resolve().parents[1]
APPROVAL = ROOT / pipeline.V14_EXPOSURE_TASK_APPROVAL_LOCATOR


class V14ExposureApprovalContractTests(unittest.TestCase):
    def test_exact_task_approval_bytes_pass_the_shared_contract(self) -> None:
        approval, requested_at = pipeline.validate_v14_task_approval_evidence(APPROVAL)

        self.assertEqual(
            hashlib.sha256(APPROVAL.read_bytes()).hexdigest(),
            pipeline.V14_EXPOSURE_TASK_APPROVAL_SHA256,
        )
        self.assertEqual(approval["approved_by"], "Abdel Babiker")
        self.assertIsNotNone(requested_at.tzinfo)

    def test_any_task_approval_mutation_is_rejected(self) -> None:
        mutated = json.loads(APPROVAL.read_text())
        mutated["approval_statement"] = "Changed instruction"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "task_approval.json"
            path.write_text(json.dumps(mutated, indent=2, sort_keys=True) + "\n")
            with self.assertRaisesRegex(SystemExit, "checksum mismatch"):
                pipeline.validate_v14_task_approval_evidence(path)

    def test_builder_uses_the_shared_immutable_approval_validator(self) -> None:
        source = inspect.getsource(builder.main)

        self.assertIn("validate_v14_task_approval_evidence", source)
        self.assertLess(
            source.index("validate_v14_task_approval_evidence"),
            source.index("output.mkdir"),
        )
        self.assertIn("V14_EXPOSURE_TASK_APPROVAL_SHA256", source)

    def test_root_validator_requires_the_exact_approval_binding_and_bytes(self) -> None:
        source = inspect.getsource(pipeline.validate_v14_exposure_root_for_ingest)

        self.assertIn('"sha256": V14_EXPOSURE_TASK_APPROVAL_SHA256', source)
        self.assertIn("validate_v14_task_approval_evidence", source)


if __name__ == "__main__":
    unittest.main()
