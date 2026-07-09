-- Phase 2.1: curated layer. Typed, validated tables built from
-- processing.record_versions (never from files) by the new
-- `build-curated` pipeline command. Same posture as the other private
-- schemas: RLS enabled on every table, schema revoked from anon/authenticated.
--
-- Category-column validation pattern: curated.code_lists is keyed by
-- (list_name, code) because the same code (e.g. 'unknown') is reused
-- across multiple domains (activity_context, body_location, ...), so a
-- single-column FK to code_lists.code cannot disambiguate which list a
-- value belongs to. Each FK'd category column therefore gets a paired
-- `<column>_list` generated column holding the constant list_name, and a
-- composite FK (<column>_list, <column>) -> code_lists(list_name, code).
-- A NULL category value is exempt from the FK (Postgres MATCH SIMPLE
-- default), which is deliberate: NULL means "not computed for this row"
-- (e.g. the three adjudicated-duplicate rows whose merged record_state
-- predates the current field set), distinct from the controlled value
-- 'unknown' which means "computed, insufficient source evidence".

create schema if not exists curated;

revoke all on schema curated from anon, authenticated;

create table curated.code_lists (
  list_name text not null,
  code text not null,
  label text not null,
  consensus_basis text not null,
  notes text not null default '',
  active boolean not null default true,
  primary key (list_name, code)
);

