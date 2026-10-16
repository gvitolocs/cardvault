import 'package:pokoin_suggest/pokoin_suggest.dart';
import '../provider/suggestion_dictionary_provider.dart';

class MarketplaceSuggestionService {
  MarketplaceSuggestionService({SuggestionDictionaryProvider? provider})
      : _provider = provider ?? SuggestionDictionaryProvider();
  final SuggestionDictionaryProvider _provider;
  Future<SuggestionWorker>? _pending;
  SuggestionWorker? _worker;
  bool _disposed = false;
  final _tasks = <String, Future<SuggestionTask>>{};

  Future<SuggestionWorker> _load() async {
    final worker = await SuggestionWorker.start(await _provider.readBundled());
    if (_disposed) {
      worker.dispose();
      throw StateError('Suggestion service disposed');
    }
    _worker = worker;
    return worker;
  }

  Future<List<LocalSuggestion>> suggest(String query) async {
    return (await (await _task(query)).analysis).rows;
  }

  Future<ArtistQuery?> resolveArtist(String query) async =>
      (await _task(query)).artist;

  Future<SuggestionTask> _task(String query) {
    final existing = _tasks[query];
    if (existing != null) return existing;
    final result = _runTask(query);
    _tasks[query] = result;
    if (_tasks.length > 8) _tasks.remove(_tasks.keys.first);
    return result;
  }

  Future<SuggestionTask> _runTask(String query) async {
    if (_disposed) {
      throw StateError('Suggestion service disposed');
    }
    final worker = await (_pending ??= _load());
    if (_disposed) {
      throw StateError('Suggestion service disposed');
    }
    return worker.schedule(query);
  }

  Future<void> warmUp() async {
    if (_disposed) {
      return;
    }
    await (_pending ??= _load());
  }

  void dispose() {
    _disposed = true;
    _worker?.dispose();
  }
}
