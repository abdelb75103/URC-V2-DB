-- Additive V5 contact-mechanism distribution for the 2024-25 dashboard payloads.
--
-- Adds one new top-level payload key, `contact_distribution`, to the V5 team and
-- league release candidates. Nothing existing is rebuilt: the new payload
-- snapshots inherit the approved coverage-corrected payload and merge a single
-- key into it, and the assertion block below proves that every other section is
-- byte-identical as a jsonb value.
--
-- Source of truth is `curated.injuries.contact_context`, a frozen three-value
-- pipeline derivation. `analysis.analysis_window_injury_cohort_v5_snapshot` does
-- not project it, so it is joined by `injury_id`. The released cohort view is
-- deliberately left unchanged.
--
-- The Unknown mechanism slice is emitted on purpose (Abdel, 26 July 2026). It is
-- a real coverage statement for a mechanism field, not noise. Do not filter it
-- and do not route it through the front-facing unknown suppression used by the
-- other breakdowns.
--
-- League rows pool raw counts across the 16 released teams before any
-- derivation. The `all` setting row is the sum across every setting, so it does
-- not equal match + training: 23 league-wide cases carry an unknown setting.
--
-- OPERATIONAL NOTE (companion change required, not made by this migration):
-- `tools/sql/refresh_analysis_window_v5_candidate_snapshots.sql` must also
-- refresh the two materialised views created here, immediately after it
-- refreshes the coverage payload snapshots. Without that, a later v5 refresh
-- leaves these snapshots holding pre-refresh payloads while the candidate views
-- read from them.

set transaction isolation level repeatable read;

-- 1. Distribution views -------------------------------------------------------

create view
  analysis.analysis_window_contact_distribution_v5
with (security_invoker = true) as
with cohort as (
  select
    cohort.curated_build_id,
    cohort.team_key,
    cohort.season,
    cohort.setting_code,
    injury.contact_context,
    cohort.is_time_loss
  from analysis.analysis_window_injury_cohort_v5_snapshot cohort
  join analysis.league_member_releases_v2 member
    using (curated_build_id, team_key, season)
  join curated.injuries injury on injury.id = cohort.injury_id
), observed as (
  select
    curated_build_id, team_key, season, setting_code, contact_context,
    count(*) as recorded_injuries,
    count(*) filter (where is_time_loss) as time_loss_injuries
  from cohort
  group by curated_build_id, team_key, season, setting_code, contact_context
  union all
  select
    curated_build_id, team_key, season, 'all'::text, contact_context,
    count(*),
    count(*) filter (where is_time_loss)
  from cohort
  group by curated_build_id, team_key, season, contact_context
), setting_domain(setting_code) as (
  values ('all'), ('match'), ('training'), ('unknown')
), contact_domain(contact_context, contact_label) as (
  values ('contact', 'Contact'),
         ('non_contact', 'Non-contact'),
         ('unknown', 'Unknown')
)
select
  member.curated_build_id,
  member.team_key,
  member.season,
  setting_domain.setting_code,
  contact_domain.contact_context,
  contact_domain.contact_label,
  coalesce(observed.recorded_injuries, 0)::bigint as recorded_injuries,
  coalesce(observed.time_loss_injuries, 0)::bigint as time_loss_injuries
from analysis.league_member_releases_v2 member
cross join setting_domain
cross join contact_domain
left join observed
  on observed.curated_build_id = member.curated_build_id
 and observed.team_key = member.team_key
 and observed.season = member.season
 and observed.setting_code = setting_domain.setting_code
 and observed.contact_context = contact_domain.contact_context;

create view
  analysis.analysis_window_league_contact_distribution_v5
with (security_invoker = true) as
select
  season,
  setting_code,
  contact_context,
  contact_label,
  sum(recorded_injuries)::bigint as recorded_injuries,
  sum(time_loss_injuries)::bigint as time_loss_injuries
from analysis.analysis_window_contact_distribution_v5
group by season, setting_code, contact_context, contact_label;

-- 2. Payload snapshot layer ---------------------------------------------------

