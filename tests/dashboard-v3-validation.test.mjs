import assert from "node:assert/strict";
import { mkdir, symlink } from "node:fs/promises";
import test from "node:test";
import { resolve } from "node:path";
import {
  assertPrivatePreviewOutputPath,
  expectedOriginClass,
  validateOriginClassCounts,
  validateLegacyMultiMatchRefusal,
} from "../tools/dashboard-v3-validation.mjs";

const projectRoot = resolve(new URL("../", import.meta.url).pathname);

test("preview outputs refuse public payload directories", async () => {
  await assert.rejects(
    assertPrivatePreviewOutputPath(resolve(projectRoot, "content/reporting/preview.json"), projectRoot, "--output"),
    /must not write under public payload directory/
  );
  await assert.rejects(
    assertPrivatePreviewOutputPath(resolve(projectRoot, "public/reconciliation.json"), projectRoot, "--reconciliation-output"),
    /must not write under public payload directory/
  );
  await assert.doesNotReject(
    assertPrivatePreviewOutputPath(resolve(projectRoot, "data/reporting/preview.json"), projectRoot, "--output")
  );
});

test("preview outputs refuse a symlinked parent redirected into public payloads", async () => {
  const privateFixtureRoot = resolve(projectRoot, "data/tmp");
  const redirect = resolve(privateFixtureRoot, "dashboard-v3-public-redirect-test");
  await mkdir(privateFixtureRoot, { recursive: true });
  try {
    await symlink(resolve(projectRoot, "content"), redirect, "dir");
  } catch (error) {
    if (error?.code !== "EEXIST") throw error;
  }
  await assert.rejects(
    assertPrivatePreviewOutputPath(resolve(redirect, "blocked-preview.json"), projectRoot, "--output"),
    /must not write under public payload directory/
  );
});

test("origin strings enforce semantic provenance classes", () => {
  assert.equal(expectedOriginClass("approved_mapping:source_reported"), "source_reported");
  assert.equal(expectedOriginClass("manual_adjudication:reviewed"), "adjudicated");
  assert.equal(expectedOriginClass("inferred_from_evidence"), "inferred");
  assert.equal(expectedOriginClass("approved_mapping:protocol_defined_inference"), "inferred");
  assert.equal(expectedOriginClass("mapped_from_codebook"), "mapped");

  const uncertain = {
    scope_key: "example",
    field: "contact_context",
    origin: "approved_mapping:deterministic_derivation",
    origin_class: "inferred",
    count: 3,
  };
  const unclassified = [{ ...uncertain, conservative_class: "inferred" }];
  assert.doesNotThrow(() => validateOriginClassCounts([uncertain], unclassified));
  assert.throws(
    () => validateOriginClassCounts([{ ...uncertain, origin_class: "mapped" }], unclassified),
    /must conservatively be inferred/
  );
  assert.throws(
    () => validateOriginClassCounts([uncertain], []),
    /is not visible in unclassified_origins/
  );
  assert.throws(
    () => validateOriginClassCounts([{ ...uncertain, origin: "inferred_from_evidence", origin_class: "mapped" }]),
    /must be inferred, not mapped/
  );
});

test("legacy diagnosis multi-matches must remain Unknown and be ledgered", () => {
  const reconciliation = {
    teams: [
      { team_key: "example", diagnosis_legacy_multi_match_refused: 1 },
      { team_key: "urc", diagnosis_legacy_multi_match_refused: 1 },
    ],
  };
  const refused = [{
    id: "row-1",
    team_key: "example",
    field: "diagnosis",
    legacy_pattern_match_count: 2,
    resulting_value: "unknown",
  }];

  assert.doesNotThrow(() => validateLegacyMultiMatchRefusal(refused, reconciliation));
  assert.throws(
    () => validateLegacyMultiMatchRefusal([{ ...refused[0], resulting_value: "concussion" }], reconciliation),
    /did not remain Unknown/
  );
  assert.throws(
    () => validateLegacyMultiMatchRefusal([], reconciliation),
    /multi-matches, 0 ledgered as Unknown/
  );
});
