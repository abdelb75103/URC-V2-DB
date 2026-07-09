-- Phase 0 controlled reason codes (0.1 protected-alias redaction, 0.3 smoke
-- release retirement). Reason codes are controlled: seed by migration, never
-- ad hoc inside a pipeline command.

insert into audit.reason_codes (code, description) values
  (
    'protected_metadata_redaction',
    'Purged a protected Team A-Z league-alias placeholder value from stored '
    'source_values or record_state; the row and key are retained, only the '
    'value is replaced with [REDACTED_PROTECTED_METADATA].'
  ),
  (
    'aggregate_release_retired',
    'Aggregate release status flipped from approved to retired (e.g. a '
    'local development smoke-test artifact superseded by a governance-'
    'reviewed release); the release row and its metric rows are kept.'
  )
on conflict (code) do nothing;
