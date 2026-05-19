drop function if exists public.search_marketplace_candidates(text, integer, integer, text);
drop function if exists public.search_marketplace_blueprint_candidates_v2(text, integer, integer, text);

create or replace function public.search_marketplace_blueprint_candidates_v2(
  search_term text,
  result_limit integer default 20,
  result_offset integer default 0,
  search_language text default 'en'
)
returns table (
  card_id bigint,
  name text,
  set_name text,
  card_number text,
  product_variant text,
  rarity text,
  card_type text,
  item_kind text,
  product_type text,
  trainer_name text,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  card_palette jsonb,
  emoji text,
  imported_at timestamptz,
  search_rank real
)
language sql
stable
security definer
set search_path = public
set jit = off
as $$
  with normalized as (
    select
      public.marketplace_search_normalize(search_term) as q,
      public.marketplace_search_compact(search_term) as compact_q,
      least(greatest(result_limit, 1), 15874) as clean_limit,
      least(greatest(result_offset, 0), 15874) as clean_offset,
      lower(coalesce(nullif(search_language, ''), 'en')) as language
  ),
  query_tokens as (
    select distinct token
    from normalized n
    cross join lateral unnest(public.marketplace_search_tokenize(n.q)) token
    where token <> ''
  ),
  query_intent as (
    select
      exists (select 1 from query_tokens where token ~ '^[0-9]+$') as has_number_token,
      exists (
        select 1
        from query_tokens qt
        join public.marketplace_variations v
          on qt.token = any(v.normalized_aliases)
          or public.marketplace_search_compact(qt.token) = any(v.compact_aliases)
      ) as has_variation_token,
      exists (
        select 1
        from query_tokens qt
        join public.marketplace_expansion_aliases ea
          on ea.normalized_alias = qt.token
          or ea.compact_alias = public.marketplace_search_compact(qt.token)
      ) as has_expansion_alias_token,
      exists (
        select 1
        from query_tokens qt
        where not qt.token ~ '^[0-9]+$'
          and not exists (
            select 1
            from public.marketplace_variations v
            where qt.token = any(v.normalized_aliases)
              or public.marketplace_search_compact(qt.token) = any(v.compact_aliases)
          )
          and not exists (
            select 1
            from public.marketplace_expansion_aliases ea
            where ea.normalized_alias = qt.token
              or ea.compact_alias = public.marketplace_search_compact(qt.token)
          )
      ) as has_text_token
  ),
  name_hits as (
    select
      qt.token as query_token,
      'name'::text as token_kind,
      n.name as entity_key,
      (
        case
          when n.normalized_name = qt.token then 1300
          when n.compact_name = public.marketplace_search_compact(qt.token) then 1220
          when length(qt.token) >= 2 and n.normalized_name like qt.token || '%' then 1040
          when length(qt.token) >= 2 and n.compact_name like public.marketplace_search_compact(qt.token) || '%' then 980
          when length(qt.token) between 4 and 8
            and abs(length(n.compact_name) - length(public.marketplace_search_compact(qt.token))) <= 1
            and public.marketplace_edit_distance(n.compact_name, public.marketplace_search_compact(qt.token)) = 1 then 920
          when length(qt.token) between 5 and 8
            and abs(length(n.compact_name) - length(public.marketplace_search_compact(qt.token))) <= 2
            and left(n.compact_name, 2) = left(public.marketplace_search_compact(qt.token), 2)
            and public.marketplace_edit_distance(n.compact_name, public.marketplace_search_compact(qt.token)) <= 3 then 760
          when n.normalized_name % qt.token then 780 + similarity(n.normalized_name, qt.token) * 220
          when length(qt.token) >= 4 and word_similarity(n.normalized_name, qt.token) >= 0.38 then 700 + word_similarity(n.normalized_name, qt.token) * 200
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_card_names n
      on n.normalized_name = qt.token
      or n.compact_name = public.marketplace_search_compact(qt.token)
      or (length(qt.token) >= 2 and n.normalized_name like qt.token || '%')
      or (length(qt.token) >= 2 and n.compact_name like public.marketplace_search_compact(qt.token) || '%')
      or (
        length(qt.token) between 4 and 8
        and abs(length(n.compact_name) - length(public.marketplace_search_compact(qt.token))) <= 1
        and public.marketplace_edit_distance(n.compact_name, public.marketplace_search_compact(qt.token)) <= 1
      )
      or (
        length(qt.token) between 5 and 8
        and abs(length(n.compact_name) - length(public.marketplace_search_compact(qt.token))) <= 2
        and left(n.compact_name, 2) = left(public.marketplace_search_compact(qt.token), 2)
        and public.marketplace_edit_distance(n.compact_name, public.marketplace_search_compact(qt.token)) <= 3
      )
      or (length(qt.token) >= 4 and n.normalized_name % qt.token)
      or (length(qt.token) >= 4 and word_similarity(n.normalized_name, qt.token) >= 0.38)
  ),
  name_word_hits as (
    select
      c.card_id,
      qt.token as query_token,
      'name'::text as token_kind,
      (
        case
          when name_word.word = qt.token then 1180
          when name_word.word like qt.token || '%' then 940
          when length(qt.token) between 4 and 12
            and abs(length(name_word.word) - length(public.marketplace_search_compact(qt.token))) <= 1
            and left(name_word.word, 2) = left(public.marketplace_search_compact(qt.token), 2)
            and public.marketplace_edit_distance(name_word.word, public.marketplace_search_compact(qt.token)) <= 2 then 780
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_search_candidates c
      on length(qt.token) >= 4
    cross join lateral (
      select distinct public.marketplace_search_compact(word_value) as word
      from regexp_split_to_table(public.marketplace_search_normalize(c.name), ' ') word_value
      where word_value <> ''
    ) name_word
    where length(qt.token) >= 4
      and (
        name_word.word = qt.token
        or name_word.word like qt.token || '%'
        or (
        length(qt.token) between 4 and 12
        and abs(length(name_word.word) - length(public.marketplace_search_compact(qt.token))) <= 1
        and left(name_word.word, 2) = left(public.marketplace_search_compact(qt.token), 2)
        and public.marketplace_edit_distance(name_word.word, public.marketplace_search_compact(qt.token)) <= 2
      )
    )
  ),
  translated_name_hits as (
    select
      qt.token as query_token,
      'name'::text as token_kind,
      t.name as entity_key,
      (
        case
          when t.normalized_localized_name = qt.token then 1320
          when t.compact_localized_name = public.marketplace_search_compact(qt.token) then 1240
          when length(qt.token) >= 2 and t.normalized_localized_name like qt.token || '%' then 1050
          when length(qt.token) >= 2 and t.compact_localized_name like public.marketplace_search_compact(qt.token) || '%' then 990
          when t.normalized_localized_name % qt.token then 800 + similarity(t.normalized_localized_name, qt.token) * 220
          when length(qt.token) >= 4 and word_similarity(t.normalized_localized_name, qt.token) >= 0.38 then 720 + word_similarity(t.normalized_localized_name, qt.token) * 200
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    cross join normalized norm
    join public.marketplace_card_name_translations t
      on t.language = norm.language
      and norm.language <> 'en'
      and (
        t.normalized_localized_name = qt.token
        or t.compact_localized_name = public.marketplace_search_compact(qt.token)
        or (length(qt.token) >= 2 and t.normalized_localized_name like qt.token || '%')
        or (length(qt.token) >= 2 and t.compact_localized_name like public.marketplace_search_compact(qt.token) || '%')
        or (length(qt.token) >= 4 and t.normalized_localized_name % qt.token)
        or (length(qt.token) >= 4 and word_similarity(t.normalized_localized_name, qt.token) >= 0.38)
      )
  ),
  rarity_hits as (
    select
      qt.token as query_token,
      'rarity'::text as token_kind,
      r.rarity as entity_key,
      (
        case
          when r.normalized_rarity = qt.token then 980
          when r.compact_rarity = public.marketplace_search_compact(qt.token) then 940
          when r.normalized_rarity like qt.token || '%' then 720
          when length(qt.token) >= 4 and r.normalized_rarity % qt.token then 560 + similarity(r.normalized_rarity, qt.token) * 160
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_rarities r
      on r.normalized_rarity = qt.token
      or r.compact_rarity = public.marketplace_search_compact(qt.token)
      or r.normalized_rarity like qt.token || '%'
      or (length(qt.token) >= 4 and r.normalized_rarity % qt.token)
  ),
  rarity_alias_hits as (
    select
      qt.token as query_token,
      'rarity'::text as token_kind,
      c.card_id as entity_key,
      (
        case
          when qt.token = 'sir'
            and public.marketplace_search_normalize(c.card_number) like '%special illustration rare%' then 900
          when qt.token = 'ir'
            and public.marketplace_search_normalize(c.card_number) like '%illustration rare%' then 820
          when qt.token in ('ur', 'ultra')
            and public.marketplace_search_normalize(c.card_number) like '%ultra rare%' then 800
          when qt.token in ('sr', 'secret')
            and public.marketplace_search_normalize(c.card_number) like '%secret rare%' then 780
          when qt.token in ('rare', 'holo', 'shiny')
            and public.marketplace_search_normalize(c.card_number) like '%' || qt.token || '%' then 520
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_search_candidates c
      on (
        qt.token = 'sir'
        and public.marketplace_search_normalize(c.card_number) like '%special illustration rare%'
      )
      or (
        qt.token = 'ir'
        and public.marketplace_search_normalize(c.card_number) like '%illustration rare%'
      )
      or (
        qt.token in ('ur', 'ultra')
        and public.marketplace_search_normalize(c.card_number) like '%ultra rare%'
      )
      or (
        qt.token in ('sr', 'secret')
        and public.marketplace_search_normalize(c.card_number) like '%secret rare%'
      )
      or (
        qt.token in ('rare', 'holo', 'shiny')
        and public.marketplace_search_normalize(c.card_number) like '%' || qt.token || '%'
      )
  ),
  number_hits as (
    select
      qt.token as query_token,
      'number'::text as token_kind,
      num.card_number as entity_key,
      (
        case
          when num.normalized_number = qt.token then 1120
          when num.compact_number = public.marketplace_search_compact(qt.token) then 1120
          when qt.token = any(num.number_tokens) then 1080
          when num.normalized_number ~ ('(^|[^0-9])' || regexp_replace(qt.token, '([\\^$.|?*+()\\[\\]{}])', '\\\1', 'g') || '([^0-9]|$)') then 1060
          when num.normalized_number like qt.token || '%' then 860
          when num.compact_number like public.marketplace_search_compact(qt.token) || '%' then 820
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_expansion_numbers num
      on num.normalized_number = qt.token
      or num.compact_number = public.marketplace_search_compact(qt.token)
      or qt.token = any(num.number_tokens)
      or (
        qt.token ~ '^[0-9]+$'
        and num.normalized_number ~ ('(^|[^0-9])' || regexp_replace(qt.token, '([\\^$.|?*+()\\[\\]{}])', '\\\1', 'g') || '([^0-9]|$)')
      )
      or num.normalized_number like qt.token || '%'
      or num.compact_number like public.marketplace_search_compact(qt.token) || '%'
  ),
  variant_hits as (
    select
      qt.token as query_token,
      'variant'::text as token_kind,
      c.card_id as entity_key,
      (
        case
          when public.marketplace_search_normalize(c.product_variant) = qt.token then 860
          when public.marketplace_search_compact(c.product_variant) = public.marketplace_search_compact(qt.token) then 840
          when public.marketplace_search_normalize(c.product_variant) like qt.token || '%' then 700
          when public.marketplace_search_compact(c.product_variant) like public.marketplace_search_compact(qt.token) || '%' then 680
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_search_candidates c
      on c.product_variant <> ''
      and (
        public.marketplace_search_normalize(c.product_variant) = qt.token
        or public.marketplace_search_compact(c.product_variant) = public.marketplace_search_compact(qt.token)
        or public.marketplace_search_normalize(c.product_variant) like qt.token || '%'
        or public.marketplace_search_compact(c.product_variant) like public.marketplace_search_compact(qt.token) || '%'
      )
  ),
  variation_hits as (
    select
      qt.token as query_token,
      'variation'::text as token_kind,
      v.variation_key as entity_key,
      (
        case
          when qt.token = any(v.normalized_aliases) then 1180
          when public.marketplace_search_compact(qt.token) = any(v.compact_aliases) then 1160
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_variations v
      on qt.token = any(v.normalized_aliases)
      or public.marketplace_search_compact(qt.token) = any(v.compact_aliases)
  ),
  phrase_variation_hits as (
    select
      v.variation_key as query_token,
      'variation'::text as token_kind,
      v.variation_key as entity_key,
      1320::numeric as token_score
    from normalized n
    join public.marketplace_variations v
      on exists (
        select 1
        from unnest(v.normalized_aliases, v.compact_aliases) as alias_pair(normalized_alias, compact_alias)
        where (
          (
            alias_pair.normalized_alias <> ''
            and n.q ~ ('(^|[^a-z0-9])' || regexp_replace(alias_pair.normalized_alias, '([\\^$.|?*+()\\[\\]{}])', '\\\1', 'g') || '([^a-z0-9]|$)')
          )
          or (
            length(alias_pair.compact_alias) >= 2
            and n.compact_q like '%' || alias_pair.compact_alias || '%'
          )
        )
      )
  ),
  expansion_hits as (
    select
      qt.token as query_token,
      'expansion'::text as token_kind,
      e.normalized_name as entity_key,
      (
        case
          when e.normalized_name = qt.token then 1050
          when e.compact_name = public.marketplace_search_compact(qt.token) then 1030
          when length(qt.token) >= 2 and e.normalized_name like qt.token || '%' then 820
          when length(qt.token) >= 2 and e.compact_name like public.marketplace_search_compact(qt.token) || '%' then 780
          when length(qt.token) >= 4 and e.normalized_name % qt.token then 620 + similarity(e.normalized_name, qt.token) * 180
          else 0
        end
      )::numeric as token_score
    from query_tokens qt
    join public.cardtrader_pokemon_expansions e
      on e.normalized_name = qt.token
      or e.compact_name = public.marketplace_search_compact(qt.token)
      or (length(qt.token) >= 2 and e.normalized_name like qt.token || '%')
      or (length(qt.token) >= 2 and e.compact_name like public.marketplace_search_compact(qt.token) || '%')
      or (length(qt.token) >= 4 and e.normalized_name % qt.token)
  ),
  expansion_alias_hits as (
    select
      qt.token as query_token,
      'expansion'::text as token_kind,
      ea.normalized_expansion_name as entity_key,
      (
        case
          when ea.normalized_alias = qt.token then 1180
          when ea.compact_alias = public.marketplace_search_compact(qt.token) then 1160
          else 0
        end
        + greatest(0, 220 - ea.priority)
      )::numeric as token_score
    from query_tokens qt
    join public.marketplace_expansion_aliases ea
      on ea.normalized_alias = qt.token
      or ea.compact_alias = public.marketplace_search_compact(qt.token)
  ),
  token_blueprints as (
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 640 + c.search_weight as score
    from name_hits h
    join public.marketplace_search_candidates c on c.name = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, c.name as entity_key, h.token_score + 620 + c.search_weight as score
    from name_word_hits h
    join public.marketplace_search_candidates c on c.card_id = h.card_id
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 700 + c.search_weight as score
    from translated_name_hits h
    join public.marketplace_search_candidates c on c.name = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 320 + c.search_weight as score
    from rarity_hits h
    join public.marketplace_search_candidates c on c.rarity = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key::text, h.token_score + 300 + c.search_weight as score
    from rarity_alias_hits h
    join public.marketplace_search_candidates c on c.card_id = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 560 + c.search_weight as score
    from number_hits h
    join public.marketplace_search_candidates c on c.card_number = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key::text, h.token_score + 360 + c.search_weight as score
    from variant_hits h
    join public.marketplace_search_candidates c on c.card_id = h.entity_key
    union all
    select cv.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 1320 + c.search_weight as score
    from variation_hits h
    join public.marketplace_card_variations cv on cv.variation_key = h.entity_key
    join public.marketplace_search_candidates c on c.card_id = cv.card_id
    union all
    select cv.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 1120 + c.search_weight as score
    from phrase_variation_hits h
    join public.marketplace_card_variations cv on cv.variation_key = h.entity_key
    join public.marketplace_search_candidates c on c.card_id = cv.card_id
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 440 + c.search_weight as score
    from expansion_hits h
    join public.marketplace_search_candidates c on c.expansion_name = h.entity_key
    union all
    select c.card_id, h.query_token, h.token_kind, h.entity_key, h.token_score + 980 + c.search_weight as score
    from expansion_alias_hits h
    join public.marketplace_search_candidates c
      on public.marketplace_search_normalize(c.expansion_name) = h.entity_key
  ),
  per_card_token as (
    select
      card_id,
      query_token,
      max(score) as token_score,
      bool_or(
        token_kind = 'name'
        and query_token !~ '^[0-9]+$'
        and not exists (
          select 1
          from public.marketplace_variations v
          where query_token = any(v.normalized_aliases)
            or public.marketplace_search_compact(query_token) = any(v.compact_aliases)
        )
        and not exists (
          select 1
          from public.marketplace_expansion_aliases ea
          where ea.normalized_alias = query_token
            or ea.compact_alias = public.marketplace_search_compact(query_token)
        )
      ) as matched_name,
      bool_or(token_kind = 'number') as matched_number,
      bool_or(token_kind = 'variation') as matched_variation,
      bool_or(token_kind = 'expansion') as matched_expansion,
      bool_or(token_kind = 'rarity') as matched_rarity
    from token_blueprints
    group by card_id, query_token
  ),
  scored_cards as (
    select
      c.*,
      coalesce(sum(p.token_score), 0)
        + count(distinct p.query_token) * 420
        + case when count(distinct p.query_token) = (select count(*) from query_tokens) then 900 else 0 end
        + case
            when (select has_text_token and has_number_token from query_intent)
              and bool_or(p.matched_name)
              and bool_or(p.matched_number) then 5200
            when bool_or(p.matched_name) and bool_or(p.matched_number) then 900
            else 0
          end
        + case
            when (select has_text_token and has_variation_token from query_intent)
              and bool_or(p.matched_name)
              and bool_or(p.matched_variation) then 4400
            when bool_or(p.matched_name) and bool_or(p.matched_variation) then 1200
            else 0
          end
        + case
            when (select has_text_token and has_expansion_alias_token from query_intent)
              and bool_or(p.matched_name)
              and bool_or(p.matched_expansion) then 4600
            when bool_or(p.matched_name) and bool_or(p.matched_expansion) then 700
            else 0
          end
        + case
            when bool_or(p.matched_name) and bool_or(p.matched_rarity) then 420
            else 0
          end
        - case
            when (select has_text_token and has_number_token from query_intent)
              and bool_or(p.matched_name)
              and not bool_or(p.matched_number) then 2400
            else 0
          end
        - case
            when (select has_text_token and has_variation_token from query_intent)
              and bool_or(p.matched_name)
              and not bool_or(p.matched_variation) then 1800
            else 0
          end
        - case
            when (select has_text_token and has_expansion_alias_token from query_intent)
              and bool_or(p.matched_name)
              and not bool_or(p.matched_expansion) then 2200
            else 0
          end
        - case
            when (select has_text_token and has_expansion_alias_token from query_intent)
              and bool_or(p.matched_expansion)
              and not bool_or(p.matched_name) then 5000
            else 0
          end
        + case when c.item_kind = 'product' then -80 else 0 end as rank_score,
      count(distinct p.query_token) as matched_tokens
    from public.marketplace_search_candidates c
    join per_card_token p on p.card_id = c.card_id
    group by
      c.card_id,
      c.name,
      c.set_name,
      c.card_number,
      c.product_variant,
      c.rarity,
      c.card_type,
      c.item_kind,
      c.product_type,
      c.trainer_name,
      c.image_url,
      c.cdn_image_url,
      c.preview_image_url,
      c.card_palette,
      c.emoji,
      c.search_text,
      c.name_prefix,
      c.set_prefix,
      c.expansion_name,
      c.search_weight,
      c.imported_at,
      c.projected_at
  )
  select
    c.card_id,
    c.name,
    c.set_name,
    c.card_number,
    c.product_variant,
    c.rarity,
    c.card_type,
    c.item_kind,
    c.product_type,
    c.trainer_name,
    c.image_url,
    c.cdn_image_url,
    c.preview_image_url,
    c.card_palette,
    c.emoji,
    c.imported_at,
    c.rank_score::real as search_rank
  from scored_cards c
  order by c.rank_score desc, c.matched_tokens desc, c.name asc, c.card_number asc
  limit (select clean_limit from normalized)
  offset (select clean_offset from normalized);
$$;

create or replace function public.search_marketplace_candidates(
  search_term text,
  result_limit integer default 20,
  result_offset integer default 0,
  search_language text default 'en'
)
returns table (
  card_id bigint,
  name text,
  set_name text,
  card_number text,
  product_variant text,
  rarity text,
  card_type text,
  item_kind text,
  product_type text,
  trainer_name text,
  image_url text,
  cdn_image_url text,
  preview_image_url text,
  card_palette jsonb,
  emoji text,
  imported_at timestamptz,
  search_rank real
)
language sql
stable
security definer
set search_path = public
set jit = off
as $$
  select *
  from public.search_marketplace_blueprint_candidates_v2(search_term, result_limit, result_offset, search_language);
$$;

