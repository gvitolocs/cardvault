-- Image keys are leftover ct_id (public / 2). Catalog rows still had public-id
-- prefixes, leftover/4, and leftover/8 from repeated halving. Those collide
-- with older CardTrader leftovers (Juniper 684712 leftover 342356 is Pikachu
-- V-UNION's public id; DB stored 171178 = Pikachu leftover).
--
-- Homepage slug follows the leftover JPEG, not a leftover/4 dump of another card.

begin;
set local statement_timeout = 0;

update public.marketplace_search_candidates
   set cdn_image_url = regexp_replace(cdn_image_url, '(^|/)(previews/)?(\d+)_', '\1\2' || ct_id::text || '_'),
       image_url = regexp_replace(image_url, '(^|/)(previews/)?(\d+)_', '\1\2' || ct_id::text || '_'),
       preview_image_url = regexp_replace(preview_image_url, '(^|/)(previews/)?(\d+)_', '\1\2' || ct_id::text || '_'),
       homepage_image_url = regexp_replace(homepage_image_url, '(^|/)(previews/)?(\d+)_', '\1\2' || ct_id::text || '_')
 where item_kind = 'single'
   and product_type = 'card'
   and ct_id is not null
   and coalesce(cdn_image_url, image_url, preview_image_url, homepage_image_url, '')
       !~* '(one-piece|riftbound|competitive)/';

update public.marketplace_search_candidates
   set homepage_image_url = regexp_replace(
         regexp_replace(coalesce(cdn_image_url, image_url), '[?#].*$', ''),
         '\.(jpe?g|png|webp)$',
         '_homepage.webp',
         'i'
       )
 where item_kind = 'single'
   and product_type = 'card'
   and coalesce(cdn_image_url, image_url) ~* '/\d+_.+\.(jpe?g|png|webp)(\?|$)'
   and coalesce(cdn_image_url, image_url) !~* '(one-piece|riftbound|competitive)/';

commit;
