-- Analysis-window V5 reporting successor, 2024-25 only.
--
-- Dependency map
-- ==============
-- * Reuses analysis.lineage_included_rows_v1 and
--   lineage.master_source_bridge because the reviewed master-plus-ledger
--   lineage is window-independent.
-- * Reuses analysis.lineage_reporting_classification_v1 only as the frozen
--   classification mapping for the V5 subset. The V5 classification view
--   joins that mapping back to the V5 injury cohort, so no pre-window injury
--   can enter a V5 metric through this dependency.
-- * Reads curated.exposure and ingestion.source_rows to expose historical
--   eligibility beside effective V5 eligibility without changing curated rows.
-- * Reads curated.fixtures for the frozen fixture-derived match denominator,
--   and analysis.league_member_releases_v2 for the approved 16-team build set.
-- * Reuses reporting.latest_team_dashboard and
--   analysis.league_dashboard_payload_v2 only for immutable descriptive
--   coverage/prior-season fields. Every V5 cohort-derived metric below comes
--   from an analysis_window_*_v5 successor.
-- * Supersedes neither V1-V4 views nor their payloads. The direct V5 candidate
--   views avoid the historical UNION candidate chain, just as the V4 fast path
--   does for V4.
--
-- Rollback is reporting-tuple re-promotion, not DDL reversal: retain this
-- additive migration and re-promote the accepted V4 tuple
-- (v4 / reporting_classification_2026-07-22_v2 /
-- lineage_2024-25_2026-07-24_v1). V4 views and candidates stay available.

insert into audit.reason_codes (code, description) values
  (
    'league_dashboard_release_v5',
    'Immutable 16-team league dashboard release from the accepted 2024-25 analysis-window V5 cohort.'
  )
on conflict (code) do nothing;

alter table audit.reporting_cohort_rule_adjudications_v3
  drop constraint reporting_cohort_rule_adjudications_v3_migration_version_check,
  add constraint reporting_cohort_rule_adjudications_v3_migration_version_check check (
    migration_version in ('20260720170000', '20260724181000', '20260725190000')
  );

-- This is a new immutable identity. No prior window row is updated.
insert into analysis.reporting_season_windows_v3
  (cohort_view_version, season, season_start, season_end, decision_ref)
values (
  'analysis_window_2024-25_2026-07-25_v1',
  '2024-25',
  date '2024-09-01',
  date '2025-06-30',
  'ANALYSIS-WINDOW-01'
);

insert into audit.reporting_cohort_rule_adjudications_v3
  (adjudication_ref, cohort_view_version, season, decision, evidence_sha256,
   evidence_locator, reviewer, migration_version, decided_at)
values (
  'ANALYSIS-WINDOW-01',
  'analysis_window_2024-25_2026-07-25_v1',
  '2024-25',
  '{
    "exposure_rule":"effective row-level cohort: readmit only rows whose sole historical exclusion is outside_official_analysis_window, preserve all non-window exclusions, use weekly start through start plus six days, and exclude only proven pre-URC match/friendly activity from 1 to 19 September",
    "fixture_rule":"registered fixtures inside the immutable reporting window multiplied by 20 player-hours per team participation",
    "injury_rule":"reviewed master-plus-ledger lineage; dated injuries must fall inside the immutable window while season-attributed undated injuries remain outside monthly plots only",
    "pre_urc_sharks_rule":"verified Sharks Currie Cup match sessions dated 2024-09-08 and 2024-09-14 are excluded from the newly opened exposure band",
    "window_rule":"inclusive 2024-09-01 through 2025-06-30; no injury or exposure re-clean, re-ingest, or curated-build mutation"
  }'::jsonb,
  'c9530c949c60ff4abe91753571dfed6dd9d1146f33cc466dfbbc7fdeddb8443d',
  'docs/evidence/analysis_window_2024-25_v5.json',
  'Abdel Babiker',
  '20260725190000',
  timestamptz '2026-07-25 00:00:00+00'
);

create view analysis.accepted_analysis_window_cohort_rules_v5
with (security_invoker = true) as
select r.cohort_view_version, r.season,
  encode(digest(convert_to(jsonb_agg(jsonb_build_object(
    'adjudication_ref', r.adjudication_ref,
    'decision', r.decision,
    'evidence_sha256', r.evidence_sha256,
    'evidence_locator', r.evidence_locator,
    'reviewer', r.reviewer,
    'migration_version', r.migration_version
  ) order by r.adjudication_ref)::text, 'UTF8'), 'sha256'), 'hex')
    as cohort_evidence_sha256
from audit.reporting_cohort_rule_adjudications_v3 r
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = r.cohort_view_version
 and w.season = r.season
 and w.decision_ref = r.adjudication_ref
where r.adjudication_ref = 'ANALYSIS-WINDOW-01'
  and r.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
  and r.reviewer = 'Abdel Babiker'
  and r.evidence_sha256 =
    'c9530c949c60ff4abe91753571dfed6dd9d1146f33cc466dfbbc7fdeddb8443d'
  and r.evidence_locator = 'docs/evidence/analysis_window_2024-25_v5.json'
  and r.migration_version = '20260725190000'
  and r.decision = '{
    "exposure_rule":"effective row-level cohort: readmit only rows whose sole historical exclusion is outside_official_analysis_window, preserve all non-window exclusions, use weekly start through start plus six days, and exclude only proven pre-URC match/friendly activity from 1 to 19 September",
    "fixture_rule":"registered fixtures inside the immutable reporting window multiplied by 20 player-hours per team participation",
    "injury_rule":"reviewed master-plus-ledger lineage; dated injuries must fall inside the immutable window while season-attributed undated injuries remain outside monthly plots only",
    "pre_urc_sharks_rule":"verified Sharks Currie Cup match sessions dated 2024-09-08 and 2024-09-14 are excluded from the newly opened exposure band",
    "window_rule":"inclusive 2024-09-01 through 2025-06-30; no injury or exposure re-clean, re-ingest, or curated-build mutation"
  }'::jsonb
