import 'package:shared_preferences/shared_preferences.dart';

/// Device-wide display preference, never account inventory or an API filter.
class ArtworkPreferencesProvider {
  static const languageKey = 'rebuild.collectionArtworkLanguage.v1';
  Future<String?> readLanguage() async =>
      (await SharedPreferences.getInstance()).getString(languageKey);
  Future<void> writeLanguage(String language) async {
    await (await SharedPreferences.getInstance())
        .setString(languageKey, language);
  }
}
