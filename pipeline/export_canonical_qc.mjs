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

async function groupedCount(fileHash, field) {
  const result = await client.query(
    `
      with target_file as (
        select id from ingestion.source_files
        where team = $1 and season = $2 and file_sha256 = $3
      ),
      latest_versions as (
        select distinct on (rv.source_row_id) rv.record_state
        from processing.record_versions rv
        join ingestion.source_rows sr on sr.id = rv.source_row_id
        where sr.source_file_id in (select id from target_file)
        order by rv.source_row_id, rv.version_number desc
      )
      select coalesce(record_state->>$4, '<null>') as value, count(*)::int as rows
      from latest_versions
      group by value
      order by rows desc, value;
    `,
    [args.team, args.season, fileHash, field]
  );
  return Object.fromEntries(result.rows.map((row) => [row.value, row.rows]));
}

try {
  await client.connect();
  const fileHash = args["file-sha256"];
  const summaryResult = await client.query(
    `
      with target_file as (
        select id from ingestion.source_files
        where team = $1 and season = $2 and file_sha256 = $3
      ),
      latest_versions as (
        select distinct on (rv.source_row_id) rv.record_state, rv.eligibility_status
        from processing.record_versions rv
        join ingestion.source_rows sr on sr.id = rv.source_row_id
        where sr.source_file_id in (select id from target_file)
        order by rv.source_row_id, rv.version_number desc
      )
      select jsonb_build_object(
        'latest_record_versions', count(*),
        'review_required', count(*) filter (where eligibility_status = 'review_required'),
        'included_pending_protocol', count(*) filter (where eligibility_status = 'included_pending_protocol'),
        'derived_return_date_records', count(*) filter (where record_state->>'derived_return_date' is not null),
        'controlled_body_location_inferences', count(*) filter (where record_state #>> '{field_origins,body_location}' like 'inferred_%'),
        'unknown_body_location_records', count(*) filter (where record_state->>'body_location' = 'unknown'),
        'unclosed_injury_records', count(*) filter (where record_state->>'is_closed' = 'false')
      ) as summary
      from latest_versions;
    `,
    [args.team, args.season, fileHash]
  );

  const report = {
    team: args.team,
    season: args.season,
    source_file_sha256: fileHash,
    summary: summaryResult.rows[0].summary,
    counts: {
      activity_context: await groupedCount(fileHash, "activity_context"),
      contact_context: await groupedCount(fileHash, "contact_context"),
      recurrence_status: await groupedCount(fileHash, "recurrence_status"),
      severity_category: await groupedCount(fileHash, "severity_category"),
      body_location: await groupedCount(fileHash, "body_location"),
      problem_type: await groupedCount(fileHash, "problem_type"),
      injury_type: await groupedCount(fileHash, "injury_type")
    }
  };

  await fs.promises.mkdir(path.dirname(args.output), { recursive: true });
  await fs.promises.writeFile(args.output, JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify({ output: args.output, rows: report.summary.latest_record_versions }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
