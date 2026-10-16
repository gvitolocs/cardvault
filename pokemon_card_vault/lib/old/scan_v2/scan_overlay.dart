import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'scan_engine.dart';

({double scale, double dx, double dy}) _fitTransform({
  required Size imageSize,
  required Size viewSize,
  required BoxFit fit,
}) {
  final sx = viewSize.width / imageSize.width;
  final sy = viewSize.height / imageSize.height;
  final scale = fit == BoxFit.cover ? math.max(sx, sy) : math.min(sx, sy);
  final dx = (viewSize.width - imageSize.width * scale) / 2;
  final dy = (viewSize.height - imageSize.height * scale) / 2;
  return (scale: scale, dx: dx, dy: dy);
}

/// Maps a rect from the camera/JPEG image onto a preview that shows the
/// whole sensor (BoxFit.contain — no crop).
Rect mapImageRectToContain({
  required Rect imageRect,
  required Size imageSize,
  required Size viewSize,
}) {
  return mapImageRectToFit(
    imageRect: imageRect,
    imageSize: imageSize,
    viewSize: viewSize,
    fit: BoxFit.contain,
  );
}

Rect mapImageRectToFit({
  required Rect imageRect,
  required Size imageSize,
  required Size viewSize,
  required BoxFit fit,
}) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      viewSize.width <= 0 ||
      viewSize.height <= 0) {
    return Rect.zero;
  }
  final t = _fitTransform(imageSize: imageSize, viewSize: viewSize, fit: fit);
  return Rect.fromLTRB(
    imageRect.left * t.scale + t.dx,
    imageRect.top * t.scale + t.dy,
    imageRect.right * t.scale + t.dx,
    imageRect.bottom * t.scale + t.dy,
  );
}

Offset mapImagePointToContain({
  required Offset imagePoint,
  required Size imageSize,
  required Size viewSize,
}) {
  return mapImagePointToFit(
    imagePoint: imagePoint,
    imageSize: imageSize,
    viewSize: viewSize,
    fit: BoxFit.contain,
  );
}

Offset mapImagePointToFit({
  required Offset imagePoint,
  required Size imageSize,
  required Size viewSize,
  required BoxFit fit,
}) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      viewSize.width <= 0 ||
      viewSize.height <= 0) {
    return Offset.zero;
  }
  final t = _fitTransform(imageSize: imageSize, viewSize: viewSize, fit: fit);
  return Offset(imagePoint.dx * t.scale + t.dx, imagePoint.dy * t.scale + t.dy);
}

class LiveCardBoxesPainter extends CustomPainter {
  LiveCardBoxesPainter({
    required this.boxes,
    required this.imageSize,
    required this.pulse,
    this.fit = BoxFit.contain,
  });

  final List<ScanBox> boxes;
  final Size imageSize;
  final double pulse;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty || imageSize.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFFFACC15).withValues(alpha: 0.7 + pulse * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final box in boxes) {
      final corners = box.corners;
      if (corners.length < 8) continue;
      final path = Path();
      for (var i = 0; i < 4; i++) {
        final mapped = mapImagePointToFit(
          imagePoint: Offset(corners[i * 2], corners[i * 2 + 1]),
          imageSize: imageSize,
          viewSize: size,
          fit: fit,
        );
        if (i == 0) {
          path.moveTo(mapped.dx, mapped.dy);
        } else {
          path.lineTo(mapped.dx, mapped.dy);
        }
      }
      path.close();
      final bounds = path.getBounds();
      if (bounds.width < 8 || bounds.height < 8) continue;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(LiveCardBoxesPainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.boxes != boxes ||
        oldDelegate.fit != fit;
  }
}
