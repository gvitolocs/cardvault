-- Collector search aliases from data/pokemon_tcg_expansion_shortnames_and_card_nicknames.txt.
-- Expansion short codes go into marketplace_expansion_aliases (already on Meili).
-- Card nicknames (Moonbreon, Mewtube, …) bind to printings, then Meili `nicknames`.
-- Do not use 2-letter aliases as primary keys. Do not alias EX (Expedition) — it is the mechanic.

begin;
set local statement_timeout = 0;

create table if not exists public.marketplace_card_nicknames (
  nickname text not null,
  normalized_nickname text not null,
  compact_nickname text not null,
  card_name text not null,
  expansion_name text not null default '',
  card_number text not null default '',
  notes text not null default '',
  source text not null default 'tcg_shortnames',
  updated_at timestamptz not null default now(),
  primary key (normalized_nickname, card_name, expansion_name, card_number)
);

create index if not exists marketplace_card_nicknames_compact_idx
  on public.marketplace_card_nicknames (compact_nickname);

create table if not exists public.marketplace_card_nickname_hits (
  card_id bigint not null references public.marketplace_search_candidates(card_id) on delete cascade,
  nickname text not null,
  updated_at timestamptz not null default now(),
  primary key (card_id, nickname)
);

create index if not exists marketplace_card_nickname_hits_nick_idx
  on public.marketplace_card_nickname_hits (nickname);

do $grant$
begin
  if exists (select 1 from pg_roles where rolname = 'pokoin_marketplace') then
    execute 'grant select, insert, update, delete on public.marketplace_card_nicknames to pokoin_marketplace';
    execute 'grant select, insert, update, delete on public.marketplace_card_nickname_hits to pokoin_marketplace';
  end if;
end
$grant$;

commit;
