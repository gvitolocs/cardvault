import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../cache/marketplace_image_cache.dart';
import '../../../model/card_ownership.dart';
import '../../shared/component/card_ownership_artwork.dart';
import '../../shared/component/card_language_selector.dart';
import '../../shared/atomics/collection_quantity_badge.dart';
import '../../../style/cardex_style.dart';

/// Route-local image warming; never runs in album grids or changes ownership.
class CardDetailsArtwork extends StatefulWidget {
  const CardDetailsArtwork({
    super.key,
    required this.cardName,
    required this.cardId,
    required this.fallbackUrl,
    required this.imageBuilder,
    required this.languageImages,
    this.ownership,
    this.onLanguageSelected,
    this.imageProvider,
  });
  final String cardName, cardId, fallbackUrl;
  final Map<String, String> languageImages;
  final CardOwnership? ownership;
  final Widget Function(String url) imageBuilder;
  final ValueChanged<String>? onLanguageSelected;
  final ImageProvider Function(String url, int decodeWidth)? imageProvider;
  static const inset = 12.0;
  static const scanWidth = 266.0;
  static const maxWidth = scanWidth + 2 * inset;
  static const outerAspectRatio =
      maxWidth / (scanWidth / CardexStyle.cardAspectRatio + 2 * inset);
  @override
  State<CardDetailsArtwork> createState() => _CardDetailsArtworkState();
}

class _CardDetailsArtworkState extends State<CardDetailsArtwork> {
  final _queued = <String>{}, _ready = <String>{}, _failed = <String>{};
  final _queue = Queue<String>();
  int _running = 0;
  bool _scheduled = false;
  double _decodeWidth = 266;

  void _schedule() {
    final ownership = widget.ownership;
    if (ownership?.known != true) return;
    for (final language in ownership!.languages.where((entry) => entry.owned)) {
      final url = widget.languageImages[language.code];
      if (url != null && _queued.add(url)) _queue.add(url);
    }
    if (_scheduled || _queue.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _drain();
    });
  }

  void _drain() {
    while (mounted && _running < 2 && _queue.isNotEmpty) {
      _running++;
      _warm(_queue.removeFirst());
    }
  }

  ImageProvider _provider(String url) {
    final pixels = (_decodeWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 768);
    return widget.imageProvider?.call(url, pixels) ??
        ResizeImage.resizeIfNeeded(
            pixels,
            null,
            CachedNetworkImageProvider(url,
                cacheManager: MarketplaceImageCache.instance));
  }

  Future<void> _warm(String url) async {
    var failed = false;
    try {
      await precacheImage(_provider(url), context, onError: (_, __) {
        failed = true;
      });
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      (failed ? _failed : _ready).add(url);
    });
    _running--;
    _drain();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final ownership = widget.ownership;
        final framed = ownership != null;
        final width =
            framed ? bounds.maxWidth : bounds.maxWidth.clamp(0, 266).toDouble();
        _decodeWidth = width - (framed ? CardDetailsArtwork.inset * 2 : 0);
        _schedule();
        final code = ownership?.selectedLanguage;
        final localized = widget.languageImages[code];
        final url = localized != null && _ready.contains(localized)
            ? localized
            : widget.fallbackUrl;
        final label = ownership?.selected?.label.toLowerCase();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: width,
              child: AspectRatio(
                  aspectRatio: framed
                      ? CardDetailsArtwork.outerAspectRatio
                      : CardexStyle.cardAspectRatio,
                  child: Stack(fit: StackFit.expand, children: [
                    Positioned.fill(
                        left: framed ? CardDetailsArtwork.inset : 0,
                        right: framed ? CardDetailsArtwork.inset : 0,
                        top: framed ? CardDetailsArtwork.inset : 0,
                        bottom: framed ? CardDetailsArtwork.inset : 0,
                        child: ownership == null
                            ? widget.imageBuilder(url)
                            : CardOwnershipArtwork(
                                image: widget.imageBuilder(url),
                                cardName: widget.cardName,
                                ownership: ownership,
                                showControls: false)),
                    if (ownership != null &&
                        (ownership.known || ownership.hasConfirmedCopies))
                      Positioned(
                          top: 0,
                          right: 0,
                          child: CardLanguageSelector(
                              ownership: ownership,
                              cardName: widget.cardName,
                              compact: true,
                              edgeAccent: false,
                              onSelected: (language) => _select(language))),
                    if (ownership?.known == true && ownership!.total > 0)
                      Positioned(
                          bottom: 0,
                          right: 0,
                          child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxWidth: width * .45),
                              child: CollectionQuantityBadge(
                                  quantity: ownership.total,
                                  compact: true,
                                  edgeAccent: false))),
                  ]))),
          if (localized != null && !_ready.contains(localized))
            Semantics(
                liveRegion: true,
                child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _failed.contains(localized)
                        ? Column(children: [
                            Text(
                                'Scansione in $label non disponibile. Mostrata immagine del catalogo.',
                                style: const TextStyle(fontSize: 11)),
                            TextButton(
                                onPressed: () async {
                                  if (!_failed.remove(localized)) return;
                                  setState(() {});
                                  await _provider(localized).evict();
                                  if (!mounted) return;
                                  setState(() => _queued.remove(localized));
                                },
                                child: const Text('Riprova immagine')),
                          ])
                        : Text('Caricamento scansione in $label…',
                            style: const TextStyle(fontSize: 11)))),
          if (ownership?.known == true &&
              label != null &&
              code != 'EN' &&
              localized == null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Scansione in $label non fornita dall’API; immagine del catalogo.',
                    style: const TextStyle(fontSize: 11))),
        ]);
      });

  // Kept separate from image warming: selection remains the shared read-only action.
  void _select(String language) => widget.onLanguageSelected?.call(language);
}
