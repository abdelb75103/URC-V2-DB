-- Additive V6 release seam.  Year 2 team candidates are assembled from active
-- curated builds; accepted releases become league members only after promotion.

create table reporting.team_release_payloads_v6 (
  release_id uuid primary key references reporting.aggregate_releases(id),
  team_key text not null references reporting.teams(team_key),
  season text not null check (season = '2025-26'),
  curated_build_id uuid not null references curated.builds(id),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (classification_view_version = 'reporting_classification_2026-07-22_v2'),
  cohort_view_version text not null check (cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'),
  dashboard_payload jsonb not null,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique (release_id, team_key, season, curated_build_id)
);

create function reporting.prevent_team_release_payload_v6_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'team_release_payloads_v6 is immutable';
end;
$$;

create trigger team_release_payloads_v6_immutable
before update or delete on reporting.team_release_payloads_v6
for each row execute function reporting.prevent_team_release_payload_v6_mutation();

create table reporting.league_release_payloads_v6 (
  release_id uuid primary key references reporting.aggregate_releases(id),
  dashboard_payload jsonb not null check (jsonb_typeof(dashboard_payload) = 'object'),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);

create trigger league_release_payloads_v6_immutable
before update or delete on reporting.league_release_payloads_v6
for each row execute function reporting.prevent_team_release_payload_v6_mutation();

-- The established league release transaction still snapshots its bundle into
-- V2 storage.  This additive trigger copies only its V6 payload into the V6
-- immutable reader store, avoiding any mutation of the historical path.
create function reporting.copy_v6_league_release_payload()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if exists (
    select 1 from reporting.league_release_context_v2 context
    where context.release_id = new.release_id and context.analysis_version = 'v6'
  ) then
    insert into reporting.league_release_payloads_v6 (release_id, dashboard_payload, payload_sha256)
    values (new.release_id, new.dashboard_payload, new.payload_sha256);
  end if;
  return new;
end;
$$;

create trigger league_release_payloads_v2_copy_v6
after insert on reporting.league_release_payloads_v2
for each row execute function reporting.copy_v6_league_release_payload();

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_analysis_version_check,
  add constraint league_release_context_v2_analysis_version_check check (
    analysis_version in ('v2', 'v3', 'v4', 'v5', 'v6')
  ),
  drop constraint league_release_context_v2_decision_recorded_at_check,
  add constraint league_release_context_v2_decision_recorded_at_check check (
    (analysis_version = 'v2' and decision_recorded_at = date '2026-07-14') or
    (analysis_version = 'v3' and decision_recorded_at = date '2026-07-19') or
    (analysis_version = 'v4' and decision_recorded_at = date '2026-07-24') or
    (analysis_version = 'v5' and decision_recorded_at = date '2026-07-25') or
    (analysis_version = 'v6' and decision_recorded_at = date '2026-08-15')
  ),
  drop constraint league_release_context_v2_cohort_view_version_check,
  add constraint league_release_context_v2_cohort_view_version_check check (
    cohort_view_version in ('v2', 'season_bound_2026-07-20_v1',
      'lineage_2024-25_2026-07-24_v1', 'analysis_window_2024-25_2026-07-25_v1',
      'analysis_window_2025-26_2026-08-15_v1')
  ),
  drop constraint league_release_context_v2_cohort_evidence,
  add constraint league_release_context_v2_cohort_evidence check (
    (cohort_view_version = 'v2' and cohort_evidence_sha256 is null) or
    (cohort_view_version <> 'v2' and cohort_evidence_sha256 is not null)
  );

-- Partial Year 2 release progress is deliberately invisible to pooled league
-- work.  This relation returns either no rows or the exact 16 approved V6
-- release/build pairs, never a partial member set.
create view analysis.league_member_releases_v6
with (security_invoker = true) as
with accepted as (
  select distinct on (payload.team_key, payload.season)
    payload.team_key, payload.season, payload.release_id as team_release_id,
    payload.curated_build_id, release.approved_at, payload.created_at
  from reporting.team_release_payloads_v6 payload
  join reporting.aggregate_releases release on release.id = payload.release_id
  join curated.builds build on build.id = payload.curated_build_id
    and build.team_key = payload.team_key and build.season = payload.season
    and build.status = 'active'
  where release.status = 'approved'
  order by payload.team_key, payload.season, release.approved_at desc nulls last,
    payload.created_at desc, payload.release_id desc
), complete as (
  select * from accepted
  where (select count(*) from accepted where season = '2025-26') = 16
    and (select count(distinct team_key) from accepted where season = '2025-26') = 16
    and (select count(*) from reporting.teams where active) = 16
)
select team_key, season, team_release_id, curated_build_id, approved_at
from complete;

-- Before all 16 team releases this is the first-release candidate with a NULL
-- release id.  Afterwards it is the exact accepted release/build member pair
-- used by the league bundle transaction.
create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select active.team_key, active.season, member.team_release_id,
  active.curated_build_id, active.analysis_version,
  active.classification_view_version, active.classification_evidence_sha256,
  active.cohort_view_version, active.cohort_evidence_sha256, active.dashboard
from analysis.team_dashboard_payload_analysis_window_v6_enriched active
left join analysis.league_member_releases_v6 member
  on member.team_key = active.team_key and member.season = active.season
 and member.curated_build_id = active.curated_build_id;

-- The league candidate is not available during the first team release.  It
-- binds the immutable payload selected above back to the current active build.
create or replace view analysis.league_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select candidate.season, candidate.analysis_version,
  candidate.classification_view_version, candidate.classification_evidence_sha256,
  candidate.cohort_view_version, candidate.cohort_evidence_sha256,
  candidate.dashboard
from analysis.league_dashboard_payload_analysis_window_v6_enriched candidate
where exists (
  select 1 from analysis.league_member_releases_v6 member
  where member.season = candidate.season
  group by member.season
  having count(*) = 16
     and count(distinct member.team_key) = 16
)
and not exists (
  select 1
  from analysis.league_member_releases_v6 member
  left join analysis.team_dashboard_release_candidates_analysis_window_v6 active
    on active.team_key = member.team_key and active.season = member.season
   and active.curated_build_id = member.curated_build_id
  where member.season = candidate.season and active.team_key is null
);

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
begin
  if not exists (
    select 1 from reporting.league_release_context_v2 context
    where context.release_id = new.release_id and (
      (context.analysis_version = 'v6' and exists (
        select 1 from analysis.league_dashboard_release_candidates_analysis_window_v6 candidate
        where candidate.season = context.season and candidate.analysis_version = context.analysis_version
          and candidate.classification_view_version = context.classification_view_version
          and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
          and candidate.cohort_view_version = context.cohort_view_version
          and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
          and candidate.dashboard = new.dashboard_payload
      )) or (context.analysis_version <> 'v6' and exists (
        select 1 from analysis.league_dashboard_release_candidates_v5 candidate
        where candidate.season = context.season and candidate.analysis_version = context.analysis_version
          and candidate.classification_view_version = context.classification_view_version
          and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
          and candidate.cohort_view_version = context.cohort_view_version
          and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
          and candidate.dashboard = new.dashboard_payload
      ))
    )
  ) then raise exception 'league dashboard snapshot must equal its bound candidate'; end if;
  return new;
end;
$$;

create or replace function reporting.validate_team_dashboard_v2_candidates()
returns trigger language plpgsql as $$
begin
  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    where not exists (
      select 1 from analysis.team_dashboard_release_candidates_analysis_window_v6 candidate
      where context.analysis_version = 'v6' and candidate.season = context.season
        and candidate.team_key = payload.team_key and candidate.team_release_id = payload.team_release_id
        and candidate.curated_build_id = payload.curated_build_id and candidate.analysis_version = context.analysis_version
        and candidate.classification_view_version = context.classification_view_version
        and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
        and candidate.cohort_view_version = context.cohort_view_version
        and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
        and candidate.dashboard = payload.dashboard_payload
    ) and context.analysis_version = 'v6'
  ) then raise exception 'every V6 team dashboard snapshot must equal its bound candidate'; end if;
  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v5 candidate
      on candidate.season = context.season and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version = context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.analysis_version <> 'v6' and candidate.team_key is null
  ) then raise exception 'every team dashboard snapshot must equal its bound candidate'; end if;
  return null;
