import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../style/card_color_palette.dart';

/// Copia soltanto la miniatura già dipinta, senza scaricare un'altra immagine.
class CardPaletteSnapshot extends StatefulWidget {
  const CardPaletteSnapshot(
      {super.key,
      required this.thumbnail,
      required this.builder,
      required this.onSelected,
      this.enabled = true});
  final Widget thumbnail;
  final bool enabled;
  final ValueChanged<Color?> onSelected;
  final Widget Function(
      BuildContext context, Widget thumbnail, VoidCallback onTap) builder;

  @override
  State<CardPaletteSnapshot> createState() => _CardPaletteSnapshotState();
}

class _CardPaletteSnapshotState extends State<CardPaletteSnapshot> {
  final _boundary = GlobalKey();
  bool _capturing = false;

  bool _hasLoadedImage(RenderObject node) {
    if (node is RenderImage && node.image != null) return true;
    var loaded = false;
    node.visitChildren((child) {
      loaded = loaded || _hasLoadedImage(child);
    });
    return loaded;
  }

  Future<void> _select() async {
    if (_capturing) return;
    if (!widget.enabled) {
      widget.onSelected(null);
      return;
    }
    _capturing = true;
    Color? color;
    try {
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary &&
          boundary.hasSize &&
          _hasLoadedImage(boundary)) {
        final snapshot = await boundary.toImage(pixelRatio: 1);
        try {
          color = await CardColorPalette.fromImage(snapshot);
        } finally {
          snapshot.dispose();
        }
      }
    } catch (_) {
      // Miniatura non pronta: la pagina può ricavare il colore dalla foto caricata.
    } finally {
      _capturing = false;
    }
    if (mounted) widget.onSelected(color);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context,
      RepaintBoundary(key: _boundary, child: widget.thumbnail), _select);
}
