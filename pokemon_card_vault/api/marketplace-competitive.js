const { marketplaceQuery } = require('./_marketplace_db');

function cleanLimit(value, fallback = 40, max = 120) {
  if (value == null || value === '') return fallback;
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), max);
}

function cleanText(value, maxLength = 80) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanTournamentId(value) {
  return cleanText(value, 64).replace(/[^a-zA-Z0-9_-]/g, '');
}

function cleanDeckId(value) {
  return cleanText(value, 32).replace(/[^0-9]/g, '');
}

function cleanDecklistId(value) {
  const clean = cleanText(value, 120);
  return clean === '[object Object]' ? '' : clean;
}

function cleanYear(value) {
  const year = Number(value);
  if (!Number.isSafeInteger(year) || year < 2000 || year > 2100) return null;
  return year;
}

function wants(value) {
  return value === '1' || value === 'true' || value === 'yes';
}

function isMissingPublicLimitlessTable(error) {
  return error?.code === '42P01' && /limitless_public_/.test(String(error.message || ''));
}

function formatLabel(gameRow, formatId) {
  if (!formatId) return '';
  const formats = gameRow?.formats && typeof gameRow.formats === 'object'
    ? gameRow.formats
    : {};
  return formats[formatId] || formatId;
}

function tournamentFromRow(row) {
  return {
    id: row.tournament_id,
    name: row.name || '',
    game: row.game_id || '',
    gameName: row.game_name || row.game_id || '',
    format: row.format || '',
    formatLabel: row.format_label || row.format || '',
    date: row.tournament_date,
    players: Number(row.player_count || 0),
    organizerId: row.organizer_id,
    organizerName: row.organizer_name || '',
    platform: row.platform || '',
    decklistsAvailable: row.decklists_available === true,
    isPublic: row.is_public !== false,
    isOnline: row.is_online === true,
    phases: row.phases || [],
    sourceUrl: row.source_url || '',
    detailsFetchedAt: row.details_fetched_at,
    standingsFetchedAt: row.standings_fetched_at,
    pairingsFetchedAt: row.pairings_fetched_at,
    updatedAt: row.updated_at,
  };
}

function publicTournamentFromRow(row) {
  return {
    id: row.tournament_id,
    name: row.name || '',
    game: 'PTCG',
    gameName: 'Pokemon TCG',
    format: row.format || '',
    formatLabel: row.format_label || row.format || '',
    date: row.tournament_date,
    players: Number(row.player_count || 0),
    organizerId: null,
    organizerName: row.country_name || row.country || '',
    platform: 'Limitless',
    decklistsAvailable: true,
    isPublic: true,
    isOnline: false,
    phases: [],
    sourceUrl: row.source_url || '',
    detailsFetchedAt: row.source_fetched_at,
    standingsFetchedAt: row.source_fetched_at,
    pairingsFetchedAt: null,
    updatedAt: row.updated_at,
    winnerName: row.winner_name || '',
    winnerCountry: row.winner_country || '',
  };
}

function standingFromRow(row) {
  return {
    placing: row.placing,
    playerId: row.player_id || '',
    name: row.display_name || row.player_id || '',
    country: row.country || '',
    record: {
      wins: Number(row.wins || 0),
      losses: Number(row.losses || 0),
      ties: Number(row.ties || 0),
    },
    dropRound: row.drop_round,
    deckName: row.deck_name || '',
    deckArchetype: row.deck_archetype || '',
    decklistId: cleanDecklistId(row.decklist_id),
    deckSummary: row.deck_summary || {},
  };
}

function pairingFromRow(row) {
  return {
    phase: Number(row.phase || 0),
    round: Number(row.round || 0),
    table: Number(row.table_number || 0),
    player1Id: row.player1_id || '',
    player1Name: row.player1_name || row.player1_id || '',
    player2Id: row.player2_id || '',
    player2Name: row.player2_name || row.player2_id || '',
    winnerPlayerId: row.winner_player_id || '',
    result: row.result || '',
  };
}

function publicStandingFromRow(row) {
  return {
    placing: row.placing,
    playerId: row.player_id || '',
    name: row.player_name || row.player_id || '',
    country: row.country || '',
    record: {
      wins: 0,
      losses: 0,
      ties: 0,
    },
    dropRound: null,
    deckName: row.deck_name || '',
    deckArchetype: row.variant || row.deck_name || '',
    decklistId: cleanDecklistId(row.decklist_id),
    deckSummary: {
      deckId: row.deck_id || '',
      sourceUrl: row.source_url || '',
    },
  };
}

