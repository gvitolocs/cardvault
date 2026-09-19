-- PPP Promos (`ppp-promo`, cards numbered PPP-P 001–007) are Japanese
-- promotional prints. CardTrader exposes no pokemon_language property for
-- these seven blueprints, so the nationality vote incorrectly falls through
-- to western. Pin the official source so later refreshes retain Japanese.

begin;
set local statement_timeout = 0;

update public.pokoin_pokemon_expansions
set nationality = 'japanese',
    milo_gallery = public.pokoin_expansion_milo_gallery('japanese', kind),
    official_source = 'tcgdex-ja',
    updated_at = now()
where lower(code) = 'ppp-promo'
   or lower(name) = 'ppp promos';

select public.pokoin_refresh_expansion_nationality() as expansions_updated;

commit;

select code, name, nationality, milo_gallery, official_source, kind, listed
from public.pokoin_pokemon_expansions
where lower(code) = 'ppp-promo'
   or lower(name) = 'ppp promos';
