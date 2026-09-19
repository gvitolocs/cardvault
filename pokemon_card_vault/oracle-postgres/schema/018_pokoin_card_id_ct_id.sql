-- APPLIED on pokoin-marketplace (2026-08-29). Our marketplace id is CardTrader × 2.
-- marketplace_cards.card_id = pokoin_public_number(ct_id) = ct_id * 2.
-- ct_id is only the CardTrader original (CDN filenames, CLIP, blueprint joins).
-- Canonical: docs/marketplace-public-ids.md
--
-- Do not run doubledCardId on card_id (already our id). CDN keys stay {ct_id}_*.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.marketplace_cards
  add column if not exists ct_id bigint;

alter table public.marketplace_search_candidates
  add column if not exists ct_id bigint;

alter table public.marketplace_card_urls
  add column if not exists ct_id bigint;

alter table public.marketplace_card_versions
  add column if not exists ct_id bigint;

alter table public.marketplace_card_variations
  add column if not exists ct_id bigint;

alter table public.marketplace_card_events
  add column if not exists ct_id bigint;

update public.marketplace_cards
set ct_id = card_id
where ct_id is null;

update public.marketplace_search_candidates
set ct_id = card_id
where ct_id is null;

update public.marketplace_card_urls
set ct_id = card_id
where ct_id is null;

update public.marketplace_card_versions
set ct_id = coalesce(blueprint_id, card_id)
where ct_id is null;

update public.marketplace_card_variations
set ct_id = card_id
where ct_id is null;

update public.marketplace_card_events
set ct_id = card_id
where ct_id is null;

alter table public.marketplace_cards
  alter column ct_id set not null;

alter table public.marketplace_search_candidates
  alter column ct_id set not null;

alter table public.marketplace_card_urls
  alter column ct_id set not null;

alter table public.marketplace_card_versions
  alter column ct_id set not null;

-- ---------------------------------------------------------------------------
-- Drop generated public_number and constraints that block rewriting PKs
-- ---------------------------------------------------------------------------

alter table public.marketplace_card_urls
  drop column if exists public_number;

alter table public.marketplace_card_urls
  drop constraint if exists marketplace_card_urls_card_id_fkey;

alter table public.marketplace_card_variations
  drop constraint if exists marketplace_card_variations_card_id_fkey;

alter table public.marketplace_cards
  drop constraint if exists marketplace_cards_card_id_fkey;

alter table public.marketplace_cards
  drop constraint if exists marketplace_cards_pkey;

alter table public.marketplace_search_candidates
  drop constraint if exists marketplace_search_candidates_pkey;

alter table public.marketplace_card_urls
  drop constraint if exists marketplace_card_urls_pkey;

alter table public.marketplace_card_versions
  drop constraint if exists marketplace_card_versions_pkey;

alter table public.marketplace_card_variations
  drop constraint if exists marketplace_card_variations_pkey;

alter table public.marketplace_name_ngrams
  drop constraint if exists marketplace_name_ngrams_pkey;

-- ---------------------------------------------------------------------------
-- Rewrite Pokoin ids (injective: n -> n*2)
-- ---------------------------------------------------------------------------

update public.marketplace_cards
set card_id = ct_id * 2
where card_id <> ct_id * 2;

update public.marketplace_search_candidates
set card_id = ct_id * 2
where card_id <> ct_id * 2;

update public.marketplace_card_urls
set card_id = ct_id * 2
where card_id <> ct_id * 2;

update public.marketplace_card_versions
set card_id = ct_id * 2
where card_id <> ct_id * 2;

update public.marketplace_card_variations
set card_id = ct_id * 2
where card_id <> ct_id * 2;

update public.marketplace_card_events
set card_id = ct_id * 2
where card_id <> ct_id * 2;

update public.marketplace_name_ngrams
set card_id = card_id * 2
where card_id is not null
  and card_id % 2 = 1;

alter table public.marketplace_card_urls
  add column public_number bigint generated always as (card_id) stored;

-- ---------------------------------------------------------------------------
-- Recreate keys
-- ---------------------------------------------------------------------------

alter table public.marketplace_cards
  add constraint marketplace_cards_pkey primary key (card_id);

alter table public.marketplace_cards
  add constraint marketplace_cards_ct_id_key unique (ct_id);

alter table public.marketplace_cards
  add constraint marketplace_cards_ct_id_fkey
  foreign key (ct_id) references public.pokoin_pokemon_blueprints(id) on delete cascade;

alter table public.marketplace_search_candidates
  add constraint marketplace_search_candidates_pkey primary key (card_id);

alter table public.marketplace_search_candidates
  add constraint marketplace_search_candidates_ct_id_key unique (ct_id);

