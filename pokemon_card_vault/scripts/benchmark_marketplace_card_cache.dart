import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

// Import the real implementation in the Flutter-only benchmark harness too.
// ignore: avoid_relative_lib_imports
import '../lib/models/pokemon_card.dart';
// ignore: avoid_relative_lib_imports
import '../lib/services/marketplace_card_cache.dart';

PokemonCard _card(int id, {bool updated = false}) => PokemonCard.fromJson({
      'id': '$id',
      'name': updated ? 'Updated $id' : 'Card $id',
      'releaseDate': '2026-01-01T00:00:00.000',
    });

/// Local disk microbenchmark, not an emulator or end-to-end startup measurement.
Future<void> main() async {
  final directory =
      await Directory.systemTemp.createTemp('pokoin-cache-bench-');
  Hive.init(directory.path);
  Hive.registerAdapter(PokemonCardAdapter());
  try {
    for (final size in [1000, 10000]) {
      for (var sample = 0; sample < 3; sample++) {
        final before =
            await Hive.openBox<PokemonCard>('before_${size}_$sample');
        final after = await Hive.openBox<PokemonCard>('after_${size}_$sample');
        await before.addAll(List.generate(size, (index) => _card(index)));
        await after.addAll(List.generate(size, (index) => _card(index)));
        List<PokemonCard> snapshot() => [
              ...List.generate(83, (index) => _card(index, updated: true)),
              ...List.generate(15, (index) => _card(size + index)),
            ];

        final baseline = Stopwatch()..start();
        final byId = {for (final card in before.values) card.id: card};
        for (final card in snapshot()) {
          byId[card.id] = card;
        }
        await before.clear();
        var key = 0;
        for (final card in byId.values) {
          await before.put(key++, card);
        }
        await before.flush();
        baseline.stop();

        final optimized = Stopwatch()..start();
        await upsertMarketplaceCardCache(after, snapshot());
        await after.flush();
        optimized.stop();
        final oldRecords = {
          for (final card in before.values) card.id: jsonEncode(card.toJson()),
        };
        final newRecords = {
          for (final card in after.values) card.id: jsonEncode(card.toJson()),
        };
        final sameRecords = oldRecords.length == newRecords.length &&
            oldRecords.entries
                .every((entry) => newRecords[entry.key] == entry.value);
        if (!sameRecords) throw StateError('Cache record parity failed');
        stdout.writeln(jsonEncode({
          'catalogSize': size,
          'sample': sample + 1,
          'incomingCards': 98,
          'baselineMs': baseline.elapsedMicroseconds / 1000,
          'optimizedMs': optimized.elapsedMicroseconds / 1000,
          'sameRecords': sameRecords,
        }));
        await before.close();
        await after.close();
      }
    }
  } finally {
    await Hive.close();
    await directory.delete(recursive: true);
  }
}
