import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/models/card_listing.dart';
import 'package:pokoin/models/pokemon_card.dart';
import 'package:pokoin/providers/cart_provider.dart';

PokemonCard _card({required double price}) {
  return PokemonCard(
    id: 'test-card',
    name: 'Test Card',
    imageUrl: 'https://cdn.pokoin.com/cards/test-card.png',
    rarity: 'Rare',
    type: 'Trading card',
    hp: 0,
    attacks: const [],
    price: price,
    description: 'Test card',
    set: 'Test Set',
    number: '1/1',
    artist: '',
    stock: 10,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime(2026),
    tags: const ['Test Set'],
    condition: 'NM',
    isGraded: false,
  );
}

void main() {
  test('cart pricing uses temporary fixed 2000 PKN shipping', () {
    final state = CartState(
      items: [
        CartItem(card: _card(price: 100), quantity: 2),
      ],
    );

    expect(state.subtotal, 200);
    expect(state.tax, 16);
    expect(state.shipping, temporaryFixedCheckoutShippingPkn);
    expect(state.shipping, 2000);
    expect(state.total, 2216);
  });

  test('NFT-only cart pricing sets shipping to zero', () {
    final state = CartState(
      fulfillmentMode: CartFulfillmentMode.nftOnly,
      items: [
        CartItem(
          card: _card(price: 100),
          quantity: 2,
          nftAvailable: true,
          reserveAvailable: true,
        ),
      ],
    );

    expect(state.canCheckoutNftOnly, isTrue);
    expect(state.isNftOnlyCheckout, isTrue);
    expect(state.subtotal, 200);
    expect(state.tax, 16);
    expect(state.shipping, 0);
    expect(state.total, 216);
  });

  test('NFT-only cart falls back to physical shipping for ineligible items',
      () {
    final state = CartState(
      fulfillmentMode: CartFulfillmentMode.nftOnly,
      items: [
        CartItem(card: _card(price: 100), quantity: 1),
      ],
    );

    expect(state.canCheckoutNftOnly, isFalse);
    expect(state.isNftOnlyCheckout, isFalse);
    expect(state.shipping, temporaryFixedCheckoutShippingPkn);
    expect(state.total, 2108);
  });

  test('reserve-only items are not NFT checkout eligible without NFT flag', () {
    final state = CartState(
      fulfillmentMode: CartFulfillmentMode.nftOnly,
      items: [
        CartItem(
          card: _card(price: 100),
          quantity: 1,
          reserveAvailable: true,
          nftAvailable: false,
        ),
      ],
    );

    expect(state.canCheckoutNftOnly, isFalse);
    expect(state.isNftOnlyCheckout, isFalse);
    expect(state.shipping, temporaryFixedCheckoutShippingPkn);
  });

  test('cart item snapshot uses current listing seller display name', () {
    final item = CartItem.fromListing(
      card: _card(price: 100),
      listing: CardListing.fromJson('listing-1', {
        'id': 'listing-1',
        'cardId': 'test-card',
        'sellerUid': 'seller-uid',
        'sellerName': 'vitologiuseppe17',
        'sellerDisplayName': 'Giuseppe',
        'sellerCountry': 'EU',
        'sellerReputationLabel': 'New',
        'condition': 'NM',
        'language': 'EN',
        'pricePkn': 100,
        'quantityAvailable': 1,
        'shippingAvailable': true,
        'reserveAvailable': false,
        'nftAvailable': false,
        'status': 'active',
        'cardName': 'Test Card',
        'cardImageUrl': '',
        'setName': 'Test Set',
        'collectorNumber': '1/1',
      }),
    );

    expect(item.sellerName, 'Giuseppe');
  });
}