end;
$$;

-- V6 reader projections retain the established V5 source for historical
-- seasons.  Only public payload fields cross the web_reader boundary.
create view reporting.latest_team_dashboard_v6
with (security_invoker = false, security_barrier = true) as
select team_key, team, season, generated_at, analysis_window, method, coverage,
  headline, setting_split, setting_metrics, monthly, body_locations, injury_types,
  injury_profiles, injury_type_families, severity_distribution, contact_distribution,
  prior_season, limitations
from reporting.latest_team_dashboard_v5
where season <> '2025-26'
union all
select payload.team_key,
  payload.dashboard_payload ->> 'team' as team, payload.season,
  (payload.dashboard_payload ->> 'generated_at')::timestamptz as generated_at,
  payload.dashboard_payload -> 'analysis_window' as analysis_window,
  payload.dashboard_payload -> 'method' as method,
  payload.dashboard_payload -> 'coverage' as coverage,
  payload.dashboard_payload -> 'headline' as headline,
  payload.dashboard_payload -> 'setting_split' as setting_split,
  payload.dashboard_payload -> 'setting_metrics' as setting_metrics,
  payload.dashboard_payload -> 'monthly' as monthly,
  payload.dashboard_payload -> 'body_locations' as body_locations,
  payload.dashboard_payload -> 'injury_types' as injury_types,
  payload.dashboard_payload -> 'injury_profiles' as injury_profiles,
  payload.dashboard_payload -> 'injury_type_families' as injury_type_families,
  payload.dashboard_payload -> 'severity_distribution' as severity_distribution,
  payload.dashboard_payload -> 'contact_distribution' as contact_distribution,
  payload.dashboard_payload -> 'prior_season' as prior_season,
  payload.dashboard_payload -> 'limitations' as limitations
