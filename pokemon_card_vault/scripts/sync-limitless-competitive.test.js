const assert = require('node:assert/strict');
const test = require('node:test');

const {
  decklistId,
  normalizePairing,
  normalizeStanding,
  normalizeTournament,
  parseDeckOverview,
  parseArgs,
  parsePublicDecklistCards,
  parsePublicDecks,
  parsePublicTournaments,
  run,
} = require('./sync-limitless-competitive');

test('parseArgs defaults to safe dry-run and accepts filters', () => {
  const options = parseArgs([
    '--game=ptcg',
    '--max-tournaments=25',
    '--request-delay-ms=0',
    '--skip-pairings',
    '--tournament-id=abc123',
  ]);

  assert.equal(options.dryRun, true);
  assert.deepEqual(options.games, ['PTCG']);
  assert.deepEqual(options.tournamentIds, ['abc123']);
  assert.equal(options.maxTournaments, 25);
  assert.equal(options.includePairings, false);
});

test('parseArgs enables bounded public Limitless imports by default', () => {
  const options = parseArgs([
    '--skip-public',
    '--public-deck-limit=3',
    '--public-tournament-limit=4',
    '--public-decklist-limit=2',
  ]);

  assert.equal(options.includePublic, false);
  assert.equal(options.publicDeckLimit, 3);
  assert.equal(options.publicTournamentLimit, 4);
  assert.equal(options.publicDecklistLimit, 2);
});

test('normalizers preserve Limitless tournament standing and pairing fields', () => {
  const tournament = normalizeTournament({
    id: 'abc123',
    game: 'PTCG',
    name: 'Rare Candy Showdown',
    date: '2026-05-25T00:00:00.000Z',
    format: 'STANDARD',
    players: 140,
    organizer: { id: 2518, name: 'Rare Candy Club' },
    decklists: true,
    phases: [{ phase: 1, type: 'SWISS' }],
  });
  const standing = normalizeStanding('abc123', {
    name: 'Player One',
    country: 'IT',
    player: 'p1',
    placing: 1,
    record: { wins: 7, losses: 0, ties: 0 },
    decklist: 'deck123',
    deck: { archetype: 'Charizard' },
  });
  const pairing = normalizePairing('abc123', {
    round: 1,
    phase: 1,
    table: 2,
    player1: 'p1',
    player2: 'p2',
    winner: 'p1',
  }, 0);

  assert.equal(tournament.organizer_name, 'Rare Candy Club');
  assert.equal(tournament.decklists_available, true);
  assert.equal(standing.deck_archetype, 'Charizard');
  assert.equal(standing.decklist_id, 'deck123');
  assert.equal(pairing.table_number, 2);
  assert.equal(decklistId('abc123', { player: 'p1' }), 'abc123:p1');
});

test('dry-run fetches public endpoints without opening a database', async () => {
  const calls = [];
  const result = await run(
    parseArgs(['--dry-run', '--max-tournaments=1', '--request-delay-ms=0']),
    {
      client: {
        async get(apiPath) {
          calls.push(apiPath);
          if (apiPath === '/games') return [{ id: 'PTCG', name: 'Pokemon TCG' }];
          if (apiPath === '/tournaments') {
            return [{ id: 'abc123', game: 'PTCG', name: 'Rare Candy', players: 2 }];
          }
          if (apiPath.endsWith('/details')) {
            return { id: 'abc123', game: 'PTCG', name: 'Rare Candy', players: 2 };
          }
          if (apiPath.endsWith('/standings')) return [];
          if (apiPath.endsWith('/pairings')) return [];
          throw new Error(`unexpected ${apiPath}`);
        },
      },
    },
  );

  assert.equal(result.mode, 'dry-run');
  assert.equal(result.tournamentsSeen, 1);
  assert.equal(result.detailsFetched, 1);
  assert.deepEqual(calls, [
    '/games',
    '/tournaments',
    '/tournaments/abc123/details',
    '/tournaments/abc123/standings',
    '/tournaments/abc123/pairings',
  ]);
});

test('public Limitless parsers extract decks, tournaments, and deck detail rows', () => {
  const decks = parsePublicDecks(`
    <table><tr><th>#</th><th></th><th>Deck</th><th>Points</th><th>Share</th></tr>
    <tr><td>1</td><td></td><td><a href="/decks/284">Dragapult <span>ex</span></a></td><td>2648</td><td>41.74%</td></tr></table>
  `);
  const tournaments = parsePublicTournaments(`
    <table><tr><th>Date</th><th>Country</th><th>Name</th><th></th><th>Players</th><th>Winner</th></tr>
    <tr data-date="2026-05-16" data-country="BR" data-format="standard" data-players="1725">
      <td>16 May 26</td><td><img alt="BR" data-tooltip="Brazil"></td>
      <td><a href="/tournaments/544">Regional Campinas</a></td>
      <td><img alt="standard" data-tooltip="Standard"></td><td>1725</td>
      <td><img alt="AR"><a href="/players/1198">Matias Matricardi</a></td>
    </tr></table>
  `);
  const detail = parseDeckOverview(`
    <h1>Dragapult</h1>
    Totals: 1,342,250$ | 17959 Points
    Regional Top 8: 236, including 30 wins
    International Top 8: 37, including 3 wins
    <div class="core-card"><a href="/cards/TWM/130"><img alt="TWM #130" data-set="TWM" data-number="130"></a><span class="share">3 in 99.81%</span></div>
    <table>
      <tr><th></th><th>Place</th><th>Variant</th><th>Player</th><th>List</th></tr>
      <tr><th class="sub-heading" colspan=5><a href="/tournaments/544">16th May 2026 - Regional Campinas</a></th></tr>
      <tr><td><img alt="standard"></td><td>2nd</td><td><img class="pokemon" alt="dragapult"></td><td><a href="/players/790">Francisco Osorio</a></td><td><a href="/decks/list/27143"></a></td></tr>
    </table>
    <table><tr><th>#</th><th>Name</th><th>Country</th><th>Points</th></tr>
      <tr><td>1</td><td><a href="/players/6816">Nathan O.</a></td><td><img alt="US"></td><td>204</td></tr>
    </table>
  `, '284');

  assert.equal(decks[0].deck_id, '284');
  assert.equal(decks[0].share, 41.74);
  assert.equal(tournaments[0].tournament_id, '544');
  assert.equal(tournaments[0].format, 'STANDARD');
  assert.equal(detail.deck.total_points, 17959);
  assert.equal(detail.coreCards[0].card_key, 'TWM:130');
  assert.equal(detail.results[0].decklist_id, '27143');
  assert.equal(detail.results[0].tournament_date, '2026-05-16');
  assert.equal(detail.players[0].points, 204);
});

test('public decklist parser extracts card sections and set metadata', () => {
  const cards = parsePublicDecklistCards(`
    <div class="decklist-column-heading">Pokémon (21)</div>
    <div class="decklist-card" data-set="TWM" data-number="128">
      <a class="card-link" href="/cards/TWM/128"><span class="card-count">4</span><span class="card-name">Dreepy</span></a>
    </div>
  `, '27143');

  assert.equal(cards[0].decklist_id, '27143');
  assert.equal(cards[0].card_name, 'Dreepy');
  assert.equal(cards[0].section, 'pokémon');
  assert.equal(cards[0].set_code, 'TWM');
});
