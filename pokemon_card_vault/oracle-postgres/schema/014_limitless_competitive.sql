create table if not exists public.limitless_games (
  game_id text primary key,
  name text not null,
  formats jsonb not null default '{}'::jsonb,
  platforms jsonb not null default '{}'::jsonb,
  metagame boolean not null default false,
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'limitless',
  source_updated_at timestamptz,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.limitless_tournaments (
  tournament_id text primary key,
  game_id text references public.limitless_games(game_id) on update cascade,
  name text not null,
  format text,
  tournament_date timestamptz,
  player_count integer not null default 0,
  organizer_id integer,
  organizer_name text,
  platform text,
  decklists_available boolean,
  is_public boolean,
  is_online boolean,
  phases jsonb not null default '[]'::jsonb,
  raw_listing jsonb not null default '{}'::jsonb,
  raw_details jsonb not null default '{}'::jsonb,
  source text not null default 'limitless',
  source_url text,
  details_fetched_at timestamptz,
  standings_fetched_at timestamptz,
  pairings_fetched_at timestamptz,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.limitless_players (
  player_id text primary key,
  display_name text not null,
  country text,
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'limitless',
  first_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.limitless_tournament_standings (
  tournament_id text not null references public.limitless_tournaments(tournament_id) on delete cascade,
  player_id text not null references public.limitless_players(player_id) on update cascade,
  "placing" integer,
  display_name text not null,
  country text,
  wins integer not null default 0,
  losses integer not null default 0,
  ties integer not null default 0,
  drop_round integer,
  deck_name text,
  deck_archetype text,
  decklist_id text,
  deck_summary jsonb not null default '{}'::jsonb,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tournament_id, player_id)
);

create table if not exists public.limitless_tournament_pairings (
  tournament_id text not null references public.limitless_tournaments(tournament_id) on delete cascade,
  phase integer not null,
  round integer not null,
  table_number integer not null default 0,
  match_index integer not null default 0,
  player1_id text references public.limitless_players(player_id) on update cascade,
  player2_id text references public.limitless_players(player_id) on update cascade,
  winner_player_id text references public.limitless_players(player_id) on update cascade,
  result text,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tournament_id, phase, round, table_number, match_index)
);

create table if not exists public.limitless_decklists (
  decklist_id text primary key,
  tournament_id text not null references public.limitless_tournaments(tournament_id) on delete cascade,
  player_id text references public.limitless_players(player_id) on update cascade,
  "placing" integer,
  title text,
  archetype text,
  game_id text references public.limitless_games(game_id) on update cascade,
  format text,
  source_url text,
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'limitless',
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.limitless_deck_cards (
  decklist_id text not null references public.limitless_decklists(decklist_id) on delete cascade,
  card_key text not null,
  card_name text not null,
  count integer not null,
  section text not null default 'main',
  set_code text,
  collector_number text,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (decklist_id, section, card_key)
);

create table if not exists public.limitless_sync_runs (
  id bigserial primary key,
  sync_type text not null default 'incremental',
  status text not null default 'running',
  dry_run boolean not null default false,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  tournaments_seen integer not null default 0,
  tournaments_upserted integer not null default 0,
  details_fetched integer not null default 0,
  standings_fetched integer not null default 0,
  pairings_fetched integer not null default 0,
  decklists_fetched integer not null default 0,
  error text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists limitless_tournaments_date_idx
  on public.limitless_tournaments (tournament_date desc nulls last);

create index if not exists limitless_tournaments_game_format_idx
  on public.limitless_tournaments (game_id, format, tournament_date desc nulls last);

create index if not exists limitless_tournaments_public_idx
  on public.limitless_tournaments (is_public, tournament_date desc nulls last);

create index if not exists limitless_standings_tournament_placing_idx
  on public.limitless_tournament_standings (tournament_id, "placing");

create index if not exists limitless_standings_deck_archetype_idx
  on public.limitless_tournament_standings (deck_archetype);

create index if not exists limitless_pairings_tournament_round_idx
  on public.limitless_tournament_pairings (tournament_id, phase, round, table_number);

create index if not exists limitless_decklists_tournament_idx
  on public.limitless_decklists (tournament_id, "placing");

create index if not exists limitless_deck_cards_name_idx
  on public.limitless_deck_cards (card_name);

create table if not exists public.limitless_public_decks (
  deck_id text primary key,
  name text not null,
  format text,
  format_label text,
  rank integer,
  points integer not null default 0,
  share numeric(7, 3) not null default 0,
  earnings_text text,
  total_points integer,
  regional_top8 integer,
  regional_wins integer,
  international_top8 integer,
  international_wins integer,
  variants jsonb not null default '[]'::jsonb,
  raw jsonb not null default '{}'::jsonb,
  source text not null default 'limitless-public',
  source_url text,
  source_fetched_at timestamptz,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.limitless_public_deck_core_cards (
  deck_id text not null references public.limitless_public_decks(deck_id) on delete cascade,
  card_key text not null,
  display_name text not null,
  count numeric(6, 2),
  inclusion_share numeric(7, 3),
  set_code text,
  collector_number text,
  source_url text,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (deck_id, card_key)
);

create table if not exists public.limitless_public_deck_results (
  deck_id text not null references public.limitless_public_decks(deck_id) on delete cascade,
  tournament_id text not null,
  tournament_name text not null,
  tournament_date date,
  format text,
  "placing" integer,
  placing_label text,
  variant text,
  player_id text,
  player_name text not null,
  decklist_id text,
  source_url text,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (deck_id, tournament_id, "placing", player_name)
);

create table if not exists public.limitless_public_deck_players (
  deck_id text not null references public.limitless_public_decks(deck_id) on delete cascade,
  player_id text not null,
  player_name text not null,
  country text,
  rank integer,
  points integer not null default 0,
  source_url text,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (deck_id, player_id)
);

create table if not exists public.limitless_public_tournaments (
  tournament_id text primary key,
  name text not null,
  country text,
  country_name text,
  format text,
  format_label text,
  tournament_date date,
  player_count integer not null default 0,
  winner_player_id text,
  winner_name text,
  winner_country text,
  source text not null default 'limitless-public',
  source_url text,
  raw jsonb not null default '{}'::jsonb,
  source_fetched_at timestamptz,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.limitless_public_tournament_standings (
  tournament_id text not null references public.limitless_public_tournaments(tournament_id) on delete cascade,
  "placing" integer not null,
  player_id text,
  player_name text not null,
  country text,
  deck_id text,
  deck_name text,
  variant text,
  decklist_id text,
  source_url text,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tournament_id, "placing", player_name)
);

create table if not exists public.limitless_public_decklist_cards (
  decklist_id text not null,
  card_key text not null,
  card_name text not null,
  count numeric(6, 2) not null,
  section text not null default 'main',
  set_code text,
  collector_number text,
  source_url text,
  raw jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (decklist_id, section, card_key)
);

create index if not exists limitless_public_decks_rank_idx
  on public.limitless_public_decks (rank, points desc);

create index if not exists limitless_public_deck_results_deck_date_idx
  on public.limitless_public_deck_results (deck_id, tournament_date desc nulls last, "placing");

create index if not exists limitless_public_tournaments_date_idx
  on public.limitless_public_tournaments (tournament_date desc nulls last, player_count desc);

create index if not exists limitless_public_tournament_standings_deck_idx
  on public.limitless_public_tournament_standings (deck_id, tournament_id, "placing");

alter table if exists public.limitless_public_tournament_standings
  drop constraint if exists limitless_public_tournament_standings_deck_id_fkey;
