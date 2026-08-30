-- Register only the reviewed Year 2 problem-type guard. Object, trigger and
-- de-identified evidence checks run before the one migration row is recorded.

do $$
begin
  if to_regclass(
      'analysis.accepted_urc_2025_26_injury_problem_type_successor_v1'
    ) is null
    or to_regclass(
      'analysis.urc_2025_26_injury_cohort_reconciliation_v1'
    ) is null
    or to_regclass(
      'analysis.team_dashboard_release_candidates_analysis_window_v6'
    ) is null
    or to_regprocedure(
      'analysis.reject_active_year2_eligible_unknown_injury_v1()'
    ) is null
  then
    raise exception 'URC 2025-26 injury problem-type guard objects are incomplete';
  end if;

  if (
    select count(*)
    from analysis.accepted_urc_2025_26_injury_problem_type_successor_v1 evidence
    where evidence.rule_version =
        'urc_2025_26_injury_problem_type_successor_v1'
      and evidence.evidence_sha256 =
        '3e857b9ed8192722d22f51ebe32469d230951072705924425e14b6923de1f3fb'
      and evidence.protected_v12_root_manifest_sha256 =
        '01dd17a82ab1835fd84f2c84048b9e15b4072a4f9bca3b3d3a348817a68d7241'
      and evidence.protected_v12_file_set_sha256 =
        '5ea322d4e246510ce82075f5690ea2ac5715dace31ead35bff9db3bacc6a7abd'
      and evidence.conflict_rule = 'clear_illness_evidence_wins'
  ) <> 1 then
    raise exception 'URC 2025-26 injury problem-type evidence is absent or checksum-mismatched';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_trigger trigger_row
    join pg_catalog.pg_class relation on relation.oid = trigger_row.tgrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where not trigger_row.tgisinternal
      and namespace.nspname = 'curated'
      and (
        (relation.relname = 'injuries'
          and trigger_row.tgname =
            'curated_injuries_year2_problem_type_guard_v1')
        or
        (relation.relname = 'builds'
          and trigger_row.tgname =
            'curated_builds_year2_problem_type_guard_v1')
      )
  ) <> 2 then
    raise exception 'URC 2025-26 injury problem-type constraint triggers are incomplete';
  end if;

  if has_table_privilege(
      'web_reader',
      'analysis.accepted_urc_2025_26_injury_problem_type_successor_v1',
      'select'
    )
    or has_table_privilege(
      'web_reader',
      'analysis.urc_2025_26_injury_cohort_reconciliation_v1',
      'select'
    )
  then
    raise exception 'URC 2025-26 injury problem-type audit relations are not least-privilege';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260823150000',
  'urc_2025_26_injury_problem_type_release_guard',
  array['migration_sha256=8411c99e01698610f6f88d321ea49496732a70596bbf123fa7d54dff33fbaabe']
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations migration
    where migration.version = '20260823150000'
      and migration.name =
        'urc_2025_26_injury_problem_type_release_guard'
      and migration.statements = array[
        'migration_sha256=8411c99e01698610f6f88d321ea49496732a70596bbf123fa7d54dff33fbaabe'
      ]
  ) then
    raise exception 'URC 2025-26 injury problem-type guard registration is absent or checksum-mismatched';
  end if;
end;
$$;