group by r.cohort_view_version, r.season
having count(*) = 1;

-- A V5 subset of the accepted master-plus-ledger cohort. Undated
-- season-attributed injuries remain intentionally eligible for totals.
create view analysis.analysis_window_injury_cohort_v5
with (security_invoker = true) as
select
  i.id as injury_id, b.curated_build_id, b.team_key, r.season,
  b.source_row_id, r.source_row, parsed.date_injured,
  coalesce(parsed.parsed_days, 0)::numeric as days_lost,
  coalesce(parsed.parsed_days, 0) > 0 as is_time_loss,
  case trim(r.final_values ->> 'Occasion category')
    when 'Match' then 'match'
    when 'Training' then 'training'
    else 'unknown'
  end as setting_code,
  coalesce(i.body_location, 'unknown') as body_location_code,
  coalesce(bl.label, 'Unknown') as body_location_label,
  coalesce(i.injury_type, 'unknown') as injury_type_code,
  coalesce(it.label, 'Unknown') as injury_type_label,
  case
    when parsed.parsed_days is null then 'unknown_or_censored'
    when parsed.parsed_days = 0 then 'zero_days_medical_attention_only'
    when parsed.parsed_days = 1 then 'one_day'
    when parsed.parsed_days between 2 and 3 then 'two_to_three_days'
    when parsed.parsed_days between 4 and 7 then 'four_to_seven_days'
    when parsed.parsed_days between 8 and 28 then 'eight_to_twenty_eight_days'
    when parsed.parsed_days > 28 then 'greater_than_twenty_eight_days'
    else 'unknown_or_censored'
  end as severity_code,
  case
    when parsed.parsed_days is null then 'Unknown or censored'
    when parsed.parsed_days = 0 then 'Medical attention'
    when parsed.parsed_days = 1 then '1 day'
    when parsed.parsed_days between 2 and 3 then '2-3 days'
    when parsed.parsed_days between 4 and 7 then '4-7 days'
    when parsed.parsed_days between 8 and 28 then '8-28 days'
    when parsed.parsed_days > 28 then '>28 days'
    else 'Unknown or censored'
  end as severity_label,
  parsed.date_injured is null as is_undated,
  w.cohort_view_version
from analysis.lineage_included_rows_v1 r
join lineage.master_source_bridge b using (season, source_row)
join curated.injuries i on i.id = b.injury_id
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
 and w.season = r.season
join analysis.accepted_analysis_window_cohort_rules_v5 rule
  on rule.cohort_view_version = w.cohort_view_version
 and rule.season = w.season
left join curated.code_lists bl
  on bl.list_name = 'body_location'
 and bl.code = coalesce(i.body_location, 'unknown')
left join curated.code_lists it
  on it.list_name = 'injury_type'
 and it.code = coalesce(i.injury_type, 'unknown')
cross join lateral (
  select
    case
      when trim(r.final_values ->> 'Date Injured') ~ '^\d{2}/\d{2}/\d{4}$'
        then to_date(trim(r.final_values ->> 'Date Injured'), 'DD/MM/YYYY')
      else null
    end as date_injured,
    case
      when trim(r.final_values ->> 'Days Injured') ~ '^\d+(\.0+)?$'
        then trim(r.final_values ->> 'Days Injured')::numeric
      else null
    end as parsed_days
) parsed
where trim(r.final_values ->> 'Problem type') = 'Injury'
  and (
    parsed.date_injured is null
    or parsed.date_injured between w.season_start and w.season_end
  );

-- The clinical classification rule is window-independent. This successor
-- reuses only the accepted mapping for V5 injury IDs, never the V4 cohort.
create view analysis.analysis_window_reporting_classification_v5
with (security_invoker = true) as
select c.*
from analysis.lineage_reporting_classification_v1 c
join analysis.analysis_window_injury_cohort_v5 v5
  on v5.injury_id = c.injury_id
 and v5.curated_build_id = c.curated_build_id
 and v5.team_key = c.team_key
 and v5.season = c.season;

