import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

class WalletUser {
  final String uid;
  final String email;
  final String displayName;
  final String idToken;

  const WalletUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.idToken,
  });
}

class WalletAuthService {
  static const _apiKey = 'AIzaSyDlbKXeR0R3aAATZtCG6dhEPUw39DhXQpU';

  final StreamController<WalletUser?> _authController =
      StreamController<WalletUser?>.broadcast();

  WalletUser? _currentUser;
  StreamSubscription<User?>? _firebaseSubscription;

  Stream<WalletUser?> get authState async* {
    await _syncFirebaseUser();
    _listenToFirebaseAuth();
    yield _currentUser;
    yield* _authController.stream;
  }

  Future<void> signInWithEmail(String email, String password) async {
    final payload = await _authRequest(
      'accounts:signInWithPassword',
      <String, Object>{
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      },
    );
    _setUser(payload);
    await ensureUsername();
  }

  Future<void> registerWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    final payload = await _authRequest('accounts:signUp', <String, Object>{
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    _setUser(payload, fallbackDisplayName: displayName.trim());
    await ensureUsername();
  }

  Future<void> signInWithGoogle() async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized yet.');
    }
    final provider = GoogleAuthProvider()
      ..setCustomParameters(<String, String>{'prompt': 'select_account'});
    final credential = await FirebaseAuth.instance.signInWithPopup(provider);
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Google sign-in did not return a user.');
    }

    _currentUser = await _fromFirebaseUser(firebaseUser);
    _authController.add(_currentUser);
    await ensureUsername();
  }

  Future<void> signInWithCustomToken(String customToken) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized yet.');
    }
    final credential = await FirebaseAuth.instance.signInWithCustomToken(
      customToken,
    );
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Wallet sign-in did not return a user.');
    }
    _currentUser = await _fromFirebaseUser(firebaseUser);
    _authController.add(_currentUser);
    await ensureUsername();
  }

  Future<Map<String, String>> requestWalletNonce(String address) async {
    final response = await http.post(
      Uri.parse('/api/wallet-auth/nonce'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'address': address.trim().toLowerCase()}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Wallet nonce failed.');
    }
    return <String, String>{
      'address': payload['address'] as String? ?? '',
      'message': payload['message'] as String? ?? '',
    };
  }

  Future<Map<String, String>> verifyWalletSignature({
    required String address,
    required String signature,
  }) async {
    final response = await http.post(
      Uri.parse('/api/wallet-auth/verify'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'address': address.trim().toLowerCase(),
        'signature': signature,
      }),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Wallet verification failed.',
      );
    }
    return <String, String>{
      'customToken': payload['customToken'] as String? ?? '',
      'uid': payload['uid'] as String? ?? '',
      'email': payload['email'] as String? ?? '',
      'displayName': payload['displayName'] as String? ?? '',
      'walletAddress': payload['walletAddress'] as String? ?? '',
    };
  }

  Future<void> signOut() async {
    if (Firebase.apps.isNotEmpty) {
      await FirebaseAuth.instance.signOut();
    }
    _currentUser = null;
    _authController.add(null);
  }

  Future<String?> walletAddressForEmail(String email) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized yet.');
    }
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in before sending to an email.');
    }

    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw ArgumentError('Enter a valid email address.');
    }

    final doc = await FirebaseFirestore.instance
        .collection('email_wallets')
        .doc(normalized)
        .get();
    return doc.data()?['address'] as String?;
  }

  Future<void> transferAccountBalance({
    required String recipientUsername,
    required int amountPkn,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Sign in before sending to an email.');
    }
    if (amountPkn <= 0) {
      throw ArgumentError('Enter a whole PKN amount greater than zero.');
    }
    final token = await firebaseUser.getIdToken();
    final response = await http.post(
      Uri.parse('/api/transfer-account-balance'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'recipientUsername': recipientUsername.trim().toLowerCase(),
        'amountPkn': amountPkn,
      }),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Account transfer failed.',
      );
    }
  }

  Future<void> requestPknWithdraw({
    required String toAddress,
    required int amountPkn,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Sign in before requesting a withdraw.');
    }
    final address = toAddress.trim();
    if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
      throw ArgumentError('Enter a valid 0x payout address.');
    }
    if (amountPkn <= 0) {
      throw ArgumentError('Enter a whole PKN amount greater than zero.');
    }
    final token = await firebaseUser.getIdToken();
    final response = await http.post(
      Uri.parse('/api/request-pkn-withdraw'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'toAddress': address, 'amountPkn': amountPkn}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Withdraw request failed.',
      );
    }
  }

  Future<Map<String, dynamic>> quoteWpknExchange({
    required String direction,
    required int amountIn,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Sign in before requesting an exchange quote.');
    }
    final token = await firebaseUser.getIdToken();
    final response = await http.post(
      Uri.parse('/api/wpkn-exchange/quote'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'direction': direction, 'amountIn': amountIn}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Exchange quote failed.');
    }
    return payload;
  }

  Future<Map<String, dynamic>> requestWpknExchange({
    required String quoteId,
    required String direction,
    required String toAddress,
  }) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Sign in before requesting an exchange.');
    }
    final token = await firebaseUser.getIdToken();
    final response = await http.post(
      Uri.parse('/api/wpkn-exchange/request'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'quoteId': quoteId,
        'direction': direction,
        'toAddress': toAddress.trim(),
      }),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Exchange request failed.',
      );
    }
    return payload;
  }

  Future<List<Map<String, dynamic>>> wpknExchangeRequests() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return const <Map<String, dynamic>>[];
    }
    final token = await firebaseUser.getIdToken();
    final response = await http.get(
      Uri.parse('/api/wpkn-exchange/status'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Exchange status failed.',
      );
    }
    return ((payload['requests'] as List?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<String?> linkedWalletAddress() async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return null;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(firebaseUser.uid)
        .get();
    final address = (doc.data()?['walletAddress'] as String?)?.trim();
    return address == null || address.isEmpty ? null : address;
  }

  Future<List<Map<String, dynamic>>> ledgerActivity({int limit = 12}) async {
    if (Firebase.apps.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return const <Map<String, dynamic>>[];
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('ledger_entries')
        .where('uid', isEqualTo: firebaseUser.uid)
        .get();
    final rows = snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
    rows.sort((a, b) => _readTimestamp(b['createdAt']).compareTo(
          _readTimestamp(a['createdAt']),
        ));
    return rows.take(limit).toList(growable: false);
  }

  static DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<List<Map<String, dynamic>>> onChainActivity({
    required String address,
    int limit = 12,
  }) async {
    final normalized = address.trim().toLowerCase();
    if (!RegExp(r'^0x[a-f0-9]{40}$').hasMatch(normalized)) {
      return const <Map<String, dynamic>>[];
    }
    final response = await http
        .get(Uri.parse('https://rpc.pokoin.com/explorer/address/$normalized'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const <Map<String, dynamic>>[];
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ((payload['transactions'] as List?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .toList(growable: false);
  }

  Future<List<String>> searchRecipientUsernames(String query) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return const <String>[];
    }
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return const <String>[];
    }
    final token = await firebaseUser.getIdToken();
    final uri = Uri.parse(
      '/api/search-recipient-emails',
    ).replace(queryParameters: {'q': normalized});
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Recipient search failed.',
      );
    }
    return ((payload['usernames'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<String?> ensureUsername() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return null;
    }
    final token = await firebaseUser.getIdToken();
    final response = await http.post(
      Uri.parse('/api/ensure-username'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Username setup failed.');
    }
    return payload['username'] as String?;
  }

  Future<void> _syncFirebaseUser() async {
    if (Firebase.apps.isEmpty) {
      return;
    }
    final firebaseUser = FirebaseAuth.instance.currentUser;
    _currentUser =
        firebaseUser == null ? null : await _fromFirebaseUser(firebaseUser);
  }

  void _listenToFirebaseAuth() {
    if (Firebase.apps.isEmpty || _firebaseSubscription != null) {
      return;
    }
    _firebaseSubscription = FirebaseAuth.instance.idTokenChanges().listen((
      user,
    ) async {
      _currentUser = user == null ? null : await _fromFirebaseUser(user);
      _authController.add(_currentUser);
    });
  }

  Future<WalletUser> _fromFirebaseUser(User firebaseUser) async {
    return WalletUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ??
          firebaseUser.email?.split('@').first ??
          'Pokoin user',
      idToken: await firebaseUser.getIdToken() ?? '',
    );
  }

  Future<Map<String, dynamic>> _authRequest(
    String method,
    Map<String, Object> body,
  ) async {
    final response = await http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/$method?key=$_apiKey',
      ),
      headers: const <String, String>{'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || payload['error'] != null) {
      final error = payload['error'] as Map<String, dynamic>?;
      throw Exception(error?['message'] ?? 'Firebase Auth failed');
    }
    return payload;
  }

  void _setUser(
    Map<String, dynamic> payload, {
    String fallbackDisplayName = '',
  }) {
    final email = payload['email'] as String? ?? '';
    _currentUser = WalletUser(
      uid: payload['localId'] as String? ?? '',
      email: email,
      displayName: payload['displayName'] as String? ??
          (fallbackDisplayName.isEmpty
              ? email.split('@').first
              : fallbackDisplayName),
      idToken: payload['idToken'] as String? ?? '',
    );
    _authController.add(_currentUser);
  }
}
