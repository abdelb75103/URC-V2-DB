do $$
begin
  if to_regclass('analysis.accepted_release_contracts_v2') is null
    or not analysis.release_contract_candidates_available_v1(
      '2025-26', 'v6',
      'reporting_classification_2025-26_2026-08-31_v3',
      'injury_lineage_2025-26_2026-08-30_v2'
    )
    or has_table_privilege(
      'web_reader', 'analysis.accepted_release_contracts_v2', 'select'
    )
  then
    raise exception 'Corrected Year 2 release contract is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831111000',
  'urc_2025_26_corrected_release_contract',
  array[
    'migration_sha256=3a62db419a073a1ffbf433c81db7f7a44f40f69a7ee967c9f49e2a813638e06a',
    'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
    'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
    'release_contract_table=analysis.accepted_release_contracts_v2'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831111000'
      and name = 'urc_2025_26_corrected_release_contract'
      and statements = array[
        'migration_sha256=3a62db419a073a1ffbf433c81db7f7a44f40f69a7ee967c9f49e2a813638e06a',
        'classification_view_version=reporting_classification_2025-26_2026-08-31_v3',
        'cohort_view_version=injury_lineage_2025-26_2026-08-30_v2',
        'release_contract_table=analysis.accepted_release_contracts_v2'
      ]
  ) then
    raise exception 'Corrected Year 2 release contract registration is invalid';
  end if;
end;
$$;
