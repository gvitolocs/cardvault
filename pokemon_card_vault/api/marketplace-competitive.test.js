const assert = require('node:assert/strict');
const test = require('node:test');

const {
  cleanLimit,
  cleanTournamentId,
  fetchDashboard,
  fetchDeckDetail,
  fetchPublicTournamentGroup,
  fetchSummary,
  fetchTopDecks,
  fetchTournamentList,
  fetchTournamentSnapshot,
  fetchPublicTournamentSnapshot,
  fetchYears,
} = require('./marketplace-competitive');

test('competitive limit sanitizer keeps defaults for absent values', () => {
  assert.equal(cleanLimit(null, 24, 80), 24);
  assert.equal(cleanLimit('', 24, 80), 24);
  assert.equal(cleanLimit('0', 24, 80), 1);
});

test('marketplace competitive list maps tournament rows', async () => {
  const queries = [];
  const tournaments = await fetchTournamentList({
    game: 'ptcg',
    limit: 10,
    query: async (sql, values) => {
      queries.push({ sql, values });
      return {
        rows: [
          {
            tournament_id: 'abc123',
            name: 'Rare Candy Showdown',
            game_id: 'PTCG',
            game_name: 'Pokemon TCG',
            format: 'STANDARD',
            format_label: 'Standard',
            tournament_date: '2026-05-25T00:00:00.000Z',
            player_count: 140,
            organizer_name: 'Rare Candy Club',
            decklists_available: true,
            is_online: true,
            phases: [{ phase: 1, type: 'SWISS' }],
            standings_fetched_at: '2026-05-25T01:00:00.000Z',
            pairings_fetched_at: '2026-05-25T01:00:00.000Z',
          },
        ],
      };
    },
  });

  assert.match(queries[0].sql, /limitless_tournaments/);
  assert.deepEqual(queries[0].values, ['PTCG', 10]);
  assert.equal(tournaments[0].id, 'abc123');
  assert.equal(tournaments[0].gameName, 'Pokemon TCG');
  assert.equal(tournaments[0].decklistsAvailable, true);
});

test('marketplace competitive detail fetches standings and pairings', async () => {
  const snapshot = await fetchTournamentSnapshot({
    tournamentId: 'abc123',
    query: async (sql) => {
      if (/from public\.limitless_tournaments/.test(sql)) {
        return {
          rows: [
            {
              tournament_id: 'abc123',
              name: 'Rare Candy Showdown',
              game_id: 'PTCG',
              game_name: 'Pokemon TCG',
              format: 'STANDARD',
              format_label: 'Standard',
              player_count: 2,
              phases: [],
            },
          ],
        };
      }
      if (/from public\.limitless_tournament_standings/.test(sql)) {
        return {
          rows: [
            {
              placing: 1,
              player_id: 'p1',
              display_name: 'Player One',
              wins: 1,
              losses: 0,
              ties: 0,
              deck_archetype: 'Charizard',
            },
          ],
        };
      }
      if (/from public\.limitless_tournament_pairings/.test(sql)) {
        return {
          rows: [
            {
              phase: 1,
              round: 1,
              table_number: 1,
              player1_id: 'p1',
              player1_name: 'Player One',
              player2_id: 'p2',
              player2_name: 'Player Two',
              winner_player_id: 'p1',
            },
          ],
        };
      }
      throw new Error(`unexpected query: ${sql}`);
    },
  });

  assert.equal(snapshot.tournament.id, 'abc123');
  assert.equal(snapshot.standings[0].deckArchetype, 'Charizard');
  assert.equal(snapshot.pairings[0].player2Name, 'Player Two');
});