-- First-class effective exposure cohort. Historical curated state remains
-- untouched. A row may be readmitted only if the former window reason was its
-- sole historical reason and its native reporting period overlaps V5.
create view analysis.analysis_window_effective_exposure_cohort_v5
with (security_invoker = true) as
with window_rule as (
  select w.cohort_view_version, w.season, w.season_start, w.season_end
  from analysis.reporting_season_windows_v3 w
  join analysis.accepted_analysis_window_cohort_rules_v5 accepted
    on accepted.cohort_view_version = w.cohort_view_version
   and accepted.season = w.season
  where w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
), source_rows as (
  select
    e.id as exposure_id,
    e.source_row_id,
    e.curated_build_id,
    e.team_key,
    e.season,
    e.grain,
    e.session_date,
    e.week_start_date,
    e.minutes_clean,
    e.distance_m_clean,
    e.scope_status,
    e.eligibility_status as historical_eligibility_status,
    e.exclusion_reasons as historical_exclusion_reasons,
    coalesce(e.session_date, e.week_start_date) as effective_period_start,
    coalesce(e.session_date, e.week_start_date)
      + case when e.grain = 'weekly' then 6 else 0 end as effective_period_end,
    lower(trim(concat_ws(' ',
      nullif(sr.source_values ->> 'Competition', ''),
      nullif(sr.source_values ->> 'session type', ''),
      nullif(sr.source_values ->> 'Session Type', ''),
      nullif(sr.source_values ->> 'Training Type', ''),
      nullif(sr.source_values ->> 'Training With', ''),
      nullif(sr.source_values ->> 'If match, surface?', ''),
      nullif(sr.source_values ->> 'Description', ''),
      nullif(sr.source_values ->> 'Notes', '')
    ))) as source_scope_text
  from curated.exposure e
  join ingestion.source_rows sr on sr.id = e.source_row_id
), period_status as (
  select s.*, w.cohort_view_version, w.season_start, w.season_end,
    (
      s.effective_period_start is not null
      and s.effective_period_start <= w.season_end
      and s.effective_period_end >= w.season_start
    ) as period_overlaps_window,
    (
      s.historical_eligibility_status = 'excluded_from_primary'
      and cardinality(s.historical_exclusion_reasons) = 1
      and s.historical_exclusion_reasons[1] =
        'outside_official_analysis_window'
    ) as is_sole_window_historical_exclusion
  from source_rows s
  join window_rule w on w.season = s.season
), semantic_status as (
  select p.*,
    (
      p.effective_period_start <= date '2024-09-19'
      and p.effective_period_end >= date '2024-09-01'
    ) as overlaps_pre_urc_band,
    (
      p.source_scope_text ~
        '(^|[^[:alnum:]])(friendly|fixture|opposition|opponent|vs|versus|currie[[:space:]-]*cup)([^[:alnum:]]|$)'
      or (
        p.source_scope_text ~ '(^|[^[:alnum:]])match([^[:alnum:]]|$)'
        and p.source_scope_text !~
          '(warm[[:space:]-]*up|top[[:space:]-]*up|captain.?s[[:space:]-]*run|game[[:space:]-]*[0-9]+)'
      )
      or p.source_scope_text ~
        '(^|[^[:alnum:]])game[[:space:]]*\([^)]*[[:alpha:]][^)]*\)'
      or (
        p.team_key = 'sharks'
        and p.effective_period_start in (date '2024-09-08', date '2024-09-14')
      )
    ) as has_definite_pre_urc_match_evidence
  from period_status p
), effective as (
  select s.*,
    (
      s.is_sole_window_historical_exclusion
      and s.period_overlaps_window
      and s.overlaps_pre_urc_band
      and s.has_definite_pre_urc_match_evidence
    ) as rejected_by_pre_urc_match_rule,
    case
      when not (
        s.is_sole_window_historical_exclusion
        and s.period_overlaps_window
        and s.overlaps_pre_urc_band
        and s.has_definite_pre_urc_match_evidence
      ) then null
      when s.team_key = 'sharks'
        and s.effective_period_start in (date '2024-09-08', date '2024-09-14')
        then 'verified_currie_cup_match'
      when s.source_scope_text ~
        '(^|[^[:alnum:]])friendly([^[:alnum:]]|$)'
        then 'explicit_friendly'
      when s.source_scope_text ~
        '(^|[^[:alnum:]])(fixture|opposition|opponent|vs|versus)([^[:alnum:]]|$)'
        then 'explicit_opponent_fixture'
      when s.source_scope_text ~
        '(^|[^[:alnum:]])currie[[:space:]-]*cup([^[:alnum:]]|$)'
        then 'semantic_non_urc_match'
      when s.source_scope_text ~ '(^|[^[:alnum:]])match([^[:alnum:]]|$)'
        and s.source_scope_text !~
          '(warm[[:space:]-]*up|top[[:space:]-]*up|captain.?s[[:space:]-]*run|game[[:space:]-]*[0-9]+)'
        then 'explicit_match'
      when s.source_scope_text ~
        '(^|[^[:alnum:]])game[[:space:]]*\([^)]*[[:alpha:]][^)]*\)'
        then 'semantic_non_urc_match'
      else null
    end as pre_urc_match_evidence_class,
    (
      s.period_overlaps_window
      and s.historical_eligibility_status = 'excluded_from_primary'
      and s.is_sole_window_historical_exclusion
      and 'outside_official_analysis_window' = any(s.historical_exclusion_reasons)
    ) as outside_official_analysis_window_removed
  from semantic_status s
), classified as (
  select e.*,
    case
      when e.rejected_by_pre_urc_match_rule then
        array['pre_urc_non_urc_match_or_friendly']::text[]
      when not e.period_overlaps_window then
        case
          when 'outside_official_analysis_window' = any(
            e.historical_exclusion_reasons
          ) then e.historical_exclusion_reasons
          else array_append(
            e.historical_exclusion_reasons,
            'outside_official_analysis_window'
          )
        end
      when e.historical_eligibility_status = 'included_pending_protocol'
        then '{}'::text[]
      when e.is_sole_window_historical_exclusion then '{}'::text[]
      else e.historical_exclusion_reasons
    end as effective_exclusion_reasons
  from effective e
)
select
  exposure_id,
  source_row_id,
  source_row_id as stable_source_row_id,
  curated_build_id,
  exists (
    select 1
    from analysis.league_member_releases_v2 member
    where member.curated_build_id = classified.curated_build_id
      and member.team_key = classified.team_key
      and member.season = classified.season
  ) as approved_member_build,
  team_key,
  team_key as team,
  season,
  grain as reporting_grain,
  effective_period_start,
  effective_period_start as period_start,
  effective_period_end,
  effective_period_end as period_end,
  minutes_clean,
  minutes_clean / 60 as exposure_hours,
  distance_m_clean,
  scope_status,
  historical_eligibility_status,
  historical_exclusion_reasons,
  effective_status.value as effective_eligibility_status,
  effective_status.value as effective_v5_eligibility_status,
  effective_exclusion_reasons,
  effective_exclusion_reasons as effective_v5_exclusion_reasons,
  outside_official_analysis_window_removed,
  rejected_by_pre_urc_match_rule,
  rejected_by_pre_urc_match_rule as pre_urc_match_rule_rejected,
  pre_urc_match_evidence_class,
  case when rejected_by_pre_urc_match_rule then source_scope_text else null end
    as pre_urc_match_evidence_value,
  period_overlaps_window,
  cohort_view_version,
  'analysis_window_v5_effective_row_cohort'::text as rule_basis,
  'analysis_window_v5_effective_row_cohort'::text as rule_basis_code
from classified
cross join lateral (
  select case
    when period_overlaps_window
      and not rejected_by_pre_urc_match_rule
      and (
        historical_eligibility_status = 'included_pending_protocol'
        or is_sole_window_historical_exclusion
      ) then 'included_pending_protocol'
    else 'excluded_from_primary'
  end as value
) effective_status;

