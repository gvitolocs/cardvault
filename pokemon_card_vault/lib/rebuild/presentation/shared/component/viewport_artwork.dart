import 'package:flutter/material.dart';

/// Delay image/provider creation until the outer viewport sees the album sleeve.
class ViewportArtwork extends StatefulWidget {
  const ViewportArtwork(
      {super.key,
      required this.position,
      required this.builder,
      this.pageChanges});
  final ScrollPosition position;
  final Listenable? pageChanges;
  final WidgetBuilder builder;
  @override
  State<ViewportArtwork> createState() => _ViewportArtworkState();
}

class _ViewportArtworkState extends State<ViewportArtwork> {
  bool _visible = false, _scheduled = false;
  @override
  void initState() {
    super.initState();
    _listen();
    _schedule();
  }

  void _listen() {
    widget.position.addListener(_schedule);
    widget.pageChanges?.addListener(_schedule);
  }

  void _unlisten(ViewportArtwork target) {
    target.position.removeListener(_schedule);
    target.pageChanges?.removeListener(_schedule);
  }

  @override
  void didUpdateWidget(ViewportArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unlisten(oldWidget);
    _listen();
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  void _schedule() {
    if (_visible || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _visible) return;
      final image = context.findRenderObject();
      final viewport =
          widget.position.context.notificationContext?.findRenderObject();
      if (image is! RenderBox ||
          viewport is! RenderBox ||
          !image.hasSize ||
          !viewport.hasSize ||
          !image.attached ||
          !viewport.attached) {
        return;
      }
      final bounds = image.localToGlobal(Offset.zero) & image.size;
      final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
      if (bounds.overlaps(visible)) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) => _visible
      ? widget.builder(context)
      : const Center(child: Icon(Icons.style_outlined, size: 40));
  @override
  void dispose() {
    _unlisten(widget);
    super.dispose();
  }
}
