import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/cart_add_result.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/marketplace/atomics/search_card_tile.dart';
import 'package:pokoin/rebuild/presentation/marketplace/component/top_sellers.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/card_best_deal.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/listing_details.dart';
import 'package:pokoin/rebuild/controller/card_details_controller.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'package:pokoin/rebuild/service/cart_service.dart';
import 'card_details_test.dart' as fixtures;
import 'fixtures/cart_fixtures.dart';

const preview = MarketplaceCardPreview(
    id: '24', name: 'Carta vera', expansion: 'Set', pricePkn: 999);

void main() {
  test(
      'quick add fetches live offers on demand, selects the cheapest and shares rapid taps',
      () async {
    var cards = 0, offers = 0;
    final service = CardService(client: MockClient((request) async {
      expect(request.url.queryParameters['cardId'], '24');
      if (request.url.path.endsWith('card-page')) {
        cards++;
        return fixtures.response({'card': fixtures.cardJson});
      }
      offers++;
      expect(request.url.queryParameters['limit'], '80');
      return fixtures.response({
        'listings': [
          fixtures.offerJson('expensive', price: 100),
          {
            ...fixtures.offerJson('cardtrader:live:123', price: 22, stock: 1),
            'sellerUid': 'seller',
            'source': 'cardtrader_live',
            'sourceListingId': '123'
          },
          fixtures.offerJson('wrong-card', cardId: '48', price: 1),
          fixtures.offerJson('sold-out', stock: 0, price: 1),
        ]
      });
    }));
    final cart = CartController(cards: service);
    addTearDown(service.dispose);
    addTearDown(cart.dispose);
    final first = cart.addCheapestOffer('24');
    final duplicate = cart.addCheapestOffer('24');
    expect(duplicate, same(first));
    expect(cart.adding('24').value, isTrue);
    expect((await first).status, CartAddStatus.added);
    expect(cart.adding('24').value, isFalse);
    expect(cart.listingItems.single.listing.id, 'cardtrader:live:123');
    expect(cart.totalPkn, 22); // Neither catalog 123.5 nor preview 999.
    expect(cart.listingItems.single.listing.sourceData['sellerUid'], 'seller');
    expect((await cart.addCheapestOffer('24')).status, CartAddStatus.full);
    expect(cart.itemCount, 1);
    expect(cards, 1);
    expect(offers, 2); // Availability is not cached between user actions.
  });

  test(
      'empty and failed listing responses never add an indicative catalog price',
      () async {
    var attempt = 0;
    final service = CardService(client: MockClient((request) async {
      if (request.url.path.endsWith('card-page')) {
        return fixtures.response({'card': fixtures.cardJson});
      }
      attempt++;
      if (attempt == 1) return fixtures.response({'listings': []});
      if (attempt == 2) return http.Response('unavailable', 503);
      return fixtures.response({
        'listings': [fixtures.offerJson('real')]
      });
    }));
    final cart = CartController(cards: service);
    addTearDown(service.dispose);
    addTearDown(cart.dispose);
    expect(
        (await cart.addCheapestOffer('24')).status, CartAddStatus.unavailable);
    expect(cart.itemCount, 0);
    expect((await cart.addCheapestOffer('24')).status, CartAddStatus.failed);
    expect(cart.itemCount, 0);
    expect((await cart.addCheapestOffer('24')).status, CartAddStatus.added);
    expect(cart.itemCount, 1);
  });

  test(
      'account changes cancel late additions and allow a new action for the same public card',
      () async {
    final replies = <Completer<http.Response>>[];
    final cards = CardService(client: MockClient((request) {
      if (request.url.path.endsWith('card-page')) {
        return Future.value(fixtures.response({'card': fixtures.cardJson}));
      }
      final reply = Completer<http.Response>();
      replies.add(reply);
      return reply.future;
    }));
    final service = CartService(local: MemoryCartLocal());
    final sessions = StreamController<String?>();
    final cart = CartController(service: service, cards: cards)
      ..start(userIds: sessions.stream);
    addTearDown(cards.dispose);
    addTearDown(service.dispose);
    addTearDown(cart.dispose);
    addTearDown(sessions.close);
    sessions.add('alice');
    await settleCart(service);
    final old = cart.addCheapestOffer('24');
    await Future<void>.delayed(Duration.zero);
    sessions.add('bob');
    await settleCart(service);
    final next = cart.addCheapestOffer('24');
    replies.single.complete(fixtures.response({
      'listings': [fixtures.offerJson('real')]
    }));
    expect((await old).status, CartAddStatus.sessionChanged);
    expect((await next).status, CartAddStatus.added);
    await settleCart(service);
    expect(cart.itemCount, 1);
  });

  test('disposing during a listing request ignores its response', () async {
    final reply = Completer<http.Response>();
    final service = CardService(
        client: MockClient((request) => request.url.path.endsWith('card-page')
            ? Future.value(fixtures.response({'card': fixtures.cardJson}))
            : reply.future));
    final cartService = CartService();
    final cart = CartController(service: cartService, cards: service);
    addTearDown(service.dispose);
    addTearDown(cartService.dispose);
    final pending = cart.addCheapestOffer('24');
    cart.dispose();
    reply.complete(fixtures.response({
      'listings': [fixtures.offerJson('real')]
    }));
    expect((await pending).status, CartAddStatus.sessionChanged);
    expect(cartService.itemCount, 0);
  });

  testWidgets(
      'search tile action is left of price and adds a live offer without opening details',
      (tester) async {
    var calls = 0, opened = 0;
    final cards = CardService(client: MockClient((request) async {
      calls++;
      return fixtures.response(request.url.path.endsWith('card-page')
          ? {'card': fixtures.cardJson}
          : {
              'listings': [fixtures.offerJson('live', price: 22)]
            });
    }));
    final cart = CartController(cards: cards);
    addTearDown(cards.dispose);
    addTearDown(cart.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 200,
                    child: SearchCardTile(
                        card: preview, cart: cart, onOpen: () => opened++))))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    final add = find.byTooltip('Aggiungi al carrello · offerta più economica');
    expect(tester.getCenter(add).dx,
        lessThan(tester.getCenter(find.text('999,00 PKN')).dx));
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(calls, 2);
    expect(cart.totalPkn, 22);
    expect(find.textContaining('22,00 PKN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'top seller prices and actions fit a small phone at enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final cart = CartController();
    addTearDown(cart.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TopSellers(cards: const [
      MarketplaceCardPreview(
          id: '24',
          name: 'Una carta con nome molto lungo',
          expansion: 'Espansione lunga')
    ], cart: cart, onSelected: (_) {})))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aggiungi al carrello · offerta più economica'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'details show retry and empty states without falling back to demo offers',
      (tester) async {
    var listingCalls = 0, infoCalls = 0;
    final service = CardService(client: MockClient((request) async {
      if (request.url.path.endsWith('card-page')) {
        infoCalls++;
        return fixtures.response({'card': fixtures.cardJson});
      }
      listingCalls++;
      return listingCalls == 1
          ? http.Response('unavailable', 503)
          : fixtures.response({'listings': []});
    }));
    final cart = CartController();
    addTearDown(service.dispose);
    addTearDown(cart.dispose);
    final controller = CardDetailsController(cardId: '24', service: service);
    await tester.pumpWidget(MaterialApp(
        home:
            CardDetails(preview: preview, controller: controller, cart: cart)));
    await tester.pumpAndSettle();
    final retry = find.text('Riprova offerte').first;
    await tester.scrollUntilVisible(retry.hitTestable(), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(retry.hitTestable());
    await tester.pumpAndSettle();
    expect(controller.listings.value.hasError, isFalse);
    expect(controller.listings.value.loading, isFalse);
    expect(listingCalls, 2);
    await tester.scrollUntilVisible(find.byType(CardBestDeal), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('redshakkio'), findsNothing);
    expect(find.text('Offerta dimostrativa'), findsNothing);
    expect(find.text('Nessuna inserzione disponibile per i filtri scelti.'),
        findsWidgets);
    expect(listingCalls, 2);
    expect(infoCalls, 1);
    expect(cart.itemCount, 0);
  });

  testWidgets(
      'best deal and shop share filters and add exactly the selected real offer',
      (tester) async {
    final service = CardService(
        client: MockClient((request) async =>
            fixtures.response(request.url.path.endsWith('card-page')
                ? {'card': fixtures.cardJson}
                : {
                    'listings': [
                      fixtures.offerJson('cheap-it', price: 22, language: 'IT'),
                      fixtures.offerJson('english', price: 50, language: 'EN'),
                    ]
                  })));
    final controller = CardDetailsController(cardId: '24', service: service);
    final cart = CartController();
    addTearDown(service.dispose);
    addTearDown(cart.dispose);
    await tester.pumpWidget(MaterialApp(
        home:
            CardDetails(preview: preview, controller: controller, cart: cart)));
    await tester.pumpAndSettle();
    controller.filter(language: 'EN');
    await tester.pumpAndSettle();
    final best = find.byType(CardBestDeal);
    await tester.scrollUntilVisible(best, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<CardBestDeal>(best).state.bestOffer!.id, 'english');
    final add = find.descendant(
        of: best, matching: find.byTooltip('Aggiungi al carrello'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(cart.listingItems.single.listing.id, 'english');
    expect(cart.totalPkn, 50);
    await tester.scrollUntilVisible(find.text('Shop'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListingDetails>(find.byType(ListingDetails))
            .state
            .language,
        'EN');
    expect(tester.takeException(), isNull);
  });
}
