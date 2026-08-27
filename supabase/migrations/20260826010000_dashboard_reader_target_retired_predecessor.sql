-- Keep target attestation stable after an immutable successor retires the
-- previously approved correction release. The retained release remains exact
-- target evidence in either lifecycle state.
create or replace view reporting.approved_dashboard_reader_target_v1
with (security_invoker = false, security_barrier = true) as
select (
  current_database() = 'postgres'
  and exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260803163430'
      and migration.name = 'dynamic_row_correction_batch_v7_hardening'
      and migration.statements = array[
        'migration_sha256=859e18440317494eb3936fd80c136a8b8fb2e7b2604141bcf58048aeaf604365'
      ]
  )
  and exists (
    select 1
    from reporting.league_release_context_v2 context
    join reporting.aggregate_releases release on release.id = context.release_id
    join reporting.league_release_payloads_v2 payload on payload.release_id = context.release_id
    where context.release_id = '76ac684a-dc60-4b12-ab78-0a502d284555'::uuid
      and context.season = '2024-25'
      and release.release_label = 'urc-2024-25-v5-4ae722941285-a1'
      and payload.payload_sha256 = '2f4bb3cbe77e1ea1608cf8442419c2d6e11333473ce73d10559532061382fa53'
      and exists (
        select 1
        from reporting.aggregate_releases correction_release
        where correction_release.release_label = 'urc-2024-25-correction-r1122-20260729-a1'
          and correction_release.status in ('approved', 'retired')
      )
  )
) as target_attested;

revoke all on reporting.approved_dashboard_reader_target_v1
  from public, anon, authenticated, web_reader;
grant select on reporting.approved_dashboard_reader_target_v1 to web_reader;

comment on view reporting.approved_dashboard_reader_target_v1 is
  'One boolean least-privilege target attestation for the server-side web reader. Retained immutable correction evidence remains valid after a successor retires it.';

do $$
begin
  if not (select target_attested from reporting.approved_dashboard_reader_target_v1)
    or not has_table_privilege(
      'web_reader',
      'reporting.approved_dashboard_reader_target_v1',
      'select'
    )
  then
    raise exception 'dashboard reader target attestation successor is invalid';
  end if;
end;
$$;
