import 'dart:io';
import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'package:test/test.dart';

void main() {
  final engine = SuggestEngine(decodePkd1(
      File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync()));
  final resolver = ArtistQueryResolver(engine.dictionary, engine.names);
  for (final raw in [
    'Pikachu Komi',
    'Pikachu Komiya',
    'Komi Pikachu',
    'Pikachu Tomokazu Komiya',
    'Tomokazu Komiya Pikachu'
  ]) {
    test('binds name and artist separately: $raw', () {
      final result = resolver.resolve(raw)!;
      expect(result.slug, 'tomokazu-komiya');
      expect(result.remainingQuery, 'Pikachu');
    });
  }
  test('short prefixes and literal mechanics/names do not become artists', () {
    for (final raw in [
      'Pikachu Ko',
      'Mimikyu GX',
      'Pikachu V',
      "Imakuni?'s Doduo",
      'Pikachu'
    ]) {
      expect(resolver.resolve(raw), isNull, reason: raw);
    }
    expect(resolver.resolve('Komi')!.remainingQuery, isEmpty);
    expect(resolver.resolve('Pikachu Komi 025/165')!.remainingQuery,
        'Pikachu 025/165');
  });
  test('worker exposes early artist routing and contextual choices', () async {
    final worker = await SuggestionWorker.start(
        File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync());
    addTearDown(worker.dispose);
    final task = worker.schedule('Pikachu Komi');
    expect((await task.artist)!.slug, 'tomokazu-komiya');
    final result = await task.analysis;
    expect(result.rows.first.display, 'Pikachu · Tomokazu Komiya');
    expect(result.rows.first.query, 'Pikachu Tomokazu Komiya');
    expect(result.artist!.remainingQuery, 'Pikachu');
  });
}