function gameFromRow(row) {
  return {
    id: row.game_id || '',
    name: row.name || row.game_id || '',
    formats: row.formats || {},
    platforms: row.platforms || {},
    metagame: row.metagame === true,
  };
}

function topDeckFromRow(row) {
  return {
    deckId: row.deck_id ? String(row.deck_id) : '',
    archetype: row.archetype || 'Unknown deck',
    game: row.game_id || '',
    format: row.format || '',
    formatLabel: row.format_label || row.format || '',
    count: Number(row.deck_count || 0),
    share: Number(row.share || 0),
    points: Number(row.points || 0),
    featuredPlayer: row.featured_player || '',
    featuredPlacing: row.featured_placing,
    featuredRecord: {
      wins: Number(row.featured_wins || 0),
      losses: Number(row.featured_losses || 0),
      ties: Number(row.featured_ties || 0),
    },
    featuredTournamentId: row.featured_tournament_id || '',
    featuredTournamentName: row.featured_tournament_name || '',
    featuredTournamentDate: row.featured_tournament_date || null,
    featuredDecklistId: cleanDecklistId(row.featured_decklist_id),
    representativeCardId: row.representative_card_id ? String(row.representative_card_id) : '',
    representativeCardName: row.representative_card_name || '',
    representativeCardSetName: row.representative_card_set_name || '',
    representativeCardNumber: row.representative_card_number || '',
    representativeCardPath: row.representative_card_path || '',
    imageUrl: row.representative_image_url || '',
    cardImageUrl: row.representative_image_url || '',
    sourceUrl: row.source_url || '',
  };
}

function deckCardFromRow(row) {
  return {
    name: row.display_name || row.card_name || '',
    count: row.count == null ? null : Number(row.count),
    inclusionShare: row.inclusion_share == null ? null : Number(row.inclusion_share),
    section: row.section || '',
    setCode: row.set_code || '',
    collectorNumber: row.collector_number || '',
    sourceUrl: row.source_url || '',
    marketplaceCardId: row.marketplace_card_id ? String(row.marketplace_card_id) : '',
    marketplacePath: row.marketplace_card_path || '',
    imageUrl: row.marketplace_image_url || '',
  };
}

function deckResultFromRow(row) {
  return {
    tournamentId: row.tournament_id || '',
    tournamentName: row.tournament_name || '',
    tournamentDate: row.tournament_date || null,
    format: row.format || '',
    placing: row.placing,
    placingLabel: row.placing_label || '',
    variant: row.variant || '',
    playerId: row.player_id || '',
    playerName: row.player_name || '',
    decklistId: cleanDecklistId(row.decklist_id),
    sourceUrl: row.source_url || '',
  };
}

function deckPlayerFromRow(row) {
  return {
    playerId: row.player_id || '',
    playerName: row.player_name || '',
    country: row.country || '',
    rank: row.rank,
    points: Number(row.points || 0),
    sourceUrl: row.source_url || '',
  };
}

function deckDetailFromRow(row) {
  return {
    id: row.deck_id || '',
    name: row.name || '',
    format: row.format || '',
    formatLabel: row.format_label || row.format || '',
    rank: row.rank,
    points: Number(row.points || row.total_points || 0),
    share: Number(row.share || 0),
    earningsText: row.earnings_text || '',
    totalPoints: Number(row.total_points || 0),
    regionalTop8: Number(row.regional_top8 || 0),
    regionalWins: Number(row.regional_wins || 0),
    internationalTop8: Number(row.international_top8 || 0),
    internationalWins: Number(row.international_wins || 0),
    variants: Array.isArray(row.variants) ? row.variants : [],
    sourceUrl: row.source_url || '',
    updatedAt: row.updated_at,
  };
}

function buildTournamentFilters({ game, format, year } = {}, alias = 't') {
  const values = [];
  let where = 'where true';
  const cleanGame = cleanText(game, 24).toUpperCase();
  const cleanFormat = cleanText(format, 40).toUpperCase();
  const cleanYearValue = cleanYear(year);
  if (cleanGame) {
    values.push(cleanGame);
    where += ` and ${alias}.game_id = $${values.length}`;
  }
  if (cleanFormat) {
    values.push(cleanFormat);
    where += ` and upper(${alias}.format) = $${values.length}`;
  }
  if (cleanYearValue) {
    values.push(cleanYearValue);
    where += ` and ${alias}.tournament_date >= make_timestamptz($${values.length}, 1, 1, 0, 0, 0)`;
    values.push(cleanYearValue + 1);
    where += ` and ${alias}.tournament_date < make_timestamptz($${values.length}, 1, 1, 0, 0, 0)`;
  }
  return { where, values };
}