-- body_location, injury_type: docs/IOC_TAXONOMY_BUCKETS.csv verbatim.
insert into curated.code_lists (list_name, code, label, consensus_basis, notes) values
  ('body_location', 'head', 'Head', 'IOC 2020 body area', 'Includes face/brain/concussion evidence when coded as head.'),
  ('body_location', 'neck', 'Neck', 'IOC 2020 body area', 'Includes cervical spine.'),
  ('body_location', 'shoulder', 'Shoulder', 'IOC 2020 body area', 'Includes shoulder/clavicle/scapula region.'),
  ('body_location', 'upper_arm', 'Upper arm', 'IOC 2020 body area', 'Upper arm segment.'),
  ('body_location', 'elbow', 'Elbow', 'IOC 2020 body area', 'Elbow region.'),
  ('body_location', 'forearm', 'Forearm', 'IOC 2020 body area', 'Forearm region.'),
  ('body_location', 'wrist', 'Wrist', 'IOC 2020 body area', 'Wrist/carpus region.'),
  ('body_location', 'hand', 'Hand', 'IOC 2020 body area', 'Hand/finger/thumb region.'),
  ('body_location', 'chest', 'Chest', 'IOC 2020 body area', 'Chest/rib/sternum region.'),
  ('body_location', 'thoracic_spine', 'Thoracic spine', 'IOC 2020 body area', 'Thoracic spine/costovertebral region.'),
  ('body_location', 'lumbosacral', 'Lumbosacral', 'IOC 2020 body area', 'Lumbar spine/sacrum/coccyx/buttock/pelvis fallback.'),
  ('body_location', 'abdomen', 'Abdomen', 'IOC 2020 body area', 'Abdominal/trunk fallback when code supports abdomen.'),
  ('body_location', 'hip_groin', 'Hip/Groin', 'IOC 2020 body area', 'Hip and groin region.'),
  ('body_location', 'thigh', 'Thigh', 'IOC 2020 body area', 'Thigh/femur/hamstring/quadriceps/adductor region.'),
  ('body_location', 'knee', 'Knee', 'IOC 2020 body area', 'Knee/patella/patellar tendon region.'),
  ('body_location', 'lower_leg', 'Lower leg', 'IOC 2020 body area', 'Lower leg/calf/Achilles region.'),
  ('body_location', 'ankle', 'Ankle', 'IOC 2020 body area', 'Ankle/syndesmosis region.'),
  ('body_location', 'foot', 'Foot', 'IOC 2020 body area', 'Foot/toe/calcaneus/plantar fascia region.'),
  ('body_location', 'unspecified', 'Unspecified', 'IOC 2020 body area', 'Use only when source/coding indicates unspecified body area.'),
  ('body_location', 'multiple', 'Multiple', 'IOC 2020 body area', 'Use only when source/coding indicates multiple body areas.'),
  ('body_location', 'unknown', 'Unknown', 'Pipeline audit category', 'Use when no defensible body-location evidence exists; not an IOC body-area bucket.'),
  ('injury_type', 'muscle_injury', 'Muscle injury', 'IOC 2020 tissue/pathology', 'Includes strain/tear/rupture-like muscle injury source categories.'),
  ('injury_type', 'muscle_contusion', 'Muscle contusion', 'IOC 2020 tissue/pathology', 'Reserved for future teams when source evidence distinguishes muscle contusion.'),
  ('injury_type', 'muscle_compartment_syndrome', 'Muscle compartment syndrome', 'IOC 2020 tissue/pathology', 'Reserved for future teams.'),
  ('injury_type', 'tendinopathy', 'Tendinopathy', 'IOC 2020 tissue/pathology', 'Nonrupture tendon/paratenon/bursa/fascia-related category.'),
  ('injury_type', 'tendon_rupture', 'Tendon rupture', 'IOC 2020 tissue/pathology', 'Reserved for explicit tendon rupture source evidence.'),
  ('injury_type', 'brain_spinal_cord_injury', 'Brain/spinal cord injury', 'IOC 2020 tissue/pathology', 'Includes concussion/brain/spinal cord injury.'),
  ('injury_type', 'peripheral_nerve_injury', 'Peripheral nerve injury', 'IOC 2020 tissue/pathology', 'Includes nerve injuries when source/coding supports it.'),
  ('injury_type', 'fracture', 'Fracture', 'IOC 2020 tissue/pathology', 'Traumatic fracture category.'),
  ('injury_type', 'bone_stress_injury', 'Bone stress injury', 'IOC 2020 tissue/pathology', 'Reserved for explicit stress injury evidence.'),
  ('injury_type', 'bone_contusion', 'Bone contusion', 'IOC 2020 tissue/pathology', 'Reserved for explicit bony contusion evidence.'),
  ('injury_type', 'avascular_necrosis', 'Avascular necrosis', 'IOC 2020 tissue/pathology', 'Reserved for future teams.'),
  ('injury_type', 'physis_injury', 'Physis injury', 'IOC 2020 tissue/pathology', 'Reserved for physeal/apophyseal injury evidence.'),
  ('injury_type', 'cartilage_injury', 'Cartilage injury', 'IOC 2020 tissue/pathology', 'Includes osteochondral/cartilage/labral/meniscal source categories when supported.'),
  ('injury_type', 'arthritis', 'Arthritis', 'IOC 2020 tissue/pathology', 'Includes osteoarthritis source categories.'),
  ('injury_type', 'synovitis_capsulitis', 'Synovitis/capsulitis', 'IOC 2020 tissue/pathology', 'Safe default for combined synovitis/impingement/bursitis source category unless bursitis is explicit.'),
  ('injury_type', 'bursitis', 'Bursitis', 'IOC 2020 tissue/pathology', 'Reserved for explicit bursitis evidence.'),
  ('injury_type', 'joint_sprain', 'Joint sprain', 'IOC 2020 tissue/pathology', 'Includes ligament/dislocation/subluxation-like source categories when supported.'),
  ('injury_type', 'chronic_instability', 'Chronic instability', 'IOC 2020 tissue/pathology', 'Includes instability source categories.'),
  ('injury_type', 'contusion_superficial', 'Contusion (superficial)', 'IOC 2020 tissue/pathology', 'Includes bruising/haematoma when not specifically muscle contusion.'),
  ('injury_type', 'laceration', 'Laceration', 'IOC 2020 tissue/pathology', 'Includes laceration/abrasion source category unless abrasion is explicit.'),
  ('injury_type', 'abrasion', 'Abrasion', 'IOC 2020 tissue/pathology', 'Reserved for explicit abrasion evidence.'),
  ('injury_type', 'vascular_trauma', 'Vessels (vascular trauma)', 'IOC 2020 tissue/pathology', 'Reserved for future teams.'),
  ('injury_type', 'stump_injury', 'Stump injury', 'IOC 2020 tissue/pathology', 'Reserved for future teams.'),
  ('injury_type', 'internal_organ_trauma', 'Internal organs (organ trauma)', 'IOC 2020 tissue/pathology', 'Includes organ damage source categories.'),
  ('injury_type', 'nonspecific', 'Nonspecific', 'IOC 2020 tissue/pathology', 'Use when source/coding indicates nonspecific injury pathology.'),
  ('injury_type', 'unknown', 'Unknown', 'Pipeline audit category', 'Use when no defensible tissue/pathology evidence exists; not an IOC tissue/pathology bucket.')
