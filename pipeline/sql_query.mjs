import fs from "node:fs";
import { Client } from "pg";

// Read-only counterpart of sql_exec.mjs: runs exactly one query inside a
// read-only transaction and prints its rows as JSON to stdout. Used by
// pipeline commands (via query_sql() in pipeline/__main__.py) that need to
// read live data to decide what to do (idempotence checks, team_key
// resolution, reconciliation) before ever writing.

const sqlPath = process.argv[2];
const paramsPath = process.argv[3];
if (!sqlPath) {
  console.error("SQL file path required");
  process.exit(2);
}

// The Supavisor pooler can drop an over-long upstream query without the error
// ever reaching the client, which leaves node waiting on a connection that
// will never answer (observed 2026-07-24: 33 minutes, 0% CPU, nothing active
// server-side). Bound the wait so that failure mode surfaces as an error
// instead of a silent hang; raise PIPELINE_QUERY_TIMEOUT_MS for a genuinely
// long read.
const connectionTimeoutMillis = (() => {
  const raw = process.env.PIPELINE_CONNECTION_TIMEOUT_MS || "10000";
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    console.error("PIPELINE_CONNECTION_TIMEOUT_MS must be a positive integer");
    process.exit(2);
  }
  return parsed;
})();

const client = new Client({
  connectionString: process.env.SUPABASE_DB_URL,
  connectionTimeoutMillis,
  keepAlive: true,
  query_timeout: Number(process.env.PIPELINE_QUERY_TIMEOUT_MS || 900000)
});

try {
  await client.connect();
  // Postgres rejects CREATE (even for temp tables) inside a read-only
  // transaction, so the params table is a session-scoped temp table set up
  // before the transaction starts; the caller's query itself still runs
  // under `read only` enforcement and is always rolled back.
  if (paramsPath) {
    const params = JSON.parse(fs.readFileSync(paramsPath, "utf8"));
    await client.query("create temp table _pipeline_params (idx integer primary key, value jsonb)");
    await client.query(
      "insert into _pipeline_params select ordinality::int, value from jsonb_array_elements($1::jsonb) with ordinality",
      [JSON.stringify(params)]
    );
  }
  await client.query("begin transaction read only");
  const result = await client.query(fs.readFileSync(sqlPath, "utf8"));
  const rows = Array.isArray(result) ? result[result.length - 1].rows : result.rows;
  await client.query("rollback");
  process.stdout.write(JSON.stringify(rows));
} catch (error) {
  try {
    await client.query("rollback");
  } catch {}
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
