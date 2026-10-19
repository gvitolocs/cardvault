/// Offerta acquistabile distinta dalla carta del catalogo.
class MarketplaceListing {
  const MarketplaceListing(
      {required this.id,
      required this.cardId,
      required this.sellerName,
      required this.country,
      required this.condition,
      required this.language,
      required this.pricePkn,
      required this.stock,
      this.status = 'active',
      this.comment = '',
      this.sourceData = const {},
      this.attributes = const []});

  final String id,
      cardId,
      sellerName,
      country,
      condition,
      language,
      status,
      comment;
  final double pricePkn;
  final int stock;
  final List<String> attributes;
  // Conserva anche metadati di venditore/provenienza non mostrati nella UI.
  final Map<String, dynamic> sourceData;

  ListingOrigin get origin {
    String text(Object? value) => value is String ? value.trim() : '';
    final source = text(sourceData['source']).toLowerCase();
    final metadata = sourceData['sourceMetadata'];
    final provider = metadata is Map ? text(metadata['provider']) : '';
    final sourceId = text(sourceData['sourceListingId']).toLowerCase();
    // CardTrader viene esposto dal backend tramite il venditore pknreserve:
    // l'origine si ricava dai metadati, non dal nome del venditore.
    if (source.startsWith('cardtrader') ||
        provider.toLowerCase() == 'cardtrader' ||
        id.toLowerCase().startsWith('cardtrader:') ||
        sourceId.startsWith('cardtrader:')) {
      return const ListingOrigin('cardtrader', 'CardTrader');
    }
    if (source.startsWith('pokoin_user')) {
      return const ListingOrigin('pokoin', 'Pokoin');
    }
    if (source == 'reserve' ||
        source == 'pknreserve' ||
        source == 'cardreserve' ||
        source.startsWith('reserve_') ||
        source.startsWith('pokoin_reserve') ||
        sourceId.startsWith('reserve:') ||
        sourceId.startsWith('pknreserve:')) {
      return const ListingOrigin('cardreserve', 'CardReserve');
    }
    final declared =
        provider.isNotEmpty ? provider : text(sourceData['source']);
    if (declared.isEmpty || declared.toLowerCase() == 'unknown') {
      return const ListingOrigin('cardreserve', 'CardReserve');
    }
    final label = declared.replaceAll('_', ' ');
    return ListingOrigin('source:${declared.toLowerCase()}',
        '${label[0].toUpperCase()}${label.substring(1)}');
  }

  Map<String, dynamic> toJson() => {
        ...sourceData,
        'id': id,
        'cardId': cardId,
        'sellerName': sellerName,
        'sellerCountry': country,
        'condition': condition,
        'language': language,
        'pricePkn': pricePkn,
        'quantityAvailable': stock,
        'status': status,
        'sellerComment': comment,
        'attributes': attributes,
      };
  bool get isAvailable =>
      id.isNotEmpty &&
      cardId.isNotEmpty &&
      status == 'active' &&
      stock > 0 &&
      pricePkn.isFinite &&
      pricePkn > 0;

  factory MarketplaceListing.fromJson(Map<String, dynamic> json) {
    String read(String key, [String fallback = '']) =>
        '${json[key] ?? fallback}'.trim();
    final attributes = <String>[
      if (json['attributes'] is List)
        ...(json['attributes'] as List).map((value) => '$value'),
    ];
    for (final entry in const {
      'signed': 'Firmata',
      'reverse': 'Reverse',
      'firstEdition': 'Prima edizione',
      'sealed': 'Sigillata',
      'graded': 'Gradata'
    }.entries) {
      if (json[entry.key] == true) attributes.add(entry.value);
    }
    final foil = read('foilState');
    if (foil.isNotEmpty && foil != 'standard') {
      attributes.add(foil);
    }
    final variant = read('variantState');
    if (variant.isNotEmpty) attributes.add(variant);
    final grade = read('grade');
    if (grade.isNotEmpty) {
      attributes.add('${read('gradingCompany')} $grade'.trim());
    }
    return MarketplaceListing(
      id: read('id'),
      cardId: read('cardId'),
      sellerName: read('sellerName', 'Venditore'),
      country: read('sellerCountry'),
      condition: read('condition'),
      language: read('language'),
      pricePkn: double.tryParse(read('pricePkn')) ?? 0,
      stock: int.tryParse(read('quantityAvailable')) ?? 0,
      status: read('status'),
      comment: read('sellerComment'),
      attributes: List.unmodifiable(attributes.toSet()),
      sourceData: Map.unmodifiable(json),
    );
  }
}

class ListingOrigin {
  const ListingOrigin(this.id, this.label);
  final String id, label;
}
