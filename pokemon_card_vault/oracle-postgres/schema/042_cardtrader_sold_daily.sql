-- Stored daily sold medians by condition / language / reverse / first edition / graded.
-- The desk graph reads this instead of scanning marketplace_price_observations.
-- Graded seller comments are filled going forward (properties.seller_comment);
-- do not backfill comments from old CardTrader descriptions.

begin;

set local statement_timeout = 0;
set local lock_timeout = 0;
set local idle_in_transaction_session_timeout = 0;

drop table if exists public.cardtrader_sold_daily;

create table if not exists public.cardtrader_sold_daily (
  blueprint_id bigint not null,
  observed_day date not null,
  condition text not null,
  language text not null,
  reverse boolean not null default false,
  first_edition boolean not null default false,
  graded boolean not null default false,
  median_pkn numeric not null,
  min_pkn numeric not null,
  max_pkn numeric not null,
  sold_qty integer not null default 0,
  listings integer not null default 0,
  sample_count integer not null default 0,
  graded_comments text[] not null default '{}',
  refreshed_at timestamptz not null default now(),
  primary key (
    blueprint_id, observed_day, condition, language, reverse, first_edition, graded
  )
);

create index if not exists cardtrader_sold_daily_blueprint_day_idx
  on public.cardtrader_sold_daily (blueprint_id, observed_day);

create or replace function public.cardtrader_sold_condition(value text)
returns text
language sql
immutable
as $$
  select case
    when lower(btrim(coalesce(value, ''))) in ('nm', 'mint', 'near mint', 'near mint foil') then 'NM'
    when lower(btrim(coalesce(value, ''))) in ('sp', 'slightly played', 'lightly played', 'lp', 'excellent', 'ex') then 'SP'
    when lower(btrim(coalesce(value, ''))) in ('mp', 'moderately played', 'played good', 'good', 'gd') then 'MP'
    when lower(btrim(coalesce(value, ''))) in ('poor', 'po', 'damaged', 'dmg') then 'Poor'
    when lower(btrim(coalesce(value, ''))) in ('pl', 'played', 'poor played') then 'PL'
    else nullif(btrim(value), '')
  end;
$$;

create or replace function public.cardtrader_sold_language(value text)
returns text
language sql
immutable
as $$
  select case
    when lower(btrim(coalesce(value, ''))) in ('en', 'english') then 'EN'
    when lower(btrim(coalesce(value, ''))) in ('it', 'italian') then 'IT'
    when lower(btrim(coalesce(value, ''))) in ('fr', 'french') then 'FR'
    when lower(btrim(coalesce(value, ''))) in ('de', 'german') then 'DE'
    when lower(btrim(coalesce(value, ''))) in ('es', 'spanish') then 'ES'
    when lower(btrim(coalesce(value, ''))) in ('jp', 'ja', 'japanese') then 'JP'
    when lower(btrim(coalesce(value, ''))) in ('pt', 'portuguese') then 'PT'
    when lower(btrim(coalesce(value, ''))) in ('nl', 'dutch') then 'NL'
    when lower(btrim(coalesce(value, ''))) in ('pl', 'polish') then 'PL'
    when lower(btrim(coalesce(value, ''))) in ('ru', 'russian') then 'RU'
    when lower(btrim(coalesce(value, ''))) in ('ko', 'kr', 'korean') then 'KO'
    when lower(btrim(coalesce(value, ''))) in ('zh-tw', 'zht', 'zh_hant', 'zh-hant') then 'ZHT'
    when lower(btrim(coalesce(value, ''))) in ('zh', 'zh-cn', 'zh_hans', 'zh-hans', 'chinese') then 'ZH'
    when lower(btrim(coalesce(value, ''))) in ('id', 'indonesian', 'indonesia') then 'ID'
    else nullif(upper(btrim(value)), '')
  end;
$$;

create or replace function public.cardtrader_listing_is_reverse(
  properties jsonb default '{}'::jsonb,
  reverse boolean default false,
  foil_state text default ''
)
returns boolean
language sql
immutable
as $$
  select coalesce(reverse, false)
    or lower(btrim(coalesce(foil_state, ''))) = 'reverse'
    or lower(coalesce(properties->>'foil_state', properties->>'foilState', '')) = 'reverse'
    or lower(coalesce(properties->>'pokemon_reverse', '')) in ('true', '1', 'yes', 'reverse');
$$;

create or replace function public.cardtrader_listing_is_first_edition(
  properties jsonb default '{}'::jsonb,
  first_edition boolean default false
)
returns boolean
language sql
immutable
as $$
  select coalesce(first_edition, false)
    or lower(coalesce(
      properties->>'first_edition',
      properties->>'firstEdition',
      properties->>'pokemon_first_edition',
      ''
    )) in ('true', '1', 'yes');
$$;

create or replace function public.cardtrader_graded_seller_comment(
  properties jsonb default '{}'::jsonb,
  raw_metadata jsonb default '{}'::jsonb
)
returns text
language sql
immutable
as $$
  select left(btrim(coalesce(
    nullif(properties->>'seller_comment', ''),
    nullif(properties->>'sellerComment', ''),
    nullif(raw_metadata->>'seller_comment', ''),
    nullif(raw_metadata->>'sellerComment', '')
  )), 500);
$$;

