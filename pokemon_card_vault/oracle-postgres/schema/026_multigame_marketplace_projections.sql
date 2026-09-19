-- Thin marketplace projections for isolated CardTrader games
-- (One Piece / Riftbound). Apply inside pokoin_one_piece and pokoin_riftbound.
--
-- card_id = ct_id * 2 (same public-id rule as Pokemon).
-- CDN keys and blueprint.id stay raw ct_id.
-- Raw dumps stay in marketplace_* schemas; projections live in public.

create extension if not exists unaccent with schema public;
create extension if not exists pg_trgm with schema public;

create or replace function public.pokoin_public_number(cardtrader_id bigint)
returns bigint
language sql
immutable
as $$
  select cardtrader_id * 2;
$$;

create or replace function public.marketplace_url_slug_part(value text)
returns text
language sql
stable
as $$
  select trim(both '-' from regexp_replace(
    lower(public.unaccent(coalesce(value, ''))),
    '[^a-z0-9]+',
    '-',
    'g'
  ));
$$;

create or replace function public.marketplace_search_compact(value text)
returns text
language sql
stable
as $$
  select regexp_replace(
    lower(public.unaccent(coalesce(value, ''))),
    '[^a-z0-9]+',
    '',
    'g'
  );
$$;

create or replace function public.marketplace_card_url_collector_number(
  card_number text,
  card_id bigint
)
returns text
language sql
immutable
as $$
  select case
    when cleaned = '' or cleaned = card_id::text then ''
    else cleaned
  end
  from (
    select regexp_replace(trim(both from coalesce(card_number, '')), '^#+\s*', '') as cleaned
  ) source;
$$;

create table if not exists public.marketplace_search_candidates (
  card_id bigint primary key,
  ct_id bigint not null,
  name text not null,
  source_name text not null default '',
  display_name text not null default '',
  canonical_name text not null default '',
  set_name text not null default '',
  card_number text not null default '',
  product_variant text not null default '',
  rarity text not null default 'Card',
  card_type text not null default 'Card',
  item_kind text not null default 'single' check (item_kind in ('single', 'product')),
  product_type text not null default 'card',
  trainer_name text not null default '',
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  homepage_image_url text,
  card_palette jsonb not null default '{}'::jsonb,
  emoji text not null default '',
  search_text text not null default '',
  name_prefix text not null default '',
  set_prefix text not null default '',
  expansion_name text not null default '',
  search_weight numeric not null default 0,
  imported_at timestamptz,
  projected_at timestamptz not null default now()
);

create index if not exists marketplace_search_candidates_name_prefix_idx
  on public.marketplace_search_candidates (name_prefix, search_weight desc, imported_at desc nulls last);

create index if not exists marketplace_search_candidates_set_prefix_idx
  on public.marketplace_search_candidates (set_prefix, search_weight desc, imported_at desc nulls last);

create index if not exists marketplace_search_candidates_search_text_trgm_idx
  on public.marketplace_search_candidates using gin (search_text gin_trgm_ops);

create index if not exists marketplace_search_candidates_set_name_idx
  on public.marketplace_search_candidates (set_name, card_id desc);

create index if not exists marketplace_search_candidates_ct_id_idx
  on public.marketplace_search_candidates (ct_id);

create table if not exists public.marketplace_card_urls (
  card_id bigint primary key references public.marketplace_search_candidates(card_id) on delete cascade,
  ct_id bigint not null,
  language text not null default 'en',
  canonical_slug text not null check (canonical_slug <> ''),
  canonical_slug_normalized text not null check (canonical_slug_normalized <> ''),
  canonical_path text not null check (canonical_path <> ''),
  canonical_path_normalized text not null check (canonical_path_normalized <> ''),
  rarity text not null default 'Card',
  name text not null,
  card_number text not null default '',
  set_name text not null default '',
  item_kind text not null default 'single',
  product_type text not null default 'card',
  is_unique boolean not null default true,
  duplicate_group_size integer not null default 1 check (duplicate_group_size >= 1),
  duplicate_keys jsonb not null default '[]'::jsonb,
  source_projected_at timestamptz,
  updated_at timestamptz not null default now()
);

create unique index if not exists marketplace_card_urls_public_number_idx
  on public.marketplace_card_urls (card_id);

create index if not exists marketplace_card_urls_ct_id_idx
  on public.marketplace_card_urls (ct_id);

