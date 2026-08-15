-- Additive V6 release seam. Year 2 candidates are derived from active curated
-- builds, then copied as immutable reviewed bytes before an atomic 16-team
-- league bundle may cross the public-reader boundary. Year 1 remains untouched.

create function reporting.canonical_jsonb_sha256_v1(payload jsonb)
returns text
language sql
immutable
strict
set search_path = pg_catalog, extensions
as $$
  select encode(extensions.digest(convert_to(payload::text, 'UTF8'), 'sha256'), 'hex');
$$;

revoke execute on function reporting.canonical_jsonb_sha256_v1(jsonb)
  from public, anon, authenticated, web_reader;

create table reporting.team_release_payloads_v6 (
  release_id uuid primary key references reporting.aggregate_releases(id),
  team_key text not null references reporting.teams(team_key),
  season text not null check (season = '2025-26'),
  curated_build_id uuid not null references curated.builds(id),
  analysis_version text not null check (analysis_version = 'v6'),
  classification_view_version text not null check (classification_view_version = 'reporting_classification_2026-07-22_v2'),
  classification_evidence_sha256 text not null check (classification_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  cohort_view_version text not null check (cohort_view_version = 'analysis_window_2025-26_2026-08-15_v1'),
  cohort_evidence_sha256 text not null check (cohort_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  dashboard_payload jsonb not null check (jsonb_typeof(dashboard_payload) = 'object'),
  payload_sha256 text not null check (
    payload_sha256 ~ '^[0-9a-f]{64}$'
    and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard_payload)
  ),
  created_at timestamptz not null default now(),
  unique (release_id, team_key, season, curated_build_id)
);

alter table reporting.team_release_payloads_v6 enable row level security;
revoke all on reporting.team_release_payloads_v6 from public, anon, authenticated, web_reader;

create function reporting.prevent_team_release_payload_v6_mutation()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'team_release_payloads_v6 is immutable';
end;
$$;

revoke execute on function reporting.prevent_team_release_payload_v6_mutation()
  from public, anon, authenticated, web_reader;

create trigger team_release_payloads_v6_immutable
before update or delete on reporting.team_release_payloads_v6
for each row execute function reporting.prevent_team_release_payload_v6_mutation();

create table reporting.league_release_payloads_v6 (
  release_id uuid primary key references reporting.aggregate_releases(id),
  dashboard_payload jsonb not null check (jsonb_typeof(dashboard_payload) = 'object'),
  payload_sha256 text not null check (
    payload_sha256 ~ '^[0-9a-f]{64}$'
    and payload_sha256 = reporting.canonical_jsonb_sha256_v1(dashboard_payload)
  ),
  created_at timestamptz not null default now()
);

alter table reporting.league_release_payloads_v6 enable row level security;
revoke all on reporting.league_release_payloads_v6 from public, anon, authenticated, web_reader;

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

revoke execute on function reporting.copy_v6_league_release_payload()
  from public, anon, authenticated, web_reader;

create trigger league_release_payloads_v2_copy_v6
after insert on reporting.league_release_payloads_v2
for each row execute function reporting.copy_v6_league_release_payload();

-- A rollback is an append-only successor bundle.  It copies retained,
-- immutable prior bytes into a new release and never re-approves historical
-- releases or team payloads.  The context is private and immutable so the V6
-- validation triggers can distinguish this exact replay from a live candidate.
create table reporting.v6_league_rollback_context (
  release_id uuid primary key references reporting.aggregate_releases(id),
  rollback_of_release_id uuid not null references reporting.aggregate_releases(id),
  replaces_release_id uuid not null references reporting.aggregate_releases(id),
  created_at timestamptz not null default now(),
  check (release_id <> rollback_of_release_id),
  check (release_id <> replaces_release_id),
  check (rollback_of_release_id <> replaces_release_id)
);
alter table reporting.v6_league_rollback_context enable row level security;
revoke all on reporting.v6_league_rollback_context from public, anon, authenticated, web_reader;
create trigger v6_league_rollback_context_immutable
before update or delete on reporting.v6_league_rollback_context
for each row execute function reporting.prevent_team_release_payload_v6_mutation();

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
-- work. This relation returns either no rows or the exact 16 latest approved
-- release/build pairs for the active 16-team roster, never a partial set.
create view analysis.league_member_releases_v6
with (security_invoker = true) as
with accepted as (
  select distinct on (payload.team_key, payload.season)
    payload.team_key, payload.season, payload.release_id as team_release_id,
    payload.curated_build_id, release.approved_at, payload.created_at
  from reporting.team_release_payloads_v6 payload
  join reporting.aggregate_releases release on release.id = payload.release_id
  join reporting.teams roster on roster.team_key = payload.team_key and roster.active
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

-- This build-derived relation is only for individual team preflight/promotion.
-- It intentionally does not read accepted releases, so a first team release is
-- possible. A league promotion uses the distinct immutable reader below.
create or replace view analysis.team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select active.team_key, active.season, null::uuid as team_release_id,
  active.curated_build_id, active.analysis_version,
  active.classification_view_version, active.classification_evidence_sha256,
  active.cohort_view_version, active.cohort_evidence_sha256, active.dashboard
from analysis.team_dashboard_payload_analysis_window_v6_enriched active;

-- The league path is deliberately different: these dashboard bytes have
-- already passed the individual review gate and are read from immutable V6
-- release storage. They are the only team payloads allowed into a league
-- bundle, preventing a current active build from silently replacing reviewed
-- bytes between the team and league promotion steps.
create view analysis.league_team_dashboard_release_candidates_analysis_window_v6
with (security_invoker = true) as
select member.team_key, member.season, member.team_release_id,
  member.curated_build_id, payload.analysis_version,
  payload.classification_view_version, payload.classification_evidence_sha256,
  payload.cohort_view_version, payload.cohort_evidence_sha256,
  payload.dashboard_payload as dashboard
from analysis.league_member_releases_v6 member
join reporting.team_release_payloads_v6 payload
  on payload.release_id = member.team_release_id
 and payload.team_key = member.team_key
 and payload.season = member.season
 and payload.curated_build_id = member.curated_build_id;

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
  left join analysis.league_team_dashboard_release_candidates_analysis_window_v6 stored
    on stored.team_key = member.team_key and stored.season = member.season
   and stored.curated_build_id = member.curated_build_id
   and stored.team_release_id = member.team_release_id
  where member.season = candidate.season and stored.team_key is null
);

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
declare
  target_classification_version text;
  target_analysis_version text;
begin
  select classification_view_version, analysis_version
    into target_classification_version, target_analysis_version
  from reporting.league_release_context_v2
  where release_id = new.release_id;

  if target_classification_version =
      'reporting_classification_2026-07-22_v2'
    and target_analysis_version = 'v3' then
    if not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_classification_incremental_20260722_v1
        candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'incremental league dashboard snapshot changed fields outside the accepted classification sections';
    end if;
  elsif target_analysis_version = 'v4' then
    if not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_release_candidates_lineage_v4 candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
    end if;
  elsif target_analysis_version = 'v5' then
    if not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_release_candidates_analysis_window_v5
        candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
    end if;
  elsif target_analysis_version = 'v6' then
    if exists (
      select 1 from reporting.v6_league_rollback_context rollback
      join reporting.league_release_context_v2 prior_context on prior_context.release_id = rollback.rollback_of_release_id
      join reporting.aggregate_releases prior_release on prior_release.id = rollback.rollback_of_release_id
      join reporting.league_release_payloads_v6 prior_payload on prior_payload.release_id = rollback.rollback_of_release_id
      where rollback.release_id = new.release_id
        and prior_release.status in ('approved', 'retired')
        and prior_context.season = (select season from reporting.league_release_context_v2 where release_id = new.release_id)
        and prior_context.analysis_version = 'v6'
        and prior_payload.dashboard_payload = new.dashboard_payload
    ) then
      null;
    elsif not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_release_candidates_analysis_window_v6
        candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'V6 league dashboard snapshot must equal its locked candidate';
    end if;
  elsif not exists (
    select 1
    from reporting.league_release_context_v2 context
    join analysis.league_dashboard_release_candidates_v6 candidate
      on candidate.season = context.season
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = new.dashboard_payload
    where context.release_id = new.release_id
  ) then
    raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
  end if;
  return new;
end;
$$;

create or replace function reporting.validate_team_dashboard_v2_candidates()
returns trigger language plpgsql as $$
begin
  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    join reporting.v6_league_rollback_context rollback on rollback.release_id = context.release_id
    left join reporting.team_dashboard_payloads_v2 prior_payload
      on prior_payload.bundle_release_id = rollback.rollback_of_release_id
     and prior_payload.team_key = payload.team_key
     and prior_payload.team_release_id = payload.team_release_id
     and prior_payload.curated_build_id = payload.curated_build_id
     and prior_payload.dashboard_payload = payload.dashboard_payload
    where context.analysis_version = 'v6' and prior_payload.team_key is null
  ) then
    raise exception 'every V6 rollback team dashboard snapshot must equal retained immutable predecessor bytes';
  end if;

  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_classification_incremental_20260722_v1
      candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.classification_view_version =
        'reporting_classification_2026-07-22_v2'
      and context.analysis_version = 'v3'
      and candidate.team_key is null
  ) then
    raise exception 'incremental team dashboard snapshots changed fields outside the accepted classification sections';
  end if;

  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_lineage_v4 candidate
      on candidate.season = context.season and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version = context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.analysis_version = 'v4' and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;

  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_analysis_window_v5 candidate
      on candidate.season = context.season and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version = context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.analysis_version = 'v5' and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;

  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    left join analysis.league_team_dashboard_release_candidates_analysis_window_v6 candidate
      on candidate.season = context.season and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version = context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.analysis_version = 'v6'
      and not exists (
        select 1 from reporting.v6_league_rollback_context rollback
        where rollback.release_id = context.release_id
      )
      and candidate.team_key is null
  ) then
    raise exception 'every V6 team dashboard snapshot must equal its immutable reviewed candidate';
  end if;

  if exists (
    select 1 from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v6 candidate
      on candidate.season = context.season and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version = context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where (
      context.classification_view_version <>
        'reporting_classification_2026-07-22_v2'
      or context.analysis_version <> 'v3'
    )
      and context.analysis_version <> 'v4'
      and context.analysis_version <> 'v5'
      and context.analysis_version <> 'v6'
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;
  return null;
end;
$$;

revoke execute on function reporting.validate_league_dashboard_v2_candidate()
  from public, anon, authenticated, web_reader;
revoke execute on function reporting.validate_team_dashboard_v2_candidates()
  from public, anon, authenticated, web_reader;

-- One completed, approved V6 bundle is the only Year 2 reader boundary. It
-- selects one successor and proves all sixteen immutable member snapshots
-- exist before a dashboard or cache token can be read.
create view reporting.latest_approved_league_bundle_v6
with (security_invoker = false, security_barrier = true) as
with newest as (
  select context.release_id, context.season
  from reporting.league_release_context_v2 context
  join reporting.aggregate_releases release on release.id = context.release_id
  join reporting.league_release_payloads_v6 payload on payload.release_id = context.release_id
  where context.season = '2025-26'
    and context.analysis_version = 'v6'
    and release.status = 'approved'
  order by release.approved_at desc nulls last, release.created_at desc, context.release_id desc
  limit 1
), complete as (
  select newest.release_id, newest.season
  from newest
  where (select count(*) from reporting.league_release_members_v2 member
         where member.release_id = newest.release_id) = 16
    and (select count(distinct member.team_key) from reporting.league_release_members_v2 member
         where member.release_id = newest.release_id) = 16
    and (select count(*)
         from reporting.team_dashboard_payloads_v2 payload
         join reporting.league_release_members_v2 member
           on member.release_id = payload.bundle_release_id
          and member.team_key = payload.team_key
          and member.team_release_id = payload.team_release_id
          and member.curated_build_id = payload.curated_build_id
         where payload.bundle_release_id = newest.release_id) = 16
)
select release_id, season from complete;

-- V6 reader projections retain the established V5 source for historical
-- seasons. Only public payload fields cross the web_reader boundary.
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
from reporting.latest_approved_league_bundle_v6 bundle
join reporting.team_dashboard_payloads_v2 payload
  on payload.bundle_release_id = bundle.release_id;

create view reporting.latest_league_dashboard_v6
with (security_invoker = false, security_barrier = true) as
select team, season, generated_at, analysis_window, method, coverage, headline,
  setting_split, setting_metrics, monthly, body_locations, injury_types,
  injury_profiles, injury_type_families, severity_distribution, contact_distribution,
  prior_season, limitations
from reporting.latest_league_dashboard_v5
where season <> '2025-26'
union all
select payload.dashboard_payload ->> 'team', bundle.season,
  (payload.dashboard_payload ->> 'generated_at')::timestamptz, payload.dashboard_payload -> 'analysis_window',
  payload.dashboard_payload -> 'method', payload.dashboard_payload -> 'coverage', payload.dashboard_payload -> 'headline',
  payload.dashboard_payload -> 'setting_split', payload.dashboard_payload -> 'setting_metrics', payload.dashboard_payload -> 'monthly',
  payload.dashboard_payload -> 'body_locations', payload.dashboard_payload -> 'injury_types', payload.dashboard_payload -> 'injury_profiles',
  payload.dashboard_payload -> 'injury_type_families', payload.dashboard_payload -> 'severity_distribution',
  payload.dashboard_payload -> 'contact_distribution', payload.dashboard_payload -> 'prior_season', payload.dashboard_payload -> 'limitations'
from reporting.latest_approved_league_bundle_v6 bundle
join reporting.league_release_payloads_v6 payload on payload.release_id = bundle.release_id;

create view reporting.latest_dashboard_cache_token_v2
with (security_invoker = false, security_barrier = true) as
select season, cache_token from reporting.latest_dashboard_cache_token_v1
where season <> '2025-26'
union all
select bundle.season,
  encode(extensions.digest(convert_to(bundle.release_id::text || ':' || payload.payload_sha256, 'UTF8'), 'sha256'), 'hex')
from reporting.latest_approved_league_bundle_v6 bundle
join reporting.league_release_payloads_v6 payload on payload.release_id = bundle.release_id;

create view reporting.approved_dashboard_reader_target_v2
with (security_invoker = false, security_barrier = true) as
select target_attested and to_regclass('reporting.latest_team_dashboard_v6') is not null
  and to_regclass('reporting.latest_league_dashboard_v6') is not null
  and to_regclass('reporting.latest_dashboard_cache_token_v2') is not null
  and to_regclass('reporting.latest_approved_league_bundle_v6') is not null as target_attested
from reporting.approved_dashboard_reader_target_v1;

revoke all on reporting.latest_approved_league_bundle_v6,
  reporting.team_release_payloads_v6, reporting.league_release_payloads_v6
  from public, anon, authenticated, web_reader;
grant select on reporting.latest_team_dashboard_v6, reporting.latest_league_dashboard_v6,
  reporting.latest_dashboard_cache_token_v2, reporting.approved_dashboard_reader_target_v2 to web_reader;