create or replace function public.annotate_cardtrader_removed_sale_observations(
  target_day date default current_date - 1
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := coalesce(target_day, current_date - 1);
  updated_count integer := 0;
begin
  update public.marketplace_price_observations obs
  set
    reverse = public.cardtrader_listing_is_reverse(
      history.properties,
      obs.reverse,
      obs.foil_state
    ),
    first_edition = public.cardtrader_listing_is_first_edition(
      history.properties,
      obs.first_edition
    ),
    foil_state = case
      when public.cardtrader_listing_is_reverse(history.properties, obs.reverse, obs.foil_state)
        then 'reverse'
      else coalesce(nullif(obs.foil_state, ''), 'standard')
    end,
    metadata = case
      when obs.graded
        and public.cardtrader_graded_seller_comment(history.properties, history.raw_metadata) <> ''
      then obs.metadata || jsonb_build_object(
        'sellerComment',
        public.cardtrader_graded_seller_comment(history.properties, history.raw_metadata)
      )
      else obs.metadata
    end
  from public.cardtrader_market_listing_removed_history history
  where obs.source = 'cardtrader_removed_sale'
    and (obs.observed_at at time zone 'utc')::date = v_day
    and history.removed_day = v_day
    and history.provider || ':' || history.external_listing_id || ':' || history.removed_day::text || ':' || history.archive_reason
      = obs.source_item_id;

  get diagnostics updated_count = row_count;
  return coalesce(updated_count, 0);
end;
$$;

create or replace function public.refresh_cardtrader_sold_daily(
  target_day date default null
)
returns integer
language plpgsql
security definer
set search_path = public
set statement_timeout = 0
as $$
declare
  refreshed_count integer := 0;
begin
  perform set_config('statement_timeout', '0', true);

  if target_day is not null then
    delete from public.cardtrader_sold_daily
    where observed_day = target_day;
  else
    truncate public.cardtrader_sold_daily;
  end if;

  insert into public.cardtrader_sold_daily (
    blueprint_id,
    observed_day,
    condition,
    language,
    reverse,
    first_edition,
    graded,
    median_pkn,
    min_pkn,
    max_pkn,
    sold_qty,
    listings,
    sample_count,
    graded_comments,
    refreshed_at
  )
  select
    obs.blueprint_id,
    (obs.observed_at at time zone 'utc')::date as observed_day,
    public.cardtrader_sold_condition(obs.condition) as condition,
    public.cardtrader_sold_language(obs.language) as language,
    public.cardtrader_listing_is_reverse(
      coalesce(history.properties, '{}'::jsonb),
      obs.reverse,
      obs.foil_state
    ) as reverse,
    public.cardtrader_listing_is_first_edition(
      coalesce(history.properties, '{}'::jsonb),
      obs.first_edition
    ) as first_edition,
    obs.graded,
    percentile_cont(0.5) within group (order by obs.price_pkn) as median_pkn,
    min(obs.price_pkn) as min_pkn,
    max(obs.price_pkn) as max_pkn,
    coalesce(sum(obs.quantity), 0)::integer as sold_qty,
    count(*)::integer as listings,
    count(*)::integer as sample_count,
    case
      when obs.graded then coalesce(
        array_remove(array_agg(distinct nullif(obs.metadata->>'sellerComment', '')), null),
        '{}'::text[]
      )
      else '{}'::text[]
    end as graded_comments,
    now()
  from public.marketplace_price_observations obs
  left join public.cardtrader_market_listing_removed_history history
    on history.provider || ':' || history.external_listing_id || ':' || history.removed_day::text || ':' || history.archive_reason
      = obs.source_item_id
  where obs.source = 'cardtrader_removed_sale'
    and obs.price_pkn > 0
    and obs.blueprint_id is not null
    and (target_day is null or (obs.observed_at at time zone 'utc')::date = target_day)
    and public.cardtrader_sold_condition(obs.condition) is not null
    and public.cardtrader_sold_language(obs.language) is not null
  group by
    obs.blueprint_id,
    (obs.observed_at at time zone 'utc')::date,
    public.cardtrader_sold_condition(obs.condition),
    public.cardtrader_sold_language(obs.language),
    public.cardtrader_listing_is_reverse(
      coalesce(history.properties, '{}'::jsonb),
      obs.reverse,
      obs.foil_state
    ),
    public.cardtrader_listing_is_first_edition(
      coalesce(history.properties, '{}'::jsonb),
      obs.first_edition
    ),
    obs.graded;

  get diagnostics refreshed_count = row_count;
  return coalesce(refreshed_count, 0);
end;
$$;

create or replace function public.finalize_cardtrader_daily_market_refresh(
  p_provider text default 'cardtrader',
  p_removed_day date default current_date - 1,
  p_imported_at timestamptz default now()
)
returns table (
  cache_refreshed_count integer,
  analytics_count integer,
  price_summary_count integer
)
language plpgsql
security definer
set search_path = public
set statement_timeout = 0
as $$
declare
  v_provider text := coalesce(nullif(trim(p_provider), ''), 'cardtrader');
  v_day date := coalesce(p_removed_day, current_date - 1);
begin
  perform set_config('statement_timeout', '0', true);
  perform set_config('lock_timeout', '0', true);

  select public.refresh_cardtrader_blueprint_listing_cache(v_provider, '[]'::jsonb, p_imported_at)
  into cache_refreshed_count;

  perform public.annotate_cardtrader_removed_sale_observations(v_day);
  perform public.refresh_cardtrader_sold_daily(v_day);

  select public.refresh_cardtrader_blueprint_daily_analytics(v_day)
  into analytics_count;

  select public.refresh_marketplace_blueprint_price_summary(null)
  into price_summary_count;

  perform public.refresh_marketplace_hot_blueprints();

  return next;
end;
$$;

commit;
