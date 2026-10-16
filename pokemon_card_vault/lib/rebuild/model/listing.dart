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
    final attributes = <String>[];
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
      attributes: List.unmodifiable(attributes),
    );
  }
}