alter table public.marketplace_card_urls
  add constraint marketplace_card_urls_pkey primary key (card_id);

alter table public.marketplace_card_urls
  add constraint marketplace_card_urls_card_id_fkey
  foreign key (card_id) references public.marketplace_search_candidates(card_id) on delete cascade;

create unique index if not exists marketplace_card_urls_public_number_idx
  on public.marketplace_card_urls (public_number);

create index if not exists marketplace_card_urls_ct_id_idx
  on public.marketplace_card_urls (ct_id);

alter table public.marketplace_card_versions
  add constraint marketplace_card_versions_pkey primary key (card_id);

alter table public.marketplace_card_variations
  add constraint marketplace_card_variations_pkey primary key (card_id, variation_key);

alter table public.marketplace_card_variations
  add constraint marketplace_card_variations_card_id_fkey
  foreign key (card_id) references public.marketplace_search_candidates(card_id) on delete cascade;

alter table public.marketplace_name_ngrams
  add constraint marketplace_name_ngrams_pkey
  primary key (card_id, language, source, chunk, chunk_position);

comment on column public.marketplace_cards.card_id is
  'Pokoin public card id (CardTrader blueprint id * 2).';
comment on column public.marketplace_cards.ct_id is
  'Original CardTrader blueprint id. CDN filenames and CardTrader API keep this value.';
comment on column public.marketplace_card_urls.public_number is
  'Same as Pokoin card_id after the ct_id cutover; kept for URL lookups.';

-- ---------------------------------------------------------------------------
-- Generated card_id mirrors (artists / tcg / limitless)
-- ---------------------------------------------------------------------------

alter table public.marketplace_blueprint_artists
  drop column if exists card_id;

alter table public.marketplace_blueprint_artists
  add column if not exists ct_id bigint;

update public.marketplace_blueprint_artists
set ct_id = blueprint_id
where ct_id is null;

alter table public.marketplace_blueprint_artists
  add column card_id bigint generated always as (blueprint_id * 2) stored;

create index if not exists marketplace_blueprint_artists_card_idx
  on public.marketplace_blueprint_artists (card_id);

alter table public.marketplace_blueprint_tcg_metadata
  drop column if exists card_id;

alter table public.marketplace_blueprint_tcg_metadata
  add column if not exists ct_id bigint;

update public.marketplace_blueprint_tcg_metadata
set ct_id = blueprint_id
where ct_id is null;

alter table public.marketplace_blueprint_tcg_metadata
  add column card_id bigint generated always as (blueprint_id * 2) stored;

create index if not exists marketplace_blueprint_tcg_metadata_card_idx
  on public.marketplace_blueprint_tcg_metadata (card_id);

alter table public.limitless_marketplace_expansion_blueprints
  drop column if exists card_id;

alter table public.limitless_marketplace_expansion_blueprints
  add column if not exists ct_id bigint;

update public.limitless_marketplace_expansion_blueprints
set ct_id = blueprint_id
where ct_id is null;

alter table public.limitless_marketplace_expansion_blueprints
  add column card_id bigint generated always as (blueprint_id * 2) stored;

create index if not exists limitless_marketplace_expansion_blueprints_card_idx
  on public.limitless_marketplace_expansion_blueprints (card_id);

-- ---------------------------------------------------------------------------
-- pokoin_card_id text fields currently store the CardTrader id
-- ---------------------------------------------------------------------------

update public.cardtrader_blueprint_listing_cache
set pokoin_card_id = (blueprint_id * 2)::text
where pokoin_card_id ~ '^[0-9]+$'
  and pokoin_card_id::bigint = blueprint_id;

update public.cardtrader_market_listing_snapshots
set pokoin_card_id = (blueprint_id * 2)::text
where pokoin_card_id ~ '^[0-9]+$'
  and blueprint_id is not null
  and pokoin_card_id::bigint = blueprint_id;

update public.cardtrader_market_listing_removed_history
set pokoin_card_id = (blueprint_id * 2)::text
where pokoin_card_id ~ '^[0-9]+$'
  and blueprint_id is not null
  and pokoin_card_id::bigint = blueprint_id;

update public.cardtrader_user_listing_snapshots
set pokoin_card_id = (blueprint_id * 2)::text
where pokoin_card_id ~ '^[0-9]+$'
  and blueprint_id is not null
  and pokoin_card_id::bigint = blueprint_id;

update public.cardtrader_user_listing_removed_history
set pokoin_card_id = (blueprint_id * 2)::text
where pokoin_card_id ~ '^[0-9]+$'
  and blueprint_id is not null
  and pokoin_card_id::bigint = blueprint_id;

