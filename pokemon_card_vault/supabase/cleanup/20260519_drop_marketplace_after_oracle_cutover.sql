-- Destructive cleanup after Oracle marketplace cutover.
-- Keep Supabase forum tables/functions/storage untouched.
-- Run only after Oracle has been loaded and Vercel production has
-- MARKETPLACE_DATABASE_URL configured.

begin;

do $$
declare
  missing_forum_objects text[];
begin
  select array_agg(object_name)
  into missing_forum_objects
  from (
    values
      ('forum_categories'),
      ('forum_topics'),
      ('forum_posts'),
      ('forum_media'),
      ('forum_topic_cards')
  ) expected(object_name)
  where to_regclass('public.' || expected.object_name) is null;

  if missing_forum_objects is not null then
    raise exception
      'Refusing cleanup because forum objects are missing: %',
      missing_forum_objects;
  end if;
end;
$$;

drop function if exists public.search_marketplace_blueprint_candidates_v2(text, integer, integer) cascade;
drop function if exists public.search_marketplace_candidates(text, integer, integer) cascade;
drop function if exists public.get_marketplace_home_snapshot(integer) cascade;
drop function if exists public.refresh_marketplace_oracle_projections() cascade;
drop function if exists public.refresh_marketplace_token_search_index() cascade;
drop function if exists public.refresh_marketplace_search_candidates() cascade;
drop function if exists public.refresh_marketplace_card_versions() cascade;
drop function if exists public.refresh_marketplace_cards_from_blueprints() cascade;
drop function if exists public.classify_marketplace_product_type(text, text, text, text, text, text, bigint) cascade;
drop function if exists public.marketplace_expansion_number_int(text) cascade;
drop function if exists public.marketplace_search_tokenize(text) cascade;
drop function if exists public.marketplace_search_compact(text) cascade;
drop function if exists public.marketplace_search_normalize(text) cascade;
drop function if exists public.search_cardtrader_pokemon_blueprints(text, integer, integer) cascade;
drop function if exists public.refresh_cardtrader_search_previews() cascade;

drop table if exists public.marketplace_card_events cascade;
drop table if exists public.marketplace_search_candidates cascade;
drop table if exists public.marketplace_card_versions cascade;
drop table if exists public.marketplace_cards cascade;
drop table if exists public.marketplace_card_names cascade;
drop table if exists public.marketplace_rarities cascade;
drop table if exists public.marketplace_expansion_numbers cascade;
drop table if exists public.marketplace_trainers cascade;
drop table if exists public.cardtrader_pokemon_expansions cascade;
drop table if exists public.cardtrader_pokemon_blueprints cascade;
drop table if exists public.cardtrader_search_previews cascade;

commit;
