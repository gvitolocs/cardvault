import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../model/scanner.dart';
import '../service/scanner_service.dart';

class ScannerController extends ChangeNotifier {
  ScannerController(
      {ScannerService? service,
      Future<void> Function(List<ScannedCard>)? storeDrafts})
      : _service = service ?? ScannerService(),
        _storeDrafts = storeDrafts;
  final ScannerService _service;
  final Future<void> Function(List<ScannedCard>)? _storeDrafts;
  final String _captureSession =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  ScanMode mode = ScanMode.batch;
  String? singleCaptureId;
  String? _uid, _batchId;
  int _epoch = 0, _sequence = 0;
  bool _disposed = false, _recognizing = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  List<ScannedCard> _cards = [];
  List<ScannerCandidate> candidates = [];
  List<ScannedCard> get cards => List.unmodifiable(_cards);
  ScanDestination destination = ScanDestination.collection;
  bool busy = false, ready = false, preparing = false, needsReload = false;
  bool activated = false,
      cameraPaused = true,
      pricing = false,
      confirmationPending = false;
  String? message, cameraError;
  String? _stableId, _latchedId, _lastCaptureId, _uncertainId;
  int _stableHits = 0, _emptyFrames = 0;
  Set<String> _knownBeforeAdd = {};
  Future<void>? _reviewing;
  final _pricedFacets = <String, String>{};
  int get quantity => _cards.fold(0, (sum, row) => sum + row.quantity);
  bool get authenticated => _uid != null;
  bool get acceptsFrame =>
      activated &&
      ready &&
      !_recognizing &&
      !busy &&
      !confirmationPending &&
      !cameraPaused &&
      !_disposed &&
      DateTime.now().difference(_lastFrame).inMilliseconds >= 650;
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setUser(String? uid) {
    if (_uid == uid) return;
    ++_epoch;
    _uid = uid;
    _batchId = null;
    _cards = [];
    singleCaptureId = null;
    candidates = [];
    busy = false;
    needsReload = false;
    message = null;
    _uncertainId = null;
    confirmationPending = false;
    _pricedFacets.clear();
    _reviewing = null;
    pricing = false;
    activated = false;
    cameraPaused = true;
    _resetLatch();
    _notify();
  }

  void _resetLatch() {
    _stableId = null;
    _latchedId = null;
    _lastCaptureId = null;
    _stableHits = 0;
    _emptyFrames = 0;
  }

  Future<void> start() async {
    activated = true;
    cameraPaused = false;
    _resetLatch();
    _notify();
    await prepare();
  }

  void selectMode(ScanMode value) {
    if (busy || mode == value) return;
    mode = value;
    singleCaptureId = null;
    _resetLatch();
    _notify();
  }

