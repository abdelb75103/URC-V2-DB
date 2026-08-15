-- Additive 2025-26 release contract.
--
-- This migration deliberately registers the Year 2 boundary and no computed
-- dashboard cohort. The V5 computational chain is frozen for 2024-25. A
-- separate evidence-backed V6 successor must create the two candidate views
-- named below before a Year 2 release can proceed.

insert into audit.reason_codes (code, description) values
  (
    'league_dashboard_release_v6',
    'Immutable 16-team 2025-26 league dashboard release from the accepted V6 reporting contract.'
  ),
  (
    'curated_fixture_provenance_v1',
    'Append-only official-fixture provenance attached to a registered curated fixture row.'
  )
on conflict (code) do nothing;

alter table audit.reporting_cohort_rule_adjudications_v3
  drop constraint reporting_cohort_rule_adjudications_v3_migration_version_check,
  add constraint reporting_cohort_rule_adjudications_v3_migration_version_check check (
    migration_version in (
      '20260720170000', '20260724181000', '20260725190000',
      '20260815010000'
    )
  );

-- This is a new immutable identity. July and August source evidence stays in
-- lineage and curated storage, but falls outside this initial reporting cohort.
insert into analysis.reporting_season_windows_v3
  (cohort_view_version, season, season_start, season_end, decision_ref)
values (
  'analysis_window_2025-26_2026-08-15_v1',
  '2025-26',
  date '2025-09-01',
  date '2026-06-30',
  'ANALYSIS-WINDOW-2025-26-01'
);

insert into audit.reporting_cohort_rule_adjudications_v3
  (adjudication_ref, cohort_view_version, season, decision, evidence_sha256,
   evidence_locator, reviewer, migration_version, decided_at)
values (
  'ANALYSIS-WINDOW-2025-26-01',
  'analysis_window_2025-26_2026-08-15_v1',
  '2025-26',
  '{
    "fixture_rule":"official registered URC fixtures within the immutable reporting window multiplied by 20 player-hours per team participation",
    "injury_rule":"included canonical injury rows dated within the immutable reporting window; season-attributed undated rows remain in non-monthly totals and breakdowns",
    "retention_rule":"retain July and August 2025 source evidence with full lineage while excluding it from the initial reporting cohort",
    "window_rule":"inclusive 2025-09-01 through 2026-06-30; no 2024-25 source, processing, curated, cohort, release, or payload mutation"
  }'::jsonb,
  'a9c5ebc40a063564d70a2cc2e1f45fddb7069a900d398bea5b32208b65eaf3fe',
  'docs/evidence/urc_2025_26_reporting_contract.json',
  'Abdel Babiker',
  '20260815010000',
  timestamptz '2026-08-15 00:00:00+00'
);

-- Per-row public-fixture provenance was not represented by curated.fixtures.
-- Keep it in a new relation, rather than changing any frozen fixture row.
create table curated.fixture_provenance_v1 (
  season text not null,
  source_row_number integer not null,
  upstream_match_id text not null check (length(trim(upstream_match_id)) > 0),
  source_locator text not null check (source_locator ~ '^https://'),
  source_request_sha256 text not null check (source_request_sha256 ~ '^[0-9a-f]{64}$'),
  source_response_sha256 text not null check (source_response_sha256 ~ '^[0-9a-f]{64}$'),
  retrieved_at timestamptz not null,
  registered_by_run_id uuid not null references audit.pipeline_runs(id),
  created_at timestamptz not null default now(),
  primary key (season, source_row_number),
  unique (season, upstream_match_id),
  foreign key (season, source_row_number)
    references curated.fixtures (season, source_row_number)
);

alter table curated.fixture_provenance_v1 enable row level security;
revoke all on curated.fixture_provenance_v1 from public, anon, authenticated, web_reader;

create function curated.reject_fixture_provenance_v1_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'curated.fixture_provenance_v1 is append-only; register a superseding fixture source row';
end;
$$;
revoke execute on function curated.reject_fixture_provenance_v1_mutation()
  from public, anon, authenticated, web_reader;

create trigger fixture_provenance_v1_immutable
before update or delete on curated.fixture_provenance_v1
for each row execute function curated.reject_fixture_provenance_v1_mutation();

-- One explicit, season-bound tuple prevents a Year 1 V5 fallback. The
-- candidate relation names are data rather than a broad naming convention, so
-- a new computational successor must opt in deliberately.
create table analysis.accepted_release_contracts_v1 (
  season text primary key check (season = '2025-26'),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (
    classification_view_version = 'reporting_classification_2026-07-22_v2'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
  ),
  team_candidate_relation text not null check (
    team_candidate_relation =
      'analysis.team_dashboard_release_candidates_analysis_window_v6'
  ),
  league_candidate_relation text not null check (
    league_candidate_relation =
      'analysis.league_dashboard_release_candidates_analysis_window_v6'
  ),
  required_scientific_relations jsonb not null check (
    required_scientific_relations = '[
      "analysis.analysis_window_injury_cohort_v6",
      "analysis.analysis_window_league_monthly_v6",
      "analysis.analysis_window_league_summary_v6"
    ]'::jsonb
  ),
  metric_contract jsonb not null check (jsonb_typeof(metric_contract) = 'object'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  evidence_locator text not null check (evidence_locator =
    'docs/evidence/urc_2025_26_reporting_contract.json'
  ),
  created_at timestamptz not null default now(),
  unique (season, analysis_version, classification_view_version, cohort_view_version)
);

