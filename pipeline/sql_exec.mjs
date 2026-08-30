import fs from "node:fs";
import { createHash } from "node:crypto";
import { Client } from "pg";
import {
  assertApprovedConnectionString,
  proveApprovedLiveTarget,
} from "./approved_target.mjs";

const sqlPath = process.argv[2];
const paramsPath = process.argv[3];
if (!sqlPath) {
  console.error("SQL file path required");
  process.exit(2);
}

const expectedParamsSha256 = (() => {
  const value = (process.env.PIPELINE_PARAMS_SHA256 || "").trim().toLowerCase();
  if (!value) return "";
  if (!/^[0-9a-f]{64}$/.test(value)) {
    console.error("PIPELINE_PARAMS_SHA256 must be a lowercase SHA-256 digest");
    process.exit(2);
  }
  if (!paramsPath) {
    console.error("PIPELINE_PARAMS_SHA256 requires a params file");
    process.exit(2);
  }
  return value;
})();

let params;
let paramsSha256 = "";
if (paramsPath) {
  try {
    const paramsBytes = fs.readFileSync(paramsPath);
    paramsSha256 = createHash("sha256").update(paramsBytes).digest("hex");
    if (expectedParamsSha256 && paramsSha256 !== expectedParamsSha256) {
      console.error(
        `params SHA-256 mismatch: expected ${expectedParamsSha256}, got ${paramsSha256}`
      );
      process.exit(2);
    }
    params = JSON.parse(paramsBytes.toString("utf8"));
  } catch (error) {
    console.error(`failed to read params file: ${error.message}`);
    process.exit(2);
  }
}

// keepAlive lets a dead pooler connection surface as a socket error rather
// than an unbounded wait; see the note in sql_query.mjs. No query_timeout
// here: a write must not be abandoned client-side on a timer.
const connectionTimeoutMillis = (() => {
  const raw = process.env.PIPELINE_CONNECTION_TIMEOUT_MS || "10000";
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    console.error("PIPELINE_CONNECTION_TIMEOUT_MS must be a positive integer");
    process.exit(2);
  }
  return parsed;
})();

const connectionString = process.env.SUPABASE_DB_URL;
try {
  assertApprovedConnectionString(connectionString);
} catch (error) {
  console.error(error.message);
  process.exit(2);
}

const client = new Client({
  connectionString,
  connectionTimeoutMillis,
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

// Multi-statement snapshot builds must see one database state throughout the
// transaction. Keep the default unchanged and accept one fixed, non-injectable
// override for those migrations only.
const transactionIsolation = (() => {
  const raw = process.env.PIPELINE_TRANSACTION_ISOLATION || "";
  if (raw === "") return "";
  if (raw === "repeatable_read") return "repeatable read";
  console.error(
    "PIPELINE_TRANSACTION_ISOLATION must be empty or repeatable_read"
  );
  process.exit(2);
})();

try {
  await client.connect();
  const proof = await proveApprovedLiveTarget(client);
  console.error(
    `URC target proof passed: project_ref=${proof.projectRef} database=${proof.database} evidence=${proof.evidence}`
  );
  await client.query("begin");
  if (transactionIsolation) {
    await client.query(
      `set transaction isolation level ${transactionIsolation}`
    );
  }
  // The target's default statement_timeout is 2 minutes, which is shorter than
  // a legitimate promotion transaction: release-league re-derives the league
  // payload and all 16 team payloads twice for its inserts and twice more in
  // the validation triggers (about 70s each), and that re-derivation is what
  // proves the stored snapshot equals the analytical candidate. Raising the
  // bound for the transaction is the fix; weakening the equality check is not.
  await client.query(`set local statement_timeout = ${statementTimeoutMs}`);
  if (paramsPath) {
    await client.query("create temp table _pipeline_params (idx integer primary key, value jsonb) on commit drop");
    await client.query("create temp table _pipeline_params_attestation (payload_sha256 text not null) on commit drop");
    await client.query(
      "insert into _pipeline_params select ordinality::int, value from jsonb_array_elements($1::jsonb) with ordinality",
      [JSON.stringify(params)]
    );
    await client.query(
      "insert into _pipeline_params_attestation (payload_sha256) values ($1)",
      [paramsSha256]
    );
  }
  await proveApprovedLiveTarget(client);
  await client.query(fs.readFileSync(sqlPath, "utf8"));
  await client.query("commit");
} catch (error) {
  try {
    await client.query("rollback");
  } catch {}
  console.error(error.message);
  if (error.position) console.error(`SQL error position: ${error.position}`);
  if (error.where) console.error(`SQL error context: ${error.where}`);
  process.exitCode = 1;
} finally {
  await client.end();
}
