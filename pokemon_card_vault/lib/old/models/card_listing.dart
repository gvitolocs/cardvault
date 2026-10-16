import 'pokemon_card.dart';

class CardListing {
  const CardListing({
    required this.id,
    required this.cardId,
    required this.sellerUid,
    required this.sellerName,
    required this.sellerCountry,
    required this.sellerReputationLabel,
    required this.condition,
    required this.language,
    required this.pricePkn,
    required this.quantityAvailable,
    required this.signed,
    required this.reverse,
    required this.firstEdition,
    required this.foilState,
    required this.variantState,
    required this.sealed,
    required this.graded,
    this.gradingCompany,
    this.grade,
    this.certificationId,
    required this.shippingAvailable,
    required this.reserveAvailable,
    required this.nftAvailable,
    required this.sellerComment,
    this.source = 'pokoin_user_listing',
    this.sourceListingId = '',
    this.sourceMetadata = const <String, dynamic>{},
    required this.status,
    required this.cardName,
    required this.cardImageUrl,
    required this.setName,
    required this.collectorNumber,
    this.canonicalPath = '',
    this.publicNumber = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String cardId;
  final String sellerUid;
  final String sellerName;
  final String sellerCountry;
  final String sellerReputationLabel;
  final String condition;
  final String language;
  final double pricePkn;
  final int quantityAvailable;
  final bool signed;
  final bool reverse;
  final bool firstEdition;
  final String foilState;
  final String variantState;
  final bool sealed;
  final bool graded;
  final String? gradingCompany;
  final String? grade;
  final String? certificationId;
  final bool shippingAvailable;
  final bool reserveAvailable;
  final bool nftAvailable;
  final String sellerComment;
  final String source;
  final String sourceListingId;
  final Map<String, dynamic> sourceMetadata;
  final String status;
  final String cardName;
  final String cardImageUrl;
  final String setName;
  final String collectorNumber;
  final String canonicalPath;
  final String publicNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active' && quantityAvailable > 0;

  bool get isNftEligible => nftAvailable;

  bool get isCardTraderLinked {
    final normalizedSource = source.trim().toLowerCase();
    final normalizedSourceId = sourceListingId.trim().toLowerCase();
    return normalizedSource == 'cardtrader' ||
        normalizedSource.startsWith('cardtrader') ||
        normalizedSourceId.contains('cardtrader') ||
        normalizedSourceId.contains('cardtrader.com');
  }

  Map<String, dynamic> toSnapshotJson() {
    return {
      'id': id,
      'cardId': cardId,
      'sellerUid': sellerUid,
      'sellerName': sellerName,
      'sellerCountry': sellerCountry,
      'sellerReputationLabel': sellerReputationLabel,
      'condition': condition,
      'language': language,
      'pricePkn': pricePkn,
      'quantityAvailable': quantityAvailable,
      'signed': signed,
      'reverse': reverse,
      'firstEdition': firstEdition,
      'foilState': foilState,
      'variantState': variantState,
      'sealed': sealed,
      'graded': graded,
      'gradingCompany': gradingCompany,
      'grade': grade,
      'certificationId': certificationId,
      'shippingAvailable': shippingAvailable,
      'reserveAvailable': reserveAvailable,
      'nftAvailable': nftAvailable,
      'sellerComment': sellerComment,
      'source': source,
      'sourceListingId': sourceListingId,
      'sourceMetadata': sourceMetadata,
      'status': status,
      'cardName': cardName,
      'cardImageUrl': cardImageUrl,
      'setName': setName,
      'collectorNumber': collectorNumber,
      'canonicalPath': canonicalPath,
      'publicNumber': publicNumber,
    };
  }

  factory CardListing.fromJson(String id, Map<String, dynamic> json) {
    final source = '${json['source'] ?? 'pokoin_user_listing'}';
    final sourceListingId = '${json['sourceListingId'] ?? ''}';
    final reserveAvailable = json['reserveAvailable'] == true;
    final nftAvailable = json['nftAvailable'] == true;
    return CardListing(
      id: id,
      cardId: '${json['cardId'] ?? ''}',
      sellerUid: '${json['sellerUid'] ?? ''}',
      sellerName: _readSellerName(
        json,
        reserveAvailable: reserveAvailable,
        source: source,
        sourceListingId: sourceListingId,
      ),
      sellerCountry: '${json['sellerCountry'] ?? 'EU'}',
      sellerReputationLabel: '${json['sellerReputationLabel'] ?? 'New'}',
      condition: '${json['condition'] ?? 'NM'}',
      language: '${json['language'] ?? 'EN'}',
      pricePkn: (json['pricePkn'] as num?)?.toDouble() ?? 0,
      quantityAvailable: (json['quantityAvailable'] as num?)?.toInt() ?? 0,
      signed: json['signed'] == true,
      reverse: json['reverse'] == true,
      firstEdition: json['firstEdition'] == true,
      foilState: '${json['foilState'] ?? 'standard'}',
      variantState: '${json['variantState'] ?? ''}',
      sealed: json['sealed'] == true,
      graded: json['graded'] == true,
      gradingCompany: json['gradingCompany'] as String?,
      grade: json['grade'] as String?,
      certificationId: json['certificationId'] as String?,
      shippingAvailable: json['shippingAvailable'] != false,
      reserveAvailable: reserveAvailable,
      nftAvailable: nftAvailable,
      sellerComment: '${json['sellerComment'] ?? ''}',
      source: source,
      sourceListingId: sourceListingId,
      sourceMetadata:
          Map<String, dynamic>.from(json['sourceMetadata'] as Map? ?? const {}),
      status: '${json['status'] ?? 'active'}',
      cardName: '${json['cardName'] ?? ''}',
      cardImageUrl: '${json['cardImageUrl'] ?? ''}',
      setName: '${json['setName'] ?? ''}',
      collectorNumber: '${json['collectorNumber'] ?? ''}',
      canonicalPath:
          '${json['canonicalPath'] ?? json['canonical_path'] ?? ''}'.trim(),
      publicNumber:
          '${json['publicNumber'] ?? json['public_number'] ?? ''}'.trim(),
      createdAt: _readDate(json['createdAt']),
      updatedAt: _readDate(json['updatedAt']),
    );
  }

  factory CardListing.draft({
    required PokemonCard card,
    required String sellerUid,
    required String sellerName,
    required String sellerCountry,
    required String sellerReputationLabel,
    required String condition,
    required String language,
    required double pricePkn,
    required int quantityAvailable,
    required bool signed,
    required bool reverse,
    bool firstEdition = false,
    String foilState = 'standard',
    String variantState = '',
    required bool sealed,
    required bool graded,
    String? gradingCompany,
    String? grade,
    String? certificationId,
    required bool shippingAvailable,
    required bool reserveAvailable,
    required bool nftAvailable,
    String sellerComment = '',
    String source = 'pokoin_user_listing',
    String sourceListingId = '',
    Map<String, dynamic> sourceMetadata = const <String, dynamic>{},
  }) {
    return CardListing(
      id: '',
      cardId: card.id,
      sellerUid: sellerUid,
      sellerName: sellerName,
      sellerCountry: sellerCountry,
      sellerReputationLabel: sellerReputationLabel,
      condition: condition,
      language: language,
      pricePkn: pricePkn,
      quantityAvailable: quantityAvailable,
      signed: signed,
      reverse: reverse,
      firstEdition: firstEdition,
      foilState: foilState,
      variantState: variantState,
      sealed: sealed,
      graded: graded,
      gradingCompany: gradingCompany,
      grade: grade,
      certificationId: certificationId,
      shippingAvailable: shippingAvailable,
      reserveAvailable: reserveAvailable,
      nftAvailable: nftAvailable,
      sellerComment: sellerComment,
      source: source,
      sourceListingId: sourceListingId,
      sourceMetadata: sourceMetadata,
      status: 'active',
      cardName: card.name,
      cardImageUrl: card.imageUrl,
      setName: card.set,
      collectorNumber: card.number,
      canonicalPath: card.canonicalPath,
    );
  }

  CardListing copyWith({
    String? id,
    String? cardId,
    String? sellerUid,
    String? sellerName,
    String? sellerCountry,
    String? sellerReputationLabel,
    String? condition,
    String? language,
    double? pricePkn,
    int? quantityAvailable,
    bool? signed,
    bool? reverse,
    bool? firstEdition,
    String? foilState,
    String? variantState,
    bool? sealed,
    bool? graded,
    String? gradingCompany,
    String? grade,
    String? certificationId,
    bool? shippingAvailable,
    bool? reserveAvailable,
    bool? nftAvailable,
    String? sellerComment,
    String? source,
    String? sourceListingId,
    Map<String, dynamic>? sourceMetadata,
    String? status,
    String? cardName,
    String? cardImageUrl,
    String? setName,
    String? collectorNumber,
    String? canonicalPath,
    String? publicNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CardListing(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      sellerUid: sellerUid ?? this.sellerUid,
      sellerName: sellerName ?? this.sellerName,
      sellerCountry: sellerCountry ?? this.sellerCountry,
      sellerReputationLabel:
          sellerReputationLabel ?? this.sellerReputationLabel,
      condition: condition ?? this.condition,
      language: language ?? this.language,
      pricePkn: pricePkn ?? this.pricePkn,
      quantityAvailable: quantityAvailable ?? this.quantityAvailable,
      signed: signed ?? this.signed,
      reverse: reverse ?? this.reverse,
      firstEdition: firstEdition ?? this.firstEdition,
      foilState: foilState ?? this.foilState,
      variantState: variantState ?? this.variantState,
      sealed: sealed ?? this.sealed,
      graded: graded ?? this.graded,
      gradingCompany: gradingCompany ?? this.gradingCompany,
      grade: grade ?? this.grade,
      certificationId: certificationId ?? this.certificationId,
      shippingAvailable: shippingAvailable ?? this.shippingAvailable,
      reserveAvailable: reserveAvailable ?? this.reserveAvailable,
      nftAvailable: nftAvailable ?? this.nftAvailable,
      sellerComment: sellerComment ?? this.sellerComment,
      source: source ?? this.source,
      sourceListingId: sourceListingId ?? this.sourceListingId,
      sourceMetadata: sourceMetadata ?? this.sourceMetadata,
      status: status ?? this.status,
      cardName: cardName ?? this.cardName,
      cardImageUrl: cardImageUrl ?? this.cardImageUrl,
      setName: setName ?? this.setName,
      collectorNumber: collectorNumber ?? this.collectorNumber,
      canonicalPath: canonicalPath ?? this.canonicalPath,
      publicNumber: publicNumber ?? this.publicNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static String _readSellerName(
    Map<String, dynamic> json, {
    required bool reserveAvailable,
    required String source,
    required String sourceListingId,
  }) {
    final currentName = '${json['sellerDisplayName'] ?? ''}'.trim();
    if (currentName.isNotEmpty) {
      return currentName;
    }
    final normalizedSource = source.trim().toLowerCase();
    final normalizedSourceId = sourceListingId.trim().toLowerCase();
    if (reserveAvailable ||
        normalizedSource.startsWith('cardtrader') ||
        normalizedSourceId.contains('cardtrader')) {
      return 'pknreserve';
    }
    final profileName = '${json['profileDisplayName'] ?? ''}'.trim();
    if (profileName.isNotEmpty) {
      return profileName;
    }
    final profileUsername = '${json['profileUsername'] ?? ''}'.trim();
    if (profileUsername.isNotEmpty) {
      return profileUsername;
    }
    final sellerName = '${json['sellerName'] ?? ''}'.trim();
    return sellerName.isEmpty ? 'Pokoin seller' : sellerName;
  }
}
