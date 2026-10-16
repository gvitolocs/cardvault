import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'scan_engine.dart';
import 'scan_verify.dart';

/// Public page is `https://pokoin.com/marketplace/en/cards/{ct_id * 2}`.
/// Never double a TCG id. The root shortlink `/{n}` 302s; Chrome iOS often
/// paints the white landing `/` instead.
/// Marketplace API `card_id` is already public — do not double it (that is 4×).
///
/// Fast TCG catalog: `hit.id` is TCGplayer; map via `pokoin_tcg_ids.json`.
/// CDN-Milo (`identity=ct_id`): `hit.id` is already CardTrader; double it once.
class PokoinCardLookup {
  PokoinCardLookup({
    http.Client? client,
    Map<String, String>? tcgToCtId,
    String? identity,
  }) : _client = client ?? http.Client(),
        _identityOverride = identity {
    if (tcgToCtId != null) {
      _tcgToPokoin = Map<String, String>.from(tcgToCtId);
      _mapReady = true;
    }
  }

  static const webHost = 'pokoin.com';
  static const apiHost = 'api.pokoin.com';
  static const tcgMapAsset = 'assets/pokoin_tcg_ids.json';
  static const ctIdIdentity = 'ct_id';

  final http.Client _client;
  final String? _identityOverride;
  Map<String, String> _tcgToPokoin = const {};
  bool _mapReady = false;

  String get identity => _identityOverride ?? ScanEngine.identity;

  bool get usesCtId => identity == ctIdIdentity;

