import '../constants/scanner_constants.dart';
import '../model/scanner.dart';
import '../provider/scanner_provider.dart';
import '../provider/scanner/scan_engine.dart';
import '../provider/scanner_market_provider.dart';

class ScannerService {
  ScannerService({ScannerProvider? provider, ScannerMarketProvider? market})
      : _provider = provider ?? ScannerProvider(),
        _market = market ?? ScannerMarketProvider();
  final ScannerProvider _provider;
  final ScannerMarketProvider _market;
  final _prices =
      <String, ({DateTime at, Future<ScannerMarketSnapshot> data})>{};

  Future<ScannerMarketData> marketData(ScannedCard card) async {
    var cached = _prices[card.cardId];
    if (cached == null ||
        DateTime.now().difference(cached.at) > const Duration(minutes: 5)) {
      if (_prices.length >= 64) _prices.remove(_prices.keys.first);
      cached = (at: DateTime.now(), data: _market.fetch(card.cardId));
      _prices[card.cardId] = cached;
    }
    final snapshot = await cached.data;
    final suggested =
        suggestPrice(card, snapshot.slices) ?? snapshot.card?.pricePkn;
    return ScannerMarketData(card: snapshot.card, suggested: suggested);
  }

  /// Port of the site's scan-pricing.js: exact facets, nearest condition,
  /// then other languages (English first), preferring fresh observed medians.
  static double? suggestPrice(ScannedCard card, List<ScannerSaleSlice> slices) {
    final pool = slices
        .where((s) => !s.graded && s.median.isFinite && s.median >= .01)
        .toList();
    final rungs = <bool Function(ScannerSaleSlice)>[
      (s) =>
          s.condition == card.condition &&
          s.language == card.language &&
          s.reverse == (card.foilState == 'reverse') &&
          !s.firstEdition,
      (s) => s.condition == card.condition && s.language == card.language,
      (s) => s.language == card.language,
      (s) => s.condition == card.condition,
      (s) => true,
    ];
    int distance(String condition) {
      final conditions = scannerConditions.keys.toList();
      final a = conditions.indexOf(condition),
          b = conditions.indexOf(card.condition);
      return a < 0 || b < 0 ? conditions.length : (a - b).abs();
    }

    for (var i = 0; i < rungs.length; i++) {
      final hits = pool.where(rungs[i]).toList();
      if (hits.isEmpty) continue;
      hits.sort((a, b) {
        if (i == 2) {
          final d = distance(a.condition).compareTo(distance(b.condition));
          if (d != 0) return d;
        }
        if (i >= 3) {
          final d = (b.language == 'EN' ? 1 : 0)
              .compareTo(a.language == 'EN' ? 1 : 0);
          if (d != 0) return d;
        }
        final day = b.day.compareTo(a.day);
        if (day != 0) return day;
        final samples = b.samples.compareTo(a.samples);
        return samples != 0 ? samples : b.listings.compareTo(a.listings);
      });
      return hits.first.median;
    }
    return null;
  }

  static String? publicCardId(String raw, {required String identity}) {
    if (identity != 'ct_id' || !RegExp(r'^[1-9]\d*$').hasMatch(raw)) {
      return null;
    }
    return (BigInt.parse(raw) * BigInt.two).toString();
  }

  Future<void> prepare() => ScanEngine.init(selectedGallery: 'western');
  Future<List<ScannerCandidate>> recognize(ScannerFrame frame) async {
    final result = await ScanEngine.scanFrame(
            format: frame.bgra ? 'bgra' : 'yuv420',
            width: frame.width,
            height: frame.height,
            sensorOrientation: frame.orientation,
            bgra: frame.bgra ? frame.planes[0] : null,
            bgraStride: frame.bgra ? frame.strides[0] : 0,
            y: frame.bgra ? null : frame.planes[0],
            u: frame.bgra ? null : frame.planes[1],
            v: frame.bgra ? null : frame.planes[2],
            yStride: frame.strides[0],
            uStride: frame.bgra ? 0 : frame.strides[1],
            vStride: frame.bgra ? 0 : frame.strides[2],
            uvPixelStride: frame.pixelStride)
        .timeout(const Duration(seconds: 20));
    // Bundled CNN ids are CardTrader. Never double TCGplayer or public ids.
    if (ScanEngine.identity != 'ct_id') {
      throw StateError('Unsupported scan identity');
    }
    final hits = result.hits
        .where((hit) =>
            hit.score.isFinite &&
            hit.score > 0 &&
            publicCardId(hit.id, identity: ScanEngine.identity) != null)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return hits
        .take(3)
        .map((hit) => ScannerCandidate(
            cardId: publicCardId(hit.id, identity: ScanEngine.identity)!,
            name: hit.title,
            setName: hit.setName,
            number: hit.collectorNumber,
            score: hit.score))
        .toList();
  }

  Future<ScannerBatch> open(String uid) => _provider.open(uid);
  Future<ScannerBatch> read(String uid, String id) => _provider.read(uid, id);
  Future<ScannedCard> add(String uid, String id, ScannerCandidate card) =>
      _provider.add(uid, id, card);
  Future<void> remove(String uid, String id) => _provider.remove(uid, id);
  Future<void> save(String uid, String id, List<ScannedCard> cards,
      ScanDestination destination) async {
    if (cards.isEmpty ||
        cards.any((card) =>
            !scannerConditions.containsKey(card.condition) ||
            !scannerLanguages.containsKey(card.language) ||
            card.quantity < 1 ||
            card.quantity > 99 ||
            (card.price.trim().isNotEmpty && !card.validPrice) ||
            (destination == ScanDestination.listing && !card.validPrice))) {
      throw const FormatException(
          'Controlla quantità e prezzi: per i listing il prezzo PK è obbligatorio.');
    }
    // Prevent silently submitting scans added elsewhere since the last review.
    final snapshot = await _provider.read(uid, id);
    if (snapshot.submitted) {
      if (snapshot.submittedDestination != null &&
          snapshot.submittedDestination != destination) {
        throw const FormatException(
            'Queste carte sono già state salvate nell’altra destinazione. Ricarica le scansioni.');
      }
      await _provider.verifyOwnership(uid, cards);
      return;
    }
    if (snapshot.cards.length != cards.length ||
        !snapshot.cards
            .every((row) => cards.any((card) => card.id == row.id))) {
      throw const FormatException(
          'Il gruppo è cambiato. Ricarica le carte prima di confermare.');
    }
    for (final card in cards) {
      await _provider.patch(uid, card);
    }
    await _provider.submit(uid, id, destination);
    await _provider.verifyOwnership(uid, cards);
  }
}
