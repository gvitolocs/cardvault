import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Import the actual app services in the isolated native test harness too.
// ignore: avoid_relative_lib_imports
import '../lib/services/auth_service.dart';
// ignore: avoid_relative_lib_imports
import '../lib/services/marketplace_api_uri.dart';
// ignore: avoid_relative_lib_imports
import '../lib/services/pokoin_api_auth.dart';
// ignore: avoid_relative_lib_imports
import '../lib/services/pokoin_api_client.dart';

class _SignedOutApiAuth extends PokoinApiAuthService {
  final requirements = <bool>[];

  @override
  Future<Map<String, String>> authorizationHeaders({
    bool forceRefresh = false,
    bool requireSignedIn = true,
  }) async {
    requirements.add(requireSignedIn);
    if (requireSignedIn) {
      throw StateError('Sign in before calling the Pokoin API.');
    }
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _SignedOutApiAuth auth;
  late List<http.Request> requests;

  AuthService service(http.Response Function(http.Request) respond) {
    return AuthService(
        pokoinApiClient: PokoinApiClient(
      auth: auth,
      client: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    ));
  }

  setUp(() {
    auth = _SignedOutApiAuth();
    requests = [];
  });

  for (final path in [
    '/api/register-email',
    '/api/verify-email-signup',
    '/api/ensure-username'
  ]) {
    test('native $path has an absolute API origin', () {
      final uri = marketplaceApiUri(path);
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.pokoin.com');
      expect(uri.path, path);
    });
  }

  test('pending signup uses the native public API without requiring login',
      () async {
    final signup =
        service((_) => http.Response('{"ok":true,"pending":true}', 200));
    await signup.registerWithEmail(
      email: '  Collector@Example.com  ',
      password: ' Test-password-123 ',
      username: '  Collector123  ',
      redirectPath: '/wallet',
    );
    final request = requests.single;
    expect(request.url, Uri.parse('https://api.pokoin.com/api/register-email'));
    expect(request.method, 'POST');
    expect(request.headers['Content-Type'], contains('application/json'));
    expect(
        request.headers.keys.any((key) => key.toLowerCase() == 'authorization'),
        isFalse);
    expect(jsonDecode(request.body), {
      'email': 'collector@example.com',
      'password': ' Test-password-123 ',
      'username': 'collector123',
      'redirectPath': '/wallet',
    });
    expect(auth.requirements, [false]);
    // A pending signup finishes without initializing Firebase or signing in.
  });

  test('invalid username prevents sending credentials', () async {
    final signup = service((_) => http.Response('{}', 200));
    await expectLater(
        signup.registerWithEmail(
          email: 'collector@example.com',
          password: 'Test-password-123',
          username: 'name with spaces',
          redirectPath: '/wallet',
        ),
        throwsArgumentError);
    expect(requests, isEmpty);
    expect(auth.requirements, isEmpty);
  });

  test('registration reports the server error without pretending to sign in',
      () async {
    final signup = service(
        (_) => http.Response('{"error":"Email is already registered."}', 409));
    await expectLater(
        signup.registerWithEmail(
          email: 'collector@example.com',
          password: 'Test-password-123',
          username: 'collector123',
          redirectPath: '/wallet',
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', 'Email is already registered.')));
    expect(auth.requirements, [false]);
  });

  test('verification sends the trimmed token to an absolute public URL',
      () async {
    final signup = service((_) =>
        http.Response('{"error":"This verification link has expired."}', 400));
    await expectLater(
        signup.verifyEmailSignupToken('  test-expired-token  '),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            'This verification link has expired.')));
    expect(requests.single.url,
        Uri.parse('https://api.pokoin.com/api/verify-email-signup'));
    expect(requests.single.method, 'POST');
    expect(jsonDecode(requests.single.body), {'token': 'test-expired-token'});
    expect(auth.requirements, [false]);
    expect(
        requests.single.headers.keys
            .any((key) => key.toLowerCase() == 'authorization'),
        isFalse);
  });

  test('verification must return a custom token before Firebase sign-in',
      () async {
    final signup = service((_) => http.Response('{"ok":true}', 200));
    await expectLater(
        signup.verifyEmailSignupToken('test-token'),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            'Email verification did not return a login token.')));
    expect(auth.requirements, [false]);
  });

  test('account API calls still require login by default', () async {
    final client = PokoinApiClient(
        auth: auth,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }));
    await expectLater(
        client.postJson(marketplaceApiUri('/api/ensure-username')),
        throwsA(isA<StateError>()));
    expect(auth.requirements, [true]);
    expect(requests, isEmpty);
  });
}
