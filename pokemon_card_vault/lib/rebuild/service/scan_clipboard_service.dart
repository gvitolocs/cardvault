import '../constants/scanner_constants.dart';
import '../constants/seller_country_constants.dart';
import '../model/listing_draft.dart';
import '../provider/scan_clipboard_provider.dart';
import '../provider/draft_listing_provider.dart';
import 'shipping_addresses_service.dart';

class ScanClipboardService {
  ScanClipboardService(
      {ScanClipboardProvider? local,
      DraftListingProvider? listings,
      ShippingAddressesService? addresses})
      : _local = local ?? HiveScanClipboardProvider(),
        _listings = listings ?? DraftListingProvider(),
        _addresses = addresses ?? ShippingAddressesService();
  final ScanClipboardProvider _local;
  final DraftListingProvider _listings;
  final ShippingAddressesService _addresses;
  Future<List<ListingDraft>> read(String? uid) => _local.read(uid);
  Future<void> write(String? uid, List<ListingDraft> drafts) =>
      _local.write(uid, drafts);
  void validate(ListingDraft draft) {
    final card = draft.card;
    if (!RegExp(r'^[0-9]{1,18}$').hasMatch(card.cardId) ||
        !card.validPrice ||
        card.quantity < 1 ||
        card.quantity > 99 ||
        !scannerConditions.containsKey(card.condition) ||
        !scannerLanguages.containsKey(card.language) ||
        !const ['standard', 'holo', 'reverse', 'stamped', 'promo', 'other']
            .contains(card.foilState)) {
      throw const FormatException(
          'Controlla prezzo PK, quantità e caratteristiche della carta.');
    }
    if ((draft.shipping || draft.shipFromCountry.isNotEmpty) &&
        !sellerCountryCodes.split(' ').contains(draft.shipFromCountry)) {
      throw const FormatException(
          'Seleziona il Paese da cui spedisci. Posizione indica invece dove conservi la carta.');
    }
    if (draft.graded &&
        (draft.gradingCompany.trim().isEmpty ||
            draft.grade.trim().isEmpty ||
            draft.certificationId.trim().isEmpty)) {
      throw const FormatException(
          'Indica società, voto e certificazione della carta gradata.');
    }
  }

  Future<String> publish(String uid, ListingDraft draft, String sellerName) {
    validate(draft);
    return _listings.publish(uid, draft, sellerName);
  }

  Future<String?> reconcile(String uid, ListingDraft draft) =>
      _listings.reconcile(uid, draft);
  Future<String> sellerCountry(String uid) async {
    try {
      final country = await _addresses.defaultCountry(uid);
      if (sellerCountryCodes.split(' ').contains(country)) return country;
    } catch (_) {
      /* Seller setting is a valid fallback when addresses are unavailable. */
    }
    final country = await _listings.sellerCountry(uid);
    return sellerCountryCodes.split(' ').contains(country) ? country : '';
  }
}
