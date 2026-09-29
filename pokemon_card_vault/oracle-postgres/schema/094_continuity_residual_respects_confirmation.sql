-- 094: keep seller-stack continuity residuals pending until 093 confirms them.
--
-- reconcile_cardtrader_seller_stack_continuity (088) trims a vanished listing
-- to its residual when the seller stack partly reappears under a new listing
-- id, and set the residual to 'provisional' unconditionally. Under 093 a
-- vanish is 'pending' until 3 complete absences, so on the first complete
-- run after the rule went live (2026-09-24 18:39) 77 residual rows / 241
-- units were counted after a single absence. Body = live 088 otherwise.

begin;
set local statement_timeout = 0;

CREATE OR REPLACE FUNCTION public.reconcile_cardtrader_seller_stack_continuity(p_provider text, p_from_day date, p_to_day date DEFAULT NULL::date, p_scope_blueprint_ids jsonb DEFAULT '[]'::jsonb)
 RETURNS TABLE(retracted_rows integer, reduced_rows integer, qty_retracted bigint, qty_residual bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '0'
 SET jit TO 'off'
AS $function$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_from date := p_from_day;
  v_to date := coalesce(p_to_day, p_from_day);
  v_scope jsonb := coalesce(p_scope_blueprint_ids, '[]'::jsonb);
  v_retracted integer := 0;
  v_reduced integer := 0;
  v_qty_retracted bigint := 0;
  v_qty_residual bigint := 0;
begin
  create temporary table if not exists cardtrader_continuity_plan (
    history_id uuid primary key,
    provider text not null,
    external_listing_id text not null,
    removed_day date not null,
    original_qty integer not null,
    continuity_qty integer not null,
    residual_qty integer not null
  ) on commit drop;

  delete from cardtrader_continuity_plan;

  with open_rows as (
    select
      h.id,
      h.provider,
      h.external_listing_id,
      h.removed_day,
      h.quantity,
      h.seller_account_id,
      coalesce(h.blueprint_id, h.cardtrader_blueprint_id) as bp,
      lower(btrim(coalesce(h.condition, ''))) as cond,
      lower(btrim(coalesce(h.language, ''))) as lang,
      public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '') as is_rev,
      public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false) as is_first,
      public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb)) as is_graded
    from public.cardtrader_market_listing_removed_history h
    where h.provider = v_provider
      and h.removed_day between v_from and v_to
      and h.archive_reason = 'inferred_sale'
      and h.status in ('provisional', 'pending')
      and coalesce(h.seller_account_id, '') <> ''
      and h.quantity > 0
      and (
        jsonb_array_length(v_scope) = 0
        or coalesce(h.blueprint_id, h.cardtrader_blueprint_id)
             in (select jsonb_array_elements_text(v_scope)::bigint)
      )
  ),
  -- Live successor capacity per stack.  Archived rows are deleted from the
  -- snapshot table, so the live pool can never contain a predecessor.
  successor as (
    select
      o.seller_account_id, o.bp, o.cond, o.lang, o.is_rev, o.is_first, o.is_graded,
      sum(s.quantity)::bigint as succ_qty
    from (select distinct seller_account_id, bp, cond, lang, is_rev, is_first, is_graded from open_rows) o
    join public.cardtrader_market_listing_snapshots s
      on s.provider = v_provider
     and coalesce(s.blueprint_id, s.cardtrader_blueprint_id) = o.bp
     -- 091: pin the snapshot probe to open_rows' blueprints so the planner
     -- uses the coalesce(blueprint) index instead of hashing all ~2.9M rows.
     and coalesce(s.blueprint_id, s.cardtrader_blueprint_id) in (select o2.bp from open_rows o2)
     and s.seller_account_id = o.seller_account_id
     and lower(btrim(coalesce(s.condition, ''))) = o.cond
     and lower(btrim(coalesce(s.language, ''))) = o.lang
     and public.cardtrader_listing_is_reverse(coalesce(s.properties, '{}'::jsonb), false, '') = o.is_rev
     and public.cardtrader_listing_is_first_edition(coalesce(s.properties, '{}'::jsonb), false) = o.is_first
     and public.cardtrader_listing_is_graded(coalesce(s.raw_metadata, '{}'::jsonb), coalesce(s.properties, '{}'::jsonb)) = o.is_graded
    group by 1,2,3,4,5,6,7
  ),
  -- Continuity credited by earlier passes permanently consumes successor
  -- capacity.  Without this the reconciliation is not idempotent: a residual
  -- left provisional by one pass would be re-credited against the same
  -- successor units by the next, erasing a genuine partial sale.
  credited as (
    select
      h.seller_account_id,
      coalesce(h.blueprint_id, h.cardtrader_blueprint_id) as bp,
      lower(btrim(coalesce(h.condition, ''))) as cond,
      lower(btrim(coalesce(h.language, ''))) as lang,
      public.cardtrader_listing_is_reverse(coalesce(h.properties, '{}'::jsonb), false, '') as is_rev,
      public.cardtrader_listing_is_first_edition(coalesce(h.properties, '{}'::jsonb), false) as is_first,
      public.cardtrader_listing_is_graded(coalesce(h.raw_metadata, '{}'::jsonb), coalesce(h.properties, '{}'::jsonb)) as is_graded,
      sum(coalesce((h.archive_metadata->>'continuityQuantity')::bigint, 0)) as credited_qty
    from public.cardtrader_market_listing_removed_history h
    where h.provider = v_provider
      and h.archive_metadata ? 'continuityQuantity'
      -- 091: only stacks this call can credit (credited is left-joined to
      -- open_rows). Unscoped, this re-aggregated the whole history on every
      -- per-expansion persist (~8.7 s x ~834 expansions).
      and coalesce(h.blueprint_id, h.cardtrader_blueprint_id) in (select o.bp from open_rows o)
      and h.seller_account_id in (select o.seller_account_id from open_rows o)
    group by 1,2,3,4,5,6,7
  ),
  allocated as (
    select
      o.*,
      greatest(coalesce(sc.succ_qty, 0) - coalesce(cr.credited_qty, 0), 0) as succ_qty,
      coalesce(sum(o.quantity) over (
        partition by o.seller_account_id, o.bp, o.cond, o.lang, o.is_rev, o.is_first, o.is_graded
        order by o.quantity desc, o.id
        rows between unbounded preceding and 1 preceding
      ), 0)::bigint as consumed_before
    from open_rows o
    left join successor sc
      on sc.seller_account_id = o.seller_account_id
     and sc.bp = o.bp and sc.cond = o.cond and sc.lang = o.lang
     and sc.is_rev = o.is_rev and sc.is_first = o.is_first and sc.is_graded = o.is_graded
    left join credited cr
      on cr.seller_account_id = o.seller_account_id
     and cr.bp = o.bp and cr.cond = o.cond and cr.lang = o.lang
     and cr.is_rev = o.is_rev and cr.is_first = o.is_first and cr.is_graded = o.is_graded
  )
  insert into cardtrader_continuity_plan
    (history_id, provider, external_listing_id, removed_day, original_qty, continuity_qty, residual_qty)
  select
    a.id, a.provider, a.external_listing_id, a.removed_day, a.quantity,
    greatest(least(a.quantity::bigint, a.succ_qty - a.consumed_before), 0)::integer,
    (a.quantity - greatest(least(a.quantity::bigint, a.succ_qty - a.consumed_before), 0))::integer
  from allocated a
  where greatest(least(a.quantity::bigint, a.succ_qty - a.consumed_before), 0) > 0;

  -- Full continuity: the stack came back whole.  Not a sale at all.
  update public.cardtrader_market_listing_removed_history h
  set status = 'retracted',
      resolved_at = now(),
      archive_reason = 'listing_id_rotated',
      archive_metadata = coalesce(h.archive_metadata, '{}'::jsonb) || jsonb_build_object(
        'reclassifiedFrom', 'inferred_sale',
        'reclassifiedBecause', 'seller_stack_reappeared_under_new_listing_id',
        'continuityQuantity', p.continuity_qty,
        'residualQuantity', 0
      )
  from cardtrader_continuity_plan p
  where h.id = p.history_id
    and p.residual_qty = 0
    and h.status in ('provisional', 'pending');
  get diagnostics v_retracted = row_count;

  delete from public.marketplace_price_observations o
  using cardtrader_continuity_plan p
  where p.residual_qty = 0
    and o.source = 'cardtrader_removed_sale'
    and split_part(o.source_item_id, ':', 1) = p.provider
    and split_part(o.source_item_id, ':', 2) = p.external_listing_id
    and split_part(o.source_item_id, ':', 3) = p.removed_day::text;

  -- Partial continuity: only the residual may ever become a sale, and it stays
  -- provisional so the normal confirmation rules still decide its fate.
  update public.cardtrader_market_listing_removed_history h
  set quantity = p.residual_qty,
      -- 094: a residual still awaiting 3-complete-dump confirmation (093)
      -- stays pending; only unconfirmed-model rows keep the old promotion.
      status = case
        when h.status = 'pending' and coalesce(h.archive_metadata, '{}'::jsonb) ? 'confirmationRequired'
          then 'pending'
        else 'provisional'
      end,
      archive_metadata = coalesce(h.archive_metadata, '{}'::jsonb) || jsonb_build_object(
        'continuityQuantity', p.continuity_qty,
        'residualQuantity', p.residual_qty,
        'originalQuantity', p.original_qty,
        'reducedBecause', 'seller_stack_partially_reappeared_under_new_listing_id'
      )
  from cardtrader_continuity_plan p
  where h.id = p.history_id
    and p.residual_qty > 0
    and h.status in ('provisional', 'pending');
  get diagnostics v_reduced = row_count;

  update public.marketplace_price_observations o
  set quantity = p.residual_qty
  from cardtrader_continuity_plan p
  where p.residual_qty > 0
    and o.source = 'cardtrader_removed_sale'
    and split_part(o.source_item_id, ':', 1) = p.provider
    and split_part(o.source_item_id, ':', 2) = p.external_listing_id
    and split_part(o.source_item_id, ':', 3) = p.removed_day::text;

  select coalesce(sum(p.continuity_qty), 0), coalesce(sum(p.residual_qty), 0)
  into v_qty_retracted, v_qty_residual
  from cardtrader_continuity_plan p;

  return query select v_retracted, v_reduced, v_qty_retracted, v_qty_residual;
end;
$function$;

commit;
