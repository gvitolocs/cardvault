import 'dart:async';
import 'dart:developer';
import 'dart:isolate';
import 'dart:typed_data';

import 'bundled_dictionary.dart';
import 'catalog_intent.dart';
import 'compact_query.dart';
import 'pkd1.dart';
import 'artist_query.dart';

class SuggestionAnalysis {
  const SuggestionAnalysis(this.rows, {this.artist});
  final List<LocalSuggestion> rows;
  final ArtistQuery? artist;
}

class SuggestionTask {
  const SuggestionTask(this.analysis, this.artist);
  final Future<SuggestionAnalysis> analysis;
  final Future<ArtistQuery?> artist;
}

class LocalSuggestion {
  const LocalSuggestion(
      {required this.display,
      required this.query,
      required this.kind,
      this.artist,
      this.slug = ''});
  final String display, query, kind, slug;
  final ArtistQuery? artist;
}

class SuggestionSuperseded implements Exception {}

class _Request {
  _Request(this.id, this.query);
  final int id;
  final String query;
  final result = Completer<SuggestionAnalysis>();
  final artist = Completer<ArtistQuery?>();

  void fail(Object error) {
    if (!artist.isCompleted) artist.complete(null);
    result.completeError(error);
  }
}

class _Work {
  const _Work(this.id, this.query);
  final int id;
  final String query;
}

class _Answer {
  const _Answer(this.id, this.rows, {this.artist});
  final int id;
  final List<LocalSuggestion> rows;
  final ArtistQuery? artist;
}

class _Failure {
  const _Failure(this.id, this.message);
  final int id;
  final String message;
}

class _ArtistAnswer {
  const _ArtistAnswer(this.id, this.artist);
  final int id;
  final ArtistQuery? artist;
}

/// One worker per engine. At most one query runs and one latest query waits.
/// Dictionary preparation and every rank/parse stay outside the UI isolate.
class SuggestionWorker {
  SuggestionWorker._();
  final _replies = ReceivePort();
  final _ready = Completer<void>();
  Isolate? _isolate;
  SendPort? _commands;
  _Request? _active, _queued;
  var _nextId = 0;
  var _closed = false;

  static Future<SuggestionWorker> start(Uint8List bytes) async {
    final worker = SuggestionWorker._();
    worker._replies.listen(worker._receive);
    try {
      worker._isolate = await Isolate.spawn(_workerMain,
          (worker._replies.sendPort, TransferableTypedData.fromList([bytes])),
          onError: worker._replies.sendPort, onExit: worker._replies.sendPort);
      await worker._ready.future.timeout(const Duration(seconds: 15));
      return worker;
    } catch (_) {
      worker.dispose();
      rethrow;
    }
  }

  Future<List<LocalSuggestion>> suggest(String query) async =>
      (await analyze(query)).rows;

  Future<SuggestionAnalysis> analyze(String query) => schedule(query).analysis;

  SuggestionTask schedule(String query) {
    if (_closed) {
      final error = Future<SuggestionAnalysis>.error(
          StateError('Suggestion worker disposed'));
      error.ignore();
      return SuggestionTask(error, Future.value(null));
    }
    final request = _Request(++_nextId, query);
    // A caller may need only the early artist answer; full-rank failures still
    // propagate to analysis consumers without becoming unhandled errors.
    request.result.future.ignore();
    if (_active == null) {
      _send(request);
    } else {
      _queued?.fail(SuggestionSuperseded());
      _queued = request;
    }
    return SuggestionTask(request.result.future, request.artist.future);
  }

  void _send(_Request request) {
    _active = request;
    _commands!.send(_Work(request.id, request.query));
  }

  void _receive(dynamic message) {
    if (_closed) {
      return;
    }
    if (message is SendPort) {
      _commands = message;
      _ready.complete();
      return;
    }
    if (message is _Failure && message.id == 0) {
      if (!_ready.isCompleted) {
        _ready.completeError(StateError(message.message));
      }
      return;
    }
    if (message is List || message == null) {
      final error = StateError('Suggestion worker exited');
      if (!_ready.isCompleted) {
        _ready.completeError(error);
      }
      _active?.fail(error);
      _active = null;
      _queued?.fail(error);
      _queued = null;
      _closed = true;
      _replies.close();
      return;
    }
    final active = _active;
    if (message is _ArtistAnswer && active?.id == message.id) {
      if (!active!.artist.isCompleted) active.artist.complete(message.artist);
      return;
    }
    if (message is _Answer && active?.id == message.id) {
      if (!active!.artist.isCompleted) active.artist.complete(message.artist);
      active.result.complete(SuggestionAnalysis(List.unmodifiable(message.rows),
          artist: message.artist));
    } else if (message is _Failure && active?.id == message.id) {
      active!.fail(StateError(message.message));
    } else {
      return;
    }
    _active = null;
    final next = _queued;
    _queued = null;
    if (next != null) {
      _send(next);
    }
  }

  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _replies.close();
    final error = StateError('Suggestion worker disposed');
    _active?.fail(error);
    _queued?.fail(error);
    _active = null;
    _queued = null;
  }
}

