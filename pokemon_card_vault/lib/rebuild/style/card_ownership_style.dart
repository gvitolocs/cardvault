import 'package:flutter/material.dart';

abstract final class CardOwnershipStyle {
  static const background = Color(0xE6222A32);
  static const owned = Color(0xFFE9FF72);
  static const sleeve = Color(0xFF242C3B);
  static const missing = Color(0xFF909090);
  static const flagText = TextStyle(
      fontSize: 20, fontFamilyFallback: ['Noto Color Emoji', 'Segoe UI Emoji']);
  static const grayscale = ColorFilter.matrix([
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
}
