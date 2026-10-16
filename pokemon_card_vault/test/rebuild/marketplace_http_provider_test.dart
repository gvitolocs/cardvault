import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pokoin/rebuild/provider/marketplace_http_provider.dart';

void main() {
  test('cancelActive aborts pending work and keeps the provider reusable',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    server.listen((request) {
      if (request.uri.path == '/waiting') {
        received.complete();
      } else {
        request.response.write('{}');
        request.response.close();
      }
    });
    final client = http.Client();
    final provider = MarketplaceHttpProvider(client);
    try {
      final waiting = provider.get(
          Uri.parse('http://127.0.0.1:${server.port}/waiting'),
          timeout: const Duration(seconds: 2));
      final aborted =
          expectLater(waiting, throwsA(isA<http.RequestAbortedException>()));
      await received.future;
      provider.cancelActive();
      await aborted;
      final ready = await provider.get(
          Uri.parse('http://127.0.0.1:${server.port}/ready'),
          timeout: const Duration(seconds: 2));
      expect(ready.body, '{}');
    } finally {
      provider.dispose();
      client.close();
      await server.close(force: true);
    }
  });

  test('timeout aborts an actual local HTTP request awaiting response headers',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestReceived = Completer<void>();
    server.listen((request) {
      requestReceived.complete();
      // Headers are deliberately withheld; do not release a real server job.
    });
    final client = http.Client();
    final provider = MarketplaceHttpProvider(client);
    try {
      final uri = Uri.parse('http://127.0.0.1:${server.port}/delayed');
      await expectLater(
          provider.get(uri, timeout: const Duration(milliseconds: 300)),
          throwsA(isA<TimeoutException>()));
      expect(requestReceived.isCompleted, isTrue);
      // A second native request is still usable after cancelling the first.
      final secondServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      secondServer.listen((request) {
        request.response.write('{}');
        request.response.close();
      });
      try {
        final response = await provider.get(
            Uri.parse('http://127.0.0.1:${secondServer.port}/ready'),
            timeout: const Duration(seconds: 2));
        expect(response.body, '{}');
      } finally {
        await secondServer.close(force: true);
      }
    } finally {
      provider.dispose();
      client.close();
      await server.close(force: true);
    }
  });

  test('timeout cancels a partially received response body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final headersSent = Completer<void>();
    server.listen((request) async {
      request.response.write('{');
      await request.response.flush();
      headersSent.complete();
    });
    final client = http.Client();
    final provider = MarketplaceHttpProvider(client);
    try {
      await expectLater(
          provider.get(Uri.parse('http://127.0.0.1:${server.port}/body'),
              timeout: const Duration(milliseconds: 300)),
          throwsA(isA<TimeoutException>()));
      expect(headersSent.isCompleted, isTrue);
    } finally {
      provider.dispose();
      client.close();
      await server.close(force: true);
    }
  });
}
