import 'package:cloud_firestore/cloud_firestore.dart';

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
    required this.graded,
    this.gradingCompany,
    this.grade,
    this.certificationId,
    required this.shippingAvailable,
    required this.nftAvailable,
    required this.status,
    required this.cardName,
    required this.cardImageUrl,
    required this.setName,
    required this.collectorNumber,
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
  final bool graded;
  final String? gradingCompany;
  final String? grade;
  final String? certificationId;
  final bool shippingAvailable;
  final bool nftAvailable;
  final String status;
  final String cardName;
  final String cardImageUrl;
  final String setName;
  final String collectorNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'active' && quantityAvailable > 0;

  Map<String, dynamic> toFirestore() {
    return {
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
      'graded': graded,
      'gradingCompany': gradingCompany,
      'grade': grade,
      'certificationId': certificationId,
      'shippingAvailable': shippingAvailable,
      'nftAvailable': nftAvailable,
      'status': status,
      'cardName': cardName,
      'cardImageUrl': cardImageUrl,
      'setName': setName,
      'collectorNumber': collectorNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    };
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
      'graded': graded,
      'gradingCompany': gradingCompany,
      'grade': grade,
      'certificationId': certificationId,
      'shippingAvailable': shippingAvailable,
      'nftAvailable': nftAvailable,
      'status': status,
      'cardName': cardName,
      'cardImageUrl': cardImageUrl,
      'setName': setName,
      'collectorNumber': collectorNumber,
    };
  }

  factory CardListing.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return CardListing.fromJson(document.id, document.data() ?? const {});
  }

  factory CardListing.fromJson(String id, Map<String, dynamic> json) {
    return CardListing(
      id: id,
      cardId: '${json['cardId'] ?? ''}',
      sellerUid: '${json['sellerUid'] ?? ''}',
      sellerName: '${json['sellerName'] ?? 'Pokoin seller'}',
      sellerCountry: '${json['sellerCountry'] ?? 'EU'}',
      sellerReputationLabel: '${json['sellerReputationLabel'] ?? 'New'}',
      condition: '${json['condition'] ?? 'NM'}',
      language: '${json['language'] ?? 'EN'}',
      pricePkn: (json['pricePkn'] as num?)?.toDouble() ?? 0,
      quantityAvailable: (json['quantityAvailable'] as num?)?.toInt() ?? 0,
      signed: json['signed'] == true,
      reverse: json['reverse'] != false,
      graded: json['graded'] == true,
      gradingCompany: json['gradingCompany'] as String?,
      grade: json['grade'] as String?,
      certificationId: json['certificationId'] as String?,
      shippingAvailable: json['shippingAvailable'] != false,
      nftAvailable: json['nftAvailable'] == true,
      status: '${json['status'] ?? 'active'}',
      cardName: '${json['cardName'] ?? ''}',
      cardImageUrl: '${json['cardImageUrl'] ?? ''}',
      setName: '${json['setName'] ?? ''}',
      collectorNumber: '${json['collectorNumber'] ?? ''}',
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
    required bool graded,
    String? gradingCompany,
    String? grade,
    String? certificationId,
    required bool shippingAvailable,
    required bool nftAvailable,
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
      graded: graded,
      gradingCompany: gradingCompany,
      grade: grade,
      certificationId: certificationId,
      shippingAvailable: shippingAvailable,
      nftAvailable: nftAvailable,
      status: 'active',
      cardName: card.name,
      cardImageUrl: card.imageUrl,
      setName: card.set,
      collectorNumber: card.number,
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
