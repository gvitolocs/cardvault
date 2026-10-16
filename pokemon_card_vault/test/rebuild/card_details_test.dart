import 'dart:async';
import 'fixtures/account_fixtures.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/listing_details.dart';
import 'package:pokoin/rebuild/controller/card_details_controller.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/main_mobile_prototype.dart';
import 'package:pokoin/rebuild/model/card.dart';
import 'package:pokoin/rebuild/model/demo_catalog.dart';
import 'package:pokoin/rebuild/model/listing.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'package:pokoin/rebuild/service/marketplace_home_service.dart';
import 'marketplace_home_service_test.dart' as discovery;

const cardJson = <String, dynamic>{
  'id': '24',
  'name': 'Carta vera',
  'set': 'Set reale',
  'number': '12/100',
  'heroImageUrl': '',
  'price': 123.5,
  'artist': 'Illustratore',
  'rarityKind': 'gold',
};
Map<String, dynamic> offerJson(String id,
        {double price = 123.5,
        int stock = 2,
        String cardId = '24',
        String condition = 'NM',
        String language = 'IT',
        String status = 'active'}) =>
    {
      'id': id,
      'cardId': cardId,
      'sellerName': 'Venditore $id',
      'sellerCountry': 'IT',
      'condition': condition,
      'language': language,
      'pricePkn': price,
      'quantityAvailable': stock,
      'status': status,
    };
http.Response response(Object data) => http.Response(jsonEncode(data), 200);

