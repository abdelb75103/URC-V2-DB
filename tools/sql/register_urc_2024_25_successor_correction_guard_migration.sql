-- Register only after the live guard contains the exact governed successor
-- tuple and served correction-set hash.

do $$
declare
  guard_definition text;
begin
  select pg_get_functiondef(
    'reporting.guard_active_row_corrections_v1()'::regprocedure
  ) into guard_definition;

  if position(
    'reporting_classification_2024-25_2026-08-27_v1'
    in guard_definition
  ) = 0 or position(
    'b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051'
    in guard_definition
  ) = 0 then
    raise exception '2024-25 successor correction-aware guard is incomplete';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260827160000',
  'urc_2024_25_successor_correction_guard',
  array[
    'migration_sha256=5d088a059bbd43ae0245b1e018287b0fb06ef44383cfc404b7c40579261ff168',
    'active_correction_set_hash=b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051',
    'classification_view_version=reporting_classification_2024-25_2026-08-27_v1'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260827160000'
      and name = 'urc_2024_25_successor_correction_guard'
      and statements = array[
        'migration_sha256=5d088a059bbd43ae0245b1e018287b0fb06ef44383cfc404b7c40579261ff168',
        'active_correction_set_hash=b83d9ab7cf68d8c1b2239ebcd49cb9de882d91b4db1174d80b3fbcdf7baea051',
        'classification_view_version=reporting_classification_2024-25_2026-08-27_v1'
      ]
  ) then
    raise exception '2024-25 successor correction-guard registration is invalid';
  end if;
end;
$$;
