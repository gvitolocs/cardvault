import 'dart:io';
import 'dart:typed_data';

import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'package:test/test.dart';

void main() {
  test('worker prepares once, ranks names and preserves typed filters',
      () async {
    final worker = await SuggestionWorker.start(
        File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync());
    addTearDown(worker.dispose);
    expect(await worker.suggest('pi'), isEmpty);
    final name = await worker.suggest('charziard');
    expect(name.first.display, 'Charizard');
    final collector = await worker.suggest('061 shieldon');
    expect(collector.first.query, contains('061'));
    expect(collector.first.display, 'Shieldon');
    final artist = await worker.suggest('komiya');
    expect(artist.first.kind, 'artist');
    expect(artist.first.display, 'Tomokazu Komiya');
    final set = await worker.suggest('expedition');
    expect(set.first.kind, 'set');
    expect(await worker.suggest('061/106'), isEmpty);
    final rarity = await worker.suggest('eevee fullart');
    expect(rarity.first.query, contains('fullart'));
    expect(rarity.first.query, isNot(contains('undefined')));
  });
  test('worker coalesces queued queries and rejects corrupted assets',
      () async {
    final worker = await SuggestionWorker.start(
        File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync());
    addTearDown(worker.dispose);
    final first = worker.suggest('charizard braixen');
    final skipped = worker.suggest('mewtwo');
    final skippedCheck =
        expectLater(skipped, throwsA(isA<SuggestionSuperseded>()));
    final latest = worker.suggest('pikachu');
    await first;
    await skippedCheck;
    expect((await latest).first.display, 'Pikachu');
    await expectLater(SuggestionWorker.start(Uint8List(4)), throwsStateError);
  });
  test('disposal rejects further work', () async {
    final worker = await SuggestionWorker.start(
        File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync());
    worker.dispose();
    await expectLater(worker.suggest('pikachu'), throwsStateError);
  });
}