void main() {
  test(
      'canonical card IDs and PKN pass unchanged; shared reads and bounded card cache',
      () async {
    var cardRequests = 0;
    var listingRequests = 0;
    final service = CardService(client: MockClient((request) async {
      expect(request.url.queryParameters['cardId'], '24');
      expect(request.url.queryParameters.containsKey('includeSales'), isFalse);
      if (request.url.path.endsWith('card-page')) {
        cardRequests++;
        return response({'card': cardJson});
      }
      listingRequests++;
      expect(request.url.queryParameters['limit'], '80');
      return response({
        'listings': [offerJson('a')]
      });
    }));
    addTearDown(service.dispose);
    final cards =
        await Future.wait([service.fetchCard('24'), service.fetchCard('24')]);
    expect(cards.first.id, '24');
    expect(cards.first.pricePkn, 123.5);
    await service.fetchCard('24');
    expect(cardRequests, 1);
    await Future.wait(
        [service.fetchListings('24'), service.fetchListings('24')]);
    expect(listingRequests, 1);
    await service.fetchListings('24');
    expect(listingRequests, 2); // re-opening validates stock with a new GET
  });

  test(
      'rejects wrong cards, duplicate and unavailable offers without using catalog price',
      () async {
    final service = CardService(
        client: MockClient((_) async => response({
              'listings': [
                offerJson('a'),
                offerJson('a'),
                offerJson('wrong', cardId: '48'),
                offerJson('empty', stock: 0),
                offerJson('inactive', status: 'inactive'),
                offerJson('free', price: 0),
              ]
            })));
    addTearDown(service.dispose);
    expect((await service.fetchListings('24')).map((e) => e.id), ['a']);
    await expectLater(service.fetchCard('demo-1'), throwsStateError);
  });

  test('malformed card payload and failed responses stay retryable', () async {
    var calls = 0;
    final service = CardService(client: MockClient((_) async {
      calls++;
      if (calls == 1) {
        return response({
          'card': {...cardJson, 'id': '48'}
        });
      }
      if (calls == 2) return http.Response('private diagnostic', 503);
      return response({'card': cardJson});
    }));
    addTearDown(service.dispose);
    await expectLater(service.fetchCard('24'), throwsFormatException);
    await expectLater(service.fetchCard('24'), throwsStateError);
    expect((await service.fetchCard('24')).name, 'Carta vera');
  });

  test('listing identity, stock limit and demo currency are independent', () {
    final cart = CartController();
    addTearDown(cart.dispose);
    final card = MarketplaceCard.fromJson(cardJson);
    final a = MarketplaceListing.fromJson(offerJson('a'));
    final b = MarketplaceListing.fromJson(offerJson('b', price: 200));
    var aChanges = 0;
    var bChanges = 0;
    cart.quantityFor('a').addListener(() => aChanges++);
    cart.quantityFor('b').addListener(() => bChanges++);
    expect(cart.addListing(card, a), isTrue);
    expect(cart.addListing(card, a), isTrue);
    expect(cart.addListing(card, a), isFalse);
    cart.addListing(card, b);
    cart.addCard(demoCards.first);
    expect(aChanges, 2);
    expect(bChanges, 1);
    expect(cart.listingItems, hasLength(2));
    expect(cart.totalPkn, 447);
    expect(cart.totalPrice, 24.9);
    expect(cart.itemCount, 4);
    expect(
        cart.addListing(card,
            MarketplaceListing.fromJson(offerJson('wrong', cardId: '48'))),
        isFalse);
    final snapshot = cart.listingItems;
    cart.decreaseListing('a');
    expect(snapshot.first.quantity, 2);
    expect(cart.quantityFor('a').value, 1);
    cart.removeListing('b');
    cart.decreaseListing('a');
    expect(cart.listingItems, isEmpty);
    expect(cart.totalPkn, 0);
  });

  test('filters and cart edits cause no GETs or card-info notifications',
      () async {
    var calls = 0;
    final service = CardService(client: MockClient((request) async {
      calls++;
      return response(request.url.path.endsWith('card-page')
          ? {'card': cardJson}
          : {
              'listings': [
                offerJson('a', price: 200),
                offerJson('b', price: 100, condition: 'SP', language: 'EN'),
              ]
            });
    }));
    addTearDown(service.dispose);
    final controller = CardDetailsController(cardId: '24', service: service);
    final cart = CartController();
    addTearDown(controller.dispose);
    addTearDown(cart.dispose);
    await controller.load();
    var infoChanges = 0;
    controller.info.addListener(() => infoChanges++);
    expect(controller.listings.value.visible.first.id, 'b');
    controller.filter(condition: 'NM');
    expect(controller.listings.value.visible.single.id, 'a');
    controller.filter(language: 'IT', sort: ListingSort.highestPrice);
    controller.filter(sort: ListingSort.highestPrice);
    expect(controller.listings.value.visible.first.id, 'a');
    cart.addListing(
        controller.info.value.card!, controller.listings.value.visible.first);
    await controller.load();
    expect(calls, 2);
    expect(infoChanges, 0);
  });

  test(
      'partial failure retries only the failed endpoint and disposal ignores late replies',
      () async {
    final counts = <String, int>{};
    final service = CardService(client: MockClient((request) async {
      final path = request.url.path;
      counts[path] = (counts[path] ?? 0) + 1;
      if (path.endsWith('card-page')) return response({'card': cardJson});
      return counts[path] == 1
          ? http.Response('internal details', 503)
          : response({'listings': []});
    }));
    addTearDown(service.dispose);
    final controller = CardDetailsController(cardId: '24', service: service);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.info.value.card, isNotNull);
    expect(controller.listings.value.hasError, isTrue);
    await controller.retryListings();
    expect(controller.listings.value.hasError, isFalse);
    expect(controller.listings.value.visible, isEmpty);
    expect(counts['/api/marketplace-card-page'], 1);
    expect(counts['/api/marketplace-listings'], 2);
    final pending = Completer<http.Response>();
    final lateService = CardService(client: MockClient((_) => pending.future));
    addTearDown(lateService.dispose);
    final lateController =
        CardDetailsController(cardId: '24', service: lateService);
    final loading = lateController.load();
    lateController.dispose();
    pending.complete(response({'card': cardJson, 'listings': []}));
    await loading;
  });

  testWidgets(
      'top seller opens metadata with demo market and preserves the shared cart',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var homeCalls = 0, detailCalls = 0;
    final home = MarketplaceHomeService(
        client: MockClient((request) async {
          homeCalls++;
          return discovery.jsonResponse(request.url.path.contains('expansion')
              ? discovery.expansionsPayload
              : discovery.homePayload);
        }),
        loadCatalogOrder: () async => {});
    final details = CardService(client: MockClient((request) async {
      detailCalls++;
      return response(request.url.path.endsWith('card-page')
          ? {'card': cardJson}
          : {
              'listings': [offerJson('a')]
            });
    }));
    addTearDown(home.dispose);
    addTearDown(details.dispose);
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        homeService: home,
        cardService: details,
        accountService: guestAccountService()));
    await tester.pumpAndSettle();
    for (var step = 0;
        step < 20 &&
            find.text('Carta economica').hitTestable().evaluate().isEmpty;
        step++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Carta economica'));
    await tester.pumpAndSettle();
    expect(find.byType(CardDetails), findsOneWidget);
    expect(find.text('Carta vera'), findsOneWidget);
    expect(find.text('Set reale · 12/100 · Illustratore'), findsOneWidget);
    expect(find.textContaining('123,50'), findsNothing);
    await tester.tap(find.byTooltip('Informazioni carta'));
    await tester.pumpAndSettle();
    expect(find.text('Illustratore: Illustratore'), findsOneWidget);
    Navigator.of(tester.element(find.text('Illustratore: Illustratore'))).pop();
    await tester.pumpAndSettle();
    for (var step = 0;
        step < 20 && find.text('Shop').hitTestable().evaluate().isEmpty;
        step++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    expect(find.text('Shop').hitTestable(), findsOneWidget);
    expect(find.text('Aggiungi al carrello'), findsNothing);
    final screen = tester.widget<CardDetails>(find.byType(CardDetails));
    expect(screen.cart.itemCount, 0);
    screen.cart.addCard(demoCards.first);
    await tester.tap(find.byTooltip('Apri carrello'));
    await tester.pumpAndSettle();
    expect(find.text('Totale di esempio: 24,90 €'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
    Navigator.of(tester.element(find.text('Totale di esempio: 24,90 €'))).pop();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Carrello, 1 articoli'), findsOneWidget);
    expect(homeCalls, 2);
    expect(detailCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'listing stays lazy on 320px phone with enlarged text and local filters',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var calls = 0;
    final service = CardService(client: MockClient((request) async {
      calls++;
      return response(request.url.path.endsWith('card-page')
          ? {'card': cardJson}
          : {
              'listings': List.generate(
                  80,
                  (index) => offerJson('$index',
                      price: 100 + index.toDouble(),
                      language: index.isEven ? 'IT' : 'EN'))
            });
    }));
    addTearDown(service.dispose);
    final controller = CardDetailsController(cardId: '24', service: service);
    final cart = CartController();
    addTearDown(controller.dispose);
    addTearDown(cart.dispose);
    await controller.load();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomScrollView(slivers: [
      ValueListenableBuilder(
          valueListenable: controller.listings,
          builder: (context, state, _) => ListingDetails(
              state: state,
              card: controller.info.value.card,
              cart: cart,
              onFilter: controller.filter,
              onRetry: controller.retryListings)),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Venditore 79'), findsNothing);
    for (var step = 0;
        step < 20 &&
            find.text('Aggiungi al carrello').hitTestable().evaluate().isEmpty;
        step++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Aggiungi al carrello').hitTestable().first);
    await tester.pumpAndSettle();
    expect(cart.totalPkn, 100);
    controller.filter(language: 'EN');
    await tester.pumpAndSettle();
    expect(controller.listings.value.visible.length, 40);
    expect(find.byType(ListingDetails), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