async function fetchGames({ query = marketplaceQuery } = {}) {
  const result = await query(
    `
      select game_id, name, formats, platforms, metagame
      from public.limitless_games
      order by
        case when game_id = 'PTCG' then 0 when game_id = 'POCKET' then 1 else 2 end,
        name asc
    `,
  );
  return result.rows.map(gameFromRow);
}

async function fetchTournamentList({
  game,
  format,
  year,
  limit,
  query = marketplaceQuery,
} = {}) {
  const { where, values } = buildTournamentFilters({ game, format, year });
  values.push(cleanLimit(limit));
  const result = await query(
    `
      select
        t.tournament_id,
        t.name,
        t.game_id,
        g.name as game_name,
        t.format,
        coalesce(g.formats ->> t.format, t.format, '') as format_label,
        t.tournament_date,
        t.player_count,
        t.organizer_id,
        t.organizer_name,
        t.platform,
        t.decklists_available,
        t.is_public,
        t.is_online,
        t.phases,
        t.source_url,
        t.details_fetched_at,
        t.standings_fetched_at,
        t.pairings_fetched_at,
        t.updated_at
      from public.limitless_tournaments t
      left join public.limitless_games g on g.game_id = t.game_id
      ${where}
      order by t.tournament_date desc nulls last, t.player_count desc, t.tournament_id desc
      limit $${values.length}
    `,
    values,
  );
  return result.rows.map(tournamentFromRow);
}

