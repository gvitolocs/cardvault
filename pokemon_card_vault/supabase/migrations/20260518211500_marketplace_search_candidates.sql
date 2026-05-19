create extension if not exists pg_trgm with schema extensions;

create table if not exists public.marketplace_search_candidates (
  card_id bigint primary key,
  name text not null,
  set_name text not null default 'Pokemon',
  card_number text not null default '',
  rarity text not null default 'Card',
  card_type text not null default 'Card',
  item_kind text not null default 'single' check (item_kind in ('single', 'product')),
  product_type text not null default 'card',
  trainer_name text not null default '',
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  search_text text not null default '',
  name_prefix text not null default '',
  set_prefix text not null default '',
  search_weight numeric not null default 0,
  imported_at timestamptz,
  projected_at timestamptz not null default now()
);

create index if not exists marketplace_search_candidates_name_prefix_idx
  on public.marketplace_search_candidates (name_prefix, search_weight desc, imported_at desc nulls last);

create index if not exists marketplace_search_candidates_set_prefix_idx
  on public.marketplace_search_candidates (set_prefix, search_weight desc, imported_at desc nulls last);

create index if not exists marketplace_search_candidates_kind_idx
  on public.marketplace_search_candidates (item_kind, product_type, search_weight desc);

create index if not exists marketplace_search_candidates_search_text_trgm_idx
  on public.marketplace_search_candidates using gin (search_text gin_trgm_ops);

create index if not exists marketplace_search_candidates_trainer_idx
  on public.marketplace_search_candidates (trainer_name)
  where trainer_name <> '';

