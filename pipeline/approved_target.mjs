export const APPROVED_URC_PROJECT_REF = "eukkvswaxweenovqqgzr";

export function assertApprovedConnectionString(connectionString) {
  let url;
  try {
    url = new URL(connectionString);
  } catch {
    throw new Error("database URL is invalid; approved URC project proof failed");
  }

  if (!new Set(["postgres:", "postgresql:"]).has(url.protocol)) {
    throw new Error("database URL scheme is not PostgreSQL; approved URC project proof failed");
  }
  if (url.pathname.replace(/^\//, "") !== "postgres") {
    throw new Error("database name is not postgres; approved URC project proof failed");
  }

  const directMatch = url.hostname.match(/^db\.([a-z0-9]{20})\.supabase\.co$/);
  const poolerMatch = url.username.match(/^postgres\.([a-z0-9]{20})$/);
  const projectRef = directMatch?.[1] ?? poolerMatch?.[1];
  const approvedHost = directMatch
    ? true
    : url.hostname.endsWith(".pooler.supabase.com");
  if (!approvedHost || projectRef !== APPROVED_URC_PROJECT_REF) {
    throw new Error("database URL does not resolve to the approved URC project");
  }

  return {
    projectRef,
    hostname: url.hostname,
    database: "postgres",
  };
}

const LIVE_IDENTITY_SQL = `
select
  current_database() as database_name,
  current_user as database_role,
  exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260803163430'
      and migration.name = 'dynamic_row_correction_batch_v7_hardening'
      and migration.statements = array[
        'migration_sha256=859e18440317494eb3936fd80c136a8b8fb2e7b2604141bcf58048aeaf604365'
      ]
  ) as migration_matches,
  exists (
    select 1
    from reporting.league_release_context_v2 context
    join reporting.aggregate_releases release
      on release.id = context.release_id
    join reporting.league_release_payloads_v2 payload
      on payload.release_id = context.release_id
    where context.release_id = '76ac684a-dc60-4b12-ab78-0a502d284555'::uuid
      and context.season = '2024-25'
      and release.release_label = 'urc-2024-25-v5-4ae722941285-a1'
      and payload.payload_sha256 = '2f4bb3cbe77e1ea1608cf8442419c2d6e11333473ce73d10559532061382fa53'
      and exists (
        select 1
        from reporting.aggregate_releases correction_release
        where correction_release.release_label = 'urc-2024-25-correction-r1122-20260729-a1'
          and correction_release.status = 'approved'
      )
  ) as frozen_release_matches
`;

export async function proveApprovedLiveTarget(client) {
  const result = await client.query(LIVE_IDENTITY_SQL);
  const row = result?.rows?.[0];
  if (
    result?.rows?.length !== 1 ||
    row.database_name !== "postgres" ||
    row.migration_matches !== true ||
    row.frozen_release_matches !== true
  ) {
    throw new Error("live database identity does not match the approved URC project");
  }
  return {
    projectRef: APPROVED_URC_PROJECT_REF,
    database: row.database_name,
    role: row.database_role,
    evidence: "registered-migration+frozen-release",
  };
}
