import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/pokemon_card.dart';

class CardService {
  // Local storage
  static const String _cardsBoxName = 'pokemon_cards';
  static const String _supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const Map<String, double> _pknPrices = <String, double>{
    '1': 495,
    '2': 149995,
    '3': 99995,
    '4': 74995,
    '5': 44995,
    '6': 39995,
  };
  static const int catalogPageSize = 500;

  Future<void> _initHive() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PokemonCardAdapter());
    }
  }

  Future<List<PokemonCard>> getAllCards() async {
    await _initHive();

    try {
      final marketplaceCards = await _getMarketplaceCards();
      if (marketplaceCards.isNotEmpty) {
        await _saveCardsToLocal(marketplaceCards);
        return marketplaceCards;
      }

      final supabaseCards = await _getSupabaseBlueprintCards();
      if (supabaseCards.isNotEmpty) {
        await _saveCardsToLocal(supabaseCards);
        return supabaseCards;
      }

      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      if (box.isNotEmpty) {
        final cards = _normalizeCards(box.values.toList());
        return cards;
      }

      final cards = _getSampleCards();
      await _saveCardsToLocal(cards);
      return cards;
    } catch (e) {
      debugPrint('Error getting cards: $e');
      return _getSampleCards();
    }
  }

  Future<MarketplaceHomeSnapshot?> getMarketplaceHomeSnapshot() async {
    try {
      final response = await _getMarketplaceHomeResponse();
      if (response == null || response.statusCode >= 400) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = (data['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => PokemonCard.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      final sectionData =
          Map<String, dynamic>.from(data['sections'] as Map? ?? {});
      return MarketplaceHomeSnapshot(
        cards: cards,
        sections: MarketplaceHomeSections(
          recentlySeenIds: _stringList(sectionData['recentlySeenIds']),
          bestSellerIds: _stringList(sectionData['bestSellerIds']),
          featuredIds: _stringList(sectionData['featuredIds']),
        ),
      );
    } catch (error) {
      debugPrint('Marketplace home snapshot failed: $error');
      return null;
    }
  }

  Future<http.Response?> _getMarketplaceHomeResponse() {
    final uri = Uri.base.resolve('/api/marketplace-home');
    return http.get(uri).timeout(const Duration(seconds: 8));
  }

  static List<String> _stringList(Object? value) {
    return (value as List<dynamic>? ?? const [])
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @visibleForTesting
  PokemonCard cardFromBlueprintForTest(Map<String, dynamic> row) {
    return _cardFromBlueprint(row);
  }

  Future<List<PokemonCard>> _getMarketplaceCards() async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return const [];
    }
    try {
      final uri = Uri.parse(
        '$_supabaseUrl/rest/v1/marketplace_cards'
        '?select=card_id,name,version,image_url,cdn_image_url,preview_image_url,set_name,rarity,card_type,card_number,is_holo,is_foil,item_kind,product_type,imported_at'
        '&cdn_image_url=not.is.null'
        '&order=imported_at.desc.nullslast'
        '&limit=$catalogPageSize',
      );
      final response = await http.get(
        uri,
        headers: {
          'apikey': _supabaseAnonKey,
          'authorization': 'Bearer $_supabaseAnonKey',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 400) {
        debugPrint('Marketplace cards load failed: ${response.statusCode}');
        return const [];
      }

      final rows = jsonDecode(response.body) as List<dynamic>;
      return _normalizeCards(rows
          .whereType<Map>()
          .map((row) => _cardFromMarketplaceRow(Map<String, dynamic>.from(row)))
          .toList());
    } catch (error) {
      debugPrint('Marketplace cards load failed: $error');
      return const [];
    }
  }

  PokemonCard _cardFromMarketplaceRow(Map<String, dynamic> row) {
    final id = '${row['card_id'] ?? row['id'] ?? ''}';
    final rarity = _cleanLabel(row['rarity'], fallback: 'Card');
    final setName = _cleanLabel(row['set_name'], fallback: 'Pokemon');
    final itemKind = _normalizeItemKind(row['item_kind']);
    final productType = _normalizeProductType(row['product_type'], itemKind);
    final type = _marketplaceDisplayType(
      productType,
      fallback: _cleanLabel(row['card_type'], fallback: 'Trading card'),
    );
    final imageUrl =
        _normalizeImageUrl(row['cdn_image_url'] ?? row['image_url']);
    final previewImageUrl = _normalizeImageUrl(
      row['preview_image_url'] ?? row['cdn_image_url'] ?? row['image_url'],
    );
    return PokemonCard(
      id: id,
      name: '${row['name'] ?? 'Pokemon card'}',
      imageUrl: imageUrl,
      previewImageUrl: previewImageUrl,
      rarity: rarity,
      type: type,
      hp: 0,
      attacks: const [],
      price: (_pknPrices[id] ?? 1000 + (_stableSeed(id) % 120000)).toDouble(),
      description: itemKind == 'product'
          ? 'Imported from the Pokoin marketplace product projection.'
          : 'Imported from the Pokoin marketplace projection. Full blueprint data is loaded on card detail.',
      set: setName,
      number: '${row['card_number'] ?? row['version'] ?? id}',
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: row['is_foil'] == true,
      isHolo: row['is_holo'] == true,
      releaseDate: _parseDate(row['imported_at']),
      tags: [setName, rarity, type, itemKind, productType],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
    );
  }

  PokemonCard _cardFromVersionRow(Map<String, dynamic> row) {
    final id = '${row['card_id'] ?? row['id'] ?? ''}';
    final setName = _cleanLabel(row['expansion_name'], fallback: 'Pokemon');
    final productType = _normalizeProductType(row['product_type'], 'single');
    final itemKind = productType == 'card' ? 'single' : 'product';
    final type = _marketplaceDisplayType(productType, fallback: 'Trading card');
    final imageUrl =
        _normalizeImageUrl(row['cdn_image_url'] ?? row['image_url']);
    final previewImageUrl = _normalizeImageUrl(
      row['preview_image_url'] ?? row['cdn_image_url'] ?? row['image_url'],
    );
    return PokemonCard(
      id: id,
      name: '${row['name'] ?? 'Pokemon card'}',
      imageUrl: imageUrl,
      previewImageUrl: previewImageUrl,
      rarity: 'Card',
      type: type,
      hp: 0,
      attacks: const [],
      price: (_pknPrices[id] ?? 1000 + (_stableSeed(id) % 120000)).toDouble(),
      description: itemKind == 'product'
          ? 'Imported from the Pokoin marketplace product version index.'
          : 'Imported from the Pokoin marketplace version index. Full blueprint data is loaded on card detail.',
      set: setName,
      number: '${row['expansion_number'] ?? id}',
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: _parseDate(row['projected_at']),
      tags: [setName, 'Card', type, itemKind, productType],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
    );
  }

  Future<List<PokemonCard>> _getSupabaseBlueprintCards() async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return const [];
    }
    try {
      var response = await _getBlueprintRows(includePreview: true);
      if (response.statusCode >= 400) {
        response = await _getBlueprintRows(includePreview: false);
      }
      if (response.statusCode >= 400) {
        debugPrint('Supabase card load failed: ${response.statusCode}');
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      return _normalizeCards(rows
          .whereType<Map>()
          .map((row) => _cardFromBlueprint(Map<String, dynamic>.from(row)))
          .toList());
    } catch (error) {
      debugPrint('Supabase card load failed: $error');
      return const [];
    }
  }

  Future<http.Response> _getBlueprintRows({required bool includePreview}) {
    final previewSelect = includePreview ? ',preview_image_url' : '';
    final uri = Uri.parse(
      '$_supabaseUrl/rest/v1/cardtrader_pokemon_blueprints'
      '?select=id,name,version,image_url,cdn_image_url$previewSelect,blueprint,expansion'
      '&cdn_image_url=not.is.null'
      '&order=imported_at.desc'
      '&limit=$catalogPageSize',
    );
    return http.get(
      uri,
      headers: {
        'apikey': _supabaseAnonKey,
        'authorization': 'Bearer $_supabaseAnonKey',
      },
    ).timeout(const Duration(seconds: 10));
  }

  PokemonCard _cardFromBlueprint(Map<String, dynamic> row) {
    final blueprint = Map<String, dynamic>.from(row['blueprint'] as Map? ?? {});
    final expansion = Map<String, dynamic>.from(row['expansion'] as Map? ?? {});
    final properties = _readProperties(blueprint);
    final id = '${row['id'] ?? ''}';
    final name = '${row['name'] ?? blueprint['name'] ?? 'Pokemon card'}';
    final setName =
        '${expansion['name'] ?? blueprint['expansion_name'] ?? 'Pokemon'}';
    final number = properties['number'] ??
        properties['collector_number'] ??
        properties['card_number'] ??
        '${row['version'] ?? id}';
    final rarity = _cleanLabel(
      properties['rarity'] ??
          blueprint['rarity'] ??
          properties['collector_rarity'] ??
          '',
      fallback: 'Card',
    );
    final type = _cleanLabel(
      properties['card_type'] ??
          properties['type'] ??
          blueprint['type'] ??
          blueprint['category_name'] ??
          '',
      fallback: 'Trading card',
    );
    final imageUrl = _normalizeImageUrl(
      _fullBlueprintImageUrl(blueprint) ??
          row['cdn_image_url'] ??
          row['image_url'] ??
          blueprint['image_url'],
    );
    final previewImageUrl = _normalizeImageUrl(
      row['preview_image_url'] ??
          row['cdn_preview_image_url'] ??
          row['previewImageUrl'] ??
          row['cdn_image_url'] ??
          row['image_url'] ??
          blueprint['image_url'],
    );
    final price = _pknPrices[id] ?? 1000 + (_stableSeed(id) % 120000);
    return PokemonCard(
      id: id,
      name: name,
      imageUrl: imageUrl,
      previewImageUrl: previewImageUrl,
      rarity: rarity,
      type: type,
      hp: 0,
      attacks: const [],
      price: price.toDouble(),
      description:
          'Imported from CardTrader blueprint data. Seller listings are managed on Pokoin.',
      set: setName,
      number: number.toString(),
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: rarity.toLowerCase().contains('holo'),
      isHolo: rarity.toLowerCase().contains('holo'),
      releaseDate: DateTime.now(),
      tags: [
        setName,
        rarity,
        type,
        'single',
        if (properties['stage'] != null) '${properties['stage']}',
      ],
      condition: 'NM',
      isGraded: false,
      itemKind: 'single',
    );
  }

  Map<String, Object?> _readProperties(Map<String, dynamic> blueprint) {
    final properties = <String, Object?>{};
    final editable = blueprint['editable_properties'];
    if (editable is List) {
      for (final item in editable.whereType<Map>()) {
        final key = '${item['name'] ?? item['slug'] ?? item['key'] ?? ''}'
            .toLowerCase()
            .replaceAll(' ', '_');
        if (key.isNotEmpty) {
          properties[key] = item['value'] ?? item['text'];
        }
      }
    }
    for (final entry in blueprint.entries) {
      properties.putIfAbsent(entry.key.toLowerCase(), () => entry.value);
    }
    return properties;
  }

  String? _fullBlueprintImageUrl(Map<String, dynamic> blueprint) {
    final image = blueprint['image'];
    if (image is! Map) {
      return null;
    }

    final rawUrl = '${image['url'] ?? ''}'.trim();
    if (rawUrl.isEmpty || rawUrl.contains('/preview_')) {
      return null;
    }
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    if (rawUrl.startsWith('/')) {
      return 'https://cardtrader.com$rawUrl';
    }
    return rawUrl;
  }

  int _stableSeed(String value) {
    return value.codeUnits.fold<int>(0, (sum, unit) => sum + unit * 31);
  }

  String _cleanLabel(Object? value, {required String fallback}) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text.toLowerCase() == 'pokemon') {
      return fallback;
    }
    return text;
  }

  DateTime _parseDate(Object? value) {
    return DateTime.tryParse('${value ?? ''}') ?? DateTime.now();
  }

  String _normalizeItemKind(Object? value) {
    return '${value ?? ''}'.trim().toLowerCase() == 'product'
        ? 'product'
        : 'single';
  }

  String _normalizeProductType(Object? value, String itemKind) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    const allowed = {
      'card',
      'booster_pack',
      'booster_box',
      'booster_bundle',
      'elite_trainer_box',
      'tin',
      'collection_box',
      'deck',
      'championship_deck',
      'accessory',
      'sealed_product',
    };
    if (allowed.contains(normalized)) {
      return normalized;
    }
    return itemKind == 'product' ? 'sealed_product' : 'card';
  }

  String _marketplaceDisplayType(String productType,
      {required String fallback}) {
    switch (productType) {
      case 'booster_pack':
        return 'Booster pack';
      case 'booster_box':
        return 'Booster box';
      case 'booster_bundle':
        return 'Booster bundle';
      case 'elite_trainer_box':
        return 'Elite Trainer Box';
      case 'tin':
        return 'Tin';
      case 'collection_box':
        return 'Collection box';
      case 'deck':
        return 'Deck';
      case 'championship_deck':
        return 'Championship deck';
      case 'accessory':
        return 'Accessory';
      case 'sealed_product':
        return 'Sealed product';
      default:
        return fallback;
    }
  }

  String _normalizeImageUrl(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) {
      return '';
    }

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      return text;
    }
    if (uri.host != 'cdn.pokoin.com') {
      return text;
    }

    final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
    return '/card-images$path${uri.hasQuery ? '?${uri.query}' : ''}';
  }

  Future<void> _saveCardsToLocal(List<PokemonCard> cards) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      await box.clear();
      for (int i = 0; i < cards.length; i++) {
        await box.put(i, cards[i]);
      }
    } catch (e) {
      debugPrint('Error saving cards to local storage: $e');
    }
  }

  List<PokemonCard> _normalizeCards(List<PokemonCard> cards) {
    return cards
        .map(
          (card) => card.copyWith(
            stock: card.stock,
            price: _pknPrices[card.id] ?? card.price,
          ),
        )
        .toList();
  }

  Future<PokemonCard?> getCardById(String id) async {
    try {
      final projectionCard = await _getMarketplaceProjectionCardById(id);
      final blueprintCard = await _getSupabaseBlueprintCardById(id);
      final remoteCard = _mergeProjectionWithBlueprint(
        projectionCard: projectionCard,
        blueprintCard: blueprintCard,
      );
      if (remoteCard != null) {
        await _upsertCardToLocal(remoteCard);
        return remoteCard;
      }

      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      return box.values.firstWhere((card) => card.id == id);
    } catch (e) {
      debugPrint('Error getting card by ID: $e');
      return null;
    }
  }

  Future<PokemonCard?> _getMarketplaceProjectionCardById(String id) async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return null;
    }
    final trimmedId = id.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return null;
    }

    try {
      final uri = Uri.parse(
        '$_supabaseUrl/rest/v1/marketplace_card_versions',
      ).replace(
        queryParameters: {
          'select':
              'card_id,name,expansion_name,expansion_number,image_url,cdn_image_url,preview_image_url,projected_at,product_type',
          'card_id': 'eq.$trimmedId',
          'limit': '1',
        },
      );
      final response = await http.get(
        uri,
        headers: {
          'apikey': _supabaseAnonKey,
          'authorization': 'Bearer $_supabaseAnonKey',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return null;
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final maps = rows.whereType<Map>();
      if (maps.isEmpty) {
        return null;
      }
      return _cardFromVersionRow(Map<String, dynamic>.from(maps.first));
    } catch (error) {
      debugPrint('Marketplace projection card by id failed: $error');
      return null;
    }
  }

  PokemonCard? _mergeProjectionWithBlueprint({
    required PokemonCard? projectionCard,
    required PokemonCard? blueprintCard,
  }) {
    if (projectionCard == null) {
      return blueprintCard;
    }
    if (blueprintCard == null) {
      return projectionCard;
    }
    final shouldUseProjectionImage = projectionCard.itemKind == 'product' ||
        blueprintCard.imageUrl.trim().isEmpty;
    return blueprintCard.copyWith(
      name: projectionCard.name,
      imageUrl: shouldUseProjectionImage && projectionCard.imageUrl.isNotEmpty
          ? projectionCard.imageUrl
          : null,
      previewImageUrl: projectionCard.previewImageUrl.isNotEmpty
          ? projectionCard.previewImageUrl
          : null,
      type: projectionCard.type,
      description: projectionCard.description,
      set: projectionCard.set,
      number: projectionCard.number,
      tags: projectionCard.tags,
      itemKind: projectionCard.itemKind,
      productType: projectionCard.productType,
    );
  }

  Future<List<PokemonCard>> getExpansionVersionCards(PokemonCard card) async {
    return getCardsByExpansion(card.set);
  }

  Future<List<PokemonCard>> getCardsByExpansion(String expansionName) async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return const [];
    }
    final normalizedExpansion = expansionName.trim();
    if (normalizedExpansion.isEmpty) {
      return const [];
    }

    try {
      final uri = Uri.parse(
        '$_supabaseUrl/rest/v1/marketplace_card_versions',
      ).replace(
        queryParameters: {
          'select':
              'card_id,name,expansion_name,expansion_number,image_url,cdn_image_url,preview_image_url,projected_at,product_type',
          'expansion_name': 'eq.$normalizedExpansion',
          'order':
              'expansion_number_int.asc.nullslast,expansion_number.asc,blueprint_id.asc',
          'limit': '1000',
        },
      );
      final response = await http.get(
        uri,
        headers: {
          'apikey': _supabaseAnonKey,
          'authorization': 'Bearer $_supabaseAnonKey',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      return rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      debugPrint('Expansion cards failed: $error');
      return const [];
    }
  }

  Future<PokemonCard?> _getSupabaseBlueprintCardById(String id) async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return null;
    }
    final trimmedId = id.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return null;
    }

    try {
      var response =
          await _getBlueprintRowById(trimmedId, includePreview: true);
      if (response.statusCode >= 400) {
        response = await _getBlueprintRowById(trimmedId, includePreview: false);
      }
      if (response.statusCode >= 400) {
        debugPrint('Supabase card by id failed: ${response.statusCode}');
        return null;
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final maps = rows.whereType<Map>();
      if (maps.isEmpty) {
        return null;
      }
      final row = maps.first;
      return _normalizeCards([
        _cardFromBlueprint(Map<String, dynamic>.from(row)),
      ]).first;
    } catch (error) {
      debugPrint('Supabase card by id failed: $error');
      return null;
    }
  }

  Future<http.Response> _getBlueprintRowById(
    String id, {
    required bool includePreview,
  }) {
    final previewSelect = includePreview ? ',preview_image_url' : '';
    final uri = Uri.parse(
      '$_supabaseUrl/rest/v1/cardtrader_pokemon_blueprints'
      '?select=id,name,version,image_url,cdn_image_url$previewSelect,blueprint,expansion'
      '&id=eq.$id'
      '&limit=1',
    );
    return http.get(
      uri,
      headers: {
        'apikey': _supabaseAnonKey,
        'authorization': 'Bearer $_supabaseAnonKey',
      },
    ).timeout(const Duration(seconds: 8));
  }

  Future<void> _upsertCardToLocal(PokemonCard card) async {
    try {
      await _initHive();
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys.firstWhere(
        (key) => box.get(key)?.id == card.id,
        orElse: () => null,
      );
      if (key == null) {
        await box.add(card);
      } else {
        await box.put(key, card);
      }
    } catch (error) {
      debugPrint('Error caching card by id: $error');
    }
  }

  Future<List<PokemonCard>> searchCards(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return getAllCards();
    }

    final remote = await searchMarketplaceCards(normalizedQuery, limit: 240);
    if (remote.isNotEmpty) {
      return remote;
    }

    try {
      return _rankLocalCards(await getAllCards(), normalizedQuery, 240);
    } catch (e) {
      debugPrint('Error searching cards: $e');
      return const [];
    }
  }

  Future<List<PokemonCard>> searchMarketplaceCards(
    String query, {
    int limit = 120,
    String? productType,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return const [];
    }

    if (productType != null && productType.trim().isNotEmpty) {
      final rows = await _searchMarketplaceCardVersions(
        normalizedQuery,
        limit: limit,
        productType: productType,
      );
      return rows;
    }

    final versionRows = await _searchMarketplaceCardVersions(
      normalizedQuery,
      limit: limit * 2,
    );
    final singleRows =
        versionRows.where((card) => card.itemKind != 'product').toList();
    final productRows = await _searchMarketplaceCardRows(
      normalizedQuery,
      limit: limit * 2,
      productSearchOnly: true,
    );
    return _dedupeCards([...singleRows, ...productRows]).take(limit).toList();
  }

  Future<List<PokemonCard>> getMarketplaceCardsByProductType(
    String productType, {
    int limit = 240,
  }) async {
    return _searchMarketplaceCardVersions(
      '',
      limit: limit,
      productType: productType,
    );
  }

  Future<List<PokemonCard>> searchCardPreviews(
    String query, {
    List<PokemonCard> fallbackCards = const [],
    int limit = 8,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return const [];
    }

    final local = _rankLocalCards(fallbackCards, normalizedQuery, limit);
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return local;
    }

    try {
      final remote =
          await searchMarketplaceCards(normalizedQuery, limit: limit);
      return _dedupeCards([...remote, ...local]).take(limit).toList();
    } catch (error) {
      debugPrint('Supabase card search failed: $error');
      return local;
    }
  }

  Future<List<PokemonCard>> _searchMarketplaceCardRows(
    String normalizedQuery, {
    required int limit,
    String? productType,
    bool productSearchOnly = false,
  }) async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return const [];
    }

    try {
      final terms = _searchTerms(normalizedQuery);
      final queryParameters = <String, String>{
        'select':
            'card_id,name,version,image_url,cdn_image_url,preview_image_url,set_name,rarity,card_type,card_number,is_holo,is_foil,item_kind,product_type,imported_at',
        'order': 'imported_at.desc.nullslast',
        'limit': '${limit * 4}',
      };
      final normalizedProductType = productType?.trim();
      if (normalizedProductType != null && normalizedProductType.isNotEmpty) {
        queryParameters['product_type'] = 'eq.$normalizedProductType';
      } else if (productSearchOnly) {
        queryParameters['item_kind'] = 'eq.product';
      }
      if (terms.length <= 1) {
        if (normalizedQuery.isNotEmpty) {
          queryParameters['or'] = productSearchOnly
              ? '(name.ilike.*$normalizedQuery*,set_name.ilike.*$normalizedQuery*)'
              : '(name.ilike.*$normalizedQuery*,set_name.ilike.*$normalizedQuery*,card_type.ilike.*$normalizedQuery*,rarity.ilike.*$normalizedQuery*,card_number.ilike.*$normalizedQuery*)';
        }
      } else {
        queryParameters['and'] = _andAnyFieldFilter(
          terms,
          productSearchOnly
              ? ['name', 'set_name']
              : [
                  'name',
                  'set_name',
                  'card_type',
                  'rarity',
                  'card_number',
                ],
        );
      }
      final uri = Uri.parse('$_supabaseUrl/rest/v1/marketplace_cards').replace(
        queryParameters: queryParameters,
      );
      final response = await http.get(
        uri,
        headers: {
          'apikey': _supabaseAnonKey,
          'authorization': 'Bearer $_supabaseAnonKey',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return const [];
      }

      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromMarketplaceRow(Map<String, dynamic>.from(row)))
          .toList();
      return _rankLocalCards(cards, normalizedQuery, limit);
    } catch (error) {
      debugPrint('Marketplace card row search failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> _searchMarketplaceCardVersions(
    String normalizedQuery, {
    required int limit,
    String? productType,
  }) async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      return const [];
    }

    try {
      final terms = _searchTerms(normalizedQuery);
      final queryParameters = <String, String>{
        'select':
            'card_id,name,expansion_name,expansion_number,image_url,cdn_image_url,preview_image_url,projected_at,product_type',
        'limit': '${limit * 4}',
      };
      if (normalizedQuery.isEmpty) {
        queryParameters['order'] =
            'expansion_name.asc,expansion_number_int.asc.nullslast,expansion_number.asc';
      }
      final normalizedProductType = productType?.trim();
      if (normalizedProductType != null && normalizedProductType.isNotEmpty) {
        queryParameters['product_type'] = 'eq.$normalizedProductType';
      }
      if (terms.length <= 1) {
        if (normalizedQuery.isNotEmpty) {
          queryParameters['or'] = normalizedProductType != null &&
                  normalizedProductType.isNotEmpty
              ? '(name.ilike.*$normalizedQuery*,expansion_name.ilike.*$normalizedQuery*)'
              : '(name.ilike.*$normalizedQuery*,expansion_name.ilike.*$normalizedQuery*,expansion_number.ilike.*$normalizedQuery*)';
        }
      } else {
        queryParameters['and'] = _andAnyFieldFilter(
          terms,
          normalizedProductType != null && normalizedProductType.isNotEmpty
              ? ['name', 'expansion_name']
              : ['name', 'expansion_name', 'expansion_number'],
        );
      }
      final uri =
          Uri.parse('$_supabaseUrl/rest/v1/marketplace_card_versions').replace(
        queryParameters: queryParameters,
      );
      final response = await http.get(
        uri,
        headers: {
          'apikey': _supabaseAnonKey,
          'authorization': 'Bearer $_supabaseAnonKey',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return const [];
      }

      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      return _rankLocalCards(cards, normalizedQuery, limit);
    } catch (error) {
      debugPrint('Marketplace card version search failed: $error');
      return const [];
    }
  }

  Future<void> recordMarketplaceEvent(
    String cardId,
    String eventType, {
    String source = 'web',
  }) async {
    final id = int.tryParse(cardId);
    if (id == null) {
      return;
    }
    try {
      await http
          .post(
            Uri.base.resolve('/api/marketplace-event'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'cardId': id,
              'eventType': eventType,
              'source': source,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Analytics must never block the marketplace UX.
    }
  }

  List<PokemonCard> _rankLocalCards(
    List<PokemonCard> cards,
    String query,
    int limit,
  ) {
    final normalizedQuery = query.toLowerCase();
    final ranked = cards
        .map((card) => MapEntry(card, _localSearchScore(card, normalizedQuery)))
        .where((entry) => entry.value > 0)
        .toList()
      ..sort((a, b) {
        final score = b.value.compareTo(a.value);
        if (score != 0) {
          return score;
        }
        return a.key.name.compareTo(b.key.name);
      });
    return ranked.map((entry) => entry.key).take(limit).toList();
  }

  int _localSearchScore(PokemonCard card, String query) {
    final name = card.name.toLowerCase();
    final set = card.set.toLowerCase();
    final isProduct = card.itemKind == 'product';
    final number = isProduct ? '' : card.number.toLowerCase();
    final tags = card.tags.join(' ').toLowerCase();
    final haystack =
        isProduct ? '$name $set $tags' : '$name $set $number $tags';
    final terms = _searchTerms(query);

    if (number == query) {
      return 980;
    }
    if (number.startsWith(query)) {
      return 880;
    }
    if (_wordStartsWith(number, query)) {
      return 840;
    }
    if (name == query) {
      return 1000;
    }
    if (terms.length > 1 && terms.every(haystack.contains)) {
      var score = 520;
      var matchedName = false;
      var matchedSet = false;
      var matchedNumber = false;
      for (final term in terms) {
        if (number == term) {
          score += 220;
          matchedNumber = true;
        } else if (number.startsWith(term)) {
          score += 190;
          matchedNumber = true;
        } else if (_wordStartsWith(number, term)) {
          score += 170;
          matchedNumber = true;
        } else if (number.contains(term)) {
          score += 140;
          matchedNumber = true;
        } else if (name.startsWith(term)) {
          score += 190;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 150;
          matchedName = true;
        } else if (name.contains(term)) {
          score += 80;
          matchedName = true;
        } else if (set.startsWith(term)) {
          score += 180;
          matchedSet = true;
        } else if (_wordStartsWith(set, term)) {
          score += 160;
          matchedSet = true;
        } else if (set.contains(term)) {
          score += 120;
          matchedSet = true;
        }
      }
      if (matchedName && matchedSet) {
        score += 140;
      }
      if (matchedNumber && matchedName) {
        score += 180;
      } else if (matchedNumber && matchedSet) {
        score += 120;
      }
      return score;
    }
    if (name.startsWith(query)) {
      return 800;
    }
    if (name.contains(query)) {
      return 600;
    }
    if (number.contains(query)) {
      return 700;
    }
    if (set.contains(query)) {
      return 350;
    }
    if (tags.contains(query)) {
      return 180;
    }
    return 0;
  }

  List<String> _searchTerms(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2)
        .toList();
  }

  String _andAnyFieldFilter(List<String> terms, List<String> fields) {
    final groups = terms.map((term) {
      final clauses = fields.map((field) => '$field.ilike.*$term*').join(',');
      return 'or($clauses)';
    }).join(',');
    return '($groups)';
  }

  bool _wordStartsWith(String value, String term) {
    return value
        .split(RegExp(r'[^a-z0-9]+'))
        .any((word) => word.startsWith(term));
  }

  List<PokemonCard> _dedupeCards(List<PokemonCard> cards) {
    final seen = <String>{};
    final unique = <PokemonCard>[];
    for (final card in cards) {
      if (seen.add(card.id)) {
        unique.add(card);
      }
    }
    return unique;
  }

  Future<List<PokemonCard>> getCardsByRarity(String rarity) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.rarity == rarity).toList();
    } catch (e) {
      debugPrint('Error getting cards by rarity: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsByType(String type) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.type == type).toList();
    } catch (e) {
      debugPrint('Error getting cards by type: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsBySet(String setName) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.set == setName).toList();
    } catch (e) {
      debugPrint('Error getting cards by set: $e');
      return [];
    }
  }

  Future<void> addCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      await box.add(card);
    } catch (e) {
      debugPrint('Error adding card: $e');
      rethrow;
    }
  }

  Future<void> updateCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys
          .firstWhere((key) => box.get(key)?.id == card.id, orElse: () => -1);
      if (key != -1) {
        await box.put(key, card);
      }
    } catch (e) {
      debugPrint('Error updating card: $e');
      rethrow;
    }
  }

  Future<void> deleteCard(String cardId) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys
          .firstWhere((key) => box.get(key)?.id == cardId, orElse: () => -1);
      if (key != -1) {
        await box.delete(key);
      }
    } catch (e) {
      debugPrint('Error deleting card: $e');
      rethrow;
    }
  }

  List<PokemonCard> _getSampleCards() {
    return [
      PokemonCard(
        id: '1',
        name: 'Pikachu',
        imageUrl: 'https://images.pokemontcg.io/base1/58_hires.png',
        rarity: 'Common',
        type: 'Lightning',
        hp: 40,
        attacks: ['Thunder Shock', 'Thunder'],
        price: _pknPrices['1']!,
        description: 'A cute electric mouse Pokémon.',
        set: 'Base Set',
        number: '58',
        artist: 'Atsuko Nishida',
        stock: 0,
        rating: 4.5,
        reviewCount: 23,
        isFoil: false,
        isHolo: false,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Lightning', 'Common', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '2',
        name: 'Charizard',
        imageUrl: 'https://images.pokemontcg.io/base1/4_hires.png',
        rarity: 'Rare Holo',
        type: 'Fire',
        hp: 120,
        attacks: ['Fire Spin', 'Flamethrower'],
        price: _pknPrices['2']!,
        description: 'A powerful dragon Pokémon.',
        set: 'Base Set',
        number: '4',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.9,
        reviewCount: 156,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Fire', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '3',
        name: 'Blastoise',
        imageUrl: 'https://images.pokemontcg.io/base1/2_hires.png',
        rarity: 'Rare Holo',
        type: 'Water',
        hp: 100,
        attacks: ['Hydro Pump', 'Rain Dance'],
        price: _pknPrices['3']!,
        description: 'A powerful water turtle Pokémon.',
        set: 'Base Set',
        number: '2',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.7,
        reviewCount: 89,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Water', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '4',
        name: 'Venusaur',
        imageUrl: 'https://images.pokemontcg.io/base1/15_hires.png',
        rarity: 'Rare Holo',
        type: 'Grass',
        hp: 100,
        attacks: ['Solar Beam', 'Razor Leaf'],
        price: _pknPrices['4']!,
        description: 'A powerful grass dinosaur Pokémon.',
        set: 'Base Set',
        number: '15',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.6,
        reviewCount: 67,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Grass', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '5',
        name: 'Alakazam',
        imageUrl: 'https://images.pokemontcg.io/base1/1_hires.png',
        rarity: 'Rare Holo',
        type: 'Psychic',
        hp: 80,
        attacks: ['Confuse Ray', 'Psybeam'],
        price: _pknPrices['5']!,
        description: 'A powerful psychic Pokémon.',
        set: 'Base Set',
        number: '1',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.4,
        reviewCount: 45,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Psychic', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '6',
        name: 'Machamp',
        imageUrl: 'https://images.pokemontcg.io/base1/8_hires.png',
        rarity: 'Rare Holo',
        type: 'Fighting',
        hp: 100,
        attacks: ['Karate Chop', 'Submission'],
        price: _pknPrices['6']!,
        description: 'A powerful fighting Pokémon.',
        set: 'Base Set',
        number: '8',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.3,
        reviewCount: 34,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Fighting', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
    ];
  }
}

class MarketplaceHomeSnapshot {
  const MarketplaceHomeSnapshot({
    required this.cards,
    required this.sections,
  });

  final List<PokemonCard> cards;
  final MarketplaceHomeSections sections;
}

class MarketplaceHomeSections {
  const MarketplaceHomeSections({
    required this.recentlySeenIds,
    required this.bestSellerIds,
    required this.featuredIds,
  });

  final List<String> recentlySeenIds;
  final List<String> bestSellerIds;
  final List<String> featuredIds;
}
