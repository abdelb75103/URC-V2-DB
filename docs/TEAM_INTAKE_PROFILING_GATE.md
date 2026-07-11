# Team Intake Profiling Gate

Status: mandatory pre-ingest gate for every new team and season.

## Purpose

Each team can use different schemas, labels, units, date conventions, exposure grain, clinical category lists, and supporting fields. Before any live ingestion or team-specific implementation, profile the supplied pseudonymised files and decide how their source evidence maps into the frozen V2 canonical model.

The goal is maximum **defensible** completeness while preserving comparability. Do not fill a canonical field merely because another team used a similar label or because a value can be guessed. A populated canonical value must be source-reported, deterministically derived, supported by an approved team-specific mapping/inference rule, or manually adjudicated. Otherwise retain the source value and use `Unknown`.

## Boundary and outputs

Profiling is local and read-only. It may inspect the supplied pseudonymised injury and exposure files, their codebooks/mapping files, manifests, and secure source-locator metadata. It must not ingest, process, build curated data, or write to the live database.

Create the team-specific evidence under the Git-ignored team intake directory:

- `data/intake/<season>/<team_key>/team_intake_profile.md`
- `data/intake/<season>/<team_key>/team_intake_profile.json`
- a versioned source-to-canonical mapping file when mappings are required

The profile must record the input checksums, reviewer, review timestamp, profile/mapping version, and one of these decisions:

- `compatible`: the existing pipeline and mappings cover the intake without implementation changes.
- `adapter_required`: source-format normalization is needed, but the frozen canonical schema, controlled categories, cohort, and `_v1` metrics do not change.
- `adjudication_required`: one or more ambiguous mappings or inference rules need a recorded human decision before processing.
- `protocol_incompatible`: the intake would require a new analytical definition, controlled bucket, eligibility rule, threshold, or denominator; stop and follow the versioned-rule-change process.

Abdel must approve the profile decision and mapping version before `ingest` or any team-specific implementation begins.

Before ingestion, add an `intake_profile` object to the supplied intake manifest containing:

- `team` and `season`, matching the intended ingest target;
- `profile_path`, `profile_sha256`, and `profile_version`;
- `decision`;
- `mapping_path`, `mapping_sha256`, and `mapping_version`, or explicit nulls when no mapping file is required;
- `ai_review_status`, `ai_reviewed_by`, and `ai_reviewed_at`;
- `approved_by` and `approved_at`;
- `unresolved_adjudication_ids`, which must be an empty list before ingestion;
- `approved_input_sha256s`, containing the injury/exposure input checksums to which the approval applies.

The JSON profile is the checksummed approval envelope and must contain the same team, season, profile/mapping versions and checksums, decision, AI-review fields, approval fields, unresolved-adjudication list, and approved input checksums recorded in the manifest. `ingest --manifest` is required and validates that envelope before loading rows or constructing SQL. It fails closed unless the profile team/season matches the ingest target, the decision is `compatible` or `adapter_required`, the AI review status is `completed`, the recorded approver is `Abdel Babiker`, review/approval timestamps are ordered timezone-aware ISO values no later than the current time (allowing five minutes of clock skew), no adjudications remain unresolved, the current input checksum is approved, and the profile/mapping files exist with matching checksums.

For `adapter_required`, the mapping file must be JSON containing a matching `mapping_version` and a non-empty `mappings` list. Every mapping object requires nonblank `canonical_field` and `canonical_value`, a non-empty `source_evidence` object of source-field/value strings, and an `evidence_class` of `source_reported`, `deterministic_derivation`, `protocol_defined_inference`, or `manual_adjudication`. If any approved input, profile, mapping, or approval field changes, the checksummed envelope no longer matches and ingestion is blocked until the profile gate is rerun and re-approved.

## Required profile

### 1. File and provenance inventory

Record every supplied file, sheet/table, checksum, row count, preparer, preparation timestamp, codebook/mapping version, secure original-file locator/checksum where available, pseudonymisation status, player identifier field, and carried source-row/cell locators. Reconcile row counts between the retained source evidence and canonical intake.

### 2. Reporting structure

Record separately for injury and exposure data:

