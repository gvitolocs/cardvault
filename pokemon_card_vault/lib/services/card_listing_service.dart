import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../models/card_listing.dart';
import 'pokoin_api_auth.dart';
import 'pokoin_api_client.dart';

class CardListingService {
  CardListingService({
    http.Client? client,
    FirebaseAuth? auth,
    PokoinApiClient? apiClient,
  })  : _auth = auth,
        _apiClient = apiClient ??
            PokoinApiClient(
              client: client ?? http.Client(),
              auth: PokoinApiAuthService.instance(
                auth: auth,
              ),
            );

  final FirebaseAuth? _auth;
  final PokoinApiClient _apiClient;

  Stream<List<CardListing>> activeListings({int limit = 500}) {
    return Stream.fromFuture(_getListings(limit: limit));
  }

  Stream<List<CardListing>> activeListingsForCard(String cardId) {
    return Stream.fromFuture(_getListings(cardId: cardId));
  }

  Stream<List<CardListing>> listingsForSeller(String sellerUid) {
    if (sellerUid.trim().isEmpty) {
      return Stream.value(const []);
    }
    return Stream.fromFuture(_getListings(sellerUid: sellerUid));
  }

  Stream<List<CardListing>> activeListingsForSellerUsername(String username) {
    if (username.trim().isEmpty) {
      return Stream.value(const []);
    }
    return Stream.fromFuture(_getListings(sellerUsername: username));
  }

  Future<CardListing> createListing(CardListing listing) async {
    final data = await _request('POST', body: {
      ...listing.toSnapshotJson(),
    });
    final created = CardListing.fromJson(
      '${data['id'] ?? ''}',
      Map<String, dynamic>.from(data),
    );
    return created;
  }

  Future<List<CardListing>> listingsByIds(Iterable<String> listingIds) async {
    final ids = listingIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) {
      return const [];
    }
    final listings = await Future.wait(
      ids.map((id) async {
        final rows = await _getListings(listingId: id, limit: 1);
        return rows.isEmpty ? null : rows.first;
      }),
    );
    return listings.whereType<CardListing>().toList(growable: false);
  }

  Future<void> updateListingStatus({
    required String listingId,
    required String sellerUid,
    required String status,
  }) async {
    await _request('PATCH', listingId: listingId, body: {
      'sellerUid': sellerUid,
      'status': status,
    });
  }

  Future<void> updateListingQuantity({
    required String listingId,
    required String sellerUid,
    required int quantityAvailable,
  }) async {
    if (quantityAvailable < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }
    await _request('PATCH', listingId: listingId, body: {
      'sellerUid': sellerUid,
      'quantityAvailable': quantityAvailable,
    });
  }

  Future<CardListing> updateListing(CardListing listing) async {
    if (listing.id.trim().isEmpty) {
      throw ArgumentError('Listing id is required.');
    }
    final data = await _request('PATCH', listingId: listing.id, body: {
      ...listing.toSnapshotJson(),
      'sellerUid': listing.sellerUid,
    });
    return CardListing.fromJson(
      '${data['id'] ?? listing.id}',
      Map<String, dynamic>.from(data),
    );
  }

  Future<void> removeListing({
    required String listingId,
    required String sellerUid,
  }) async {
    await updateListingStatus(
      listingId: listingId,
      sellerUid: sellerUid,
      status: 'inactive',
    );
  }

  Future<void> decrementListingQuantity({
    required String listingId,
    required int quantity,
  }) async {
    if (listingId.isEmpty || quantity <= 0) {
      return;
    }
    await _request('POST', listingId: listingId, action: 'decrement', body: {
      'quantity': quantity,
    });
  }

  Future<List<CardListing>> _getListings({
    int limit = 500,
    String? listingId,
    String? cardId,
    String? sellerUid,
    String? sellerUsername,
  }) async {
    final query = {
      'limit': '$limit',
      if (listingId != null && listingId.trim().isNotEmpty)
        'id': listingId.trim(),
      if (cardId != null && cardId.trim().isNotEmpty) 'cardId': cardId.trim(),
      if (sellerUid != null && sellerUid.trim().isNotEmpty)
        'sellerUid': sellerUid.trim(),
      if (sellerUsername != null && sellerUsername.trim().isNotEmpty)
        'sellerUsername': sellerUsername.trim().toLowerCase(),
    };
    final uri = Uri.base.resolve('/api/marketplace-listings').replace(
          queryParameters: query,
        );
    final response = await _apiClient.get(
      uri,
      requireAuth: sellerUid != null,
    );
    final data = _decode(response);
    final rows = (data['listings'] as List<dynamic>? ?? const []);
    return rows
        .whereType<Map>()
        .map((row) => CardListing.fromJson(
              '${row['id'] ?? ''}',
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }

  Future<Map<String, dynamic>> _request(
    String method, {
    String? listingId,
    String? action,
    Map<String, dynamic>? body,
  }) async {
    final auth =
        _auth ?? (Firebase.apps.isEmpty ? null : FirebaseAuth.instance);
    if (auth?.currentUser == null) {
      throw StateError('Sign in before updating marketplace listings.');
    }
    final uri = Uri.base.resolve('/api/marketplace-listings').replace(
      queryParameters: {
        if (listingId != null && listingId.isNotEmpty) 'id': listingId,
        if (action != null && action.isNotEmpty) 'action': action,
      },
    );
    final response = await _apiClient.sendJson(method, uri, body: body);
    return _decode(response);
  }
}

Map<String, dynamic> _decode(http.Response response) {
  final decoded = response.body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode >= 400) {
    throw StateError(
      decoded['error'] as String? ?? 'Marketplace listing request failed.',
    );
  }
  return decoded;
}
