-- Seal the league candidate only after all 16 successor team releases exist.
-- The snapshot remains bound to their immutable release and build identifiers.

set local statement_timeout = 0;

create table analysis.league_dashboard_release_candidate_snapshot_v6_20260830 (
  snapshot_version text primary key,
  season text not null check (season = '2025-26'),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null,
  classification_evidence_sha256 text not null,
  cohort_view_version text not null,
  cohort_evidence_sha256 text not null,
  member_count integer not null check (member_count = 16),
  member_set_sha256 text not null check (member_set_sha256 ~ '^[0-9a-f]{64}$'),
  dashboard jsonb not null,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

alter table analysis.league_dashboard_release_candidate_snapshot_v6_20260830
  enable row level security;
revoke all on analysis.league_dashboard_release_candidate_snapshot_v6_20260830
  from public, anon, authenticated, web_reader;

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
), candidate as materialized (
  select payload.season, 'v6'::text as analysis_version,
    payload.classification_view_version,
    payload.classification_evidence_sha256,
    payload.cohort_view_version,
    payload.cohort_evidence_sha256,
    jsonb_set(
      jsonb_set(
        jsonb_set(
          payload.dashboard,
          '{coverage,included_exposure_status}',
          to_jsonb('includes_temporary_league_mean_estimates_for_two_teams'::text)
        ),
        '{coverage,distance_km}',
        'null'::jsonb
      ),
      '{limitations}',
      jsonb_build_array(
        'Benetton and Edinburgh season exposure hours are temporary means of the other 14 source-backed team totals, not submitted exposure.',
        'Their training hours equal estimated season totals less fixture-derived match hours.',
        'League monthly exposure, league distance, and both teams'' monthly exposure and distance remain unavailable.'
      )
    ) as dashboard
  from analysis.league_dashboard_payload_analysis_window_v6_enriched payload
  where payload.season = '2025-26'
)
insert into analysis.league_dashboard_release_candidate_snapshot_v6_20260830 (
  snapshot_version, season, analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256,
  member_count, member_set_sha256, dashboard, payload_sha256
)
select '20260830160000', candidate.season, candidate.analysis_version,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version, candidate.cohort_evidence_sha256,
  members.member_count, members.member_set_sha256, candidate.dashboard,
  reporting.canonical_jsonb_sha256_v1(candidate.dashboard)
from candidate
join member_set members using (season);

do $$
begin
  if (
    select count(*)
    from analysis.league_dashboard_release_candidate_snapshot_v6_20260830
    where snapshot_version = '20260830160000'
      and member_count = 16
      and dashboard #>> '{coverage,included_exposure_status}' =
        'includes_temporary_league_mean_estimates_for_two_teams'
      and dashboard #> '{coverage,distance_km}' = 'null'::jsonb
      and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard)
  ) <> 1 then
    raise exception 'V6 exposure-successor league snapshot was not sealed exactly once';
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
from analysis.league_dashboard_release_candidate_snapshot_v6_20260830 snapshot
join member_set members
  on members.season = snapshot.season
 and members.member_count = snapshot.member_count
 and members.member_set_sha256 = snapshot.member_set_sha256
where snapshot.snapshot_version = '20260830160000'
  and snapshot.payload_sha256 = reporting.canonical_jsonb_sha256_v1(snapshot.dashboard);

revoke all on analysis.league_dashboard_release_candidates_analysis_window_v6
  from public, anon, authenticated, web_reader;
