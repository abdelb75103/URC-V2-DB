import fs from "node:fs";
import path from "node:path";
import { Client } from "pg";

// LEGACY / NOT FOR PIPELINE USE. This script predates the accepted export
// audit contract and is retained only to explain a historical local artifact.
// See tools/legacy/README.md and docs/PIPELINE_RUNBOOK.md.

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

const columns = [
  "PlayerID",
  "DOB",
  "Age",
  "Weight",
  "Height",
  "Gender",
  "InjuryID",
  "Received At Club",
  "Received/Injured In Team",
  "Problem type",
  "Date Injured",
  "Injury Status",
  "Fit for selection",
  "Training only",
  "Treatment/Rehab",
  "Fit For Selection Date",
  "Confirmed Return Date",
  "Days Injured",
  "Games Missed",
  "Training Days Missed",
  "Occasion category",
  "Body Part",
  "Orchard Code",
  "Illness Code",
  "Description",
  "Injury Tissue Type/s",
  "Side",
  "Injury Grade",
  "BAMIC Grade",
  "Nature of onset",
  "Recurrence",
  "Recurrence Stage",
  "Recurrence InjuryID",
  "Is Contact",
  "Mechanism of Injury",
  "Mechanism Notes",
  "Injury Surface Type",
  "Injury Surface Condition",
  "Injury Ambient Condition",
  "Injury Training Type",
  "Match Type",
  "Occasion",
  "Received At Position",
  "Match status",
  "Equipment",
  "Injury Immediate Action",
  "Required Surgery",
  "TimeLoss vs Medical Attention",
  "is_injury_closed"
];

const bodyLabels = {
  abdomen: "Abdomen",
  ankle: "Ankle",
  chest: "Chest",
  elbow: "Elbow",
  forearm: "Forearm",
  foot: "Foot",
  hand: "Hand",
  head: "Head",
  hip_groin: "Hip/Groin",
  knee: "Knee",
  lower_leg: "Lower leg",
  lumbosacral: "Lumbosacral",
  multiple: "Multiple",
  neck: "Neck",
  shoulder: "Shoulder",
  thigh: "Thigh",
  thoracic_spine: "Thoracic spine",
  unspecified: "Unspecified",
  upper_arm: "Upper arm",
  wrist: "Wrist",
  unknown: "Unspecified"
};

const severityLabels = {
  zero_days_medical_attention_only: "Medical Attention",
  one_day: "1 day",
  two_to_three_days: "2-3 days",
  four_to_seven_days: "4-7 days",
  eight_to_twenty_eight_days: "8-28 days",
  greater_than_twenty_eight_days: ">28 days",
  unknown_or_censored: "Unknown"
};

const injuryTypeLabels = {
  arthritis: "Arthritis",
  avascular_necrosis: "Avascular necrosis",
  bone_contusion: "Bone contusion",
  bone_stress_injury: "Bone stress injury",
  brain_spinal_cord_injury: "Brain/spinal cord injury",
  bursitis: "Bursitis",
  cartilage_injury: "Cartilage injury",
  chronic_instability: "Chronic instability",
  contusion_superficial: "Contusion (superficial)",
  brain_spinal_cord_injury: "Brain/spinal cord injury",
  fracture: "Fracture",
  internal_organ_trauma: "Internal organs (organ trauma)",
  joint_sprain: "Joint sprain",
  laceration: "Laceration",
  muscle_injury: "Muscle injury",
  nonspecific: "Nonspecific",
  peripheral_nerve_injury: "Peripheral nerve injury",
  physis_injury: "Physis injury",
  synovitis_capsulitis: "Synovitis/capsulitis",
  tendon_rupture: "Tendon rupture",
  tendinopathy: "Tendinopathy",
  unknown: "Nonspecific"
};

function csvEscape(value) {
  if (value === null || value === undefined) return "";
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function formatDate(isoDate) {
  if (!isoDate) return "";
  const [year, month, day] = String(isoDate).split("-");
  return `${day}/${month}/${year}`;
}

function activityLabel(value) {
  if (value === "urc_match") return "match";
  if (value === "training") return "training";
  return "unknown";
}

function matchTypeLabel(value) {
  if (value === "urc_match") return "URC";
  if (value === "training") return "training";
  return "unknown";
}

function contactLabel(value) {
  if (value === "contact") return "Contact";
  if (value === "non_contact") return "Non-Contact";
  return "Unknown";
}

function recurrenceLabel(value) {
  if (value === "first_episode") return "First episode";
  if (value === "recurrence") return "Recurrence";
  return "Unknown";
}

function statusLabel(value) {
  if (value === true) return "Closed";
  if (value === false) return "Open/Ongoing";
  return "Unknown";
}

function problemTypeLabel(value) {
  if (value === "injury") return "Injury";
  if (value === "illness") return "Illness";
  return "Unknown";
}

function timeLossLabel(days) {
  if (days === null || days === undefined || days === "") return "Unknown";
  return Number(days) > 0 ? "Time Loss" : "Medical Attention";
}

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
        rv.record_state,
        sr.source_values
      from processing.record_versions rv
      join ingestion.source_rows sr on sr.id = rv.source_row_id
      where sr.source_file_id in (select id from target_file)
      order by rv.source_row_id, rv.version_number desc
    )
    select source_values, record_state
    from latest_versions
    order by (record_state #>> '{source_locator,standardised_row_number}')::int;
  `;
  const result = await client.query(sql, [args.team, args.season, args["file-sha256"]]);
  const rows = result.rows.map(({ source_values: sourceValues, record_state: state }) => {
    const row = Object.fromEntries(columns.map((column) => [column, sourceValues[column] ?? ""]));
    const returnDate = state.is_closed === true ? formatDate(state.derived_return_date) : "";
    row["Problem type"] = problemTypeLabel(state.problem_type);
    row["Injury Status"] = statusLabel(state.is_closed);
    row["Fit for selection"] = state.is_closed === false ? "No" : "Yes";
    row["Fit For Selection Date"] = "";
    row["Confirmed Return Date"] = returnDate;
    row["Occasion category"] = activityLabel(state.activity_context);
    row["Match Type"] = matchTypeLabel(state.activity_context);
    row["Body Part"] = bodyLabels[state.body_location] ?? "Unknown";
    row["Injury Tissue Type/s"] = injuryTypeLabels[state.injury_type] ?? "Unknown";
    row["Injury Grade"] = severityLabels[state.severity_category] ?? "Unknown";
    row["Recurrence"] = recurrenceLabel(state.recurrence_status);
    row["Is Contact"] = contactLabel(state.contact_context);
    row["TimeLoss vs Medical Attention"] = timeLossLabel(state.days_injured_source);
    return row;
  });
  const csv = [
    columns.join(","),
    ...rows.map((row) => columns.map((column) => csvEscape(row[column])).join(","))
  ].join("\n") + "\n";
  await fs.promises.mkdir(path.dirname(args.output), { recursive: true });
  await fs.promises.writeFile(args.output, csv);
  console.log(JSON.stringify({ output: args.output, rows: result.rowCount, columns: columns.length }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
