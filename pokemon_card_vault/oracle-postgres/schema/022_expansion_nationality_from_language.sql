-- APPLIED on pokoin-marketplace (2026-08-31).
-- Reclassify pokoin_pokemon_expansions.nationality from CardTrader
-- blueprint.editable_properties.pokemon_language (print market), not set-name regex.
-- 021 regex called Rising Fist / XY-era JP "western" because codes look English.
-- Language vote: jp_only ~24k blueprints vs western langs ~30k — they even out.
-- Chinese CS*/Gem Pack rows often have no pokemon_language; keep code heuristic.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;

create or replace function public.pokoin_refresh_expansion_nationality()
returns integer
language plpgsql
as $$
declare
  updated_count integer := 0;
begin
  with card as (
    select
      b.expansion_id,
      (
        select e2->'possible_values'
        from jsonb_array_elements(b.editable_properties) e2
        where e2->>'name' = 'pokemon_language'
        limit 1
      ) as langs
    from public.pokoin_pokemon_blueprints b
    where b.expansion_id is not null
  ),
  voted as (
    select
      expansion_id,
      count(*) filter (
        where langs @> '["jp"]'::jsonb
          and not (langs ?| array['en','fr','de','it'])
      ) as jp_only,
      count(*) filter (
        where langs ?| array['en','fr','de','it']
          and not langs @> '["jp"]'::jsonb
      ) as western,
      count(*) filter (
        where langs ?| array['zh-CN','zh-TW','zh']
          and not langs @> '["jp"]'::jsonb
          and not (langs ?| array['en','fr','de','it'])
      ) as zh
    from card
    group by 1
  ),
  classified as (
    select
      e.expansion_id,
      case
        when public.pokoin_expansion_nationality(e.code, e.name) = 'product' then 'product'
        when public.pokoin_expansion_nationality(e.code, e.name) = 'korean' then 'korean'
        when v.jp_only >= v.western and v.jp_only >= v.zh and v.jp_only > 0 then 'japanese'
        when v.western >= v.jp_only and v.western >= v.zh and v.western > 0 then 'western'
        when v.zh > 0 then 'chinese'
        else public.pokoin_expansion_nationality(e.code, e.name)
      end as nationality
    from public.pokoin_pokemon_expansions e
    join voted v on v.expansion_id = e.expansion_id
  )
  update public.pokoin_pokemon_expansions e
  set
    nationality = c.nationality,
    milo_gallery = public.pokoin_expansion_milo_gallery(c.nationality),
    updated_at = now()
  from classified c
  where e.expansion_id = c.expansion_id
    and (
      e.nationality is distinct from c.nationality
      or e.milo_gallery is distinct from public.pokoin_expansion_milo_gallery(c.nationality)
    );

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

select public.pokoin_refresh_expansion_nationality() as expansions_updated;

commit;
