-- Tracking rows for the contact mechanism ring migrations.
-- sql_exec.mjs does not self-register, so this runs immediately after both
-- migrations are applied. It refuses to register anything that is not actually
-- present and correctly bound.

do $$
begin
  if to_regclass(
    'analysis.analysis_window_contact_distribution_v5'
  ) is null or to_regclass(
    'analysis.analysis_window_league_contact_distribution_v5'
  ) is null or to_regclass(
    'analysis.team_dashboard_payload_analysis_window_v5_contact_snapshot'
  ) is null or to_regclass(
    'analysis.league_dashboard_payload_analysis_window_v5_contact_snapshot'
  ) is null then
    raise exception 'V5 contact distribution objects are missing';
  end if;

  if position(
    'team_dashboard_payload_analysis_window_v5_contact_snapshot'
    in pg_get_viewdef(
      'analysis.team_dashboard_release_candidates_analysis_window_v5'::regclass,
      true
    )
  ) = 0 or position(
    'league_dashboard_payload_analysis_window_v5_contact_snapshot'
    in pg_get_viewdef(
      'analysis.league_dashboard_release_candidates_analysis_window_v5'::regclass,
      true
    )
  ) = 0 then
    raise exception 'V5 candidate views are not bound to the contact snapshots';
  end if;

  if to_regclass('reporting.latest_team_dashboard_v4') is null
    or to_regclass('reporting.latest_league_dashboard_v4') is null then
    raise exception 'V4 contact reader views are missing';
  end if;

  if not has_table_privilege(
    'web_reader', 'reporting.latest_team_dashboard_v4', 'select'
  ) or not has_table_privilege(
    'web_reader', 'reporting.latest_league_dashboard_v4', 'select'
  ) then
    raise exception 'web_reader cannot read the V4 contact reader views';
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, name, statements)
values
  ('20260726160000', 'contact_distribution_v5', null),
  ('20260726161000', 'contact_distribution_reader_v4', null)
on conflict (version) do nothing;

do $$
begin
  if (
    select count(*)
    from supabase_migrations.schema_migrations
    where (version, name) in (
      ('20260726160000', 'contact_distribution_v5'),
      ('20260726161000', 'contact_distribution_reader_v4')
    )
  ) <> 2 then
    raise exception 'contact distribution migration tracking is invalid';
  end if;
end;
$$;
