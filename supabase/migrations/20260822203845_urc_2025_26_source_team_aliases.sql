-- Exact title-case source-team spellings present in the approved Year 2
-- intake. Canonical lower-case aliases already exist; these two observed
-- source values are additive aliases only.

insert into reporting.team_key_aliases (alias, team_key, excluded, note) values
  ('Dragons', 'dragons', false, 'Approved URC 2025-26 source spelling.'),
  ('Glasgow', 'glasgow', false, 'Approved URC 2025-26 source spelling.')
on conflict (alias) do nothing;

do $$
begin
  if (
    select count(*)
    from reporting.team_key_aliases alias
    join reporting.teams team on team.team_key = alias.team_key and team.active
    where (alias.alias, alias.team_key, alias.excluded) in (
      ('Dragons', 'dragons', false),
      ('Glasgow', 'glasgow', false)
    )
  ) <> 2 then
    raise exception 'URC 2025-26 source-team aliases are absent, inactive, or conflicting';
  end if;
end;
$$;
