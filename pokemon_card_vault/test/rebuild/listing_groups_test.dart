import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/controller/card_details_controller.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/listing.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/listing_details.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/listing_origin_group.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/listing_row.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'card_details_test.dart' as fixtures;

Map<String, dynamic> offer(String id, double price,
        {String? source,
        String condition = 'NM',
        String language = 'IT',
        Map<String, dynamic>? metadata}) =>
    {
      ...fixtures.offerJson(id,
          price: price, stock: 5, condition: condition, language: language),
      if (source != null) 'source': source,
      if (metadata != null) 'sourceMetadata': metadata,
      'sellerName': 'pknreserve',
    };

List<Map<String, dynamic>> manyOffers() => [
      for (var index = 11; index >= 0; index--)
        offer('ct-$index', 10 + index.toDouble(),
            source: 'cardtrader_live',
            condition: index.isEven ? 'NM' : 'Poor',
            language: index < 6 ? 'IT' : 'EN'),
      for (var index = 0; index < 6; index++)
        offer('reserve-$index', 40 + index.toDouble(),
            condition: 'NM', language: 'EN'),
    ];

void main() {
  test(
      'origins use source/provider/id metadata instead of the shared reserve seller name',
      () {
    for (final row in [
      offer('a', 10, source: 'cardtrader_live'),
      offer('b', 10, metadata: {'provider': 'CardTrader'}),
      offer('cardtrader:live:123', 10),
      {...offer('c', 10), 'sourceListingId': 'cardtrader:456'},
    ]) {
      final listing = MarketplaceListing.fromJson(row);
      expect(listing.origin.id, 'cardtrader');
      expect(listing.origin.label, 'CardTrader');
      expect(listing.sellerName, 'pknreserve');
      expect(listing.toJson()['sourceMetadata'], row['sourceMetadata']);
    }
    expect(
        MarketplaceListing.fromJson(
                offer('native', 10, source: 'pokoin_user_listing'))
            .origin
            .label,
        'Pokoin');
    expect(
        MarketplaceListing.fromJson(
                offer('reserve', 10, source: 'pokoin_reserve'))
            .origin
            .label,
        'CardReserve');
    expect(MarketplaceListing.fromJson(offer('unknown', 10)).origin.label,
        'CardReserve');
    expect(
        MarketplaceListing.fromJson(
                offer('external', 10, metadata: {'provider': 'OtherMarket'}))
            .origin
            .label,
        'OtherMarket');
  });

  test(
      'cheapest groups reveal four at a time independently, without additional HTTP',
      () async {
    var requests = 0;
    final service = CardService(client: MockClient((request) async {
      requests++;
      return fixtures.response(request.url.path.endsWith('card-page')
          ? {'card': fixtures.cardJson}
          : {'listings': manyOffers()});
    }));
    final controller = CardDetailsController(cardId: '24', service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    await controller.load();
    var groups = controller.listings.value.groups;
    expect(groups.map((group) => group.origin.label),
        ['CardTrader', 'CardReserve']);
    expect(groups.first.shown.map((row) => row.pricePkn), [10, 11, 12, 13]);
    expect(groups.first.offers, hasLength(12));
    expect(groups.last.shown, hasLength(4));
    final oldState = controller.listings.value;
    controller.loadMoreListings('cardtrader');
    expect(controller.listings.value.groups.first.shown, hasLength(8));
    expect(controller.listings.value.groups.last.shown, hasLength(4));
    expect(oldState.groups.first.shown, hasLength(4));
    controller.loadMoreListings('cardreserve');
    expect(controller.listings.value.groups.last.shown, hasLength(6));
    expect(controller.listings.value.groups.last.hasMore, isFalse);
    controller.toggleListingGroup('cardtrader');
    expect(controller.listings.value.groups.first.expanded, isFalse);
    controller.toggleListingGroup('cardtrader');
    expect(controller.listings.value.groups.first.expanded, isTrue);
    expect(controller.listings.value.groups.first.shown, hasLength(8));
    controller.loadMoreListings('cardtrader');
    controller.loadMoreListings('cardtrader');
    expect(controller.listings.value.groups.first.shown, hasLength(12));
    expect(controller.listings.value.bestOffer!.id, 'ct-0');
    expect(requests, 2);
  });

  test(
      'filter and sort changes reset group pages and keep the best offer independent of pagination',
      () async {
    final service = CardService(
        client: MockClient((request) async => fixtures.response(
            request.url.path.endsWith('card-page')
                ? {'card': fixtures.cardJson}
                : {'listings': manyOffers()})));
    final controller = CardDetailsController(cardId: '24', service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    await controller.load();
    controller.loadMoreListings('cardtrader');
    controller.toggleListingGroup('cardreserve');
    controller.filter(language: 'EN');
    expect(controller.listings.value.groups.first.shown, hasLength(4));
    expect(controller.listings.value.groups.last.expanded, isTrue);
    expect(controller.listings.value.bestOffer!.id, 'ct-6');
    controller.filter(condition: 'Poor', language: 'EN');
    expect(controller.listings.value.groups, hasLength(1));
    expect(controller.listings.value.groups.single.shown.map((row) => row.id),
        ['ct-7', 'ct-9', 'ct-11']);
    controller.filter(sort: ListingSort.highestPrice);
    expect(controller.listings.value.groups.first.shown.first.pricePkn, 45);
    expect(controller.listings.value.bestOffer!.pricePkn, 10);
    controller.filter(language: 'not-present');
    expect(controller.listings.value.groups, isEmpty);
    controller.loadMoreListings('missing');
    controller.toggleListingGroup('missing');
    expect(controller.listings.value.groups, isEmpty);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
        'groups and condition/language buttons fit ${width}px at enlarged text',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var requests = 0;
      final service = CardService(client: MockClient((request) async {
        requests++;
        return fixtures.response(request.url.path.endsWith('card-page')
            ? {'card': fixtures.cardJson}
            : {'listings': manyOffers()});
      }));
      final controller = CardDetailsController(cardId: '24', service: service);
      final cart = CartController();
      addTearDown(service.dispose);
      addTearDown(controller.dispose);
      addTearDown(cart.dispose);
      await controller.load();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CustomScrollView(slivers: [
        ValueListenableBuilder<ListingsState>(
            valueListenable: controller.listings,
            builder: (context, state, _) => ListingDetails(
                state: state,
                card: controller.info.value.card,
                cart: cart,
                onFilter: controller.filter,
                onRetry: controller.retryListings,
                onLoadMore: controller.loadMoreListings,
                onToggleGroup: controller.toggleListingGroup)),
      ]))));
      await tester.pumpAndSettle();
      Future<void> scrollTo(Finder finder, double step) async {
        await tester.scrollUntilVisible(finder.hitTestable(), step,
            scrollable: find.byType(Scrollable).first, maxScrolls: 80);
        await tester.pumpAndSettle();
      }

      final more = find.descendant(
          of: find.byKey(const ValueKey('listing-group:cardtrader')),
          matching: find.text('Mostra altre 4'));
      await scrollTo(more, 250);
      expect(
          find.byWidgetPredicate(
              (widget) => widget is ListingRow && widget.listing.id == 'ct-4'),
          findsNothing);
      await tester.tap(more.hitTestable());
      await tester.pumpAndSettle();
      expect(controller.listings.value.groups.first.shown, hasLength(8));
      await scrollTo(find.text('CardTrader'), -250);
      await tester.tap(find.text('CardTrader'));
      await tester.pumpAndSettle();
      final group = find.byWidgetPredicate((widget) =>
          widget is ListingOriginGroup &&
          widget.group.origin.id == 'cardtrader');
      expect(find.descendant(of: group, matching: find.byType(ListingRow)),
          findsNothing);
      await scrollTo(find.text('Condizioni: tutte'), -250);
      await tester.tap(find.text('Condizioni: tutte'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'NM'));
      await tester.pumpAndSettle();
      expect(controller.listings.value.condition, 'NM');
      expect(controller.listings.value.groups.first.shown, hasLength(4));
      expect(controller.listings.value.groups.first.expanded, isTrue);
      await scrollTo(find.text('Lingua: tutte'), -250);
      await tester.tap(find.text('Lingua: tutte'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'EN'));
      await tester.pumpAndSettle();
      expect(controller.listings.value.language, 'EN');
      expect(
          controller.listings.value.visible
              .every((row) => row.language == 'EN' && row.condition == 'NM'),
          isTrue);
      expect(controller.listings.value.bestOffer!.id, 'ct-6');
      expect(requests, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
