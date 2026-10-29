import 'package:flutter/material.dart';
import '../../../controller/collection_artwork_controller.dart';

/// Mounted only inside the visible artwork builder, not for an entire album.
class CollectionCardArtwork extends StatefulWidget {
  const CollectionCardArtwork(
      {super.key,
      required this.controller,
      required this.cardId,
      required this.language,
      required this.fallbackUrl,
      required this.imageBuilder});
  final CollectionArtworkController controller;
  final String cardId, language, fallbackUrl;
  final Widget Function(String url, VoidCallback? onError) imageBuilder;
  @override
  State<CollectionCardArtwork> createState() => _CollectionCardArtworkState();
}

class _CollectionCardArtworkState extends State<CollectionCardArtwork> {
  VoidCallback? _release;
  final _failedImages = <String>{};
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _acquire();
  }

  void _acquire() {
    if (widget.language != 'EN') {
      _release = widget.controller.acquire(widget.cardId);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CollectionCardArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.cardId != widget.cardId ||
        oldWidget.language != widget.language) {
      oldWidget.controller.removeListener(_changed);
      _release?.call();
      _release = null;
      widget.controller.addListener(_changed);
      _acquire();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final english = widget.language == 'EN';
    final ready = controller.preferenceReady &&
        (english || controller.resolved(widget.cardId));
    if (!ready) {
      return Center(
          child: Semantics(
              label: 'Caricamento immagine nella lingua scelta',
              child: const Icon(Icons.style_outlined, size: 40)));
    }
    final localized = controller
        .metadataFor(widget.cardId)
        ?.languageImageUrls[widget.language];
    final failed = localized != null && _failedImages.contains(localized);
    final fallback = !english && (localized == null || failed);
    return Stack(fit: StackFit.expand, children: [
      widget.imageBuilder(
          english || fallback ? widget.fallbackUrl : localized!,
          localized == null || fallback
              ? null
              : () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _failedImages.add(localized)) {
                      setState(() {});
                    }
                  });
                  WidgetsBinding.instance.ensureVisualUpdate();
                }),
      if (fallback)
        Positioned(
            left: 3,
            top: 3,
            child: Tooltip(
                message:
                    'Scansione ${widget.language} non disponibile; immagine del catalogo.',
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text('Catalogo',
                            style: TextStyle(
                                color: Colors.white, fontSize: 9)))))),
    ]);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _release?.call();
    super.dispose();
  }
}
