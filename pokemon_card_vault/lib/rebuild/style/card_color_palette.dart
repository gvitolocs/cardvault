import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Colore del riquadro testuale stampato, evitando bordo e illustrazione.
abstract final class CardColorPalette {
  static Future<Color?> fromImage(ui.Image image) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return null;
    return fromRgba(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        image.width,
        image.height);
  }

  static Color? fromRgba(Uint8List bytes, int width, int height) {
    if (width < 1 || height < 1 || bytes.length < width * height * 4) {
      return null;
    }
    final bins = <int, _ColorBin>{};
    // La zona 55–86% copre il fondo di attacchi/abilità, non il disegno superiore.
    for (var row = 0; row < 32; row++) {
      final y = (height * (.55 + .31 * row / 31)).floor().clamp(0, height - 1);
      for (var column = 0; column < 32; column++) {
        final x =
            (width * (.10 + .80 * column / 31)).floor().clamp(0, width - 1);
        final offset = (y * width + x) * 4;
        if (bytes[offset + 3] < 200) continue;
        final color = Color.fromARGB(
            255, bytes[offset], bytes[offset + 1], bytes[offset + 2]);
        final hsv = HSVColor.fromColor(color);
        // Ignora le lettere nere; il bianco può essere il fondo della carta.
        if (hsv.value < .18) {
          continue;
        }
        final key = (hsv.hue / 20).floor() * 100 +
            (hsv.saturation * 4).floor() * 10 +
            (hsv.value * 5).floor();
        (bins[key] ??= _ColorBin())
            .add(bytes[offset], bytes[offset + 1], bytes[offset + 2]);
      }
    }
    if (bins.isEmpty) return null;
    final dominant = bins.values.reduce((a, b) => a.count >= b.count ? a : b);
    return dominant.color;
  }
}

class _ColorBin {
  int count = 0, red = 0, green = 0, blue = 0;
  void add(int r, int g, int b) {
    count++;
    red += r;
    green += g;
    blue += b;
  }

  Color get color => Color.fromARGB(255, (red / count).round(),
      (green / count).round(), (blue / count).round());
}
