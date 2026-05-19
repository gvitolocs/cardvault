create extension if not exists pg_trgm with schema extensions;

create or replace function public.marketplace_search_normalize(value text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function public.marketplace_search_compact(value text)
returns text
language sql
immutable
as $$
  select regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]', '', 'g');
$$;

create or replace function public.marketplace_search_tokenize(value text)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(token order by token), '{}'::text[])
  from (
    select distinct token
    from regexp_split_to_table(public.marketplace_search_normalize(value), ' ') token
    where token <> ''
      and (length(token) >= 2 or token ~ '^[0-9]+$')
  ) tokens;
$$;

create table if not exists public.marketplace_card_names (
  name text primary key,
  normalized_name text not null,
  compact_name text not null,
  name_tokens text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_card_names_normalized_trgm_idx
  on public.marketplace_card_names using gin (normalized_name gin_trgm_ops);

create index if not exists marketplace_card_names_compact_trgm_idx
  on public.marketplace_card_names using gin (compact_name gin_trgm_ops);

create table if not exists public.marketplace_rarities (
  rarity text primary key,
  normalized_rarity text not null,
  compact_rarity text not null,
  rarity_tokens text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_rarities_normalized_trgm_idx
  on public.marketplace_rarities using gin (normalized_rarity gin_trgm_ops);

create index if not exists marketplace_rarities_compact_trgm_idx
  on public.marketplace_rarities using gin (compact_rarity gin_trgm_ops);

create table if not exists public.marketplace_expansion_numbers (
  card_number text primary key,
  number_int integer,
  normalized_number text not null,
  compact_number text not null,
  number_tokens text[] not null default '{}'::text[],
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_expansion_numbers_number_int_idx
  on public.marketplace_expansion_numbers (number_int);

create index if not exists marketplace_expansion_numbers_compact_idx
  on public.marketplace_expansion_numbers (compact_number);

alter table public.cardtrader_pokemon_expansions
  add column if not exists compact_name text,
  add column if not exists name_tokens text[] not null default '{}'::text[];

create index if not exists cardtrader_pokemon_expansions_normalized_name_key
  on public.cardtrader_pokemon_expansions (normalized_name);

create index if not exists cardtrader_pokemon_expansions_normalized_trgm_idx
  on public.cardtrader_pokemon_expansions using gin (normalized_name gin_trgm_ops);

create index if not exists cardtrader_pokemon_expansions_compact_trgm_idx
  on public.cardtrader_pokemon_expansions using gin (compact_name gin_trgm_ops);

alter table public.marketplace_search_candidates
  add column if not exists expansion_name text not null default '';

create index if not exists marketplace_search_candidates_expansion_name_idx
  on public.marketplace_search_candidates (expansion_name, search_weight desc);

create or replace function public.refresh_marketplace_token_search_index()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  insert into public.marketplace_card_names (
    name,
    normalized_name,
    compact_name,
    name_tokens,
    updated_at
  )
  select
    source.name,
    public.marketplace_search_normalize(source.name),
    public.marketplace_search_compact(source.name),
    public.marketplace_search_tokenize(source.name),
    now()
  from (
    select distinct c.name
    from public.marketplace_search_candidates c
    where c.name is not null and c.name <> ''
  ) source
  on conflict (name) do update set
    normalized_name = excluded.normalized_name,
    compact_name = excluded.compact_name,
    name_tokens = excluded.name_tokens,
    updated_at = now();

  insert into public.marketplace_rarities (
    rarity,
    normalized_rarity,
    compact_rarity,
    rarity_tokens,
    updated_at
  )
  select
    source.rarity,
    public.marketplace_search_normalize(source.rarity),
    public.marketplace_search_compact(source.rarity),
    public.marketplace_search_tokenize(source.rarity),
    now()
  from (
    select distinct c.rarity
    from public.marketplace_search_candidates c
    where c.rarity is not null and c.rarity <> ''
  ) source
  on conflict (rarity) do update set
    normalized_rarity = excluded.normalized_rarity,
    compact_rarity = excluded.compact_rarity,
    rarity_tokens = excluded.rarity_tokens,
    updated_at = now();

  insert into public.marketplace_expansion_numbers (
    card_number,
    number_int,
    normalized_number,
    compact_number,
    number_tokens,
    updated_at
  )
  select
    source.card_number,
    public.marketplace_expansion_number_int(source.card_number),
    public.marketplace_search_normalize(source.card_number),
    public.marketplace_search_compact(source.card_number),
    public.marketplace_search_tokenize(source.card_number),
    now()
  from (
    select distinct c.card_number
    from public.marketplace_search_candidates c
    where c.card_number is not null and c.card_number <> ''
  ) source
  on conflict (card_number) do update set
    number_int = excluded.number_int,
    normalized_number = excluded.normalized_number,
    compact_number = excluded.compact_number,
    number_tokens = excluded.number_tokens,
    updated_at = now();

  insert into public.cardtrader_pokemon_expansions (
    expansion_id,
    game_id,
    code,
    name,
    compact_name,
    name_tokens,
    updated_at
  )
  select
    source.expansion_id,
    source.game_id,
    source.code,
    source.name,
    public.marketplace_search_compact(source.name),
    public.marketplace_search_tokenize(source.name),
    now()
  from (
    select distinct on (b.expansion_id)
      b.expansion_id,
      b.game_id,
      nullif(b.expansion->>'code', '') as code,
      coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as name
    from public.cardtrader_pokemon_blueprints b
    where b.expansion_id is not null
    order by
      b.expansion_id,
      case when nullif(b.expansion->>'name', '') is null then 1 else 0 end,
      b.imported_at desc nulls last
  ) source
  on conflict (expansion_id) do update set
    game_id = excluded.game_id,
    code = coalesce(public.cardtrader_pokemon_expansions.code, excluded.code),
    name = excluded.name,
    compact_name = excluded.compact_name,
    name_tokens = excluded.name_tokens,
    updated_at = now();

  update public.cardtrader_pokemon_expansions e
  set
    compact_name = public.marketplace_search_compact(e.name),
    name_tokens = public.marketplace_search_tokenize(e.name),
    updated_at = now()
  where e.compact_name is null
    or e.name_tokens = '{}'::text[];

  update public.marketplace_search_candidates c
  set expansion_name = public.marketplace_search_normalize(c.set_name)
  where c.expansion_name = ''
    or c.expansion_name is null;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

alter table public.marketplace_card_names enable row level security;
alter table public.marketplace_rarities enable row level security;
alter table public.marketplace_expansion_numbers enable row level security;

drop policy if exists "Marketplace card names are publicly readable" on public.marketplace_card_names;
create policy "Marketplace card names are publicly readable"
  on public.marketplace_card_names for select to anon, authenticated using (true);

drop policy if exists "Marketplace rarities are publicly readable" on public.marketplace_rarities;
create policy "Marketplace rarities are publicly readable"
  on public.marketplace_rarities for select to anon, authenticated using (true);

drop policy if exists "Marketplace expansion numbers are publicly readable" on public.marketplace_expansion_numbers;
create policy "Marketplace expansion numbers are publicly readable"
  on public.marketplace_expansion_numbers for select to anon, authenticated using (true);

create or replace function public.search_marketplace_blueprint_candidates_v2(
  search_term text,
  result_limit integer default 20,
  result_offset integer default 0
)
returns table (
  card_id bigint,
  name text,
  set_name text,
  card_number text,
  rarity text,
  card_type text,
  item_kind text,
  product_type text,
  trainer_name text,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  imported_at timestamptz,
  search_rank real
)
language sql
stable
security definer
set search_path = public
as $$
  with normalized as (
    select
      public.marketplace_search_normalize(search_term) as q,
      public.marketplace_search_compact(search_term) as compact_q,
      least(greatest(result_limit, 1), 15874) as clean_limit,
      least(greatest(result_offset, 0), 15874) as clean_offset
  ),
  query_tokens as (
    select distinct token
    from normalized n
    cross join lateral unnest(public.marketplace_search_tokenize(n.q)) token
    where token <> ''
  ),
  name_hits as (
    select
      qt.token as query_token,
      'name'::text as token_kind,
      n.name as entity_key,
      (
        case
          when n.normalized_name = qt.token then 1300
          when n.compact_name = public.marketplace_search_compact(qt.token) then 1220
          when n.normalized_name like qt.token || '%' then 1040
          when n.compact_name like public.marketplace_search_compact(qt.token) || '%' then 980
          when n.normalized_name % qt.token then 780 + similarity(n.normalized_name, qt.token) * 220
          when length(qt.token) >= 4 and word_similarity(n.normalized_name, qt.token) >= 0.38 then 700 + word_similarity(n.normalized_name, qt.token) * 200
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_card_names n
      on n.normalized_name = qt.token
      or n.compact_name = public.marketplace_search_compact(qt.token)
      or n.normalized_name like qt.token || '%'
      or n.compact_name like public.marketplace_search_compact(qt.token) || '%'
      or (length(qt.token) >= 4 and n.normalized_name % qt.token)
      or (length(qt.token) >= 4 and word_similarity(n.normalized_name, qt.token) >= 0.38)
  ),
  rarity_hits as (
    select
      qt.token as query_token,
      'rarity'::text as token_kind,
      r.rarity as entity_key,
      (
        case
          when r.normalized_rarity = qt.token then 980
          when r.compact_rarity = public.marketplace_search_compact(qt.token) then 940
          when r.normalized_rarity like qt.token || '%' then 720
          when length(qt.token) >= 4 and r.normalized_rarity % qt.token then 560 + similarity(r.normalized_rarity, qt.token) * 160
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_rarities r
      on r.normalized_rarity = qt.token
      or r.compact_rarity = public.marketplace_search_compact(qt.token)
      or r.normalized_rarity like qt.token || '%'
      or (length(qt.token) >= 4 and r.normalized_rarity % qt.token)
  ),
  number_hits as (
    select
      qt.token as query_token,
      'number'::text as token_kind,
      num.card_number as entity_key,
      (
        case
          when num.normalized_number = qt.token then 1120
          when num.compact_number = public.marketplace_search_compact(qt.token) then 1120
          when num.normalized_number like qt.token || '%' then 860
          when num.compact_number like public.marketplace_search_compact(qt.token) || '%' then 820
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_expansion_numbers num
      on num.normalized_number = qt.token
      or num.compact_number = public.marketplace_search_compact(qt.token)
      or num.normalized_number like qt.token || '%'
      or num.compact_number like public.marketplace_search_compact(qt.token) || '%'
  ),
  expansion_hits as (
    select
      qt.token as query_token,
      'expansion'::text as token_kind,
      e.normalized_name as entity_key,
      (
        case
          when e.normalized_name = qt.token then 1050
          when e.compact_name = public.marketplace_search_compact(qt.token) then 1030
          when e.normalized_name like qt.token || '%' then 820
          when e.compact_name like public.marketplace_search_compact(qt.token) || '%' then 780
          when length(qt.token) >= 4 and e.normalized_name % qt.token then 620 + similarity(e.normalized_name, qt.token) * 180
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.cardtrader_pokemon_expansions e
      on e.normalized_name = qt.token
      or e.compact_name = public.marketplace_search_compact(qt.token)
      or e.normalized_name like qt.token || '%'
      or e.compact_name like public.marketplace_search_compact(qt.token) || '%'
      or (length(qt.token) >= 4 and e.normalized_name % qt.token)
  ),
  token_blueprints as (
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 640 + c.search_weight as score
    from name_hits h
    join public.marketplace_search_candidates c on c.name = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 320 + c.search_weight as score
    from rarity_hits h
    join public.marketplace_search_candidates c on c.rarity = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 560 + c.search_weight as score
    from number_hits h
    join public.marketplace_search_candidates c on c.card_number = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 440 + c.search_weight as score
    from expansion_hits h
    join public.marketplace_search_candidates c on c.expansion_name = h.entity_key
  ),
  per_card_token as (
    select
      card_id,
      query_token,
      max(score) as token_score,
      bool_or(token_kind = 'name') as matched_name,
      bool_or(token_kind = 'number') as matched_number,
      bool_or(token_kind = 'expansion') as matched_expansion,
      bool_or(token_kind = 'rarity') as matched_rarity
    from token_blueprints
    group by card_id, query_token
  ),
  scored_cards as (
    select
      c.*,
      coalesce(sum(p.token_score), 0)
        + count(distinct p.query_token) * 420
        + case when count(distinct p.query_token) = (select count(*) from query_tokens) then 900 else 0 end
        + case when bool_or(p.matched_name) and bool_or(p.matched_number) then 700 else 0 end
        + case when bool_or(p.matched_name) and bool_or(p.matched_expansion) then 520 else 0 end
        + case when bool_or(p.matched_name) and bool_or(p.matched_rarity) then 360 else 0 end
        + case when c.item_kind = 'product' then -80 else 0 end as rank_score,
      count(distinct p.query_token) as matched_tokens
    from public.marketplace_search_candidates c
    join per_card_token p on p.card_id = c.card_id
    group by
      c.card_id,
      c.name,
      c.set_name,
      c.card_number,
      c.rarity,
      c.card_type,
      c.item_kind,
      c.product_type,
      c.trainer_name,
      c.image_url,
      c.cdn_image_url,
      c.preview_image_url,
      c.search_text,
      c.name_prefix,
      c.set_prefix,
      c.search_weight,
      c.imported_at,
      c.projected_at,
      c.expansion_name
  ),
  fallback_candidates as (
    select
      c.*,
      (
        case
          when public.marketplace_search_compact(c.name) like (select compact_q from normalized) || '%' then 1400
          when public.marketplace_search_compact(c.set_name) like (select compact_q from normalized) || '%' then 760
          when public.marketplace_search_compact(c.card_number) like (select compact_q from normalized) || '%' then 980
          else 0
        end
        + c.search_weight
        + case when c.item_kind = 'product' then -80 else 0 end
      )::numeric as rank_score,
      1::bigint as matched_tokens
    from public.marketplace_search_candidates c
    cross join normalized n
    where n.q <> ''
      and n.compact_q <> ''
      and (
        public.marketplace_search_compact(c.name) like n.compact_q || '%'
        or public.marketplace_search_compact(c.set_name) like n.compact_q || '%'
        or public.marketplace_search_compact(c.card_number) like n.compact_q || '%'
      )
    order by rank_score desc, c.name asc, c.card_number asc
    limit least(greatest((select clean_limit + clean_offset from normalized), 1), 15874)
  ),
  candidates as (
    select distinct on (card_id) *
    from (
      select * from scored_cards
      union all
      select * from fallback_candidates
      where (select count(*) from scored_cards) < (select clean_limit from normalized)
    ) pooled
    order by card_id, rank_score desc
  )
  select
    c.card_id,
    c.name,
    c.set_name,
    c.card_number,
    c.rarity,
    c.card_type,
    c.item_kind,
    c.product_type,
    c.trainer_name,
    c.image_url,
    c.cdn_image_url,
    c.preview_image_url,
    c.imported_at,
    c.rank_score::real as search_rank
  from candidates c
  order by c.rank_score desc, c.matched_tokens desc, c.name asc, c.card_number asc
  limit (select clean_limit from normalized)
  offset (select clean_offset from normalized);
$$;

select public.refresh_marketplace_token_search_index();
