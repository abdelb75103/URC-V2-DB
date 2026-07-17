import { realpath } from "node:fs/promises";
import { basename, dirname, isAbsolute, relative, resolve } from "node:path";

function isWithin(candidate, parent) {
  const pathFromParent = relative(parent, candidate);
  return pathFromParent === ""
    || (!pathFromParent.startsWith("..") && !isAbsolute(pathFromParent));
}

async function resolveThroughExistingAncestor(path) {
  let ancestor = resolve(path);
  const missingSegments = [];
  while (true) {
    try {
      return resolve(await realpath(ancestor), ...missingSegments.reverse());
    } catch (error) {
      if (error?.code !== "ENOENT" && error?.code !== "ENOTDIR") throw error;
      const parent = dirname(ancestor);
      if (parent === ancestor) throw error;
      missingSegments.push(basename(ancestor));
      ancestor = parent;
    }
  }
}

export async function assertPrivatePreviewOutputPath(path, projectRoot, flag) {
  const candidate = resolve(path);
  const resolvedCandidate = await resolveThroughExistingAncestor(candidate);
  for (const lexicalPublicRoot of [resolve(projectRoot, "content"), resolve(projectRoot, "public")]) {
    const resolvedPublicRoot = await resolveThroughExistingAncestor(lexicalPublicRoot);
    if (isWithin(candidate, lexicalPublicRoot) || isWithin(resolvedCandidate, resolvedPublicRoot)) {
      throw new Error(`${flag} must not write under public payload directory ${lexicalPublicRoot}`);
    }
  }
}

export function expectedOriginClass(origin) {
  if (origin.startsWith("manual_adjudication:")) return "adjudicated";
  if (origin === "source_reported" || origin === "approved_mapping:source_reported") {
    return "source_reported";
  }
  if (origin.startsWith("inferred") || origin.includes("protocol_defined_inference")) {
    return "inferred";
  }
  if (origin.startsWith("mapped_from_")) return "mapped";
  return undefined;
}

export function validateOriginClassCounts(originClassCounts, unclassifiedOrigins = []) {
  const unclassifiedKeys = new Set(unclassifiedOrigins.map((row) =>
    `${row.scope_key}:${row.field}:${row.origin}`));
  for (const row of originClassCounts) {
    if (row.origin_class === "remaining_unknown") continue;
    const expected = expectedOriginClass(row.origin);
    if (expected && row.origin_class !== expected) {
      throw new Error(`${row.scope_key}: ${row.field} origin ${row.origin} must be ${expected}, not ${row.origin_class}`);
    }
    if (!expected) {
      const key = `${row.scope_key}:${row.field}:${row.origin}`;
      if (row.origin_class !== "inferred") {
        throw new Error(`${row.scope_key}: unclassified ${row.field} origin ${row.origin} must conservatively be inferred`);
      }
      if (!unclassifiedKeys.has(key)) {
        throw new Error(`${row.scope_key}: unclassified ${row.field} origin ${row.origin} is not visible in unclassified_origins`);
      }
    }
  }
  for (const row of unclassifiedOrigins) {
    if (expectedOriginClass(row.origin)) {
      throw new Error(`${row.scope_key}: recognized ${row.field} origin ${row.origin} must not be listed as unclassified`);
    }
  }
}

export function validateLegacyMultiMatchRefusal(candidates, reconciliation) {
  const refusedByTeam = new Map();
  for (const row of candidates) {
    if (row.field !== "diagnosis" || (row.legacy_pattern_match_count ?? 0) <= 1) continue;
    if (row.resulting_value !== "unknown") {
      throw new Error(`${row.id}: multi-match legacy diagnosis fallback did not remain Unknown`);
    }
    refusedByTeam.set(row.team_key, (refusedByTeam.get(row.team_key) ?? 0) + 1);
  }

  let leagueExpected = 0;
  for (const team of reconciliation.teams ?? []) {
    const expected = Number(team.diagnosis_legacy_multi_match_refused ?? 0);
    if (team.team_key === "urc") {
      leagueExpected = expected;
      continue;
    }
    const ledgered = refusedByTeam.get(team.team_key) ?? 0;
    if (ledgered !== expected) {
      throw new Error(`${team.team_key}: ${expected} legacy diagnosis multi-matches, ${ledgered} ledgered as Unknown`);
    }
  }

  const ledgeredLeagueTotal = [...refusedByTeam.values()].reduce((sum, count) => sum + count, 0);
  if (ledgeredLeagueTotal !== leagueExpected) {
    throw new Error(`urc: ${leagueExpected} legacy diagnosis multi-matches, ${ledgeredLeagueTotal} ledgered as Unknown`);
  }
}