async function fetchTopDecks({
  game,
  format,
  year,
  limit = 8,
  query = marketplaceQuery,
} = {}) {
  const publicDecks = await fetchPublicTopDecks({ format, year, limit, query }).catch((error) => {
    if (isMissingPublicLimitlessTable(error)) return [];
    throw error;
  });
  if (publicDecks.length > 0) return publicDecks;

  const { where, values } = buildTournamentFilters({ game, format, year });
  values.push(cleanLimit(limit, 8, 24));
  const result = await query(
    `
      with filtered as (
        select
          coalesce(nullif(s.deck_archetype, ''), nullif(s.deck_name, ''), 'Unknown deck') as archetype,
          t.game_id,
          t.format,
          coalesce(g.formats ->> t.format, t.format, '') as format_label,
          s.display_name,
          s."placing",
          s.wins,
          s.losses,
          s.ties,
          s.decklist_id,
          t.tournament_id,
          t.name as tournament_name,
          t.tournament_date
        from public.limitless_tournament_standings s
        join public.limitless_tournaments t on t.tournament_id = s.tournament_id
        left join public.limitless_games g on g.game_id = t.game_id
        ${where}
      ),
      ranked as (
        select
          *,
          row_number() over (
            partition by archetype
            order by "placing" asc nulls last, wins desc, losses asc, tournament_date desc nulls last
          ) as featured_rank
        from filtered
      ),
      grouped as (
        select
          archetype,
          max(game_id) as game_id,
          max(format) as format,
          max(format_label) as format_label,
          count(*)::integer as deck_count,
          case
            when sum(count(*)) over () = 0 then 0
            else round((count(*)::numeric / sum(count(*)) over ()) * 100, 1)
          end as share
        from filtered
        group by archetype
      ),
      top_grouped as (
        select *
        from grouped
        order by deck_count desc, archetype asc
        limit $${values.length}
      )
      select
        top_grouped.*,
        ranked.display_name as featured_player,
        ranked."placing" as featured_placing,
        ranked.wins as featured_wins,
        ranked.losses as featured_losses,
        ranked.ties as featured_ties,
        ranked.decklist_id as featured_decklist_id,
        ranked.tournament_id as featured_tournament_id,
        ranked.tournament_name as featured_tournament_name,
        ranked.tournament_date as featured_tournament_date,
        representative.card_id as representative_card_id,
        representative.name as representative_card_name,
        representative.set_name as representative_card_set_name,
        representative.card_number as representative_card_number,
        representative.canonical_path as representative_card_path,
        representative.image_url as representative_image_url
      from top_grouped
      left join ranked on ranked.archetype = top_grouped.archetype and ranked.featured_rank = 1
      left join lateral (
        select
          c.card_id,
          c.name,
          c.set_name,
          c.card_number,
          coalesce(urls.canonical_path, '') as canonical_path,
          coalesce(
            nullif(c.preview_image_url, ''),
            nullif(c.homepage_image_url, ''),
            nullif(c.cdn_image_url, ''),
            nullif(c.image_url, ''),
            ''
          ) as image_url
        from public.marketplace_search_candidates c
        left join public.marketplace_card_urls urls
          on urls.card_id = c.card_id and urls.language = 'en'
        cross join lateral (
          select
            regexp_replace(lower(top_grouped.archetype), '[^a-z0-9]+', '', 'g') as compact_archetype,
            regexp_replace(lower(top_grouped.archetype), '[^a-z0-9]+', ' ', 'g') as archetype_words,
            regexp_replace(lower(coalesce(nullif(c.canonical_name, ''), c.name)), '[^a-z0-9]+', '', 'g') as compact_card,
            regexp_replace(lower(coalesce(nullif(c.canonical_name, ''), c.name)), '[^a-z0-9]+', ' ', 'g') as card_words
        ) normalized
        cross join lateral (
          select array_remove(array_agg(token.value), null) as tokens
          from regexp_split_to_table(normalized.archetype_words, '[[:space:]]+') as token(value)
          where length(token.value) >= 4
            and token.value not in (
              'mega', 'pokemon', 'pokémon', 'deck', 'box', 'toolbox', 'lost',
              'zone', 'future', 'ancient', 'control', 'stall', 'turbo',
              'festival', 'lead', 'ex', 'vstar', 'vmax', 'basic'
            )
        ) significant
        where c.item_kind = 'single'
          and coalesce(c.preview_image_url, c.homepage_image_url, c.cdn_image_url, c.image_url, '') <> ''
          and normalized.compact_archetype <> ''
          and (
            normalized.compact_card = normalized.compact_archetype
            or normalized.compact_card like normalized.compact_archetype || '%'
            or normalized.compact_archetype like normalized.compact_card || '%'
            or (coalesce(array_length(significant.tokens, 1), 0) > 0 and exists (
              select 1
              from unnest(significant.tokens) as token(value)
              where normalized.card_words like '%' || token.value || '%'
            ))
          )
        order by
          case when normalized.compact_card = normalized.compact_archetype then 0 else 1 end,
          case when normalized.compact_card like normalized.compact_archetype || '%' then 0 else 1 end,
          case when normalized.compact_archetype like normalized.compact_card || '%' then 0 else 1 end,
          (
            select count(*)
            from unnest(significant.tokens) as token(value)
            where normalized.card_words like '%' || token.value || '%'
          ) desc,
          c.search_weight desc,
          c.imported_at desc nulls last,
          c.card_id asc
        limit 1
      ) representative on true
      order by top_grouped.deck_count desc, top_grouped.archetype asc
    `,
    values,
  );
  return result.rows.map(topDeckFromRow);
}

async function fetchPublicTopDecks({
  format,
  year,
  limit = 8,
  query = marketplaceQuery,
} = {}) {
  const values = [];
  let where = 'where true';
  const cleanFormat = cleanText(format, 40).toUpperCase();
  const cleanYearValue = cleanYear(year);
  if (cleanFormat) {
    values.push(cleanFormat);
    where += ` and (upper(d.format) = $${values.length} or d.format is null)`;
  }
  if (cleanYearValue) {
    values.push(cleanYearValue);
    where += ` and exists (
      select 1
      from public.limitless_public_deck_results r
      where r.deck_id = d.deck_id
        and r.tournament_date >= make_date($${values.length}, 1, 1)
        and r.tournament_date < make_date($${values.length} + 1, 1, 1)
    )`;
  }
  values.push(cleanLimit(limit, 8, 24));
  const result = await query(
    `
      with top_decks as (
        select
          d.deck_id,
          d.name as archetype,
          'PTCG' as game_id,
          coalesce(d.format, '') as format,
          coalesce(d.format_label, d.format, '') as format_label,
          d.points as deck_count,
          d.points,
          d.share,
          d.source_url
        from public.limitless_public_decks d
        ${where}
        order by d.rank asc nulls last, d.points desc, d.share desc, d.name asc
        limit $${values.length}
      )
      select
        d.*,
        featured.player_name as featured_player,
        featured."placing" as featured_placing,
        featured.decklist_id as featured_decklist_id,
        featured.tournament_id as featured_tournament_id,
        featured.tournament_name as featured_tournament_name,
        featured.tournament_date as featured_tournament_date,
        null::bigint as representative_card_id,
        ''::text as representative_card_name,
        ''::text as representative_card_set_name,
        ''::text as representative_card_number,
        ''::text as representative_card_path,
        ''::text as representative_image_url
      from top_decks d
      left join lateral (
        select *
        from public.limitless_public_deck_results r
        where r.deck_id = d.deck_id
        order by r.tournament_date desc nulls last, r."placing" asc nulls last, r.player_name asc
        limit 1
      ) featured on true
      order by d.deck_count desc, d.archetype asc
    `,
    values,
  );
  return result.rows.map(topDeckFromRow);
}

