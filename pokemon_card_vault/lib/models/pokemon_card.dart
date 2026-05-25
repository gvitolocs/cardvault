import 'package:hive/hive.dart';

part 'pokemon_card.g.dart';

@HiveType(typeId: 0)
class PokemonCard extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String imageUrl;

  @HiveField(3)
  final String rarity;

  @HiveField(4)
  final String type;

  @HiveField(5)
  final int hp;

  @HiveField(6)
  final List<String> attacks;

  @HiveField(7)
  final double price;

  @HiveField(8)
  final String description;

  @HiveField(9)
  final String set;

  @HiveField(10)
  final String number;

  @HiveField(11)
  final String artist;

  @HiveField(12)
  final int stock;

  @HiveField(13)
  final double rating;

  @HiveField(14)
  final int reviewCount;

  @HiveField(15)
  final bool isFoil;

  @HiveField(16)
  final bool isHolo;

  @HiveField(17)
  final DateTime releaseDate;

  @HiveField(18)
  final List<String> tags;

  @HiveField(19)
  final String condition;

  @HiveField(20)
  final bool isGraded;

  @HiveField(21)
  final String? grade;

  @HiveField(22)
  final String? gradingCompany;

  @HiveField(23)
  final String previewImageUrl;

  @HiveField(24)
  final String itemKind;

  @HiveField(25)
  final String productType;

  @HiveField(26)
  final String trainerName;

  @HiveField(27)
  final String expansionSymbolUrl;

  @HiveField(28)
  final Map<String, dynamic> cardPalette;

  @HiveField(29)
  final String emoji;

  @HiveField(30)
  final String homepageImageUrl;

  @HiveField(31)
  final String expansionLogoUrl;

  @HiveField(32)
  final String canonicalPath;

  @HiveField(33)
  final bool hasCardTraderListing;

  @HiveField(34)
  final int cardtraderEligibleListingCount;

  @HiveField(35)
  final int watchlistCount;

  @HiveField(36)
  final int cartHolderCount;

  PokemonCard({
    required this.id,
    required this.name,
    required this.imageUrl,
    String? previewImageUrl,
    String? homepageImageUrl,
    required this.rarity,
    required this.type,
    required this.hp,
    required this.attacks,
    required this.price,
    required this.description,
    required this.set,
    required this.number,
    required this.artist,
    required this.stock,
    required this.rating,
    required this.reviewCount,
    required this.isFoil,
    required this.isHolo,
    required this.releaseDate,
    required this.tags,
    required this.condition,
    required this.isGraded,
    this.grade,
    this.gradingCompany,
    this.itemKind = 'single',
    this.productType = 'card',
    this.trainerName = '',
    this.expansionSymbolUrl = '',
    this.expansionLogoUrl = '',
    this.canonicalPath = '',
    this.hasCardTraderListing = false,
    this.cardtraderEligibleListingCount = 0,
    this.watchlistCount = 0,
    this.cartHolderCount = 0,
    Map<String, dynamic>? cardPalette,
    this.emoji = '',
  })  : previewImageUrl = previewImageUrl ?? imageUrl,
        homepageImageUrl = homepageImageUrl ?? previewImageUrl ?? imageUrl,
        cardPalette = Map<String, dynamic>.from(cardPalette ?? const {});

  factory PokemonCard.fromJson(Map<String, dynamic> json) {
    return PokemonCard(
      id: _readString(json, const ['id', 'card_id']),
      name: _readString(json, const ['name']),
      imageUrl: _readString(json, const ['imageUrl', 'image_url']),
      previewImageUrl: _readString(
        json,
        const ['previewImageUrl', 'preview_image_url', 'imageUrl', 'image_url'],
      ),
      homepageImageUrl: json['homepageImageUrl'] ??
          json['homepage_image_url'] ??
          json['previewImageUrl'] ??
          json['preview_image_url'] ??
          json['imageUrl'] ??
          json['image_url'] ??
          '',
      rarity: _readString(json, const [
        'rarity',
        'collector_rarity',
        'pokemon_rarity',
      ]),
      type: _readString(json, const ['type', 'cardType', 'card_type']),
      hp: json['hp'] ?? 0,
      attacks: List<String>.from(json['attacks'] ?? []),
      price: _readDouble(json, const [
        'price',
        'lowestPricePkn',
        'lowest_price_pkn',
        'cardtraderLowestPricePkn',
        'cardtrader_lowest_price_pkn',
      ]),
      description: json['description'] ?? '',
      set: _readString(
        json,
        const ['set', 'setName', 'set_name', 'expansionName', 'expansion_name'],
      ),
      number: _readString(json, const [
        'number',
        'cardNumber',
        'card_number',
        'expansionNumber',
        'expansion_number',
      ]),
      artist: json['artist'] ?? '',
      stock: _readInt(json, const ['stock', 'listed_quantity']),
      rating: _readDouble(json, const ['rating', 'watchlistCount', 'watchlist_count']),
      reviewCount: json['reviewCount'] ?? 0,
      isFoil: json['isFoil'] ?? false,
      isHolo: json['isHolo'] ?? false,
      releaseDate: DateTime.parse(
          json['releaseDate'] ?? DateTime.now().toIso8601String()),
      tags: List<String>.from(json['tags'] ?? []),
      condition: json['condition'] ?? 'NM',
      isGraded: json['isGraded'] ?? false,
      grade: json['grade'],
      gradingCompany: json['gradingCompany'],
      itemKind: json['itemKind'] ?? 'single',
      productType: json['productType'] ?? json['product_type'] ?? 'card',
      trainerName: json['trainerName'] ?? json['trainer_name'] ?? '',
      expansionSymbolUrl:
          json['expansionSymbolUrl'] ?? json['expansion_symbol_url'] ?? '',
      expansionLogoUrl:
          json['expansionLogoUrl'] ?? json['expansion_logo_url'] ?? '',
      canonicalPath: _readString(json, const [
        'canonicalPath',
        'canonical_path',
        'marketplacePath',
        'marketplace_path',
        'cardUrl',
        'card_url',
      ]),
      hasCardTraderListing: _readBool(json, const [
        'hasCardTraderListing',
        'has_cardtrader_listing',
        'cardtraderAvailable',
        'cardtrader_available',
      ]),
      cardtraderEligibleListingCount: _readInt(json, const [
        'cardtraderEligibleListingCount',
        'cardtrader_eligible_listing_count',
      ]),
      watchlistCount: _readWatchlistCount(json),
      cartHolderCount: _readCartHolderCount(json),
      cardPalette: _readCardPalette(json),
      emoji: _readCardEmoji(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'previewImageUrl': previewImageUrl,
      'homepageImageUrl': homepageImageUrl,
      'rarity': rarity,
      'type': type,
      'hp': hp,
      'attacks': attacks,
      'price': price,
      'description': description,
      'set': set,
      'number': number,
      'artist': artist,
      'stock': stock,
      'rating': rating,
      'reviewCount': reviewCount,
      'isFoil': isFoil,
      'isHolo': isHolo,
      'releaseDate': releaseDate.toIso8601String(),
      'tags': tags,
      'condition': condition,
      'isGraded': isGraded,
      'grade': grade,
      'gradingCompany': gradingCompany,
      'itemKind': itemKind,
      'productType': productType,
      'trainerName': trainerName,
      'expansionSymbolUrl': expansionSymbolUrl,
      'expansionLogoUrl': expansionLogoUrl,
      'canonicalPath': canonicalPath,
      'hasCardTraderListing': hasCardTraderListing,
      'cardtraderEligibleListingCount': cardtraderEligibleListingCount,
      'watchlistCount': watchlistCount,
      'cartHolderCount': cartHolderCount,
      'cardPalette': cardPalette,
      'emoji': emoji,
    };
  }

  PokemonCard copyWith({
    String? id,
    String? name,
    String? imageUrl,
    String? previewImageUrl,
    String? homepageImageUrl,
    String? rarity,
    String? type,
    int? hp,
    List<String>? attacks,
    double? price,
    String? description,
    String? set,
    String? number,
    String? artist,
    int? stock,
    double? rating,
    int? reviewCount,
    bool? isFoil,
    bool? isHolo,
    DateTime? releaseDate,
    List<String>? tags,
    String? condition,
    bool? isGraded,
    String? grade,
    String? gradingCompany,
    String? itemKind,
    String? productType,
    String? trainerName,
    String? expansionSymbolUrl,
    String? expansionLogoUrl,
    String? canonicalPath,
    bool? hasCardTraderListing,
    int? cardtraderEligibleListingCount,
    int? watchlistCount,
    int? cartHolderCount,
    Map<String, dynamic>? cardPalette,
    String? emoji,
  }) {
    return PokemonCard(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      previewImageUrl: previewImageUrl ?? this.previewImageUrl,
      homepageImageUrl: homepageImageUrl ?? this.homepageImageUrl,
      rarity: rarity ?? this.rarity,
      type: type ?? this.type,
      hp: hp ?? this.hp,
      attacks: attacks ?? this.attacks,
      price: price ?? this.price,
      description: description ?? this.description,
      set: set ?? this.set,
      number: number ?? this.number,
      artist: artist ?? this.artist,
      stock: stock ?? this.stock,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isFoil: isFoil ?? this.isFoil,
      isHolo: isHolo ?? this.isHolo,
      releaseDate: releaseDate ?? this.releaseDate,
      tags: tags ?? this.tags,
      condition: condition ?? this.condition,
      isGraded: isGraded ?? this.isGraded,
      grade: grade ?? this.grade,
      gradingCompany: gradingCompany ?? this.gradingCompany,
      itemKind: itemKind ?? this.itemKind,
      productType: productType ?? this.productType,
      trainerName: trainerName ?? this.trainerName,
      expansionSymbolUrl: expansionSymbolUrl ?? this.expansionSymbolUrl,
      expansionLogoUrl: expansionLogoUrl ?? this.expansionLogoUrl,
      canonicalPath: canonicalPath ?? this.canonicalPath,
      hasCardTraderListing: hasCardTraderListing ?? this.hasCardTraderListing,
      cardtraderEligibleListingCount:
          cardtraderEligibleListingCount ?? this.cardtraderEligibleListingCount,
      watchlistCount: watchlistCount ?? this.watchlistCount,
      cartHolderCount: cartHolderCount ?? this.cartHolderCount,
      cardPalette: cardPalette ?? this.cardPalette,
      emoji: emoji ?? this.emoji,
    );
  }

  bool get isMarketAvailable =>
      stock > 0 || hasCardTraderListing || cardtraderEligibleListingCount > 0;

  int get starMetricCount =>
      watchlistCount > 0 ? watchlistCount : rating.round();

  int get cartMetricCount => cartHolderCount > 0 ? cartHolderCount : 0;

  static Map<String, dynamic> _readCardPalette(Map<String, dynamic> json) {
    final value = json['cardPalette'] ?? json['card_palette'];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  static int _readWatchlistCount(Map<String, dynamic> json) {
    final direct = _readInt(json, const [
      'watchlistCount',
      'watchlist_count',
    ]);
    if (direct > 0) {
      return direct;
    }
    final analytics = json['analytics'];
    if (analytics is Map<String, dynamic>) {
      return _readInt(analytics, const [
        'watchlistCount',
        'watchlist_count',
      ]);
    }
    if (analytics is Map) {
      return _readInt(Map<String, dynamic>.from(analytics), const [
        'watchlistCount',
        'watchlist_count',
      ]);
    }
    final rating = json['rating'];
    if (rating is num) {
      return rating > 0 ? rating.toInt() : 0;
    }
    return 0;
  }

  static int _readCartHolderCount(Map<String, dynamic> json) {
    final direct = _readInt(json, const [
      'cartHolderCount',
      'cart_holder_count',
    ]);
    if (direct > 0) {
      return direct;
    }
    final analytics = json['analytics'];
    if (analytics is Map<String, dynamic>) {
      return _readInt(analytics, const [
        'cartHolderCount',
        'cart_holder_count',
      ]);
    }
    if (analytics is Map) {
      return _readInt(Map<String, dynamic>.from(analytics), const [
        'cartHolderCount',
        'cart_holder_count',
      ]);
    }
    return 0;
  }

  static String _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static bool _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value > 0;
      }
      final text = '${value ?? ''}'.trim().toLowerCase();
      if (const {'true', '1', 'yes', 'y'}.contains(text)) {
        return true;
      }
    }
    return false;
  }

  static int _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) {
        return value.toInt();
      }
      final parsed = int.tryParse('${value ?? ''}'.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return 0;
  }

  static double _readDouble(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) {
        return value.toDouble();
      }
      final parsed = double.tryParse('${value ?? ''}'.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return 0;
  }

  static String _readCardEmoji(Map<String, dynamic> json) {
    final identity = _readEmojiList(
      json['cardIdentityEmojis'] ?? json['card_identity_emojis'],
    );
    final identityText = _readString(json, const [
      'cardIdentityEmoji',
      'card_identity_emoji',
    ]);
    if (identity.isEmpty && identityText.isNotEmpty) {
      identity.addAll(_splitEmojiText(identityText));
    }

    final variant = _readString(json, const [
      'rarityVariantEmoji',
      'rarity_variant_emoji',
      'variantEmoji',
      'variant_emoji',
    ]);
    final fallback = _splitEmojiText(json['emoji']);
    final tokens = <String>[];
    for (final token in identity) {
      if (!tokens.contains(token)) {
        tokens.add(token);
      }
      if (tokens.length == 2) {
        break;
      }
    }
    if (tokens.length < 2) {
      for (final token in fallback.where((token) => !_isVariantEmoji(token))) {
        if (!tokens.contains(token)) {
          tokens.add(token);
        }
        if (tokens.length == 2) {
          break;
        }
      }
    }
    if (tokens.length < 2) {
      for (final token in _fallbackIdentityEmojis(json)) {
        if (!tokens.contains(token)) {
          tokens.add(token);
        }
        if (tokens.length == 2) {
          break;
        }
      }
    }
    final variantTokens = _splitEmojiText(variant);
    final variantToken =
        (variantTokens.isNotEmpty ? variantTokens.first : null) ??
            _rarityVariantEmoji(json) ??
            fallback.firstWhere(_isVariantEmoji, orElse: () => '');
    if (variantToken.isNotEmpty) {
      tokens.add(variantToken);
    }
    return tokens.join(' ').trim();
  }

  static List<String> _readEmojiList(Object? value) {
    if (value is! List) {
      return <String>[];
    }
    return value.expand(_splitEmojiText).toList(growable: true);
  }

  static List<String> _splitEmojiText(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) {
      return const <String>[];
    }
    final matches =
        RegExp(r'\S(?:[\uFE0F\u{1F3FB}-\u{1F3FF}]|\u200D\S)*', unicode: true)
            .allMatches(text);
    return matches
        .map((match) => match.group(0)!.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static bool _isVariantEmoji(String token) {
    return const {
      '👑',
      '🌟',
      '💥',
      '💎',
      '⬆️',
      '🛡️',
      '✨',
      '🌈',
      '🔺',
      '🔻',
      '🤝',
      '🏅',
      '⚡',
      '🎨',
      '🎟️',
      '🏆',
      '⭐',
      '🔷',
      '⚪',
    }.contains(token);
  }

  static List<String> _fallbackIdentityEmojis(Map<String, dynamic> json) {
    final text =
        '${json['name'] ?? ''} ${json['card_type'] ?? json['type'] ?? ''}'
            .toLowerCase();
    if (RegExp(
            r'leafeon|eevee|vaporeon|jolteon|flareon|espeon|umbreon|glaceon|sylveon')
        .hasMatch(text)) {
      return const ['🦊', '✨'];
    }
    if (RegExp(
            r'drifloon|drifblim|gastly|haunter|gengar|mismagius|mimikyu|duskull|dusknoir')
        .hasMatch(text)) {
      return const ['👻', '🌫️'];
    }
    if (RegExp(
            r'meltan|melmetal|magnemite|magneton|magnezone|beldum|metang|metagross|klink|klang|klinklang')
        .hasMatch(text)) {
      return const ['⚙️', '🔩'];
    }
    if (text.contains('cresselia')) {
      return const ['🌙', '🔮'];
    }
    if (RegExp(r'mewtwo|mew|lunala|solgaleo|jirachi|celebi').hasMatch(text)) {
      return const ['🔮', '✨'];
    }
    return const ['🃏', '✨'];
  }

  static String? _rarityVariantEmoji(Map<String, dynamic> json) {
    final text = [
      json['rarity'],
      json['product_variant'],
      json['productVariant'],
      json['number'],
      json['card_number'],
      json['expansion_number'],
      json['name'],
    ].map((value) => '${value ?? ''}'.toLowerCase()).join(' ');
    if (RegExp(r'promo|stamped|stamp').hasMatch(text)) return '🎟️';
    if (RegExp(
            r'special illustration rare|special art rare|illustration rare|art rare|alternate art|alt art|full[- ]?art')
        .hasMatch(text)) {
      return '🎨';
    }
    if (RegExp(r'gold secret|secret rare|hyper rare|gold').hasMatch(text)) {
      return '🏆';
    }
    if (RegExp(r'shining|shiny|holo|foil|reverse').hasMatch(text)) return '✨';
    if (RegExp(r'(^|[^a-z0-9])(vmax|v max)([^a-z0-9]|$)').hasMatch(text)) {
      return '👑';
    }
    if (RegExp(r'(^|[^a-z0-9])(vstar|v star)([^a-z0-9]|$)').hasMatch(text)) {
      return '🌟';
    }
    if (RegExp(r'(^|[^a-z0-9])(gx|g x)([^a-z0-9]|$)').hasMatch(text)) {
      return '💥';
    }
    if (RegExp(r'(^|[^a-z0-9])(ex|e x)([^a-z0-9]|$)').hasMatch(text)) {
      return '💎';
    }
    if (RegExp(r'(^|[^a-z0-9])rare([^a-z0-9]|$)').hasMatch(text)) return '⭐';
    if (RegExp(r'(^|[^a-z0-9])uncommon([^a-z0-9]|$)').hasMatch(text)) {
      return '🔷';
    }
    if (RegExp(r'(^|[^a-z0-9])common([^a-z0-9]|$)').hasMatch(text)) return '⚪';
    return null;
  }
}
