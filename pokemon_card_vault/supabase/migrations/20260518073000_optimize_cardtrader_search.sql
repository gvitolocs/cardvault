create index if not exists cardtrader_pokemon_blueprints_expansion_name_trgm_idx
  on public.cardtrader_pokemon_blueprints
  using gin ((coalesce(expansion->>'name', '')) gin_trgm_ops);

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
    select lower(nullif(trim(search_term), '')) as q
  ),
  candidates as (
    select
      b.*,
      n.q,
      coalesce(b.expansion->>'name', '') as expansion_name
    from public.cardtrader_pokemon_blueprints b
    cross join normalized n
    where
      n.q is not null
      and coalesce(b.cdn_image_url, b.image_url) is not null
      and (
        b.name ilike n.q || '%'
        or b.name ilike '%' || n.q || '%'
        or b.name % n.q
        or coalesce(b.expansion->>'name', '') ilike n.q || '%'
      )
    order by
      case when lower(b.name) = n.q then 0 else 1 end,
      case when lower(b.name) like n.q || '%' then 0 else 1 end,
      similarity(b.name, n.q) desc,
      b.name asc
    limit least(greatest(result_limit * 6, 12), 80)
  )
  select
    c.id,
    c.name,
    c.version,
    c.image_url,
    c.cdn_image_url,
    c.preview_image_url,
    c.blueprint,
    c.expansion,
    greatest(
      similarity(c.name, c.q),
      similarity(c.expansion_name, c.q) * 0.65
    )::real as search_rank
  from candidates c
  order by
    case when lower(c.name) = c.q then 0 else 1 end,
    case when lower(c.name) like c.q || '%' then 0 else 1 end,
    search_rank desc,
    c.name asc
  limit least(greatest(result_limit, 1), 20);
$$;
