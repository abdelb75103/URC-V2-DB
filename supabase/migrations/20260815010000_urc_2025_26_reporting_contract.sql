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
    'team_dashboard_release_v6',
    'Immutable 2025-26 team dashboard release from the accepted V6 reporting contract.'
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
  'e8d82b7d5b89c32576b806bb33778601030538ba8fb56fc1a68febc5f56d3fd2',
  'docs/evidence/urc_2025_26_reporting_contract.json',
  'Abdel Babiker',
  '20260815010000',
  timestamptz '2026-08-15 00:00:00+00'
);

-- Per-row public-fixture provenance was not represented by curated.fixtures.
-- The curated fixture row carries the canonical prepared CSV checksum.  The
-- separate upstream response checksum records the official JSON bytes from
-- which fixture_preparation.py produced that CSV; these are deliberately
-- different byte streams and must never be equated.
create table curated.fixture_provenance_v1 (
  season text not null,
  source_row_number integer not null,
  upstream_match_id text not null check (length(trim(upstream_match_id)) > 0),
  source_locator text not null check (source_locator ~ '^https://'),
  prepared_file_sha256 text not null check (prepared_file_sha256 ~ '^[0-9a-f]{64}$'),
  source_request_sha256 text not null check (source_request_sha256 ~ '^[0-9a-f]{64}$'),
  upstream_response_sha256 text not null check (upstream_response_sha256 ~ '^[0-9a-f]{64}$'),
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

-- Once loaded, the checksum-bound Year 2 schedule is immutable. Historical
-- seasons retain their existing behaviour; a future correction must use an
-- additive season-specific successor rather than rewriting accepted rows.
create function curated.reject_urc_2025_26_fixture_mutation()
returns trigger language plpgsql as $$
begin
  if old.season = '2025-26' then
    raise exception 'accepted 2025-26 curated fixtures are immutable';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function curated.reject_urc_2025_26_fixture_mutation()
  from public, anon, authenticated, web_reader;

create trigger curated_fixtures_2025_26_immutable
before update or delete on curated.fixtures
for each row execute function curated.reject_urc_2025_26_fixture_mutation();

-- The public fixture relation can only become accepted through this exact
-- committed preparation record. It binds the protected raw response and its
-- de-identified prepared CSV without storing raw response content in Git or
-- the reporting reader surface.
create table analysis.fixture_preparation_evidence_v1 (
  season text primary key check (season = '2025-26'),
  evidence_locator text not null check (evidence_locator =
    'docs/evidence/urc_2025_26_fixture_preparation.json'),
  evidence_sha256 text not null check (evidence_sha256 =
    '7b9a79ae5aeb3d8895d31e2c8d48ac0a555b40d772739b7949acac57f3a6d7ff'),
  official_endpoint text not null check (official_endpoint =
    'https://www.unitedrugby.com/graphql'),
  source_locator_pattern text not null check (source_locator_pattern =
    'https://www\.unitedrugby\.com/graphql#data\.matchstats\[[0-9]+\]'),
  source_request_sha256 text not null check (source_request_sha256 =
    '57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af'),
  upstream_response_sha256 text not null check (upstream_response_sha256 =
    '411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6'),
  prepared_file_sha256 text not null check (prepared_file_sha256 =
    '071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b'),
  retrieved_at timestamptz not null check (retrieved_at = timestamptz '2026-08-15T01:09:13Z')
);

insert into analysis.fixture_preparation_evidence_v1 (
  season, evidence_locator, evidence_sha256, official_endpoint,
  source_locator_pattern, source_request_sha256, upstream_response_sha256,
  prepared_file_sha256, retrieved_at
) values (
  '2025-26', 'docs/evidence/urc_2025_26_fixture_preparation.json',
  '7b9a79ae5aeb3d8895d31e2c8d48ac0a555b40d772739b7949acac57f3a6d7ff',
  'https://www.unitedrugby.com/graphql',
  'https://www\.unitedrugby\.com/graphql#data\.matchstats\[[0-9]+\]',
  '57f968c98a21c0fc3f8350c03beffdc5ccfa89e7221e3ba13200bae16ff6b1af',
  '411d683d87619bd35f1e6ce62951c0c1ad4aa1ccd57e042ac77651def0e017f6',
  '071520f3f3c3dbe1979c8a42936d42bed9bc9b61ecf82131cc8151417d035d1b',
  timestamptz '2026-08-15T01:09:13Z'
);

alter table analysis.fixture_preparation_evidence_v1 enable row level security;
revoke all on analysis.fixture_preparation_evidence_v1
  from public, anon, authenticated, web_reader;

create function analysis.reject_fixture_preparation_evidence_v1_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'analysis.fixture_preparation_evidence_v1 is immutable';
end;
$$;
revoke execute on function analysis.reject_fixture_preparation_evidence_v1_mutation()
  from public, anon, authenticated, web_reader;
create trigger fixture_preparation_evidence_v1_immutable
before update or delete on analysis.fixture_preparation_evidence_v1
for each row execute function analysis.reject_fixture_preparation_evidence_v1_mutation();

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
  league_team_candidate_relation text not null check (
    league_team_candidate_relation =
      'analysis.league_team_dashboard_release_candidates_analysis_window_v6'
  ),
  league_candidate_relation text not null check (
    league_candidate_relation =
      'analysis.league_dashboard_release_candidates_analysis_window_v6'
  ),
  required_scientific_relations jsonb not null check (
    required_scientific_relations = '[
      "analysis.accepted_urc_fixtures_v6",
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
  team_candidate_relation, league_team_candidate_relation, league_candidate_relation,
  required_scientific_relations,
  metric_contract,
  evidence_sha256, evidence_locator
) values (
  '2025-26',
  'v6',
  'reporting_classification_2026-07-22_v2',
  'analysis_window_2025-26_2026-08-15_v1',
  'analysis.team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_dashboard_release_candidates_analysis_window_v6',
  '[
    "analysis.accepted_urc_fixtures_v6",
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
  'e8d82b7d5b89c32576b806bb33778601030538ba8fb56fc1a68febc5f56d3fd2',
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
      and to_regclass(contract.league_team_candidate_relation) is not null
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
-- frozen V2-base marker and the approved additive correction, plus the
-- registered hardening migration.  The correction deliberately remains a
-- separate append-only release family; folding it into V2 would make target
-- attestation depend on a non-existent V2 context row.
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
    join reporting.league_release_payloads_v2 payload on payload.release_id = context.release_id
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