create view analysis.exposure_hours_by_build_analysis_window_v5
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season,
    coalesce(sum(e.minutes_clean), 0) / 60 as total_hours,
    case when count(distinct e.reporting_grain) = 1
      then min(e.reporting_grain) else 'mixed' end as exposure_grain
  from analysis.analysis_window_effective_exposure_cohort_v5 e
  where e.effective_eligibility_status = 'included_pending_protocol'
  group by e.curated_build_id, e.team_key, e.season
), fixtures as (
  select f.season, teams.team_key, count(*)::integer as matches_played
  from curated.fixtures f
  join analysis.reporting_season_windows_v3 w
    on w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
   and w.season = f.season
  join analysis.accepted_analysis_window_cohort_rules_v5 accepted
    on accepted.cohort_view_version = w.cohort_view_version
   and accepted.season = w.season
  cross join lateral (values (f.home_team_key), (f.away_team_key))
    teams(team_key)
  where f.match_date between w.season_start and w.season_end
  group by f.season, teams.team_key
)
select e.curated_build_id, e.team_key, e.season,
  coalesce(f.matches_played, 0) as matches_played,
  coalesce(f.matches_played, 0) * 20.0 as match_hours,
  e.total_hours - coalesce(f.matches_played, 0) * 20.0 as training_hours,
  e.total_hours,
  e.exposure_grain,
  'analysis_window_v5_effective_exposure_and_registered_fixtures'::text
    as method_note
from exposure e
left join fixtures f using (team_key, season);

create view analysis.analysis_window_team_summary_v5
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days
from analysis.analysis_window_injury_cohort_v5 c
group by c.curated_build_id, c.team_key, c.season;

