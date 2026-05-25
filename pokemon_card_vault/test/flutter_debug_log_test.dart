import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/services/flutter_debug_log.dart';
import 'package:pokoin/services/pokoin_api_auth.dart';

class _TestApiAuthService extends PokoinApiAuthService {
  _TestApiAuthService();

  @override
  Future<Map<String, String>> authorizationHeaders({
    bool forceRefresh = false,
    bool requireSignedIn = true,
  }) async {
    return const {'Authorization': 'Bearer test-token'};
  }
}

void main() {
  test('flutter debug query flag enables logging request', () {
    expect(
      flutterDebugRequestedFromUri(
        Uri.parse('https://pokoin.com/123/pikachu?flutterDebug=1'),
      ),
      isTrue,
    );
    expect(
      flutterDebugRequestedFromUri(
        Uri.parse('https://pokoin.com/123/pikachu?searchDebug=1'),
      ),
      isFalse,
    );
  });

  test('sanitizeFlutterDebugValue removes sensitive nested fields', () {
    final sanitized = sanitizeFlutterDebugValue({
      'route': '/123/pikachu',
      'authorization': 'Bearer secret',
      'nested': {
        'token': 'hidden',
        'value': 'visible',
      },
      'items': [
        {'password': 'hidden', 'name': 'kept'},
      ],
    });

    expect(sanitized, {
      'route': '/123/pikachu',
      'nested': {'value': 'visible'},
      'items': [
        {'name': 'kept'},
      ],
    });
  });

  test('authorized debug users auto-enable logging without query flag',
      () async {
    final requests = <http.Request>[];
    final logger = FlutterDebugLog.instance;
    logger.configureForTest(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 201);
      }),
      auth: _TestApiAuthService(),
      authorized: false,
      requested: false,
    );
    addTearDown(() {
      logger.configureForTest(
        client: MockClient((_) async => http.Response('{}', 200)),
        authorized: false,
        requested: false,
      );
    });

    logger.setAuthorized(true, userId: 'debug-uid');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(logger.enabled, isTrue);
    expect(logger.requested, isTrue);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/flutter-debug-logs');
    expect(requests.single.body, contains('"eventName":"debug.start"'));
    expect(requests.single.body, contains('"source":"authorized_profile"'));
    expect(requests.single.body, contains('"debugUserId":"debug-uid"'));
  });

  test(
      'authorized debug users flush recent events recorded before profile load',
      () async {
    final requests = <http.Request>[];
    final logger = FlutterDebugLog.instance;
    logger.configureForTest(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 201);
      }),
      auth: _TestApiAuthService(),
      authorized: false,
      requested: false,
    );
    addTearDown(() {
      logger.configureForTest(
        client: MockClient((_) async => http.Response('{}', 200)),
        authorized: false,
        requested: false,
      );
    });

    logger.record(
      'router.initialized',
      category: 'navigation',
      routePath: '/marketplace/en/cards/633200/rare-leafeon',
      browserUri: Uri.parse(
          'https://pokoin.com/marketplace/en/cards/633200/rare-leafeon'),
    );
    logger.setAuthorized(true, userId: 'debug-uid');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(requests, hasLength(2));
    expect(requests.first.body, contains('"eventName":"router.initialized"'));
    expect(requests.first.body, contains('"debugUserId":"debug-uid"'));
    expect(requests.last.body, contains('"eventName":"debug.start"'));
  });
}
