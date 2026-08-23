from pathlib import Path
import os
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "pipeline" / "approved_target.mjs"


class ApprovedTargetTests(unittest.TestCase):
    def run_node(self, source: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["node", "--input-type=module", "--eval", source],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_live_proof_accepts_exact_migration_and_frozen_release_identity(self) -> None:
        source = f"""
          import {{ proveApprovedLiveTarget }} from {str(MODULE)!r};
          let calls = 0;
          const client = {{
            async query(sql) {{
              calls += 1;
              if (!sql.includes('20260803163430')) throw new Error('migration evidence missing');
              if (!sql.includes('urc-2024-25-correction-r1122-20260729-a1')) throw new Error('release evidence missing');
              return {{ rows: [{{
                database_name: 'postgres',
                database_role: 'postgres',
                migration_matches: true,
                frozen_release_matches: true
              }}] }};
            }}
          }};
          const proof = await proveApprovedLiveTarget(client);
          if (calls !== 1) process.exit(3);
          if (proof.projectRef !== 'eukkvswaxweenovqqgzr') process.exit(4);
          process.stdout.write('ok');
        """
        result = self.run_node(source)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("ok", result.stdout)

    def test_live_proof_rejects_a_missing_frozen_release_identity(self) -> None:
        source = f"""
          import {{ proveApprovedLiveTarget }} from {str(MODULE)!r};
          const client = {{
            async query() {{
              return {{ rows: [{{
                database_name: 'postgres',
                database_role: 'postgres',
                migration_matches: true,
                frozen_release_matches: false
              }}] }};
            }}
          }};
          try {{
            await proveApprovedLiveTarget(client);
            process.exit(3);
          }} catch (error) {{
            process.stderr.write(error.message);
          }}
        """
        result = self.run_node(source)
        self.assertEqual(0, result.returncode)
        self.assertIn("approved URC project", result.stderr)

    def test_each_sql_client_repeats_live_proof_immediately_before_caller_sql(self) -> None:
        for relative_path in ("pipeline/sql_query.mjs", "pipeline/sql_exec.mjs"):
            source = (ROOT / relative_path).read_text(encoding="utf-8")
            self.assertEqual(2, source.count("proveApprovedLiveTarget(client)"), relative_path)
            final_proof = source.rfind("await proveApprovedLiveTarget(client);")
            caller_sql = source.rfind('await client.query(fs.readFileSync(sqlPath, "utf8"))')
            self.assertGreater(final_proof, -1, relative_path)
            self.assertGreater(caller_sql, final_proof, relative_path)
            between = source[final_proof:caller_sql]
            self.assertEqual(0, between.count("client.query("), relative_path)

    def test_read_only_client_applies_its_validated_timeout_inside_postgres(self) -> None:
        source = (ROOT / "pipeline/sql_query.mjs").read_text(encoding="utf-8")
        self.assertIn("const queryTimeoutMillis = (() => {", source)
        self.assertIn("PIPELINE_QUERY_TIMEOUT_MS must be a positive integer", source)
        self.assertIn("query_timeout: queryTimeoutMillis", source)
        self.assertIn(
            "await client.query(`set local statement_timeout = ${queryTimeoutMillis}`);",
            source,
        )

    def test_read_only_client_rejects_a_timeout_above_node_timer_range(self) -> None:
        environment = os.environ.copy()
        environment["PIPELINE_QUERY_TIMEOUT_MS"] = "2147483648"
        result = subprocess.run(
            ["node", "pipeline/sql_query.mjs", "/tmp/not-read.sql"],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(2, result.returncode)
        self.assertIn("no greater than 2147483647", result.stderr)


if __name__ == "__main__":
    unittest.main()