create view analysis.analysis_window_setting_split_v5
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season, c.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.analysis_window_injury_cohort_v5 c
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season, c.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create view analysis.analysis_window_injury_profiles_v5
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from analysis.analysis_window_injury_cohort_v5 c
  cross join lateral (values
    ('body_location'::text, c.body_location_code, c.body_location_label),
    ('injury_type'::text, c.injury_type_code, c.injury_type_label),
    ('injury_profile'::text,
      c.body_location_code || '__' || c.injury_type_code,
      c.body_location_label || ' · ' || c.injury_type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create view analysis.analysis_window_effective_injury_profiles_v5
with (security_invoker = true) as
with labelled as (
  select c.*,
    coalesce(bl.label,
      initcap(replace(c.effective_body_location_code, '_', ' '))) as body_label,
    coalesce(it.label,
      initcap(replace(c.effective_injury_type_code, '_', ' '))) as type_label
  from analysis.analysis_window_reporting_classification_v5 c
  left join curated.code_lists bl
    on bl.list_name = 'body_location'
   and bl.code = c.effective_body_location_code
  left join curated.code_lists it
    on it.list_name = 'injury_type'
   and it.code = c.effective_injury_type_code
), grouped as (
  select c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code,
    count(*) as time_loss_injuries, sum(c.days_lost) as days_lost
  from labelled c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  cross join lateral (values
    ('body_location'::text, c.effective_body_location_code, c.body_label),
    ('injury_type'::text, c.effective_injury_type_code, c.type_label),
    ('injury_profile'::text,
      c.effective_body_location_code || '__' || c.effective_injury_type_code,
      c.body_label || ' · ' || c.type_label)
  ) d(dimension, code, label)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    d.dimension, d.code, d.label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create view analysis.analysis_window_diagnosis_profiles_v5
with (security_invoker = true) as
with grouped as (
  select c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code as code, c.diagnosis_label as label,
    s.setting_code, count(*) as time_loss_injuries,
    sum(c.days_lost) as days_lost
  from analysis.analysis_window_reporting_classification_v5 c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  cross join lateral (values ('all'::text), (c.setting_code)) s(setting_code)
  where c.is_time_loss
  group by c.curated_build_id, c.team_key, c.season,
    c.diagnosis_code, c.diagnosis_label, s.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then e.total_hours
    when 'match' then e.match_hours
    when 'training' then e.training_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then e.total_hours
      when 'match' then e.match_hours
      when 'training' then e.training_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.exposure_hours_by_build_analysis_window_v5 e
  using (curated_build_id, team_key, season);

create view analysis.analysis_window_monthly_v5
with (security_invoker = true) as
with exposure as (
  select e.curated_build_id, e.team_key, e.season,
    date_trunc('month', e.effective_period_start)::date as month_start,
    sum(e.minutes_clean) / 60 as exposure_hours,
    sum(e.distance_m_clean) / 1000 as distance_km
  from analysis.analysis_window_effective_exposure_cohort_v5 e
  where e.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
    and e.effective_eligibility_status = 'included_pending_protocol'
  group by e.curated_build_id, e.team_key, e.season,
    date_trunc('month', e.effective_period_start)
), injuries as (
  select curated_build_id, team_key, season,
    date_trunc('month', date_injured)::date as month_start,
    count(*) filter (where is_time_loss) as time_loss_injuries,
    coalesce(sum(days_lost) filter (where is_time_loss), 0) as days_lost
  from analysis.analysis_window_injury_cohort_v5
  where cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
    and date_injured is not null
  group by curated_build_id, team_key, season, date_trunc('month', date_injured)
), months as (
  select curated_build_id, team_key, season, month_start from exposure
  union
  select curated_build_id, team_key, season, month_start from injuries
)
select m.curated_build_id, m.team_key, m.season, m.month_start,
  to_char(m.month_start, 'Mon YYYY') as month_label,
  coalesce(e.exposure_hours, 0) as exposure_hours,
  coalesce(e.distance_km, 0) as distance_km,
  coalesce(i.time_loss_injuries, 0) as time_loss_injuries,
  coalesce(i.days_lost, 0) as days_lost,
  analysis.rate_per_1000_v1(coalesce(i.time_loss_injuries, 0),
    coalesce(e.exposure_hours, 0)) as incidence_per_1000h,
  analysis.rate_per_1000_v1(coalesce(i.days_lost, 0),
    coalesce(e.exposure_hours, 0)) as burden_per_1000h
from months m
left join exposure e using (curated_build_id, team_key, season, month_start)
left join injuries i using (curated_build_id, team_key, season, month_start);

create view analysis.analysis_window_severity_distribution_v5
with (security_invoker = true) as
select c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  case c.severity_code
    when 'zero_days_medical_attention_only' then 0
    when 'one_day' then 1
    when 'two_to_three_days' then 2
    when 'four_to_seven_days' then 3
    when 'eight_to_twenty_eight_days' then 4
    when 'greater_than_twenty_eight_days' then 5
    else 6
  end as band_order
from analysis.analysis_window_injury_cohort_v5 c
group by c.curated_build_id, c.team_key, c.season,
  c.severity_code, c.severity_label;

create view analysis.analysis_window_league_summary_v5
with (security_invoker = true) as
with cohort as (
  select c.*
  from analysis.analysis_window_injury_cohort_v5 c
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
), exposure as (
  select e.season,
    sum(e.total_hours) as exposure_hours,
    sum(e.match_hours) as match_exposure_hours,
    sum(e.training_hours) as training_exposure_hours
  from analysis.exposure_hours_by_build_analysis_window_v5 e
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by e.season
)
select c.season,
  count(*) as recorded_injuries,
  count(*) filter (where c.is_time_loss) as time_loss_injuries,
  coalesce(sum(c.days_lost) filter (where c.is_time_loss), 0) as days_lost,
  avg(c.days_lost) filter (where c.is_time_loss) as mean_severity_days,
  percentile_cont(0.5) within group (order by c.days_lost)
    filter (where c.is_time_loss) as median_severity_days,
  e.exposure_hours,
  e.match_exposure_hours,
  e.training_exposure_hours
from cohort c
join exposure e using (season)
group by c.season, e.exposure_hours,
  e.match_exposure_hours, e.training_exposure_hours;

create view analysis.analysis_window_league_setting_split_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_setting_split_v5 x
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by x.season, x.setting_code
)
select g.*,
  case g.setting_code
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create view analysis.analysis_window_league_injury_profiles_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_injury_profiles_v5 x
  join analysis.league_member_releases_v2 m
    using (curated_build_id, team_key, season)
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create view analysis.analysis_window_league_effective_injury_profiles_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.dimension, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_effective_injury_profiles_v5 x
  group by x.season, x.dimension, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create view analysis.analysis_window_league_diagnosis_profiles_v5
with (security_invoker = true) as
with grouped as (
  select x.season, x.code, x.label, x.setting_code,
    sum(x.time_loss_injuries) as time_loss_injuries,
    sum(x.days_lost) as days_lost
  from analysis.analysis_window_diagnosis_profiles_v5 x
  group by x.season, x.code, x.label, x.setting_code
)
select g.*,
  case g.setting_code
    when 'all' then h.exposure_hours
    when 'match' then h.match_exposure_hours
    when 'training' then h.training_exposure_hours
    else null
  end as exposure_hours,
  analysis.rate_per_1000_v1(g.time_loss_injuries,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as incidence_per_1000h,
  analysis.rate_per_1000_v1(g.days_lost,
    case g.setting_code
      when 'all' then h.exposure_hours
      when 'match' then h.match_exposure_hours
      when 'training' then h.training_exposure_hours
      else null
    end) as burden_per_1000h,
  g.days_lost::numeric / nullif(g.time_loss_injuries, 0)
    as mean_severity_days
from grouped g
join analysis.analysis_window_league_summary_v5 h using (season);

create view analysis.analysis_window_league_monthly_v5
with (security_invoker = true) as
select x.season, x.month_start, x.month_label,
  sum(x.exposure_hours) as exposure_hours,
  sum(x.distance_km) as distance_km,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  analysis.rate_per_1000_v1(sum(x.time_loss_injuries), sum(x.exposure_hours))
    as incidence_per_1000h,
  analysis.rate_per_1000_v1(sum(x.days_lost), sum(x.exposure_hours))
    as burden_per_1000h
from analysis.analysis_window_monthly_v5 x
join analysis.league_member_releases_v2 m
  using (curated_build_id, team_key, season)
group by x.season, x.month_start, x.month_label;

create view analysis.analysis_window_league_severity_distribution_v5
with (security_invoker = true) as
select x.season, x.severity_code, x.severity_label,
  sum(x.recorded_injuries) as recorded_injuries,
  sum(x.time_loss_injuries) as time_loss_injuries,
  sum(x.days_lost) as days_lost,
  min(x.band_order) as band_order
from analysis.analysis_window_severity_distribution_v5 x
join analysis.league_member_releases_v2 m
  using (curated_build_id, team_key, season)
group by x.season, x.severity_code, x.severity_label;

create view analysis.team_dashboard_payload_analysis_window_v5
with (security_invoker = true) as
with body as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from analysis.analysis_window_effective_injury_profiles_v5 p
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), types as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.analysis_window_effective_injury_profiles_v5 p
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.curated_build_id, p.team_key, p.season
), profile_rows as (
  select p.curated_build_id, p.team_key, p.season, p.dimension,
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from analysis.analysis_window_effective_injury_profiles_v5 p
  union all
  select p.curated_build_id, p.team_key, p.season, 'diagnosis',
    p.code, p.label, p.setting_code, p.time_loss_injuries, p.days_lost,
    p.exposure_hours, p.incidence_per_1000h, p.burden_per_1000h,
    p.mean_severity_days
  from analysis.analysis_window_diagnosis_profiles_v5 p
), profiles as (
  select p.curated_build_id, p.team_key, p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code) as docs
  from profile_rows p
  group by p.curated_build_id, p.team_key, p.season
)
select m.team_key, m.season, m.team_release_id, m.curated_build_id,
  rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', m.generated_at,
    'team', d.team,
    'season', m.season,
    'analysis_window', jsonb_build_object(
      'start', w.season_start,
      'end', w.season_end,
      'basis', 'Immutable 2024-25 reporting window with effective row-level exposure eligibility.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.',
      'Match exposure = registered fixtures in the reporting window × 15 players × 80 minutes / 60 per team.',
      'Training exposure = effective included exposure in the reporting window minus fixture-derived match exposure.',
      'IOC-aligned body-location and tissue/pathology categories use the accepted mappings.',
      'Injury rows and values are restated from the reviewed 2024-25 master workbook and its ordered decision ledger.'
    ),
    'coverage',
      (coalesce(d.coverage, '{}'::jsonb) - 'injury_cohort_filters')
      || jsonb_build_object(
        'hours', e.total_hours,
        'match_hours', e.match_hours,
        'training_hours', e.training_hours,
        'exposure_grain', e.exposure_grain,
        'included_exposure_status', 'included',
        'analysis_window_start', w.season_start,
        'analysis_window_end', w.season_end
      ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', s.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', s.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(s.time_loss_injuries, e.total_hours),
        'unit', 'per 1,000 player-hours',
        'numerator', s.time_loss_injuries,
        'denominator', e.total_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', s.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', s.days_lost, 'denominator', s.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', s.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(s.days_lost, e.total_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', s.days_lost, 'denominator', e.total_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.analysis_window_setting_split_v5 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.analysis_window_setting_split_v5 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from analysis.analysis_window_monthly_v5 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from analysis.analysis_window_severity_distribution_v5 x
      where x.curated_build_id = m.curated_build_id
        and x.team_key = m.team_key and x.season = m.season
    ), '[]'::jsonb),
    'prior_season', d.prior_season,
    'limitations', jsonb_build_array(
      'The immutable reporting window, rather than team-specific exposure coverage, defines numerator and denominator eligibility.',
      'Historical exposure state is retained; V5 exposes effective eligibility without mutating curated rows.',
      'Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.',
      'Unknown-setting injuries are included in overall metrics but have no match/training rate.',
      'Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.',
      'The reviewed master-plus-ledger lineage is the authoritative injury record.'
    )
  ) as dashboard
