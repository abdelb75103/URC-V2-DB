do $$
begin
  if (
      select count(*)
      from reporting.team_key_aliases alias
      join reporting.teams team
        on team.team_key = alias.team_key and team.active
      where (alias.alias, alias.team_key, alias.excluded) in (
        ('Cardiff Rugby', 'cardiff', false),
        ('Dragons RFC', 'dragons', false)
      )
    ) <> 2
    or to_regclass(
      'audit.urc_2025_26_fixture_reconciliation_decisions_v1'
    ) is null
    or to_regclass(
      'analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1'
    ) is null
    or to_regclass(
      'analysis.urc_2025_26_injury_fixture_corrected_rows_v2'
    ) is null
    or (
      select count(*) filter (where team_key = 'cardiff') = 19
         and count(*) filter (where team_key = 'dragons') = 42
         and count(*) = 61
      from audit.urc_2025_26_fixture_reconciliation_decisions_v1
    ) is not true
    or exists (
      select 1
      from audit.urc_2025_26_fixture_reconciliation_decisions_v1
      where cohort_view_version <>
          'injury_lineage_2025-26_2026-08-31_v3'
        or evidence_sha256 <>
          'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450'
        or evidence_locator <>
          'docs/evidence/urc_2025_26_welsh_fixture_alias_exact_date_correction.json'
    )
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
    ) <> 1545
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss
    ) <> 938
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss and days_lost is not null
    ) <> 782
    or (
      select coalesce(sum(days_lost), 0)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss
    ) <> 20665
    or has_table_privilege(
      'web_reader',
      'audit.urc_2025_26_fixture_reconciliation_decisions_v1',
      'select'
    )
    or has_table_privilege(
      'web_reader',
      'analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1',
      'select'
    )
    or has_table_privilege(
      'web_reader',
      'analysis.urc_2025_26_injury_fixture_corrected_rows_v2',
      'select'
    )
  then
    raise exception 'Year 2 Welsh exact-date fixture correction is incomplete or crossed the reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260831120000',
  'urc_2025_26_welsh_fixture_alias_correction',
  array[
    'migration_sha256=457ab116338396172393db7156a9c56cd9c77e3a6c6f30ae6a1c6701d4a2d678',
    'decision_version=welsh_fixture_alias_exact_date_2026_08_31_v1',
    'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
    'evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
    'reason_code=fixture_team_alias_exact_date_restoration',
    'restored_cardiff_rows=19',
    'restored_dragons_rows=42',
    'restored_other_team_rows=0'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260831120000'
      and name = 'urc_2025_26_welsh_fixture_alias_correction'
      and statements = array[
        'migration_sha256=457ab116338396172393db7156a9c56cd9c77e3a6c6f30ae6a1c6701d4a2d678',
        'decision_version=welsh_fixture_alias_exact_date_2026_08_31_v1',
        'cohort_view_version=injury_lineage_2025-26_2026-08-31_v3',
        'evidence_sha256=e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
        'reason_code=fixture_team_alias_exact_date_restoration',
        'restored_cardiff_rows=19',
        'restored_dragons_rows=42',
        'restored_other_team_rows=0'
      ]
  ) then
    raise exception 'Year 2 Welsh exact-date fixture correction registration is invalid';
  end if;
end;
$$;
