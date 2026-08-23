import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import test from "node:test";
import ts from "typescript";

const require = createRequire(import.meta.url);

async function loadTargetModule() {
  const source = await readFile(new URL("../lib/reporting.ts", import.meta.url), "utf8");
  const pgUrl = pathToFileURL(require.resolve("pg")).href;
  const zodUrl = pathToFileURL(require.resolve("zod")).href;
  const executable = source
    .replace('import "server-only";\n', "")
    .replace('import { Pool } from "pg";', `import pg from "${pgUrl}";\nconst { Pool } = pg;`)
    .replace('import { z } from "zod";', `import { z } from "${zodUrl}";`);
  const javascript = ts.transpileModule(executable, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString("base64")}`);
}

test("web reader target proof accepts only the approved project and least-privilege role", async () => {
  const { assertApprovedWebReaderConnectionString } = await loadTargetModule();
  const proof = assertApprovedWebReaderConnectionString(
    "postgresql://web_reader.eukkvswaxweenovqqgzr:ignored@aws-0-eu-west-3.pooler.supabase.com:5432/postgres",
  );
  assert.equal(proof.projectRef, "eukkvswaxweenovqqgzr");
  assert.throws(
    () => assertApprovedWebReaderConnectionString(
      "postgresql://web_reader.aaaaaaaaaaaaaaaaaaaa:ignored@aws-0-eu-west-3.pooler.supabase.com:5432/postgres",
    ),
    /approved URC project/,
  );
  assert.throws(
    () => assertApprovedWebReaderConnectionString(
      "postgresql://postgres.eukkvswaxweenovqqgzr:ignored@aws-0-eu-west-3.pooler.supabase.com:5432/postgres",
    ),
    /approved URC project/,
  );
});

test("reporting queries obtain database attestation before each reader SQL statement", async () => {
  const reporting = await readFile(new URL("../lib/reporting.ts", import.meta.url), "utf8");
  assert.match(reporting, /approvedWebReaderQuery/);
  assert.match(reporting, /reporting\.approved_dashboard_reader_target_v2/);
  assert.match(reporting, /target_attested/);
  assert.doesNotMatch(reporting, /pool\.query/);
  assert.match(reporting, /pool\.connect\(\)[\s\S]*begin transaction read only[\s\S]*approved_dashboard_reader_target_v2[\s\S]*client\.query<any, any\[]>\(sql, values\)/);
});

test("attestation and dashboard SQL run on one read-only database session", async () => {
  const priorUrl = process.env.WEB_READER_DB_URL;
  process.env.WEB_READER_DB_URL =
    "postgresql://web_reader.eukkvswaxweenovqqgzr:fixture@aws-0-eu-west-3.pooler.supabase.com:5432/postgres";
  const statements = [];
  let released = false;
  globalThis.__urcWebReaderPool = {
    query: async () => {
      throw new Error("pool-level query must not run an attested dashboard read");
    },
    connect: async () => ({
      query: async (sql) => {
        statements.push(sql.trim());
        if (sql.includes("approved_dashboard_reader_target_v2")) {
          return { rows: [{ target_attested: true }] };
        }
        return { rows: [] };
      },
      release: () => { released = true; },
    }),
  };

  try {
    const { getTeamDashboard } = await loadTargetModule();
    assert.equal(await getTeamDashboard("fixture-team", "2025-26"), undefined);
    assert.match(statements[0], /^begin transaction read only$/i);
    assert.match(statements[1], /approved_dashboard_reader_target_v2/);
    assert.match(statements[2], /latest_team_dashboard_v6/);
    assert.match(statements[3], /^commit$/i);
    assert.equal(released, true);
  } finally {
    globalThis.__urcWebReaderPool = undefined;
    if (priorUrl === undefined) delete process.env.WEB_READER_DB_URL;
    else process.env.WEB_READER_DB_URL = priorUrl;
  }
});
