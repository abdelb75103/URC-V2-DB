-- The governed 2024-25 classification successor incorporates the exact served
-- row-correction set. Treat only that tuple and hash as correction-aware while
-- preserving the ordinary-release block for every other release.

create or replace function reporting.guard_active_row_corrections_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, analysis, audit, reporting
as $$
declare
  target_season text;
  successor_is_correction_aware boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status = 'approved' then
      raise exception
        'aggregate releases must be inserted as draft before approval';
    end if;
    return new;
  end if;

  if old.status = 'draft' and new.status = 'approved'
    and not exists (
      select 1
      from reporting.correction_release_context_v1 correction
      where correction.bundle_release_id = new.id
    )
    and not exists (
      select 1
      from reporting.correction_rollback_context_v1 rollback
      where rollback.bundle_release_id = new.id
    ) then
    select context.season,
      context.analysis_version = 'v5'
      and context.classification_view_version =
        'reporting_classification_2024-25_2026-08-27_v1'
      and context.cohort_view_version =
        'analysis_window_2024-25_2026-07-25_v1'
      and audit.row_correction_set_hash_v3(context.season, null) =
        'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'
    into target_season, successor_is_correction_aware
    from reporting.league_release_context_v2 context
    where context.release_id = new.id;

    if target_season is not null
      and not coalesce(successor_is_correction_aware, false)
      and (
        exists (
          select 1
          from analysis.row_correction_served_sets_v1 served
          where served.season = target_season
        )
        or exists (
          select 1
          from audit.correction_sets_v1 pending
          where pending.season = target_season
            and not exists (
              select 1
              from reporting.correction_release_context_v1 promoted
              where promoted.correction_set_id = pending.id
            )
        )
      ) then
      raise exception
        'ordinary release approval blocked while served row corrections are active or a correction is pending';
    end if;
  end if;

  if old.status = 'approved' and new.status = 'retired' then
    select context.season into target_season
    from reporting.dashboard_bundle_context_v1 context
    where context.release_id = old.id;
    if exists (
      select 1
      from analysis.row_correction_served_sets_v1 served
      where served.season = target_season
    ) and not exists (
      select 1
      from reporting.aggregate_releases successor
      join reporting.dashboard_bundle_context_v1 successor_context
        on successor_context.release_id = successor.id
      left join reporting.league_release_context_v2 league_context
        on league_context.release_id = successor.id
      left join reporting.correction_release_context_v1 correction
        on correction.bundle_release_id = successor.id
      left join reporting.correction_rollback_context_v1 rollback
        on rollback.bundle_release_id = successor.id
      where successor.status = 'draft'
        and successor_context.season = target_season
        and (
          correction.bundle_release_id is not null
          or rollback.bundle_release_id is not null
          or (
            league_context.analysis_version = 'v5'
            and league_context.classification_view_version =
              'reporting_classification_2024-25_2026-08-27_v1'
            and league_context.cohort_view_version =
              'analysis_window_2024-25_2026-07-25_v1'
            and audit.row_correction_set_hash_v3(target_season, null) =
              'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'
          )
        )
    ) then
      raise exception
        'ordinary release blocked while served row corrections are active';
    end if;
  end if;
  return new;
end;
$$;
