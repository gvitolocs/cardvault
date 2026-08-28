import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/providers/card_provider.dart';
import 'package:pokoin/widgets/pokoin_assistant.dart';

void main() {
  group('Pokontact internal links', () {
    test('accepts Pokoin absolute URLs as app routes', () {
      expect(
        internalAssistantPathFromUrlForTest(
          'https://pokoin.com/marketplace/en/cards/548832/mew-ex',
        ),
        '/marketplace/en/cards/548832/mew-ex',
      );
      expect(
        internalAssistantPathFromUrlForTest(
          'https://www.pokoin.com/marketplace/search?q=Drowzee%2010%2F198',
        ),
        '/marketplace/search?q=Drowzee%2010%2F198',
      );
    });

    test('accepts safe relative marketplace URLs', () {
      expect(
        internalAssistantPathFromUrlForTest(
            '/marketplace/en/cards/24690/drowzee'),
        '/marketplace/en/cards/24690/drowzee',
      );
    });

    test('rejects external and protocol-relative URLs', () {
      expect(
          internalAssistantPathFromUrlForTest(
              'https://example.com/marketplace'),
          isEmpty);
      expect(internalAssistantPathFromUrlForTest('//pokoin.com/marketplace'),
          isEmpty);
    });

    test('trims punctuation from clickable assistant links', () {
      expect(
        trimAssistantLinkForTest(
          'https://pokoin.com/marketplace/en/cards/548832/mew-ex.',
        ),
        'https://pokoin.com/marketplace/en/cards/548832/mew-ex',
      );
    });

    test('extracts safe navigation paths from API action variants', () {
      expect(
        assistantNavigationPathsFromActionsForTest([
          {
            'type': 'navigate',
            'data': {
              'canonicalPath':
                  '/marketplace/en/cards/548832/stored-mew-ex-path',
            },
          },
          {
            'type': 'open_url',
            'url': 'https://example.com/not-pokoin',
          },
        ]),
        ['/marketplace/en/cards/548832/stored-mew-ex-path'],
      );
      expect(
        assistantNavigationPathsFromActionsForTest([
          {
            'action': 'open',
            'url': 'https://pokoin.com/marketplace/search?q=Mew',
          },
        ]),
        isEmpty,
      );
    });

    test(
        'treats local assistant navigation current-page writes as one-shot echoes',
        () {
      resetAssistantNavigationReplayGuardForTest();
      final now = DateTime.utc(2026, 5, 24, 17, 0);
      const sessionId = 'flutter-12345678-1';
      const whirlpoolPath = '/marketplace/en/cards/123456/whirlpool-card-page';
      const leafeonPath = '/marketplace/en/cards/633200/leafeon';

      recordAssistantLocalNavigationForTest(
        sessionId: sessionId,
        path: whirlpoolPath,
        now: now,
      );

      expect(
        shouldIgnoreAssistantCurrentPageEchoForTest(
          sessionId: sessionId,
          path: whirlpoolPath,
          source: 'assistant-navigate',
          now: now.add(const Duration(seconds: 15)),
        ),
        isTrue,
      );
      expect(
        shouldIgnoreAssistantCurrentPageEchoForTest(
          sessionId: sessionId,
          path: leafeonPath,
          source: 'assistant-navigate',
          now: now.add(const Duration(seconds: 15)),
        ),
        isFalse,
      );
      expect(
        shouldIgnoreAssistantCurrentPageEchoForTest(
          sessionId: sessionId,
          path: whirlpoolPath,
          source: 'remote-assistant',
          now: now.add(const Duration(seconds: 15)),
        ),
        isFalse,
      );
      expect(
        shouldIgnoreAssistantCurrentPageEchoForTest(
          sessionId: sessionId,
          path: whirlpoolPath,
          source: 'assistant-navigate',
          now: now.add(const Duration(minutes: 3)),
        ),
        isFalse,
      );
    });

    test('builds structured current page context for marketplace search', () {
      final cardState = CardState(
        filteredCards: [
          _testCard(
            id: '248856',
            name: 'Magikarp',
            set: 'Paldea Evolved',
            number: '203/193',
            canonicalPath:
                '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
          ),
        ],
        searchQuery: 'Magikarp 203/193',
        selectedRarity: 'Illustration Rare',
        showOnlyInStock: true,
        searchLanguage: 'en',
      );

      final context = assistantPageContextForTest(
        Uri.parse(
          '/marketplace/search?q=Magikarp%20203%2F193&token=secret&productType=card',
        ),
        cardState: cardState,
      );

      expect(context['kind'], 'search');
      expect(context['internalUri'],
          '/marketplace/search?q=Magikarp+203%2F193&productType=card');
      expect(context['searchQuery'], 'Magikarp 203/193');
      expect(context['queryParameters'], isNot(contains('token')));
      expect(context['filters'], containsPair('rarity', 'Illustration Rare'));
      expect(context['filters'], containsPair('inStock', 'true'));
      expect(context['filters'], containsPair('productType', 'card'));
      final visibleCards = context['visibleCards'] as List<Map<String, String>>;
      expect(visibleCards, hasLength(1));
      expect(visibleCards.first['id'], '248856');
      expect(visibleCards.first['number'], '203/193');
    });

    test('builds active card and artist context from routes', () {
      final cardContext = assistantPageContextForTest(
        Uri.parse('/marketplace/en/cards/497712/card-magikarp-203-193'),
        cardState: CardState(
          cards: [
            _testCard(
              id: '248856',
              name: 'Magikarp',
              set: 'Paldea Evolved',
              number: '203/193',
              artist: 'Shinji Kanda',
            ),
          ],
        ),
      );
      expect(cardContext['kind'], 'card');
      expect(cardContext['cardId'], '248856');
      expect(cardContext['activeCard'], containsPair('name', 'Magikarp'));
      expect(cardContext['activeCard'], containsPair('artist', 'Shinji Kanda'));

      final artistContext = assistantPageContextForTest(
        Uri.parse('/marketplace/en/artists/shinji-kanda/profile'),
      );
      expect(artistContext['kind'], 'artist');
      expect(artistContext['artistSlug'], 'shinji-kanda');
      expect(artistContext['artist'], containsPair('name', 'Shinji Kanda'));
    });
  });
}

PokemonCard _testCard({
  required String id,
  required String name,
  String set = '',
  String number = '',
  String artist = '',
  String canonicalPath = '',
}) {
  return PokemonCard(
    id: id,
    name: name,
    imageUrl: '',
    rarity: 'Card',
    type: 'Pokemon',
    hp: 0,
    attacks: const [],
    price: 0,
    description: '',
    set: set,
    number: number,
    artist: artist,
    stock: 1,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2024),
    tags: const [],
    condition: 'NM',
    isGraded: false,
    canonicalPath: canonicalPath,
  );
}