create materialized view
  analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot as
select
  candidate.team_key,
  candidate.season,
  candidate.team_release_id,
  candidate.curated_build_id,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version,
  candidate.cohort_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'contact_distribution', contact.contact_distribution
  ) as dashboard
from analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot
  candidate
join (
  select
    curated_build_id,
    team_key,
    season,
    jsonb_agg(
      jsonb_build_object(
        'key', contact_context,
        'label', contact_label,
        'setting', setting_code,
        'recorded_injuries', recorded_injuries,
        'time_loss_injuries', time_loss_injuries
      )
      order by
        array_position(
          array['all', 'match', 'training', 'unknown'], setting_code),
        array_position(
          array['contact', 'non_contact', 'unknown'], contact_context)
    ) as contact_distribution
  from analysis.analysis_window_contact_distribution_v5
  group by curated_build_id, team_key, season
) contact using (curated_build_id, team_key, season);

create unique index
  team_dashboard_payload_analysis_window_v5_contact_snapshot_key
  on analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot
  (team_key, season);

create materialized view
  analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot as
select
  candidate.season,
  candidate.classification_view_version,
  candidate.classification_evidence_sha256,
  candidate.cohort_view_version,
  candidate.cohort_evidence_sha256,
  candidate.dashboard || jsonb_build_object(
    'contact_distribution', contact.contact_distribution
  ) as dashboard
from analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot
  candidate
join (
  select
    season,
    jsonb_agg(
      jsonb_build_object(
        'key', contact_context,
        'label', contact_label,
        'setting', setting_code,
        'recorded_injuries', recorded_injuries,
        'time_loss_injuries', time_loss_injuries
      )
      order by
        array_position(
          array['all', 'match', 'training', 'unknown'], setting_code),
        array_position(
          array['contact', 'non_contact', 'unknown'], contact_context)
    ) as contact_distribution
  from analysis.analysis_window_league_contact_distribution_v5
  group by season
) contact using (season);

create unique index
  league_dashboard_payload_analysis_window_v5_contact_snapshot_key
  on analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
  (season);

-- 3. Assertions ---------------------------------------------------------------
--
-- These live in a function, not an inline block, because the snapshots are
-- refreshed later by tools/sql/refresh_analysis_window_v5_candidate_snapshots.sql.
-- A refresh replaces the materialised contents, so assertions that ran only at
-- migration time would guarantee nothing about what is actually promoted. Both
-- the migration below and the refresh script call this one definition, so the
-- two can never drift apart.

