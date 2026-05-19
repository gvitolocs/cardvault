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
  tokens_count integer;
begin
  cards_count := public.refresh_marketplace_cards_from_blueprints();
  versions_count := public.refresh_marketplace_card_versions();
  candidates_count := public.refresh_marketplace_search_candidates();
  tokens_count := public.refresh_marketplace_token_search_index();

  return jsonb_build_object(
    'marketplaceCards', cards_count,
    'marketplaceCardVersions', versions_count,
    'searchCandidates', candidates_count,
    'tokenDimensions', tokens_count,
    'refreshedAt', now()
  );
end;
$$;

