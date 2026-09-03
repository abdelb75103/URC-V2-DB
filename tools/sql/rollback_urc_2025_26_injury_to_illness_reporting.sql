-- Run only after proving the same approved live target and authorising rollback.
-- Restores the retained definitions and V7 snapshots. Keeps the 24 decisions.
begin;
set local search_path = pg_catalog, public, extensions, reporting, analysis;

do $$
declare item record;
begin
  if current_database() <> 'postgres'
    or (select target_attested from reporting.approved_dashboard_reader_target_v8) is distinct from true
    or (select count(*) from audit.urc_2025_26_injury_to_illness_rollback_v1) <> 5
    or (select count(*) from audit.urc_2025_26_injury_to_illness_decisions_v1) <> 24
    or strpos(pg_get_viewdef('reporting.latest_team_dashboard_v7'::regclass),
      'diagnosis_family_team_dashboard_payloads_v3') = 0
    or strpos(pg_get_viewdef('reporting.latest_league_dashboard_v7'::regclass),
      'diagnosis_family_league_dashboard_payloads_v3') = 0
  then
    raise exception 'Injury-to-illness rollback target or active successor differs';
  end if;
  for item in select * from audit.urc_2025_26_injury_to_illness_rollback_v1
    order by object_name
  loop
    execute 'create or replace view ' || item.object_name || ' as ' || item.definition;
  end loop;
end;
$$;
refresh materialized view analysis.urc_diagnosis_family_rows_v1;

do $$
begin
  if (select count(*) from analysis.urc_2025_26_canonical_injury_rows_v1) <> 1545
    or (select sum(recorded_illnesses) from analysis.urc_illness_league_profiles_v1
      where season = '2025-26') <> 439
    or exists (
      select 1 from reporting.latest_team_dashboard_v7 reader
      join reporting.diagnosis_family_team_dashboard_payloads_v2 retained using (team_key, season)
      where reader.headline <> retained.dashboard -> 'headline'
        or reader.illness_summary <> retained.dashboard -> 'illness_summary'
    )
  then
    raise exception 'Retained reporting predecessor was not restored';
  end if;
end;
$$;

create table audit.urc_2025_26_injury_to_illness_rollback_applied_v1 as
select now() as recorded_at,
  'urc_2025_26_injury_to_illness_2026_09_03_v1'::text as rule_version,
  'Restored the retained reader definitions and V7 payloads; correction evidence remains immutable.'::text as action;
alter table audit.urc_2025_26_injury_to_illness_rollback_applied_v1 enable row level security;
revoke all on audit.urc_2025_26_injury_to_illness_rollback_applied_v1
from public, anon, authenticated, web_reader;
create trigger injury_to_illness_rollback_applied_v1_immutable before update or delete
on audit.urc_2025_26_injury_to_illness_rollback_applied_v1
for each row execute function audit.reject_urc_diagnosis_family_adjudication_mutation_v1();
commit;
