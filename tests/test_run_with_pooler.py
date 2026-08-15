from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "pipeline/run_with_pooler.mjs"
FAKE_SECRET = (
    "postgresql://postgres.eukkvswaxweenovqqgzr:never-print-this@"
    "aws-0-eu-west-3.pooler.supabase.com:5432/postgres"
)
WRONG_TARGET_SECRET = (
    "postgresql://postgres.aaaaaaaaaaaaaaaaaaaa:never-print-this@"
    "aws-0-eu-west-3.pooler.supabase.com:5432/postgres"
)


class RunWithPoolerTests(unittest.TestCase):
    def run_wrapper(
        self,
        script: str,
        *args: str,
        entrypoint: str = "sql_query.mjs",
        command: list[str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            cwd = Path(directory)
            (cwd / ".env.local").write_text(
                f"SUPABASE_DB_URL_POOLER={FAKE_SECRET}\n",
                encoding="utf-8",
            )
            pipeline = cwd / "pipeline"
            pipeline.mkdir()
            (pipeline / entrypoint).write_text(script, encoding="utf-8")
            child = command or ["node", f"pipeline/{entrypoint}", *args]
            result = subprocess.run(
                ["node", str(WRAPPER), *child],
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

    def test_sql_exec_entrypoint_is_approved_without_emitting_connection(self) -> None:
        result = self.run_wrapper(
            "if (!process.env.SUPABASE_DB_URL) process.exit(3);\n"
            'process.stdout.write("exec-ok");\n',
            entrypoint="sql_exec.mjs",
        )
        self.assertEqual(0, result.returncode)
        self.assertEqual("exec-ok", result.stdout)

    def test_python_pipeline_entrypoint_is_approved_without_emitting_connection(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            cwd = Path(directory)
            (cwd / ".env.local").write_text(
                f"SUPABASE_DB_URL_POOLER={FAKE_SECRET}\n",
                encoding="utf-8",
            )
            package = cwd / "pipeline"
            package.mkdir()
            (package / "__main__.py").write_text(
                "import os\n"
                "raise SystemExit(0 if os.environ.get('SUPABASE_DB_URL') else 3)\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                ["node", str(WRAPPER), "python3", "-m", "pipeline"],
                cwd=cwd,
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(0, result.returncode)
        self.assertNotIn("never-print-this", result.stdout)
        self.assertNotIn("never-print-this", result.stderr)

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

    def test_near_miss_entrypoints_are_rejected(self) -> None:
        for command in (
            ["node", "pipeline/sql_query.mjs.bak"],
            ["node", "./pipeline/sql_query.mjs"],
            ["python3", "-m", "pipeline.other"],
            ["python3", "pipeline"],
        ):
            result = subprocess.run(
                ["node", str(WRAPPER), *command],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(2, result.returncode, command)
            self.assertIn("not an approved", result.stderr)

    def test_wrong_project_reference_is_rejected_before_child_execution(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            cwd = Path(directory)
            (cwd / ".env.local").write_text(
                f"SUPABASE_DB_URL_POOLER={WRONG_TARGET_SECRET}\n",
                encoding="utf-8",
            )
            pipeline = cwd / "pipeline"
            pipeline.mkdir()
            (pipeline / "sql_query.mjs").write_text(
                'process.stdout.write("child-ran");\n',
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    "node",
                    str(WRAPPER),
                    "node",
                    "pipeline/sql_query.mjs",
                ],
                cwd=cwd,
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(2, result.returncode)
        self.assertNotIn("child-ran", result.stdout)
        self.assertIn("approved URC project", result.stderr)
        self.assertNotIn("never-print-this", result.stdout)
        self.assertNotIn("never-print-this", result.stderr)
