-- Keep the installed setting-profile assertion valid after its exact candidate
-- is promoted. Candidate lineage, rather than current-reader state, proves the
-- predecessor on which the additive successor was built.

create or replace function analysis.assert_urc_2024_25_setting_profile_successor_v1()
returns void
language plpgsql
set search_path = pg_catalog, analysis, audit, reporting
as $$
declare
  league_dashboard jsonb;
begin
  if (select count(*) from analysis.urc_2024_25_team_dashboard_candidate_v2) <> 16
     or (select count(*) from analysis.urc_2024_25_league_dashboard_candidate_v2) <> 1
     or exists (
       select 1 from analysis.urc_2024_25_team_dashboard_candidate_v2
       where predecessor_release_id <>
         '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
     )
     or exists (
       select 1 from analysis.urc_2024_25_league_dashboard_candidate_v2
       where predecessor_release_id <>
         '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
     )
  then
    raise exception 'setting-profile successor candidate lineage is incomplete';
  end if;

  if not exists (
    select 1
    from analysis.urc_2024_25_classification_evidence_v1 evidence
    where evidence.adjudication_rows = 32
      and evidence.specific_diagnosis_injury_rows = 1660
      and evidence.specific_diagnosis_illness_rows_excluded = 392
      and evidence.specific_diagnosis_evidence_sha256 =
        'a43ba36a7f67ecd208112d702bcc058de947b00d721399e9e0ad26d23f3ac167'
      and evidence.specific_diagnosis_mapping_rows_sha256 =
        '8c26ddfbabef220a5ddc8e957b6ef143f0eeb46342d4e9634edf720162e5b7c7'
  ) then
    raise exception 'setting-profile successor diagnosis evidence is incomplete';
  end if;

  select dashboard into league_dashboard
  from analysis.urc_2024_25_league_dashboard_candidate_v2;
  if (select (item ->> 'value')::bigint
      from jsonb_array_elements(league_dashboard -> 'headline') item
      where item ->> 'key' = 'recorded_injuries') <> 1662
     or (select (item ->> 'value')::bigint
         from jsonb_array_elements(league_dashboard -> 'headline') item
         where item ->> 'key' = 'time_loss_injuries') <> 913
     or (select (item ->> 'numerator')::numeric
         from jsonb_array_elements(league_dashboard -> 'headline') item
         where item ->> 'key' = 'severity_mean_days') <> 17575
  then
    raise exception 'setting-profile successor changed the approved headline totals';
  end if;

  if exists (
    with expected as (
      select injury.team_key, setting.setting_code,
        count(*) filter (
          where injury.final_classification = 'Time Loss'
        )::bigint as time_loss_injuries,
        coalesce(sum(injury.days_lost) filter (
          where injury.final_classification = 'Time Loss'
            and injury.duration_usable
        ), 0)::numeric as days_lost
      from analysis.urc_2024_25_final_injury_classification_v1 injury
      cross join lateral (
        select injury.setting_code
          where injury.setting_code in ('match', 'training', 'unknown')
        union all select 'all'::text
      ) setting
      where injury.canonical_problem_type = 'injury'
      group by injury.team_key, setting.setting_code
    ), published as (
      select profile.team_key, profile.setting_code,
        sum(profile.time_loss_injuries)::bigint as time_loss_injuries,
        sum(profile.days_lost)::numeric as days_lost
      from analysis.urc_2024_25_team_profiles_v2 profile
      where profile.dimension = 'diagnosis'
      group by profile.team_key, profile.setting_code
    )
    select 1
    from expected
    full join published using (team_key, setting_code)
    where (expected.time_loss_injuries, expected.days_lost)
      is distinct from (published.time_loss_injuries, published.days_lost)
  ) then
    raise exception 'published diagnosis totals do not match injury-only source rows';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_team_profiles_v2 profile
    join reporting.dashboard_bundle_team_payloads_v1 payload
      on payload.team_key = profile.team_key
     and payload.curated_build_id = profile.curated_build_id
     and payload.bundle_release_id =
       '8b50b9e2-023b-4f99-b6ae-e53d8e21706e'::uuid
    where profile.setting_code in ('all', 'match', 'training')
      and profile.exposure_hours is distinct from case profile.setting_code
        when 'all' then (payload.dashboard_payload -> 'coverage' ->> 'hours')::numeric
        when 'match' then (payload.dashboard_payload -> 'coverage' ->> 'match_hours')::numeric
        when 'training' then (payload.dashboard_payload -> 'coverage' ->> 'training_hours')::numeric
      end
  ) then
    raise exception 'team profile denominator does not match its setting';
  end if;

  if exists (
    select 1
    from analysis.urc_2024_25_team_severity_distribution_v2 overall
    left join lateral (
      select sum(setting.recorded_injuries)::bigint as recorded_injuries,
        sum(setting.time_loss_injuries)::bigint as time_loss_injuries,
        sum(setting.days_lost)::numeric as days_lost
      from analysis.urc_2024_25_team_severity_distribution_v2 setting
      where setting.team_key = overall.team_key
        and setting.curated_build_id = overall.curated_build_id
        and setting.severity_code = overall.severity_code
        and setting.setting_code in ('match', 'training', 'unknown')
    ) settings on true
    where overall.setting_code = 'all'
      and (overall.recorded_injuries, overall.time_loss_injuries, overall.days_lost)
        is distinct from
          (settings.recorded_injuries, settings.time_loss_injuries, settings.days_lost)
  ) then
    raise exception 'severity all row does not reconcile to match, training and unknown';
  end if;

  if jsonb_array_length(league_dashboard -> 'injury_type_families') = 0
     or not (select bool_and(setting in ('all', 'match', 'training'))
             from jsonb_to_recordset(league_dashboard -> 'severity_distribution')
               as severity(setting text))
     or (select count(distinct setting)
         from jsonb_to_recordset(league_dashboard -> 'injury_profiles')
           as profile(setting text)
         where setting in ('all', 'match', 'training')) <> 3
  then
    raise exception 'published setting profiles, families or severity rows are incomplete';
  end if;
end;
$$;

select analysis.assert_urc_2024_25_setting_profile_successor_v1();

revoke execute on function
  analysis.assert_urc_2024_25_setting_profile_successor_v1()
from public, anon, authenticated, web_reader;

comment on function analysis.assert_urc_2024_25_setting_profile_successor_v1() is
  'Fails closed unless 2024-25 setting profiles, severity and injury-type families reconcile against their immutable candidate predecessor after promotion.';
