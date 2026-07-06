import fs from "node:fs";
import { Client } from "pg";

const sqlPath = process.argv[2];
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
