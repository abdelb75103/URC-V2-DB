from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "pipeline/run_with_pooler.mjs"
FAKE_SECRET = "postgresql://user:never-print-this@example.invalid/postgres"


class RunWithPoolerTests(unittest.TestCase):
    def run_wrapper(
        self, script: str, *args: str
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            cwd = Path(directory)
            (cwd / ".env.local").write_text(
                f"SUPABASE_DB_URL_POOLER={FAKE_SECRET}\n",
                encoding="utf-8",
            )
            pipeline = cwd / "pipeline"
            pipeline.mkdir()
            (pipeline / "sql_query.mjs").write_text(script, encoding="utf-8")
            result = subprocess.run(
                ["node", str(WRAPPER), "node", "pipeline/sql_query.mjs", *args],
                cwd=cwd,
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertNotIn("never-print-this", result.stdout)
        self.assertNotIn("never-print-this", result.stderr)
        return result

    def test_approved_entrypoint_receives_connection_without_emitting_it(self) -> None:
        result = self.run_wrapper(
            "if (!process.env.SUPABASE_DB_URL) process.exit(3);\n"
            'process.stdout.write("ok");\n'
        )
        self.assertEqual(0, result.returncode)
        self.assertEqual("ok", result.stdout)

    def test_failed_child_does_not_emit_connection(self) -> None:
        result = self.run_wrapper("process.exit(7);\n")
        self.assertEqual(7, result.returncode)

    def test_arbitrary_command_is_rejected_before_env_is_loaded(self) -> None:
        result = subprocess.run(
            ["node", str(WRAPPER), "node", "-e", "console.log(process.env)"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(2, result.returncode)
        self.assertIn("not an approved", result.stderr)
        self.assertNotIn("SUPABASE_DB_URL_POOLER", result.stdout)