from analysis.league_member_releases_v2 m
join reporting.latest_team_dashboard d
  on d.release_id = m.team_release_id
 and d.team_key = m.team_key
 and d.season = m.season
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
 and w.season = m.season
join analysis.accepted_analysis_window_cohort_rules_v5 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
join analysis.analysis_window_team_summary_v5 s
  on s.curated_build_id = m.curated_build_id
 and s.team_key = m.team_key
 and s.season = m.season
join analysis.exposure_hours_by_build_analysis_window_v5 e
  on e.curated_build_id = m.curated_build_id
 and e.team_key = m.team_key
 and e.season = m.season
left join body
  on body.curated_build_id = m.curated_build_id
 and body.team_key = m.team_key and body.season = m.season
left join types
  on types.curated_build_id = m.curated_build_id
 and types.team_key = m.team_key and types.season = m.season
left join profiles
  on profiles.curated_build_id = m.curated_build_id
 and profiles.team_key = m.team_key and profiles.season = m.season;

create view analysis.league_dashboard_payload_analysis_window_v5
with (security_invoker = true) as
with body as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.code) as docs
  from analysis.analysis_window_league_effective_injury_profiles_v5 p
  where p.dimension = 'body_location' and p.setting_code = 'all'
  group by p.season
), types as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'key', p.code, 'label', p.label,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by p.time_loss_injuries desc, p.days_lost desc, p.code) as docs
  from analysis.analysis_window_league_effective_injury_profiles_v5 p
  where p.dimension = 'injury_type' and p.setting_code = 'all'
  group by p.season
), profile_rows as (
  select p.season, p.dimension, p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from analysis.analysis_window_league_effective_injury_profiles_v5 p
  union all
  select p.season, 'diagnosis', p.code, p.label, p.setting_code,
    p.time_loss_injuries, p.days_lost, p.exposure_hours,
    p.incidence_per_1000h, p.burden_per_1000h, p.mean_severity_days
  from analysis.analysis_window_league_diagnosis_profiles_v5 p
), profiles as (
  select p.season,
    jsonb_agg(jsonb_build_object(
      'dimension', p.dimension, 'code', p.code, 'label', p.label,
      'setting', p.setting_code,
      'time_loss_injuries', p.time_loss_injuries,
      'days_lost', p.days_lost, 'exposure_hours', p.exposure_hours,
      'incidence_per_1000h', p.incidence_per_1000h,
      'burden_per_1000h', p.burden_per_1000h,
      'mean_severity_days', p.mean_severity_days
    ) order by
      case when p.dimension = 'diagnosis' then 1 else 0 end,
      p.dimension, p.setting_code, p.time_loss_injuries desc,
      p.days_lost desc, p.code) as docs
  from profile_rows p
  group by p.season
)
select h.season,
  rules.classification_view_version,
  rules.classification_evidence_sha256,
  cohort.cohort_view_version,
  cohort.cohort_evidence_sha256,
  jsonb_build_object(
    'generated_at', (
      select max(m.generated_at)
      from analysis.league_member_releases_v2 m
      where m.season = h.season
    ),
    'team', 'URC Overall',
    'season', h.season,
    'analysis_window', jsonb_build_object(
      'start', w.season_start,
      'end', w.season_end,
      'basis', 'Immutable 2024-25 reporting window with effective row-level exposure eligibility.'
    ),
    'method', jsonb_build_array(
      'Incidence = pooled time-loss injuries / pooled exposure hours × 1,000.',
      'Burden = pooled days lost / pooled exposure hours × 1,000.',
      'Season-attributed undated injuries are included in counts and breakdowns but excluded from monthly series.',
      'Match exposure = registered fixtures in the reporting window × 15 players × 80 minutes / 60 per team.',
      'Training exposure = effective included exposure in the reporting window minus fixture-derived match exposure.',
      'IOC-aligned body-location and tissue/pathology categories use the accepted mappings.',
      'Injury rows and values are restated from the reviewed 2024-25 master workbook and its ordered decision ledger.'
    ),
    'coverage', coalesce((
      select b.dashboard -> 'coverage'
      from analysis.league_dashboard_payload_v2 b
      where b.season = h.season
    ), '{}'::jsonb) || jsonb_build_object(
      'hours', h.exposure_hours,
      'match_hours', h.match_exposure_hours,
      'training_hours', h.training_exposure_hours,
      'teams_included', (
        select count(*)
        from analysis.league_member_releases_v2 m
        where m.season = h.season
      ),
      'included_exposure_status', 'included',
      'analysis_window_start', w.season_start,
      'analysis_window_end', w.season_end
    ),
    'headline', jsonb_build_array(
      jsonb_build_object(
        'key', 'recorded_injuries', 'label', 'Recorded injuries',
        'value', h.recorded_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows in the immutable reporting window, including season-attributed undated rows)'
      ),
      jsonb_build_object(
        'key', 'time_loss_injuries', 'label', 'Time-loss injuries',
        'value', h.time_loss_injuries, 'unit', 'injuries',
        'formula', 'count(eligible injury rows where days lost > 0)'
      ),
      jsonb_build_object(
        'key', 'incidence_per_1000h', 'label', 'Incidence',
        'value', analysis.rate_per_1000_v1(
          h.time_loss_injuries, h.exposure_hours),
        'unit', 'per 1,000 player-hours',
        'numerator', h.time_loss_injuries,
        'denominator', h.exposure_hours,
        'formula', 'pooled time-loss injuries / pooled exposure hours * 1000'
      ),
      jsonb_build_object(
        'key', 'severity_mean_days', 'label', 'Mean severity',
        'value', h.mean_severity_days, 'unit', 'days lost per injury',
        'numerator', h.days_lost, 'denominator', h.time_loss_injuries,
        'formula', 'pooled days lost / pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'severity_median_days', 'label', 'Median severity',
        'value', h.median_severity_days, 'unit', 'days lost per injury',
        'formula', 'median(days lost) across pooled time-loss injuries'
      ),
      jsonb_build_object(
        'key', 'burden_per_1000h', 'label', 'Burden',
        'value', analysis.rate_per_1000_v1(h.days_lost, h.exposure_hours),
        'unit', 'days lost per 1,000 player-hours',
        'numerator', h.days_lost, 'denominator', h.exposure_hours,
        'formula', 'pooled days lost / pooled exposure hours * 1000'
      )
    ),
    'setting_split', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.analysis_window_league_setting_split_v5 x
      where x.season = h.season
    ), '[]'::jsonb),
    'setting_metrics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'setting', x.setting_code, 'label', initcap(x.setting_code),
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost, 'exposure_hours', x.exposure_hours,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h,
        'mean_severity_days', x.mean_severity_days
      ) order by case x.setting_code
        when 'match' then 1 when 'training' then 2 else 3 end)
      from analysis.analysis_window_league_setting_split_v5 x
      where x.season = h.season
    ), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
        'month', x.month_label, 'exposure_hours', x.exposure_hours,
        'distance_km', x.distance_km,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost,
        'incidence_per_1000h', x.incidence_per_1000h,
        'burden_per_1000h', x.burden_per_1000h
      ) order by x.month_start)
      from analysis.analysis_window_league_monthly_v5 x
      where x.season = h.season
    ), '[]'::jsonb),
    'body_locations', coalesce(body.docs, '[]'::jsonb),
    'injury_types', coalesce(types.docs, '[]'::jsonb),
    'injury_profiles', coalesce(profiles.docs, '[]'::jsonb),
    'severity_distribution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', x.severity_code, 'label', x.severity_label,
        'recorded_injuries', x.recorded_injuries,
        'time_loss_injuries', x.time_loss_injuries,
        'days_lost', x.days_lost
      ) order by x.band_order)
      from analysis.analysis_window_league_severity_distribution_v5 x
      where x.season = h.season
    ), '[]'::jsonb),
    'prior_season', jsonb_build_object(
      'season', '2023-24',
      'status', 'pending',
      'note', 'No prior-season league injury and exposure denominator pair has passed the V2 workflow.'
    ),
    'limitations', jsonb_build_array(
      'The immutable reporting window, rather than team-specific exposure coverage, defines numerator and denominator eligibility.',
      'Historical exposure state is retained; V5 exposes effective eligibility without mutating curated rows.',
      'Season-attributed undated injuries are retained in counts and breakdowns but cannot be month-plotted.',
      'Unknown-setting injuries are included in overall metrics but have no match/training rate.',
      'Exact diagnoses are not inferred; accepted IA-02/ACL-01 reporting classification is applied separately.',
      'The reviewed master-plus-ledger lineage is the authoritative injury record.'
    )
  ) as dashboard
