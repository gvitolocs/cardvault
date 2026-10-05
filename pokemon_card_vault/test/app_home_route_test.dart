import 'package:flutter_test/flutter_test.dart';
// Also run the real policy in the Flutter-only Windows test harness.
// ignore: avoid_relative_lib_imports
import '../lib/utils/app_home_route.dart';

void main() {
  test('native root enters the marketplace', () {
    expect(nativeHomeRedirect(Uri.parse('/'), isWeb: false), '/marketplace');
  });

  test('native root keeps query parameters and fragment', () {
    expect(
      nativeHomeRedirect(Uri.parse('/?lang=it#recent'), isWeb: false),
      '/marketplace?lang=it#recent',
    );
  });

  for (final route in [
    '/marketplace',
    '/marketplace/search?q=pikachu',
    '/marketplace/en/cards/226324/reshiram-zekrom-gx',
    '/cardscan',
    '/wallet',
    '/profile',
    '/auth?from=%2Fprofile',
    '/auth?signupToken=test-only-token',
  ]) {
    test('native deep link $route is not overridden', () {
      expect(nativeHomeRedirect(Uri.parse(route), isWeb: false), isNull);
    });
  }

  for (final root in [
    'https://pokoin.com/',
    'https://explorer.pokoin.com/',
    'https://forum.pokoin.com/',
    'http://localhost:5000/?lang=it',
  ]) {
    test('web root $root keeps its existing page', () {
      expect(nativeHomeRedirect(Uri.parse(root), isWeb: true), isNull);
    });
  }
}
