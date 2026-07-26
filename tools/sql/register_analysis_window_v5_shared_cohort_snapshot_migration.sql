do $$
begin
  if to_regclass(
    'analysis.analysis_window_injury_cohort_v5_snapshot'
  ) is null or to_regclass(
    'analysis.analysis_window_reporting_classification_v5_snapshot'
  ) is null or to_regclass(
    'analysis.analysis_window_effective_exposure_cohort_v5_snapshot'
  ) is null then
    raise exception 'V5 shared cohort snapshot objects are missing';
  end if;
  if position(
    'analysis_window_injury_cohort_v5_snapshot'
    in pg_get_viewdef(
      'analysis.analysis_window_reporting_classification_v5_snapshot'::regclass,
      true
    )
  ) = 0 or position(
    'analysis_window_injury_cohort_v5_snapshot'
    in pg_get_viewdef(
      'analysis.analysis_window_team_summary_v5'::regclass,
      true
    )
  ) = 0 or position(
    'analysis_window_effective_exposure_cohort_v5_snapshot'
    in pg_get_viewdef(
      'analysis.exposure_hours_by_build_analysis_window_v5'::regclass,
      true
    )
  ) = 0 or position(
    'analysis_window_reporting_classification_v5_snapshot'
    in pg_get_viewdef(
      'analysis.analysis_window_effective_injury_profiles_v5'::regclass,
      true
    )
  ) = 0 then
    raise exception 'V5 aggregates are not bound to the shared cohort snapshots';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260726015000',
  'analysis_window_v5_shared_cohort_snapshots',
  null
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260726015000'
      and name = 'analysis_window_v5_shared_cohort_snapshots'
  ) then
    raise exception 'V5 shared cohort snapshot migration tracking is invalid';
  end if;
end;
$$;
