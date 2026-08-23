-- Evaluate the accepted build-derived league candidate once, then seal its
-- exact JSONB bytes behind the existing candidate relation. The snapshot is
-- valid only while the same sixteen approved team release/build identities
-- remain current. A member change returns zero candidates until a new
-- versioned snapshot successor is reviewed and installed.

create table analysis.league_dashboard_release_candidate_snapshot_v6_20260823 (
  snapshot_version text primary key check (snapshot_version = '20260823120000'),
  season text not null check (season = '2025-26'),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (
    classification_view_version = 'reporting_classification_2026-07-22_v2'
  ),
  classification_evidence_sha256 text not null check (
    classification_evidence_sha256 ~ '^[0-9a-f]{64}$'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'
  ),
  cohort_evidence_sha256 text not null check (
    cohort_evidence_sha256 ~ '^[0-9a-f]{64}$'
  ),
  member_count integer not null check (member_count = 16),
  member_set_sha256 text not null check (member_set_sha256 ~ '^[0-9a-f]{64}$'),
  dashboard jsonb not null check (jsonb_typeof(dashboard) = 'object'),
  payload_sha256 text not null check (
    payload_sha256 ~ '^[0-9a-f]{64}$'
    and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
  ),
  created_at timestamptz not null default now(),
  unique (season, analysis_version, classification_view_version, cohort_view_version)
);

alter table analysis.league_dashboard_release_candidate_snapshot_v6_20260823
  enable row level security;
revoke all on analysis.league_dashboard_release_candidate_snapshot_v6_20260823
  from public, anon, authenticated, web_reader;

create function reporting.prevent_v6_league_candidate_snapshot_mutation_20260823()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'V6 league candidate snapshot is immutable';
end;
$$;

revoke execute on function
  reporting.prevent_v6_league_candidate_snapshot_mutation_20260823()
  from public, anon, authenticated, web_reader;

create trigger league_dashboard_release_candidate_snapshot_v6_20260823_immutable
before update or delete
on analysis.league_dashboard_release_candidate_snapshot_v6_20260823
for each row execute function
  reporting.prevent_v6_league_candidate_snapshot_mutation_20260823();

with current_members as materialized (
  select member.team_key, member.season, member.team_release_id,
    member.curated_build_id
  from analysis.league_member_releases_v6 member
  where member.season = '2025-26'
), member_set as (
  select season, count(*)::integer as member_count,
    reporting.canonical_jsonb_sha256_v1(
      jsonb_agg(jsonb_build_object(
        'team_key', team_key,
        'team_release_id', team_release_id::text,
        'curated_build_id', curated_build_id::text
      ) order by team_key)
    ) as member_set_sha256
  from current_members
  group by season
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct team_release_id) = 16
    and count(distinct curated_build_id) = 16
), build_derived_candidate as materialized (
  select candidate.season, candidate.analysis_version,
    candidate.classification_view_version,
    candidate.classification_evidence_sha256,
    candidate.cohort_view_version, candidate.cohort_evidence_sha256,
    candidate.dashboard
  from analysis.league_dashboard_release_candidates_analysis_window_v6 candidate
  where candidate.season = '2025-26'
    and candidate.analysis_version = 'v6'
    and candidate.classification_view_version =
      'reporting_classification_2026-07-22_v2'
    and candidate.cohort_view_version =
      'analysis_window_2025-26_2026-08-15_v1'
)
insert into analysis.league_dashboard_release_candidate_snapshot_v6_20260823 (
  snapshot_version, season, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  member_count, member_set_sha256, dashboard, payload_sha256
)
select '20260823120000', candidate.season, candidate.analysis_version,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version, candidate.cohort_evidence_sha256,
  members.member_count, members.member_set_sha256, candidate.dashboard,
  reporting.canonical_jsonb_sha256_v1(candidate.dashboard)
from build_derived_candidate candidate
join member_set members using (season);

do $$
begin
  if (
    select count(*)
    from analysis.league_dashboard_release_candidate_snapshot_v6_20260823
    where snapshot_version = '20260823120000'
      and member_count = 16
      and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
  ) <> 1 then
    raise exception 'V6 league candidate snapshot was not sealed exactly once';
  end if;
end;
$$;

create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
with current_members as materialized (
  select member.team_key, member.season, member.team_release_id,
    member.curated_build_id
  from analysis.league_member_releases_v6 member
  where member.season = '2025-26'
), member_set as (
  select season, count(*)::integer as member_count,
    reporting.canonical_jsonb_sha256_v1(
      jsonb_agg(jsonb_build_object(
        'team_key', team_key,
        'team_release_id', team_release_id::text,
        'curated_build_id', curated_build_id::text
      ) order by team_key)
    ) as member_set_sha256
  from current_members
  group by season
  having count(*) = 16
    and count(distinct team_key) = 16
    and count(distinct team_release_id) = 16
    and count(distinct curated_build_id) = 16
)
select snapshot.season, snapshot.analysis_version,
  snapshot.classification_view_version,
  snapshot.classification_evidence_sha256,
  snapshot.cohort_view_version, snapshot.cohort_evidence_sha256,
  snapshot.dashboard
from analysis.league_dashboard_release_candidate_snapshot_v6_20260823 snapshot
join member_set members
  on members.season = snapshot.season
 and members.member_count = snapshot.member_count
 and members.member_set_sha256 = snapshot.member_set_sha256
where snapshot.snapshot_version = '20260823120000'
  and snapshot.payload_sha256 = reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.league_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;

do $$
begin
  if to_regclass(
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260823'
    ) is null
    or to_regclass(
      'analysis.league_dashboard_release_candidates_analysis_window_v6'
    ) is null
    or not (
      select relrowsecurity
      from pg_class
      where oid =
        'analysis.league_dashboard_release_candidate_snapshot_v6_20260823'::regclass
    )
    or has_table_privilege(
      'web_reader',
      'analysis.league_dashboard_release_candidate_snapshot_v6_20260823',
      'select'
    )
  then
    raise exception 'V6 league candidate snapshot boundary is incomplete';
  end if;
end;
$$;
