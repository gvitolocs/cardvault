import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../model/scanner.dart';
import 'scanner/scan_debug_log.dart';

/// Uses the existing Scan Connect transaction and ownership reconciliation.
/// Mutations never retry automatically: after an uncertain add the caller reads
/// the authoritative batch before accepting another card.
class ScannerProvider {
  ScannerProvider(
      {http.Client? client, Future<String?> Function(String)? token})
      : _client = client,
        _token = token;
  final http.Client? _client;
  final Future<String?> Function(String)? _token;

  Future<Map<String, dynamic>> _request(String uid, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final user = _token == null ? FirebaseAuth.instance.currentUser : null;
    if (_token == null && user?.uid != uid) throw StateError('Session changed');
    final token = await (_token != null ? _token(uid) : user!.getIdToken())
        .timeout(const Duration(seconds: 12));
    if (token == null || token.isEmpty) {
      throw StateError('Authentication required');
    }
    final client = _client ?? http.Client();
    try {
      final uri = Uri.https('api.pokoin.com', path, query);
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      };
      final response = await (body == null
              ? client.get(uri, headers: headers)
              : client.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 30));
      final action = query?['action'] ??
          (path == '/api/marketplace-collection' ? 'ownership' : 'read');
      // Fixed operation names and status only: no tokens, IDs or response bodies.
      ScanDebugLog.i(
          'scan request action=$action status=${response.statusCode}');
      await ScanDebugLog.flush();
      if (response.statusCode != 200) {
        throw ScannerRequestFailure(action, response.statusCode);
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid scan response');
      }
      return data;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<ScannerBatch> open(String uid) async {
    final data = await _request(uid, '/api/scan-session',
        query: {'action': 'start'}, body: {});
    final id = '${(data['batch'] as Map)['id']}';
    return read(uid, id);
  }

  Future<ScannerBatch> read(String uid, String batchId) async {
    final data =
        await _request(uid, '/api/scan-batch', query: {'batchId': batchId});
    final batch = data['batch'] as Map;
    if (batch['id'] != batchId || data['items'] is! List) {
      throw const FormatException('Invalid batch');
    }
    return ScannerBatch(
        id: batchId,
        submitted: batch['status'] == 'submitted',
        submittedDestination: batch['submitResult'] is Map
            ? (batch['submitResult']['intent'] == 'collection'
                ? ScanDestination.collection
                : ScanDestination.listing)
            : null,
        cards: (data['items'] as List)
            .whereType<Map<String, dynamic>>()
            .where((row) => row['status'] == 'active')
            .map(ScannedCard.fromJson)
            .toList());
  }

  Future<ScannedCard> add(
      String uid, String batchId, ScannerCandidate card) async {
    final data = await _request(uid, '/api/scan-batch', query: {
      'action': 'add'
    }, body: {
      'batchId': batchId,
      'cardId': card.cardId,
      'language': 'IT',
      'condition': 'NM',
      'quantity': 1
    });
    final rows = data['items'];
    if (rows is! List ||
        rows.length != 1 ||
        rows.single is! Map<String, dynamic>) {
      throw const FormatException(
          'Aggiunta non confermata dal server. Ricarica le scansioni.');
    }
    final added = ScannedCard.fromJson(rows.single as Map<String, dynamic>);
    if (added.cardId != card.cardId || added.id.isEmpty || added.id == 'null') {
      throw const FormatException('Risposta scanner non valida.');
    }
    return added;
  }

  Future<void> patch(String uid, ScannedCard card) async {
    await _request(uid, '/api/scan-batch',
        query: {'action': 'item'},
        body: {'itemId': card.id, 'patch': card.patch});
  }

  Future<void> remove(String uid, String itemId) async {
    await _request(uid, '/api/scan-batch',
        query: {'action': 'remove'}, body: {'itemId': itemId});
  }

  Future<void> submit(
      String uid, String batchId, ScanDestination destination) async {
    final data = await _request(uid, '/api/scan-batch', query: {
      'action': 'submit'
    }, body: {
      'batchId': batchId,
      'submitKey': 'mobile:$batchId',
      'intent':
          destination == ScanDestination.collection ? 'collection' : 'list',
      'targets': {'pokoin': true, 'cardtrader': false}
    });
    final result = data['result'];
    if (data['batch'] is! Map ||
        data['batch']['status'] != 'submitted' ||
        result is! Map ||
        result['intent'] !=
            (destination == ScanDestination.collection
                ? 'collection'
                : 'list') ||
        num.tryParse('${result['ownership']}') == null ||
        (result['ownership'] as num) <= 0) {
      throw const FormatException(
          'Il server non ha confermato il salvataggio del possesso. Riprova la verifica.');
    }
  }

  Future<void> verifyOwnership(String uid, List<ScannedCard> cards) async {
    final data = await _request(uid, '/api/marketplace-collection');
    final rows = data['items'];
    if (data['uid'] != uid ||
        rows is! List ||
        !cards.every((card) => rows.any((row) =>
            row is Map &&
            row['id'] == 'scan:${card.id}' &&
            '${row['cardId']}' == card.cardId &&
            (num.tryParse('${row['quantity']}') ?? 0) > 0))) {
      throw const FormatException(
          'Salvataggio ricevuto, ma il possesso non è ancora visibile. Premi nuovamente Conferma per verificare senza duplicare le carte.');
    }
    ScanDebugLog.i('scan ownership verified rows=${cards.length}');
    await ScanDebugLog.flush();
  }
}
