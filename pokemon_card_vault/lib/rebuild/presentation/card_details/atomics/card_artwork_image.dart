import 'dart:async';
import 'package:flutter/material.dart';
import '../../../style/card_color_palette.dart';

/// La foto e il campionamento condividono lo stesso ImageProvider/cache Flutter.
class CardArtworkImage extends StatefulWidget {
  const CardArtworkImage(
      {super.key, required this.image, required this.onColor});
  final ImageProvider image;
  final ValueChanged<Color> onColor;

  @override
  State<CardArtworkImage> createState() => _CardArtworkImageState();
}

class _CardArtworkImageState extends State<CardArtworkImage> {
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage, onError: (_, __) {});
  int _generation = 0;
  bool _sampled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(CardArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _resolve();
  }

  void _resolve() {
    final next = widget.image.resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _generation++;
    _sampled = false;
    _stream = next..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronous) {
    if (_sampled) {
      info.dispose();
      return;
    }
    _sampled = true;
    unawaited(_sample(info, _generation));
  }

  Future<void> _sample(ImageInfo info, int generation) async {
    try {
      final color = await CardColorPalette.fromImage(info.image);
      if (color == null || !mounted || generation != _generation) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) widget.onColor(color);
      });
      // Garantisce il callback anche quando l'immagine era già in cache.
      WidgetsBinding.instance.ensureVisualUpdate();
    } catch (_) {
      // Foto non leggibile: resta la palette di attesa della pagina.
    } finally {
      info.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
      image: widget.image,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.style_outlined, size: 40)));
}