  Future<bool> copyToClipboard({String? onlyId}) async {
    if (busy || _cards.isEmpty || _storeDrafts == null) return false;
    final epoch = _epoch;
    busy = true;
    cameraPaused = true;
    _notify();
    try {
      // Local drafts must remain copyable when indicative-price APIs are offline.
      await review().timeout(const Duration(seconds: 2), onTimeout: () {});
      if (!_current(epoch)) return false;
      final copied =
          _cards.where((c) => onlyId == null || c.id == onlyId).toList();
      if (copied.isEmpty) return false;
      await _storeDrafts(copied);
      if (!_current(epoch)) return false;
      final ids = copied.map((c) => c.id).toSet();
      _cards = _cards.where((c) => !ids.contains(c.id)).toList();
      _pricedFacets.removeWhere((id, _) => ids.contains(id));
      singleCaptureId = null;
      confirmationPending = false;
      needsReload = false;
      message = 'Bozze salvate in Clipboard. Puoi continuare a scansionare.';
      return true;
    } catch (_) {
      if (_current(epoch)) {
        message =
            'Trasferimento non riuscito. Le carte restano nella linguetta: riprova.';
      }
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  void leave() {
    activated = false;
    cameraPaused = true;
    _resetLatch();
  }

  void selectDestination(ScanDestination value) {
    if (busy || confirmationPending || destination == value) return;
    destination = value;
    message = null;
    _notify();
  }

  void pauseCamera(bool paused) {
    if (!paused && mode == ScanMode.single && singleCaptureId != null) return;
    if (cameraPaused == paused) return;
    cameraPaused = paused;
    _notify();
    if (paused) unawaited(review());
  }

  Future<void> prepare() async {
    if (ready || preparing || _disposed) return;
    preparing = true;
    cameraError = null;
    _notify();
    try {
      await _service.prepare();
      ready = true;
    } catch (_) {
      cameraError = 'Impossibile avviare il riconoscimento. Riprova.';
    } finally {
      preparing = false;
      _notify();
    }
  }

  Future<void> recognize(ScannerFrame frame) async {
    if (!acceptsFrame) return;
    _recognizing = true;
    _lastFrame = DateTime.now();
    final epoch = _epoch;
    try {
      final found = await _service.recognize(frame);
      if (_current(epoch) && activated && !cameraPaused) {
        recordRecognition(found);
        cameraError = null;
      }
    } catch (_) {
      if (_current(epoch)) {
        cameraError = 'Riconoscimento interrotto. Riprova il riconoscimento.';
        ready = false;
        _notify();
      }
    } finally {
      _recognizing = false;
    }
  }

  /// Two consecutive observations accept one card. A held card updates its
  /// best scores, and must leave the view (or change) before counting again.
  void recordRecognition(List<ScannerCandidate> found) {
    if (!activated ||
        cameraPaused ||
        busy ||
        confirmationPending ||
        _disposed) {
      return;
    }
    final ranked = found.where((c) => c.score.isFinite && c.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final unique = <String, ScannerCandidate>{};
    for (final candidate in ranked) {
      unique.putIfAbsent(candidate.cardId, () => candidate);
    }
    candidates = ranked.isNotEmpty && ranked.first.score >= .60
        ? unique.values.take(3).toList()
        : [];
    if (candidates.isEmpty) {
      _stableId = null;
      _stableHits = 0;
      if (++_emptyFrames >= 2) {
        _latchedId = null;
        _lastCaptureId = null;
      }
      _notify();
      return;
    }
    _emptyFrames = 0;
    final best = candidates.first;
    if (best.cardId == _latchedId) {
      final index = _cards.indexWhere((row) => row.id == _lastCaptureId);
      if (index >= 0) {
        final previous = _cards[index];
        final all = <String, ScannerCandidate>{};
        for (final item in [...previous.alternatives, ...candidates]) {
          if (!all.containsKey(item.cardId) ||
              all[item.cardId]!.score < item.score) {
            all[item.cardId] = item;
          }
        }
        final alternatives = all.values.toList()
          ..sort((a, b) => b.score.compareTo(a.score));
        _cards[index] =
            previous.edit(alternatives: alternatives.take(3).toList());
      }
      _notify();
      return;
    }
    _stableHits = _stableId == best.cardId ? _stableHits + 1 : 1;
    _stableId = best.cardId;
    if (_stableHits >= 2) {
      final id = 'local:$_captureSession:${++_sequence}';
      _cards = [
        ..._cards,
        ScannedCard(
            id: id,
            cardId: best.cardId,
            name: best.name,
            setName: best.setName,
            number: best.number,
            imageUrl: '',
            alternatives: List.unmodifiable(candidates))
      ];
      _latchedId = best.cardId;
      _lastCaptureId = id;
      message = '${best.name} acquisita · da confermare.';
      if (mode == ScanMode.single) {
        singleCaptureId = id;
        cameraPaused = true;
      }
    }
    _notify();
  }

  void edit(ScannedCard card) {
    if (busy || needsReload || confirmationPending) return;
    _cards = [
      for (final row in _cards)
        if (row.id == card.id) card else row
    ];
    message = null;
    _notify();
    if (cameraPaused) unawaited(review());
  }

  void chooseCandidate(String id, ScannerCandidate candidate) {
    final card = _cards.where((row) => row.id == id).firstOrNull;
    if (card == null ||
        !card.alternatives.any((c) => c.cardId == candidate.cardId)) {
      return;
    }
    edit(card.edit(selected: candidate));
  }

  Future<void> review() {
    if (_disposed) return Future.value();
    if (_reviewing != null) return _reviewing!;
    late final Future<void> operation;
    operation = _review().whenComplete(() {
      if (identical(_reviewing, operation)) _reviewing = null;
    });
    return _reviewing = operation;
  }

  Future<void> _review() async {
    final epoch = _epoch;
    pricing = true;
    _notify();
    try {
      // Re-evaluate pending facets after each request so user changes made while
      // a price is loading are not overwritten by the older response.
      while (_current(epoch)) {
        final pending = _cards
            .where((row) => _pricedFacets[row.id] != row.facets)
            .take(3)
            .toList();
        if (pending.isEmpty) break;
        for (final row in pending) {
          _pricedFacets[row.id] = row.facets;
        }
        final results = await Future.wait(pending.map((row) async {
          final data = await _service.marketData(row);
          return (row: row, data: data);
        }));
        if (!_current(epoch)) return;
        for (final result in results) {
          _cards = [
            for (final current in _cards)
              if (current.id == result.row.id &&
                  current.facets == result.row.facets)
                current.edit(market: result.data)
              else
                current
          ];
        }
        _notify();
      }
    } catch (_) {
      /* Indicative prices must never block collection ownership. */
    } finally {
      if (_current(epoch)) {
        pricing = false;
        _notify();
      }
    }
  }

  void _merge(ScannerBatch batch) {
    final previous = {for (final row in _cards) row.id: row};
    final locals = _cards.where((row) => row.isLocal).toList();
    if (_uncertainId != null) {
      final pending = locals.where((row) => row.id == _uncertainId).firstOrNull;
      final matches = batch.cards
          .where((row) =>
              !_knownBeforeAdd.contains(row.id) &&
              row.cardId == pending?.cardId)
          .toList();
      if (pending != null && matches.length == 1) {
        previous[matches.single.id] = pending.edit(id: matches.single.id);
        locals.removeWhere((row) => row.id == pending.id);
        _uncertainId = null;
      }
    }
    _cards = [...batch.cards.map((row) => previous[row.id] ?? row), ...locals];
  }

  Future<void> reload() async {
    if (busy || _uid == null) return;
    final uid = _uid!, epoch = _epoch;
    busy = true;
    message = null;
    _notify();
    try {
      final batch = await (_batchId == null
          ? _service.open(uid)
          : _service.read(uid, _batchId!));
      if (!_current(epoch)) return;
      if (batch.submitted) {
        // A submitted batch may still be awaiting ownership verification.
        // Keep those rows so Confirm can retry the read without creating copies.
        message =
            'Gruppo già inviato. Premi Conferma per verificare il possesso.';
      } else {
        _batchId = batch.id;
        _merge(batch);
      }
      needsReload = _uncertainId != null;
      if (needsReload) {
        message =
            'Aggiunta ancora incerta. Ricarica o rimuovi la riga locale prima di continuare.';
      }
    } catch (_) {
      if (_current(epoch)) {
        message = 'Impossibile recuperare le scansioni. Riprova.';
        needsReload = true;
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> remove(String id) async {
    if (busy || confirmationPending) return;
    if (id.startsWith('local:')) {
      _cards = _cards.where((row) => row.id != id).toList();
      if (_uncertainId == id) {
        _uncertainId = null;
        needsReload = false;
      }
      _notify();
      return;
    }
    if (needsReload || _uid == null) return;
    final epoch = _epoch, uid = _uid!;
    busy = true;
    _notify();
    try {
      await _service.remove(uid, id);
      if (_current(epoch)) {
        _cards = _cards.where((row) => row.id != id).toList();
      }
    } catch (_) {
      if (_current(epoch)) {
        needsReload = true;
        message = 'Ricarica per verificare la rimozione.';
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> save() async {
    if (busy || needsReload || _uid == null || _cards.isEmpty) return false;
    final epoch = _epoch, uid = _uid!, target = destination;
    busy = true;
    cameraPaused = true;
    message = null;
    _notify();
    try {
      await review();
      if (!_current(epoch)) return false;
      if (target == ScanDestination.listing &&
          _cards.any((row) => !row.validPrice)) {
        throw const FormatException(
            'Inserisci un prezzo PK valido per ogni listing.');
      }
      if (_batchId == null) {
        final batch = await _service.open(uid);
        if (!_current(epoch)) return false;
        _batchId = batch.id;
        if (batch.cards.isNotEmpty) {
          _merge(batch);
          throw const FormatException(
              'Ripristinate altre scansioni aperte. Controlla la lista prima di confermare.');
        }
      }
      for (final local in _cards.where((row) => row.isLocal).toList()) {
        _knownBeforeAdd =
            _cards.where((row) => !row.isLocal).map((row) => row.id).toSet();
        _uncertainId = local.id;
        final added = await _service.add(
            uid,
            _batchId!,
            ScannerCandidate(
                cardId: local.cardId,
                name: local.name,
                setName: local.setName,
                number: local.number,
                score: 1));
        if (!_current(epoch)) return false;
        _cards = [
          for (final row in _cards)
            if (row.id == local.id) row.edit(id: added.id) else row
        ];
        _uncertainId = null;
      }
      confirmationPending = true;
      await _service.save(uid, _batchId!, List.of(_cards), target);
      if (!_current(epoch)) return false;
      _cards = [];
      confirmationPending = false;
      _batchId = null;
      _pricedFacets.clear();
      message = target == ScanDestination.collection
          ? 'Possesso confermato: carte aggiunte alla collezione.'
          : 'Possesso confermato e listing pubblicati.';
      return true;
    } on ScannerRequestFailure catch (error) {
      if (_current(epoch)) {
        message = error.message;
        needsReload = _uncertainId != null;
      }
      return false;
    } on FormatException catch (error) {
      if (_current(epoch)) {
        message = error.message;
        needsReload = _uncertainId != null;
      }
      return false;
    } catch (_) {
      if (_current(epoch)) {
        needsReload = _uncertainId != null;
        message = needsReload
            ? 'Aggiunta non confermata. Ricarica e verifica prima di riprovare.'
            : 'Salvataggio non confermato. Riprova: le carte già salvate non verranno duplicate.';
      }
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
