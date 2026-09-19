-- marketplace_card_versions is looked up by public card_id (PK) or CardTrader ct_id.
-- `WHERE card_id = $1 OR ct_id = $1` seq-scanned 46k rows (~1s) because there was
-- no ct_id index. API now resolves card_id via marketplace_search_candidates
-- (PK + unique ct_id) then hits this PK. Keep a unique ct_id index for old URLs
-- and joins. Canonical: docs/marketplace-public-ids.md and
-- docs/marketplace-card-image-pipeline.md

create unique index if not exists marketplace_card_versions_ct_id_key
  on public.marketplace_card_versions (ct_id);
