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

test("web reader target proof accepts only the approved URC project reference", async () => {
  const { assertApprovedWebReaderConnectionString } = await loadTargetModule();
  const proof = assertApprovedWebReaderConnectionString(
    "postgresql://postgres.eukkvswaxweenovqqgzr:ignored@aws-0-eu-west-3.pooler.supabase.com:5432/postgres",
  );
  assert.equal(proof.projectRef, "eukkvswaxweenovqqgzr");
  assert.throws(
    () => assertApprovedWebReaderConnectionString(
      "postgresql://postgres.aaaaaaaaaaaaaaaaaaaa:ignored@aws-0-eu-west-3.pooler.supabase.com:5432/postgres",
    ),
    /approved URC project/,
  );
});

test("reporting queries obtain database attestation before each reader SQL statement", async () => {
  const reporting = await readFile(new URL("../lib/reporting.ts", import.meta.url), "utf8");
  assert.match(reporting, /approvedWebReaderQuery/);
  assert.match(reporting, /reporting\.approved_dashboard_reader_target_v1/);
  assert.match(reporting, /target_attested/);
  assert.equal((reporting.match(/pool\.query/g) ?? []).length, 2);
  assert.match(reporting, /assertApprovedWebReaderConfiguration\(\);[\s\S]*pool\.query\([\s\S]*assertApprovedWebReaderConfiguration\(\);[\s\S]*return pool\.query/);
});
