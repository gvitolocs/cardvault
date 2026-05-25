create or replace function public.refresh_marketplace_oracle_projections()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cards_count integer;
  versions_count integer;
  candidates_count integer;
  card_urls_count integer;
  tokens_count integer;
  ngrams_count integer;
  price_summary_count integer;
  hot_blueprints_count integer;
  artist_card_counts_count integer;
begin
  cards_count := public.refresh_marketplace_cards_from_blueprints();
  versions_count := public.refresh_marketplace_card_versions();
  candidates_count := public.refresh_marketplace_search_candidates();
  card_urls_count := public.refresh_marketplace_card_urls();
  artist_card_counts_count := public.refresh_marketplace_artist_card_counts();
  tokens_count := public.refresh_marketplace_token_search_index();
  ngrams_count := public.refresh_marketplace_name_ngrams();
  price_summary_count := public.refresh_marketplace_blueprint_price_summary();
  hot_blueprints_count := public.refresh_marketplace_hot_blueprints();

  return jsonb_build_object(
    'marketplaceCards', cards_count,
    'marketplaceCardVersions', versions_count,
    'searchCandidates', candidates_count,
    'marketplaceCardUrls', card_urls_count,
    'artistCardCounts', artist_card_counts_count,
    'tokenDimensions', tokens_count,
    'nameNgrams', ngrams_count,
    'priceSummaries', price_summary_count,
    'hotBlueprints', hot_blueprints_count,
    'refreshedAt', now()
  );
end;
$$;