- exact source columns, types, populated/blank coverage, units, native grain, and repeated-measure structure;
- date and duration formats, reporting start/end, gaps, late starts, and missing periods;
- duplicate structure and candidate natural keys;
- source category value inventories and frequencies;
- missingness, impossible values, outliers, and fields whose apparent meaning is uncertain;
- competition, squad, academy, international, rehab/RTP, training, and match context fields;
- device/vendor context and any thresholds already applied upstream.

Exposure grain must be confirmed from the current file evidence as `weekly` or `session`. Prior-team knowledge can prompt the check but cannot replace it. The selected grain must then be supplied explicitly to every exposure command.

### 3. Field-by-field canonical mapping

For every required comparable injury field, document:

- canonical target and allowed values;
- source field(s) and distinct source values used as evidence;
- transformation or mapping rule;
- evidence class: source-reported, deterministic derivation, protocol-defined inference, or manual adjudication;
- origin/status value retained by the pipeline;
- coverage before and after the proposed rule;
- conflicts, unresolved values, and required review;
- tests or reconciliation samples needed before acceptance.

At minimum cover occasion category, match type, problem type, injury status, fit-for-selection status, confirmed return date and origin, days injured, severity/time-loss category, recurrence, contact context, body location, and tissue/pathology.

### 4. Team-specific taxonomy pass

Inventory every distinct source body-location and tissue/pathology value for the team. Map each value into the existing IOC 2020 consensus buckets in `docs/IOC_TAXONOMY_BUCKETS.csv`, using the strongest available evidence in this order:

1. a valid source controlled code plus its retained codebook;
2. an explicit source category whose meaning matches one consensus bucket;
3. a deterministic combination of named supporting fields;
4. a documented team-specific inference rule using named evidence fields;
5. manual adjudication.

Supporting fields such as diagnosis text, Orchard/OSIICS code, body part, laterality, tissue type, mechanism, and problem type may improve specificity only when the rule is explicit and reproducible. Review all distinct values and cross-field conflicts. Do not import another team's label mapping without confirming that the current team's codebook and value usage mean the same thing. AI may propose and challenge mappings, but it cannot silently create clinical facts or resolve ambiguous clinical categories.

The canonical IOC buckets remain shared across all teams. Team-specific variation belongs in the versioned source-to-canonical mapping and audit evidence, not in new dashboard categories.

### 5. AI review pass

Before sign-off, run a fresh review of the profile, value inventories, proposed mappings, coverage changes, and anomaly summaries. The review must check for:

- assumptions copied from another team;
- source labels mapped without codebook or value-use evidence;
- ambiguous dates, units, durations, exposure grain, or reporting windows;
- contradictory supporting fields;
- mappings that increase completeness by overstating certainty;
- team-specific logic leaking into shared scientific or reporting rules;
- missing provenance, audit origins, review cases, or test coverage;
- protected aliases or direct identifiers entering committed outputs.

Record findings and their disposition in the profile. AI output is review evidence, not adjudication; Abdel or another named human reviewer approves ambiguous scientific decisions.

## Implementation boundary after approval

Prefer a narrow source adapter or versioned team mapping over team-name branches in shared processing code. The adapter may normalize representation, units, and source labels into the already-frozen canonical contract. It must preserve source values and locators and include team-specific fixtures/reconciliation evidence.

A team-specific source mapping into existing controlled values is not permission to change the canonical taxonomy, analytical cohort, exposure denominator, validity thresholds, or `_v1` metric definitions. Any such change is `protocol_incompatible` and requires a recorded adjudication, a new versioned migration/rule set, and reruns for every affected team and season.

## Gate sequence

1. Receive and checksum the pseudonymised files locally.
2. Build the profile and source-value inventories.
3. Draft and test the source-to-canonical mappings.
4. Complete the AI review pass and resolve or list all findings.
5. Obtain Abdel's explicit profile/mapping approval.
6. Implement only the approved adapter or mapping changes, if any.
7. Separately reconfirm the exact hosted Supabase target and obtain Abdel's approval for the named live action; profile/mapping approval does not authorize a database write.
8. Run only the approved `ingest`, processing, curated-build, adjudication, or release action, retaining the existing per-step sign-offs.

No live database write occurs during profiling. Every later live action retains the project's exact-target approval requirement.
