insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831123000',
  'urc_2025_26_welsh_fixture_release_context_date',
  array[
    'migration_sha256=19ce1c8db124b96fda83764416dbfb98a241ca16b0dc38cd4705efed642c40ae',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
    'decision_recorded_at=2026-08-31'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831123000'
      and name = 'urc_2025_26_welsh_fixture_release_context_date'
      and statements = array[
        'migration_sha256=19ce1c8db124b96fda83764416dbfb98a241ca16b0dc38cd4705efed642c40ae',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
        'decision_recorded_at=2026-08-31'
      ]
  ) then
    raise exception 'Welsh fixture release context date registration is invalid';
  end if;
end;
$$;
