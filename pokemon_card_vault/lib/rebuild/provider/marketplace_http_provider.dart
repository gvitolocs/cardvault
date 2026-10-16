import 'dart:async';
import 'package:http/http.dart' as http;

/// Timeout che interrompe la richiesta HTTP, anche durante la lettura del corpo.
class MarketplaceHttpProvider {
  MarketplaceHttpProvider(this._client);
  final http.Client _client;
  final _active = <Completer<void>>{};
  bool _disposed = false;

  Future<http.Response> get(Uri uri, {required Duration timeout}) async {
    if (_disposed) throw StateError('Provider disposed');
    final abort = Completer<void>();
    _active.add(abort);
    try {
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abort.future);
      final response = _client.send(request).then(http.Response.fromStream);
      return await response.timeout(timeout, onTimeout: () {
        if (!abort.isCompleted) abort.complete();
        throw TimeoutException('Marketplace request timed out', timeout);
      });
    } finally {
      // Include errori di lettura; la richiesta non resta attiva dopo il ritorno.
      if (!abort.isCompleted) abort.complete();
      _active.remove(abort);
    }
  }

  void cancelActive() {
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
    _active.clear();
  }

  void dispose() {
    _disposed = true;
    cancelActive();
  }
}
