import 'marketplace_home.dart';
import 'scanner.dart';

enum DraftStatus { editing, publishing, uncertain, published }

/// Local to-do entry, never evidence of ownership or a published listing.
class ListingDraft {
  const ListingDraft(
      {required this.card,
      this.comment = '',
      this.location = '',
      this.firstEdition = false,
      this.sealed = false,
      this.graded = false,
      this.shipping = true,
      this.shipFromCountry = '',
      this.shipFromCountryManual = false,
      this.gradingCompany = '',
      this.grade = '',
      this.certificationId = '',
      this.status = DraftStatus.editing,
      this.listingId = ''});
  final ScannedCard card;
  final String comment,
      shipFromCountry,
      location,
      gradingCompany,
      grade,
      certificationId,
      listingId;
  final bool firstEdition, sealed, graded, shipping, shipFromCountryManual;
  final DraftStatus status;
  String get id => card.id;
  bool get editable => status == DraftStatus.editing;
  bool get pending => status != DraftStatus.published;
  MarketplaceCardPreview get preview => MarketplaceCardPreview(
      id: card.cardId,
      name: card.name,
      expansion: card.setName,
      number: card.number,
      imageUrl: card.imageUrl,
      pricePkn: card.pricePkn);
  ListingDraft edit(
          {ScannedCard? card,
          String? comment,
          String? location,
          bool? firstEdition,
          bool? sealed,
          bool? graded,
          bool? shipping,
          String? shipFromCountry,
          bool? shipFromCountryManual,
          String? gradingCompany,
          String? grade,
          String? certificationId,
          DraftStatus? status,
          String? listingId}) =>
      ListingDraft(
          card: card ?? this.card,
          comment: comment ?? this.comment,
          location: location ?? this.location,
          firstEdition: firstEdition ?? this.firstEdition,
          sealed: sealed ?? this.sealed,
          graded: graded ?? this.graded,
          shipping: shipping ?? this.shipping,
          shipFromCountry: shipFromCountry ?? this.shipFromCountry,
          shipFromCountryManual:
              shipFromCountryManual ?? this.shipFromCountryManual,
          gradingCompany: gradingCompany ?? this.gradingCompany,
          grade: grade ?? this.grade,
          certificationId: certificationId ?? this.certificationId,
          status: status ?? this.status,
          listingId: listingId ?? this.listingId);
  Map<String, dynamic> toJson() => {
        'card': card.toJson(),
        'comment': comment,
        'location': location,
        'firstEdition': firstEdition,
        'sealed': sealed,
        'graded': graded,
        'shipping': shipping,
        'shipFromCountry': shipFromCountry,
        'shipFromCountryManual': shipFromCountryManual,
        'gradingCompany': gradingCompany,
        'grade': grade,
        'certificationId': certificationId,
        'status': status.name,
        'listingId': listingId
      };
  factory ListingDraft.fromJson(Map<String, dynamic> json) {
    final status = DraftStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => throw const FormatException('Invalid draft status'));
    return ListingDraft(
        card: ScannedCard.fromStored(
            Map<String, dynamic>.from(json['card'] as Map)),
        comment: '${json['comment'] ?? ''}',
        location: '${json['location'] ?? ''}',
        firstEdition: json['firstEdition'] == true,
        sealed: json['sealed'] == true,
        graded: json['graded'] == true,
        shipping: json['shipping'] != false,
        shipFromCountry: '${json['shipFromCountry'] ?? ''}',
        shipFromCountryManual: json['shipFromCountryManual'] == true,
        gradingCompany: '${json['gradingCompany'] ?? ''}',
        grade: '${json['grade'] ?? ''}',
        certificationId: '${json['certificationId'] ?? ''}',
        // A process may die after the server committed but before local acknowledgement.
        status:
            status == DraftStatus.publishing ? DraftStatus.uncertain : status,
        listingId: '${json['listingId'] ?? ''}');
  }
}

class DraftPublishFailure implements Exception {
  const DraftPublishFailure(this.message, {this.definite = false});
  final String message;
  final bool definite;
}
