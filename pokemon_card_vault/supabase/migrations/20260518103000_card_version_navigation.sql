create table if not exists public.marketplace_card_versions (
  card_id bigint primary key,
  name text not null,
  expansion_name text not null,
  expansion_number text not null,
  expansion_number_int integer,
  blueprint_id bigint not null,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  projected_at timestamptz not null default now()
);

create index if not exists marketplace_card_versions_exact_idx
  on public.marketplace_card_versions (
    lower(name),
    lower(expansion_name),
    expansion_number_int,
    expansion_number,
    blueprint_id
  );

create or replace function public.refresh_marketplace_card_versions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  insert into public.marketplace_card_versions (
    card_id,
    name,
    expansion_name,
    expansion_number,
    expansion_number_int,
    blueprint_id,
    image_url,
    cdn_image_url,
    preview_image_url,
    projected_at
  )
  select
    b.id,
    b.name,
    coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as expansion_name,
    coalesce(
      nullif(b.blueprint->>'number', ''),
      nullif(b.blueprint->>'collector_number', ''),
      nullif(b.blueprint->>'card_number', ''),
      b.version,
      b.id::text
    ) as expansion_number,
    nullif(
      substring(coalesce(
        nullif(b.blueprint->>'number', ''),
        nullif(b.blueprint->>'collector_number', ''),
        nullif(b.blueprint->>'card_number', ''),
        b.version,
        b.id::text
      ) from '[0-9]+'),
      ''
    )::integer as expansion_number_int,
    b.id as blueprint_id,
    b.image_url,
    b.cdn_image_url,
    b.preview_image_url,
    now()
  from public.cardtrader_pokemon_blueprints b
  where b.cdn_image_url is not null
  on conflict (card_id) do update set
    name = excluded.name,
    expansion_name = excluded.expansion_name,
    expansion_number = excluded.expansion_number,
    expansion_number_int = excluded.expansion_number_int,
    blueprint_id = excluded.blueprint_id,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    projected_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.get_adjacent_marketplace_card_versions(target_card_id bigint)
returns table(previous_id text, next_id text)
language sql
stable
set search_path = public
as $$
  with target as (
    select *
    from public.marketplace_card_versions
    where card_id = target_card_id
    limit 1
  ),
  same_expansion as (
    select v.*
    from public.marketplace_card_versions v
    join target t
      on lower(v.name) = lower(t.name)
     and v.expansion_name = t.expansion_name
  ),
  ordered as (
    select
      card_id,
      row_number() over (
        order by expansion_number_int nulls last, expansion_number, blueprint_id
      ) as rn,
      count(*) over () as total
    from same_expansion
  ),
  current_row as (
    select rn, total
    from ordered
    where card_id = target_card_id
  )
  select
    prev.card_id::text as previous_id,
    next.card_id::text as next_id
  from current_row cur
  left join ordered prev
    on prev.rn = case when cur.rn = 1 then cur.total else cur.rn - 1 end
  left join ordered next
    on next.rn = case when cur.rn = cur.total then 1 else cur.rn + 1 end;
$$;

alter table public.marketplace_card_versions enable row level security;

drop policy if exists "Marketplace card versions are publicly readable" on public.marketplace_card_versions;
create policy "Marketplace card versions are publicly readable"
  on public.marketplace_card_versions
  for select
  to anon, authenticated
  using (true);

select public.refresh_marketplace_card_versions();
