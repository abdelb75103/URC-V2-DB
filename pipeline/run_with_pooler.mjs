import fs from "node:fs";
import { spawnSync } from "node:child_process";

const command = process.argv.slice(2);
if (command.length === 0) {
  console.error("command required");
  process.exit(2);
}
const approvedNodeEntrypoints = new Set([
  "pipeline/sql_query.mjs",
  "pipeline/sql_exec.mjs",
]);
const approved =
  (command[0] === "node" && approvedNodeEntrypoints.has(command[1])) ||
  (command[0] === "python3" &&
    command[1] === "-m" &&
    command[2] === "pipeline");
if (!approved) {
  console.error("command is not an approved database pipeline entrypoint");
  process.exit(2);
}

const values = {};
for (const rawLine of fs.readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const line = rawLine.trim();
  if (!line || line.startsWith("#")) continue;
  const separator = line.indexOf("=");
  if (separator < 1) continue;
  const key = line.slice(0, separator).trim();
  let value = line.slice(separator + 1).trim();
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    value = value.slice(1, -1);
  }
  values[key] = value;
}

const pooler = values.SUPABASE_DB_URL_POOLER;
if (!pooler) {
  console.error("SUPABASE_DB_URL_POOLER is missing from .env.local");
  process.exit(2);
}

const result = spawnSync(command[0], command.slice(1), {
  cwd: process.cwd(),
  env: { ...process.env, SUPABASE_DB_URL: pooler },
  stdio: "inherit",
});
if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status ?? 1);