alter table analysis.accepted_release_contracts_v1 enable row level security;
revoke all on analysis.accepted_release_contracts_v1
  from public, anon, authenticated, web_reader;

create function analysis.reject_accepted_release_contract_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'analysis.accepted_release_contracts_v1 is immutable; add a new versioned contract';
end;
$$;
revoke execute on function analysis.reject_accepted_release_contract_mutation()
  from public, anon, authenticated, web_reader;

create trigger accepted_release_contracts_v1_immutable
before update or delete on analysis.accepted_release_contracts_v1
for each row execute function analysis.reject_accepted_release_contract_mutation();

insert into analysis.accepted_release_contracts_v1 (
  season, analysis_version, classification_view_version, cohort_view_version,
  team_candidate_relation, league_candidate_relation, required_scientific_relations,
  metric_contract,
  evidence_sha256, evidence_locator
) values (
  '2025-26',
  'v6',
  'reporting_classification_2026-07-22_v2',
  'analysis_window_2025-26_2026-08-15_v1',
  'analysis.team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_dashboard_release_candidates_analysis_window_v6',
  '[
    "analysis.analysis_window_injury_cohort_v6",
    "analysis.analysis_window_league_monthly_v6",
    "analysis.analysis_window_league_summary_v6"
  ]'::jsonb,
  '{
    "burden":"pooled days lost / pooled exposure hours * 1000",
    "incidence":"pooled time-loss injuries / pooled exposure hours * 1000",
    "match_exposure":"registered fixtures in the reporting window * 20 player-hours per team participation",
    "mean_severity":"pooled days lost / pooled time-loss injuries"
  }'::jsonb,
  'a9c5ebc40a063564d70a2cc2e1f45fddb7069a900d398bea5b32208b65eaf3fe',
  'docs/evidence/urc_2025_26_reporting_contract.json'
);

create function analysis.release_contract_candidates_available_v1(
  requested_season text,
  requested_analysis_version text,
  requested_classification_view_version text,
  requested_cohort_view_version text
)
returns boolean
language sql
stable
set search_path = pg_catalog, analysis
as $$
  select exists (
    select 1
    from analysis.accepted_release_contracts_v1 contract
    where contract.season = requested_season
      and contract.analysis_version = requested_analysis_version
      and contract.classification_view_version =
        requested_classification_view_version
      and contract.cohort_view_version = requested_cohort_view_version
      and to_regclass(contract.team_candidate_relation) is not null
      and to_regclass(contract.league_candidate_relation) is not null
      and not exists (
        select 1
        from jsonb_array_elements_text(contract.required_scientific_relations)
          required(relation_name)
        where to_regclass(required.relation_name) is null
      )
  );
$$;
revoke execute on function analysis.release_contract_candidates_available_v1(
  text, text, text, text
) from public, anon, authenticated, web_reader;

-- The website's role receives no release, audit, migration, or fixture tables.
-- It can only attest that its connection is the approved database, using a
-- frozen Year 1 release marker and the registered hardening migration.
create view reporting.approved_dashboard_reader_target_v1
with (security_invoker = false, security_barrier = true) as
select (
  current_database() = 'postgres'
  and exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260803163430'
      and migration.name = 'dynamic_row_correction_batch_v7_hardening'
      and migration.statements = array[
        'migration_sha256=859e18440317494eb3936fd80c136a8b8fb2e7b2604141bcf58048aeaf604365'
      ]
  )
  and exists (
    select 1
    from reporting.league_release_context_v2 context
    join reporting.aggregate_releases release on release.id = context.release_id
    where context.season = '2024-25'
      and release.release_label = 'urc-2024-25-correction-r1122-20260729-a1'
      and release.status = 'approved'
  )
) as target_attested;

revoke all on reporting.approved_dashboard_reader_target_v1
  from public, anon, authenticated, web_reader;
grant select on reporting.approved_dashboard_reader_target_v1 to web_reader;

comment on table curated.fixture_provenance_v1 is
  'Append-only public official-fixture provenance keyed to one curated fixture source row. No protected team alias or player data is stored.';
comment on table analysis.accepted_release_contracts_v1 is
  'Explicit season-bound release tuple and required V6 candidate relation names. Year 2 promotion fails closed until those relations exist.';
comment on function analysis.release_contract_candidates_available_v1(text, text, text, text) is
  'Fail-closed predicate for an explicit release tuple and its required candidate relations.';
comment on view reporting.approved_dashboard_reader_target_v1 is
  'One boolean least-privilege target attestation for the server-side web reader. It exposes no release, fixture, migration, team, or player values.';
