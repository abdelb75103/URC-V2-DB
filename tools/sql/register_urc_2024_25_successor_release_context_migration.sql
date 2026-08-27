-- Registration is separate from the schema change and fails closed unless
-- both validated constraints include the governed successor version.

do $$
declare
  version_constraint text;
  evidence_constraint text;
begin
  select pg_get_constraintdef(oid)
  into version_constraint
  from pg_constraint
  where conrelid = 'reporting.league_release_context_v2'::regclass
    and conname = 'league_release_context_v2_classification_view_version_check'
    and convalidated;

  select pg_get_constraintdef(oid)
  into evidence_constraint
  from pg_constraint
  where conrelid = 'reporting.league_release_context_v2'::regclass
    and conname = 'league_release_context_v2_classification_evidence'
    and convalidated;

  if position(
    'reporting_classification_2024-25_2026-08-27_v1'
    in coalesce(version_constraint, '')
  ) = 0 or position(
    'reporting_classification_2024-25_2026-08-27_v1'
    in coalesce(evidence_constraint, '')
  ) = 0 then
    raise exception '2024-25 successor release-context constraints are incomplete';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260827150000',
  'urc_2024_25_successor_release_context',
  array[
    'migration_sha256=e3b3538d5da7ccd6c83061293f325054b7a338087386905514bc9e0da0a2fbc3',
    'classification_view_version=reporting_classification_2024-25_2026-08-27_v1'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260827150000'
      and name = 'urc_2024_25_successor_release_context'
      and statements = array[
        'migration_sha256=e3b3538d5da7ccd6c83061293f325054b7a338087386905514bc9e0da0a2fbc3',
        'classification_view_version=reporting_classification_2024-25_2026-08-27_v1'
      ]
  ) then
    raise exception '2024-25 successor release-context registration is invalid';
  end if;
end;
$$;
