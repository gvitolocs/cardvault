import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/service/marketplace_home_selection_service.dart';

void main() {
  test('expansion dates and catalog fallback are preserved without fake dates',
      () {
    MarketplaceExpansion expansion(String name, {DateTime? date}) =>
        MarketplaceExpansion(
            name: name, slug: name, cardCount: 1, releaseDate: date);
    final dated = MarketplaceHomeSelectionService.recentExpansions([
      expansion('Old', date: DateTime(2020)),
      expansion('New', date: DateTime(2026)),
    ]);
    expect(dated.first.name, 'New');
    final fallback = MarketplaceHomeSelectionService.recentExpansions(
        [expansion('A'), expansion('B')],
        catalogOrder: {'A': 1, 'B': 2});
    expect(fallback.first.name, 'B');
    expect(fallback.every((set) => set.releaseDate == null), isTrue);
    expect(MarketplaceHomeSelectionService.recentExpansions(fallback, limit: 0),
        isEmpty);
  });

  test('ranked cards are capped at twelve and metadata stays unmodified', () {
    final cards = List.generate(
        100,
        (index) => MarketplaceCardPreview(
            id: '$index', name: 'Carta $index', expansion: 'Set'));
    final result = MarketplaceHomeSelectionService.cardsForRankedIds(
        cards, List.generate(100, (index) => '${99 - index}'));
    expect(result, hasLength(12));
    expect(result.first.id, '99');
    expect(cards.first.id, '0');
  });
}
