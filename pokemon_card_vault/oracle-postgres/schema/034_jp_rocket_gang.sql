-- Rocket Gang (rog) is the Japanese ロケット団 set (64 cards). CardTrader's
-- English name was aliased to pokemontcg.io base4 (Base Set 2), zero
-- pokemon_language votes, so pokoin_expansion_nationality() fell through to
-- western and the set desk showed the EU flag.
--
-- English Team Rocket stays `tr` / base5 (83 cards). Do not pin tr.
-- Rocket Gang Strikes Back (`rgsb` / PCG3) is already japanese via tcgdex-ja.

begin;
set local statement_timeout = 0;

create or replace function public.pokoin_expansion_nationality(code text, name text)
returns text
language sql
immutable
as $fn$
  select case
    when coalesce(name, '') ~* 'korean' then 'korean'
    when coalesce(name, '') ~* 'thailand|indonesia' then 'unknown'
    when coalesce(name, '') ~* 'simplified chinese|traditional chinese|gem pack|^collect 151'
      or coalesce(code, '') ~* '^(cs[mv0-9]|csv|csm|cbb)'
      or lower(coalesce(code, '')) in ('151c', 'svp-c', '30thc')
      then 'chinese'
    when coalesce(name, '') ~* 'products?'
      or lower(coalesce(code, '')) in ('popr', 'svproducts', 'pkm-center', 'meproducts')
      then 'product'
    when lower(coalesce(code, '')) in (
        'sm-p', 's-p', 'mp-promo', 'sl', 'mc', 'pvs', 'ec1', 'xy', 'pxy',
        'dp-promos', 'svjp', 'svd', 'svc', 'svaw', 'svam', 'sval', 'svjl',
        'pt1', 'pt2', 'pt3', 'aoa', 'exsh', 'dp2-sol', 'ebb',
        'wcp', 'cbs', 'cfm', 'hrt', 'mic', 'uns',
        'awl', 'awlpf', 'gstnw', 'n1pf', 'ctr', 'neojp',
        'rog'
      )
      or coalesce(code, '') ~* '^(s[0-9]|sv[0-9]|sm[0-9]|m[0-9]|sp[0-9]|scjp|gym)'
      or coalesce(name, '') ~* 'movie commemoration|start deck 100|southern islands jp|constructed starter|half deck|battle master deck|battle strength deck|^world champions pack$|^awakening legends|gold, silver, to a new world|crossing the ruins|^rocket gang($| )'
      then 'japanese'
    else 'western'
  end;
$fn$;

create or replace function public.pokoin_refresh_expansion_nationality()
returns integer
language plpgsql
as $$
declare updated_count integer := 0;
begin
  with card as (
    select b.expansion_id, (
      select e2->'possible_values'
      from jsonb_array_elements(b.editable_properties) e2
      where e2->>'name' = 'pokemon_language' limit 1
    ) as langs
    from public.pokoin_pokemon_blueprints b
    where b.expansion_id is not null
  ), voted as (
    select expansion_id,
      count(*) filter (where langs @> '["jp"]'::jsonb and not (langs ?| array['en','fr','de','it'])) as jp_only,
      count(*) filter (where langs ?| array['en','fr','de','it'] and not langs @> '["jp"]'::jsonb) as western,
      count(*) filter (where langs ?| array['zh-CN','zh-TW','zh'] and not langs @> '["jp"]'::jsonb and not (langs ?| array['en','fr','de','it'])) as zh
    from card group by 1
  ), classified as (
    select e.expansion_id,
      case
        when public.pokoin_expansion_nationality(e.code, e.name) = 'product' then 'product'
        when public.pokoin_expansion_nationality(e.code, e.name) = 'korean' then 'korean'
        when public.pokoin_expansion_nationality(e.code, e.name) = 'chinese' then 'chinese'
        when e.official_source = 'tcgdex-ja' then 'japanese'
        when e.official_source = 'tcgdex-zh-cn' then 'chinese'
        when lower(e.code) in ('awl', 'awlpf', 'gstnw', 'n1pf', 'ctr', 'neojp', 'rog') then 'japanese'
        when v.jp_only >= v.western and v.jp_only >= v.zh and v.jp_only > 0 then 'japanese'
        when v.western >= v.jp_only and v.western >= v.zh and v.western > 0 then 'western'
        when v.zh > 0 then 'chinese'
        else public.pokoin_expansion_nationality(e.code, e.name)
      end as nationality
    from public.pokoin_pokemon_expansions e
    join voted v on v.expansion_id = e.expansion_id
  )
  update public.pokoin_pokemon_expansions e
  set nationality = c.nationality,
      milo_gallery = public.pokoin_expansion_milo_gallery(c.nationality, e.kind),
      updated_at = now()
  from classified c
  where e.expansion_id = c.expansion_id
    and (e.nationality is distinct from c.nationality
         or e.milo_gallery is distinct from public.pokoin_expansion_milo_gallery(c.nationality, e.kind));
  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

update public.pokoin_pokemon_expansions
set nationality = 'japanese',
    milo_gallery = public.pokoin_expansion_milo_gallery('japanese', kind),
    updated_at = now()
where (lower(code) = 'rog' or name ~* '^rocket gang($| )')
  and nationality is distinct from 'japanese';

commit;

select code, name, nationality, milo_gallery, official_id, official_source
from public.pokoin_pokemon_expansions
where lower(code) in ('rog', 'tr', 'rgsb', 'trr')
   or name ~* 'rocket gang|^team rocket$'
order by name;