test('competitive dashboard groups archetypes and tournament columns', async () => {
  const calls = [];
  const dashboard = await fetchDashboard({
    game: 'PTCG',
    format: 'STANDARD',
    query: async (sql, values) => {
      calls.push({ sql, values });
      if (/with filtered/.test(sql)) {
        return {
          rows: [
            {
              archetype: 'Charizard',
              game_id: 'PTCG',
              format: 'STANDARD',
              format_label: 'Standard',
              deck_count: 5,
              share: '62.5',
              featured_player: 'Player One',
              featured_placing: 1,
              featured_wins: 7,
              featured_losses: 1,
              featured_ties: 0,
              featured_tournament_id: 'top123',
              featured_tournament_name: 'Rare Candy Showdown',
              featured_tournament_date: '2026-05-25T00:00:00.000Z',
              featured_decklist_id: 'deck123',
              representative_card_id: '12345',
              representative_card_name: 'Charizard ex',
              representative_card_set_name: 'Obsidian Flames',
              representative_card_number: '125/197',
              representative_card_path:
                '/marketplace/en/cards/12345/charizard-ex',
              representative_image_url:
                'https://cdn.pokoin.com/cards/charizard.webp',
            },
          ],
        };
      }
      if (/limitless_public_decks/.test(sql)) {
        const error = new Error('relation "public.limitless_public_decks" does not exist');
        error.code = '42P01';
        throw error;
      }
      if (/limitless_public_tournaments/.test(sql)) {
        const error = new Error('relation "public.limitless_public_tournaments" does not exist');
        error.code = '42P01';
        throw error;
      }
      if (/from public\.limitless_tournaments/.test(sql)) {
        return {
          rows: [
            {
              tournament_id: 'abc123',
              name: 'Rare Candy Showdown',
              game_id: 'PTCG',
              game_name: 'Pokemon TCG',
              format: 'STANDARD',
              format_label: 'Standard',
              tournament_date: '2026-05-25T00:00:00.000Z',
              player_count: 140,
              is_online: false,
              phases: [],
            },
          ],
        };
      }
      throw new Error(`unexpected query: ${sql}`);
    },
  });

  assert.equal(dashboard.topDecks[0].archetype, 'Charizard');
  assert.equal(dashboard.topDecks[0].share, 62.5);
  assert.equal(dashboard.topDecks[0].featuredTournamentId, 'top123');
  assert.equal(dashboard.topDecks[0].representativeCardName, 'Charizard ex');
  assert.equal(
    dashboard.topDecks[0].cardImageUrl,
    'https://cdn.pokoin.com/cards/charizard.webp',
  );
  assert.equal(dashboard.recentTournaments[0].id, 'abc123');
  assert.equal(dashboard.upcomingTournaments[0].id, 'abc123');
  assert.equal(dashboard.cityLeagues[0].id, 'abc123');
  assert.deepEqual(calls.find((call) => /with filtered/.test(call.sql)).values, [
    'PTCG',
    'STANDARD',
    8,
  ]);
});

test('competitive top decks prefers public Limitless metagame rows', async () => {
  const decks = await fetchTopDecks({
    query: async (sql, values) => {
      assert.match(sql, /limitless_public_decks/);
      assert.deepEqual(values, [8]);
      return {
        rows: [
          {
            deck_id: '284',
            archetype: 'Dragapult ex',
            points: 2648,
            deck_count: 2648,
            share: '41.74',
            featured_player: 'Francisco Osorio',
            featured_placing: 2,
            featured_tournament_id: '544',
          },
        ],
      };
    },
  });

  assert.equal(decks[0].deckId, '284');
  assert.equal(decks[0].archetype, 'Dragapult ex');
  assert.equal(decks[0].points, 2648);
  assert.equal(decks[0].featuredTournamentId, '544');
});

test('competitive recent tournaments can read public Limitless database rows', async () => {
  const tournaments = await fetchPublicTournamentGroup({
    format: 'STANDARD',
    query: async (sql, values) => {
      assert.match(sql, /limitless_public_tournaments/);
      assert.deepEqual(values, ['STANDARD', 8]);
      return {
        rows: [
          {
            tournament_id: '544',
            name: 'Regional Campinas',
            format: 'STANDARD',
            format_label: 'Standard',
            tournament_date: '2026-05-16',
            player_count: 1725,
            winner_name: 'Matias Matricardi',
          },
        ],
      };
    },
  });

  assert.equal(tournaments[0].id, '544');
  assert.equal(tournaments[0].platform, 'Limitless');
  assert.equal(tournaments[0].winnerName, 'Matias Matricardi');
});

