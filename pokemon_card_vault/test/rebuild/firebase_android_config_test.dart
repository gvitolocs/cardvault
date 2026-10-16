import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/firebase_options.dart';
import 'package:pokoin/rebuild/provider/account_provider.dart';

void main() {
  final config =
      jsonDecode(File('android/app/google-services.json').readAsStringSync())
          as Map<String, dynamic>;
  final client = (config['client'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((row) =>
          row['client_info']['android_client_info']['package_name'] ==
          'com.vitologic.pokoin');

  test(
      'Android initializes with native options matching the supplied Firebase config',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final options = DefaultFirebaseOptions.currentPlatform;
    expect(options, same(DefaultFirebaseOptions.android));
    expect(options.appId, client['client_info']['mobilesdk_app_id']);
    expect(options.appId, contains(':android:'));
    expect(options.apiKey, (client['api_key'] as List).single['current_key']);
    expect(options.projectId, config['project_info']['project_id']);
    expect(options.messagingSenderId, config['project_info']['project_number']);
    expect(options.storageBucket, config['project_info']['storage_bucket']);
    expect(options.projectId, DefaultFirebaseOptions.web.projectId);
    expect(options.appId, isNot(DefaultFirebaseOptions.web.appId));
  });

  test(
      'Google token audience uses the matched app web client, not an appinvite client',
      () {
    final webClient = (client['oauth_client'] as List)
        .singleWhere((row) => row['client_type'] == 3);
    expect(AccountProvider.googleServerClientId, webClient['client_id']);
    final androidClients = (client['oauth_client'] as List)
        .where((row) => row['client_type'] == 1);
    expect(androidClients, isNotEmpty);
    for (final row in androidClients) {
      expect(row['android_info']['package_name'], 'com.vitologic.pokoin');
      expect(row['android_info']['certificate_hash'],
          matches(RegExp(r'^[0-9a-fA-F]{40}$')));
    }
  });

  test('Gradle processes the config for the actual APK package', () {
    final settings = File('android/settings.gradle').readAsStringSync();
    final app = File('android/app/build.gradle').readAsStringSync();
    expect(settings, contains('id "com.google.gms.google-services"'));
    expect(app, contains('id "com.google.gms.google-services"'));
    expect(app, contains('applicationId = "com.vitologic.pokoin"'));
  });
}
