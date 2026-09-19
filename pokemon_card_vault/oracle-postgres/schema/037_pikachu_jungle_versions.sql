-- Ken Sugimori Jungle Pikachu artwork across the original EN/JP printings,
-- the W-stamped promo, Legendary Collection reprint, and Chinese World
-- Collection printing.
--
-- source artbox-pin: cluster-name-version-sets.py --all must not split this
-- reviewed illustration group when frame/layout differences reduce pixel
-- similarity.

begin;
set local statement_timeout = 0;

insert into public.pokoin_version_sets (version, gameplay_name, member_count, source)
values ('v243052', 'Pikachu', 5, 'artbox-pin')
on conflict (version) do update
  set gameplay_name = excluded.gameplay_name,
      member_count = excluded.member_count,
      source = excluded.source,
      updated_at = now();

update public.marketplace_search_candidates
   set version = 'v243052'
 where card_id in (
   243052, -- Jungle 60/64
   243066, -- W Promo 60/64
   243408, -- Legendary Collection 86/110
   281952, -- Japanese Pokémon Jungle No.025
   342326  -- Pikachu World Collection Chinese
 );

delete from public.pokoin_version_sets s
 where s.version in ('v243066', 'v243408', 'v281952', 'v342326')
   and not exists (
     select 1
       from public.marketplace_search_candidates c
      where c.version = s.version
   );

commit;
