-- Restore only Cardiff and Dragons Match injuries excluded by the Welsh
-- fixture-name mismatch when the injury date equals an accepted URC fixture.
-- Frozen lineage and fixture rows remain unchanged.

insert into reporting.team_key_aliases (alias, team_key, excluded, note) values
  ('Cardiff Rugby', 'cardiff', false, 'Official URC fixture-list spelling.'),
  ('Dragons RFC', 'dragons', false, 'Official URC fixture-list spelling.')
on conflict (alias) do nothing;

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
  ) <> 2 then
    raise exception 'Welsh official fixture aliases are absent, inactive, or conflicting';
  end if;
end;
$$;

insert into audit.reason_codes (code, description) values (
  'fixture_team_alias_exact_date_restoration',
  'Restores a Match injury excluded solely by fixture reconciliation when its date exactly matches the team accepted URC fixture.'
)
on conflict (code) do nothing;

do $$
begin
  if not exists (
    select 1
    from audit.reason_codes
    where code = 'fixture_team_alias_exact_date_restoration'
      and description =
        'Restores a Match injury excluded solely by fixture reconciliation when its date exactly matches the team accepted URC fixture.'
      and active
  ) then
    raise exception 'Welsh fixture correction reason code is absent or conflicting';
  end if;
end;
$$;

create view analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1
with (security_invoker = true) as
with parsed as (
  select master.version_id, master.source_row, master.team_key,
    master.final_master_row_sha256, master.row_values,
    master.exclusion_reason, master.final_classification,
    master.time_loss_days,
    case
      when btrim(master.row_values ->> 'Date Injured') ~
          '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
        and to_char(
          to_date(btrim(master.row_values ->> 'Date Injured'), 'DD/MM/YYYY'),
          'DD/MM/YYYY'
        ) = btrim(master.row_values ->> 'Date Injured')
      then to_date(btrim(master.row_values ->> 'Date Injured'), 'DD/MM/YYYY')
    end as injury_date
  from lineage.injury_master_rows_v3 master
  cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
  where master.version_id = evidence.successor_version_id
    and master.excluded
    and master.exclusion_reason = 'Fixture reconciliation unresolved'
    and lower(btrim(master.row_values ->> 'Problem type')) = 'injury'
    and lower(btrim(master.row_values ->> 'Occasion category')) = 'match'
)
select parsed.version_id, parsed.source_row, parsed.team_key,
  parsed.final_master_row_sha256, parsed.exclusion_reason, parsed.final_classification,
  parsed.time_loss_days, parsed.injury_date,
  fixture.source_row_number as fixture_source_row_number,
  fixture.upstream_match_id
from parsed
join analysis.accepted_urc_fixtures_v6 fixture
  on fixture.season = '2025-26'
 and fixture.match_date = parsed.injury_date
 and parsed.team_key in (fixture.home_team_key, fixture.away_team_key);

revoke all on analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1
  from public, anon, authenticated, web_reader;

create table audit.urc_2025_26_fixture_reconciliation_decisions_v1 (
  version_id uuid not null,
  source_row integer not null,
  team_key text not null references reporting.teams(team_key),
  season text not null check (season = '2025-26'),
  final_master_row_sha256 text not null check (
    final_master_row_sha256 ~ '^[0-9a-f]{64}$'
  ),
  predecessor_exclusion_reason text not null check (
    predecessor_exclusion_reason = 'Fixture reconciliation unresolved'
  ),
  injury_date date not null,
  fixture_source_row_number integer not null,
  upstream_match_id text not null,
  reason_code text not null references audit.reason_codes(code) check (
    reason_code = 'fixture_team_alias_exact_date_restoration'
  ),
  decision_version text not null check (
    decision_version = 'welsh_fixture_alias_exact_date_2026_08_31_v1'
  ),
  cohort_view_version text not null check (
    cohort_view_version = 'injury_lineage_2025-26_2026-08-31_v3'
  ),
  evidence_sha256 text not null check (
    evidence_sha256 =
      'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450'
  ),
  evidence_locator text not null check (
    evidence_locator =
      'docs/evidence/urc_2025_26_welsh_fixture_alias_exact_date_correction.json'
  ),
  decided_by text not null check (decided_by = 'Abdel Babiker'),
  decided_at timestamptz not null check (
    decided_at = timestamptz '2026-08-31 00:00:00+00'
  ),
  created_at timestamptz not null default now(),
  primary key (version_id, source_row),
  foreign key (version_id, source_row)
    references lineage.injury_master_rows_v3(version_id, source_row),
  foreign key (season, fixture_source_row_number)
    references curated.fixtures(season, source_row_number),
  check (team_key in ('cardiff', 'dragons'))
);