-- ---------------------------------------------------------------------------
-- Refresh functions: keep writing doubled Pokoin ids + ct_id
-- ---------------------------------------------------------------------------

create or replace function public.refresh_marketplace_cards_from_blueprints()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  refreshed_count integer;
begin
  alter table public.pokoin_pokemon_blueprints
    add column if not exists emoji text not null default '';

  alter table public.marketplace_cards
    add column if not exists product_variant text not null default '';
  alter table public.marketplace_cards
    add column if not exists card_palette jsonb not null default '{}'::jsonb;
  alter table public.marketplace_cards
    add column if not exists emoji text not null default '';
  alter table public.marketplace_cards
    add column if not exists ct_id bigint;
  perform public.marketplace_seed_cards_type();

  alter table public.marketplace_card_names
    add column if not exists emoji text not null default '';

  insert into public.marketplace_card_names (name, normalized_name, compact_name, emoji, name_tokens, updated_at)
  select
    name,
    public.marketplace_search_normalize(name),
    public.marketplace_search_compact(name),
    public.marketplace_card_name_emoji(name),
    public.marketplace_search_tokenize(name),
    now()
  from (select distinct name from public.pokoin_pokemon_blueprints where name <> '') source
  on conflict (name) do update set
    normalized_name = excluded.normalized_name,
    compact_name = excluded.compact_name,
    emoji = excluded.emoji,
    name_tokens = excluded.name_tokens,
    updated_at = now();

  perform public.marketplace_seed_cards_name_type();

  update public.pokoin_pokemon_blueprints b
  set
    card_palette = public.marketplace_card_palette(
      coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
      b.name,
      coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
      concat_ws(' ', coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'), b.version)
    ),
    emoji = concat_ws(
      ' ',
      nullif(n.emoji, ''),
      public.marketplace_card_variant_emoji(
        b.name,
        coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
        b.version
      )
    )
  from public.marketplace_card_names n
  where n.name = b.name;

  insert into public.marketplace_cards (
    card_id, ct_id, name, version, product_variant, image_url, cdn_image_url, preview_image_url,
    set_name, rarity, card_type, card_number, is_holo, is_foil,
    imported_at, projected_at, item_kind, product_type, trainer_name, card_palette, emoji
  )
  select
    public.pokoin_public_number(source.id),
    source.id,
    source.name,
    source.version,
    case when source.product_type = 'card' then '' else coalesce(source.version, '') end,
    source.image_url,
    source.cdn_image_url,
    source.preview_image_url,
    source.set_name,
    source.rarity,
    source.card_type,
    case when source.product_type = 'card' then coalesce(source.explicit_card_number, source.version, source.id::text) else coalesce(source.explicit_card_number, '') end,
    lower(coalesce(source.rarity, '')) like '%holo%',
    lower(coalesce(source.rarity, '')) like '%holo%',
    source.imported_at,
    now(),
    case when source.product_type = 'card' then 'single' else 'product' end,
    source.product_type,
    source.trainer_name,
    source.card_palette,
    source.emoji
  from (
    select
      b.id,
      b.name,
      b.version,
      b.image_url,
      b.cdn_image_url,
      b.preview_image_url,
      coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as set_name,
      coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card') as rarity,
      coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card') as card_type,
      coalesce(nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', '')) as explicit_card_number,
      public.classify_marketplace_product_type(
        b.name,
        coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'),
        b.blueprint->>'category_name',
        b.blueprint->>'type',
        coalesce(nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, b.id::text),
        b.version,
        b.id
      ) as product_type,
      coalesce(nullif(b.blueprint->>'trainer_name', ''), '') as trainer_name,
      public.marketplace_card_palette(
        coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
        b.name,
        coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
        concat_ws(' ', coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'), b.version)
      ) as card_palette,
      coalesce(
        nullif(b.emoji, ''),
        public.marketplace_card_emoji(
          coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
          b.name,
          coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
          b.version
        )
      ) as emoji,
      b.imported_at
    from public.pokoin_pokemon_blueprints b
  ) source
  where coalesce(source.preview_image_url, source.cdn_image_url, source.image_url) is not null
  on conflict (card_id) do update set
    ct_id = excluded.ct_id,
    name = excluded.name,
    version = excluded.version,
    product_variant = excluded.product_variant,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    set_name = excluded.set_name,
    rarity = excluded.rarity,
    card_type = excluded.card_type,
    card_number = excluded.card_number,
    is_holo = excluded.is_holo,
    is_foil = excluded.is_foil,
    imported_at = excluded.imported_at,
    projected_at = now(),
    item_kind = excluded.item_kind,
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name,
    card_palette = excluded.card_palette,
    emoji = excluded.emoji;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$function$;

create or replace function public.refresh_marketplace_card_versions()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  refreshed_count integer;
begin
  alter table public.marketplace_card_versions
    add column if not exists product_variant text not null default '';
  alter table public.marketplace_card_versions
    add column if not exists card_palette jsonb not null default '{}'::jsonb;
  alter table public.marketplace_card_versions
    add column if not exists emoji text not null default '';
  alter table public.marketplace_card_versions
    add column if not exists ct_id bigint;

  insert into public.marketplace_card_versions (
    card_id,
    name,
    expansion_name,
    expansion_number,
    expansion_number_int,
    product_variant,
    blueprint_id,
    ct_id,
    image_url,
    cdn_image_url,
    preview_image_url,
    product_type,
    trainer_name,
    card_palette,
    emoji,
    projected_at
  )
  select
    c.card_id,
    c.name,
    c.set_name,
    c.card_number,
    public.marketplace_expansion_number_int(c.card_number),
    c.product_variant,
    c.ct_id,
    c.ct_id,
    c.image_url,
    c.cdn_image_url,
    c.preview_image_url,
    c.product_type,
    c.trainer_name,
    c.card_palette,
    c.emoji,
    now()
  from public.marketplace_cards c
  where coalesce(c.preview_image_url, c.cdn_image_url, c.image_url) is not null
  on conflict (card_id) do update set
    name = excluded.name,
    expansion_name = excluded.expansion_name,
    expansion_number = excluded.expansion_number,
    expansion_number_int = excluded.expansion_number_int,
    product_variant = excluded.product_variant,
    blueprint_id = excluded.blueprint_id,
    ct_id = excluded.ct_id,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name,
    card_palette = excluded.card_palette,
    emoji = excluded.emoji,
    projected_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$function$;

create or replace function public.refresh_marketplace_card_urls()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  refreshed_count integer;
begin
  delete from public.marketplace_card_urls;

  insert into public.marketplace_card_urls (
    card_id,
    ct_id,
    language,
    canonical_slug,
    canonical_slug_normalized,
    canonical_path,
    canonical_path_normalized,
    rarity,
    name,
    card_number,
    set_name,
    item_kind,
    product_type,
    is_unique,
    duplicate_group_size,
    duplicate_keys,
    source_projected_at,
    updated_at
  )
  select
    parsed.card_id,
    parsed.ct_id,
    'en',
    parsed.canonical_slug,
    public.marketplace_search_compact(parsed.canonical_slug),
    parsed.canonical_path,
    lower(parsed.canonical_path),
    parsed.rarity,
    parsed.name,
    parsed.card_number,
    parsed.set_name,
    parsed.item_kind,
    parsed.product_type,
    parsed.duplicate_group_size = 1,
    parsed.duplicate_group_size,
    '[]'::jsonb,
    parsed.projected_at,
    now()
  from (
    select
      source.card_id,
      source.ct_id,
      source.rarity,
      source.name,
      source.card_number,
      source.set_name,
      source.item_kind,
      source.product_type,
      source.projected_at,
      source.canonical_slug,
      '/marketplace/en/cards/' || source.card_id::text
        || '/' || source.canonical_slug as canonical_path,
      count(*) over (partition by source.canonical_slug) as duplicate_group_size
    from (
      select
        c.card_id,
        c.ct_id,
        coalesce(nullif(trim(c.rarity), ''), 'Card') as rarity,
        coalesce(
          nullif(trim(c.display_name), ''),
          nullif(trim(c.canonical_name), ''),
          c.name
        ) as name,
        coalesce(c.card_number, '') as card_number,
        coalesce(nullif(trim(c.set_name), ''), 'Pokemon') as set_name,
        c.item_kind,
        c.product_type,
        c.projected_at,
        coalesce(nullif(trim(both '-' from concat_ws(
          '-',
          public.marketplace_url_slug_part(coalesce(nullif(trim(c.rarity), ''), 'Card')),
          public.marketplace_url_slug_part(coalesce(
            nullif(trim(c.display_name), ''),
            nullif(trim(c.canonical_name), ''),
            c.name
          )),
          public.marketplace_url_slug_part(
            public.marketplace_card_url_collector_number(c.card_number, c.ct_id)
          ),
          public.marketplace_url_slug_part(coalesce(nullif(trim(c.set_name), ''), 'Pokemon'))
        )), ''), 'card') as canonical_slug
      from public.marketplace_cards c
      inner join public.marketplace_search_candidates sc
        on sc.card_id = c.card_id
    ) source
  ) parsed;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$function$;

commit;
