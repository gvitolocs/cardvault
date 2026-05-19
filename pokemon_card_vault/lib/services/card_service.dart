import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/pokemon_card.dart';

class MarketplaceExpansion {
  const MarketplaceExpansion({
    required this.name,
    required this.slug,
    required this.cardCount,
    required this.symbolImageUrl,
    required this.defaultSymbolUrl,
  });

  factory MarketplaceExpansion.fromJson(Map<String, dynamic> json) {
    return MarketplaceExpansion(
      name: '${json['name'] ?? ''}',
      slug: '${json['slug'] ?? ''}',
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
      symbolImageUrl: '${json['symbolImageUrl'] ?? ''}',
      defaultSymbolUrl: '${json['defaultSymbolUrl'] ?? ''}',
    );
  }

  final String name;
  final String slug;
  final int cardCount;
  final String symbolImageUrl;
  final String defaultSymbolUrl;
}

class MarketplaceExpansionSnapshot {
  const MarketplaceExpansionSnapshot({
    required this.expansion,
    required this.cards,
  });

  final MarketplaceExpansion expansion;
  final List<PokemonCard> cards;
}

class CardService {
  // Local storage
  static const String _cardsBoxName = 'pokemon_cards';
  static const String _homeSnapshotBoxName = 'marketplace_home_snapshot';
  static const String _homeSnapshotKey = 'snapshot';
  static const Map<String, double> _pknPrices = <String, double>{
    '1': 495,
    '2': 149995,
    '3': 99995,
    '4': 74995,
    '5': 44995,
    '6': 39995,
  };
  static const int catalogPageSize = 500;
  static const Map<String, String> _raritySearchAliases = {
    'goldstar': 'gold star',
    'shiningrare': 'shining rare',
    'shinystar': 'shiny star',
    'illustrationrare': 'illustration rare',
    'specialillustrationrare': 'special illustration rare',
    'amazingerare': 'amazing rare',
    'radiantrare': 'radiant rare',
    'ultrarare': 'ultra rare',
    'secretrare': 'secret rare',
    'hyperrare': 'hyper rare',
    'doublerare': 'double rare',
    'rareholo': 'rare holo',
    'holographicrare': 'holographic rare',
    'holorare': 'holo rare',
  };
  static const Map<String, String> _trainerSearchAliases = {
    'camilla': 'cynthia',
    'cynthia': 'cynthia',
    'shirona': 'cynthia',
    'n': 'n',
    'lance': 'lance',
    'camus': 'lance',
    'misty': 'misty',
    'ondine': 'misty',
    'kasumi': 'misty',
    'brock': 'brock',
    'pierre': 'brock',
    'takeshi': 'brock',
    'erika': 'erika',
    'giovanni': 'giovanni',
    'sabrina': 'sabrina',
    'sandra': 'clair',
    'clair': 'clair',
    'iris': 'iris',
    'steven': 'steven',
    'rochard': 'steven',
    'diantha': 'diantha',
    'lilia': 'lillie',
    'lillie': 'lillie',
    'gladio': 'gladion',
    'gladion': 'gladion',
    'marnie': 'marnie',
    'mary': 'marnie',
    'hop': 'hop',
    'dandel': 'leon',
    'leon': 'leon',
    'roy': 'raihan',
    'raihan': 'raihan',
    'nemona': 'nemona',
    'peonia': 'peonia',
    'iono': 'iono',
    'kissara': 'iono',
  };
  static const Set<String> _ownershipStopWords = {
    'di',
    'de',
    'del',
    'della',
    'da',
    'du',
    'des',
    'of',
    'the',
    'owned',
    'owner',
  };

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