  Future<void> load() async {
    if (_mapReady) return;
    try {
      final raw = await rootBundle.loadString(tcgMapAsset);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _tcgToPokoin = {
          for (final entry in decoded.entries)
            '${entry.key}': '${entry.value}',
        };
      }
    } catch (_) {
      _tcgToPokoin = const {};
    }
    _mapReady = true;
  }

  String? pokoinIdForTcg(String tcgId) => _tcgToPokoin[tcgId.trim()];

  bool hasLiveUrl(ScanHit hit, [List<ScanHit> alsoTry = const []]) {
    if (usesCtId) {
      return _isCtId(hit.id);
    }
    for (final candidate in _mapCandidates(hit, alsoTry)) {
      final mapped = pokoinIdForTcg(candidate.id);
      if (mapped != null && mapped.isNotEmpty) return true;
    }
    return false;
  }

  static bool _isCtId(String value) =>
      RegExp(r'^[1-9]\d*$').hasMatch(value.trim());

  static String doubledPublicNumber(String cardId) {
    final clean = cardId.trim();
    if (!RegExp(r'^\d+$').hasMatch(clean)) return '';
    final value = BigInt.tryParse(clean);
    if (value == null || value <= BigInt.zero) return '';
    return (value * BigInt.from(2)).toString();
  }

  static String slugPart(String value) {
    final folded = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return folded.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String pageSlug({
    required String name,
    String number = '',
    String setName = '',
  }) {
    final parts = [
      slugPart(name),
      slugPart(number),
      slugPart(setName),
    ].where((part) => part.isNotEmpty);
    final slug = parts.join('-');
    return slug.isEmpty ? 'card' : slug;
  }

  /// Canonical public page: doubled id in the marketplace path.
  static Uri marketplacePage({
    required String cardId,
    String name = '',
    String number = '',
    String setName = '',
  }) {
    final doubled = doubledPublicNumber(cardId);
    final slug = pageSlug(name: name, number: number, setName: setName);
    return Uri.https(webHost, '/marketplace/en/cards/$doubled/$slug');
  }

  /// Root shortlink the user remembers: `pokoin.com/{cardId * 2}`.
  static Uri rootShortlink(String cardId) {
    return Uri.https(webHost, '/${doubledPublicNumber(cardId)}');
  }

  /// Live open: marketplace SPA, no 302 through the white `/` landing page.
  static Uri marketplaceCardUrl(String publicNumber) {
    return Uri.https(webHost, '/marketplace/en/cards/$publicNumber');
  }

  static Uri liveCardPage(String cardId) {
    return marketplaceCardUrl(doubledPublicNumber(cardId));
  }

  static String _displayName(String name) {
    return name
        .replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ')
        .replaceAll(RegExp(r'\s+-\s+.*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _alnum(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static Set<String> _tokens(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 2)
        .toSet();
  }

  /// Rank a marketplace row against a Milo hit. Higher is better.
  static int matchScore(ScanHit hit, MarketplaceCard card) {
    var score = 0;
    final hitName = _alnum(_displayName(hit.name));
    final cardName = _alnum(card.name);
    if (hitName.isNotEmpty && cardName.isNotEmpty) {
      if (hitName == cardName) {
        score += 4;
      } else if (cardName.contains(hitName) || hitName.contains(cardName)) {
        score += 2;
      }
    }

    final hitNum = _alnum(hit.collectorNumber);
    final cardNum = _alnum(card.number);
    if (hitNum.isNotEmpty && cardNum.contains(hitNum)) {
      score += 5;
    }

    final overlap = _tokens(hit.setName).intersection(_tokens(card.setName));
    if (overlap.isNotEmpty) {
      score += overlap.length >= 2 ? 3 : 2;
    }

    final staffHit = hit.name.toLowerCase().contains('staff');
    final staffCard =
        '${card.name} ${card.number}'.toLowerCase().contains('staff');
    if (staffHit != staffCard) {
      score -= 3;
    }
    return score;
  }

  static String searchQuery(ScanHit hit) {
    final name = _displayName(hit.name);
    return [
      name,
      hit.collectorNumber,
      hit.setName,
    ].where((part) => part.trim().isNotEmpty).join(' ');
  }

  /// Live scan: tcg map only (ct_id × 2). Newer printings often miss the map;
  /// fall back to another same-species hit that is mapped. Gallery may search the API.
  Future<Uri?> urlForHit(
    ScanHit hit, {
    String? vitBlueprintId,
    bool liveFast = false,
    List<ScanHit> alsoTry = const [],
  }) async {
    await load();
    if (vitBlueprintId != null &&
        vitBlueprintId.trim().isNotEmpty &&
        RegExp(r'^\d+$').hasMatch(vitBlueprintId.trim())) {
      return liveCardPage(vitBlueprintId.trim());
    }
    if (usesCtId) {
      if (_isCtId(hit.id)) return liveCardPage(hit.id.trim());
      if (liveFast) return null;
    } else {
      for (final candidate in _mapCandidates(hit, alsoTry)) {
        final mapped = pokoinIdForTcg(candidate.id);
        if (mapped != null && mapped.isNotEmpty) {
          return liveCardPage(mapped);
        }
      }
      if (liveFast) return null;
    }
    final card = await findMarketplaceCard(hit);
    if (card == null) return null;
    return marketplaceCardUrl(card.cardId);
  }

  List<ScanHit> _mapCandidates(ScanHit hit, List<ScanHit> alsoTry) {
    final seen = <String>{hit.id};
    final sameNumber = <ScanHit>[];
    final sameSpeciesHits = <ScanHit>[];
    for (final other in alsoTry) {
      if (other.id.isEmpty || !seen.add(other.id)) continue;
      if (!sameSpecies(hit.name, other.name)) continue;
      if (hit.collectorNumber.isNotEmpty &&
          other.collectorNumber == hit.collectorNumber) {
        sameNumber.add(other);
      } else {
        sameSpeciesHits.add(other);
      }
    }
    return [hit, ...sameNumber, ...sameSpeciesHits];
  }

  Future<MarketplaceCard?> findMarketplaceCard(ScanHit hit) async {
    final queries = <String>{
      searchQuery(hit),
      [_displayName(hit.name), hit.collectorNumber]
          .where((part) => part.trim().isNotEmpty)
          .join(' '),
      [_displayName(hit.name), hit.setName]
          .where((part) => part.trim().isNotEmpty)
          .join(' '),
    }.where((query) => query.trim().length >= 3);

    MarketplaceCard? best;
    var bestScore = 0;
    for (final query in queries) {
      final rows = await _search(query);
      for (final card in rows) {
        final score = matchScore(hit, card);
        if (score > bestScore) {
          bestScore = score;
          best = card;
        }
      }
      if (bestScore >= 7) break;
    }
    if (best == null || bestScore < 5) return null;
    return best;
  }

  Future<List<MarketplaceCard>> _search(String query) async {
    final uri = Uri.https(apiHost, '/api/marketplace-cards', {
      'query': query,
      'limit': '20',
    });
    try {
      final response = await _client.get(uri).timeout(const Duration(milliseconds: 1500));
      if (response.statusCode >= 400) return const [];
      final decoded = jsonDecode(response.body);
      final rows = decoded is List ? decoded : const [];
      return rows
          .whereType<Map>()
          .map((row) => MarketplaceCard.fromJson(Map<String, dynamic>.from(row)))
          .where((card) => card.cardId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class MarketplaceCard {
  const MarketplaceCard({
    required this.cardId,
    required this.name,
    required this.number,
    required this.setName,
  });

  final String cardId;
  final String name;
  final String number;
  final String setName;

  factory MarketplaceCard.fromJson(Map<String, dynamic> json) {
    return MarketplaceCard(
      cardId: '${json['card_id'] ?? json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      number: '${json['card_number'] ?? json['expansion_number'] ?? ''}',
      setName: '${json['set_name'] ?? json['expansion_name'] ?? ''}',
    );
  }
}