void _workerMain((SendPort, TransferableTypedData) bootstrap) {
  final replies = bootstrap.$1;
  try {
    final bytes = bootstrap.$2.materialize().asUint8List();
    final engine = SuggestEngine(
        decodePkd1(bytes, expectedContentHash: bundledDictionaryContentHash));
    final artistResolver = ArtistQueryResolver(engine.dictionary, engine.names);
    final commands = ReceivePort();
    replies.send(commands.sendPort);
    commands.listen((message) {
      if (message is! _Work) {
        return;
      }
      Timeline.startSync('suggest.query',
          arguments: {'characters': message.query.length});
      try {
        if (!suggestLiveReady(message.query)) {
          replies.send(_Answer(message.id, const []));
          return;
        }
        final artist = artistResolver.resolve(message.query);
        // Release API routing before the more expensive fuzzy name ranking.
        replies.send(_ArtistAnswer(message.id, artist));
        if (artist != null) {
          final parsed = engine.parseTypedQuery(artist.remainingQuery);
          final context = [
            ...parsed.setTokens,
            ...parsed.numberTokens,
            ...parsed.artTokens,
            ...parsed.rarityTokens,
          ].map((token) => token.token);
          final names = parsed.nameQuery.isEmpty
              ? null
              : engine.rankNames(parsed.nameQuery);
          replies.send(_Answer(
              message.id,
              [
                if (names == null)
                  LocalSuggestion(
                      display: artist.display,
                      query: message.query,
                      artist: artist,
                      kind: 'artist',
                      slug: artist.slug)
                else
                  for (final name
                      in names.where((row) => row.withinCap).take(6))
                    LocalSuggestion(
                        display: '${name.display} · ${artist.display}',
                        query: [name.display, ...context, artist.display]
                            .join(' '),
                        artist: ArtistQuery(
                            slug: artist.slug,
                            display: artist.display,
                            remainingQuery:
                                [name.display, ...context].join(' ')),
                        kind: 'name'),
              ],
              artist: artist));
          return;
        }
        final parsed = engine.parseTypedQuery(message.query);
        final intent = engine.catalogIntent(message.query);
        final result = <LocalSuggestion>[];
        if (parsed.bareCollector) {
          replies.send(_Answer(message.id, const []));
          return;
        }
        if (intent.kind == 'set' && parsed.setOnly) {
          if (intent.display.isNotEmpty) {
            result.add(LocalSuggestion(
                display: intent.display,
                query: intent.display,
                kind: intent.kind,
                slug: intent.slug));
          }
        } else {
          final ranked = intent.kind == 'artist'
              ? intent.ranked
              : intent.kind == 'set'
                  ? intent.ranked
                  : engine.rankNames(parsed.nameQuery);
          final context = [
            if (intent.kind == 'name')
              ...[
                ...parsed.setTokens,
                ...parsed.numberTokens,
                ...parsed.artTokens,
                ...parsed.rarityTokens
              ].map((t) => t.token)
          ];
          final seen = <String>{};
          for (final row in ranked) {
            if (!seen.add(row.display)) {
              continue;
            }
            final selectionQuery = [row.display, ...context].join(' ');
            if (selectionQuery.length > 180) {
              continue;
            }
            result.add(LocalSuggestion(
                display: row.display,
                query: selectionQuery,
                kind: intent.kind,
                artist: intent.kind == 'artist'
                    ? ArtistQuery(
                        slug: row.slug,
                        display: row.display,
                        remainingQuery: '')
                    : null,
                slug: row.slug));
            if (result.length == 6) {
              break;
            }
          }
        }
        replies.send(_Answer(message.id, result));
      } catch (error) {
        replies.send(_Failure(message.id, '$error'));
      } finally {
        Timeline.finishSync();
      }
    });
  } catch (error) {
    replies.send(_Failure(0, '$error'));
  }
}
