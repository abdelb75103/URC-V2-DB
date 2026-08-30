-- Register the additive first-valid 2025-26 injury lineage only after its
-- private schema and exact classification successor are installed.

do $$
begin
  if to_regclass('lineage.injury_classification_rules_v2') is null
     or to_regclass('lineage.injury_master_versions_v2') is null
     or to_regclass('lineage.injury_master_rows_v2') is null
     or to_regclass('lineage.injury_inclusion_rows_v2') is null then
    raise exception '2025-26 valid injury lineage objects are incomplete';
  end if;

  if not exists (
    select 1
    from lineage.injury_classification_rules_v2
    where rule_version = 'urc_2025_26_injury_classification_2026_08_29_v2'
      and season = '2025-26'
      and jsonb_array_length(precedence) = 7
      and field_contract ->> 'classification' = 'separate'
      and field_contract ->> 'clinical_duration_days' = 'separate'
      and field_contract ->> 'time_loss_days' = 'separate'
      and field_contract ->> 'participation_restriction_evidence' = 'required'
      and field_contract ->> 'unrestricted_participation_evidence' = 'required'
  ) then
    raise exception '2025-26 classification successor is incomplete';
  end if;

  if has_table_privilege('web_reader', 'lineage.injury_master_versions_v2', 'select')
     or has_table_privilege('web_reader', 'lineage.injury_master_rows_v2', 'select')
     or has_table_privilege('web_reader', 'lineage.injury_inclusion_rows_v2', 'select') then
    raise exception '2025-26 injury lineage crossed the private reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260829230000',
  'urc_2025_26_valid_injury_ingest',
  array[
    'migration_sha256=f4c5e3986e13a0b3b1a2e4dda6759f1cf476095ecb77e38554d1226936eba62b',
    'classification_rule_version=urc_2025_26_injury_classification_2026_08_29_v2',
    'scope=private_injury_lineage_only'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260829230000'
      and name = 'urc_2025_26_valid_injury_ingest'
      and statements = array[
        'migration_sha256=f4c5e3986e13a0b3b1a2e4dda6759f1cf476095ecb77e38554d1226936eba62b',
        'classification_rule_version=urc_2025_26_injury_classification_2026_08_29_v2',
        'scope=private_injury_lineage_only'
      ]
  ) then
    raise exception '2025-26 valid injury migration registration is invalid';
  end if;
end;
$$;
