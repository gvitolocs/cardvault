import '../constants/seller_country_constants.dart';
import '../model/shipping_address.dart';
import '../provider/account_addresses_provider.dart';

class ShippingAddressesService {
  ShippingAddressesService({AccountAddressesProvider? provider})
      : _provider = provider ?? AccountAddressesProvider();
  final AccountAddressesProvider _provider;
  Future<List<ShippingAddress>> read(String uid) => _provider.read(uid);
  Future<String> defaultCountry(String uid) async {
    // Metadata only: countryCode remains queryable outside the encrypted address.
    final rows = await _provider.read(uid, reveal: false);
    final active =
        rows.where((a) => a.isDefault).firstOrNull ?? rows.firstOrNull;
    return active?.countryCode ?? '';
  }

  Future<void> save(String uid, ShippingAddress address) {
    if ([
          address.fullName,
          address.addressLine1,
          address.city,
          address.postalCode
        ].any((s) => s.trim().isEmpty) ||
        !sellerCountryCodes
            .split(' ')
            .contains(address.countryCode.toUpperCase())) {
      throw const FormatException(
          'Compila nome, indirizzo, CAP, città e Paese.');
    }
    return _provider.save(uid, address);
  }

  Future<void> remove(String uid, String id) => _provider.remove(uid, id);
}
