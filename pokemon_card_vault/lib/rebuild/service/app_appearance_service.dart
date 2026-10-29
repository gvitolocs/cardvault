import '../model/app_appearance.dart';
import '../provider/app_appearance_provider.dart';

class AppAppearanceService {
  AppAppearanceService({AppAppearanceProvider? provider})
      : _provider = provider ?? AppAppearanceProvider();
  final AppAppearanceProvider _provider;
  Future<AppAppearance> load() async =>
      AppAppearance.fromId(await _provider.read());
  Future<void> save(AppAppearance appearance) => _provider.write(appearance.id);
}
