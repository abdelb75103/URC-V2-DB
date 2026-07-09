-- Phase 0.2: team dimension table. Historical `team` strings in
-- ingestion/audit rows are never rewritten; curated/analysis/reporting
-- layers key on team_key instead, resolved through team_key_aliases.
--
-- team_key values match the website's config/teams.ts `id` field exactly
-- (verified against the live repo, 9 July 2026). union_key values match
-- config/unions.ts `id`. Team display names are public; nothing here
-- encodes the protected Team A-Z league-alias mapping.

create table reporting.teams (
  team_key text primary key,
  display_name text not null,
  union_key text not null check (union_key in ('irfu', 'wru', 'saru', 'fir', 'sru')),
  -- No team is known to have reported exposure weekly by real name: the only
  -- documented weekly-reporter evidence (docs/EXPOSURE_CLEANING_PROTOCOL.md,
  -- pipeline/__main__.py EXPOSURE_WEEKLY_TEAM_ALIASES) identifies weekly
  -- reporters only by protected league alias ('Team I', 'Team J', 'Team K',
  -- 'Team L'), and resolving that to a real team_key requires the protected
  -- alias map, which must never be joined against a table like this one that
  -- is keyed on public team names. Defaulting every team to false here is a
  -- deliberate privacy choice, not a data gap; revisit only through a
  -- process that never materializes the alias pairing in this schema.
  weekly_reporter boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table reporting.team_key_aliases (
  alias text primary key,
  team_key text references reporting.teams(team_key),
  excluded boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  constraint team_key_aliases_team_key_required_unless_excluded
    check (excluded or team_key is not null)
);

insert into reporting.teams (team_key, display_name, union_key) values
  ('connacht', 'Connacht', 'irfu'),
  ('leinster', 'Leinster', 'irfu'),
  ('munster', 'Munster', 'irfu'),
  ('ulster', 'Ulster', 'irfu'),
  ('cardiff', 'Cardiff', 'wru'),
  ('dragons', 'Dragons', 'wru'),
  ('ospreys', 'Ospreys', 'wru'),
  ('scarlets', 'Scarlets', 'wru'),
  ('bulls', 'Bulls', 'saru'),
  ('lions', 'Lions', 'saru'),
  ('sharks', 'Sharks', 'saru'),
  ('stormers', 'Stormers', 'saru'),
  ('benetton', 'Benetton', 'fir'),
  ('zebre', 'Zebre', 'fir'),
  ('edinburgh', 'Edinburgh', 'sru'),
  ('glasgow', 'Glasgow', 'sru')
on conflict (team_key) do nothing;

-- Canonical identity aliases (team_key -> itself) plus every legacy spelling
-- observed live in ingestion.source_files.team as of 9 July 2026
-- (Connacht, Edinburgh, glasgow, Leinster, Munster, Smoke Test, Ulster).
insert into reporting.team_key_aliases (alias, team_key, excluded, note) values
  ('connacht', 'connacht', false, 'Canonical team_key.'),
  ('Connacht', 'connacht', false, 'Legacy Title-case spelling observed in ingestion.source_files.team.'),
  ('leinster', 'leinster', false, 'Canonical team_key.'),
  ('Leinster', 'leinster', false, 'Legacy Title-case spelling observed in ingestion.source_files.team.'),
  ('munster', 'munster', false, 'Canonical team_key.'),
  ('Munster', 'munster', false, 'Legacy Title-case spelling observed in ingestion.source_files.team.'),
  ('ulster', 'ulster', false, 'Canonical team_key.'),
  ('Ulster', 'ulster', false, 'Legacy Title-case spelling observed in ingestion.source_files.team.'),
  ('cardiff', 'cardiff', false, 'Canonical team_key; not yet ingested.'),
  ('dragons', 'dragons', false, 'Canonical team_key; not yet ingested.'),
  ('ospreys', 'ospreys', false, 'Canonical team_key; not yet ingested.'),
  ('scarlets', 'scarlets', false, 'Canonical team_key; not yet ingested.'),
  ('bulls', 'bulls', false, 'Canonical team_key; not yet ingested.'),
  ('lions', 'lions', false, 'Canonical team_key; not yet ingested.'),
  ('sharks', 'sharks', false, 'Canonical team_key; not yet ingested.'),
  ('stormers', 'stormers', false, 'Canonical team_key; not yet ingested.'),
  ('benetton', 'benetton', false, 'Canonical team_key; not yet ingested.'),
  ('zebre', 'zebre', false, 'Canonical team_key; not yet ingested.'),
  ('edinburgh', 'edinburgh', false, 'Canonical team_key.'),
  ('Edinburgh', 'edinburgh', false, 'Legacy Title-case spelling observed in ingestion.source_files.team.'),
  ('glasgow', 'glasgow', false, 'Canonical team_key; also the exact legacy spelling observed in ingestion.source_files.team.'),
  ('Smoke Test', null, true, 'Local pipeline smoke-test artifact team; not a real URC team.')
on conflict (alias) do nothing;

alter table reporting.teams enable row level security;
alter table reporting.team_key_aliases enable row level security;