test('competitive tournament detail falls back to public Limitless standings', async () => {
  const snapshot = await fetchPublicTournamentSnapshot({
    tournamentId: '544',
    query: async (sql, values) => {
      if (/from public\.limitless_public_tournaments/.test(sql)) {
        assert.deepEqual(values, ['544']);
        return {
          rows: [
            {
              tournament_id: '544',
              name: 'Regional Campinas',
              format: 'STANDARD',
              format_label: 'Standard',
              tournament_date: '2026-05-16',
              player_count: 1725,
              winner_name: 'Matias Matricardi',
            },
          ],
        };
      }
      if (/from public\.limitless_public_tournament_standings/.test(sql)) {
        assert.deepEqual(values, ['544', 80]);
        return {
          rows: [
            {
              placing: 1,
              player_id: '6816',
              player_name: 'Nathan O.',
              country: 'US',
              deck_id: '284',
              deck_name: 'Dragapult ex',
              variant: 'Dragapult Dusknoir',
              decklist_id: '27143',
            },
          ],
        };
      }
      throw new Error(`unexpected query: ${sql}`);
    },
  });

  assert.equal(snapshot.tournament.id, '544');
  assert.equal(snapshot.tournament.platform, 'Limitless');
  assert.equal(snapshot.standings[0].name, 'Nathan O.');
  assert.equal(snapshot.standings[0].deckArchetype, 'Dragapult Dusknoir');
  assert.deepEqual(snapshot.pairings, []);
});

test('competitive deck detail maps public cards, results, players, and decklists', async () => {
  const detail = await fetchDeckDetail({
    deckId: '284',
    query: async (sql) => {
      if (/from public\.limitless_public_decks/.test(sql)) {
        return {
          rows: [
            {
              deck_id: '284',
              name: 'Dragapult',
              points: 2648,
              share: '41.74',
              variants: ['Dragapult Dusknoir'],
            },
          ],
        };
      }
      if (/from public\.limitless_public_deck_core_cards/.test(sql)) {
        return {
          rows: [
            {
              display_name: 'Dragapult ex',
              count: '3',
              inclusion_share: '99.81',
              set_code: 'TWM',
              collector_number: '130',
            },
          ],
        };
      }
      if (/from public\.limitless_public_deck_results/.test(sql)) {
        return {
          rows: [
            {
              tournament_id: '544',
              tournament_name: 'Regional Campinas',
              placing: 2,
              player_name: 'Francisco Osorio',
              decklist_id: '27143',
            },
          ],
        };
      }
      if (/from public\.limitless_public_deck_players/.test(sql)) {
        return {
          rows: [
            {
              player_id: '6816',
              player_name: 'Nathan O.',
              rank: 1,
              points: 204,
            },
          ],
        };
      }
      if (/from public\.limitless_public_decklist_cards/.test(sql)) {
        return {
          rows: [
            {
              decklist_id: '27143',
              card_name: 'Dreepy',
              count: '4',
              section: 'pokémon',
              set_code: 'TWM',
              collector_number: '128',
            },
          ],
        };
      }
      throw new Error(`unexpected query: ${sql}`);
    },
  });

  assert.equal(detail.deck.id, '284');
  assert.equal(detail.coreCards[0].name, 'Dragapult ex');
  assert.equal(detail.results[0].decklistId, '27143');
  assert.equal(detail.players[0].playerName, 'Nathan O.');
  assert.equal(detail.decklists[0].cards[0].cardName, undefined);
  assert.equal(detail.decklists[0].cards[0].name, 'Dreepy');
});