on conflict (list_name, code) do nothing;

-- activity_context, contact_context, recurrence_status, severity_category,
-- problem_type: frozen enumerations read from the pipeline mapping
-- functions (pipeline/__main__.py activity_context(), contact_context(),
-- recurrence_status(), severity_category(), problem_type()) and confirmed
-- against the live distinct record_state values for the latest version of
-- every accepted injury record, 9-10 July 2026.
insert into curated.code_lists (list_name, code, label, consensus_basis, notes) values
  ('activity_context', 'urc_match', 'URC match', 'Pipeline frozen enumeration', 'Occasion category game/match and Match Type URC.'),
  ('activity_context', 'training', 'Training', 'Pipeline frozen enumeration', 'Occasion category or Match Type training.'),
  ('activity_context', 'match', 'Non-URC match', 'Pipeline frozen enumeration', 'Occasion category game/match with a non-URC Match Type.'),
  ('activity_context', 'unknown', 'Unknown', 'Pipeline frozen enumeration', 'Insufficient direct evidence.'),
  ('contact_context', 'contact', 'Contact', 'Pipeline frozen enumeration', 'Is Contact reports a contact mechanism.'),
  ('contact_context', 'non_contact', 'Non-contact', 'Pipeline frozen enumeration', 'Is Contact reports a non-contact mechanism, or inferred from an acute muscle strain.'),
  ('contact_context', 'unknown', 'Unknown', 'Pipeline frozen enumeration', 'Source missing or unknown.'),
  ('recurrence_status', 'first_episode', 'First episode', 'Pipeline frozen enumeration', 'Recurrence reports a first/new episode.'),
  ('recurrence_status', 'recurrence', 'Recurrence', 'Pipeline frozen enumeration', 'Recurrence reports a recurrence (any stage).'),
  ('recurrence_status', 'unknown', 'Unknown', 'Pipeline frozen enumeration', 'Source missing or unknown.'),
  ('severity_category', 'zero_days_medical_attention_only', 'Medical attention (0 days)', 'Pipeline frozen enumeration', 'Closed injury, 0 days lost.'),
  ('severity_category', 'one_day', '1 day', 'Pipeline frozen enumeration', 'Closed injury, 1 day lost.'),
  ('severity_category', 'two_to_three_days', '2-3 days', 'Pipeline frozen enumeration', 'Closed injury, 2-3 days lost.'),
  ('severity_category', 'four_to_seven_days', '4-7 days', 'Pipeline frozen enumeration', 'Closed injury, 4-7 days lost.'),
  ('severity_category', 'eight_to_twenty_eight_days', '8-28 days', 'Pipeline frozen enumeration', 'Closed injury, 8-28 days lost.'),
  ('severity_category', 'greater_than_twenty_eight_days', '>28 days', 'Pipeline frozen enumeration', 'Closed injury, more than 28 days lost.'),
  ('severity_category', 'unknown_or_censored', 'Unknown or censored', 'Pipeline frozen enumeration', 'Missing days-injured evidence, or an unclosed (censored) injury.'),
  ('problem_type', 'injury', 'Injury', 'Pipeline frozen enumeration', 'Problem type injury, or inferred from Orchard Code / injury tissue type.'),
  ('problem_type', 'illness', 'Illness', 'Pipeline frozen enumeration', 'Problem type illness, or inferred from Illness Code.'),
  ('problem_type', 'unknown', 'Unknown', 'Pipeline frozen enumeration', 'Source missing or unknown.')