alter table audit.urc_2025_26_fixture_reconciliation_decisions_v1
  enable row level security;
revoke all on audit.urc_2025_26_fixture_reconciliation_decisions_v1
  from public, anon, authenticated, web_reader;

create trigger urc_2025_26_fixture_reconciliation_decisions_v1_immutable
before update or delete
on audit.urc_2025_26_fixture_reconciliation_decisions_v1
for each row execute function
  audit.reject_reporting_cohort_rule_adjudication_v3_mutation();

insert into audit.urc_2025_26_fixture_reconciliation_decisions_v1 (
  version_id, source_row, team_key, final_master_row_sha256,
  season, predecessor_exclusion_reason, injury_date, fixture_source_row_number,
  upstream_match_id, reason_code, decision_version, cohort_view_version,
  evidence_sha256, evidence_locator, decided_by, decided_at
)
select candidate.version_id, candidate.source_row, candidate.team_key,
  candidate.final_master_row_sha256, '2025-26', candidate.exclusion_reason,
  candidate.injury_date, candidate.fixture_source_row_number,
  candidate.upstream_match_id,
  'fixture_team_alias_exact_date_restoration',
  'welsh_fixture_alias_exact_date_2026_08_31_v1',
  'injury_lineage_2025-26_2026-08-31_v3',
  'e9bfde5a965bc7921bbe2434088781b68bb837f0ef1b3c1505bd18c8d90a2450',
  'docs/evidence/urc_2025_26_welsh_fixture_alias_exact_date_correction.json',
  'Abdel Babiker', timestamptz '2026-08-31 00:00:00+00'
from analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1 candidate
where candidate.team_key in ('cardiff', 'dragons')
order by candidate.team_key, candidate.source_row;

