-- Permit the governed 2024-25 classification successor in the shared league
-- release context. Existing classification versions remain unchanged.

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_classification_view_version_check,
  add constraint league_release_context_v2_classification_view_version_check check (
    classification_view_version in (
      'v2',
      'reporting_classification_2026-07-20_v1',
      'reporting_classification_2026-07-22_v2',
      'reporting_classification_2024-25_2026-08-27_v1'
    )
  ),
  drop constraint league_release_context_v2_classification_evidence,
  add constraint league_release_context_v2_classification_evidence check (
    (classification_view_version = 'v2' and classification_evidence_sha256 is null)
    or (
      classification_view_version in (
        'reporting_classification_2026-07-20_v1',
        'reporting_classification_2026-07-22_v2',
        'reporting_classification_2024-25_2026-08-27_v1'
      )
      and classification_evidence_sha256 is not null
    )
  );
