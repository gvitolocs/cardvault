import 'package:cloud_firestore/cloud_firestore.dart';

import 'card_listing.dart';
import 'pokemon_card.dart';

class UserCardCollectionItem {
  const UserCardCollectionItem({
    required this.id,
    required this.uid,
    required this.cardId,
    required this.quantity,
    required this.condition,
    required this.language,
    required this.firstEdition,
    required this.holo,
    required this.reverse,
    required this.graded,
    this.gradingCompany,
    this.grade,
    this.certificationId,
    required this.cardName,
    required this.cardImageUrl,
    required this.setName,
    required this.collectorNumber,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String uid;
  final String cardId;
  final int quantity;
  final String condition;
  final String language;
  final bool firstEdition;
  final bool holo;
  final bool reverse;
  final bool graded;
  final String? gradingCompany;
  final String? grade;
  final String? certificationId;
  final String cardName;
  final String cardImageUrl;
  final String setName;
  final String collectorNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'cardId': cardId,
      'blueprintId': cardId,
      'quantity': quantity,
      'condition': condition,
      'language': language,
      'firstEdition': firstEdition,
      'holo': holo,
      'reverse': reverse,
      'graded': graded,
      'gradingCompany': gradingCompany,
      'grade': grade,
      'certificationId': certificationId,
      'cardName': cardName,
      'cardImageUrl': cardImageUrl,
      'setName': setName,
      'collectorNumber': collectorNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory UserCardCollectionItem.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return UserCardCollectionItem.fromJson(
      document.id,
      document.data() ?? const {},
    );
  }

  factory UserCardCollectionItem.fromJson(
    String id,
    Map<String, dynamic> json,
  ) {
    return UserCardCollectionItem(
      id: id,
      uid: '${json['uid'] ?? ''}',
      cardId: '${json['cardId'] ?? json['blueprintId'] ?? ''}',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      condition: '${json['condition'] ?? 'NM'}',
      language: '${json['language'] ?? 'EN'}',
      firstEdition: json['firstEdition'] == true,
      holo: json['holo'] == true,
      reverse: json['reverse'] == true,
      graded: json['graded'] == true,
      gradingCompany: json['gradingCompany'] as String?,
      grade: json['grade'] as String?,
      certificationId: json['certificationId'] as String?,
      cardName: '${json['cardName'] ?? ''}',
      cardImageUrl: '${json['cardImageUrl'] ?? ''}',
      setName: '${json['setName'] ?? ''}',
      collectorNumber: '${json['collectorNumber'] ?? ''}',
      createdAt: _readDate(json['createdAt']),
      updatedAt: _readDate(json['updatedAt']),
    );
  }

  factory UserCardCollectionItem.fromCard({
    required PokemonCard card,
    required String uid,
    int quantity = 1,
    String condition = 'NM',
    String language = 'EN',
    bool firstEdition = false,
    bool? holo,
    bool reverse = false,
    bool graded = false,
    String? gradingCompany,
    String? grade,
    String? certificationId,
  }) {
    return UserCardCollectionItem(
      id: '',
      uid: uid,
      cardId: card.id,
      quantity: quantity,
      condition: condition,
      language: language,
      firstEdition: firstEdition,
      holo: holo ?? card.isHolo,
      reverse: reverse,
      graded: graded,
      gradingCompany: gradingCompany,
      grade: grade,
      certificationId: certificationId,
      cardName: card.name,
      cardImageUrl: card.imageUrl,
      setName: card.set,
      collectorNumber: card.number,
    );
  }

  factory UserCardCollectionItem.fromListing({
    required CardListing listing,
    required String uid,
    int? quantity,
    bool firstEdition = false,
    bool? holo,
  }) {
    return UserCardCollectionItem(
      id: '',
      uid: uid,
      cardId: listing.cardId,
      quantity: quantity ?? listing.quantityAvailable,
      condition: listing.condition,
      language: listing.language,
      firstEdition: firstEdition,
      holo: holo ?? false,
      reverse: listing.reverse,
      graded: listing.graded,
      gradingCompany: listing.gradingCompany,
      grade: listing.grade,
      certificationId: listing.certificationId,
      cardName: listing.cardName,
      cardImageUrl: listing.cardImageUrl,
      setName: listing.setName,
      collectorNumber: listing.collectorNumber,
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
