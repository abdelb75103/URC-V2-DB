from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "pipeline/sql_exec.mjs").read_text(encoding="utf-8")


class SqlExecTransactionIsolationTests(unittest.TestCase):
    def test_repeatable_read_is_the_only_non_default_value(self) -> None:
        self.assertIn('if (raw === "") return "";', SOURCE)
        self.assertIn(
            'if (raw === "repeatable_read") return "repeatable read";',
            SOURCE,
        )
        self.assertIn(
            "PIPELINE_TRANSACTION_ISOLATION must be empty or repeatable_read",
            SOURCE,
        )

    def test_isolation_is_set_before_any_transactional_data_query(self) -> None:
        transaction = SOURCE.split('await client.query("begin");', 1)[1]
        isolation = transaction.index("set transaction isolation level")
        target_proof = transaction.index("await proveApprovedLiveTarget(client)")
        params_table = transaction.index("create temp table _pipeline_params")

        self.assertLess(isolation, target_proof)
        self.assertLess(isolation, params_table)


if __name__ == "__main__":
    unittest.main()
