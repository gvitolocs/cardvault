-- Cleanup legacy Supabase marketplace/catalog data after migration to Oracle.
--
-- IMPORTANT:
-- - Review before running.
-- - This is destructive.
-- - Keep forum tables. Runtime forum APIs still use Supabase.
-- - Marketplace/catalog/search APIs now use Oracle via MARKETPLACE_DATABASE_URL.
--
-- Expected space reclaimed from current audit: about 558 MB.

begin;

-- Forum card links should keep the external blueprint id, but must not require
-- the old Supabase marketplace_cards table to exist.
alter table if exists public.forum_topic_cards
  drop constraint if exists forum_topic_cards_card_id_fkey;

-- Drop legacy marketplace/search functions that depend on the old tables.
drop function if exists public.get_adjacent_marketplace_card_versions(bigint);
drop function if exists public.get_marketplace_home_snapshot(integer);
drop function if exists public.refresh_marketplace_cards_from_blueprints();
drop function if exists public.refresh_marketplace_card_versions();
drop function if exists public.refresh_marketplace_search_candidates();
drop function if exists public.refresh_marketplace_token_search_index();
drop function if exists public.search_cardtrader_pokemon_blueprints(text, integer);
drop function if exists public.search_marketplace_candidates(text, integer);
drop function if exists public.search_marketplace_candidates(text, integer, integer);
drop function if exists public.search_marketplace_blueprint_candidates_v2(text, integer, integer, text);
drop function if exists public.classify_marketplace_item_kind(text, text, text, text, text, text);
drop function if exists public.classify_marketplace_item_kind(text, text, text, text, text);
drop function if exists public.classify_marketplace_product_type(text, text, text, text, text, text);
drop function if exists public.extract_marketplace_trainer_name(text);
drop function if exists public.marketplace_expansion_number_int(text);
drop function if exists public.marketplace_search_compact(text);
drop function if exists public.marketplace_search_normalize(text);
drop function if exists public.marketplace_search_tokenize(text);
drop function if exists public.touch_cardtrader_pokemon_expansions_updated_at() cascade;

-- Drop old catalog/projection/search tables. Forum tables are intentionally kept.
drop table if exists public.marketplace_card_events cascade;
drop table if exists public.marketplace_search_candidates cascade;
drop table if exists public.marketplace_card_versions cascade;
drop table if exists public.marketplace_cards cascade;
drop table if exists public.marketplace_card_names cascade;
drop table if exists public.marketplace_expansion_numbers cascade;
drop table if exists public.marketplace_rarities cascade;
drop table if exists public.marketplace_trainers cascade;
drop table if exists public.cardtrader_pokemon_blueprints cascade;
drop table if exists public.cardtrader_pokemon_expansions cascade;

commit;
