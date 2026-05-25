import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pokoin_api_client.dart';

class CardTraderIntegrationService {
  CardTraderIntegrationService({PokoinApiClient? apiClient})
      : _apiClient = apiClient ?? PokoinApiClient();

  final PokoinApiClient _apiClient;

  Future<CardTraderConnectionStatus> status() async {
    final response =
        await _apiClient.get(Uri.base.resolve('/api/cardtrader-status'));
    return CardTraderConnectionStatus.fromJson(_decode(response)['status']);
  }

  Future<CardTraderConnectionStatus> connect(String token) async {
    final response = await _apiClient.postJson(
      Uri.base.resolve('/api/cardtrader-connect'),
      body: {'token': token.trim()},
    );
    return CardTraderConnectionStatus.fromJson(_decode(response)['status']);
  }

  Future<CardTraderConnectionStatus> disconnect() async {
    final response = await _apiClient.postJson(
      Uri.base.resolve('/api/cardtrader-disconnect'),
    );
    return CardTraderConnectionStatus.fromJson(_decode(response)['status']);
  }

  Future<CardTraderCleanListingsResult> cleanLinkedListings() async {
    final response = await _apiClient.postJson(
      Uri.base.resolve('/api/cardtrader-clean-listings'),
    );
    return CardTraderCleanListingsResult.fromJson(_decode(response));
  }

  Future<CardTraderDryRunSummary> importDryRun() async {
    final response = await _apiClient.postJson(
      Uri.base.resolve('/api/cardtrader-import-dry-run'),
    );
    return CardTraderDryRunSummary.fromJson(_decode(response)['summary']);
  }
}

class CardTraderCleanListingsResult {
  const CardTraderCleanListingsResult({
    required this.cleanedCount,
    required this.listingIds,
    required this.cardIds,
  });

  final int cleanedCount;
  final List<String> listingIds;
  final List<String> cardIds;

  factory CardTraderCleanListingsResult.fromJson(Object? json) {
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return CardTraderCleanListingsResult(
      cleanedCount: (map['cleanedCount'] as num?)?.toInt() ?? 0,
      listingIds: (map['listingIds'] as List? ?? const [])
          .map((id) => '$id')
          .where((id) => id.trim().isNotEmpty)
          .toList(),
      cardIds: (map['cardIds'] as List? ?? const [])
          .map((id) => '$id')
          .where((id) => id.trim().isNotEmpty)
          .toList(),
    );
  }
}

class CardTraderConnectionStatus {
  const CardTraderConnectionStatus({
    required this.connected,
    required this.provider,
    required this.metadata,
    this.connectedAt,
    this.updatedAt,
    this.lastValidatedAt,
    this.disconnectedAt,
  });

  final bool connected;
  final String provider;
  final CardTraderConnectionMetadata? metadata;
  final DateTime? connectedAt;
  final DateTime? updatedAt;
  final DateTime? lastValidatedAt;
  final DateTime? disconnectedAt;

  factory CardTraderConnectionStatus.fromJson(Object? json) {
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return CardTraderConnectionStatus(
      connected: map['connected'] == true,
      provider: '${map['provider'] ?? 'cardtrader'}',
      metadata: map['metadata'] is Map
          ? CardTraderConnectionMetadata.fromJson(map['metadata'])
          : null,
      connectedAt: _parseDate(map['connectedAt']),
      updatedAt: _parseDate(map['updatedAt']),
      lastValidatedAt: _parseDate(map['lastValidatedAt']),
      disconnectedAt: _parseDate(map['disconnectedAt']),
    );
  }
}

class CardTraderConnectionMetadata {
  const CardTraderConnectionMetadata({
    required this.appName,
    required this.appId,
    required this.userEmail,
    required this.userId,
    required this.username,
    required this.sellerName,
    required this.sellerId,
    required this.scopes,
  });

  final String appName;
  final String appId;
  final String userEmail;
  final String userId;
  final String username;
  final String sellerName;
  final String sellerId;
  final List<String> scopes;

  factory CardTraderConnectionMetadata.fromJson(Object? json) {
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    final app = map['app'] is Map
        ? Map<String, dynamic>.from(map['app'])
        : <String, dynamic>{};
    final user = map['user'] is Map
        ? Map<String, dynamic>.from(map['user'])
        : <String, dynamic>{};
    final seller = map['seller'] is Map
        ? Map<String, dynamic>.from(map['seller'])
        : <String, dynamic>{};
    return CardTraderConnectionMetadata(
      appName: '${app['name'] ?? ''}',
      appId: '${app['id'] ?? ''}',
      userEmail: '${user['email'] ?? ''}',
      userId: '${user['id'] ?? ''}',
      username: '${user['username'] ?? ''}',
      sellerName: '${seller['name'] ?? ''}',
      sellerId: '${seller['id'] ?? ''}',
      scopes: (map['scopes'] as List? ?? const [])
          .map((scope) => '$scope')
          .where((scope) => scope.trim().isNotEmpty)
          .toList(),
    );
  }
}

class CardTraderDryRunSummary {
  const CardTraderDryRunSummary({
    required this.productCount,
    required this.sample,
  });

  final int productCount;
  final List<CardTraderDryRunSample> sample;

  factory CardTraderDryRunSummary.fromJson(Object? json) {
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return CardTraderDryRunSummary(
      productCount: (map['productCount'] as num?)?.toInt() ?? 0,
      sample: (map['sample'] as List? ?? const [])
          .map((row) => CardTraderDryRunSample.fromJson(row))
          .toList(),
    );
  }
}

class CardTraderDryRunSample {
  const CardTraderDryRunSample({
    required this.id,
    required this.blueprintId,
    required this.name,
    required this.quantity,
    required this.priceCents,
    required this.state,
  });

  final String id;
  final String blueprintId;
  final String name;
  final int quantity;
  final int priceCents;
  final String state;

  factory CardTraderDryRunSample.fromJson(Object? json) {
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return CardTraderDryRunSample(
      id: '${map['id'] ?? ''}',
      blueprintId: '${map['blueprintId'] ?? ''}',
      name: '${map['name'] ?? ''}',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      priceCents: (map['priceCents'] as num?)?.toInt() ?? 0,
      state: '${map['state'] ?? ''}',
    );
  }
}

Map<String, dynamic> _decode(http.Response response) {
  final decoded = response.body.trim().isEmpty
      ? <String, dynamic>{}
      : jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode >= 400) {
    throw StateError(
      decoded['error'] as String? ?? 'CardTrader request failed.',
    );
  }
  return decoded;
}

DateTime? _parseDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
