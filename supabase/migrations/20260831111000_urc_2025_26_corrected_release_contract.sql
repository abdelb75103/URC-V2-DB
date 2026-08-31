-- Accept the exact corrected Year 2 release route without mutating the
-- immutable predecessor contract.

create table analysis.accepted_release_contracts_v2 (
  season text primary key check (season = '2025-26'),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (
    classification_view_version =
      'reporting_classification_2025-26_2026-08-31_v3'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'injury_lineage_2025-26_2026-08-30_v2'
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
      "analysis.urc_2025_26_injury_successor_cohort_v1",
      "analysis.urc_2025_26_injury_successor_league_monthly_v1",
      "analysis.urc_2025_26_injury_successor_league_summary_v1",
      "analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract",
      "analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000"
    ]'::jsonb
  ),
  metric_contract jsonb not null check (metric_contract = '{
    "recorded_injuries":"count(final classified eligible injury rows, including undated)",
    "time_loss_injuries":"count(final classification = Time Loss)",
    "overall_incidence":"pooled recorded injuries / pooled exposure hours * 1000",
    "incidence":"pooled final Time Loss injuries / pooled exposure hours * 1000",
    "mean_severity":"known-duration Time Loss days lost / known-duration Time Loss injuries",
    "burden":"known-duration Time Loss days lost / pooled exposure hours * 1000"
  }'::jsonb),
  evidence_sha256 text not null check (
    evidence_sha256 =
      'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172'
  ),
  evidence_locator text not null check (
    evidence_locator =
      'docs/evidence/urc_2025_26_reporting_key_family_correction.json'
  ),
  created_at timestamptz not null default now(),
  unique (
    season, analysis_version, classification_view_version,
    cohort_view_version
  )
);

alter table analysis.accepted_release_contracts_v2 enable row level security;
revoke all on analysis.accepted_release_contracts_v2
  from public, anon, authenticated, web_reader;

create trigger accepted_release_contracts_v2_immutable
before update or delete on analysis.accepted_release_contracts_v2
for each row execute function analysis.reject_accepted_release_contract_mutation();

insert into analysis.accepted_release_contracts_v2 (
  season, analysis_version, classification_view_version,
  cohort_view_version, team_candidate_relation,
  league_team_candidate_relation, league_candidate_relation,
  required_scientific_relations, metric_contract,
  evidence_sha256, evidence_locator
) values (
  '2025-26', 'v6',
  'reporting_classification_2025-26_2026-08-31_v3',
  'injury_lineage_2025-26_2026-08-30_v2',
  'analysis.team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_team_dashboard_release_candidates_analysis_window_v6',
  'analysis.league_dashboard_release_candidates_analysis_window_v6',
  '[
    "analysis.accepted_urc_fixtures_v6",
    "analysis.urc_2025_26_injury_successor_cohort_v1",
    "analysis.urc_2025_26_injury_successor_league_monthly_v1",
    "analysis.urc_2025_26_injury_successor_league_summary_v1",
    "analysis.team_dashboard_release_candidate_snapshot_v6_20260831_family_contract",
    "analysis.league_dashboard_release_candidate_snapshot_v6_20260831110000"
  ]'::jsonb,
  '{
    "recorded_injuries":"count(final classified eligible injury rows, including undated)",
    "time_loss_injuries":"count(final classification = Time Loss)",
    "overall_incidence":"pooled recorded injuries / pooled exposure hours * 1000",
    "incidence":"pooled final Time Loss injuries / pooled exposure hours * 1000",
    "mean_severity":"known-duration Time Loss days lost / known-duration Time Loss injuries",
    "burden":"known-duration Time Loss days lost / pooled exposure hours * 1000"
  }'::jsonb,
  'd9a8d41772ffadd89ad1b40ae3e8494586adc87a5beff372ddfa8307117cc172',
  'docs/evidence/urc_2025_26_reporting_key_family_correction.json'
);

create or replace function analysis.release_contract_candidates_available_v1(
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
    from analysis.accepted_release_contracts_v2 contract
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

do $$
begin
  if not analysis.release_contract_candidates_available_v1(
      '2025-26', 'v6',
      'reporting_classification_2025-26_2026-08-31_v3',
      'injury_lineage_2025-26_2026-08-30_v2'
    )
    or has_table_privilege(
      'web_reader', 'analysis.accepted_release_contracts_v2', 'select'
    )
  then
    raise exception 'Corrected Year 2 release contract is unavailable or crossed the reader boundary';
  end if;
end;
$$;
