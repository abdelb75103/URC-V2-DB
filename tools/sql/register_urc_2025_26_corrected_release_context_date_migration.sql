do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
        'reporting.league_release_context_v2'::regclass
      and constraint_row.conname =
        'league_release_context_v2_decision_recorded_at_check'
      and pg_get_constraintdef(constraint_row.oid) like
        '%reporting_classification_2025-26_2026-08-31_v3%'
      and pg_get_constraintdef(constraint_row.oid) like '%2026-08-31%'
  ) then
    raise exception 'Corrected Year 2 release context date contract is absent';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831112000',
  'urc_2025_26_corrected_release_context_date',
  array[
    'migration_sha256=a1e4e5d54c0f9092050e2581491f26785c4cf50709c9c960bb31829f3b446d2b',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'decision_recorded_at=2026-08-31'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831112000'
      and name = 'urc_2025_26_corrected_release_context_date'
      and statements = array[
        'migration_sha256=a1e4e5d54c0f9092050e2581491f26785c4cf50709c9c960bb31829f3b446d2b',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'decision_recorded_at=2026-08-31'
      ]
  ) then
    raise exception 'Corrected Year 2 release context date registration is invalid';
  end if;
end;
$$;