create or replace function public.refresh_marketplace_search_candidates()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  insert into public.marketplace_search_candidates (
    card_id,
    name,
    set_name,
    card_number,
    rarity,
    card_type,
    item_kind,
    product_type,
    trainer_name,
    image_url,
    cdn_image_url,
    preview_image_url,
    search_text,
    name_prefix,
    set_prefix,
    search_weight,
    imported_at,
    projected_at
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
    lower(concat_ws(
      ' ',
      c.name,
      c.set_name,
      c.card_number,
      c.rarity,
      c.card_type,
      c.item_kind,
      c.product_type,
      c.trainer_name,
      array_to_string(coalesce(t.aliases, '{}'::text[]), ' ')
    )) as search_text,
    left(regexp_replace(lower(c.name), '[^a-z0-9]', '', 'g'), 3) as name_prefix,
    left(regexp_replace(lower(c.set_name), '[^a-z0-9]', '', 'g'), 3) as set_prefix,
    (
      case when c.item_kind = 'product' then 12 else 0 end +
      case when c.rarity ilike '%rare%' then 8 else 0 end +
      case when c.name ~* '(^|[^a-z0-9])(ex|vmax|vstar|gx|lv\.x)([^a-z0-9]|$)' then 10 else 0 end +
      case when c.card_number ~ '/' then 10 else 0 end +
      case when c.card_number ~* 'illustration|secret|promo|gold|shiny' then 8 else 0 end +
      case when c.trainer_name <> '' then 6 else 0 end +
      case when c.preview_image_url is not null then 4 else 0 end
    )::numeric as search_weight,
    c.imported_at,
    now()
  from public.marketplace_cards c
  left join public.marketplace_trainers t
    on lower(t.trainer_name) = lower(c.trainer_name)
  where coalesce(c.preview_image_url, c.cdn_image_url, c.image_url) is not null
  on conflict (card_id) do update set
    name = excluded.name,
    set_name = excluded.set_name,
    card_number = excluded.card_number,
    rarity = excluded.rarity,
    card_type = excluded.card_type,
    item_kind = excluded.item_kind,
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    search_text = excluded.search_text,
    name_prefix = excluded.name_prefix,
    set_prefix = excluded.set_prefix,
    search_weight = excluded.search_weight,
    imported_at = excluded.imported_at,
    projected_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

alter table public.marketplace_search_candidates enable row level security;

drop policy if exists "Marketplace search candidates are publicly readable" on public.marketplace_search_candidates;
create policy "Marketplace search candidates are publicly readable"
  on public.marketplace_search_candidates
  for select
  to anon, authenticated
  using (true);

drop function if exists public.search_marketplace_candidates(text, integer);
drop function if exists public.search_marketplace_candidates(text, integer, integer);

create or replace function public.search_marketplace_candidates(
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
      lower(trim(coalesce(search_term, ''))) as q,
      left(regexp_replace(lower(trim(coalesce(search_term, ''))), '[^a-z0-9]', '', 'g'), 3) as compact_prefix
  ),
  terms as (
    select array_remove(regexp_split_to_array(q, '[^a-z0-9]+'), '') as parts
    from normalized
  ),
  strict_candidates as (
    select
      c.*,
      n.q,
      n.compact_prefix,
      case
        when lower(c.name) = n.q then 1200
        when lower(c.name) like n.q || '%' then 1000
        when c.name_prefix = n.compact_prefix then 880
        when lower(c.trainer_name) = n.q then 920
        when c.search_text ~ ('(^|[^a-z0-9])' || n.q || '([^a-z0-9]|$)') then 860
        when lower(c.card_number) = n.q then 860
        when lower(c.card_number) like n.q || '%' then 780
        when lower(c.set_name) like n.q || '%' then 620
        when lower(c.rarity) like '%' || n.q || '%' then 560
        when lower(c.trainer_name) like n.q || '%' then 540
        else 0
      end
      + case
          when c.trainer_name <> '' and c.search_text ~ ('(^|[^a-z0-9])' || n.q || '([^a-z0-9]|$)') then 620
          when c.trainer_name <> '' and c.search_text ilike '%' || n.q || '%' then 420
          else 0
        end
      + case
          when c.trainer_name <> ''
            and exists (
              select 1
              from unnest(t.parts) as trainer_term
              where length(trainer_term) >= 2
                and (
                  lower(c.trainer_name) = trainer_term
                  or c.search_text ~ ('(^|[^a-z0-9])' || trainer_term || '([^a-z0-9]|$)')
                )
            )
            and exists (
              select 1
              from unnest(t.parts) as name_term
              where length(name_term) >= 2
                and lower(c.name) ilike '%' || name_term || '%'
            )
          then 1400
          else 0
        end
      + greatest(similarity(c.search_text, n.q) * 280, 0)
      + greatest(word_similarity(c.name, n.q) * 460, 0)
      + greatest(word_similarity(c.search_text, n.q) * 180, 0)
      + greatest(similarity(c.name_prefix, n.compact_prefix) * 420, 0)
      + case
          when n.compact_prefix = 'pii' and c.name_prefix = 'pik' then 520
          else 0
        end
      + case
          when lower(c.name) ~ ('^' || n.q || '[[:space:]]+(ex|vmax|vstar|gx|v|lv\\.x)([^a-z0-9]|$)') then 360
          when lower(c.name) ~ ('^' || n.q || '[[:space:]]+') then 160
          else 0
        end
      + c.search_weight as rank_score
    from public.marketplace_search_candidates c
    cross join normalized n
    cross join terms t
    where n.q <> ''
      and length(n.compact_prefix) >= 3
      and (
        c.name_prefix = n.compact_prefix
        or c.set_prefix = n.compact_prefix
        or lower(c.name) ilike n.q || '%'
        or lower(c.trainer_name) = n.q
        or c.search_text ~ ('(^|[^a-z0-9])' || n.q || '([^a-z0-9]|$)')
        or c.search_text ilike '%' || n.q || '%'
        or lower(c.name) % n.q
        or word_similarity(c.name, n.q) >= 0.28
        or similarity(c.name_prefix, n.compact_prefix) >= 0.25
        or similarity(c.set_prefix, n.compact_prefix) >= 0.25
      )
    order by rank_score desc, c.name asc, c.card_number asc
    limit least(greatest((result_limit + result_offset) * 4, 40), 31748)
  ),
  prefix_candidates as (
    select
      c.*,
      n.q,
      n.compact_prefix,
      (
        case
          when c.name_prefix = n.compact_prefix then 420
          when c.set_prefix = n.compact_prefix then 280
          else 0
        end
        + greatest(similarity(c.search_text, n.q) * 120, 0)
        + c.search_weight
      ) as rank_score
    from public.marketplace_search_candidates c
    cross join normalized n
    where n.q <> ''
      and n.compact_prefix <> ''
      and length(n.compact_prefix) >= 3
      and (
        c.name_prefix = n.compact_prefix
        or c.set_prefix = n.compact_prefix
      )
    order by rank_score desc, c.name asc, c.card_number asc
    limit least(greatest((result_limit + result_offset) * 4, 40), 31748)
  ),
  broad_seed_candidates as (
    select
      c.*,
      n.q,
      n.compact_prefix,
      c.search_weight as rank_score
    from public.marketplace_search_candidates c
    cross join normalized n
    where n.q <> ''
      and length(n.compact_prefix) < 3
    order by c.search_weight desc, c.name asc, c.card_number asc
    limit least(greatest(result_limit + result_offset, 1), 15874)
  ),
  candidates as (
    select distinct on (card_id) *
    from (
      select *
      from strict_candidates
      union all
      select *
      from prefix_candidates
      where (select count(*) from strict_candidates) < result_limit
      union all
      select *
      from broad_seed_candidates
      where (select count(*) from strict_candidates) < result_limit
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
  order by c.rank_score desc, c.name asc, c.card_number asc
  limit least(greatest(result_limit, 1), 15874)
  offset least(greatest(result_offset, 0), 15874);
$$;

select public.refresh_marketplace_search_candidates();