create function analysis.assert_contact_distribution_v5_integrity()
returns void
language plpgsql
as $fn$
begin
  if (
    select count(*)
    from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot
    where season = '2024-25'
  ) <> 16 or (
    select count(*)
    from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
    where season = '2024-25'
  ) <> 1 or (
    select count(*)
    from analysis.analysis_window_contact_distribution_v5
    where season = '2024-25'
  ) <> 192 or (
    select count(*)
    from analysis.analysis_window_league_contact_distribution_v5
    where season = '2024-25'
  ) <> 12 then
    raise exception
      'V5 contact snapshots require 16 teams, one league row, 192 team and 12 league distribution rows';
  end if;

  if exists (
    select 1
    from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot
      contact
    join analysis.team_dashboard_payload_analysis_window_v5_coverage_snapshot
      coverage
      using (team_key, season, team_release_id, curated_build_id)
    where contact.dashboard - 'contact_distribution' <> coverage.dashboard
  ) or exists (
    select 1
    from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
      contact
    join analysis.league_dashboard_payload_analysis_window_v5_coverage_snapshot
      coverage
      using (season)
    where contact.dashboard - 'contact_distribution' <> coverage.dashboard
  ) then
    raise exception
      'V5 contact distribution changed a payload section other than contact_distribution';
  end if;

  if exists (
    select 1
    from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot
    where season = '2024-25'
      and (
        classification_view_version <>
          'reporting_classification_2026-07-22_v2'
        or cohort_view_version <>
          'analysis_window_2024-25_2026-07-25_v1'
        or dashboard is null
      )
  ) or exists (
    select 1
    from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
    where season = '2024-25'
      and (
        classification_view_version <>
          'reporting_classification_2026-07-22_v2'
        or cohort_view_version <>
          'analysis_window_2024-25_2026-07-25_v1'
        or dashboard is null
      )
  ) then
    raise exception 'V5 contact snapshots do not match the approved tuple';
  end if;

  -- Every team payload carries the full 12-cell grid, correctly ordered and
  -- labelled, and every league cell equals the pooled sum of the 16 teams.
  if exists (
    select 1
    from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot
    where season = '2024-25'
      and jsonb_array_length(dashboard -> 'contact_distribution') <> 12
  ) or exists (
    select 1
    from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
    where season = '2024-25'
      and jsonb_array_length(dashboard -> 'contact_distribution') <> 12
  ) then
    raise exception
      'V5 contact_distribution payload must contain exactly 12 cells';
  end if;

  if exists (
    select 1
    from (
      select cell.value as cell, cell.position as position
      from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot
        snapshot
      cross join lateral jsonb_array_elements(
        snapshot.dashboard -> 'contact_distribution')
        with ordinality as cell(value, position)
      where snapshot.season = '2024-25'
      union all
      select cell.value, cell.position
      from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
        snapshot
      cross join lateral jsonb_array_elements(
        snapshot.dashboard -> 'contact_distribution')
        with ordinality as cell(value, position)
      where snapshot.season = '2024-25'
    ) cells
    where cells.position <> (
      (array_position(
        array['all', 'match', 'training', 'unknown'],
        cells.cell ->> 'setting') - 1) * 3
      + array_position(
        array['contact', 'non_contact', 'unknown'], cells.cell ->> 'key')
    )
    or (cells.cell ->> 'label') <> case cells.cell ->> 'key'
      when 'contact' then 'Contact'
      when 'non_contact' then 'Non-contact'
      when 'unknown' then 'Unknown'
    end
  ) then
    raise exception
      'V5 contact_distribution cells are mis-ordered or mis-labelled';
  end if;

  if exists (
    select 1
    from (
      select
        cell.value ->> 'setting' as setting_code,
        cell.value ->> 'key' as contact_context,
        sum((cell.value ->> 'recorded_injuries')::bigint) as recorded_injuries,
        sum((cell.value ->> 'time_loss_injuries')::bigint)
          as time_loss_injuries
      from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot
        snapshot
      cross join lateral jsonb_array_elements(
        snapshot.dashboard -> 'contact_distribution') cell
      where snapshot.season = '2024-25'
      group by 1, 2
    ) pooled
    full join (
      select
        cell.value ->> 'setting' as setting_code,
        cell.value ->> 'key' as contact_context,
        (cell.value ->> 'recorded_injuries')::bigint as recorded_injuries,
        (cell.value ->> 'time_loss_injuries')::bigint as time_loss_injuries
      from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
        snapshot
      cross join lateral jsonb_array_elements(
        snapshot.dashboard -> 'contact_distribution') cell
      where snapshot.season = '2024-25'
    ) league using (setting_code, contact_context)
    where pooled.recorded_injuries is distinct from league.recorded_injuries
       or pooled.time_loss_injuries is distinct from league.time_loss_injuries
  ) then
    raise exception
      'V5 league contact_distribution does not equal the pooled 16-team counts';
  end if;

  -- Reconcile back to the source cohort: both the per-setting rows and the
  -- `all` rows must account for every released injury exactly once.
  if (
    select sum(recorded_injuries)
    from analysis.analysis_window_league_contact_distribution_v5
    where season = '2024-25' and setting_code <> 'all'
  ) <> (
    select count(*)
    from analysis.analysis_window_injury_cohort_v5_snapshot cohort
    join analysis.league_member_releases_v2 member
      using (curated_build_id, team_key, season)
    where cohort.season = '2024-25'
  ) or (
    select sum(recorded_injuries)
    from analysis.analysis_window_league_contact_distribution_v5
    where season = '2024-25' and setting_code = 'all'
  ) <> (
    select count(*)
    from analysis.analysis_window_injury_cohort_v5_snapshot cohort
    join analysis.league_member_releases_v2 member
      using (curated_build_id, team_key, season)
    where cohort.season = '2024-25'
  ) or (
    select sum(time_loss_injuries)
    from analysis.analysis_window_league_contact_distribution_v5
    where season = '2024-25' and setting_code = 'all'
  ) <> (
    select count(*)
    from analysis.analysis_window_injury_cohort_v5_snapshot cohort
    join analysis.league_member_releases_v2 member
      using (curated_build_id, team_key, season)
    where cohort.season = '2024-25' and cohort.is_time_loss
  ) then
    raise exception
      'V5 contact distribution does not reconcile to the released injury cohort';
  end if;

  -- Verified live league acceptance numbers, 26 July 2026. If these do not
  -- reproduce exactly, stop: do not adjust the numbers.
  if exists (
    select 1
    from (
      values
        ('all', 'contact', 943, 443),
        ('all', 'non_contact', 565, 280),
        ('all', 'unknown', 150, 62),
        ('match', 'contact', 671, 327),
        ('match', 'non_contact', 153, 85),
        ('match', 'unknown', 69, 25),
        ('training', 'contact', 270, 114),
        ('training', 'non_contact', 406, 191),
        ('training', 'unknown', 66, 33),
        ('unknown', 'contact', 2, 2),
        ('unknown', 'non_contact', 6, 4),
        ('unknown', 'unknown', 15, 4)
    ) as expected (
      setting_code, contact_context, recorded_injuries, time_loss_injuries)
    full join (
      select
        cell.value ->> 'setting' as setting_code,
        cell.value ->> 'key' as contact_context,
        (cell.value ->> 'recorded_injuries')::bigint as recorded_injuries,
        (cell.value ->> 'time_loss_injuries')::bigint as time_loss_injuries
      from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot
        snapshot
      cross join lateral jsonb_array_elements(
        snapshot.dashboard -> 'contact_distribution') cell
      where snapshot.season = '2024-25'
    ) actual using (setting_code, contact_context)
    where expected.recorded_injuries is distinct from actual.recorded_injuries
       or expected.time_loss_injuries is distinct from actual.time_loss_injuries
  ) then
    raise exception
      'V5 league contact_distribution does not reproduce the verified 2026-07-26 acceptance numbers';
  end if;
