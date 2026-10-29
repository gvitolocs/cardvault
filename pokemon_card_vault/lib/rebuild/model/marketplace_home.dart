/// Metadati dei due slider: nessuna dipendenza da Hive, Firebase o widget.
class MarketplaceExpansion {
  const MarketplaceExpansion({
    required this.name,
    required this.slug,
    required this.cardCount,
    this.imageUrl = '',
    this.releaseDate,
    this.expansionId,
  });

  factory MarketplaceExpansion.fromJson(Map<String, dynamic> json) =>
      MarketplaceExpansion(
        name: '${json['name'] ?? ''}'.trim(),
        slug: '${json['slug'] ?? ''}'.trim(),
        cardCount: int.tryParse('${json['cardCount'] ?? 0}') ?? 0,
        imageUrl: _firstText(
            json, ['logoImageUrl', 'symbolImageUrl', 'defaultSymbolUrl']),
        releaseDate: DateTime.tryParse(
            '${json['releaseDate'] ?? json['release_date'] ?? ''}'),
        expansionId: int.tryParse(
            '${json['expansionId'] ?? json['expansion_id'] ?? ''}'),
      );

  final String name;
  final String slug;
  final int cardCount;
  final String imageUrl;
  final DateTime? releaseDate;
  final int? expansionId;
}

/// Anteprima del catalogo reale, separata da DemoCard e dal carrello demo.
class MarketplaceCardPreview {
  const MarketplaceCardPreview({
    required this.id,
    required this.name,
    required this.expansion,
    this.number = '',
    this.imageUrl = '',
    this.fullImageUrl = '',
    this.pricePkn,
    this.canonicalPath = '',
    this.imageLanguage = '',
  });

  factory MarketplaceCardPreview.fromJson(Map<String, dynamic> json) {
    final rawPrice = _firstText(json, [
      'price',
      'lowestPricePkn',
      'lowest_price_pkn',
      'cardtraderLowestPricePkn',
      'cardtrader_lowest_price_pkn',
    ]);
    final price = double.tryParse(rawPrice);
    return MarketplaceCardPreview(
      // L'API restituisce già l'ID canonico Pokoin: non moltiplicarlo.
      id: '${json['id'] ?? json['card_id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      expansion: _firstText(json,
          ['set', 'setName', 'set_name', 'expansionName', 'expansion_name']),
      number: _firstText(
          json, ['number', 'cardNumber', 'card_number', 'expansion_number']),
      imageUrl: _firstText(json, [
        'homepageImageUrl',
        'homepage_image_url',
        'tileImageUrl',
        'tile_image_url',
        'previewImageUrl',
        'preview_image_url',
        'imageUrl',
        'image_url',
      ]),
      fullImageUrl: _firstText(json, [
        'heroImageUrl',
        'hero_image_url',
        'gridImageUrl',
        'imageUrl',
        'image_url',
        'cdn_image_url',
      ]),
      pricePkn: price != null && price.isFinite && price > 0 ? price : null,
      canonicalPath: _firstText(json, ['canonicalPath', 'canonical_path']),
    );
  }

  final String id;
  final String name;
  final String expansion;
  final String number;
  final String imageUrl;
  final String fullImageUrl;
  // Valore PKN dell'API, senza conversioni o moltiplicatori nel client.
  final double? pricePkn;
  final String canonicalPath;

  /// Local display hint, not proof of ownership or an API listing filter.
  final String imageLanguage;
}

class MarketplaceHomeData {
  MarketplaceHomeData({
    required List<MarketplaceExpansion> expansions,
    required List<MarketplaceCardPreview> topSellers,
    this.expansionsUnavailable = false,
    this.topSellersUnavailable = false,
    this.expansionsLoading = false,
    this.topSellersLoading = false,
    this.expansionsFromCache = false,
    this.topSellersFromCache = false,
    this.refreshFailed = false,
    this.cachedAt,
  })  : expansions = List.unmodifiable(expansions),
        topSellers = List.unmodifiable(topSellers);

  final List<MarketplaceExpansion> expansions;
  final List<MarketplaceCardPreview> topSellers;
  final bool expansionsUnavailable;
  final bool topSellersUnavailable;
  final bool expansionsLoading;
  final bool topSellersLoading;
  final bool expansionsFromCache;
  final bool topSellersFromCache;
  final bool refreshFailed;

  /// Data della sezione salvata più vecchia; null per dati incompleti o di rete.
  final DateTime? cachedAt;
  bool get fromCache => expansionsFromCache || topSellersFromCache;
}

String _firstText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = '${json[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}
