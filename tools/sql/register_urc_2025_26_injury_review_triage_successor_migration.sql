-- Register the private v3 successor only after all additive objects and the
-- exact accepted rule are installed.

do $$
begin
  if to_regclass('lineage.injury_classification_rules_v3') is null
     or to_regclass('lineage.injury_master_versions_v3') is null
     or to_regclass('lineage.injury_master_rows_v3') is null
     or to_regclass('lineage.injury_inclusion_rows_v3') is null then
    raise exception '2025-26 injury review-triage successor objects are incomplete';
  end if;

  if not exists (
    select 1
    from lineage.injury_classification_rules_v3
    where rule_version = 'urc_2025_26_injury_review_triage_2026_08_30_v5'
      and predecessor_rule_version = 'urc_2025_26_injury_classification_2026_08_29_v2'
      and season = '2025-26'
      and jsonb_array_length(precedence) = 12
      and field_contract ->> 'classification' = 'separate'
      and field_contract ->> 'clinical_duration_days' = 'separate'
      and field_contract ->> 'time_loss_days' = 'separate'
  ) then
    raise exception '2025-26 injury review-triage rule is incomplete';
  end if;

  if has_table_privilege('web_reader', 'lineage.injury_master_versions_v3', 'select')
     or has_table_privilege('web_reader', 'lineage.injury_master_rows_v3', 'select')
     or has_table_privilege('web_reader', 'lineage.injury_inclusion_rows_v3', 'select') then
    raise exception '2025-26 injury review-triage successor crossed the private reader boundary';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values (
  '20260830140000',
  'urc_2025_26_injury_review_triage_successor',
  array[
    'migration_sha256=76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a',
    'classification_rule_version=urc_2025_26_injury_review_triage_2026_08_30_v5',
    'predecessor_version_id=bab7731d-975b-5d49-a34c-6acc6b0c8c94',
    'scope=private_injury_lineage_successor_only'
  ]
)
on conflict (version) do nothing;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20260830140000'
      and name = 'urc_2025_26_injury_review_triage_successor'
      and statements = array[
        'migration_sha256=76598d5843072cf1b4673a1aacdaed907874c402cd6fdd88a2956ccf598cc37a',
        'classification_rule_version=urc_2025_26_injury_review_triage_2026_08_30_v5',
        'predecessor_version_id=bab7731d-975b-5d49-a34c-6acc6b0c8c94',
        'scope=private_injury_lineage_successor_only'
      ]
  ) then
    raise exception '2025-26 injury review-triage migration registration is invalid';
  end if;
end;
$$;
