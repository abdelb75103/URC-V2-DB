-- A reviewed league bundle has already been compared to the analytical
-- candidate before promotion.  The old trigger implementations repeated the
-- full analytical payload query inside the write transaction.  Keep the
-- immutable snapshot contract, but validate the stored database hash and
-- exact approved member identities in constant-sized release tables instead.

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
declare
  expected_hash text;
begin
  select run.parameters ->> 'league_dashboard_payload_sha256'
  into expected_hash
  from reporting.league_release_context_v2 context
  join reporting.aggregate_releases release on release.id = context.release_id
  join audit.pipeline_runs run on run.id = release.pipeline_run_id
  where context.release_id = new.release_id;

  if expected_hash is null
     or expected_hash !~ '^[0-9a-f]{64}$'
     or new.payload_sha256 is distinct from expected_hash then
    raise exception 'league dashboard snapshot hash differs from the reviewed canonical payload hash';
  end if;
  return new;
end;
$$;

create or replace function reporting.validate_team_dashboard_v2_candidates()
returns trigger language plpgsql as $$
declare
  inserted_count integer;
  distinct_team_count integer;
  member_count integer;
  hash_count integer;
begin
  select count(*), count(distinct team_key), count(distinct bundle_release_id)
  into inserted_count, distinct_team_count, member_count
  from new_team_dashboard_v2_payloads;

  if inserted_count <> 16 or distinct_team_count <> 16 or member_count <> 1 then
    raise exception 'league dashboard bundle must insert exactly 16 distinct team payloads in one release';
  end if;

  select count(*) into member_count
  from reporting.league_release_members_v2 members
  join (select distinct bundle_release_id from new_team_dashboard_v2_payloads) inserted
    on inserted.bundle_release_id = members.release_id;
  if member_count <> 16 then
    raise exception 'league dashboard bundle must bind exactly 16 approved members';
  end if;

  select count(*) into hash_count
  from audit.pipeline_runs run
  join reporting.aggregate_releases release on release.pipeline_run_id = run.id
  join (select distinct bundle_release_id from new_team_dashboard_v2_payloads) inserted
    on inserted.bundle_release_id = release.id
  cross join lateral jsonb_object_keys(
    coalesce(run.parameters -> 'team_dashboard_payload_sha256s', '{}'::jsonb)
  ) as expected(team_key);
  if hash_count <> 16 then
    raise exception 'reviewed canonical team payload hash set must contain exactly 16 members';
  end if;

  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    join reporting.aggregate_releases release
      on release.id = payload.bundle_release_id
    join audit.pipeline_runs run on run.id = release.pipeline_run_id
    left join reporting.league_release_members_v2 member
      on member.release_id = payload.bundle_release_id
     and member.team_key = payload.team_key
     and member.team_release_id = payload.team_release_id
     and member.curated_build_id = payload.curated_build_id
    left join analysis.league_member_releases_v2 live
      on live.season = context.season
     and live.team_key = payload.team_key
     and live.team_release_id = payload.team_release_id
     and live.curated_build_id = payload.curated_build_id
    where member.team_key is null
       or live.team_key is null
       or payload.payload_sha256 is distinct from
          (run.parameters -> 'team_dashboard_payload_sha256s' ->> payload.team_key)
  ) then
    raise exception 'team dashboard snapshot identity or hash differs from the reviewed canonical payload';
  end if;

  if exists (
    select 1
    from reporting.league_release_members_v2 member
    join (select distinct bundle_release_id from new_team_dashboard_v2_payloads) inserted
      on inserted.bundle_release_id = member.release_id
    left join new_team_dashboard_v2_payloads payload
      on payload.bundle_release_id = member.release_id
     and payload.team_key = member.team_key
     and payload.team_release_id = member.team_release_id
     and payload.curated_build_id = member.curated_build_id
    where payload.team_key is null
  ) then
    raise exception 'reviewed canonical team payloads do not cover every approved member';
  end if;
  return null;
end;
$$;

revoke execute on function reporting.validate_league_dashboard_v2_candidate() from public;
revoke execute on function reporting.validate_team_dashboard_v2_candidates() from public;

comment on function reporting.validate_league_dashboard_v2_candidate() is
  'Validates a reviewed immutable league snapshot against its pre-write canonical database hash without recomputing analytical dashboard views.';
comment on function reporting.validate_team_dashboard_v2_candidates() is
  'Validates exactly 16 reviewed immutable team snapshots against release-member identities and canonical database hashes without recomputing analytical dashboard views.';
