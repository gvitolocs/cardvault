import 'dart:async';
import 'package:flutter/foundation.dart';
import '../model/listing_draft.dart';
import '../model/scanner.dart';
import '../service/scan_clipboard_service.dart';

class ScanClipboardController extends ChangeNotifier {
  ScanClipboardController({ScanClipboardService? service})
      : _service = service ?? ScanClipboardService();
  final ScanClipboardService _service;
  List<ListingDraft> _items = [];
  String? _uid;
  int _epoch = 0;
  bool _initialized = false, _disposed = false;
  bool loading = false, available = false;
  int transferRevision = 0;
  String? error, message;
  Future<void> _loading = Future.value(), _tail = Future.value();
  final _publishing = <String>{};
  final _countryLoads = <String>{};
  int get scopeRevision => _epoch;
  List<ListingDraft> get items => List.unmodifiable(_items);
  int get pendingCount => _items.where((d) => d.pending).length;
  bool get authenticated => _uid != null;
  ListingDraft? find(String id) => _items.where((d) => d.id == id).firstOrNull;
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setUser(String? uid) {
    if (_initialized && _uid == uid) return _loading;
    _initialized = true;
    final epoch = ++_epoch;
    _uid = uid;
    _items = [];
    available = false;
    loading = true;
    error = message = null;
    _notify();
    return _loading = _load(uid, epoch);
  }

  Future<void> _load(String? uid, int epoch) async {
    try {
      final items = await _service.read(uid);
      if (!_current(epoch)) return;
      _items = items;
      available = true;
    } catch (_) {
      if (_current(epoch)) {
        error =
            'Clipboard non leggibile. Riprova senza sovrascrivere le bozze.';
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> retryLoad() {
    if (loading || available) return Future.value();
    _initialized = false;
    return setUser(_uid);
  }

  /// Serialize edits against the latest snapshot, including rapid form input.
  /// Commit to the UI only after the atomic local write and flush succeeded.
  Future<bool> _mutate(List<ListingDraft> Function(List<ListingDraft>) edit) {
    final uid = _uid, epoch = _epoch, loaded = _loading;
    final operation = _tail.then((_) async {
      await loaded;
      if (!_current(epoch) || !available) return false;
      try {
        final next = edit(List.of(_items));
        await _service.write(uid, next);
        if (!_current(epoch)) return false;
        _items = next;
        error = null;
        _notify();
        return true;
      } catch (_) {
        if (_current(epoch)) {
          error =
              'Bozza non salvata sul dispositivo. Riprova la modifica; le scansioni restano nella linguetta.';
          _notify();
        }
        return false;
      }
    });
    _tail = operation.then((_) {});
    return operation;
  }

  Future<void> storeScans(List<ScannedCard> cards) async {
    final epoch = _epoch;
    final success = await _mutate((items) {
      final ids = items.map((d) => d.id).toSet();
      return [
        ...items,
        for (final card in cards)
          if (ids.add(card.id)) ListingDraft(card: card)
      ];
    });
    if (!success || !_current(epoch)) throw StateError('Clipboard not saved');
    ++transferRevision;
    message =
        '${cards.length} ${cards.length == 1 ? 'bozza trasferita' : 'bozze trasferite'} in Clipboard.';
    _notify();
  }

  Future<bool> importDraft(ListingDraft draft) => _mutate((items) =>
      items.any((d) => d.id == draft.id) ? items : [...items, draft]);
  Future<bool> edit(String id, ListingDraft Function(ListingDraft) change) =>
      _mutate((items) => [
            for (final item in items)
              if (item.id == id && item.editable) change(item) else item
          ]);
  Future<bool> remove(String id) => _mutate((items) => items
      .where((d) => d.id != id || d.status == DraftStatus.publishing)
      .toList());
  Future<void> flush() => _tail;
  Future<void> loadSellerCountry(String id) async {
    final uid = _uid, epoch = _epoch, draft = find(id);
    if (uid == null ||
        draft == null ||
        draft.shipFromCountryManual ||
        !draft.editable) {
      return;
    }
    final key = '$epoch:$id';
    if (!_countryLoads.add(key)) return;
    try {
      final country = await _service.sellerCountry(uid);
      if (!_current(epoch) || country.isEmpty) return;
      await edit(
          id,
          (d) =>
              d.shipFromCountryManual ? d : d.edit(shipFromCountry: country));
    } catch (_) {/* Manual origin selection remains available. */} finally {
      _countryLoads.remove(key);
    }
  }

  Future<bool> publish(String id, {String sellerName = 'Pokoin seller'}) async {
    final key = '$_epoch:$id';
    if (!_publishing.add(key)) return false;
    try {
      return await _publish(id, sellerName);
    } finally {
      _publishing.remove(key);
    }
  }

  Future<bool> _publish(String id, String sellerName) async {
    final uid = _uid, epoch = _epoch;
    await flush();
    if (!_current(epoch)) return false;
    final draft = find(id);
    if (uid == null) {
      error = 'Accedi prima di pubblicare la bozza.';
      _notify();
      return false;
    }
    if (draft == null || !draft.editable) return false;
    try {
      _service.validate(draft);
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return false;
    }
    // Persist the in-flight marker before any remote write. A process restart
    // changes it to uncertain, so another tap can never duplicate the POST.
    final started = await _mutate((items) => [
          for (final item in items)
            if (item.id == id)
              item.edit(status: DraftStatus.publishing)
            else
              item
        ]);
    if (!started || !_current(epoch)) return false;
    try {
      final listingId = await _service.publish(uid, draft, sellerName);
      if (!_current(epoch)) return false;
      final saved = await _mutate((items) => [
            for (final item in items)
              if (item.id == id)
                item.edit(status: DraftStatus.published, listingId: listingId)
              else
                item
          ]);
      if (saved) {
        message = 'Annuncio pubblicato su Pokoin.';
        _notify();
      }
      return saved;
    } catch (e) {
      if (!_current(epoch)) return false;
      final definite = e is DraftPublishFailure && e.definite;
      await _mutate((items) => [
            for (final item in items)
              if (item.id == id)
                item.edit(
                    status:
                        definite ? DraftStatus.editing : DraftStatus.uncertain)
              else
                item
          ]);
      if (_current(epoch)) {
        error = definite
            ? e.message
            : 'Esito della pubblicazione incerto. Premi Verifica pubblicazione prima di riprovare.';
        _notify();
      }
      return false;
    }
  }

  Future<void> reconcile(String id) async {
    final uid = _uid, epoch = _epoch, draft = find(id);
    if (uid == null || draft == null || draft.editable || !draft.pending) {
      return;
    }
    try {
      final listingId = await _service.reconcile(uid, draft);
      if (!_current(epoch)) return;
      if (listingId == null || listingId.isEmpty) {
        error =
            'Annuncio non ancora verificato. Controlla i tuoi listing prima di crearne un altro.';
      } else {
        await _mutate((items) => [
              for (final item in items)
                if (item.id == id)
                  item.edit(status: DraftStatus.published, listingId: listingId)
                else
                  item
            ]);
        if (!_current(epoch)) return;
        message = 'Pubblicazione verificata.';
      }
    } catch (_) {
      if (_current(epoch)) {
        error = 'Verifica non disponibile. La bozza resta in Clipboard.';
      }
    }
    if (_current(epoch)) _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
