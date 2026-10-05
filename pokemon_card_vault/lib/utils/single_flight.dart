/// Shares only an in-progress operation, never a completed (possibly stale) value.
class SingleFlight<T> {
  Future<T>? _pending;

  Future<T> run(Future<T> Function() load) => _pending ??= _load(load);

  Future<T> _load(Future<T> Function() load) async {
    try {
      return await Future<T>.sync(load);
    } finally {
      _pending = null;
    }
  }
}