from reporting.team_release_payloads_v6 payload
join reporting.aggregate_releases release on release.id = payload.release_id
where release.status = 'approved';

create view reporting.latest_league_dashboard_v6
with (security_invoker = false, security_barrier = true) as
select team, season, generated_at, analysis_window, method, coverage, headline,
  setting_split, setting_metrics, monthly, body_locations, injury_types,
  injury_profiles, injury_type_families, severity_distribution, contact_distribution,
  prior_season, limitations
from reporting.latest_league_dashboard_v5
where season <> '2025-26'
union all
select payload.dashboard_payload ->> 'team', context.season,
  (payload.dashboard_payload ->> 'generated_at')::timestamptz, payload.dashboard_payload -> 'analysis_window',
  payload.dashboard_payload -> 'method', payload.dashboard_payload -> 'coverage', payload.dashboard_payload -> 'headline',
  payload.dashboard_payload -> 'setting_split', payload.dashboard_payload -> 'setting_metrics', payload.dashboard_payload -> 'monthly',
  payload.dashboard_payload -> 'body_locations', payload.dashboard_payload -> 'injury_types', payload.dashboard_payload -> 'injury_profiles',
  payload.dashboard_payload -> 'injury_type_families', payload.dashboard_payload -> 'severity_distribution',
  payload.dashboard_payload -> 'contact_distribution', payload.dashboard_payload -> 'prior_season', payload.dashboard_payload -> 'limitations'
from reporting.league_release_context_v2 context
join reporting.aggregate_releases release on release.id = context.release_id
join reporting.league_release_payloads_v6 payload on payload.release_id = context.release_id
where context.season = '2025-26' and context.analysis_version = 'v6'
  and release.status = 'approved';

create view reporting.latest_dashboard_cache_token_v2
with (security_invoker = false, security_barrier = true) as
select season, cache_token from reporting.latest_dashboard_cache_token_v1
where season <> '2025-26'
union all
select payload.season,
  encode(extensions.digest(convert_to(string_agg(payload.release_id::text, ',' order by payload.team_key), 'UTF8'), 'sha256'), 'hex')
from reporting.team_release_payloads_v6 payload
join reporting.aggregate_releases release on release.id = payload.release_id
where payload.season = '2025-26' and release.status = 'approved'
group by payload.season
having count(*) = 16 and count(distinct payload.team_key) = 16;

create view reporting.approved_dashboard_reader_target_v2
with (security_invoker = false, security_barrier = true) as
select target_attested and to_regclass('reporting.latest_team_dashboard_v6') is not null
  and to_regclass('reporting.latest_league_dashboard_v6') is not null
  and to_regclass('reporting.latest_dashboard_cache_token_v2') is not null as target_attested
from reporting.approved_dashboard_reader_target_v1;

revoke all on reporting.team_release_payloads_v6 from public, anon, authenticated, web_reader;
grant select on reporting.latest_team_dashboard_v6, reporting.latest_league_dashboard_v6,
  reporting.latest_dashboard_cache_token_v2, reporting.approved_dashboard_reader_target_v2 to web_reader;
