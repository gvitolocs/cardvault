-- CardTrader's DP3 Dialga/Palkia constructed decks contain Japanese-only
-- card scans, but expose no pokemon_language property. The nationality vote
-- therefore falls through to western and the versions page shows EN badges.
-- Pin the two companion decks to the Japanese official-source bucket so a
-- later pokoin_refresh_expansion_nationality() keeps the correction.

begin;
set local statement_timeout = 0;

update public.pokoin_pokemon_expansions
set nationality = 'japanese',
    milo_gallery = public.pokoin_expansion_milo_gallery('japanese', kind),
    official_source = 'tcgdex-ja',
    updated_at = now()
where lower(code) in ('dp3-dial', 'dp3-pal');

select public.pokoin_refresh_expansion_nationality() as expansions_updated;

commit;

select code, name, nationality, milo_gallery, official_source, kind, listed
from public.pokoin_pokemon_expansions
where lower(code) in ('dp3-dial', 'dp3-pal')
order by code;
