-- Register the release reason used by the checksum-bound partial-exposure
-- successor. This is audit vocabulary only and changes no reporting value.

insert into audit.reason_codes (code, description) values (
  'league_dashboard_release_v6_partial_exposure_reporting',
  'Immutable 16-team 2025-26 league dashboard release with partial source-backed exposure reporting and explicit temporary team estimates.'
)
on conflict (code) do update set description = excluded.description;

do $$
begin
  if not exists (
    select 1
    from audit.reason_codes
    where code = 'league_dashboard_release_v6_partial_exposure_reporting'
      and description =
        'Immutable 16-team 2025-26 league dashboard release with partial source-backed exposure reporting and explicit temporary team estimates.'
  ) then
    raise exception 'Partial exposure league release reason code is not registered exactly';
  end if;
end;
$$;