create view analysis.urc_2025_26_injury_fixture_corrected_rows_v2
with (security_invoker = true) as
with members as (
  select master.team_key, master.source_row, master.row_values,
    master.final_classification, master.time_loss_days
  from lineage.injury_inclusion_rows_v3 inclusion
  join lineage.injury_master_rows_v3 master
    on master.version_id = inclusion.version_id
   and master.source_row = inclusion.source_row
  cross join analysis.accepted_urc_2025_26_injury_successor_evidence_v1 evidence
  where inclusion.version_id = evidence.successor_version_id
    and inclusion.dashboard_eligible

  union all

  select master.team_key, master.source_row, master.row_values,
    master.final_classification, master.time_loss_days
  from audit.urc_2025_26_fixture_reconciliation_decisions_v1 decision
  join lineage.injury_master_rows_v3 master
    on master.version_id = decision.version_id
   and master.source_row = decision.source_row
), parsed as (
  select members.*,
    nullif(btrim(row_values ->> 'Date Injured'), '') as raw_injury_date
  from members
), normalised as (
  select parsed.*,
    case
      when raw_injury_date ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
        and to_char(to_date(raw_injury_date, 'DD/MM/YYYY'), 'DD/MM/YYYY') =
          raw_injury_date
      then to_date(raw_injury_date, 'DD/MM/YYYY')
    end as injury_date,
    case
      when lower(coalesce(row_values ->> 'Occasion category', '')) ~ 'match'
        then 'match'
      when lower(coalesce(row_values ->> 'Occasion category', '')) ~ 'training'
        then 'training'
      else 'unknown'
    end as setting_code,
    case lower(btrim(coalesce(row_values ->> 'Is Contact', '')))
      when 'contact' then 'contact'
      when 'non-contact' then 'non_contact'
      when 'non contact' then 'non_contact'
      else 'unknown'
    end as contact_context,
    coalesce(nullif(regexp_replace(
      lower(btrim(coalesce(row_values ->> 'Body Part', ''))),
      '[^a-z0-9]+', '_', 'g'
    ), ''), 'unknown') as body_location_code,
    coalesce(nullif(regexp_replace(
      lower(btrim(coalesce(row_values ->> 'Injury Tissue Type/s', ''))),
      '[^a-z0-9]+', '_', 'g'
    ), ''), 'unknown') as injury_type_code,
    coalesce(nullif(regexp_replace(
      lower(btrim(coalesce(row_values ->> 'Specific Diagnosis', ''))),
      '[^a-z0-9]+', '_', 'g'
    ), ''), 'unknown') as diagnosis_code
  from parsed
)
select team_key, source_row, injury_date,
  final_classification = 'Time Loss' as is_time_loss,
  time_loss_days as days_lost, setting_code, contact_context,
  body_location_code,
  coalesce(nullif(btrim(row_values ->> 'Body Part'), ''), 'Unknown')
    as body_location_label,
  injury_type_code,
  coalesce(nullif(btrim(row_values ->> 'Injury Tissue Type/s'), ''), 'Unknown')
    as injury_type_label,
  diagnosis_code,
  coalesce(nullif(btrim(row_values ->> 'Specific Diagnosis'), ''), 'Unknown')
    as diagnosis_label,
  case
    when final_classification = 'Medical Attention'
      then 'zero_days_medical_attention_only'
    when time_loss_days is null then 'unknown_or_censored'
    when time_loss_days = 1 then 'one_day'
    when time_loss_days between 2 and 3 then 'two_to_three_days'
    when time_loss_days between 4 and 7 then 'four_to_seven_days'
    when time_loss_days between 8 and 28 then 'eight_to_twenty_eight_days'
    else 'greater_than_twenty_eight_days'
  end as severity_code
from normalised;

revoke all on analysis.urc_2025_26_injury_fixture_corrected_rows_v2
  from public, anon, authenticated, web_reader;

do $$
begin
  if (select count(*) from analysis.urc_2025_26_injury_successor_rows_v1) <> 1484
    or (
      select count(*)
      from analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1
    ) <> 61
    or exists (
      select 1
      from analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1
      where team_key not in ('cardiff', 'dragons')
    )
    or (
      select count(*) filter (where team_key = 'cardiff') = 19
         and count(*) filter (where team_key = 'dragons') = 42
         and count(*) filter (where final_classification = 'Time Loss') = 61
         and count(*) = 61
      from analysis.urc_2025_26_fixture_reconciliation_exact_candidates_v1
    ) is not true
    or (
      select count(*) filter (where team_key = 'cardiff') = 19
         and count(*) filter (where team_key = 'dragons') = 42
         and count(*) = 61
      from audit.urc_2025_26_fixture_reconciliation_decisions_v1
    ) is not true
    or (select count(*) from analysis.urc_2025_26_injury_fixture_corrected_rows_v2) <> 1545
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where is_time_loss
    ) <> 938
    or (
      select count(*)
      from analysis.urc_2025_26_injury_fixture_corrected_rows_v2
      where not is_time_loss
    ) <> 607
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
    or (
      select count(*) filter (where corrected.days_lost is not null) = 51
         and coalesce(sum(corrected.days_lost), 0) = 1618
      from audit.urc_2025_26_fixture_reconciliation_decisions_v1 decision
      join analysis.urc_2025_26_injury_fixture_corrected_rows_v2 corrected
        using (team_key, source_row)
    ) is not true
    or exists (
      select 1
      from audit.urc_2025_26_fixture_reconciliation_decisions_v1 decision
      join analysis.urc_2025_26_injury_fixture_corrected_rows_v2 corrected
        using (team_key, source_row)
      where corrected.injury_date <> decision.injury_date
        or corrected.setting_code <> 'match'
        or not corrected.is_time_loss
    )
  then
    raise exception 'Welsh exact-date fixture correction does not match the reviewed 19/42 row set';
  end if;
end;
$$;
