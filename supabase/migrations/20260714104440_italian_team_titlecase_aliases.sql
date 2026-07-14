begin;

insert into reporting.team_key_aliases (alias, team_key, excluded, note) values
  ('Benetton', 'benetton', false, 'Public intake spelling.'),
  ('Zebre', 'zebre', false, 'Public intake spelling.')
on conflict (alias) do update set
  team_key = excluded.team_key,
  excluded = excluded.excluded,
  note = excluded.note;

commit;
