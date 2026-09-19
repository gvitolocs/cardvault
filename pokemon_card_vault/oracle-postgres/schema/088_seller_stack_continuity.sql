-- Reconcile a provisional disappearance after the next valid complete-book
-- observation proves seller-stack continuity under another listing id.
-- Product ids are snapshot row keys, never stack identity.

create or replace function public.reconcile_cardtrader_seller_stack_continuity(
  p_provider text,
  p_observed_day date,
  p_scope_blueprint_ids jsonb default '[]'::jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
set statement_timeout = 0
as $$
declare
  changed_count integer := 0;
begin
  with reappeared as (
    select distinct
      history.id,
      history.provider,
      history.external_listing_id,
      history.removed_day
    from public.cardtrader_market_listing_removed_history history
    join public.cardtrader_market_listing_snapshots live
      on live.provider = history.provider
     and live.external_listing_id <> history.external_listing_id
     and live.seller_account_id <> ''
     and public.cardtrader_same_seller_listing_stack(
       history.seller_account_id,
       history.seller_account_name,
       coalesce(history.blueprint_id, history.cardtrader_blueprint_id),
       history.condition,
       history.language,
       history.properties,
       history.raw_metadata,
       live.seller_account_id,
       live.seller_account_name,
       coalesce(live.blueprint_id, live.cardtrader_blueprint_id),
       live.condition,
       live.language,
       live.properties,
       live.raw_metadata
     )
    where history.provider = coalesce(nullif(trim(p_provider), ''), 'cardtrader')
      and history.removed_day = p_observed_day - 1
      and history.archive_reason = 'inferred_sale'
      and history.status in ('confirmed', 'provisional', 'pending')
      and (
        jsonb_array_length(coalesce(p_scope_blueprint_ids, '[]'::jsonb)) = 0
        or coalesce(history.blueprint_id, history.cardtrader_blueprint_id)
             in (select jsonb_array_elements_text(p_scope_blueprint_ids)::bigint)
      )
  ),
  deleted_observations as (
    delete from public.marketplace_price_observations observation
    using reappeared
    where observation.source = 'cardtrader_removed_sale'
      and observation.source_item_id =
        reappeared.provider || ':' || reappeared.external_listing_id || ':' ||
        reappeared.removed_day::text || ':inferred_sale'
    returning observation.source_item_id
  )
  update public.cardtrader_market_listing_removed_history history
  set
    status = 'retracted',
    resolved_at = now(),
    archive_reason = 'listing_id_rotated',
    archive_metadata = coalesce(history.archive_metadata, '{}'::jsonb) || jsonb_build_object(
      'reclassifiedFrom', 'inferred_sale',
      'reclassifiedBecause', 'seller_stack_reappeared_next_valid_observation'
    )
  from reappeared
  where history.id = reappeared.id
    and history.archive_reason = 'inferred_sale';

  get diagnostics changed_count = row_count;
  return coalesce(changed_count, 0);
end;
$$;