async function fetchTournamentGroup({
  game,
  format,
  year,
  group,
  limit = 8,
  query = marketplaceQuery,
} = {}) {
  if (group === 'recent') {
    const publicRecent = await fetchPublicTournamentGroup({ format, year, limit, query }).catch((error) => {
      if (isMissingPublicLimitlessTable(error)) return [];
      throw error;
    });
    if (publicRecent.length > 0) return publicRecent;
  }
  const { where, values } = buildTournamentFilters({ game, format, year });
  let groupFilter = '';
  let orderBy = 't.tournament_date desc nulls last, t.player_count desc, t.tournament_id desc';
  if (group === 'upcoming') {
    groupFilter = 'and t.tournament_date >= now()';
    orderBy = 't.tournament_date asc nulls last, t.player_count desc, t.tournament_id desc';
  } else if (group === 'city') {
    groupFilter = 'and t.is_online is false';
  } else {
    groupFilter = 'and (t.tournament_date is null or t.tournament_date <= now())';
  }
  values.push(cleanLimit(limit, 8, 24));
  const result = await query(
    `
      select
        t.tournament_id,
        t.name,
        t.game_id,
        g.name as game_name,
        t.format,
        coalesce(g.formats ->> t.format, t.format, '') as format_label,
        t.tournament_date,
        t.player_count,
        t.organizer_id,
        t.organizer_name,
        t.platform,
        t.decklists_available,
        t.is_public,
        t.is_online,
        t.phases,
        t.source_url,
        t.details_fetched_at,
        t.standings_fetched_at,
        t.pairings_fetched_at,
        t.updated_at
      from public.limitless_tournaments t
      left join public.limitless_games g on g.game_id = t.game_id
      ${where}
      ${groupFilter}
      order by ${orderBy}
      limit $${values.length}
    `,
    values,
  );
  return result.rows.map(tournamentFromRow);
}

async function fetchPublicTournamentGroup({
  format,
  year,
  limit = 8,
  query = marketplaceQuery,
} = {}) {
  const values = [];
  let where = 'where true';
  const cleanFormat = cleanText(format, 40).toUpperCase();
  const cleanYearValue = cleanYear(year);
  if (cleanFormat) {
    values.push(cleanFormat);
    where += ` and upper(t.format) = $${values.length}`;
  }
  if (cleanYearValue) {
    values.push(cleanYearValue);
    where += ` and t.tournament_date >= make_date($${values.length}, 1, 1)`;
    values.push(cleanYearValue + 1);
    where += ` and t.tournament_date < make_date($${values.length}, 1, 1)`;
  }
  values.push(cleanLimit(limit, 8, 24));
  const result = await query(
    `
      select *
      from public.limitless_public_tournaments t
      ${where}
      order by t.tournament_date desc nulls last, t.player_count desc, t.tournament_id desc
      limit $${values.length}
    `,
    values,
  );
  return result.rows.map(publicTournamentFromRow);
}

async function fetchDashboard({ game, format, year, query = marketplaceQuery } = {}) {
  const [topDecks, recentTournaments, upcomingTournaments, cityLeagues] = await Promise.all([
    fetchTopDecks({ game, format, year, query }),
    fetchTournamentGroup({ game, format, year, group: 'recent', query }),
    fetchTournamentGroup({ game, format, year, group: 'upcoming', query }),
    fetchTournamentGroup({ game, format, year, group: 'city', query }),
  ]);
  return {
    topDecks,
    recentTournaments,
    upcomingTournaments,
    cityLeagues,
  };
}

