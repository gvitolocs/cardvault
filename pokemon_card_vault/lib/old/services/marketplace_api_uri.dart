import 'package:flutter/foundation.dart';

const String _marketplaceApiBaseUrl = String.fromEnvironment(
  'MARKETPLACE_API_BASE_URL',
  defaultValue: 'https://api.pokoin.com',
);

/// Resolves Pokoin API routes through the browser rewrite on web and through
/// the public API origin on native platforms.
Uri marketplaceApiUri(
  String path, {
  Map<String, String>? queryParameters,
}) {
  final normalized = path.startsWith('/') ? path : '/$path';
  final base = Uri.base;
  final resolved = kIsWeb && base.hasScheme && base.host.isNotEmpty
      ? base.resolve(normalized)
      : Uri.parse('$_marketplaceApiBaseUrl$normalized');
  if (queryParameters == null || queryParameters.isEmpty) {
    return resolved;
  }
  return resolved.replace(queryParameters: {
    ...resolved.queryParameters,
    ...queryParameters,
  });
}
