do $$
begin
  if (select target_attested from reporting.approved_dashboard_reader_target_v8) is distinct from true
    or (select count(*) from audit.urc_2025_26_injury_to_illness_decisions_v1) <> 24
    or (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1) <> 1521
    or strpos(pg_get_viewdef('reporting.latest_team_dashboard_v7'::regclass),
      'diagnosis_family_team_dashboard_payloads_v3') = 0
  then raise exception 'Injury-to-illness registration precondition failed';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260903010000', 'urc_2025_26_injury_to_illness_reporting',
  array['migration_sha256=dbca0452c7777d169a6b1eb2df8e5a0344591e078cb839cd46dcbfe436260297',
    'scope=24_reviewed_2025_26_problem_type_corrections_reporting_only']
);