from analysis.analysis_window_league_summary_v5 h
join analysis.reporting_season_windows_v3 w
  on w.cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
 and w.season = h.season
join analysis.accepted_analysis_window_cohort_rules_v5 cohort
  on cohort.cohort_view_version = w.cohort_view_version
 and cohort.season = w.season
cross join analysis.accepted_reporting_classification_rules_v4 rules
left join body on body.season = h.season
left join types on types.season = h.season
left join profiles on profiles.season = h.season;

-- Direct V5 branches. Do not add V5 to the retained UNION chain: filtering a
-- literal analysis version does not reliably prune its historical branches.
create view analysis.team_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select team_key, season, team_release_id, curated_build_id,
  'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.team_dashboard_payload_analysis_window_v5;

create view analysis.league_dashboard_release_candidates_analysis_window_v5
with (security_invoker = true) as
select season, 'v5'::text as analysis_version,
  classification_view_version, classification_evidence_sha256,
  cohort_view_version, cohort_evidence_sha256, dashboard
from analysis.league_dashboard_payload_analysis_window_v5;

comment on view analysis.team_dashboard_release_candidates_analysis_window_v5 is
  'Direct V5 analysis-window candidate path. It intentionally bypasses the historical UNION candidate chain.';
comment on view analysis.league_dashboard_release_candidates_analysis_window_v5 is
  'Direct V5 analysis-window candidate path. It intentionally bypasses the historical UNION candidate chain.';

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_analysis_version_check,
  add constraint league_release_context_v2_analysis_version_check check (
    analysis_version in ('v2', 'v3', 'v4', 'v5')
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_decision_recorded_at_check,
  add constraint league_release_context_v2_decision_recorded_at_check check (
    (analysis_version = 'v2' and decision_recorded_at = date '2026-07-14') or
    (analysis_version = 'v3' and decision_recorded_at = date '2026-07-19') or
    (analysis_version = 'v4' and decision_recorded_at = date '2026-07-24') or
    (analysis_version = 'v5' and decision_recorded_at = date '2026-07-25')
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_cohort_view_version_check,
  add constraint league_release_context_v2_cohort_view_version_check check (
    cohort_view_version in (
      'v2',
      'season_bound_2026-07-20_v1',
      'lineage_2024-25_2026-07-24_v1',
      'analysis_window_2024-25_2026-07-25_v1'
    )
  );

alter table reporting.league_release_context_v2
  drop constraint league_release_context_v2_cohort_evidence,
  add constraint league_release_context_v2_cohort_evidence check (
    (cohort_view_version = 'v2' and cohort_evidence_sha256 is null) or
    (
      cohort_view_version = 'season_bound_2026-07-20_v1'
      and cohort_evidence_sha256 is not null
    ) or
    (
      cohort_view_version = 'lineage_2024-25_2026-07-24_v1'
      and cohort_evidence_sha256 is not null
    ) or
    (
      cohort_view_version = 'analysis_window_2024-25_2026-07-25_v1'
      and cohort_evidence_sha256 is not null
    )
  );

create or replace function reporting.validate_league_dashboard_v2_candidate()
returns trigger language plpgsql as $$
declare
  target_classification_version text;
  target_analysis_version text;
begin
  select classification_view_version, analysis_version
    into target_classification_version, target_analysis_version
  from reporting.league_release_context_v2
  where release_id = new.release_id;

  if target_classification_version =
      'reporting_classification_2026-07-22_v2'
    and target_analysis_version = 'v3' then
    if not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_classification_incremental_20260722_v1
        candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'incremental league dashboard snapshot changed fields outside the accepted classification sections';
    end if;
  elsif target_analysis_version = 'v4' then
    if not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_release_candidates_lineage_v4 candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
    end if;
  elsif target_analysis_version = 'v5' then
    if not exists (
      select 1
      from reporting.league_release_context_v2 context
      join analysis.league_dashboard_release_candidates_analysis_window_v5
        candidate
        on candidate.season = context.season
       and candidate.analysis_version = context.analysis_version
       and candidate.classification_view_version =
          context.classification_view_version
       and candidate.classification_evidence_sha256 is not distinct from
          context.classification_evidence_sha256
       and candidate.cohort_view_version = context.cohort_view_version
       and candidate.cohort_evidence_sha256 is not distinct from
          context.cohort_evidence_sha256
       and candidate.dashboard = new.dashboard_payload
      where context.release_id = new.release_id
    ) then
      raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
    end if;
  elsif not exists (
    select 1
    from reporting.league_release_context_v2 context
    join analysis.league_dashboard_release_candidates_v6 candidate
      on candidate.season = context.season
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = new.dashboard_payload
    where context.release_id = new.release_id
  ) then
    raise exception 'league dashboard snapshot must equal its analysis-, classification-, and cohort-bound analytical candidate';
  end if;
  return new;
end;
$$;

create or replace function reporting.validate_team_dashboard_v2_candidates()
returns trigger language plpgsql as $$
begin
  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_classification_incremental_20260722_v1
      candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.classification_view_version =
        'reporting_classification_2026-07-22_v2'
      and context.analysis_version = 'v3'
      and candidate.team_key is null
  ) then
    raise exception 'incremental team dashboard snapshots changed fields outside the accepted classification sections';
  end if;

  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_lineage_v4 candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.analysis_version = 'v4'
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;

  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_analysis_window_v5
      candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where context.analysis_version = 'v5'
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;

  if exists (
    select 1
    from new_team_dashboard_v2_payloads payload
    join reporting.league_release_context_v2 context
      on context.release_id = payload.bundle_release_id
    left join analysis.team_dashboard_release_candidates_v6 candidate
      on candidate.season = context.season
     and candidate.team_key = payload.team_key
     and candidate.team_release_id = payload.team_release_id
     and candidate.curated_build_id = payload.curated_build_id
     and candidate.analysis_version = context.analysis_version
     and candidate.classification_view_version =
        context.classification_view_version
     and candidate.classification_evidence_sha256 is not distinct from
        context.classification_evidence_sha256
     and candidate.cohort_view_version = context.cohort_view_version
     and candidate.cohort_evidence_sha256 is not distinct from
        context.cohort_evidence_sha256
     and candidate.dashboard = payload.dashboard_payload
    where (
      context.classification_view_version <>
        'reporting_classification_2026-07-22_v2'
      or context.analysis_version <> 'v3'
    )
      and context.analysis_version <> 'v4'
      and context.analysis_version <> 'v5'
      and candidate.team_key is null
  ) then
    raise exception 'every team dashboard snapshot must equal its analysis-, classification-, and cohort-bound candidate';
  end if;
  return null;
end;
$$;

comment on function reporting.validate_league_dashboard_v2_candidate() is
  'Validates V5 and V4 releases against their direct candidate views, OSIICS classification-only V3 releases against the immutable incremental candidate, and every other full release against V6 candidates.';
comment on function reporting.validate_team_dashboard_v2_candidates() is
  'Statement trigger validating direct V5 and V4 lineage candidates, classification-only V3 candidates, or legacy full candidates without planning the historical UNION chain for V4 or V5.';

revoke execute on function reporting.validate_league_dashboard_v2_candidate()
  from public;
revoke execute on function reporting.validate_team_dashboard_v2_candidates()
  from public;