-- raw_schema: marketplace_one_piece | marketplace_riftbound
-- card_category_ids: singles (cards / DON!! / champions)
-- rarity_keys: jsonb keys under blueprint.fixed_properties
create or replace function public.refresh_multigame_marketplace_projections(
  raw_schema text,
  card_category_ids integer[],
  rarity_keys text[] default array['onepiece_rarity', 'riftbound_rarity']
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
  qualified_raw text;
begin
  if raw_schema is null or raw_schema !~ '^[a-z_][a-z0-9_]*$' then
    raise exception 'invalid raw_schema %', raw_schema;
  end if;
  qualified_raw := format('%I.cardtrader_blueprints', raw_schema);

  execute format($sql$
    insert into public.marketplace_search_candidates (
      card_id, ct_id, name, source_name, display_name, canonical_name,
      set_name, card_number, product_variant, rarity, card_type, item_kind,
      product_type, trainer_name, image_url, cdn_image_url, preview_image_url,
      homepage_image_url, card_palette, emoji, search_text, name_prefix, set_prefix,
      expansion_name, search_weight, imported_at, projected_at
    )
    select
      public.pokoin_public_number(b.id) as card_id,
      b.id as ct_id,
      b.name,
      b.name as source_name,
      b.name as display_name,
      b.name as canonical_name,
      coalesce(nullif(trim(b.expansion->>'name'), ''), 'Unknown') as set_name,
      coalesce(
        nullif(trim(b.blueprint->'fixed_properties'->>'collector_number'), ''),
        ''
      ) as card_number,
      coalesce(nullif(trim(b.version), ''), '') as product_variant,
      coalesce(
        (
          select nullif(trim(b.blueprint->'fixed_properties'->>key), '')
          from unnest($2::text[]) as key
          where nullif(trim(b.blueprint->'fixed_properties'->>key), '') is not null
          limit 1
        ),
        'Card'
      ) as rarity,
      'Card' as card_type,
      case
        when b.category_id = any($1::integer[]) then 'single'
        else 'product'
      end as item_kind,
      case
        when b.category_id = any($1::integer[]) then 'card'
        else 'sealed'
      end as product_type,
      '' as trainer_name,
      b.image_url,
      b.cdn_image_url,
      b.preview_image_url,
      b.homepage_image_url,
      '{}'::jsonb,
      '',
      lower(concat_ws(
        ' ',
        b.name,
        b.version,
        b.expansion->>'name',
        b.blueprint->'fixed_properties'->>'collector_number',
        (
          select string_agg(b.blueprint->'fixed_properties'->>key, ' ')
          from unnest($2::text[]) as key
        )
      )) as search_text,
      left(public.marketplace_search_compact(b.name), 3) as name_prefix,
      left(public.marketplace_search_compact(coalesce(b.expansion->>'name', '')), 3) as set_prefix,
      public.marketplace_search_compact(coalesce(b.expansion->>'name', '')) as expansion_name,
      (
        case when b.category_id = any($1::integer[]) then 0 else 8 end +
        case when b.cdn_image_url is not null then 4 else 0 end +
        case when coalesce(b.blueprint->'fixed_properties'->>'collector_number', '') <> '' then 6 else 0 end
      )::numeric as search_weight,
      b.imported_at,
      now()
    from %s b
    where coalesce(b.cdn_image_url, b.preview_image_url, b.image_url) is not null
    on conflict (card_id) do update set
      ct_id = excluded.ct_id,
      name = excluded.name,
      source_name = excluded.source_name,
      display_name = excluded.display_name,
      canonical_name = excluded.canonical_name,
      set_name = excluded.set_name,
      card_number = excluded.card_number,
      product_variant = excluded.product_variant,
      rarity = excluded.rarity,
      card_type = excluded.card_type,
      item_kind = excluded.item_kind,
      product_type = excluded.product_type,
      image_url = excluded.image_url,
      cdn_image_url = excluded.cdn_image_url,
      preview_image_url = excluded.preview_image_url,
      homepage_image_url = excluded.homepage_image_url,
      search_text = excluded.search_text,
      name_prefix = excluded.name_prefix,
      set_prefix = excluded.set_prefix,
      expansion_name = excluded.expansion_name,
      search_weight = excluded.search_weight,
      imported_at = excluded.imported_at,
      projected_at = now()
  $sql$, qualified_raw)
  using card_category_ids, rarity_keys;

  get diagnostics refreshed_count = row_count;

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
        c.name,
        coalesce(c.card_number, '') as card_number,
        coalesce(nullif(trim(c.set_name), ''), 'Unknown') as set_name,
        c.item_kind,
        c.product_type,
        c.projected_at,
        coalesce(nullif(trim(both '-' from concat_ws(
          '-',
          public.marketplace_url_slug_part(coalesce(nullif(trim(c.rarity), ''), 'Card')),
          public.marketplace_url_slug_part(c.name),
          public.marketplace_url_slug_part(
            public.marketplace_card_url_collector_number(c.card_number, c.card_id)
          ),
          public.marketplace_url_slug_part(coalesce(nullif(trim(c.set_name), ''), 'Unknown'))
        )), ''), 'card') as canonical_slug
      from public.marketplace_search_candidates c
    ) source
  ) parsed;

  return refreshed_count;
end;
$$;

comment on function public.refresh_multigame_marketplace_projections(text, integer[], text[]) is
  'Project isolated CardTrader blueprints into public marketplace_search_candidates + marketplace_card_urls. card_id = ct_id * 2.';