end;
$fn$;

revoke execute on function
  analysis.assert_contact_distribution_v5_integrity() from public;

do $$
begin
  perform analysis.assert_contact_distribution_v5_integrity();
end;
$$;

-- 4. Repoint the release candidate views --------------------------------------

create or replace view
  analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id,
  'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot;

create or replace view
  analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, 'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot;

-- 5. Object documentation -----------------------------------------------------

comment on function analysis.assert_contact_distribution_v5_integrity() is
  'Full contact_distribution integrity suite: cardinality, byte-equality of every non-contact payload section, approved tuple, 12-cell grid, ordering and labels, league-equals-pooled-teams, source-cohort reconciliation, and the verified 2026-07-26 acceptance numbers. Called by the creating migration and by every candidate snapshot refresh, so a refresh cannot silently weaken what the migration proved.';
comment on view analysis.analysis_window_contact_distribution_v5 is
  'Build-pinned V5 team contact-mechanism counts by setting, including an all-settings row and zero-filled cells; Unknown mechanism is retained by decision (Abdel, 2026-07-26).';
comment on view analysis.analysis_window_league_contact_distribution_v5 is
  'V5 league contact-mechanism counts pooled as raw counts across the 16 released teams before any derivation.';
comment on materialized view
  analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot is
  'V5 team candidates with the additive contact_distribution key merged in; every other payload section is inherited unchanged from the coverage snapshot.';
comment on materialized view
  analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot is
  'V5 league candidate with the additive contact_distribution key merged in; every other payload section is inherited unchanged from the coverage snapshot.';
