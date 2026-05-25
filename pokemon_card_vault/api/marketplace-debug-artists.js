const { getMarketplacePool, marketplaceQuery } = require('./_marketplace_db');
const { authorizeSearchDebugRequest } = require('./_search_debug_auth');

const MANUAL_ARTIST_SOURCE = 'manual_debug';
const MANUAL_PRODUCT_SOURCE = 'manual_debug_product';

function cleanBlueprintId(value) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : 0;
}

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function normalizeArtistKey(value) {
  return cleanText(value, 180)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanProductType(value) {
  const productType = cleanText(value || 'sealed_product', 80)
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return productType && productType !== 'card' ? productType : 'sealed_product';
}

function missingReason(row) {
  if (!row) return 'no_candidate';
  if (!row.current_artist) return 'missing_artist';
  if (Number(row.current_confidence || 0) < 0.92) return 'low_confidence_artist';
  return 'artist_needs_review';
}

function userLabel(user) {
  return cleanText(user?.email || user?.username || user?.uid || 'debug user', 240);
}

async function ensureClassificationOverrideTable(clientOrPool = null) {
  const query = clientOrPool?.query
    ? clientOrPool.query.bind(clientOrPool)
    : marketplaceQuery;
  await query(`
    create table if not exists public.marketplace_blueprint_classification_overrides (
      blueprint_id bigint primary key references public.cardtrader_pokemon_blueprints(id) on delete cascade,
      item_kind text not null default 'single' check (item_kind in ('single', 'product')),
      product_type text not null default 'card',
      source text not null default '',
      reason text not null default '',
      debug_uid text not null default '',
      debug_email text not null default '',
      debug_username text not null default '',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `);
  await query(`
    create index if not exists marketplace_blueprint_classification_overrides_source_idx
      on public.marketplace_blueprint_classification_overrides (source, updated_at desc)
  `);
}

async function ensureArtistDebugSkipTable(clientOrPool = null) {
  const query = clientOrPool?.query
    ? clientOrPool.query.bind(clientOrPool)
    : marketplaceQuery;
  await query(`
    create table if not exists public.marketplace_artist_debug_skips (
      id bigserial primary key,
      blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
      debug_uid text not null default '',
      debug_email text not null default '',
      debug_username text not null default '',
      reason text not null default '',
      skipped_at timestamptz not null default now()
    )
  `);
  await query(`
    create index if not exists marketplace_artist_debug_skips_recent_idx
      on public.marketplace_artist_debug_skips (blueprint_id, debug_uid, debug_email, skipped_at desc)
  `);
}

async function fetchNextArtistCandidate(user = {}) {
  await ensureClassificationOverrideTable();
  await ensureArtistDebugSkipTable();
  const result = await marketplaceQuery(`
    with unresolved as (
      select
        c.card_id,
        c.name,
        coalesce(nullif(c.source_name, ''), c.name) as source_name,
        coalesce(nullif(c.display_name, ''), c.name) as display_name,
        coalesce(nullif(c.canonical_name, ''), c.name) as canonical_name,
        c.set_name,
        c.card_number,
        c.product_variant,
        c.rarity,
        c.card_type,
        coalesce(o.item_kind, c.item_kind, 'single') as item_kind,
        coalesce(o.product_type, c.product_type, 'card') as product_type,
        c.trainer_name,
        coalesce(
          nullif(c.cdn_image_url, ''),
          nullif(b.cdn_image_url, ''),
          nullif(c.image_url, ''),
          nullif(b.image_url, ''),
          nullif(c.preview_image_url, ''),
          nullif(b.preview_image_url, ''),
          nullif(c.homepage_image_url, ''),
          nullif(b.homepage_image_url, ''),
          ''
        ) as image_url,
        coalesce(
          nullif(c.preview_image_url, ''),
          nullif(b.preview_image_url, ''),
          nullif(c.homepage_image_url, ''),
          nullif(b.homepage_image_url, ''),
          nullif(c.cdn_image_url, ''),
          nullif(b.cdn_image_url, ''),
          nullif(c.image_url, ''),
          nullif(b.image_url, ''),
          ''
        ) as preview_image_url,
        artist.artist as current_artist,
        artist.normalized_artist as current_normalized_artist,
        artist.confidence as current_confidence,
        artist.source as current_artist_source,
        artist.match_reason as current_match_reason,
        b.imported_at
      from public.marketplace_search_candidates c
      join public.cardtrader_pokemon_blueprints b on b.id = c.card_id
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = c.card_id
      left join public.marketplace_blueprint_classification_overrides o
        on o.blueprint_id = c.card_id
      where coalesce(o.item_kind, c.item_kind, 'single') <> 'product'
        and coalesce(o.product_type, c.product_type, 'card') = 'card'
        and coalesce(nullif(c.canonical_name, ''), c.name, '') <> ''
        and coalesce(c.cdn_image_url, b.cdn_image_url, c.image_url, b.image_url, c.preview_image_url, b.preview_image_url) is not null
        and not exists (
          select 1
          from public.marketplace_artist_debug_skips skips
          where skips.blueprint_id = c.card_id
            and skips.skipped_at >= now() - interval '12 hours'
            and (
              nullif(skips.debug_uid, '') = nullif($1::text, '')
              or nullif(skips.debug_email, '') = nullif($2::text, '')
            )
        )
        and (
          artist.blueprint_id is null
          or coalesce(artist.artist, '') = ''
          or artist.confidence < 0.92
        )
    ),
    with_options as (
      select
        unresolved.*,
        (
          select count(distinct existing.normalized_artist)::integer
          from public.marketplace_blueprint_artists existing
          join public.marketplace_search_candidates existing_card
            on existing_card.card_id = existing.blueprint_id
          where existing.blueprint_id <> unresolved.card_id
            and existing.normalized_artist <> ''
            and coalesce(nullif(existing_card.canonical_name, ''), existing_card.name) = unresolved.canonical_name
            and coalesce(existing_card.item_kind, 'single') <> 'product'
            and coalesce(existing_card.product_type, 'card') = 'card'
        ) as artist_option_count
      from unresolved
    )
    select *
    from with_options
    where artist_option_count > 0
    order by
      case when current_artist is null or current_artist = '' then 0 else 1 end,
      artist_option_count desc,
      imported_at desc nulls last,
      random()
    limit 1
  `, [cleanText(user?.uid, 160), cleanText(user?.email, 240)]);

  const row = result.rows[0];
  if (!row) {
    return {
      candidate: null,
      reason: 'no_unresolved_artist_candidates_with_known_same_pokemon_artists',
    };
  }

  const artists = await artistOptionsForIdentity(row.canonical_name, row.card_id);
  return {
    candidate: serializeCandidate(row, artists),
    reason: '',
  };
}

async function artistOptionsForIdentity(canonicalName, currentBlueprintId) {
  const result = await marketplaceQuery(
    `
      with matches as (
        select
          artist.normalized_artist,
          artist.artist,
          artist.blueprint_id,
          cards.name,
          cards.set_name,
          cards.card_number,
          artist.confidence,
          row_number() over (
            partition by artist.normalized_artist
            order by artist.confidence desc, artist.matched_at desc nulls last, cards.card_id desc
          ) as example_rank
        from public.marketplace_blueprint_artists artist
        join public.marketplace_search_candidates cards
          on cards.card_id = artist.blueprint_id
        where artist.normalized_artist <> ''
          and artist.blueprint_id <> $2::bigint
          and coalesce(nullif(cards.canonical_name, ''), cards.name) = $1::text
          and coalesce(cards.item_kind, 'single') <> 'product'
          and coalesce(cards.product_type, 'card') = 'card'
      )
      select
        normalized_artist,
        (array_agg(artist order by confidence desc, blueprint_id desc))[1] as artist,
        count(distinct blueprint_id)::integer as known_count,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'blueprintId', blueprint_id::text,
              'name', name,
              'setName', set_name,
              'collectorNumber', card_number
            )
            order by confidence desc, blueprint_id desc
          ) filter (where example_rank <= 3),
          '[]'::jsonb
        ) as examples
      from matches
      group by normalized_artist
      order by known_count desc, artist asc
      limit 80
    `,
    [canonicalName, currentBlueprintId],
  );

  return result.rows.map((row) => ({
    normalizedArtist: row.normalized_artist || '',
    artist: row.artist || row.normalized_artist || '',
    knownCount: Number(row.known_count || 0),
    examples: Array.isArray(row.examples) ? row.examples : [],
  }));
}

async function allArtistOptions({ limit = 1000 } = {}) {
  const result = await marketplaceQuery(
    `
      with artists as (
        select
          normalized_artist,
          max(nullif(artist, '')) as artist,
          count(distinct blueprint_id)::integer as known_count
        from public.marketplace_blueprint_artists
        where normalized_artist <> ''
        group by normalized_artist
        union all
        select
          normalized_artist,
          max(nullif(display_name, '')) as artist,
          0 as known_count
        from public.marketplace_artist_profiles
        where normalized_artist <> ''
        group by normalized_artist
      ),
      merged as (
        select
          normalized_artist,
          (array_agg(artist order by known_count desc, artist asc))[1] as artist,
          sum(known_count)::integer as known_count
        from artists
        group by normalized_artist
      )
      select normalized_artist, artist, known_count
      from merged
      where coalesce(artist, '') <> ''
      order by artist asc
      limit $1::integer
    `,
    [Math.min(Math.max(Number(limit) || 1000, 1), 5000)],
  );
  return result.rows.map((row) => ({
    normalizedArtist: row.normalized_artist || '',
    artist: row.artist || row.normalized_artist || '',
    knownCount: Number(row.known_count || 0),
    examples: [],
  }));
}

async function artistOptionByNormalized(normalizedArtist) {
  const key = normalizeArtistKey(normalizedArtist);
  if (!key) return null;
  const result = await marketplaceQuery(
    `
      with artist_sources as (
        select
          normalized_artist,
          max(nullif(artist, '')) as artist,
          max(coalesce(artist_card_count, 0))::integer as artist_card_count,
          count(distinct blueprint_id)::integer as known_count
        from public.marketplace_blueprint_artists
        where normalized_artist = $1::text
        group by normalized_artist
        union all
        select
          normalized_artist,
          max(nullif(display_name, '')) as artist,
          0::integer as artist_card_count,
          0::integer as known_count
        from public.marketplace_artist_profiles
        where normalized_artist = $1::text
        group by normalized_artist
      ),
      merged as (
        select
          normalized_artist,
          (array_agg(artist order by known_count desc, artist_card_count desc, artist asc))[1] as artist,
          greatest(max(artist_card_count), sum(known_count))::integer as known_count
        from artist_sources
        where coalesce(artist, '') <> ''
        group by normalized_artist
      ),
      examples as (
        select
          artist.blueprint_id,
          cards.name,
          cards.set_name,
          cards.card_number,
          row_number() over (
            order by artist.confidence desc, artist.matched_at desc nulls last, artist.blueprint_id desc
          ) as example_rank
        from public.marketplace_blueprint_artists artist
        left join public.marketplace_search_candidates cards
          on cards.card_id = artist.blueprint_id
        where artist.normalized_artist = $1::text
      )
      select
        merged.normalized_artist,
        merged.artist,
        merged.known_count,
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'blueprintId', blueprint_id::text,
                'name', coalesce(name, ''),
                'setName', coalesce(set_name, ''),
                'collectorNumber', coalesce(card_number, '')
              )
              order by example_rank
            )
            from examples
            where example_rank <= 3
          ),
          '[]'::jsonb
        ) as examples
      from merged
      limit 1
    `,
    [key],
  );
  const row = result.rows[0];
  if (!row) return null;
  return {
    normalizedArtist: row.normalized_artist || '',
    artist: row.artist || row.normalized_artist || '',
    knownCount: Number(row.known_count || 0),
    examples: Array.isArray(row.examples) ? row.examples : [],
  };
}

async function fetchArtistOptionsForBlueprint(blueprintId) {
  const candidate = await loadCandidateForManualAction(blueprintId);
  const existing = await marketplaceQuery(
    `
      select artist, normalized_artist, confidence, source, match_reason
      from public.marketplace_blueprint_artists
      where blueprint_id = $1::bigint
      limit 1
    `,
    [blueprintId],
  );
  const current = existing.rows[0] || {};
  return {
    candidate: serializeCandidate(
      {
        card_id: blueprintId,
        name: candidate.name,
        canonical_name: candidate.canonical_name,
        set_name: candidate.set_name,
        card_number: candidate.card_number,
        item_kind: candidate.item_kind,
        product_type: candidate.product_type,
        current_artist: current.artist || '',
        current_normalized_artist: current.normalized_artist || '',
        current_confidence: current.confidence || 0,
        current_artist_source: current.source || '',
        current_match_reason: current.match_reason || '',
      },
      await allArtistOptions(),
    ),
    reason: '',
  };
}

function serializeCandidate(row, artists) {
  return {
    blueprintId: String(row.card_id || ''),
    name: row.name || '',
    sourceName: row.source_name || '',
    displayName: row.display_name || row.name || '',
    canonicalName: row.canonical_name || row.name || '',
    expansionName: row.set_name || '',
    collectorNumber: row.card_number || '',
    productVariant: row.product_variant || '',
    rarity: row.rarity || '',
    cardType: row.card_type || '',
    itemKind: row.item_kind || 'single',
    productType: row.product_type || 'card',
    trainerName: row.trainer_name || '',
    imageUrl: row.image_url || '',
    previewImageUrl: row.preview_image_url || row.image_url || '',
    currentArtist: row.current_artist || '',
    currentNormalizedArtist: row.current_normalized_artist || '',
    currentArtistSource: row.current_artist_source || '',
    currentConfidence: Number(row.current_confidence || 0),
    currentMatchReason: row.current_match_reason || '',
    missingReason: missingReason(row),
    artists,
  };
}

async function loadCandidateForManualAction(blueprintId) {
  await ensureClassificationOverrideTable();
  const result = await marketplaceQuery(
    `
      select
        c.card_id,
        c.name,
        coalesce(nullif(c.canonical_name, ''), c.name) as canonical_name,
        c.set_name,
        c.card_number,
        coalesce(o.item_kind, c.item_kind, 'single') as item_kind,
        coalesce(o.product_type, c.product_type, 'card') as product_type
      from public.marketplace_search_candidates c
      left join public.marketplace_blueprint_classification_overrides o
        on o.blueprint_id = c.card_id
      where c.card_id = $1::bigint
      limit 1
    `,
    [blueprintId],
  );
  const row = result.rows[0];
  if (!row) {
    const error = new Error('Blueprint was not found in marketplace search candidates.');
    error.statusCode = 404;
    throw error;
  }
  return row;
}

async function saveManualArtist(body, user) {
  const blueprintId = cleanBlueprintId(body?.blueprintId);
  const normalizedArtist = normalizeArtistKey(body?.normalizedArtist);
  if (!blueprintId || !normalizedArtist) {
    const error = new Error('Blueprint and artist are required.');
    error.statusCode = 400;
    throw error;
  }

  const candidate = await loadCandidateForManualAction(blueprintId);
  if (candidate.item_kind === 'product' || candidate.product_type !== 'card') {
    const error = new Error('This blueprint is classified as a product; artist selection is disabled.');
    error.statusCode = 409;
    throw error;
  }

  const options = body?.allowAnyArtist === true
    ? [await artistOptionByNormalized(normalizedArtist)].filter(Boolean)
    : await artistOptionsForIdentity(candidate.canonical_name, blueprintId);
  const selected = options.find((option) => option.normalizedArtist === normalizedArtist);
  if (!selected) {
    const error = new Error('Selected artist is not known for this Pokemon identity.');
    error.statusCode = 400;
    throw error;
  }

  const result = await marketplaceQuery(
    `
      insert into public.marketplace_blueprint_artists (
        blueprint_id,
        artist,
        illustrator,
        normalized_artist,
        source,
        source_card_id,
        source_url,
        confidence,
        match_reason,
        matched_at,
        raw_metadata,
        updated_at
      )
      values (
        $1::bigint,
        $2::text,
        $2::text,
        $3::text,
        $4::text,
        $5::text,
        '',
        0.99,
        $6::text,
        now(),
        $7::jsonb,
        now()
      )
      on conflict (blueprint_id)
      do update set
        artist = excluded.artist,
        illustrator = excluded.illustrator,
        normalized_artist = excluded.normalized_artist,
        source = excluded.source,
        source_card_id = excluded.source_card_id,
        source_url = excluded.source_url,
        confidence = excluded.confidence,
        match_reason = excluded.match_reason,
        matched_at = excluded.matched_at,
        raw_metadata = excluded.raw_metadata,
        updated_at = now()
      returning blueprint_id, artist, normalized_artist, confidence, source, match_reason, matched_at
    `,
    [
      blueprintId,
      selected.artist,
      selected.normalizedArtist,
      MANUAL_ARTIST_SOURCE,
      selected.examples[0]?.blueprintId || String(blueprintId),
      `Manual debug curation by ${userLabel(user)}${body?.allowAnyArtist === true ? ' from full artist list' : ` using known ${candidate.canonical_name} artists`}.`,
      JSON.stringify({
        debugUser: {
          uid: cleanText(user?.uid, 160),
          email: cleanText(user?.email, 240),
          username: cleanText(user?.username, 120),
        },
        candidate: {
          blueprintId: String(blueprintId),
          name: candidate.name || '',
          canonicalName: candidate.canonical_name || '',
          setName: candidate.set_name || '',
          collectorNumber: candidate.card_number || '',
        },
        selectedExamples: selected.examples,
      }),
    ],
  );

  return result.rows[0];
}

async function classifyBlueprintAsProduct(body, user) {
  const blueprintId = cleanBlueprintId(body?.blueprintId);
  const productType = cleanProductType(body?.productType);
  if (!blueprintId) {
    const error = new Error('Blueprint is required.');
    error.statusCode = 400;
    throw error;
  }

  const pool = getMarketplacePool();
  const client = await pool.connect();
  try {
    await client.query('begin');
    await ensureClassificationOverrideTable(client);
    const existing = await client.query(
      `
        select card_id, name
        from public.marketplace_search_candidates
        where card_id = $1::bigint
        limit 1
      `,
      [blueprintId],
    );
    if (!existing.rows[0]) {
      const error = new Error('Blueprint was not found in marketplace search candidates.');
      error.statusCode = 404;
      throw error;
    }

    const reason = cleanText(
      body?.reason || `Classified as product from artist debug page by ${userLabel(user)}.`,
      500,
    );
    await client.query(
      `
        with input as (
          select
            $1::bigint as blueprint_id,
            $2::text as product_type,
            $3::text as source,
            $4::text as reason,
            $5::text as debug_uid,
            $6::text as debug_email,
            $7::text as debug_username
        )
        insert into public.marketplace_blueprint_classification_overrides (
          blueprint_id,
          item_kind,
          product_type,
          source,
          reason,
          debug_uid,
          debug_email,
          debug_username,
          updated_at
        )
        select
          blueprint_id,
          'product'::text,
          product_type,
          source,
          reason,
          debug_uid,
          debug_email,
          debug_username,
          now()
        from input
        on conflict (blueprint_id)
        do update set
          item_kind = excluded.item_kind,
          product_type = excluded.product_type,
          source = excluded.source,
          reason = excluded.reason,
          debug_uid = excluded.debug_uid,
          debug_email = excluded.debug_email,
          debug_username = excluded.debug_username,
          updated_at = now()
      `,
      [
        blueprintId,
        productType,
        MANUAL_PRODUCT_SOURCE,
        reason,
        cleanText(user?.uid, 160),
        cleanText(user?.email, 240),
        cleanText(user?.username, 120),
      ],
    );

    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id, $2::text as product_type
        )
        update public.marketplace_cards as cards
        set item_kind = 'product',
          product_type = input.product_type,
          projected_at = now()
        from input
        where cards.card_id = input.blueprint_id
      `,
      [blueprintId, productType],
    );
    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id, $2::text as product_type
        )
        update public.marketplace_search_candidates as candidates
        set item_kind = 'product',
          product_type = input.product_type,
          search_text = lower(concat_ws(' ', canonical_name, display_name, source_name, set_name, card_number, product_variant, rarity, card_type, 'product', input.product_type, trainer_name)),
          projected_at = now()
        from input
        where candidates.card_id = input.blueprint_id
      `,
      [blueprintId, productType],
    );
    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id, $2::text as product_type
        )
        update public.marketplace_card_versions as versions
        set product_type = input.product_type,
          projected_at = now()
        from input
        where versions.card_id = input.blueprint_id or versions.blueprint_id = input.blueprint_id
      `,
      [blueprintId, productType],
    );
    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id, $2::text as product_type
        )
        update public.marketplace_card_urls as urls
        set item_kind = 'product',
          product_type = input.product_type,
          updated_at = now()
        from input
        where urls.card_id = input.blueprint_id
      `,
      [blueprintId, productType],
    );

    await client.query('commit');
    return {
      blueprintId: String(blueprintId),
      itemKind: 'product',
      productType,
      source: MANUAL_PRODUCT_SOURCE,
    };
  } catch (error) {
    await client.query('rollback').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

async function classifyBlueprintAsSingleCard(body, user) {
  const blueprintId = cleanBlueprintId(body?.blueprintId);
  if (!blueprintId) {
    const error = new Error('Blueprint is required.');
    error.statusCode = 400;
    throw error;
  }

  const pool = getMarketplacePool();
  const client = await pool.connect();
  try {
    await client.query('begin');
    await ensureClassificationOverrideTable(client);
    const existing = await client.query(
      `
        select card_id, name
        from public.marketplace_search_candidates
        where card_id = $1::bigint
        limit 1
      `,
      [blueprintId],
    );
    if (!existing.rows[0]) {
      const error = new Error('Blueprint was not found in marketplace search candidates.');
      error.statusCode = 404;
      throw error;
    }

    const reason = cleanText(
      body?.reason || `Classified as single card from detail debug button by ${userLabel(user)}.`,
      500,
    );
    await client.query(
      `
        with input as (
          select
            $1::bigint as blueprint_id,
            $2::text as source,
            $3::text as reason,
            $4::text as debug_uid,
            $5::text as debug_email,
            $6::text as debug_username
        )
        insert into public.marketplace_blueprint_classification_overrides (
          blueprint_id,
          item_kind,
          product_type,
          source,
          reason,
          debug_uid,
          debug_email,
          debug_username,
          updated_at
        )
        select
          blueprint_id,
          'single'::text,
          'card'::text,
          source,
          reason,
          debug_uid,
          debug_email,
          debug_username,
          now()
        from input
        on conflict (blueprint_id)
        do update set
          item_kind = excluded.item_kind,
          product_type = excluded.product_type,
          source = excluded.source,
          reason = excluded.reason,
          debug_uid = excluded.debug_uid,
          debug_email = excluded.debug_email,
          debug_username = excluded.debug_username,
          updated_at = now()
      `,
      [
        blueprintId,
        MANUAL_PRODUCT_SOURCE,
        reason,
        cleanText(user?.uid, 160),
        cleanText(user?.email, 240),
        cleanText(user?.username, 120),
      ],
    );
    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id
        )
        update public.marketplace_cards as cards
        set item_kind = 'single',
          product_type = 'card',
          projected_at = now()
        from input
        where cards.card_id = input.blueprint_id
      `,
      [blueprintId],
    );
    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id
        )
        update public.marketplace_search_candidates as candidates
        set item_kind = 'single',
          product_type = 'card',
          search_text = lower(concat_ws(' ', canonical_name, display_name, source_name, set_name, card_number, rarity, card_type, trainer_name)),
          projected_at = now()
        from input
        where candidates.card_id = input.blueprint_id
      `,
      [blueprintId],
    );
    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id
        )
        update public.marketplace_card_versions as versions
        set product_type = 'card',
          projected_at = now()
        from input
        where versions.card_id = input.blueprint_id or versions.blueprint_id = input.blueprint_id
      `,
      [blueprintId],
    );
    await client.query(
      `
        with input as (
          select $1::bigint as blueprint_id
        )
        update public.marketplace_card_urls as urls
        set item_kind = 'single',
          product_type = 'card',
          updated_at = now()
        from input
        where urls.card_id = input.blueprint_id
      `,
      [blueprintId],
    );
    await client.query('commit');
    return {
      blueprintId: String(blueprintId),
      itemKind: 'single',
      productType: 'card',
      source: MANUAL_PRODUCT_SOURCE,
    };
  } catch (error) {
    await client.query('rollback').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

async function skipCandidate(body, user) {
  const blueprintId = cleanBlueprintId(body?.blueprintId);
  if (!blueprintId) {
    const error = new Error('Blueprint is required.');
    error.statusCode = 400;
    throw error;
  }
  await ensureArtistDebugSkipTable();
  await marketplaceQuery(
    `
      insert into public.marketplace_artist_debug_skips (
        blueprint_id,
        debug_uid,
        debug_email,
        debug_username,
        reason,
        skipped_at
      )
      values ($1::bigint, $2::text, $3::text, $4::text, $5::text, now())
    `,
    [
      blueprintId,
      cleanText(user?.uid, 160),
      cleanText(user?.email, 240),
      cleanText(user?.username, 120),
      cleanText(body?.reason || `Skipped from artist debug page by ${userLabel(user)}.`, 500),
    ],
  );
  return { blueprintId: String(blueprintId), skipped: true };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const user = await authorizeSearchDebugRequest(req);
    if (req.method === 'GET') {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const blueprintId = cleanBlueprintId(url.searchParams.get('blueprintId'));
      const payload = blueprintId
        ? await fetchArtistOptionsForBlueprint(blueprintId)
        : await fetchNextArtistCandidate(user);
      res.setHeader('Cache-Control', 'private, no-store');
      return res.status(200).json({
        ...payload,
        generatedAt: new Date().toISOString(),
        user,
      });
    }

    const action = cleanText(req.body?.action, 40);
    if (action === 'select_artist') {
      const saved = await saveManualArtist(req.body || {}, user);
      return res.status(200).json({ ok: true, saved });
    }
    if (action === 'classify_product') {
      const classified = await classifyBlueprintAsProduct(req.body || {}, user);
      return res.status(200).json({ ok: true, classified });
    }
    if (action === 'classify_single') {
      const classified = await classifyBlueprintAsSingleCard(req.body || {}, user);
      return res.status(200).json({ ok: true, classified });
    }
    if (action === 'skip') {
      const skipped = await skipCandidate(req.body || {}, user);
      return res.status(200).json({ ok: true, skipped });
    }

    return res.status(400).json({ error: 'Unsupported artist debug action.' });
  } catch (error) {
    console.error('marketplace-debug-artists failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace artist debug failed.',
    });
  }
};

module.exports._test = {
  cleanBlueprintId,
  cleanProductType,
  cleanText,
  missingReason,
  normalizeArtistKey,
  artistOptionByNormalized,
  serializeCandidate,
};