on conflict (list_name, code) do nothing;

create table curated.builds (
  id uuid primary key default gen_random_uuid(),
  pipeline_run_id uuid not null references audit.pipeline_runs(id),
  team_key text not null references reporting.teams(team_key),
  season text not null,
  source_version_set_count integer not null,
  source_version_set_hash text not null,
  row_counts jsonb not null default '{}'::jsonb,
  output_hash text,
  status text not null check (status in ('active', 'superseded')) default 'active',
  created_at timestamptz not null default now()
);

-- At most one active build per team/season; the previous active build is
-- flipped to 'superseded' (never deleted) before a --rebuild inserts a new
-- active one, so this index can never be violated by build-curated.
create unique index curated_builds_one_active_per_team_season
  on curated.builds (team_key, season)
  where status = 'active';

create table curated.injuries (
  id uuid primary key default gen_random_uuid(),
  source_row_id uuid not null references ingestion.source_rows(id),
  record_version_id uuid not null references processing.record_versions(id),
  team_key text not null references reporting.teams(team_key),
  season text not null,
  player_uid text,
  injury_uid text,
  date_injured date,
  days_injured integer,
  derived_return_date date,
  is_closed boolean,
  activity_context text,
  activity_context_list text generated always as ('activity_context') stored,
  contact_context text,
  contact_context_list text generated always as ('contact_context') stored,
  recurrence_status text,
  recurrence_status_list text generated always as ('recurrence_status') stored,
  severity_category text,
  severity_category_list text generated always as ('severity_category') stored,
  body_location text,
  body_location_list text generated always as ('body_location') stored,
  injury_type text,
  injury_type_list text generated always as ('injury_type') stored,
  problem_type text,
  problem_type_list text generated always as ('problem_type') stored,
  eligibility_status text not null check (
    eligibility_status in (
      'included_pending_protocol', 'review_required',
      'excluded_from_analysis', 'excluded_duplicate_adjudicated'
    )
  ),
  field_origins jsonb not null default '{}'::jsonb,
  source_locator jsonb not null default '{}'::jsonb,
  curated_build_id uuid not null references curated.builds(id),
  created_at timestamptz not null default now(),
  unique (curated_build_id, source_row_id),
  foreign key (activity_context_list, activity_context) references curated.code_lists (list_name, code),
  foreign key (contact_context_list, contact_context) references curated.code_lists (list_name, code),
  foreign key (recurrence_status_list, recurrence_status) references curated.code_lists (list_name, code),
  foreign key (severity_category_list, severity_category) references curated.code_lists (list_name, code),
  foreign key (body_location_list, body_location) references curated.code_lists (list_name, code),
  foreign key (injury_type_list, injury_type) references curated.code_lists (list_name, code),
  foreign key (problem_type_list, problem_type) references curated.code_lists (list_name, code)
);

-- Plan §2.1 specifies injury_uid unique. Scoped per build (superseded
-- builds keep their rows, so a global unique index would break --rebuild)
-- and partial (NULL injury_uid is allowed: the three historical
-- adjudicated-duplicate record_states carry no injury_uid). Verified
-- read-only on 10 July 2026: no team has a duplicate non-null injury_uid
-- among its latest record versions.
create unique index curated_injuries_injury_uid_unique_per_build
  on curated.injuries (curated_build_id, injury_uid)
  where injury_uid is not null;

create table curated.exposure (
  id uuid primary key default gen_random_uuid(),
  source_row_id uuid not null references ingestion.source_rows(id),
  record_version_id uuid not null references processing.record_versions(id),
  team_key text not null references reporting.teams(team_key),
  season text not null,
  player_uid text,
  grain text check (grain in ('session', 'weekly')),
  session_date date,
  week_start_date date,
  minutes_clean numeric,
  distance_m_clean numeric,
  scope_status text check (scope_status in ('in_scope_explicit', 'scope_unknown_included', 'out_of_scope_explicit')),
  exclusion_reasons text[] not null default '{}'::text[],
  eligibility_status text not null check (eligibility_status in ('included_pending_protocol', 'excluded_from_primary')),
  source_locator jsonb not null default '{}'::jsonb,
  curated_build_id uuid not null references curated.builds(id),
  created_at timestamptz not null default now(),
  unique (curated_build_id, source_row_id)
);

