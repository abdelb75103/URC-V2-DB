do $$
begin
  if to_regclass('audit.urc_2024_25_exposure_scope_decisions_v1') is null
     or to_regclass('analysis.urc_2024_25_effective_exposure_scope_v1') is null
     or to_regclass('analysis.urc_2024_25_team_dashboard_candidate_v4') is null
     or to_regclass('analysis.urc_2024_25_league_dashboard_candidate_v4') is null
  then
    raise exception '2024-25 exposure-scope successor objects are incomplete';
  end if;

  if (select count(*) from audit.urc_2024_25_exposure_scope_decisions_v1) <> 1238
     or (select count(*) from analysis.urc_2024_25_effective_exposure_scope_v1) <> 63273
  then
    raise exception '2024-25 exposure-scope successor reconciliation is incomplete';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830120000',
  'urc_2024_25_exposure_scope_successor',
  array[
    'migration_sha256=237a9379d93bf0171e5a605ccb76afdb93f302f69951048bfd2f794d200f1305',
    'cohort_view_version=analysis_window_2024-25_2026-08-30_v2',
    'decision_rowset_sha256=672f788e8fea5220fe30a8742eca6b1561a2ad092a545667a5ab50a697fa4086'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260830120000'
      and name = 'urc_2024_25_exposure_scope_successor'
      and statements = array[
        'migration_sha256=237a9379d93bf0171e5a605ccb76afdb93f302f69951048bfd2f794d200f1305',
        'cohort_view_version=analysis_window_2024-25_2026-08-30_v2',
        'decision_rowset_sha256=672f788e8fea5220fe30a8742eca6b1561a2ad092a545667a5ab50a697fa4086'
      ]
  ) then
    raise exception '2024-25 exposure-scope successor registration is invalid';
  end if;
end;
$$;
