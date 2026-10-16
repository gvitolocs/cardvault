import 'dart:async';
import '../model/cardex.dart';
import '../provider/collection_provider.dart';

/// Coordina sessione e collezione senza dipendere da Riverpod o widget legacy.
class CollectionService {
  CollectionService({CollectionProvider? provider})
      : _provider = provider ?? CollectionProvider();
  final CollectionProvider _provider;

  Stream<CardCollection> watch() {
    late StreamController<CardCollection> output;
    StreamSubscription<String?>? session;
    StreamSubscription<List<OwnedCard>>? items;
    var version = 0;
    var cancelled = false;
    void emit(CardCollection collection) {
      if (!cancelled) output.add(collection);
    }

    void unavailable() =>
        emit(CardCollection(status: CollectionStatus.unavailable));
    Future<void> changeUser(String? uid) async {
      final request = ++version;
      final previous = items;
      items = null;
      emit(CardCollection(
          status:
              uid == null ? CollectionStatus.guest : CollectionStatus.loading));
      await previous?.cancel();
      if (cancelled || request != version || uid == null) return;
      items = _provider.watchItems(uid).listen((rows) {
        if (request == version) {
          emit(CardCollection(status: CollectionStatus.ready, items: rows));
        }
      }, onError: (Object error, StackTrace stack) {
        if (request == version) unavailable();
      });
    }

    output = StreamController<CardCollection>(onListen: () {
      emit(CardCollection(status: CollectionStatus.loading));
      session = _provider.watchUserId().listen((uid) {
        unawaited(changeUser(uid).catchError((Object error) {
          unavailable();
        }));
      }, onError: (Object error, StackTrace stack) {
        ++version;
        unawaited(items?.cancel());
        items = null;
        unavailable();
      });
    }, onCancel: () async {
      cancelled = true;
      ++version;
      await session?.cancel();
      await items?.cancel();
    });
    return output.stream;
  }
}
