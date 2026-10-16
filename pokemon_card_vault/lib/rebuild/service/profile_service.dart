import '../model/account.dart';
import '../provider/profile_provider.dart';

class ProfileService {
  ProfileService({ProfileProvider? provider})
      : _provider = provider ?? ProfileProvider();
  final ProfileProvider _provider;
  Stream<AccountProfile> watchProfile(String uid) =>
      _provider.watchProfile(uid);
  Stream<AccountBalance> watchBalance(String uid) =>
      _provider.watchBalance(uid);
  Stream<List<AccountOrder>> watchOrders(String uid) =>
      _provider.watchOrders(uid);
  Stream<List<String>> watchFavorites(String uid) =>
      _provider.watchFavorites(uid);
  Future<void> updateDisplayName(String uid, String name) {
    final value = name.trim();
    if (value.length < 2 || value.length > 60) {
      throw const AccountFailure('invalid-name');
    }
    return _provider.updateDisplayName(uid, value);
  }
}
