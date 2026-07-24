import fs from "node:fs";
import { Client } from "pg";

const sqlPath = process.argv[2];
const paramsPath = process.argv[3];
if (!sqlPath) {
  console.error("SQL file path required");
  process.exit(2);
}

// keepAlive lets a dead pooler connection surface as a socket error rather
// than an unbounded wait; see the note in sql_query.mjs. No query_timeout
// here: a write must not be abandoned client-side on a timer.
const client = new Client({
  connectionString: process.env.SUPABASE_DB_URL,
  connectionTimeoutMillis: 10000,
  keepAlive: true
});

// A non-numeric override would splice NaN into the SET and abort the write,
// and 0 would silently disable the statement timeout altogether for a live
// write. Both are refused before connecting.
const statementTimeoutMs = (() => {
  const raw = process.env.PIPELINE_STATEMENT_TIMEOUT_MS;
  if (raw === undefined || raw === "") return 900000;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    console.error(
      `PIPELINE_STATEMENT_TIMEOUT_MS must be a positive integer number of milliseconds, got ${JSON.stringify(raw)}`
    );
    process.exit(2);
  }
  return parsed;
})();

try {
  await client.connect();
  await client.query("begin");
  // The target's default statement_timeout is 2 minutes, which is shorter than
  // a legitimate promotion transaction: release-league re-derives the league
  // payload and all 16 team payloads twice for its inserts and twice more in
  // the validation triggers (about 70s each), and that re-derivation is what
  // proves the stored snapshot equals the analytical candidate. Raising the
  // bound for the transaction is the fix; weakening the equality check is not.
  await client.query(`set local statement_timeout = ${statementTimeoutMs}`);
  if (paramsPath) {
    const params = JSON.parse(fs.readFileSync(paramsPath, "utf8"));
    await client.query("create temp table _pipeline_params (idx integer primary key, value jsonb) on commit drop");
    await client.query(
      "insert into _pipeline_params select ordinality::int, value from jsonb_array_elements($1::jsonb) with ordinality",
      [JSON.stringify(params)]
    );
  }
  await client.query(fs.readFileSync(sqlPath, "utf8"));
  await client.query("commit");
} catch (error) {
  try {
    await client.query("rollback");
  } catch {}
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