  Future<List<PokemonCard>> getCachedCards() async {
    await _initHive();
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      return _normalizeCards(box.values.toList());
    } catch (error) {
      debugPrint('Cached cards load failed: $error');
      return const [];
    }
  }

  Future<MarketplaceHomeSnapshot?> getCachedMarketplaceHomeSnapshot() async {
    try {
      final box = await Hive.openBox<Map>(_homeSnapshotBoxName);
      final cached = box.get(_homeSnapshotKey);
      if (cached == null) {
        return null;
      }
      return _homeSnapshotFromMap(Map<String, dynamic>.from(cached));
    } catch (error) {
      debugPrint('Cached marketplace home snapshot failed: $error');
      return null;
    }
  }

  Future<MarketplaceHomeSnapshot?> getMarketplaceHomeSnapshot() async {
    try {
      final response = await _getMarketplaceHomeResponse();
      if (response == null || response.statusCode >= 400) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final snapshot = _homeSnapshotFromMap(data);
      await _saveMarketplaceHomeSnapshot(snapshot);
      return snapshot;
    } catch (error) {
      debugPrint('Marketplace home snapshot failed: $error');
      return null;
    }
  }

  MarketplaceHomeSnapshot _homeSnapshotFromMap(Map<String, dynamic> data) {
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
  }

  Future<void> _saveMarketplaceHomeSnapshot(
    MarketplaceHomeSnapshot snapshot,
  ) async {
    try {
      final box = await Hive.openBox<Map>(_homeSnapshotBoxName);
      await box.put(_homeSnapshotKey, snapshot.toJson());
    } catch (error) {
      debugPrint('Marketplace home cache save failed: $error');
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

  @visibleForTesting
  List<PokemonCard> rankSearchCandidatesForTest(
    List<PokemonCard> cards,
    String query, {
    int limit = 20,
  }) {
    return _rankLocalCards(cards, query, limit);
  }

  Future<List<PokemonCard>> _getMarketplaceCards() async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-cards').replace(
        queryParameters: {'limit': '$catalogPageSize'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

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
    final rawNumber = '${row['card_number'] ?? ''}';
    final productVariant = '${row['product_variant'] ?? row['version'] ?? ''}';
    final itemKind = _itemKindForProjectedRow(
      itemKind: row['item_kind'],
      productType: row['product_type'],
      number: rawNumber,
    );
    final productType = _productTypeForProjectedRow(
      productType: row['product_type'],
      itemKind: itemKind,
      number: rawNumber,
    );
    final number = itemKind == 'product' ? productVariant : rawNumber;
    final trainerName = _cleanLabel(row['trainer_name'], fallback: '');
    final type = _marketplaceDisplayType(
      productType,
      fallback: _cleanLabel(row['card_type'], fallback: 'Card'),
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
      number: number,
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: row['is_foil'] == true,
      isHolo: row['is_holo'] == true,
      releaseDate: _parseDate(row['imported_at']),
      tags: [
        setName,
        rarity,
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
      ],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      expansionSymbolUrl: _normalizeImageUrl(row['expansion_symbol_url']),
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
    );
  }

  PokemonCard _cardFromVersionRow(Map<String, dynamic> row) {
    final id = '${row['card_id'] ?? row['id'] ?? ''}';
    final setName = _cleanLabel(row['expansion_name'], fallback: 'Pokemon');
    final rawNumber = '${row['expansion_number'] ?? ''}';
    final productVariant = '${row['product_variant'] ?? ''}';
    final itemKind = _itemKindForProjectedRow(
      itemKind: row['item_kind'],
      productType: row['product_type'],
      number: rawNumber,
    );
    final productType = _productTypeForProjectedRow(
      productType: row['product_type'],
      itemKind: itemKind,
      number: rawNumber,
    );
    final number = itemKind == 'product' ? productVariant : rawNumber;
    final type = _marketplaceDisplayType(productType, fallback: 'Card');
    final trainerName = _cleanLabel(row['trainer_name'], fallback: '');
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
      number: number,
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: _parseDate(row['projected_at']),
      tags: [
        setName,
        'Card',
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
      ],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      expansionSymbolUrl: _normalizeImageUrl(row['expansion_symbol_url']),
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
    );
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
    final cardType = _cleanLabel(
      properties['card_type'] ??
          properties['type'] ??
          blueprint['type'] ??
          blueprint['category_name'] ??
          '',
      fallback: 'Card',
    );
    final trainerName = _extractTrainerName(name);
    final productType = _classifyProductType(
      name: name,
      setName: setName,
      categoryName: blueprint['category_name'],
      itemType: properties['type'] ?? blueprint['type'],
      number: number,
      version: row['version'],
      id: id,
    );
    final itemKind = productType == 'card' ? 'single' : 'product';
    final type = _marketplaceDisplayType(
      productType,
      fallback: cardType,
    );
    final displayRarity = itemKind == 'product' ? type : rarity;
    final imageUrl = _normalizeImageUrl(
      row['cdn_image_url'] ??
          row['image_url'] ??
          _fullBlueprintImageUrl(blueprint) ??
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
      rarity: displayRarity,
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
      isFoil: itemKind != 'product' && rarity.toLowerCase().contains('holo'),
      isHolo: itemKind != 'product' && rarity.toLowerCase().contains('holo'),
      releaseDate: DateTime.now(),
      tags: [
        setName,
        displayRarity,
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
        if (properties['stage'] != null) '${properties['stage']}',
      ],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
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

  String _extractTrainerName(String name) {
    final match =
        RegExp(r"^(.+?)'s\s+.+$", caseSensitive: false).firstMatch(name.trim());
    return match?.group(1)?.trim() ?? '';
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

  bool _hasCollectorNumber(Object? value) {
    final text = '${value ?? ''}'.trim().toLowerCase();
    return RegExp(r'(^|[^0-9])[0-9]{1,4}[a-z]?/[0-9]{1,4}([^0-9]|$)')
        .hasMatch(text);
  }

  String _itemKindForProjectedRow({
    required Object? itemKind,
    required Object? productType,
    required Object? number,
  }) {
    if (_hasCollectorNumber(number)) {
      return 'single';
    }
    final normalizedProductType = '${productType ?? ''}'.trim().toLowerCase();
    return normalizedProductType == 'card'
        ? 'single'
        : _normalizeItemKind(itemKind);
  }

  String _productTypeForProjectedRow({
    required Object? productType,
    required String itemKind,
    required Object? number,
  }) {
    if (_hasCollectorNumber(number)) {
      return 'card';
    }
    return _normalizeProductType(productType, itemKind);
  }

  String _classifyProductType({
    required String name,
    required String setName,
    required Object? categoryName,
    required Object? itemType,
    required Object? number,
    required Object? version,
    required String id,
  }) {
    final normalizedName = name.toLowerCase();
    final normalizedSet = setName.toLowerCase();
    final normalizedCategory = '${categoryName ?? ''}'.toLowerCase();
    final normalizedType = '${itemType ?? ''}'.toLowerCase();
    final normalizedNumber = '${number ?? ''}'.toLowerCase().trim();
    final normalizedVersion = '${version ?? ''}'.toLowerCase().trim();
    final idText = id.trim();
    final hasCollectorNumber =
        RegExp(r'(^|[^0-9])[0-9]{1,4}[a-z]?/[0-9]{1,4}([^0-9]|$)')
            .hasMatch(normalizedNumber);
    final looksLikeBlueprintNumber = normalizedNumber == idText ||
        RegExp(r'^[0-9]{5,}$').hasMatch(normalizedNumber);
    final hasVersion = normalizedVersion.isNotEmpty;
    final championshipSet =
        RegExp(r'world championship decks|world championships .* deck')
            .hasMatch(normalizedSet);

    bool matches(String pattern) {
      final expression = RegExp('(^|[^a-z0-9])($pattern)([^a-z0-9]|\$)');
      return expression.hasMatch(normalizedName) ||
          expression.hasMatch(normalizedCategory) ||
          expression.hasMatch(normalizedType);
    }

    if (hasCollectorNumber) return 'card';
    if (matches(
        r'coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory')) {
      return 'accessory';
    }
    if (matches(r'booster box|display box|sealed box')) return 'booster_box';
    if (matches(r'booster bundle|bundle')) return 'booster_bundle';
    if (matches(r'booster pack|booster|pack')) return 'booster_pack';
    if (matches(r'elite trainer box|etb')) return 'elite_trainer_box';
    if (matches(r'tin|tins')) return 'tin';
    if (matches(
        r'premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection')) {
      return 'collection_box';
    }
    if (matches(r'theme deck|starter deck|battle deck|deck')) return 'deck';
    if (championshipSet &&
        !hasCollectorNumber &&
        (!hasVersion || looksLikeBlueprintNumber)) {
      return 'championship_deck';
    }
    if (!hasCollectorNumber &&
        matches(r'sealed|sealed product|product|sealed case')) {
      return 'sealed_product';
    }
    return 'card';
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
        return fallback.toLowerCase() == 'trading card' ? 'Card' : fallback;
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
      if (projectionCard != null) {
        await _upsertCardToLocal(projectionCard);
        return projectionCard;
      }

      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      return box.values.firstWhere((card) => card.id == id);
    } catch (e) {
      debugPrint('Error getting card by ID: $e');
      return null;
    }
  }

  Future<PokemonCard?> _getMarketplaceProjectionCardById(String id) async {
    final trimmedId = id.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return null;
    }

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
        queryParameters: {
          'cardId': trimmedId,
          'limit': '1',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

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

  Future<List<PokemonCard>> getExpansionVersionCards(PokemonCard card) async {
    return getCardsByExpansion(card.set);
  }

  Future<List<PokemonCard>> getOtherVersionCards(String cardId) async {
    final trimmedId = cardId.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return const [];
    }

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
        queryParameters: {
          'sameAsCardId': trimmedId,
          'productType': 'card',
          'limit': '100',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      return _sortCardsByCollectorNumber(cards);
    } catch (error) {
      debugPrint('Other version cards failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> getSimilarVersionCards(String cardId) async {
    final current = await getCardById(cardId);
    if (current == null || current.set.trim().isEmpty) {
      return const [];
    }
    final sameNameCards = await searchMarketplaceCards(
      current.name,
      limit: 80,
      productType: 'card',
    );
    final expansionCards = await getCardsByExpansion(current.set);
    final sameNameRanked = sameNameCards
        .where((card) =>
            card.id != current.id &&
            _normalizeCardText(card.name) == _normalizeCardText(current.name))
        .toList()
      ..sort((a, b) {
        final currentSet = _normalizeCardText(current.set);
        final aSameSet = _normalizeCardText(a.set) == currentSet;
        final bSameSet = _normalizeCardText(b.set) == currentSet;
        final setMatch = (bSameSet ? 1 : 0).compareTo(aSameSet ? 1 : 0);
        if (setMatch != 0) {
          return setMatch;
        }
        return _compareCollectorNumberSortKeys(
          _collectorNumberSortKey(a.number),
          _collectorNumberSortKey(b.number),
        );
      });
    final sameNameIds = sameNameRanked.map((card) => card.id).toSet();
    final rankedExpansion = expansionCards
        .where((card) => card.id != current.id && !sameNameIds.contains(card.id))
        .map((card) => (card: card, score: _similarityScore(current, card)))
        .toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) {
          return score;
        }
        return _compareCollectorNumberSortKeys(
          _collectorNumberSortKey(a.card.number),
          _collectorNumberSortKey(b.card.number),
        );
      });
    return _dedupeCards([
      ...sameNameRanked,
      ...rankedExpansion.map((entry) => entry.card),
    ]).take(16).toList();
  }

  Future<List<MarketplaceExpansion>> getMarketplaceExpansions({
    String? slug,
  }) async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-expansions').replace(
        queryParameters: {
          if (slug?.trim().isNotEmpty == true) 'slug': slug!.trim(),
          'limit': '1000',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return const [];
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['expansions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              MarketplaceExpansion.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      debugPrint('Marketplace expansions failed: $error');
      return const [];
    }
  }

  Future<MarketplaceExpansion?> getMarketplaceExpansionBySlug(
    String slug,
  ) async {
    final expansions = await getMarketplaceExpansions(slug: slug);
    return expansions.isEmpty ? null : expansions.first;
  }

  Future<MarketplaceExpansionSnapshot?> getMarketplaceExpansionSnapshotBySlug(
    String slug,
  ) async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-expansions').replace(
        queryParameters: {
          'slug': slug.trim(),
          'includeCards': '1',
          'productType': 'card',
          'limit': '1200',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return null;
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final expansion = MarketplaceExpansion.fromJson(
        Map<String, dynamic>.from(payload['expansion'] as Map? ?? const {}),
      );
      final cards = (payload['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      return MarketplaceExpansionSnapshot(
        expansion: expansion,
        cards: _sortCardsByCollectorNumber(cards),
      );
    } catch (error) {
      debugPrint('Marketplace expansion snapshot failed: $error');
      return null;
    }
  }

  Future<List<PokemonCard>> getCardsByExpansion(String expansionName) async {
    final normalizedExpansion = expansionName.trim();
    if (normalizedExpansion.isEmpty) {
      return const [];
    }

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
        queryParameters: {
          'expansionName': normalizedExpansion,
          'productType': 'card',
          'limit': '1000',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      return _sortCardsByCollectorNumber(cards);
    } catch (error) {
      debugPrint('Expansion cards failed: $error');
      return const [];
    }
  }

  List<PokemonCard> _sortCardsByCollectorNumber(List<PokemonCard> cards) {
    return [...cards]..sort((a, b) {
        final number = _compareCollectorNumberSortKeys(
          _collectorNumberSortKey(a.number),
          _collectorNumberSortKey(b.number),
        );
        if (number != 0) {
          return number;
        }
        return a.name.compareTo(b.name);
      });
  }

  int _similarityScore(PokemonCard source, PokemonCard candidate) {
    var score = 0;
    final sourceNumber = _collectorNumberSortKey(source.number).number;
    final candidateNumber = _collectorNumberSortKey(candidate.number).number;
    final distance = (sourceNumber - candidateNumber).abs();
    if (distance <= 2) {
      score += 80;
    } else if (distance <= 6) {
      score += 48;
    } else if (distance <= 12) {
      score += 24;
    }

    if (_normalizeCardText(source.type) == _normalizeCardText(candidate.type)) {
      score += 28;
    }
    if (_normalizeCardText(source.rarity) ==
        _normalizeCardText(candidate.rarity)) {
      score += 18;
    }
    final sourceTokens = _cardNameTokens(source.name);
    final candidateTokens = _cardNameTokens(candidate.name);
    score += sourceTokens.intersection(candidateTokens).length * 12;
    if (source.trainerName.isNotEmpty &&
        source.trainerName == candidate.trainerName) {
      score += 20;
    }
    return score;
  }

  Set<String> _cardNameTokens(String name) {
    return name
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3)
        .toSet();
  }

  String _normalizeCardText(String value) {
    return value.trim().toLowerCase();
  }

  int _compareCollectorNumberSortKeys(
    ({int group, int number, String suffix}) a,
    ({int group, int number, String suffix}) b,
  ) {
    final group = a.group.compareTo(b.group);
    if (group != 0) return group;
    final number = a.number.compareTo(b.number);
    if (number != 0) return number;
    return a.suffix.compareTo(b.suffix);
  }

  ({int group, int number, String suffix}) _collectorNumberSortKey(
    String number,
  ) {
    final normalized = number.trim().toLowerCase();
    final firstNumber = RegExp(r'\d+').firstMatch(normalized);
    final parsedNumber =
        firstNumber == null ? 1 << 30 : int.tryParse(firstNumber.group(0)!) ?? 1 << 30;
    final normalNumber =
        RegExp(r'[a-z]*\d+[a-z]?\s*/\s*\d+', caseSensitive: false)
                .hasMatch(normalized) ||
            RegExp(r'^\s*\d+[a-z]?\s*$').hasMatch(normalized);
    return (
      group: normalNumber ? 0 : 1,
      number: parsedNumber,
      suffix: normalized,
    );
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
    String searchLanguage = 'en',
  }) async {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      return const [];
    }

    final queryLanguage = _tcgdexLanguage(searchLanguage);
    final queries = _searchQueryVariants([normalizedQuery]);
    final results = <PokemonCard>[];

    if (productType != null && productType.trim().isNotEmpty) {
      for (final searchQuery in queries) {
        final rows = await _searchMarketplaceCardVersions(
          searchQuery,
          limit: limit,
          productType: productType,
          searchLanguage: queryLanguage,
        );
        results.addAll(rows);
        if (results.length >= limit) {
          break;
        }
      }
      return _dedupeCards(results).take(limit).toList();
    }

    for (final searchQuery in queries) {
      final rows = await _searchMarketplaceCardVersions(
        searchQuery,
        limit: limit,
        searchLanguage: queryLanguage,
      );
      results.addAll(rows.where((card) => card.itemKind != 'product'));
      final singleRows = await _searchMarketplaceCardRows(
        searchQuery,
        limit: limit,
        searchLanguage: queryLanguage,
      );
      results.addAll(singleRows.where((card) => card.itemKind != 'product'));
      final productRows = await _searchMarketplaceCardRows(
        searchQuery,
        limit: limit,
        searchLanguage: queryLanguage,
        productSearchOnly: true,
      );
      results.addAll(productRows);
      if (results.length >= limit) {
        break;
      }
    }
    return _dedupeCards(results).take(limit).toList();
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
    String searchLanguage = 'en',
    bool preserveRemotePool = false,
  }) async {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      return const [];
    }

    final queryVariants = _searchQueryVariants([normalizedQuery]);
    final local =
        _rankLocalCardsForQueries(fallbackCards, queryVariants, limit);

    try {
      final queryLanguage = _tcgdexLanguage(searchLanguage);
      final remote = await _searchMarketplaceCandidatesForQueries(
        _searchQueryVariants([normalizedQuery]),
        normalizedQuery,
        limit: limit,
        searchLanguage: queryLanguage,
        preserveRemotePool: preserveRemotePool,
      );
      final similarQuery = _previewSimilarQuery(normalizedQuery);
      final similarRemote = similarQuery == null
          ? const <PokemonCard>[]
          : await _searchMarketplaceCandidatesForQueries(
              _searchQueryVariants([similarQuery]),
              similarQuery,
              limit: limit,
              searchLanguage: queryLanguage,
              preserveRemotePool: preserveRemotePool,
            );
      final similarLocal = similarQuery == null
          ? const <PokemonCard>[]
          : _rankLocalCardsForQueries(
              fallbackCards,
              _searchQueryVariants([similarQuery]),
              limit,
            );
      return _dedupeCards([
        ...remote,
        ...local,
        ...similarRemote,
        ...similarLocal,
      ]).take(limit).toList();
    } catch (error) {
      debugPrint('Supabase card search failed: $error');
      return local;
    }
  }

  Future<List<PokemonCard>> searchAutocompleteCards(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
  }) async {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      return const [];
    }
    try {
      final response = await http
          .post(
            Uri.base.resolve('/api/marketplace-autocomplete'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'search_term': normalizedQuery,
              'result_limit': limit,
              'pool_limit': poolLimit,
              'search_language': _tcgdexLanguage(searchLanguage),
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        debugPrint('Marketplace autocomplete failed: ${response.statusCode}');
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      return _dedupeCards(rows
          .whereType<Map>()
          .map(
              (row) => _cardFromSearchCandidate(Map<String, dynamic>.from(row)))
          .toList());
    } catch (error) {
      debugPrint('Marketplace autocomplete failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> _searchMarketplaceCandidatesForQueries(
    Iterable<String> queries,
    String rankingQuery, {
    required int limit,
    String searchLanguage = 'en',
    bool preserveRemotePool = false,
  }) async {
    final results = <PokemonCard>[];
    for (final query in queries) {
      final rows = await _searchMarketplaceCandidates(
        query,
        limit: limit,
        searchLanguage: searchLanguage,
      );
      results.addAll(rows);
      if (results.length >= limit) {
        break;
      }
    }
    final deduped = _dedupeCards(results);
    if (preserveRemotePool) {
      return deduped.take(limit).toList();
    }
    return _rankLocalCards(deduped, rankingQuery, limit);
  }

  Future<List<PokemonCard>> _searchMarketplaceCandidates(
    String normalizedQuery, {
    required int limit,
    String searchLanguage = 'en',
  }) async {
    const pageSize = 1000;
    if (limit > pageSize) {
      final results = <PokemonCard>[];
      for (var offset = 0; offset < limit; offset += pageSize) {
        final pageLimit = math.min(pageSize, limit - offset);
        final page = await _searchMarketplaceCandidatePage(
          normalizedQuery,
          limit: pageLimit,
          offset: offset,
          searchLanguage: searchLanguage,
        );
        if (page.isEmpty) {
          break;
        }
        results.addAll(page);
        if (page.length < pageLimit) {
          break;
        }
      }
      return _dedupeCards(results).take(limit).toList();
    }
    return _searchMarketplaceCandidatePage(
      normalizedQuery,
      limit: limit,
      offset: 0,
      searchLanguage: searchLanguage,
    );
  }

  Future<List<PokemonCard>> _searchMarketplaceCandidatesDirect(
    String normalizedQuery, {
    required int limit,
    int offset = 0,
    String searchLanguage = 'en',
  }) async {
    try {
      final response = await http
          .post(
            Uri.base.resolve('/api/marketplace-search-candidates'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'search_term': normalizedQuery,
              'result_limit': limit,
              'result_offset': offset,
              'search_language': _tcgdexLanguage(searchLanguage),
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        debugPrint(
          'Direct marketplace candidate search failed: ${response.statusCode}',
        );
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map(
              (row) => _cardFromSearchCandidate(Map<String, dynamic>.from(row)))
          .toList();
      return _dedupeCards(cards).take(limit).toList();
    } catch (error) {
      debugPrint('Direct marketplace candidate search failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> _searchMarketplaceCandidatePage(
    String normalizedQuery, {
    required int limit,
    required int offset,
    String searchLanguage = 'en',
  }) async {
    return _searchMarketplaceCandidatesDirect(
      normalizedQuery,
      limit: limit,
      offset: offset,
      searchLanguage: searchLanguage,
    );
  }

  PokemonCard _cardFromSearchCandidate(Map<String, dynamic> row) {
    final id = '${row['card_id'] ?? row['id'] ?? ''}';
    final rarity = _cleanLabel(row['rarity'], fallback: 'Card');
    final setName = _cleanLabel(row['set_name'], fallback: 'Pokemon');
    final rawNumber = '${row['card_number'] ?? ''}';
    final productVariant = '${row['product_variant'] ?? row['version'] ?? ''}';
    final itemKind = _itemKindForProjectedRow(
      itemKind: row['item_kind'],
      productType: row['product_type'],
      number: rawNumber,
    );
    final productType = _productTypeForProjectedRow(
      productType: row['product_type'],
      itemKind: itemKind,
      number: rawNumber,
    );
    final number = itemKind == 'product' ? productVariant : rawNumber;
    final trainerName = _cleanLabel(row['trainer_name'], fallback: '');
    final type = _marketplaceDisplayType(
      productType,
      fallback: _cleanLabel(row['card_type'], fallback: 'Card'),
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
          ? 'Imported from the Pokoin autocomplete product projection.'
          : 'Imported from the Pokoin autocomplete projection.',
      set: setName,
      number: number,
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: _parseDate(row['imported_at']),
      tags: [
        setName,
        rarity,
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
      ],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
    );
  }

  String _readEmoji(Map<String, dynamic> row) => '${row['emoji'] ?? ''}'.trim();

  Map<String, dynamic> _readCardPalette(Map<String, dynamic> row) {
    final value = row['card_palette'] ?? row['cardPalette'];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  String? _previewSimilarQuery(String query) {
    final terms = _searchTerms(query)
        .where((term) => !RegExp(r'^[0-9]+$').hasMatch(term))
        .toList();
    if (terms.isEmpty) {
      return null;
    }
    terms.sort((a, b) => b.length.compareTo(a.length));
    final strongest = terms.first;
    return strongest == query.trim().toLowerCase() ? null : strongest;
  }

  String _tcgdexLanguage(String language) {
    switch (language.trim().toLowerCase()) {
      case 'it':
      case 'fr':
      case 'de':
      case 'es':
      case 'pt':
      case 'nl':
      case 'pl':
      case 'ru':
      case 'ko':
      case 'id':
      case 'th':
        return language.trim().toLowerCase();
      case 'jp':
      case 'ja':
        return 'ja';
      case 'zh':
      case 'zh-cn':
        return 'zh-cn';
      case 'zh-tw':
        return 'zh-tw';
      default:
        return 'en';
    }
  }

  Future<List<PokemonCard>> _searchMarketplaceCardRows(
    String normalizedQuery, {
    required int limit,
    String? productType,
    bool productSearchOnly = false,
    String searchLanguage = 'en',
  }) async {
    try {
      final queryParameters = <String, String>{'limit': '${limit * 4}'};
      final normalizedProductType = productType?.trim();
      if (normalizedProductType != null && normalizedProductType.isNotEmpty) {
        queryParameters['productType'] = normalizedProductType;
      } else if (productSearchOnly) {
        queryParameters['productSearchOnly'] = '1';
      }
      if (normalizedQuery.isNotEmpty) {
        queryParameters['query'] = normalizedQuery;
      }
      if (_tcgdexLanguage(searchLanguage) != 'en') {
        queryParameters['lang'] = _tcgdexLanguage(searchLanguage);
      }
      final uri = Uri.base.resolve('/api/marketplace-cards').replace(
            queryParameters: queryParameters,
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

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
    String searchLanguage = 'en',
  }) async {
    try {
      final queryParameters = <String, String>{'limit': '${limit * 4}'};
      final normalizedProductType = productType?.trim();
      if (normalizedProductType != null && normalizedProductType.isNotEmpty) {
        queryParameters['productType'] = normalizedProductType;
      }
      if (normalizedQuery.isNotEmpty) {
        queryParameters['query'] = normalizedQuery;
      }
      if (_tcgdexLanguage(searchLanguage) != 'en') {
        queryParameters['lang'] = _tcgdexLanguage(searchLanguage);
      }
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
            queryParameters: queryParameters,
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

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
    return _rankLocalCardsForQueries(
        cards, _searchQueryVariants([query]), limit);
  }

  List<PokemonCard> _rankLocalCardsForQueries(
    List<PokemonCard> cards,
    List<String> queries,
    int limit,
  ) {
    final ranked = cards
        .map((card) => MapEntry(
              card,
              queries.fold<int>(
                0,
                (score, query) => math.max(
                  score,
                  _localSearchScore(card, query.toLowerCase()),
                ),
              ),
            ))
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
    final trainerName = card.trainerName.toLowerCase();
    final isProduct = card.itemKind == 'product';
    final number = isProduct ? '' : card.number.toLowerCase();
    final tags = card.tags.join(' ').toLowerCase();
    final haystack = isProduct
        ? '$name $set $trainerName $tags'
        : '$name $set $trainerName $number $tags';
    final terms = _searchTerms(query);
    final compactQuery = query.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactName = name.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactSet = set.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactNumber = number.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactTrainerName = trainerName.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactTags = tags.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactHaystack = [
      compactName,
      compactNumber,
      compactSet,
      compactTrainerName,
      compactTags,
    ].where((part) => part.isNotEmpty).join();
    final nameCoverageBonus =
        _characterCoverageScore(compactName, compactQuery);
    final coverageBonus = math.max(
      nameCoverageBonus,
      _characterCoverageScore(compactHaystack, compactQuery) ~/ 2,
    );
    int boost(int score) => score + coverageBonus;
    final hasNumberTerm = terms.any((term) => RegExp(r'^[0-9]+$').hasMatch(term));
    final hasVariationTerm = terms.any(_isVariationSearchTerm);
    final hasRarityTerm = terms.any(_isRaritySearchTerm);
    final hasExpansionAliasTerm = terms.any(_isExpansionAliasSearchTerm);
    final hasTextTerm = terms.any(
      (term) =>
          !RegExp(r'^[0-9]+$').hasMatch(term) &&
          !_isVariationSearchTerm(term) &&
          !_isRaritySearchTerm(term) &&
          !_isExpansionAliasSearchTerm(term),
    );
    if (terms.length > 1 &&
        (hasNumberTerm || hasVariationTerm || hasExpansionAliasTerm) &&
        hasTextTerm) {
      var matchedName = false;
      var matchedNumber = false;
      var matchedVariation = false;
      var matchedExpansion = false;
      var matchedSet = false;
      var score = 0;
      for (final term in terms) {
        final compactTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (RegExp(r'^[0-9]+$').hasMatch(term)) {
          final numberTokens = _searchTerms(number);
          if (number == term ||
              compactNumber == compactTerm ||
              numberTokens.contains(term)) {
            score += 1600;
            matchedNumber = true;
          } else if (number.startsWith(term) || compactNumber.startsWith(compactTerm)) {
            score += 1300;
            matchedNumber = true;
          } else if (number.contains(term) || compactNumber.contains(compactTerm)) {
            score += 900;
            matchedNumber = true;
          }
          continue;
        }
        if (_isVariationSearchTerm(term)) {
          if (_cardHasVariation(card, term)) {
            score += 1500;
            matchedVariation = true;
          }
          continue;
        }
        if (_isExpansionAliasSearchTerm(term)) {
          if (_cardHasExpansionAlias(card, term)) {
            score += 1550;
            matchedExpansion = true;
          }
          continue;
        }
        if (name == term || compactName == compactTerm) {
          score += 1400;
          matchedName = true;
        } else if (name.startsWith(term) || compactName.startsWith(compactTerm)) {
          score += 1150;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 980;
          matchedName = true;
        } else if (_isLikelyNameTypo(compactName, compactTerm)) {
          score += 760;
          matchedName = true;
        } else if (name.contains(term) || compactName.contains(compactTerm)) {
          score += 720;
          matchedName = true;
        } else if (set.startsWith(term) || compactSet.startsWith(compactTerm)) {
          score += 520;
          matchedSet = true;
        } else if (set.contains(term) || compactSet.contains(compactTerm)) {
          score += 360;
          matchedSet = true;
        }
      }
      if (matchedName && matchedNumber) {
        return boost(score + 5200);
      }
      if (matchedName && matchedVariation) {
        return boost(score + 4400);
      }
      if (matchedName && matchedExpansion) {
        return boost(score + 4600);
      }
      if (matchedName && matchedSet) {
        return boost(score + 700);
      }
      if (matchedNumber || matchedVariation || matchedExpansion) {
        return 0;
      }
    }
    if (number == query) {
      return boost(980);
    }
    if (number.startsWith(query)) {
      return boost(880);
    }
    if (_wordStartsWith(number, query)) {
      return boost(840);
    }
    if (name == query) {
      return boost(1000);
    }
    if (compactQuery.isNotEmpty) {
      final nameDistance = _boundedDamerauLevenshtein(
        compactName,
        compactQuery,
        math.max(2, compactQuery.length ~/ 4),
      );
      if (nameDistance <= 2 && compactQuery.length >= 5) {
        return boost(940 - (nameDistance * 70));
      }
      if (compactName.startsWith(compactQuery)) {
        return boost(760);
      }
      final fuzzyName = _fuzzyPrefixScore(compactName, compactQuery);
      if (fuzzyName > 0) {
        if (terms.length <= 1 &&
            compactQuery.length >= 5 &&
            !compactName.contains(compactQuery) &&
            !compactQuery.contains(compactName)) {
          final prefix = compactName.substring(
            0,
            math.min(compactName.length, compactQuery.length),
          );
          final prefixDistance = _boundedDamerauLevenshtein(
            prefix,
            compactQuery,
            2,
          );
          if (prefixDistance > 2) {
            final fullDistance = _boundedDamerauLevenshtein(
              compactName,
              compactQuery,
              2,
            );
            if (fullDistance > 2) {
              return 0;
            }
          }
        }
        return boost(fuzzyName);
      }
      final fuzzySet = _fuzzyPrefixScore(compactSet, compactQuery);
      if (fuzzySet > 0) {
        return boost(fuzzySet ~/ 2);
      }
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
        } else if (trainerName == term) {
          score += 210;
          matchedName = true;
        } else if (trainerName.startsWith(term)) {
          score += 170;
          matchedName = true;
        } else if (trainerName.contains(term)) {
          score += 120;
          matchedName = true;
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
      return boost(score);
    }
    if (terms.length > 1 && hasRarityTerm && hasTextTerm) {
      var score = 420;
      var matchedName = false;
      var matchedRarity = false;
      for (final term in terms) {
        if (_isRaritySearchTerm(term)) {
          if (_cardHasRarityHint(card, term)) {
            score += 420;
            matchedRarity = true;
          }
        } else if (name.startsWith(term)) {
          score += 260;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 220;
          matchedName = true;
        } else if (name.contains(term)) {
          score += 160;
          matchedName = true;
        }
      }
      if (matchedName && matchedRarity) {
        return boost(score);
      }
    }
    if (name.startsWith(query)) {
      return boost(800);
    }
    if (name.contains(query)) {
      return boost(600);
    }
    if (number.contains(query)) {
      return boost(700);
    }
    if (set.contains(query)) {
      return boost(350);
    }
    if (trainerName == query) {
      return boost(760);
    }
    if (trainerName.startsWith(query)) {
      return boost(640);
    }
    if (trainerName.contains(query)) {
      return boost(480);
    }
    if (tags.contains(query)) {
      return boost(180);
    }
    if (_canUseLooseCoverageFallback(
      terms: terms,
      compactQuery: compactQuery,
      compactName: compactName,
      hasStructuredIntent:
          hasTextTerm &&
              (hasNumberTerm ||
                  hasVariationTerm ||
                  hasRarityTerm ||
                  hasExpansionAliasTerm),
      nameCoverageBonus: nameCoverageBonus,
      coverageBonus: coverageBonus,
    )) {
      return coverageBonus;
    }
    return 0;
  }

  bool _canUseLooseCoverageFallback({
    required List<String> terms,
    required String compactQuery,
    required String compactName,
    required bool hasStructuredIntent,
    required int nameCoverageBonus,
    required int coverageBonus,
  }) {
    if (coverageBonus < 220 || compactQuery.isEmpty) {
      return false;
    }

    // Query parts like "232", "ex", "v", or "sir" are structured intent, not
    // free text. Do not let ordered-character matching override exact fields.
    if (hasStructuredIntent) {
      return false;
    }

    // For complete single-word names, loose ordered-character coverage across
    // name + set + tags admits unrelated cards like "Pokemon Communication" for
    // "porygon". Keep it only for short in-progress typing and strong name hits.
    if (terms.length <= 1 && compactQuery.length >= 5) {
      return compactName.startsWith(compactQuery[0]) &&
          nameCoverageBonus >= 260;
    }

    return true;
  }

  int _fuzzyPrefixScore(String target, String query) {
    if (query.isEmpty || target.isEmpty) {
      return 0;
    }
    final windowLength = math.min(target.length, math.max(query.length + 2, 3));
    final window = target.substring(0, windowLength);
    final subsequence = _orderedCharacterMatchScore(window, query);
    if (subsequence > 0) {
      return subsequence;
    }
    final prefix = target.substring(0, math.min(target.length, query.length));
    final prefixDistance = _boundedDamerauLevenshtein(prefix, query, 2);
    if (prefixDistance <= 1) {
      return 700 - (prefixDistance * 80);
    }
    final distance = _boundedDamerauLevenshtein(window, query, 2);
    if (distance <= 1) {
      return 720 - (distance * 80);
    }
    if ((target.length - query.length).abs() <= 2) {
      final fullDistance = _boundedDamerauLevenshtein(target, query, 2);
      if (fullDistance <= 1) {
        return 720 - (fullDistance * 80);
      }
      if (fullDistance == 2 && query.length >= 5) {
        return 520;
      }
    }
    if (distance == 2 && query.length >= 3) {
      return 520;
    }
    return 0;
  }

  int _orderedCharacterMatchScore(String target, String query) {
    var targetIndex = 0;
    var gaps = 0;
    for (final codeUnit in query.codeUnits) {
      final nextIndex =
          target.indexOf(String.fromCharCode(codeUnit), targetIndex);
      if (nextIndex < 0) {
        return 0;
      }
      gaps += nextIndex - targetIndex;
      targetIndex = nextIndex + 1;
    }
    return math.max(420, 700 - (gaps * 40));
  }

  int _characterCoverageScore(String target, String query) {
    if (target.isEmpty || query.isEmpty) {
      return 0;
    }
    var targetIndex = 0;
    var matched = 0;
    var gaps = 0;
    for (final codeUnit in query.codeUnits) {
      final nextIndex =
          target.indexOf(String.fromCharCode(codeUnit), targetIndex);
      if (nextIndex < 0) {
        continue;
      }
      matched += 1;
      gaps += nextIndex - targetIndex;
      targetIndex = nextIndex + 1;
    }
    if (matched == 0) {
      return 0;
    }
    final coverage = matched / query.length;
    final matchedScore = matched * 34;
    final coverageScore = (coverage * 180).round();
    return math.max(0, matchedScore + coverageScore - (gaps * 4));
  }

  int _boundedDamerauLevenshtein(String a, String b, int maxDistance) {
    if ((a.length - b.length).abs() > maxDistance) {
      return maxDistance + 1;
    }
    final matrix = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i += 1) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j += 1) {
      matrix[0][j] = j;
    }
    for (var i = 1; i <= a.length; i += 1) {
      var rowMin = maxDistance + 1;
      for (var j = 1; j <= b.length; j += 1) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var value = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          value = math.min(value, matrix[i - 2][j - 2] + 1);
        }
        matrix[i][j] = value;
        rowMin = math.min(rowMin, value);
      }
      if (rowMin > maxDistance) {
        return maxDistance + 1;
      }
    }
    return matrix[a.length][b.length];
  }

  List<String> _searchTerms(String query) {
    return _normalizeVariationSearchPhrases(query)
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((term) => term.trim())
        .where((term) => term.length >= 2 || term == 'v')
        .toList();
  }

  String _normalizeVariationSearchPhrases(String value) {
    return value
        .replaceAll(RegExp(r'\blv\s*\.?\s*x\b', caseSensitive: false), 'lvx')
        .replaceAll(RegExp(r'\blevel\s+x\b', caseSensitive: false), 'lvx')
        .replaceAll(RegExp(r'\bv\s*max\b', caseSensitive: false), 'vmax')
        .replaceAll(RegExp(r'\bv\s*star\b', caseSensitive: false), 'vstar')
        .replaceAll(RegExp(r'\bg\s*x\b', caseSensitive: false), 'gx')
        .replaceAll(RegExp(r'\be\s*x\b', caseSensitive: false), 'ex');
  }

  bool _isVariationSearchTerm(String term) {
    const variations = {
      'ex',
      'v',
      'vmax',
      'vstar',
      'gx',
      'lvx',
      'lv',
      'mega',
      'break',
      'radiant',
      'shining',
      'shiny',
      'prime',
    };
    return variations.contains(term.replaceAll(RegExp(r'[^a-z0-9]'), ''));
  }

  bool _cardHasVariation(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final text = [
      card.name,
      card.rarity,
      card.type,
      card.productType,
      ...card.tags,
    ].join(' ').toLowerCase();
    final compact = text.replaceAll(RegExp(r'[^a-z0-9]'), '');
    switch (normalizedTerm) {
      case 'lvx':
        return RegExp(r'(^|[^a-z0-9])(lv\.?x|level x)([^a-z0-9]|$)')
            .hasMatch(text);
      case 'lv':
        return RegExp(r'(^|[^a-z0-9])lv\.?([0-9]+|x)([^a-z0-9]|$)')
            .hasMatch(text);
      case 'v':
        return RegExp(r'(^|[^a-z0-9])v([^a-z0-9]|$)').hasMatch(text);
      default:
        return RegExp('(^|[^a-z0-9])$normalizedTerm([^a-z0-9]|\$)')
                .hasMatch(text) ||
            compact.contains(normalizedTerm);
    }
  }

  bool _isRaritySearchTerm(String term) {
    const rarities = {
      'sir',
      'ir',
      'ur',
      'sr',
      'rare',
      'ultra',
      'secret',
      'illustration',
      'holo',
      'shiny',
    };
    return rarities.contains(term.replaceAll(RegExp(r'[^a-z0-9]'), ''));
  }

  bool _cardHasRarityHint(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final text = [
      card.number,
      card.rarity,
      ...card.tags,
    ].join(' ').toLowerCase();
    final normalizedText = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    switch (normalizedTerm) {
      case 'sir':
        return normalizedText.contains('special illustration rare');
      case 'ir':
        return normalizedText.contains('illustration rare');
      case 'ur':
      case 'ultra':
        return normalizedText.contains('ultra rare');
      case 'sr':
      case 'secret':
        return normalizedText.contains('secret rare');
      default:
        return normalizedText.contains(normalizedTerm);
    }
  }

  List<String> _expansionAliasTargets(String term) {
    const aliases = {
      'col': ['calloflegends'],
      'calllegends': ['calloflegends'],
      'calloflegends': ['calloflegends'],
      '151': ['151', 'pokemoncard151', 'collect151'],
      'pokemon151': ['pokemoncard151'],
      'pokemoncard151': ['pokemoncard151'],
      'collect151': ['collect151'],
      'cel': ['celebrations'],
      'pal': ['paldeaevolved'],
      'obf': ['obsidianflames'],
      'obs': ['obsidianflames'],
      'svi': ['scarletviolet'],
      'sv': ['scarletviolet'],
    };
    return aliases[term.replaceAll(RegExp(r'[^a-z0-9]'), '')] ?? const [];
  }

  bool _isExpansionAliasSearchTerm(String term) {
    return _expansionAliasTargets(term).isNotEmpty;
  }

  bool _cardHasExpansionAlias(PokemonCard card, String term) {
    final compactSet = card.set.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _expansionAliasTargets(term).any(
      (target) => compactSet == target ||
          compactSet.startsWith(target) ||
          target.startsWith(compactSet),
    );
  }

  bool _isLikelyNameTypo(String compactName, String compactTerm) {
    if (compactTerm.length < 5 || compactName.isEmpty) {
      return false;
    }
    return compactName.startsWith(compactTerm.substring(0, 2)) &&
        _boundedDamerauLevenshtein(compactName, compactTerm, 3) <= 3;
  }

  List<String> _searchQueryVariants(Iterable<String> queries) {
    final variants = <String>[];
    for (final query in queries) {
      final normalized = query.trim().toLowerCase();
      if (_meaningfulSearchLength(normalized) < 1) {
        continue;
      }
      _addUnique(variants, normalized);
      final expanded = _expandCompactSearchAliases(normalized);
      _addUnique(variants, expanded);
      for (final localizedAlias in _localizedAliasQueryVariants(normalized)) {
        _addUnique(variants, localizedAlias);
      }
      for (final trainerVariant in _trainerQueryVariants(normalized)) {
        _addUnique(variants, trainerVariant);
      }
      for (final alias in _raritySearchAliases.entries) {
        if (_containsCompactAlias(normalized, alias.key)) {
          _addUnique(variants, alias.value);
          _addUnique(
            variants,
            _expandCompactSearchAliases(
              normalized.replaceAll(alias.key, alias.value),
            ),
          );
        }
      }
    }
    return variants;
  }

  int _meaningfulSearchLength(String query) {
    return RegExp(r'[a-z0-9]', caseSensitive: false).allMatches(query).length;
  }

  List<String> _localizedAliasQueryVariants(String query) {
    final terms = _searchTerms(query);
    if (terms.isEmpty) {
      return const [];
    }
    final variants = <String>[];
    for (var i = 0; i < terms.length; i += 1) {
      final canonicalTrainer = _trainerSearchAliases[terms[i]];
      if (canonicalTrainer == null || canonicalTrainer == terms[i]) {
        continue;
      }
      final rewritten = [...terms];
      rewritten[i] = canonicalTrainer;
      _addUnique(variants, rewritten.join(' '));
      _addUnique(variants, canonicalTrainer);
    }
    return variants;
  }

  String _expandCompactSearchAliases(String query) {
    var expanded = query;
    for (final alias in _raritySearchAliases.entries) {
      expanded = expanded.replaceAllMapped(
        RegExp('(^|[^a-z0-9])${alias.key}([^a-z0-9]|\$)'),
        (match) => '${match.group(1)}${alias.value}${match.group(2)}',
      );
    }
    return expanded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _trainerQueryVariants(String query) {
    final terms = _searchTerms(query);
    if (terms.length < 2) {
      return const [];
    }
    final variants = <String>[];
    for (var i = 0; i < terms.length; i += 1) {
      final canonicalTrainer = _trainerSearchAliases[terms[i]];
      if (canonicalTrainer == null) {
        continue;
      }
      final pokemonTerms = [
        for (var j = 0; j < terms.length; j += 1)
          if (j != i && !_ownershipStopWords.contains(terms[j])) terms[j],
      ];
      if (pokemonTerms.isEmpty) {
        _addUnique(variants, canonicalTrainer);
        continue;
      }
      final pokemonQuery = pokemonTerms.join(' ');
      _addUnique(variants, '$pokemonQuery $canonicalTrainer');
      _addUnique(variants, '$canonicalTrainer $pokemonQuery');
      _addUnique(variants, "$canonicalTrainer's $pokemonQuery");
    }
    return variants;
  }

  bool _containsCompactAlias(String query, String alias) {
    return RegExp('(^|[^a-z0-9])$alias([^a-z0-9]|\$)').hasMatch(query);
  }

  void _addUnique(List<String> values, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length >= 2 && !values.contains(normalized)) {
      values.add(normalized);
    }
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

  Map<String, dynamic> toJson() {
    return {
      'cards': cards.map((card) => card.toJson()).toList(),
      'sections': sections.toJson(),
    };
  }
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

  Map<String, dynamic> toJson() {
    return {
      'recentlySeenIds': recentlySeenIds,
      'bestSellerIds': bestSellerIds,
      'featuredIds': featuredIds,
    };
  }
}
