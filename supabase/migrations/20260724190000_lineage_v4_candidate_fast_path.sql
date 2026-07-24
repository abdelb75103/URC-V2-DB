-- Lineage V4 candidate fast path.
--
-- Problem this migration fixes (measured 2026-07-24 against the live target):
-- `analysis.league_dashboard_release_candidates_v6` is a chain of UNION ALL
-- branches (v6 = v5 + lineage V4, v5 = v4 + OSIICS V3, and so on). Filtering
-- that chain on `analysis_version = 'v4'` does not prune the legacy branches,
-- so every read plans and evaluates the complete historical candidate stack.
-- Measured: `analysis.league_dashboard_payload_lineage_v1` filtered to season
-- 2024-25 returns its single 276 KB payload in about 53 seconds, while the
-- identical projection through `..._release_candidates_v6` did not return in
-- over 7 minutes (and an `explain` of it did not return in over 60 seconds,
-- so the cost includes planning, not only execution). Over the Supavisor
-- pooler that overruns the upstream timeout and the client is left waiting on
-- a connection that will never answer.
--
-- The `release-league --analysis-version v4` path reads those candidate views
-- three times, joins them twice more inside the promotion transaction, and
-- validates them again in two triggers. Every one of those hits the same
-- pathological plan.
--
-- Fix: expose the V4 branch on its own. These views are, by construction,
-- exactly the rows that `..._release_candidates_v6` contributes for
-- `analysis_version = 'v4'`: migration 20260724181000 defines that branch as
-- `select <columns>, 'v4'::text, ... from analysis.*_dashboard_payload_lineage_v1`,
-- and every other branch in the chain emits a different literal
-- `analysis_version`. No metric, cohort, classification, or payload rule
-- changes here; this is a planning fast path over the same rows. The frozen
-- `_v1` views and the whole legacy candidate chain are untouched, and
-- non-V4 releases keep validating against `..._release_candidates_v6`.

create view analysis.league_dashboard_release_candidates_lineage_v4
with (security_invoker = true) as
select season, 'v4'::text as analysis_version, classification_view_version,
  classification_evidence_sha256, cohort_view_version,
  cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_lineage_v1;

create view analysis.team_dashboard_release_candidates_lineage_v4
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id,
  'v4'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_lineage_v1;

comment on view analysis.league_dashboard_release_candidates_lineage_v4 is
  'V4 lineage branch of analysis.league_dashboard_release_candidates_v6, exposed directly so release validation does not plan the legacy union chain.';
comment on view analysis.team_dashboard_release_candidates_lineage_v4 is
  'V4 lineage branch of analysis.team_dashboard_release_candidates_v6, exposed directly so release validation does not plan the legacy union chain.';

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
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
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
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_lineage_v4 candidate
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
    where context.analysis_version = 'v4'
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;

  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v6 candidate
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
    where (
      context.classification_view_version <>
        'reporting_classification_2026-07-22_v2'
      or context.analysis_version <> 'v3'
    )
      and context.analysis_version <> 'v4'
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;
  return null;
end;
$$;

comment on function reporting.validate_league_dashboard_v2_candidate() is
  'Validates V4 releases against the lineage candidate view, OSIICS classification-only V3 releases against the immutable incremental candidate, and every other full release against v6 candidates.';
comment on function reporting.validate_team_dashboard_v2_candidates() is
  'Statement trigger validating V4 lineage, classification-only V3, or legacy full team dashboard candidates without planning the legacy union chain for V4.';

revoke execute on function reporting.validate_league_dashboard_v2_candidate()
  from public;
revoke execute on function reporting.validate_team_dashboard_v2_candidates()
  from public;
