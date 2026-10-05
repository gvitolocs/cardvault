import 'package:hive/hive.dart';

import '../models/pokemon_card.dart';

final _writers = Expando<_CacheWriter>();

/// Update only incoming cards; never clear/rewrite the surrounding catalog.
/// Serialize writes per box so overlapping fetches cannot add duplicate IDs.
Future<void> upsertMarketplaceCardCache(
  Box<PokemonCard> box,
  Iterable<PokemonCard> cards,
) {
  final incoming = <String, PokemonCard>{
    for (final card in cards)
      if (card.id.isNotEmpty) card.id: card,
  };
  if (incoming.isEmpty) return Future<void>.value();
  final writer = _writers[box] ??= _CacheWriter();
  return writer.run(() async {
    final keysById = <String, dynamic>{};
    for (final key in box.keys) {
      final id = box.get(key)?.id;
      if (id != null && id.isNotEmpty) keysById[id] = key;
    }
    final updates = <dynamic, PokemonCard>{};
    final additions = <PokemonCard>[];
    for (final entry in incoming.entries) {
      final key = keysById[entry.key];
      if (key == null) {
        additions.add(entry.value);
      } else {
        updates[key] = entry.value;
      }
    }
    if (updates.isNotEmpty) await box.putAll(updates);
    if (additions.isNotEmpty) await box.addAll(additions);
  });
}

class _CacheWriter {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() write) {
    final result = _tail.then((_) => write());
    // A failed write still reaches its caller, but must not poison later writes.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
