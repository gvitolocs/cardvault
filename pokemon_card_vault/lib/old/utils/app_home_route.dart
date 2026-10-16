import 'package:flutter/foundation.dart';

/// Native apps enter the marketplace at `/`; explicit deep links stay intact.
/// Web keeps its existing marketing, explorer and forum root pages.
String? nativeHomeRedirect(Uri location, {bool isWeb = kIsWeb}) {
  if (isWeb || location.path != '/') return null;
  return location.replace(path: '/marketplace').toString();
}
