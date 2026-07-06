import fs from "node:fs";
import { Client } from "pg";

const sqlPath = process.argv[2];
const paramsPath = process.argv[3];
if (!sqlPath) {
  console.error("SQL file path required");
  process.exit(2);
}

const client = new Client({
  connectionString: process.env.SUPABASE_DB_URL,
  connectionTimeoutMillis: 10000
});

try {
  await client.connect();
  await client.query("begin");
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
