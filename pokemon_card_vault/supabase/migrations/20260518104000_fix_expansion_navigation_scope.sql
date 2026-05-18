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
      on v.expansion_name = t.expansion_name
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
    case when cur.total > 1 then prev.card_id::text end as previous_id,
    case when cur.total > 1 then next.card_id::text end as next_id
  from current_row cur
  left join ordered prev
    on prev.rn = case when cur.rn = 1 then cur.total else cur.rn - 1 end
  left join ordered next
    on next.rn = case when cur.rn = cur.total then 1 else cur.rn + 1 end;
$$;