async function fetchYears({ game, format, query = marketplaceQuery } = {}) {
  const { where, values } = buildTournamentFilters({ game, format });
  const result = await query(
    `
      select distinct extract(year from t.tournament_date)::integer as year
      from public.limitless_tournaments t
      ${where}
        and t.tournament_date is not null
      order by year desc
      limit 12
    `,
    values,
  );
  return result.rows.map((row) => Number(row.year)).filter(Number.isSafeInteger);
}

async function fetchTournamentSnapshot({
  tournamentId,
  standingsLimit = 80,
  pairingsLimit = 120,
  query = marketplaceQuery,
} = {}) {
  const id = cleanTournamentId(tournamentId);
  if (!id) return null;
  const tournamentResult = await query(
    `
      select
        t.tournament_id,
        t.name,
        t.game_id,
        g.name as game_name,
        t.format,
        coalesce(g.formats ->> t.format, t.format, '') as format_label,
        t.tournament_date,
        t.player_count,
        t.organizer_id,
        t.organizer_name,
        t.platform,
        t.decklists_available,
        t.is_public,
        t.is_online,
        t.phases,
        t.source_url,
        t.details_fetched_at,
        t.standings_fetched_at,
        t.pairings_fetched_at,
        t.updated_at
      from public.limitless_tournaments t
      left join public.limitless_games g on g.game_id = t.game_id
      where t.tournament_id = $1
      limit 1
    `,
    [id],
  );
  const row = tournamentResult.rows[0];
  if (!row) return null;

  const standingsResult = await query(
    `
      select *
      from public.limitless_tournament_standings
      where tournament_id = $1
      order by "placing" asc nulls last, wins desc, losses asc, display_name asc
      limit $2
    `,
    [id, cleanLimit(standingsLimit, 80, 300)],
  );

  const pairingsResult = await query(
    `
      select
        p.phase,
        p.round,
        p.table_number,
        p.player1_id,
        coalesce(player1.display_name, p.player1_id) as player1_name,
        p.player2_id,
        coalesce(player2.display_name, p.player2_id) as player2_name,
        p.winner_player_id,
        p.result
      from public.limitless_tournament_pairings p
      left join public.limitless_players player1 on player1.player_id = p.player1_id
      left join public.limitless_players player2 on player2.player_id = p.player2_id
      where p.tournament_id = $1
      order by p.phase desc, p.round desc, p.table_number asc, p.match_index asc
      limit $2
    `,
    [id, cleanLimit(pairingsLimit, 120, 500)],
  );

  return {
    tournament: tournamentFromRow(row),
    standings: standingsResult.rows.map(standingFromRow),
    pairings: pairingsResult.rows.map(pairingFromRow),
  };
}

async function fetchPublicTournamentSnapshot({
  tournamentId,
  standingsLimit = 80,
  query = marketplaceQuery,
} = {}) {
  const id = cleanTournamentId(tournamentId);
  if (!id) return null;
  const tournamentResult = await query(
    `
      select *
      from public.limitless_public_tournaments
      where tournament_id = $1
      limit 1
    `,
    [id],
  );
  const row = tournamentResult.rows[0];
  if (!row) return null;

  const standingsResult = await query(
    `
      select *
      from public.limitless_public_tournament_standings
      where tournament_id = $1
      order by "placing" asc nulls last, player_name asc
      limit $2
    `,
    [id, cleanLimit(standingsLimit, 80, 300)],
  );

  return {
    tournament: publicTournamentFromRow(row),
    standings: standingsResult.rows.map(publicStandingFromRow),
    pairings: [],
  };
}