create table curated.fixtures (
  id uuid primary key default gen_random_uuid(),
  season text not null,
  stage text not null default '',
  round text not null default '',
  match_date date not null,
  date_status text not null default '',
  home_team_key text not null references reporting.teams(team_key),
  away_team_key text not null references reporting.teams(team_key),
  source_row_number integer not null,
  source_file_sha256 text not null,
  loaded_by_run_id uuid not null references audit.pipeline_runs(id),
  created_at timestamptz not null default now(),
  unique (season, source_row_number)
);

create table curated.team_exposure_denominators (
  id uuid primary key default gen_random_uuid(),
  team_key text not null references reporting.teams(team_key),
  season text not null,
  matches_played integer not null,
  match_hours numeric not null,
  training_hours numeric not null,
  total_hours numeric not null,
  method_note text not null,
  fixture_source_sha256 text not null,
  curated_build_id uuid not null references curated.builds(id),
  created_at timestamptz not null default now(),
  unique (curated_build_id, team_key, season)
);

-- Controlled reason codes for the Phase 2 curated-layer commands
-- (build-curated, load-curated-fixtures). Reason codes are controlled:
-- seed by migration, never ad hoc inside a pipeline command (Phase 0
-- precedent); the commands guard on their existence and refuse to run
-- if this migration has not been applied.
insert into audit.reason_codes (code, description) values
  (
    'curated_projection',
    'Typed projection of the latest accepted processing.record_versions '
    'row into the curated layer; source values are preserved upstream.'
  ),
  (
    'curated_denominator_derivation',
    'Team match/training exposure denominator derived from '
    'curated.exposure and curated.fixtures.'
  ),
  (
    'curated_fixture_load',
    'Registered URC fixture list loaded into curated.fixtures for '
    'match/training exposure denominators; source is the '
    'checksum-documented corrected fixture file.'
  )
on conflict (code) do nothing;

alter table curated.code_lists enable row level security;
alter table curated.builds enable row level security;
alter table curated.injuries enable row level security;
alter table curated.exposure enable row level security;
alter table curated.fixtures enable row level security;
alter table curated.team_exposure_denominators enable row level security;

-- Extra reporting.team_key_aliases entries for the public URC fixture-list
-- team-name spellings (data/intake/2024-25/fixtures/urc_fixtures_2024_25.corrected.csv
-- home_team/away_team columns), verified live 9-10 July 2026. These are
-- public club names, never the protected Team A-Z league alias.
insert into reporting.team_key_aliases (alias, team_key, excluded, note) values
  ('Benetton', 'benetton', false, 'Fixture-list spelling.'),
  ('Bulls', 'bulls', false, 'Fixture-list spelling.'),
  ('Cardiff', 'cardiff', false, 'Fixture-list spelling.'),
  ('Cardiff Rugby', 'cardiff', false, 'Fixture-list spelling.'),
  ('DHL Stormers', 'stormers', false, 'Fixture-list sponsor spelling.'),
  ('Dragons RFC', 'dragons', false, 'Fixture-list spelling.'),
  ('Edinburgh Rugby', 'edinburgh', false, 'Fixture-list spelling.'),
  ('Emirates Lions', 'lions', false, 'Fixture-list sponsor spelling.'),
  ('Glasgow Warriors', 'glasgow', false, 'Fixture-list spelling.'),
  ('Hollywoodbets Sharks', 'sharks', false, 'Fixture-list sponsor spelling.'),
  ('Ospreys', 'ospreys', false, 'Fixture-list spelling.'),
  ('Scarlets', 'scarlets', false, 'Fixture-list spelling.'),
  ('Vodacom Bulls', 'bulls', false, 'Fixture-list sponsor spelling.'),
  ('Zebre Parma', 'zebre', false, 'Fixture-list spelling.')
on conflict (alias) do nothing;
