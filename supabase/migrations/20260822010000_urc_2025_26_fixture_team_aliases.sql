begin;

-- Public official competition spellings used by the checksum-bound 2025-26
-- fixture list. Canonical team keys already exist in reporting.teams.
insert into reporting.team_key_aliases (alias, team_key, excluded, note) values
  ('Benetton Rugby', 'benetton', false, 'Official 2025-26 fixture-list spelling.'),
  ('Connacht Rugby', 'connacht', false, 'Official 2025-26 fixture-list spelling.'),
  ('Leinster Rugby', 'leinster', false, 'Official 2025-26 fixture-list spelling.'),
  ('Munster Rugby', 'munster', false, 'Official 2025-26 fixture-list spelling.'),
  ('Ulster Rugby', 'ulster', false, 'Official 2025-26 fixture-list spelling.')
on conflict (alias) do nothing;

do $$
begin
  if (
    select count(*)
    from reporting.team_key_aliases
    where (alias, team_key, excluded) in (
      ('Benetton Rugby', 'benetton', false),
      ('Connacht Rugby', 'connacht', false),
      ('Leinster Rugby', 'leinster', false),
      ('Munster Rugby', 'munster', false),
      ('Ulster Rugby', 'ulster', false)
    )
  ) <> 5 then
    raise exception '2025-26 official fixture aliases are absent or conflict with canonical team keys';
  end if;
end;
$$;

commit;
