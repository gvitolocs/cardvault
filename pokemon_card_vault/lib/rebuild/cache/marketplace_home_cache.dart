import 'dart:convert';
import '../model/marketplace_home.dart';
import '../provider/cache_file_provider.dart';

/// Salva soltanto le dodici voci di ogni carosello, con scadenze indipendenti.
class MarketplaceHomeCache {
  MarketplaceHomeCache({CacheFileProvider? storage, DateTime Function()? now})
      : _storage = storage ?? CacheFileProvider(),
        _now = now ?? DateTime.now;
  final CacheFileProvider _storage;
  final DateTime Function() _now;
  static const retention = Duration(days: 7);
  Future<void> _writes = Future.value();

  /// Usato quando occorre attendere esplicitamente la persistenza sul disco.
  Future<void> get flush => _writes;

  Future<Map<String, dynamic>> _record(String namespace) async {
    final source = await _storage.read();
    if (source == null) return {};
    final record = jsonDecode(source);
    return record is Map<String, dynamic> &&
            record['version'] == 1 &&
            record['namespace'] == namespace
        ? record
        : {};
  }

  List<dynamic>? _rail(Object? value) {
    if (value is! Map || value['items'] is! List) return null;
    final savedAt = DateTime.tryParse('${value['savedAt']}');
    if (savedAt == null ||
        savedAt.isAfter(_now()) ||
        _now().difference(savedAt) > retention) {
      return null;
    }
    return (value['items'] as List).take(12).toList();
  }

  Future<MarketplaceHomeData?> read(String namespace) async {
    try {
      final record = await _record(namespace);
      final sets = _rail(record['expansions']);
      final cards = _rail(record['topSellers']);
      if (sets == null && cards == null) return null;
      DateTime? cachedAt;
      if (sets != null && cards != null) {
        final setsAt = DateTime.parse(record['expansions']['savedAt']);
        final cardsAt = DateTime.parse(record['topSellers']['savedAt']);
        cachedAt = setsAt.isBefore(cardsAt) ? setsAt : cardsAt;
      }
      return MarketplaceHomeData(
          cachedAt: cachedAt,
          expansions: (sets ?? [])
              .map((row) => MarketplaceExpansion.fromJson(
                  Map<String, dynamic>.from(row as Map)))
              .toList(),
          topSellers: (cards ?? [])
              .map((row) => MarketplaceCardPreview.fromJson(
                  Map<String, dynamic>.from(row as Map)))
              .toList(),
          expansionsUnavailable: sets == null,
          topSellersUnavailable: cards == null,
          expansionsFromCache: sets != null,
          topSellersFromCache: cards != null);
    } catch (_) {
      // File mancante/corrotto o storage non disponibile: si usa la rete.
      return null;
    }
  }

  Future<void> save(String namespace, MarketplaceHomeData data) {
    _writes = _writes.then((_) async {
      try {
        Map<String, dynamic> record;
        try {
          record = await _record(namespace);
        } catch (_) {
          record = {};
        }
        record.addAll({'version': 1, 'namespace': namespace});
        final savedAt = _now().toUtc().toIso8601String();
        var changed = false;
        if (!data.expansionsLoading &&
            !data.expansionsUnavailable &&
            !data.expansionsFromCache) {
          record['expansions'] = {
            'savedAt': savedAt,
            'items': data.expansions
                .take(12)
                .map((set) => {
                      'name': set.name,
                      'slug': set.slug,
                      'cardCount': set.cardCount,
                      'logoImageUrl': set.imageUrl,
                      if (set.releaseDate != null)
                        'releaseDate': set.releaseDate!.toIso8601String(),
                      if (set.expansionId != null)
                        'expansionId': set.expansionId,
                    })
                .toList()
          };
          changed = true;
        }
        if (!data.topSellersLoading &&
            !data.topSellersUnavailable &&
            !data.topSellersFromCache) {
          record['topSellers'] = {
            'savedAt': savedAt,
            'items': data.topSellers
                .take(12)
                .map((card) => {
                      'id': card.id,
                      'name': card.name,
                      'set': card.expansion,
                      'number': card.number,
                      'previewImageUrl': card.imageUrl,
                      'heroImageUrl': card.fullImageUrl,
                      'price': card.pricePkn,
                      'canonicalPath': card.canonicalPath,
                    })
                .toList()
          };
          changed = true;
        }
        if (changed) await _storage.write(jsonEncode(record));
      } catch (_) {
        // Una scrittura fallita non interrompe i caroselli già disponibili.
      }
    });
    return _writes;
  }
}
