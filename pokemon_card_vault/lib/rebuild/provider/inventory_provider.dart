import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../model/inventory_listing.dart';
import 'account_api_provider.dart';

/// All native owner listings, including paused rows. Never uses public shop rails.
class InventoryProvider {
  InventoryProvider(
      {FirebaseAuth? auth,
      http.Client? client,
      Future<String?> Function(String uid)? idToken,
      this.pageSize = 1000})
      : assert(pageSize > 0 && pageSize <= 1000),
        _api = AccountApiProvider(auth: auth, client: client, idToken: idToken);

  final AccountApiProvider _api;
  final int pageSize;

  Future<List<InventoryListing>> fetchItems(String uid) =>
      _read(uid, firstLimit: pageSize);

  /// Normal owner pages; cancellation never waits for in-flight HTTP.
  /// Do not mix a limit=2 fast/cache response with the owner's full-page path:
  /// production can return overlapping snapshots even for distinct offsets.
  Stream<InventorySnapshot> watchItems(String uid) {
    var cancelled = false;
    late StreamController<InventorySnapshot> output;
    output = StreamController<InventorySnapshot>(onListen: () {
      unawaited(() async {
        try {
          await _read(uid,
              firstLimit: pageSize,
              cancelled: () => cancelled,
              onPage: (page) {
                if (!cancelled) output.add(page);
              });
        } catch (error, stack) {
          if (!cancelled) output.addError(error, stack);
        } finally {
          if (!cancelled) await output.close();
        }
      }());
    }, onCancel: () {
      cancelled = true;
    });
    return output.stream;
  }

  Future<List<InventoryListing>> _read(String uid,
      {required int firstLimit,
      bool Function()? cancelled,
      void Function(InventorySnapshot)? onPage}) async {
    final result = <InventoryListing>[];
    final ids = <String>{};
    int? expectedTotal;
    var offset = 0;
    var limit = firstLimit;
    while (true) {
      if (cancelled?.call() == true) return const [];
      final payload = await _api.get(uid, '/api/marketplace-listings', {
        'sellerUid': uid,
        'nativeOnly': '1',
        'limit': '$limit',
        'offset': '$offset',
      });
      if (cancelled?.call() == true) return const [];
      final rows = payload['listings'] ?? payload['items'];
      if (rows is! List || (payload['uid'] != null && payload['uid'] != uid)) {
        throw const FormatException('Invalid private inventory');
      }
      if (payload['total'] != null) {
        final total = int.tryParse('${payload['total']}');
        if (total == null ||
            total < 0 ||
            (expectedTotal != null && total != expectedTotal)) {
          throw const FormatException('Inventory changed during pagination');
        }
        expectedTotal = total;
      }
      for (final row in rows) {
        final quantity =
            row is Map ? num.tryParse('${row['quantityAvailable']}') : null;
        if (row is! Map<String, dynamic> ||
            row['sellerUid'] != uid ||
            '${row['id'] ?? ''}'.trim().isEmpty ||
            '${row['cardId'] ?? ''}'.trim().isEmpty ||
            quantity == null ||
            !quantity.isFinite ||
            quantity < 0 ||
            quantity != quantity.truncateToDouble() ||
            '${row['status'] ?? ''}'.trim().isEmpty) {
          throw const FormatException('Invalid owner listing');
        }
        final item = InventoryListing.fromJson(row);
        // An ignored offset must fail, not quietly return the first 1000 rows.
        if (!ids.add(item.item.id)) {
          throw const FormatException('Overlapping inventory pages; retry');
        }
        result.add(item);
      }
      offset += rows.length;
      final more = payload['hasMore'];
      if (more != null && more is! bool) {
        throw const FormatException('Invalid inventory pagination');
      }
      if ((expectedTotal != null && offset > expectedTotal) ||
          (rows.isEmpty && more == true)) {
        throw const FormatException('Incomplete inventory');
      }
      final finished = more == false ||
          (expectedTotal != null && offset == expectedTotal) ||
          (more == null && expectedTotal == null && rows.length < limit);
      if (finished) {
        if ((expectedTotal != null && offset != expectedTotal) ||
            more == true) {
          throw const FormatException('Incomplete inventory');
        }
        onPage?.call(InventorySnapshot(items: result, complete: true));
        return List.unmodifiable(result);
      }
      if (rows.isEmpty) throw const FormatException('Incomplete inventory');
      onPage?.call(InventorySnapshot(items: result, complete: false));
      limit = pageSize;
    }
  }
}