async function fetchDeckDetail({
  deckId,
  resultLimit = 80,
  cardLimit = 24,
  playerLimit = 10,
  decklistLimit = 4,
  query = marketplaceQuery,
} = {}) {
  const id = cleanDeckId(deckId);
  if (!id) return null;
  const deckResult = await query(
    `
      select *
      from public.limitless_public_decks
      where deck_id = $1
      limit 1
    `,
    [id],
  );
  const row = deckResult.rows[0];
  if (!row) return null;

  const cardsResult = await query(
    `
      select
        core.*,
        c.card_id as marketplace_card_id,
        coalesce(urls.canonical_path, '') as marketplace_card_path,
        coalesce(
          nullif(c.preview_image_url, ''),
          nullif(c.homepage_image_url, ''),
          nullif(c.cdn_image_url, ''),
          nullif(c.image_url, ''),
          ''
        ) as marketplace_image_url
      from public.limitless_public_deck_core_cards core
      left join lateral (
        select
          c.card_id,
          c.preview_image_url,
          c.homepage_image_url,
          c.cdn_image_url,
          c.image_url
        from public.marketplace_search_candidates c
        left join public.cardtrader_pokemon_blueprints b on b.id = c.card_id
        cross join lateral (
          select
            regexp_replace(lower(coalesce(nullif(c.canonical_name, ''), c.name)), '[^a-z0-9]+', '', 'g') as candidate_name,
            regexp_replace(lower(core.display_name), '[^a-z0-9]+', '', 'g') as core_name,
            regexp_replace(lower(coalesce(nullif(c.card_number, ''), nullif(b.version, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''))), '[^a-z0-9]+', '', 'g') as candidate_number,
            regexp_replace(lower(coalesce(nullif(core.collector_number, ''), core.card_key)), '[^a-z0-9]+', '', 'g') as core_number,
            lower(coalesce(nullif(b.expansion->>'code', ''), nullif(b.blueprint->>'expansion_code', ''), nullif(b.blueprint->>'set_code', ''))) as candidate_set_code,
            lower(coalesce(nullif(core.set_code, ''), split_part(core.display_name, ' ', 1))) as core_set_code
        ) normalized
        where c.item_kind = 'single'
          and (
            normalized.candidate_name = normalized.core_name
            or (
              normalized.core_number <> ''
              and (
                normalized.candidate_number = normalized.core_number
                or normalized.candidate_number like normalized.core_number || '%'
              )
              and (
                normalized.core_set_code = ''
                or normalized.candidate_set_code = normalized.core_set_code
                or lower(c.set_name) = normalized.core_set_code
              )
            )
          )
        order by c.search_weight desc, c.imported_at desc nulls last, c.card_id asc
        limit 1
      ) c on true
      left join public.marketplace_card_urls urls
        on urls.card_id = c.card_id and urls.language = 'en'
      where core.deck_id = $1
      order by core.inclusion_share desc nulls last, core.count desc nulls last, core.display_name asc
      limit $2
    `,
    [id, cleanLimit(cardLimit, 24, 80)],
  );
  const resultsResult = await query(
    `
      select *
      from public.limitless_public_deck_results
      where deck_id = $1
      order by tournament_date desc nulls last, "placing" asc nulls last, player_name asc
      limit $2
    `,
    [id, cleanLimit(resultLimit, 80, 300)],
  );
  const playersResult = await query(
    `
      select *
      from public.limitless_public_deck_players
      where deck_id = $1
      order by rank asc nulls last, points desc, player_name asc
      limit $2
    `,
    [id, cleanLimit(playerLimit, 10, 50)],
  );
  const decklistIds = resultsResult.rows
    .map((resultRow) => cleanDecklistId(resultRow.decklist_id))
    .filter(Boolean)
    .slice(0, cleanLimit(decklistLimit, 4, 20));
  let decklists = [];
  if (decklistIds.length > 0) {
    const decklistsResult = await query(
      `
        select *
        from public.limitless_public_decklist_cards
        where decklist_id = any($1::text[])
        order by decklist_id, section, count desc, card_name asc
      `,
      [decklistIds],
    );
    const grouped = new Map();
    for (const card of decklistsResult.rows) {
      if (!grouped.has(card.decklist_id)) grouped.set(card.decklist_id, []);
      grouped.get(card.decklist_id).push(deckCardFromRow(card));
    }
    decklists = decklistIds.map((decklistId) => ({
      decklistId,
      cards: grouped.get(decklistId) || [],
    }));
  }

  return {
    deck: deckDetailFromRow(row),
    coreCards: cardsResult.rows.map(deckCardFromRow),
    results: resultsResult.rows.map(deckResultFromRow),
    players: playersResult.rows.map(deckPlayerFromRow),
    decklists,
  };
}

