-- Visual check of one CDN face per uncertain expansion (nezopt cdn_images).
-- CSV9.5 is Simplified Chinese (Sylveon ex, CSMS-C), not Japanese.
-- CS*/CBB*/151c codes are mainland Chinese even when CardTrader language is jp.
-- DPt pt1–pt3 / Advent of Arceus / Expansion Sheet / Secret of the Lakes are Japanese cards.
-- Some side_product bins are still card faces (Happy Set, Chinese starters, theme exclusives,
-- Play! prize, McDonald's, Battle Academy Armarouge, JP Expansion Pack).

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
        'pt1', 'pt2', 'pt3', 'aoa', 'exsh', 'dp2-sol', 'ebb'
      )
      or coalesce(code, '') ~* '^(s[0-9]|sv[0-9]|sm[0-9]|m[0-9]|sp[0-9]|scjp|gym)'
      or coalesce(name, '') ~* 'movie commemoration|start deck 100|southern islands jp|constructed starter|half deck|battle master deck|battle strength deck'
      then 'japanese'
    else 'western'
  end;
$fn$;

-- Pin CS* / CBB* / 151c to chinese before the language vote.
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

-- Official ids from the card stamp / TCGDex, after looking at a face.
update public.pokoin_pokemon_expansions set official_id='CSV9.5C', official_name='太晶盛聚', official_source='tcgdex-zh-cn', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='csv9.5';
update public.pokoin_pokemon_expansions set official_id='CSV10C', official_name='Chasing Glory', official_source='visual', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='csv10';
update public.pokoin_pokemon_expansions set official_id='151C', official_name='Collect 151', official_source='visual', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='151c';
update public.pokoin_pokemon_expansions set official_id='CBB1C', official_name='Gem Pack Vol.1', official_source='visual', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='cbb1c';
update public.pokoin_pokemon_expansions set official_id='CBB6C', official_name='Gem Pack Vol.6', official_source='visual', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='cbb6c';
update public.pokoin_pokemon_expansions set official_id='CSVL1C', official_name='Adventure Special Pack', official_source='visual', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='csvl1';
update public.pokoin_pokemon_expansions set official_id='CSVL2C', official_name='Travel Special Pack', official_source='visual', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='csvl2';
update public.pokoin_pokemon_expansions set official_id='CSVH5C', official_name='Happy Set', official_source='visual', kind='official', listed=true, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='csvh5';
update public.pokoin_pokemon_expansions set official_id='CS5DC', official_name='Gallant Galaxy V Starter Deck', official_source='visual', kind='official', listed=false, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='cs5d';
update public.pokoin_pokemon_expansions set official_id='CSM2d', official_name='Shining Synergy GX Starter Deck', official_source='visual', kind='official', listed=false, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='csm2d';
update public.pokoin_pokemon_expansions set official_id='CSM1d', official_name='Storming Emergence GX Starter Deck', official_source='visual', kind='official', listed=false, nationality='chinese', milo_gallery='chinese', updated_at=now() where code='csm1d';

update public.pokoin_pokemon_expansions set official_id='DP2', official_name='湖の秘密', official_source='tcgdex-ja', kind='official', listed=true, nationality='japanese', milo_gallery='japanese', updated_at=now() where code='dp2-sol';
update public.pokoin_pokemon_expansions set official_id='Pt3', official_name='Beat of the Frontier', official_source='visual', kind='official', listed=true, nationality='japanese', milo_gallery='japanese', updated_at=now() where code='pt3';
update public.pokoin_pokemon_expansions set official_id='Pt2', official_name='Bonds to the End of Time', official_source='visual', kind='official', listed=true, nationality='japanese', milo_gallery='japanese', updated_at=now() where code='pt2';
update public.pokoin_pokemon_expansions set official_id='Pt1', official_name='Galactic''s Conquest', official_source='visual', kind='official', listed=true, nationality='japanese', milo_gallery='japanese', updated_at=now() where code='pt1';
update public.pokoin_pokemon_expansions set official_id='Pt4', official_name='Advent of Arceus', official_source='visual', kind='official', listed=true, nationality='japanese', milo_gallery='japanese', updated_at=now() where code='aoa';
update public.pokoin_pokemon_expansions set official_id='EBB', official_name='EX Battle Boost', official_source='visual', kind='official', listed=true, nationality='japanese', milo_gallery='japanese', updated_at=now() where code='ebb';
update public.pokoin_pokemon_expansions set nationality='japanese', milo_gallery='japanese', kind='official', listed=false, official_source='visual', updated_at=now() where code='exsh';
update public.pokoin_pokemon_expansions set milo_gallery='japanese', kind='official', listed=false, official_source='visual', updated_at=now() where code in ('1ep','1epnr');

-- English card faces that were parked as side_product after name heuristics.
update public.pokoin_pokemon_expansions set milo_gallery='western', kind='subset', official_source='visual', updated_at=now() where code='deckexclusives';
update public.pokoin_pokemon_expansions set milo_gallery='western', kind='promo', official_source='visual', updated_at=now() where code='playprizep';
update public.pokoin_pokemon_expansions set milo_gallery='western', kind='promo', official_source='visual', updated_at=now() where code in ('mc21','mcf18','mcmp');
update public.pokoin_pokemon_expansions set milo_gallery='western', kind='official', listed=false, official_source='visual', updated_at=now() where code in ('ba-2024','ba-22','ba-20','svl');
update public.pokoin_pokemon_expansions set milo_gallery='western', kind='promo', official_source='visual', updated_at=now() where code='holy';
update public.pokoin_pokemon_expansions set milo_gallery='chinese', kind='unmatched', official_source='visual', updated_at=now() where code='csve1';

select public.pokoin_refresh_expansion_nationality() as expansions_updated;

-- Re-apply visual gallery pins the refresh may have cleared for side_product kinds we promoted.
update public.pokoin_pokemon_expansions
set milo_gallery = nationality, updated_at=now()
where code in (
  'csv9.5','csv10','151c','cbb1c','cbb6c','csvl1','csvl2','csvh5','cs5d','csm2d','csm1d',
  'dp2-sol','pt1','pt2','pt3','aoa','ebb','exsh','1ep','1epnr',
  'deckexclusives','playprizep','mc21','mcf18','mcmp','ba-2024','ba-22','ba-20','svl','holy','csve1'
)
and nationality in ('western','japanese','chinese');

drop view if exists public.cardtrader_pokemon_expansions;
create view public.cardtrader_pokemon_expansions as
  select * from public.pokoin_pokemon_expansions;

commit;
