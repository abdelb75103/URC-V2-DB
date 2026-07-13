-- Intake manifests use the public, unsponsored team display names. Bind the
-- three missing spellings to the existing canonical South African team keys.
insert into reporting.team_key_aliases (alias, team_key, excluded, note) values
  ('Lions', 'lions', false, 'Public unsponsored intake spelling.'),
  ('Sharks', 'sharks', false, 'Public unsponsored intake spelling.'),
  ('Stormers', 'stormers', false, 'Public unsponsored intake spelling.')
on conflict (alias) do nothing;
