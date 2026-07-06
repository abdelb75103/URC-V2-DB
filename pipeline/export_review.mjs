import fs from "node:fs";
import path from "node:path";
import { Client } from "pg";

const args = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, "").split("=");
    return [key, rest.join("=")];
  })
);

for (const key of ["team", "season", "file-sha256", "output"]) {
  if (!args[key]) {
    console.error(`missing --${key}`);
    process.exit(2);
  }
}

const client = new Client({
  connectionString: process.env.SUPABASE_DB_URL,
  connectionTimeoutMillis: 10000
});

function csvEscape(value) {
  if (value === null || value === undefined) return "";
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

const columns = [
  "review_reason",
  "review_group_hash",
  "standardised_row_number",
  "source_row_number",
  "source_file_sha256",
  "player_uid",
  "injury_uid",
  "date_injured",
  "days_injured_source",
  "derived_return_date",
  "body_part",
  "orchard_code",
  "description",
  "injury_tissue_type",
  "side",
  "nature_of_onset",
  "occasion_category",
  "match_type"
];

try {
  await client.connect();
  const sql = `
    with target_file as (
      select id
      from ingestion.source_files
      where team = $1 and season = $2 and file_sha256 = $3
    ),
    latest_versions as (
      select distinct on (rv.source_row_id)
        rv.source_row_id,
        rv.record_state,
        sr.source_values
      from processing.record_versions rv
      join ingestion.source_rows sr on sr.id = rv.source_row_id
      where sr.source_file_id in (select id from target_file)
      order by rv.source_row_id, rv.version_number desc
    ),
    flagged as (
      select
        'candidate_duplicate_injury_signature' as review_reason,
        'key_' || left(encode(digest(
          'injury_signature' || chr(31) ||
          (source_values->>'PlayerID') || chr(31) ||
          (source_values->>'Date Injured') || chr(31) ||
          (source_values->>'Body Part') || chr(31) ||
          (source_values->>'Orchard Code') || chr(31) ||
          (source_values->>'Side') || chr(31) ||
          (source_values->>'Description') || chr(31) ||
          (source_values->>'Nature of onset'),
          'sha256'
        ), 'hex'), 24) as review_group_hash,
        record_state,
        source_values
      from latest_versions
      where (record_state #>> '{duplicate_flags,candidate_duplicate_injury_signature}')::boolean
    )
    select
      review_reason,
      review_group_hash,
      record_state #>> '{source_locator,standardised_row_number}' as standardised_row_number,
      record_state #>> '{source_locator,source_row_number}' as source_row_number,
      record_state #>> '{source_locator,source_file_sha256}' as source_file_sha256,
      record_state->>'player_uid' as player_uid,
      record_state->>'injury_uid' as injury_uid,
      record_state->>'date_injured' as date_injured,
      record_state->>'days_injured_source' as days_injured_source,
      record_state->>'derived_return_date' as derived_return_date,
      source_values->>'Body Part' as body_part,
      source_values->>'Orchard Code' as orchard_code,
      source_values->>'Description' as description,
      source_values->>'Injury Tissue Type/s' as injury_tissue_type,
      source_values->>'Side' as side,
      source_values->>'Nature of onset' as nature_of_onset,
      source_values->>'Occasion category' as occasion_category,
      source_values->>'Match Type' as match_type
    from flagged
    order by review_reason, review_group_hash, (record_state #>> '{source_locator,standardised_row_number}')::int;
  `;
  const result = await client.query(sql, [args.team, args.season, args["file-sha256"]]);
  await fs.promises.mkdir(path.dirname(args.output), { recursive: true });
  const csv = [
    columns.join(","),
    ...result.rows.map((row) => columns.map((column) => csvEscape(row[column])).join(","))
  ].join("\n") + "\n";
  await fs.promises.writeFile(args.output, csv);
  console.log(JSON.stringify({ output: args.output, rows: result.rowCount }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
