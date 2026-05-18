create extension if not exists pg_trgm;

alter table public.cardtrader_pokemon_blueprints
  add column if not exists preview_image_url text,
  add column if not exists preview_object_key text;

create index if not exists cardtrader_pokemon_blueprints_name_trgm_idx
  on public.cardtrader_pokemon_blueprints using gin (name gin_trgm_ops);

create or replace function public.search_cardtrader_pokemon_blueprints(
  search_term text,
  result_limit integer default 8
)
returns table (
  id bigint,
  name text,
  version text,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  blueprint jsonb,
  expansion jsonb,
  search_rank real
)
language sql
stable
as $$
  with normalized as (
    select nullif(trim(search_term), '') as q
  )
  select
    b.id,
    b.name,
    b.version,
    b.image_url,
    b.cdn_image_url,
    b.preview_image_url,
    b.blueprint,
    b.expansion,
    greatest(
      similarity(lower(b.name), lower(n.q)),
      ts_rank_cd(
        to_tsvector('simple', coalesce(b.name, '') || ' ' || coalesce(b.expansion->>'name', '')),
        plainto_tsquery('simple', n.q)
      )
    )::real as search_rank
  from public.cardtrader_pokemon_blueprints b
  cross join normalized n
  where
    n.q is not null
    and (
      b.name ilike '%' || n.q || '%'
      or coalesce(b.expansion->>'name', '') ilike '%' || n.q || '%'
      or similarity(lower(b.name), lower(n.q)) > 0.18
      or to_tsvector('simple', coalesce(b.name, '') || ' ' || coalesce(b.expansion->>'name', ''))
        @@ plainto_tsquery('simple', n.q)
    )
    and coalesce(b.cdn_image_url, b.image_url) is not null
  order by
    case when lower(b.name) = lower(n.q) then 0 else 1 end,
    case when lower(b.name) like lower(n.q) || '%' then 0 else 1 end,
    search_rank desc,
    b.name asc
  limit least(greatest(result_limit, 1), 20);
$$;