async function fetchSummary({ game, format, year, query = marketplaceQuery } = {}) {
  const { where, values } = buildTournamentFilters({ game, format, year });
  const result = await query(
    `
      select
        count(*)::integer as tournament_count,
        coalesce(sum(player_count), 0)::integer as total_players,
        count(*) filter (where standings_fetched_at is not null)::integer as standings_count,
        count(*) filter (where pairings_fetched_at is not null)::integer as pairings_count,
        max(updated_at) as updated_at
      from public.limitless_tournaments t
      ${where}
    `,
    values,
  );
  const row = result.rows[0] || {};
  const publicResult = await query(
    `
      select
        count(*)::integer as deck_count,
        coalesce(sum(points), 0)::integer as total_points,
        max(updated_at) as updated_at
      from public.limitless_public_decks
    `,
  ).catch(() => ({ rows: [] }));
  const publicRow = publicResult.rows[0] || {};
  return {
    tournamentCount: Number(row.tournament_count || 0),
    totalPlayers: Number(row.total_players || 0),
    tournamentsWithStandings: Number(row.standings_count || 0),
    tournamentsWithPairings: Number(row.pairings_count || 0),
    publicDeckCount: Number(publicRow.deck_count || 0),
    publicDeckPoints: Number(publicRow.total_points || 0),
    updatedAt: publicRow.updated_at || row.updated_at || null,
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const deckId = cleanDeckId(url.searchParams.get('deckId'));
    if (deckId) {
      const detail = await fetchDeckDetail({
        deckId,
        resultLimit: url.searchParams.get('resultLimit'),
        cardLimit: url.searchParams.get('cardLimit'),
        playerLimit: url.searchParams.get('playerLimit'),
        decklistLimit: url.searchParams.get('decklistLimit'),
      });
      if (!detail) {
        return res.status(404).json({ error: 'Deck not found.' });
      }
      res.setHeader('Cache-Control', 'public, max-age=30, s-maxage=180, stale-while-revalidate=300');
      return res.status(200).json(detail);
    }

    const tournamentId = cleanTournamentId(url.searchParams.get('tournamentId'));
    if (tournamentId) {
      const snapshot = await fetchTournamentSnapshot({
        tournamentId,
        standingsLimit: url.searchParams.get('standingsLimit'),
        pairingsLimit: url.searchParams.get('pairingsLimit'),
      }).catch((error) => {
        if (isMissingPublicLimitlessTable(error)) return null;
        throw error;
      }) || await fetchPublicTournamentSnapshot({
        tournamentId,
        standingsLimit: url.searchParams.get('standingsLimit'),
      }).catch((error) => {
        if (isMissingPublicLimitlessTable(error)) return null;
        throw error;
      });
      if (!snapshot) {
        return res.status(404).json({ error: 'Tournament not found.' });
      }
      res.setHeader('Cache-Control', 'public, max-age=30, s-maxage=120, stale-while-revalidate=300');
      return res.status(200).json(snapshot);
    }

    const game = url.searchParams.get('game');
    const format = url.searchParams.get('format');
    const year = url.searchParams.get('year');
    const [summary, games, years, tournaments, dashboard] = await Promise.all([
      fetchSummary({ game, format, year }),
      wants(url.searchParams.get('includeGames')) ? fetchGames() : Promise.resolve([]),
      fetchYears({ game, format }),
      fetchTournamentList({
        game,
        format,
        year,
        limit: url.searchParams.get('limit'),
      }),
      fetchDashboard({ game, format, year }),
    ]);
    res.setHeader('Cache-Control', 'public, max-age=30, s-maxage=180, stale-while-revalidate=300');
    return res.status(200).json({
      summary,
      games,
      years,
      tournaments,
      dashboard,
    });
  } catch (error) {
    console.error('marketplace-competitive failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace competitive data failed.',
    });
  }
};

module.exports.cleanLimit = cleanLimit;
module.exports.cleanTournamentId = cleanTournamentId;
module.exports.fetchGames = fetchGames;
module.exports.fetchDashboard = fetchDashboard;
module.exports.fetchDeckDetail = fetchDeckDetail;
module.exports.fetchSummary = fetchSummary;
module.exports.fetchTopDecks = fetchTopDecks;
module.exports.fetchPublicTopDecks = fetchPublicTopDecks;
module.exports.fetchTournamentList = fetchTournamentList;
module.exports.fetchTournamentGroup = fetchTournamentGroup;
module.exports.fetchPublicTournamentGroup = fetchPublicTournamentGroup;
module.exports.fetchTournamentSnapshot = fetchTournamentSnapshot;
module.exports.fetchPublicTournamentSnapshot = fetchPublicTournamentSnapshot;
module.exports.fetchYears = fetchYears;
module.exports.formatLabel = formatLabel;
