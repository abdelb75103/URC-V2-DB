-- Keep an approved immutable bundle visible while one of its member team
-- releases is superseded. A retired member is accepted only when its exact
-- original release run succeeded; all immutable identity, section, roster,
-- build, and denominator checks remain in force.

create or replace view reporting.latest_approved_dashboard_bundle_v2
with (security_invoker = false, security_barrier = true) as
select c.release_id, c.season
from reporting.league_release_context_v2 c
join reporting.aggregate_releases r on r.id = c.release_id and r.status = 'approved'
join reporting.league_release_payloads_v2 league_payload on league_payload.release_id = c.release_id
where (
  select count(*) from reporting.league_release_members_v2 m
  where m.release_id = c.release_id
) = 16
  and (
    select count(*) from reporting.team_dashboard_payloads_v2 p
    where p.bundle_release_id = c.release_id
  ) = 16
  and (select count(*) from reporting.teams) = 16
  and not exists (
    select 1 from reporting.teams roster
    where not exists (
      select 1 from reporting.league_release_members_v2 m
      where m.release_id = c.release_id and m.team_key = roster.team_key
    )
  )
  and not exists (
    select 1
    from reporting.league_release_members_v2 m
    where m.release_id = c.release_id
      and not exists (
        select 1
        from reporting.release_context team_context
        join reporting.aggregate_releases team_release
          on team_release.id = team_context.release_id
        join curated.builds build
          on build.id = team_context.curated_build_id
         and build.team_key = team_context.team_key
         and build.season = team_context.season
        join curated.team_exposure_denominators exposure
          on exposure.curated_build_id = team_context.curated_build_id
         and exposure.team_key = team_context.team_key
         and exposure.season = team_context.season
        where team_context.release_id = m.team_release_id
          and team_context.team_key = m.team_key
          and team_context.season = c.season
          and team_context.curated_build_id = m.curated_build_id
          and team_context.analysis_view_version = 'v1'
          and (
            team_release.status = 'approved'
            or (
              team_release.status = 'retired'
              and exists (
                select 1 from audit.pipeline_runs source_run
                where source_run.id = team_release.pipeline_run_id
                  and source_run.status = 'succeeded'
              )
            )
          )
          and exposure.match_hours = exposure.matches_played * 20.0
          and exposure.total_hours = exposure.match_hours + exposure.training_hours
          and (
            select count(distinct rows.section)
            from reporting.release_table_rows rows
            where rows.release_id = team_context.release_id
              and rows.section in (
                'headline', 'setting_split', 'monthly', 'body_locations',
                'injury_types', 'severity_distribution'
              )
          ) = 6
      )
  )
  and not exists (
    select 1
    from reporting.league_release_members_v2 m
    where m.release_id = c.release_id
      and not exists (
        select 1
        from reporting.team_dashboard_payloads_v2 payload
        where payload.bundle_release_id = m.release_id
          and payload.team_key = m.team_key
          and payload.team_release_id = m.team_release_id
          and payload.curated_build_id = m.curated_build_id
      )
  )
  and (
    c.season <> '2024-25'
    or (
      select sum(exposure.matches_played) = 302
         and sum(exposure.match_hours) = 6040.0
      from reporting.league_release_members_v2 m
      join curated.team_exposure_denominators exposure
        on exposure.curated_build_id = m.curated_build_id
       and exposure.team_key = m.team_key
       and exposure.season = c.season
      where m.release_id = c.release_id
    )
  )
  and c.release_id = (
    select c2.release_id
    from reporting.league_release_context_v2 c2
    join reporting.aggregate_releases r2 on r2.id = c2.release_id
    where c2.season = c.season and r2.status = 'approved'
    order by r2.approved_at desc nulls last, r2.created_at desc, r2.id desc
    limit 1
  );

comment on view reporting.latest_approved_dashboard_bundle_v2 is
  'Private immutable bundle gate. Superseded successful member releases remain valid only for their already-approved bundle snapshot.';
