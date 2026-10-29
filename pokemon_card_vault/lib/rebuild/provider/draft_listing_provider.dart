import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../model/listing_draft.dart';
import 'scanner/scan_debug_log.dart';

/// Explicit one-card publication only; ambiguous writes never auto-retry.
class DraftListingProvider {
  DraftListingProvider(
      {http.Client? client, Future<String?> Function(String)? token})
      : _client = client,
        _token = token;
  final http.Client? _client;
  final Future<String?> Function(String)? _token;
  static String? _validationMessage(http.Response response) {
    if (response.statusCode < 400 || response.statusCode >= 500) return null;
    final raw = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (raw.isEmpty || raw.startsWith('<')) return null;
    String? message;
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        for (final key in ['message', 'detail', 'error']) {
          final value = json[key];
          if (value is String && value.trim().isNotEmpty) {
            message = value;
            break;
          }
          if (value is Map && value['message'] is String) {
            message = value['message'] as String;
            break;
          }
        }
      }
    } catch (_) {
      message = raw;
    }
    if (message == null) return null;
    final clean = message
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'Bearer\s+\S+', caseSensitive: false), '[redacted]')
        .replaceAll(
            RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
            '[redacted]')
        .trim();
    return clean.length <= 400 ? clean : '${clean.substring(0, 400)}…';
  }

  Future<Map<String, dynamic>> _request(String uid,
      {Map<String, dynamic>? body,
      Map<String, String>? query,
      String path = '/api/marketplace-listings'}) async {
    final user = _token == null ? FirebaseAuth.instance.currentUser : null;
    if (_token == null && user?.uid != uid) {
      throw const DraftPublishFailure(
          'Accedi con lo stesso account della bozza.',
          definite: true);
    }
    final token = await (_token != null ? _token(uid) : user!.getIdToken())
        .timeout(const Duration(seconds: 12));
    if (token == null ||
        token.isEmpty ||
        (_token == null && FirebaseAuth.instance.currentUser?.uid != uid)) {
      throw const DraftPublishFailure('Accedi nuovamente prima di pubblicare.',
          definite: true);
    }
    final client = _client ?? http.Client();
    try {
      final uri =
          Uri.https('api.pokoin.com', path, {'game': 'pokemon', ...?query});
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      };
      final response = await (body == null
              ? client.get(uri, headers: headers)
              : client.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 30));
      ScanDebugLog.i(
          'listing request action=${path.endsWith('seller-settings') ? 'seller-settings' : body == null ? 'verify' : 'publish'} status=${response.statusCode}');
      await ScanDebugLog.flush();
      if (response.statusCode != 200) {
        final detail = _validationMessage(response);
        throw DraftPublishFailure(
            'Richiesta rifiutata (HTTP ${response.statusCode})${detail == null ? '.' : ': $detail'}',
            definite: response.statusCode >= 400 && response.statusCode < 500);
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid listing response');
      }
      return data;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<String> publish(
      String uid, ListingDraft draft, String sellerName) async {
    final card = draft.card;
    if (draft.shipFromCountry.isNotEmpty) {
      await _saveCountry(uid, draft.shipFromCountry);
    }
    final data = await _request(uid, body: {
      'cardId': card.cardId,
      'pricePkn': card.pricePkn,
      'quantityAvailable': card.quantity,
      'signed': false,
      'reserveAvailable': false,
      'nftAvailable': false,
      'condition': card.condition,
      'language': card.language,
      'foilState': card.foilState,
      'reverse': card.foilState == 'reverse',
      'firstEdition': draft.firstEdition,
      'sealed': draft.sealed,
      'graded': draft.graded,
      'gradingCompany': draft.graded ? draft.gradingCompany : null,
      'grade': draft.graded ? draft.grade : null,
      'certificationId': draft.graded ? draft.certificationId : null,
      'shippingAvailable': draft.shipping,
      'location': draft.location,
      'sellerComment': draft.comment,
      'sellerName': sellerName,
      if (draft.shipFromCountry.isNotEmpty) ...{
        'sellerCountry': draft.shipFromCountry,
        'shipFromCountry': draft.shipFromCountry,
      },
      'sellerReputationLabel': 'New',
      'source': 'pokoin_user_listing',
      'sourceListingId': 'clipboard:${draft.id}',
      'cardName': card.name,
      'setName': card.setName,
      'collectorNumber': card.number,
      'cardImageUrl': card.imageUrl,
      'targets': {'pokoin': true, 'cardtrader': false}
    });
    final row = data['listing'] is Map ? data['listing'] as Map : data;
    if (row['id'] is! String ||
        (row['id'] as String).isEmpty ||
        '${row['cardId']}' != card.cardId ||
        row['sellerUid'] != uid ||
        row['sourceListingId'] != 'clipboard:${draft.id}') {
      throw const FormatException('Listing not acknowledged');
    }
    return row['id'] as String;
  }

  Future<String?> reconcile(String uid, ListingDraft draft) async {
    final data = await _request(uid, query: {
      'sellerUid': uid,
      'cardId': draft.card.cardId,
      'limit': '1000'
    });
    final rows = data['listings'];
    if (rows is! List) throw const FormatException('Invalid listings response');
    final matches = rows
        .whereType<Map>()
        .where((row) =>
            row['sellerUid'] == uid &&
            '${row['cardId']}' == draft.card.cardId &&
            row['sourceListingId'] == 'clipboard:${draft.id}')
        .toList();
    return matches.length == 1 ? matches.single['id'] as String? : null;
  }

  Future<String> sellerCountry(String uid) async {
    final data = await _request(uid, path: '/api/marketplace-seller-settings');
    return '${data['shipFromCountry'] ?? ''}'.trim().toUpperCase();
  }

  Future<void> _saveCountry(String uid, String country) async {
    try {
      final data = await _request(uid,
          path: '/api/marketplace-seller-settings',
          body: {'shipFromCountry': country});
      if (data['shipFromCountry'] != country) {
        throw const FormatException('Country not confirmed');
      }
    } on DraftPublishFailure catch (e) {
      // No listing POST has been sent. Retrying this setting cannot duplicate a listing.
      throw DraftPublishFailure('Paese di spedizione non salvato. ${e.message}',
          definite: true);
    } catch (_) {
      throw const DraftPublishFailure(
          'Paese di spedizione non confermato. Nessun annuncio è stato inviato.',
          definite: true);
    }
  }
}