test('competitive top decks sanitizes limit and preserves featured record', async () => {
  const decks = await fetchTopDecks({
    limit: 999,
    query: async (_sql, values) => {
      assert.deepEqual(values, [24]);
      return {
        rows: [
          {
            archetype: 'Gardevoir',
            deck_count: 2,
            share: '20.0',
            featured_wins: 6,
            featured_losses: 2,
            featured_ties: 1,
          },
        ],
      };
    },
  });

  assert.equal(decks[0].count, 2);
  assert.deepEqual(decks[0].featuredRecord, { wins: 6, losses: 2, ties: 1 });
});

test('competitive top decks cleans object decklist ids', async () => {
  const decks = await fetchTopDecks({
    query: async () => ({
      rows: [
        {
          archetype: 'Mega Greninja',
          deck_count: 1,
          featured_decklist_id: '[object Object]',
        },
      ],
    }),
  });

  assert.equal(decks[0].featuredDecklistId, '');
});

test('competitive top decks joins representative Pokoin card imagery', async () => {
  const decks = await fetchTopDecks({
    game: 'PTCG',
    format: 'STANDARD',
    year: 2026,
    query: async (sql, values) => {
      if (/limitless_public_decks/.test(sql)) {
        const error = new Error('relation "public.limitless_public_decks" does not exist');
        error.code = '42P01';
        throw error;
      }
      assert.match(sql, /marketplace_search_candidates/);
      assert.match(sql, /marketplace_card_urls/);
      assert.match(sql, /significant\.tokens/);
      assert.deepEqual(values, ['PTCG', 'STANDARD', 2026, 2027, 8]);
      return {
        rows: [
          {
            archetype: 'Mega Greninja',
            deck_count: 3,
            share: '33.3',
            representative_card_id: 98765,
            representative_card_name: 'Mega Greninja ex',
            representative_card_set_name: 'Mega Evolution',
            representative_card_number: '12/100',
            representative_card_path:
              '/marketplace/en/cards/98765/mega-greninja-ex',
            representative_image_url:
              'https://cdn.pokoin.com/cards/mega-greninja.webp',
          },
        ],
      };
    },
  });

  assert.equal(decks[0].representativeCardId, '98765');
  assert.equal(decks[0].representativeCardName, 'Mega Greninja ex');
  assert.equal(
    decks[0].imageUrl,
    'https://cdn.pokoin.com/cards/mega-greninja.webp',
  );
  assert.equal(
    decks[0].cardImageUrl,
    'https://cdn.pokoin.com/cards/mega-greninja.webp',
  );
});

test('competitive years uses tournament filters without year self-filter', async () => {
  const years = await fetchYears({
    game: 'ptcg',
    format: 'standard',
    query: async (sql, values) => {
      assert.match(sql, /extract\(year from t\.tournament_date\)/);
      assert.deepEqual(values, ['PTCG', 'STANDARD']);
      return { rows: [{ year: 2026 }, { year: 2025 }] };
    },
  });

  assert.deepEqual(years, [2026, 2025]);
});

test('competitive summary applies dashboard filters', async () => {
  const summary = await fetchSummary({
    game: 'ptcg',
    format: 'standard',
    year: 2026,
    query: async (sql, values) => {
      assert.match(sql, /from public\.limitless_tournaments t/);
      assert.match(sql, /t\.game_id = \$1/);
      assert.match(sql, /upper\(t\.format\) = \$2/);
      assert.deepEqual(values, ['PTCG', 'STANDARD', 2026, 2027]);
      return {
        rows: [
          {
            tournament_count: 4,
            total_players: 256,
            standings_count: 3,
            pairings_count: 2,
          },
        ],
      };
    },
  });

  assert.equal(summary.tournamentCount, 4);
  assert.equal(summary.totalPlayers, 256);
  assert.equal(summary.tournamentsWithStandings, 3);
  assert.equal(summary.tournamentsWithPairings, 2);
});

test('competitive tournament id sanitizer removes unsafe characters', () => {
  assert.equal(cleanTournamentId(' abc-123;drop '), 'abc-123drop');
});
